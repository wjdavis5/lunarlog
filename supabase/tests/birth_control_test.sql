-- Coverage for Issue #260 (P1, epic: Tracking Model): birth-control
-- tracking -- the six-method per-day intake observations family and the
-- profile-level current-method attribute.
--
-- NO MIGRATION ACCOMPANIES THIS FILE, deliberately: the issue's storage
-- direction rides the two surfaces its dependencies already landed --
-- per-day intake lives in #240's `observations` child table as a
-- `birth_control_*` category family (`category`/`code` are
-- stored-never-rejected free text there, so the six categories and the
-- pill's taken/late/missed-style adherence codes need no DDL), and the
-- profile-level current method with its effective dates lives in #188's
-- `profile_modes.birth_control_method`/`birth_control_started_on`/
-- `birth_control_stopped_on` columns, landed free-text with #260 named
-- as the vocabulary owner. The canonical vocabulary itself is
-- client-side (`lib/domain/birth_control.dart`) -- a server-side closed
-- CHECK would reject a future re-pinned option string exactly the way
-- #240 decided codes must never be rejected. This file is the test-only
-- half: it pins the *semantics* the issue's acceptance criteria demand
-- over the existing schema.
--
-- What is proven here:
--   1. Intake rows round-trip through `sync_push`'s existing
--      `p_observations` parameter (pill adherence row, and a
--      presence-based non-pill row whose code is null), with attribution
--      and server_version stamping.
--   2. Same-(profile, local_date, category, code) collision resolution
--      applies to intake rows like every other observation (newer wins,
--      loser becomes a payload-free tombstone), while *distinct* codes on
--      the same day coexist (taken + missed stay two live rows -- the
--      multi-row model is deliberate; the consumer disambiguates, and no
--      server-side collapse is invented for the birth-control family).
--   3. Tombstone pushes clear the intake payload (issue #224 precedent).
--   4. AC4 independence, both directions: editing the profile-level
--      `birth_control_method` (and its effective dates) through
--      `p_profile_modes` never touches any observation row (count and
--      updated_at unchanged), and pushing an intake observation never
--      touches `profile_modes`' birth-control columns -- a missed pill
--      day is not a method change (A1-29), and a method switch never
--      rewrites history.
--   5. The role ladder holds for intake rows: a viewer's push is an
--      opaque rejected entry.
--
-- Fixture style: profile_modes_cycle_overrides_test.sql /
-- observations_test.sql.
begin;
select plan(22);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.resolved_row(n text, p_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'id' = p_id limit 1 $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;
-- Live pill-intake rows for the fixture day, as a sorted code array.
create function pg_temp.live_pill_codes() returns text[] language sql as
  $$ select array_agg(code order by code) from public.observations
     where profile_id = tests.ulid(801) and local_date = '2026-09-05'
       and category = 'birth_control_pill' and deleted_at is null $$;
create function pg_temp.live_birth_control_count() returns integer language sql as
  $$ select count(*)::integer from public.observations
     where profile_id = tests.ulid(801) and category like 'birth_control_%'
       and deleted_at is null $$;

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) with dad (co_parent) and doc (viewer)
-- on one profile carrying a day entry and one non-birth-control
-- observation.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doc');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(801), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(802), tests.ulid(801), '2026-09-05', 'UTC', 'none', '2026-09-05T08:00:00Z');
insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
values (tests.ulid(803), tests.ulid(802), tests.ulid(801), '2026-09-05', 'UTC', 'pain', 'cramps', '2026-09-05T08:30:00Z');

select public.create_guardian_invitation(tests.ulid(801), 'co_parent', 'Dad',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 48);
select public.create_guardian_invitation(tests.ulid(801), 'viewer', 'Doc',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 48);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Dad');
select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'Doc');

-- ---------------------------------------------------------------------------
-- 1. Round trip (AC1/AC2): a pill adherence row and a presence-based
--    non-pill row through p_observations. No new parameter, no new table.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_pill_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object(
      'id', tests.ulid(804), 'day_entry_id', tests.ulid(802),
      'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
      'category', 'birth_control_pill', 'code', 'taken',
      'updated_at', '2026-09-05T09:00:00Z'),
    jsonb_build_object(
      'id', tests.ulid(805), 'day_entry_id', tests.ulid(802),
      'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
      'category', 'birth_control_ring',
      'updated_at', '2026-09-05T09:05:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is((select category from public.observations where id = tests.ulid(804)),
  'birth_control_pill', 'round trip: pill intake category persisted');
select is((select code from public.observations where id = tests.ulid(804)),
  'taken', 'round trip: the pill adherence value is the row''s code');
select is((select day_entry_id from public.observations where id = tests.ulid(804)),
  tests.ulid(802), 'round trip: intake row attached to the day entry');
select is((select logged_by_user_id from public.observations where id = tests.ulid(804)),
  tests.get_supabase_uid('mom'), 'round trip: logged_by_user_id stamped from the caller');
select isnt((select server_version from public.observations where id = tests.ulid(804)),
  0::bigint, 'round trip: server_version stamped by the shared trigger');
select is((select category from public.observations where id = tests.ulid(805)),
  'birth_control_ring', 'round trip: presence-based method category persisted');
select is((select code from public.observations where id = tests.ulid(805)) is null,
  true, 'round trip: a non-pill method logs presence with no invented code');

-- ---------------------------------------------------------------------------
-- 2. Same-day collision resolution and coexistence.
-- ---------------------------------------------------------------------------
-- Dad's independently-logged "taken" for the same day (a different row id,
-- a newer updated_at) resolves head-to-head with mom's: dad's wins, mom's
-- becomes a payload-free tombstone (the #240 rule, now asserted for the
-- birth-control family specifically).
select tests.authenticate_as('dad');
insert into r select 'dad_pill_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(806), 'day_entry_id', tests.ulid(802),
    'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
    'category', 'birth_control_pill', 'code', 'taken',
    'updated_at', '2026-09-05T10:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is((select deleted_at is not null from public.observations where id = tests.ulid(804)),
  true, 'same-(category, code) collision: the losing intake row is tombstoned');
