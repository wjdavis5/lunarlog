-- Coverage for observations_live_profile_date_category_code_uq (Issue
-- #565). The index itself makes it IMPOSSIBLE to recreate the pre-fix
-- "two live duplicates" state via any write path (including a raw
-- service_role insert), so this proves the structural guarantee directly
-- rather than re-testing sync_push's own (already-covered, in
-- observations_test.sql) advisory dedup logic.
begin;
select plan(5);

select tests.create_supabase_user('mom');
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
-- Issue #201: authenticated no longer holds insert/update on day_entries at
-- all - this fixture insert runs as service_role instead (auth.uid() is
-- unaffected, since that reads request.jwt.claims, a separate session GUC
-- from role).
select set_config('role', 'service_role', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'none', '2026-09-01T00:00:00Z');
select set_config('role', 'authenticated', true);

select ok(
  exists (
    select 1 from pg_indexes
     where schemaname = 'public' and tablename = 'observations'
       and indexname = 'observations_live_profile_date_category_code_uq'
  ),
  'observations_live_profile_date_category_code_uq exists'
);

insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
values
  (tests.ulid(100), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'pain', 'headache', '2026-09-01T09:00:00Z');

-- A second LIVE row sharing (profile_id, local_date, category, code) is
-- rejected by the index - the exact race the issue reports (two guardians'
-- advisory-locked pushes each finding no live sibling and both inserting).
select throws_ok(
  $$insert into public.observations
      (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
    values
      (tests.ulid(101), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'pain', 'headache', '2026-09-01T10:00:00Z')$$,
  '23505', null,
  'a second LIVE duplicate on (profile_id, local_date, category, code) is rejected'
);

-- Only one live row exists.
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(1) and local_date = '2026-09-01'
      and category = 'pain' and code = 'headache' and deleted_at is null),
  1::bigint,
  'exactly one live row survives the rejected duplicate insert'
);

-- A TOMBSTONED duplicate on the same key does NOT conflict - the partial
-- index only covers deleted_at is null.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at, deleted_at)
values
  (tests.ulid(102), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', null, null, '2026-09-01T08:00:00Z', '2026-09-01T08:00:00Z');
select is(
  (select count(*) from public.observations where id = tests.ulid(102)),
  1::bigint,
  'a tombstoned row on the same date/category/code coexists with the live one (partial index)'
);

-- Two live rows with code IS NULL on the same (profile_id, local_date,
-- category) do NOT conflict - the partial index excludes code is null.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
values
  (tests.ulid(103), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'note', null, '2026-09-01T11:00:00Z');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, updated_at)
values
  (tests.ulid(104), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'note', null, '2026-09-01T12:00:00Z');
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(1) and local_date = '2026-09-01'
      and category = 'note' and code is null and deleted_at is null),
  2::bigint,
  'two live rows with code IS NULL on the same date/category coexist (index excludes code is null)'
);

rollback;
