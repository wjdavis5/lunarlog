-- Coverage for Issue #188 (P1, epic: Modes): public.profile_modes and
-- public.cycle_overrides -- schema shape (RLS, policies, grants, indexes,
-- triggers), the issue's write ladder (any accepted guardian reads; only
-- primary_guardian/co_parent writes; caregiver/viewer rejected), the
-- sync_push round trip through p_profile_modes/p_cycle_overrides
-- (including old-client key-omission safety and older-arity calls), the
-- mode-switch-never-touches-day_entries/observations guarantee, tombstone
-- payload clearing on cycle_overrides, and delete_account_data()'s new
-- counts. Fixture style: observations_test.sql / guardian_sync_push_test.sql.
begin;
select plan(85);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.resolved_row(n text, p_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'id' = p_id limit 1 $$;
create function pg_temp.resolved_mode_row(n text, p_profile_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'profile_id' = p_profile_id limit 1 $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape: tables, RLS, policies, grants, indexes, triggers.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'profile_modes');
select tests.rls_forced('public', 'profile_modes');
select tests.rls_enabled('public', 'cycle_overrides');
select tests.rls_forced('public', 'cycle_overrides');

select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'profile_modes'),
  3, 'profile_modes carries exactly the three documented policies (select, insert, update)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'profile_modes' and roles <> '{authenticated}'),
  0, 'every profile_modes policy is scoped to authenticated');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'profile_modes' and cmd = 'DELETE'),
  0, 'profile_modes has no DELETE policy (the row dies with its profile via cascade)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'cycle_overrides'),
  3, 'cycle_overrides carries exactly the three documented policies (select, insert, update)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'cycle_overrides' and roles <> '{authenticated}'),
  0, 'every cycle_overrides policy is scoped to authenticated');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'cycle_overrides' and cmd = 'DELETE'),
  0, 'cycle_overrides has no DELETE policy (tombstone-only, matching every other synced table)');

select is(
  (select has_table_privilege('authenticated', 'public.profile_modes', 'DELETE')),
  false, 'authenticated holds no DELETE grant on profile_modes');
select is(
  (select has_table_privilege('authenticated', 'public.cycle_overrides', 'DELETE')),
  false, 'authenticated holds no DELETE grant on cycle_overrides');
select is(
  (select has_table_privilege('anon', 'public.profile_modes', 'SELECT')),
  false, 'anon holds no SELECT grant on profile_modes');
select is(
  (select has_table_privilege('anon', 'public.cycle_overrides', 'SELECT')),
  false, 'anon holds no SELECT grant on cycle_overrides');
select is(
  (select has_column_privilege('authenticated', 'public.profile_modes', 'server_version', 'UPDATE')),
  false, 'server_version is not client-updatable on profile_modes');

select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'profile_modes'
      and indexname = 'profile_modes_server_version_idx'),
  1, 'profile_modes pull-path index (server_version) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'cycle_overrides'
      and indexname = 'cycle_overrides_server_version_idx'),
  1, 'cycle_overrides pull-path index (server_version) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'cycle_overrides'
      and indexname = 'cycle_overrides_profile_id_cycle_start_date_idx'),
  1, 'cycle_overrides read-path index (profile_id, cycle_start_date) exists');

select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'profile_modes' and t.tgname = 'profile_modes_set_server_version'),
  1, 'profile_modes stamps server_version via the shared trigger');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'cycle_overrides' and t.tgname = 'cycle_overrides_set_server_version'),
  1, 'cycle_overrides stamps server_version via the shared trigger');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'profile_modes' and t.tgname = 'profile_modes_after_change_signal'),
  1, 'profile_modes fires touch_sync_signal() -- rides the existing wake signal');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'cycle_overrides' and t.tgname = 'cycle_overrides_after_change_signal'),
  1, 'cycle_overrides fires touch_sync_signal() -- rides the existing wake signal');
select is(
  (select count(*)::integer from pg_publication_rel pr
     join pg_class c on c.oid = pr.prrelid
     join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and c.relname in ('profile_modes', 'cycle_overrides')),
  0, 'neither new table is in the supabase_realtime publication');

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) with dad (co_parent), nanny (caregiver),
-- doc (viewer) on one profile; a second family (other_parent); eve a
-- stranger. Mom's profile carries a day entry and an observation so the
-- mode-switch safety assertion below has payload to prove untouched.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('nanny');
select tests.create_supabase_user('doc');
select tests.create_supabase_user('eve');
select tests.create_supabase_user('other_parent');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(801), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(802), tests.ulid(801), '2026-09-05', 'UTC', 'medium', '2026-09-05T09:00:00Z');
insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
values (tests.ulid(803), tests.ulid(802), tests.ulid(801), '2026-09-05', 'UTC', 'pain', 'cramps', '2026-09-05T09:00:00Z');

