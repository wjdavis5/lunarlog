-- Coverage for Issue #861 (Postpartum mode birth date):
-- public.profile_modes.postpartum_birth_date -- the optional birth date
-- the operator supplies when selecting Postpartum, which the client-side
-- day counter runs from when present (falling back to the mode-start
-- surrogate when null). Pins: column shape and grant, the #181 derived
-- payload-key allowlist picking the new column up, the sync_push round
-- trip, and the old-client key-omission containment guard (a pre-#861
-- client's push never clears a stored birth date). The *day-count* half
-- of the issue is client-side computation and is pinned in Dart
-- (test/domain/postpartum_test.dart), not here.
-- Fixture style: pregnancy_due_date_test.sql.
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
      and column_name = 'postpartum_birth_date'),
  'date', 'postpartum_birth_date is a date column');
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_modes'
      and column_name = 'postpartum_birth_date'),
  'YES', 'postpartum_birth_date is nullable (no birth date supplied)');
select is(
  (select has_column_privilege('authenticated', 'public.profile_modes',
    'postpartum_birth_date', 'UPDATE')),
  true, 'authenticated may update postpartum_birth_date (the column-list grant shape)');
select is(
  (select has_column_privilege('anon', 'public.profile_modes',
    'postpartum_birth_date', 'SELECT')),
  false, 'anon cannot read postpartum_birth_date');

-- The #181 derived allowlist picks the new column up (information_schema
-- derivation), so a full-key client payload is never rejected as an
-- unknown key.
select ok(
  (select 'postpartum_birth_date' = any (public.sync_push_payload_keys('profile_modes'))),
  'derived payload allowlist for profile_modes includes postpartum_birth_date');

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) owns the profile.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(911), 'Riley', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Round trip: entering Postpartum mode with a supplied birth date.
-- ---------------------------------------------------------------------------
insert into r select 'birth_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(911), 'mode', 'postpartum',
    'mode_started_on', '2026-09-10',
    'postpartum_birth_date', '2026-09-01',
    'updated_at', '2026-09-10T08:00:00Z')),
  '[]'::jsonb);

select is((select mode from public.profile_modes where profile_id = tests.ulid(911)), 'postpartum',
  'round trip: postpartum mode persisted');
select is((select postpartum_birth_date from public.profile_modes where profile_id = tests.ulid(911)),
  '2026-09-01'::date, 'round trip: postpartum_birth_date persisted');

-- ---------------------------------------------------------------------------
-- Old-client containment guard: a newer push that OMITS the
-- postpartum_birth_date key (a pre-#861 client editing the same row, e.g.
-- renaming the profile) must not clear the stored birth date.
-- ---------------------------------------------------------------------------
insert into r select 'omit_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(911), 'mode', 'postpartum',
    'mode_started_on', '2026-09-10',
    'updated_at', '2026-09-11T08:00:00Z')),
  '[]'::jsonb);

select is((select postpartum_birth_date from public.profile_modes where profile_id = tests.ulid(911)),
  '2026-09-01'::date,
  'containment guard: a pre-#861 client''s key-omitting push keeps the stored birth date');

-- ---------------------------------------------------------------------------
-- Overwrite: a newer push that CARRIES the key moves it (a corrected
-- birth date), and an invalid value is rejected as a row, not a batch
-- failure.
-- ---------------------------------------------------------------------------
insert into r select 'update_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(911), 'mode', 'postpartum',
    'mode_started_on', '2026-09-10',
    'postpartum_birth_date', '2026-09-02',
    'updated_at', '2026-09-12T08:00:00Z')),
  '[]'::jsonb);

select is((select postpartum_birth_date from public.profile_modes where profile_id = tests.ulid(911)),
  '2026-09-02'::date, 'a newer push carrying the key overwrites the birth date');

-- Still mom (an authorized writer): a malformed date value must reject
-- its row through the per-row handler -- as a stranger the same push
-- would reject for the wrong reason (the write ladder), proving nothing
-- about the date guard.
insert into r select 'bad_date_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(911), 'mode', 'postpartum',
    'mode_started_on', '2026-09-10',
    'postpartum_birth_date', 'not-a-date',
    'updated_at', '2026-09-13T08:00:00Z')),
  '[]'::jsonb);

select is((select jsonb_array_length(v -> 'rejected') from r where name = 'bad_date_push'),
  1, 'a malformed postpartum_birth_date rejects its row');
select is((select postpartum_birth_date from public.profile_modes where profile_id = tests.ulid(911)),
  '2026-09-02'::date, 'the malformed push left the stored birth date untouched');

select * from finish();
rollback;
