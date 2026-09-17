-- Coverage for Issue #192 (feat(modes): Pregnancy mode):
-- public.profile_modes.estimated_due_date -- the synced due date a
-- pregnancy entry collects or derives (last recorded period start + 280
-- days, Naegele's rule; a manual pick when that start is
-- unknown/imported). Pins: column shape and grant, the #181 derived
-- payload-key allowlist picking the new column up, the sync_push round
-- trip, and the old-client key-omission containment guard (a pre-#192
-- client's push never clears a stored due date). The *mean-integrity*
-- half of the issue (the pregnancy interval's exclusion from cycle
-- averages) is client-side computation and is pinned in Dart
-- (test/domain/pregnancy_test.dart), not here -- the server stores
-- cycle_overrides rows but never computes averages.
-- Fixture style: profile_modes_cycle_overrides_test.sql.
begin;
select plan(11);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

-- ---------------------------------------------------------------------------
-- Column shape and grant.
-- ---------------------------------------------------------------------------
select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_modes'
      and column_name = 'estimated_due_date'),
  'date', 'estimated_due_date is a date column');
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_modes'
      and column_name = 'estimated_due_date'),
  'YES', 'estimated_due_date is nullable (no due date recorded)');
select is(
  (select has_column_privilege('authenticated', 'public.profile_modes',
    'estimated_due_date', 'UPDATE')),
  true, 'authenticated may update estimated_due_date (the column-list grant shape)');
select is(
  (select has_column_privilege('anon', 'public.profile_modes',
    'estimated_due_date', 'SELECT')),
  false, 'anon cannot read estimated_due_date');

-- The #181 derived allowlist picks the new column up (information_schema
-- derivation), so a full-key client payload is never rejected as an
-- unknown key.
select ok(
  (select 'estimated_due_date' = any (public.sync_push_payload_keys('profile_modes'))),
  'derived payload allowlist for profile_modes includes estimated_due_date');

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) owns the profile.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Round trip: entering Pregnancy mode with a derived due date.
-- ---------------------------------------------------------------------------
insert into r select 'due_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(901), 'mode', 'pregnancy',
    'mode_started_on', '2026-09-10',
    'estimated_due_date', '2027-06-17',
    'updated_at', '2026-09-10T08:00:00Z')),
  '[]'::jsonb);

select is((select mode from public.profile_modes where profile_id = tests.ulid(901)), 'pregnancy',
  'round trip: pregnancy mode persisted');
select is((select estimated_due_date from public.profile_modes where profile_id = tests.ulid(901)),
  '2027-06-17'::date, 'round trip: estimated_due_date persisted');

-- ---------------------------------------------------------------------------
-- Old-client containment guard: a newer push that OMITS the
-- estimated_due_date key (a pre-#192 client editing the same row, e.g.
-- renaming the profile) must not clear the stored due date.
-- ---------------------------------------------------------------------------
insert into r select 'omit_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(901), 'mode', 'pregnancy',
    'mode_started_on', '2026-09-10',
    'updated_at', '2026-09-11T08:00:00Z')),
  '[]'::jsonb);

select is((select estimated_due_date from public.profile_modes where profile_id = tests.ulid(901)),
  '2027-06-17'::date,
  'containment guard: a pre-#192 client''s key-omitting push keeps the stored due date');

-- ---------------------------------------------------------------------------
-- Overwrite: a newer push that CARRIES the key moves it (a corrected due
-- date), and an invalid value is rejected as a row, not a batch failure.
-- ---------------------------------------------------------------------------
insert into r select 'update_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(901), 'mode', 'pregnancy',
    'mode_started_on', '2026-09-10',
    'estimated_due_date', '2027-06-24',
    'updated_at', '2026-09-12T08:00:00Z')),
  '[]'::jsonb);

select is((select estimated_due_date from public.profile_modes where profile_id = tests.ulid(901)),
  '2027-06-24'::date, 'a newer push carrying the key overwrites the due date');

-- Still mom (an authorized writer): a malformed date value must reject
-- its row through the per-row handler -- as a stranger the same push
-- would reject for the wrong reason (the write ladder), proving nothing
-- about the date guard.
insert into r select 'bad_date_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(901), 'mode', 'pregnancy',
    'mode_started_on', '2026-09-10',
    'estimated_due_date', 'not-a-date',
    'updated_at', '2026-09-13T08:00:00Z')),
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from r where name = 'bad_date_push'),
  1, 'a malformed estimated_due_date rejects its row');
select is((select estimated_due_date from public.profile_modes where profile_id = tests.ulid(901)),
  '2027-06-24'::date, 'the malformed push left the stored due date untouched');

select * from finish();
rollback;