-- Mom (primary_guardian) mints the three invitations -- only primary can
-- mint a co_parent one (guardian_sync_push_test.sql's ladder).
select public.create_guardian_invitation(tests.ulid(801), 'co_parent', 'Dad',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 48);
select public.create_guardian_invitation(tests.ulid(801), 'caregiver', 'Nanny',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 48);
select public.create_guardian_invitation(tests.ulid(801), 'viewer', 'Doc',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 48);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Dad');
select tests.authenticate_as('nanny');
select public.accept_guardian_invitation(
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Nanny');
select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'Doc');

select tests.authenticate_as('other_parent');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(851), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Round trip (mom, primary_guardian): a full profile_modes row and a full
-- cycle_overrides row through the new parameters.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_mode_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'perimenopause',
    'mode_started_on', '2026-09-02',
    'birth_control_method', 'copper_iud',
    'birth_control_started_on', '2026-01-10',
    'birth_control_stopped_on', '2026-08-01',
    'health_sync_consent', true,
    'updated_at', '2026-09-02T10:00:00Z')),
  '[]'::jsonb);

select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'perimenopause',
  'round trip: mode persisted');
select is((select mode_started_on from public.profile_modes where profile_id = tests.ulid(801)), '2026-09-02'::date,
  'round trip: mode_started_on persisted');
select is((select birth_control_method from public.profile_modes where profile_id = tests.ulid(801)), 'copper_iud',
  'round trip: birth_control_method persisted');
select is((select health_sync_consent from public.profile_modes where profile_id = tests.ulid(801)), true,
  'round trip: health_sync_consent persisted');
select isnt((select server_version from public.profile_modes where profile_id = tests.ulid(801)), 0::bigint,
  'round trip: profile_modes server_version stamped by the shared trigger');

insert into r select 'mom_override_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(804), 'profile_id', tests.ulid(801),
    'cycle_start_date', '2026-08-14',
    'excluded_from_average', true, 'manual_start', true,
    'note_id', 'note-1',
    'updated_at', '2026-09-02T10:30:00Z')));

select is((select cycle_start_date from public.cycle_overrides where id = tests.ulid(804)), '2026-08-14'::date,
  'round trip: cycle_start_date persisted');
select is((select excluded_from_average from public.cycle_overrides where id = tests.ulid(804)), true,
  'round trip: excluded_from_average persisted');
select is((select manual_start from public.cycle_overrides where id = tests.ulid(804)), true,
  'round trip: manual_start persisted');
select isnt((select server_version from public.cycle_overrides where id = tests.ulid(804)), 0::bigint,
  'round trip: cycle_overrides server_version stamped by the shared trigger');

-- Older-arity calls keep working: the 3-arg (pre-#188 tip) and 2-arg
-- (pre-#240) forms resolve to the one 5-arg body with '[]' defaults.
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb)$$,
  'a 3-argument sync_push call still works (both new params default)');
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb)$$,
  'a 2-argument sync_push call still works');

-- ---------------------------------------------------------------------------
-- Write ladder: co_parent accepted; caregiver/viewer/stranger rejected in
-- the RPC (opaque rejected entries, the day_entries precedent) and by RLS
-- on a direct write.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'dad_mode_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'pregnancy',
    'updated_at', '2026-09-03T10:00:00Z')),
  '[]'::jsonb);
select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'pregnancy',
  'write ladder: co_parent can switch the mode');

select tests.authenticate_as('nanny');
insert into r select 'nanny_mode_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'updated_at', '2026-09-03T11:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('nanny_mode_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'write ladder: a caregiver''s mode push is an opaque rejected entry');
select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'pregnancy',
  'write ladder: the caregiver''s push changed nothing');

insert into r select 'nanny_override_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(805), 'profile_id', tests.ulid(801),
    'cycle_start_date', '2026-09-01', 'manual_start', true,
    'updated_at', '2026-09-03T11:30:00Z')));
select is(
  (select count(*) from public.cycle_overrides where id = tests.ulid(805)),
  0::bigint, 'write ladder: a caregiver''s cycle-override push was never stored');

