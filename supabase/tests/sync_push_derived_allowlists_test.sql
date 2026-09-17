-- Issue #181: sync_push's nine per-table key allowlists are DERIVED from
-- information_schema.columns (public.sync_push_payload_keys, materialized
-- into the function body at CREATE time by
-- 20260917120000_sync_push_derived_allowlists.sql), not hand-restated
-- literals. This file pins every leg of that contract:
--
--   1. The derivation model itself: for each synced table,
--      sync_push_payload_keys(t) == columns(t) - ignored(t) + extras(t),
--      with ignored/extras restated here as literals so they cannot
--      silently grow or shrink.
--   2. The live function matches the derivation: the arrays embedded in
--      the live sync_push body equal sync_push_payload_keys(t) for every
--      table. This is the exact birth_year/relationship regression class
--      (the issue's citation): a later migration that adds a column to a
--      synced table changes columns(t) and therefore
--      sync_push_payload_keys(t), and this comparison FAILS until
--      sync_push is re-emitted through the derivation -- the column can
--      never again be silently un-syncable.
--   3. The issue's literal AC: every column with an `authenticated` write
--      grant (INSERT or UPDATE, via information_schema.column_privileges)
--      on each synced table appears in the live embedded allowlist, aside
--      from the documented server-stamped columns (which sync_push must
--      never accept, because it stamps them from the caller -- pinned by
--      care_notes_visit_prep_test.sql's AC3). For profiles and
--      day_entries -- the tables the AC names -- the ignored set is empty,
--      so the strict form holds there.
--   4. Behavior: a profiles row carrying EVERY derived key is accepted;
--      the legacy 'user_id' extra is still tolerated on a care note; the
--      server-stamped columns (day_entries.created_at,
--      profile_tag_registry.created_by) are still rejected as unknown
--      keys, each with a positive control.
--   5. The helper is migration/test tooling, not a client API: EXECUTE is
--      denied to anon and authenticated.
begin;
select plan(38);

-- ---------------------------------------------------------------------------
-- temp helpers
-- ---------------------------------------------------------------------------

create function pg_temp.columns_of(p_table text) returns text[]
language sql as $f$
  select coalesce(array(
    select c.column_name::text
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = p_table
     order by c.column_name::text
  ), '{}'::text[])
$f$;

create function pg_temp.expected_keys(p_table text, p_ignored text[], p_extras text[]) returns text[]
language sql as $f$
  select coalesce(array(
    select c.column_name::text
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = p_table
       and c.column_name::text <> all (coalesce(p_ignored, '{}'::text[]))
     order by c.column_name::text
  ), '{}'::text[])
  || coalesce(p_extras, '{}'::text[])
$f$;

create function pg_temp.granted_writable(p_table text) returns text[]
language sql as $f$
  select coalesce(array(
    select distinct cp.column_name::text
      from information_schema.column_privileges cp
     where cp.table_schema = 'public'
       and cp.table_name = p_table
       and cp.grantee = 'authenticated'
       and cp.privilege_type in ('INSERT', 'UPDATE')
     order by cp.column_name::text
  ), '{}'::text[])
$f$;

-- The live function's embedded allowlist: the single-line canonical
-- declaration form written by 20260917120000's DO block, regex-extracted
-- from pg_proc (the body text IS what runs, so this reads the actual
-- accepted-key set, not a copy of it).
create function pg_temp.embedded_keys(p_const text) returns text[]
language plpgsql as $f$
declare
  v_src text;
  v_body text;
begin
  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sync_push';

  v_body := substring(v_src from p_const
    || '[[:space:]]+constant[[:space:]]+text\[\][[:space:]]*:=[[:space:]]*''\{([a-z_,]+)\}');
  if v_body is null then
    raise exception 'could not extract % from the live sync_push body (canonical embedded form missing)', p_const;
  end if;
  return string_to_array(v_body, ',');
end;
$f$;

create function pg_temp.sorted(p_arr text[]) returns text[]
language sql as $f$
  select coalesce(array(select unnest(p_arr) order by 1), '{}'::text[])
$f$;

-- ---------------------------------------------------------------------------
-- 1. The derivation model, pinned per table (ignored = server-stamped
--    columns removed from the allowlist; extras = legacy tolerated keys
--    that are not columns of the table).
-- ---------------------------------------------------------------------------

select is(
  pg_temp.sorted(public.sync_push_payload_keys('profiles')),
  pg_temp.sorted(pg_temp.expected_keys('profiles', '{}'::text[], '{}'::text[])),
  'model: profiles = every column, nothing ignored');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('day_entries')),
  pg_temp.sorted(pg_temp.expected_keys('day_entries', array['created_at'], '{}'::text[])),
  'model: day_entries = every column minus created_at (server-stamped)');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('observations')),
  pg_temp.sorted(pg_temp.expected_keys('observations', '{}'::text[], array['user_id'])),
  'model: observations = every column plus the legacy user_id key');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('profile_modes')),
  pg_temp.sorted(pg_temp.expected_keys('profile_modes', '{}'::text[], '{}'::text[])),
  'model: profile_modes = every column, nothing ignored');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('cycle_overrides')),
  pg_temp.sorted(pg_temp.expected_keys('cycle_overrides', '{}'::text[], '{}'::text[])),
  'model: cycle_overrides = every column, nothing ignored');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('care_notes')),
  pg_temp.sorted(pg_temp.expected_keys('care_notes', '{}'::text[], array['user_id'])),
  'model: care_notes = every column plus the legacy user_id key');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('visit_prep_items')),
  pg_temp.sorted(pg_temp.expected_keys('visit_prep_items',
    array['checked_by_user_id', 'checked_at'], array['user_id'])),
  'model: visit_prep_items = every column minus checked_by_user_id/checked_at plus legacy user_id');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('day_entry_merge_events')),
  pg_temp.sorted(pg_temp.expected_keys('day_entry_merge_events', array['created_at'], '{}'::text[])),
  'model: day_entry_merge_events = every column minus created_at (server-stamped)');

