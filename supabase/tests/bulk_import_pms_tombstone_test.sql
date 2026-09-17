-- Regression coverage for Issue #140 review follow-up (LLA-060, P2):
-- 20260915020000_bulk_import_pms_tombstone.sql. bulk_import_entries
-- (supabase/migrations/20260908190000_bulk_import.sql, last re-emitted by
-- 20260908200000_flow_model.sql) predates #220's PMS marker entirely, so
-- neither of its two write paths (the by-id UPDATE, and the
-- (profile_id, source, source_id) ON CONFLICT DO UPDATE) ever cleared a
-- stored `pms = true` when the row was becoming a tombstone -- violating
-- day_entries_tombstone_pms_check (a check_violation this function's own
-- `exception when unique_violation` handler does not catch) and aborting
-- the WHOLE CHUNK, not just the offending row. Reuses the
-- create_supabase_user / authenticate_as / pg_temp snapshot idiom already
-- established in bulk_import_test.sql; general RPC shape/authorization/
-- validation coverage lives there and is not duplicated here.
begin;
select plan(11);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated, service_role;
create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into r values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('mom');
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(760), 'Riley', true, 0, '2026-09-14T00:00:00Z', '2026-09-14T00:00:00Z');

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(760), 'clue_import', 'pending', 10, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job1', to_jsonb((select id from ins)::text));
create function pg_temp.job1() returns uuid language sql as
  $$ select (pg_temp.resp('job1') #>> '{}')::uuid $$;

-- ---------------------------------------------------------------------------
-- 1. By-id path: a chunk that tombstones an existing pms = true row by id
--    no longer aborts, and clears pms rather than leaving it stale.
-- ---------------------------------------------------------------------------
insert into r select 'byid_insert', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(761), 'profile_id', tests.ulid(760), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'byid-src', 'updated_at', '2026-09-10T08:00:00Z')));
select is(pg_temp.resp('byid_insert') -> 'inserted', '1'::jsonb, 'setup: the by-id fixture row is inserted');

-- pms is not a bulk-import-carried field (outside c_row_keys) -- simulating
-- the row already being marked PMS through the ordinary app path (ie.
-- sync_push) requires a direct write, exactly like this row would already
-- carry it in day_entries before any bulk import ever touched it.
select set_config('role', 'service_role', true);
update public.day_entries set pms = true where id = tests.ulid(761);
select set_config('role', 'authenticated', true);
select is((select pms from public.day_entries where id = tests.ulid(761)), true,
  'setup: the by-id fixture row now carries pms = true');

select lives_ok(
  format($$select public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-09-10', 'tz', 'UTC',
      'updated_at', '2026-09-10T08:00:00Z', 'deleted_at', '2026-09-11T00:00:00Z')))$$,
    tests.ulid(761), tests.ulid(760)),
  'by-id tombstone of a pms = true row no longer aborts the chunk (day_entries_tombstone_pms_check)');
select is((select pms from public.day_entries where id = tests.ulid(761)), false,
  'by-id tombstone clears the stale pms marker rather than leaving it stale');
select is((select deleted_at is not null from public.day_entries where id = tests.ulid(761)), true,
  'by-id tombstone actually lands (deleted_at is set)');

-- An ordinary (non-tombstoning) by-id update must NOT spuriously clear an
-- existing pms marker -- the fix only ever forces false when the row is
-- becoming a tombstone, never on a plain live edit.
select set_config('role', 'service_role', true);
update public.day_entries set deleted_at = null, pms = true where id = tests.ulid(761);
select set_config('role', 'authenticated', true);
select lives_ok(
  format($$select public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-09-10', 'tz', 'UTC', 'flow', 'heavy',
      'updated_at', '2026-09-12T08:00:00Z')))$$,
    tests.ulid(761), tests.ulid(760)),
  'an ordinary (non-tombstoning) by-id update still lives');
select is((select pms from public.day_entries where id = tests.ulid(761)), true,
  'an ordinary by-id live update leaves an existing pms marker untouched');

-- ---------------------------------------------------------------------------
-- 2. Source-conflict path: a chunk that tombstones an existing pms = true
--    row via the (profile_id, source, source_id) ON CONFLICT arbiter (not
--    matched by id) no longer aborts either.
-- ---------------------------------------------------------------------------
insert into r select 'conflict_insert', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(762), 'profile_id', tests.ulid(760), 'local_date', '2026-09-13',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'conflict-src', 'updated_at', '2026-09-13T08:00:00Z')));
select is(pg_temp.resp('conflict_insert') -> 'inserted', '1'::jsonb,
  'setup: the source-conflict fixture row is inserted');
select set_config('role', 'service_role', true);
update public.day_entries set pms = true where id = tests.ulid(762);
select set_config('role', 'authenticated', true);

-- A DIFFERENT id, same (profile_id, source, source_id) -- misses the by-id
-- join entirely and resolves only through the ON CONFLICT arbiter.
select lives_ok(
  format($$select public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-09-13', 'tz', 'UTC',
      'source_id', 'conflict-src', 'updated_at', '2026-09-13T08:00:00Z',
      'deleted_at', '2026-09-14T00:00:00Z')))$$,
    tests.ulid(763), tests.ulid(760)),
  'source-conflict tombstone of a pms = true row no longer aborts the chunk');
select is((select pms from public.day_entries where id = tests.ulid(762)), false,
  'source-conflict tombstone clears the stale pms marker on the pre-existing row');
select is((select deleted_at is not null from public.day_entries where id = tests.ulid(762)), true,
  'source-conflict tombstone actually lands on the pre-existing row (resolved and tombstoned in place via the arbiter, not inserted as a new row under the incoming id)');

select * from finish();
rollback;