-- Direct PostgREST-shape writes fail RLS for a caregiver (42501).
select throws_ok(
  format('insert into public.profile_modes (profile_id, mode, updated_at) values (%L, %L, now())',
    tests.ulid(801), 'tracking'),
  '42501', null,
  'write ladder: a caregiver''s direct profile_modes INSERT fails RLS');
select throws_ok(
  format($sql$insert into public.cycle_overrides
           (id, profile_id, cycle_start_date, manual_start, updated_at)
         values (%L, %L, '2026-09-01', true, now())$sql$,
    tests.ulid(806), tests.ulid(801)),
  '42501', null,
  'write ladder: a caregiver''s direct cycle_overrides INSERT fails RLS');

-- A caregiver's direct UPDATE is a silent zero-row update, not an error:
-- the RLS UPDATE policy's USING clause filters the row out before the WITH
-- CHECK ever evaluates (Postgres raises 42501 only when a row passes USING
-- and the new version violates WITH CHECK). Pin the semantics the client
-- actually sees: the row is untouched.
update public.profile_modes set mode = 'tracking' where profile_id = tests.ulid(801);
select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'pregnancy',
  'write ladder: a caregiver''s direct profile_modes UPDATE is a silent zero-row no-op');

select tests.authenticate_as('doc');
insert into r select 'doc_mode_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'updated_at', '2026-09-03T12:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('doc_mode_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'write ladder: a viewer''s mode push is an opaque rejected entry');

-- Reads: any accepted guardian (caregiver/viewer included) reads both
-- tables; strangers and other families see nothing.
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  1::bigint, 'read ladder: the caregiver (accepted guardian) can read profile_modes');
select is((select count(*) from public.cycle_overrides where profile_id = tests.ulid(801)),
  1::bigint, 'read ladder: the viewer (accepted guardian) can read cycle_overrides');

select tests.authenticate_as('eve');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  0::bigint, 'a stranger sees zero of mom''s profile_modes rows');
select is((select count(*) from public.cycle_overrides where profile_id = tests.ulid(801)),
  0::bigint, 'a stranger sees zero of mom''s cycle_overrides rows');

select tests.authenticate_as('other_parent');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  0::bigint, 'the other family sees zero of mom''s profile_modes rows');

-- ---------------------------------------------------------------------------
-- Mode-switch safety (A2-32): switching mode touches neither day_entries
-- nor observations -- only profile_modes.mode/mode_started_on change, and
-- a repeated switch is idempotent (one row, declined-with-server-copy).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
create temp table day_state as
  select count(*) as n, max(updated_at) as last_update from public.day_entries where profile_id = tests.ulid(801);
create temp table obs_state as
  select count(*) as n, max(updated_at) as last_update from public.observations where profile_id = tests.ulid(801);

insert into r select 'mom_mode_switch', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'conceive',
    'mode_started_on', '2026-09-04',
    'updated_at', '2026-09-04T08:00:00Z')),
  '[]'::jsonb);

select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'conceive',
  'mode switch applied');
select is((select mode_started_on from public.profile_modes where profile_id = tests.ulid(801)), '2026-09-04'::date,
  'mode_started_on moved with the switch');
select is(
  (select (select n from day_state) = (select count(*) from public.day_entries where profile_id = tests.ulid(801))
      and (select last_update from day_state) = (select max(updated_at) from public.day_entries where profile_id = tests.ulid(801))),
  true, 'a mode switch never touches day_entries (count and updated_at unchanged)');
select is(
  (select (select n from obs_state) = (select count(*) from public.observations where profile_id = tests.ulid(801))
      and (select last_update from obs_state) = (select max(updated_at) from public.observations where profile_id = tests.ulid(801))),
  true, 'a mode switch never touches observations (count and updated_at unchanged)');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  1::bigint, 'a mode switch never duplicates the one-row-per-profile row');

-- Idempotence: re-pushing the exact same row (same updated_at) is
-- declined with the server copy handed back -- not stored twice, not
-- half-updated, and still no day_entries churn.
insert into r select 'mom_mode_retry', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'conceive',
    'mode_started_on', '2026-09-04',
    'updated_at', '2026-09-04T08:00:00Z')),
  '[]'::jsonb);
select is((select jsonb_array_length(pg_temp.resp('mom_mode_retry') -> 'resolved')), 1,
  'an equal-timestamp re-push is declined with the server copy resolved back');