select is(
  pg_temp.sorted(public.sync_push_payload_keys('profile_tag_registry')),
  pg_temp.sorted(pg_temp.expected_keys('profile_tag_registry',
    array['created_by', 'created_at'], '{}'::text[])),
  'model: profile_tag_registry = every column minus created_by/created_at (server-stamped)');

-- ---------------------------------------------------------------------------
-- 2. The live function matches the derivation (the regression pin: a
--    column added by a later migration without re-emitting sync_push
--    fails here, exactly the birth_year/relationship bug class).
-- ---------------------------------------------------------------------------

select is(pg_temp.sorted(pg_temp.embedded_keys('c_profile_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('profiles')),
  'live: embedded c_profile_keys == derived (profiles)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_day_entry_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('day_entries')),
  'live: embedded c_day_entry_keys == derived (day_entries)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_observation_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('observations')),
  'live: embedded c_observation_keys == derived (observations)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_profile_mode_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('profile_modes')),
  'live: embedded c_profile_mode_keys == derived (profile_modes)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_cycle_override_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('cycle_overrides')),
  'live: embedded c_cycle_override_keys == derived (cycle_overrides)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_care_note_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('care_notes')),
  'live: embedded c_care_note_keys == derived (care_notes)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_visit_prep_item_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('visit_prep_items')),
  'live: embedded c_visit_prep_item_keys == derived (visit_prep_items)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_merge_event_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('day_entry_merge_events')),
  'live: embedded c_merge_event_keys == derived (day_entry_merge_events)');
select is(pg_temp.sorted(pg_temp.embedded_keys('c_tag_registry_keys')),
  pg_temp.sorted(public.sync_push_payload_keys('profile_tag_registry')),
  'live: embedded c_tag_registry_keys == derived (profile_tag_registry)');

-- ---------------------------------------------------------------------------
-- 3. The issue's literal AC: every column with an `authenticated` write
--    grant appears in the live embedded allowlist, aside from the
--    documented server-stamped columns. (day_entries currently carries no
--    write grants at all -- 20260915160000 made sync_push its sole write
--    path -- so its assertion is vacuously true and pinned for the day
--    the grants return; profiles' ignored set is empty, so the AC holds
--    there in its strict original form.)
-- ---------------------------------------------------------------------------

create function pg_temp.granted_outside_allowlist(p_const text, p_table text, p_ignored text[]) returns bigint
language sql as $f$
  select count(*)
    from unnest(pg_temp.granted_writable(p_table)) g
   where g <> all (pg_temp.embedded_keys(p_const))
     and g <> all (coalesce(p_ignored, '{}'::text[]))
$f$;

select is(pg_temp.granted_outside_allowlist('c_profile_keys', 'profiles', '{}'::text[]), 0::bigint,
  'AC: every authenticated write-granted profiles column is in the allowlist (strict form)');
select is(pg_temp.granted_outside_allowlist('c_day_entry_keys', 'day_entries', array['created_at']), 0::bigint,
  'AC: every authenticated write-granted day_entries column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_observation_keys', 'observations', '{}'::text[]), 0::bigint,
  'AC: every authenticated write-granted observations column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_profile_mode_keys', 'profile_modes', '{}'::text[]), 0::bigint,
  'AC: every authenticated write-granted profile_modes column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_cycle_override_keys', 'cycle_overrides', '{}'::text[]), 0::bigint,
  'AC: every authenticated write-granted cycle_overrides column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_care_note_keys', 'care_notes', '{}'::text[]), 0::bigint,
  'AC: every authenticated write-granted care_notes column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_visit_prep_item_keys', 'visit_prep_items',
    array['checked_by_user_id', 'checked_at']), 0::bigint,
  'AC: every authenticated write-granted visit_prep_items column is in the allowlist aside from the server-stamped checked_* pair');
select is(pg_temp.granted_outside_allowlist('c_merge_event_keys', 'day_entry_merge_events', array['created_at']), 0::bigint,
  'AC: every authenticated write-granted day_entry_merge_events column is in the allowlist');
select is(pg_temp.granted_outside_allowlist('c_tag_registry_keys', 'profile_tag_registry',
    array['created_by', 'created_at']), 0::bigint,
  'AC: every authenticated write-granted profile_tag_registry column is in the allowlist aside from the server-stamped created_* pair');