select is((select category is null and code is null and value_num is null and value_text is null
    from public.observations where id = tests.ulid(804)),
  true, 'same-(category, code) collision: the loser carries no payload (issue #224)');
select is((select deleted_at is null and code = 'taken' from public.observations where id = tests.ulid(806)),
  true, 'same-(category, code) collision: the winning intake row stays live');
select is((pg_temp.resolved_row('dad_pill_push', tests.ulid(804))) ->> 'deleted_at' is not null,
  true, 'same-(category, code) collision: the server hands back the tombstoned copy');

-- Distinct adherence codes coexist on the same day: a logged "missed"
-- next to a live "taken" is two live rows (the model allows multiple rows
-- per category per day; resolving the day's effective state is the
-- consumer's job -- the server invents no birth-control-specific
-- collapse, and the two rows here may equally be a genuinely double-logged
-- day from two devices).
select tests.authenticate_as('mom');
insert into r select 'mom_missed_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(807), 'day_entry_id', tests.ulid(802),
    'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
    'category', 'birth_control_pill', 'code', 'missed',
    'updated_at', '2026-09-05T11:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is(pg_temp.live_pill_codes(), array['missed', 'taken']::text[],
  'distinct codes coexist: taken and missed stay two live intake rows');

-- A tombstone push clears the intake payload like any other observation.
select tests.authenticate_as('mom');
insert into r select 'mom_tombstone_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(807), 'day_entry_id', tests.ulid(802),
    'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
    'updated_at', '2026-09-05T12:00:00Z', 'deleted_at', '2026-09-05T12:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is((select deleted_at is not null and category is null and code is null
    from public.observations where id = tests.ulid(807)),
  true, 'tombstone push: the missed row is stored payload-free');
select is(pg_temp.live_pill_codes(), array['taken']::text[],
  'tombstone push: only the taken row stays live');

-- ---------------------------------------------------------------------------
-- 3. AC4 independence, both directions.
-- ---------------------------------------------------------------------------
-- (a) Changing the profile-level current method never touches any
--     observation row: count AND updated_at are untouched (the guarantee
--     profile_modes_cycle_overrides_test.sql proves for `mode`, proven
--     here for the birth-control columns).
select tests.authenticate_as('mom');
insert into r select 'mom_modes_seed', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'birth_control_method', 'copper_iud',
    'birth_control_started_on', '2026-01-10',
    'updated_at', '2026-09-06T09:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);
select is((select birth_control_method from public.profile_modes where profile_id = tests.ulid(801)),
  'copper_iud', 'independence seed: the current method is stored');

create temp table obs_before as
  select count(*)::bigint as n, max(updated_at) as last_update
    from public.observations where profile_id = tests.ulid(801);

insert into r select 'mom_method_change', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(801), 'mode', 'tracking',
    'birth_control_method', 'pill',
    'birth_control_started_on', '2026-09-06',
    'updated_at', '2026-09-06T10:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is((select birth_control_method from public.profile_modes where profile_id = tests.ulid(801)),
  'pill', 'AC4: the method change lands');
select is((select birth_control_started_on from public.profile_modes where profile_id = tests.ulid(801)),
  '2026-09-06'::date, 'AC4: the effective start date lands with it');
select is((
    select (select n from obs_before) = (select count(*) from public.observations where profile_id = tests.ulid(801))
       and (select last_update from obs_before) = (select max(updated_at) from public.observations where profile_id = tests.ulid(801))),
  true, 'AC4: changing the current method never touches any intake row (count and updated_at unchanged)');

-- (b) Pushing an intake observation never touches profile_modes'
--     birth-control columns (a missed pill day is not a method change).
create temp table modes_before as
  select birth_control_method, birth_control_started_on, birth_control_stopped_on, updated_at
    from public.profile_modes where profile_id = tests.ulid(801);

insert into r select 'mom_second_intake', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(808), 'day_entry_id', tests.ulid(802),
    'profile_id', tests.ulid(801), 'local_date', '2026-09-06', 'tz', 'UTC',
    'category', 'birth_control_patch',
    'updated_at', '2026-09-06T11:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is((
    select m.birth_control_method = o.birth_control_method
       and m.birth_control_started_on is not distinct from o.birth_control_started_on
       and m.birth_control_stopped_on is not distinct from o.birth_control_stopped_on
       and m.updated_at = o.updated_at
      from modes_before o, public.profile_modes m where m.profile_id = tests.ulid(801)),
  true, 'AC4: an intake push never touches the stored current method or its dates');
select is((select category from public.observations where id = tests.ulid(808)),
  'birth_control_patch', 'AC4 reverse push: the new intake row is stored');

-- ---------------------------------------------------------------------------
-- 4. Role ladder: a viewer's intake push is an opaque rejected entry.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doc');
insert into r select 'doc_intake_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(809), 'day_entry_id', tests.ulid(802),
    'profile_id', tests.ulid(801), 'local_date', '2026-09-05', 'tz', 'UTC',
    'category', 'birth_control_pill', 'code', 'missed',
    'updated_at', '2026-09-05T13:00:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);

select is(tests.ulid(809) = any (pg_temp.rejected_ids('doc_intake_push')),
  true, 'a viewer cannot log intake rows (opaque rejected entry)');
select is(pg_temp.live_birth_control_count(), 3,
  'the viewer''s rejected push stored nothing (the live ring, pill, and patch rows only)');

select * from finish();
rollback;