select is(pg_temp.resolved_mode_row('mom_mode_retry', tests.ulid(801)) ->> 'mode', 'conceive',
  'the declined server copy names its table (profile_modes) and row');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  1::bigint, 'the retry did not store a second row');

-- An OLDER push is likewise declined (strict LWW).
insert into r select 'mom_mode_older', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'updated_at', '2026-09-03T09:59:00Z')),
  '[]'::jsonb);
select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'conceive',
  'an older mode push is declined and the stored row is untouched');

-- ---------------------------------------------------------------------------
-- Old-client omission safety: a newer push that omits the birth-control
-- and consent keys preserves the stored values (the containment-guard
-- pattern); health_sync_consent is independently settable.
-- ---------------------------------------------------------------------------
insert into r select 'mom_bc_set', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801),
    'birth_control_method', 'pill',
    'birth_control_started_on', '2026-09-01',
    'health_sync_consent', true,
    'updated_at', '2026-09-05T08:00:00Z')),
  '[]'::jsonb);
select is((select birth_control_method from public.profile_modes where profile_id = tests.ulid(801)), 'pill',
  'birth-control state stored');

insert into r select 'mom_older_client_edit', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'mode_started_on', '2026-09-06',
    -- a pre-birth-control client sends only mode fields: no
    -- birth_control_* key, no health_sync_consent key
    'updated_at', '2026-09-06T08:00:00Z')),
  '[]'::jsonb);
select is((select mode from public.profile_modes where profile_id = tests.ulid(801)), 'tracking',
  'the newer edit applied its own keys');
select is((select birth_control_method from public.profile_modes where profile_id = tests.ulid(801)), 'pill',
  'an old client omitting birth_control_method never nulls the stored value');
select is((select birth_control_started_on from public.profile_modes where profile_id = tests.ulid(801)), '2026-09-01'::date,
  'an old client omitting birth_control_started_on never nulls the stored value');
select is((select health_sync_consent from public.profile_modes where profile_id = tests.ulid(801)), true,
  'an old client omitting health_sync_consent never resets it to false');

insert into r select 'mom_consent_off', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'health_sync_consent', false,
    'updated_at', '2026-09-06T09:00:00Z')),
  '[]'::jsonb);
select is((select health_sync_consent from public.profile_modes where profile_id = tests.ulid(801)), false,
  'health_sync_consent is independently settable (D-29: distinct from cycle-sharing consent)');

-- ---------------------------------------------------------------------------
-- CHECK enforcement and payload validation.
-- ---------------------------------------------------------------------------
insert into r select 'mom_bad_mode', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'perimenopaus',
    'updated_at', '2026-09-06T10:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_bad_mode') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'an out-of-set mode is an opaque rejected entry (profile_modes_mode_check)');

insert into r select 'mom_long_method', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'birth_control_method', repeat('x', 65),
    'updated_at', '2026-09-06T10:01:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_long_method') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'an over-length birth_control_method is an opaque rejected entry');

insert into r select 'mom_bad_date', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'mode_started_on', '09/06/2026',
    'updated_at', '2026-09-06T10:02:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_bad_date') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'a non-ISO mode_started_on is an opaque rejected entry');

insert into r select 'mom_unknown_key', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking', 'foo', 1,
    'updated_at', '2026-09-06T10:03:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_unknown_key') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(801), 'rejected', true),
  'an unknown key is an opaque rejected entry');

insert into r select 'mom_missing_profile', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(999), 'mode', 'tracking',
    'updated_at', '2026-09-06T10:04:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_missing_profile') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(999), 'rejected', true),
  'a profile_modes row for a nonexistent profile is an opaque rejected entry');

insert into r select 'mom_bad_override_id', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', 'not-a-ulid-at-all-abcdefghij', 'profile_id', tests.ulid(801),
    'cycle_start_date', '2026-09-01',
    'updated_at', '2026-09-06T10:05:00Z')));
select is(
  pg_temp.resp('mom_bad_override_id') -> 'rejected' -> 0,
  jsonb_build_object('id', 'not-a-ulid-at-all-abcdefghij', 'rejected', true),
  'a non-ULID cycle_overrides id is an opaque rejected entry');

-- ---------------------------------------------------------------------------
-- cycle_overrides: LWW decline + tombstone payload clearing + structural
-- backstop.
-- ---------------------------------------------------------------------------
insert into r select 'mom_override_older', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(804), 'profile_id', tests.ulid(801),
    'cycle_start_date', '2026-08-14', 'excluded_from_average', false,
    'updated_at', '2026-09-01T00:00:00Z')));