-- ---------------------------------------------------------------------------
-- 4. Behavior: the derived model at the RPC surface.
-- ---------------------------------------------------------------------------

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('ally');
select tests.authenticate_as('ally');

-- 4a. A profiles row carrying EVERY derived profiles key (all 21,
-- including the tolerated-but-never-read ones) is accepted, not rejected
-- as carrying unknown keys -- end-to-end proof the derived allowlist
-- admits the full column set the derivation claims.
insert into r select 'p_all_keys', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1),
    'display_name', 'Full Keys',
    'is_minor', false,
    'sort_order', 3,
    'archived_at', null,
    'created_at', '2026-09-12T09:00:00Z',
    'updated_at', '2026-09-12T09:00:00Z',
    'deleted_at', null,
    'server_version', '7',
    'user_id', tests.get_supabase_uid('ally')::text,
    'birth_year', 1994,
    'relationship', 'partner',
    'transferred_at', null,
    'transferred_to_user_id', null,
    'mode', 'standard',
    'last_period_start', '2026-08-01',
    'typical_cycle_length_days', 28,
    'typical_period_length_days', 5,
    'bbt_unit', 'fahrenheit',
    'weight_unit', 'lb',
    'tracking_preferences', null)),
  '[]'::jsonb);
select is(pg_temp.resp('p_all_keys') -> 'rejected', '[]'::jsonb,
  'behavior: a profiles row carrying every derived key is accepted');
select is((select display_name from public.profiles where id = tests.ulid(1)), 'Full Keys',
  'behavior: the every-key profiles row landed');
select is((select bbt_unit from public.profiles where id = tests.ulid(1)), 'fahrenheit',
  'behavior: the every-key profiles row carried its payload');

-- 4b. The legacy extra: a care note carrying 'user_id' (never a column of
-- care_notes, tolerated since the hand-written era) is still accepted.
insert into r select 'n_legacy_uid', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(11), 'profile_id', tests.ulid(1), 'body', 'note with legacy key',
    'user_id', tests.get_supabase_uid('ally')::text,
    'updated_at', '2026-09-12T10:00:00Z')),
  '[]'::jsonb, '[]'::jsonb);
select is(pg_temp.resp('n_legacy_uid') -> 'rejected', '[]'::jsonb,
  'behavior: the legacy user_id extra is tolerated on a care note');
select is((select count(*) from public.care_notes where id = tests.ulid(11)), 1::bigint,
  'behavior: the care note carrying the legacy key landed');

-- 4c. The ignored set, negative + positive control: day_entries.created_at
-- is server-stamped and rejected as an unknown key; the identical row
-- without it is accepted.
insert into r select 'e_ok', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(101), 'profile_id', tests.ulid(1), 'local_date', '2026-09-12',
    'tz', 'America/New_York', 'flow', 'light', 'tags', '[]'::jsonb, 'note', '',
    'updated_at', '2026-09-12T10:00:00Z')));
select is(pg_temp.resp('e_ok') -> 'rejected', '[]'::jsonb,
  'behavior: control - a minimal day entry is accepted');

insert into r select 'e_created_at', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-12',
    'tz', 'America/New_York', 'flow', 'light', 'tags', '[]'::jsonb, 'note', '',
    'created_at', '2026-01-01T00:00:00Z',
    'updated_at', '2026-09-12T10:00:00Z')));
select is(pg_temp.resp('e_created_at') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(102), 'rejected', true),
  'behavior: day_entries.created_at stays rejected (server-stamped, ignored by the derivation)');

-- 4d. Same shape for profile_tag_registry.created_by.
insert into r select 't_ok', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(201), 'profile_id', tests.ulid(1), 'code', 'mood_great',
    'display_name', 'Mood: great', 'category', 'custom',
    'intensity_enabled', false, 'hidden_at', null, 'sort_order', null,
    'updated_at', '2026-09-12T10:00:00Z')));
select is(pg_temp.resp('t_ok') -> 'rejected', '[]'::jsonb,
  'behavior: control - a minimal registry tag is accepted');

insert into r select 't_created_by', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(202), 'profile_id', tests.ulid(1), 'code', 'mood_forged',
    'display_name', 'Mood: forged', 'category', 'custom',
    'intensity_enabled', false, 'hidden_at', null, 'sort_order', null,
    'created_by', tests.get_supabase_uid('ally')::text,
    'updated_at', '2026-09-12T10:00:00Z')));
select is(pg_temp.resp('t_created_by') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(202), 'rejected', true),
  'behavior: profile_tag_registry.created_by stays rejected (server-stamped, ignored by the derivation)');

-- ---------------------------------------------------------------------------
-- 5. The helper is not a client API.
-- ---------------------------------------------------------------------------

select ok(not has_function_privilege('anon', 'public.sync_push_payload_keys(text)', 'execute'),
  'EXECUTE on sync_push_payload_keys is denied to anon');
select ok(not has_function_privilege('authenticated', 'public.sync_push_payload_keys(text)', 'execute'),
  'EXECUTE on sync_push_payload_keys is denied to authenticated');

select * from finish();
rollback;