select is((select jsonb_array_length(pg_temp.resp('mom_override_older') -> 'resolved')), 1,
  'an older cycle_overrides push is declined with the server copy resolved back');
select is(pg_temp.resolved_row('mom_override_older', tests.ulid(804)) ->> 'table', 'cycle_overrides',
  'the declined override copy names its table');
select is((select excluded_from_average from public.cycle_overrides where id = tests.ulid(804)), true,
  'the declined push left the stored override untouched');

insert into r select 'mom_override_tombstone', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(804), 'profile_id', tests.ulid(801),
    'cycle_start_date', '2026-08-14',
    'deleted_at', '2026-09-06T11:00:00Z',
    'updated_at', '2026-09-06T11:00:00Z')));
select is((select excluded_from_average from public.cycle_overrides where id = tests.ulid(804)), false,
  'a cycle_overrides tombstone clears excluded_from_average');
select is((select manual_start from public.cycle_overrides where id = tests.ulid(804)), false,
  'a cycle_overrides tombstone clears manual_start');
select is((select note_id from public.cycle_overrides where id = tests.ulid(804)), null,
  'a cycle_overrides tombstone clears note_id');
select is((select cycle_start_date from public.cycle_overrides where id = tests.ulid(804)), '2026-08-14'::date,
  'a cycle_overrides tombstone keeps cycle_start_date (identity)');
select isnt((select deleted_at from public.cycle_overrides where id = tests.ulid(804)), null,
  'a cycle_overrides tombstone sets deleted_at');

-- Structural backstop: the table CHECK rejects a direct write that
-- reintroduces payload onto the tombstone, independent of sync_push.
select throws_ok(
  format('update public.cycle_overrides set note_id = %L where id = %L and profile_id = %L',
    'x', tests.ulid(804), tests.ulid(801)),
  '23514', null,
  'the tombstone-payload CHECK rejects reintroducing note_id onto a tombstone');

-- ---------------------------------------------------------------------------
-- Per-array cap: 501 profile_modes rows raises 22023 (the RPC's own
-- pre-loop guard, same as the other three arrays).
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
    (select jsonb_agg(jsonb_build_object('profile_id', tests.ulid(g), 'mode', 'tracking',
      'updated_at', '2026-09-06T00:00:00Z'))
       from generate_series(1200, 1700) g),
    '[]'::jsonb)$$,
  '22023', null, 'p_profile_modes over 500 rows is rejected');

-- ---------------------------------------------------------------------------
-- delete_account_data(): the two new counts, scoped to owned profiles; a
-- shared (non-owned) profile's rows are another family's and survive a
-- caregiver's deletion. Run last -- it deletes mom's own data.
-- ---------------------------------------------------------------------------
-- Dad (co_parent on mom's profile, owner of nothing) deletes his account:
-- mom's profile_modes/cycle_overrides rows must survive, and his counts
-- are zero.
select tests.authenticate_as('dad');
insert into r select 'dad_delete', public.delete_account_data();
select is((select (v ->> 'profile_modes')::integer from r where name = 'dad_delete'), 0,
  'delete_account_data: a co_parent deleting their account reports zero owned profile_modes rows');
select is((select (v ->> 'cycle_overrides')::integer from r where name = 'dad_delete'), 0,
  'delete_account_data: a co_parent deleting their account reports zero owned cycle_overrides rows');
-- Dad's own deletion removed his membership, so HE can no longer read the
-- shared profile's rows at all (RLS) -- re-authenticate as mom (still the
-- primary guardian) for the survival assertion.
select tests.authenticate_as('mom');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  1::bigint, 'delete_account_data: the shared profile''s mode row survives a co_parent''s deletion');

-- Mom (owner) deletes her account: both new counts report her rows.
select tests.authenticate_as('mom');
insert into r select 'mom_delete', public.delete_account_data();
select is((select (v ->> 'profile_modes')::integer from r where name = 'mom_delete'), 1,
  'delete_account_data: the owner''s profile_modes row is counted');
select is((select (v ->> 'cycle_overrides')::integer from r where name = 'mom_delete'), 1,
  'delete_account_data: the owner''s cycle_overrides row is counted');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(801)),
  0::bigint, 'delete_account_data: the owner''s profile_modes row is gone');
select is((select count(*) from public.cycle_overrides where profile_id = tests.ulid(801)),
  0::bigint, 'delete_account_data: the owner''s cycle_overrides row is gone');

select * from finish();
