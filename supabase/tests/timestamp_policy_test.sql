-- Issue #641 · LLA-058 (P2): finite-timestamp policy at all write
-- boundaries. Proves the new CHECKs reject nonfinite / far-future /
-- pre-1970 timestamps on raw column UPDATE grants (profiles, day_entries,
-- observations), that bulk_import_safe_timestamptz rejects far-future rows
-- per-row, that the helper's own bounds are correct, and that sync_push's
-- lower/nonfinite edge (-infinity) is rejected per-row via the CHECK.
begin;
select plan(25);

-- ---------------------------------------------------------------------------
-- helper bounds
-- ---------------------------------------------------------------------------
select ok(public.is_supported_timestamp(now()), 'now() is supported');
select ok(public.is_supported_timestamp('1970-01-01T00:00:00Z'::timestamptz), 'epoch lower bound inclusive');
select ok(not public.is_supported_timestamp('1969-12-31T23:59:59Z'::timestamptz), 'pre-epoch rejected');
select ok(not public.is_supported_timestamp('2100-01-01T00:00:00Z'::timestamptz), 'far-future finite (2100) rejected');
select ok(not public.is_supported_timestamp('infinity'::timestamptz), 'infinity rejected');
select ok(not public.is_supported_timestamp('-infinity'::timestamptz), '-infinity rejected');
select ok(not public.is_supported_timestamp(null), 'null rejected');

-- ---------------------------------------------------------------------------
-- bulk_import_safe_timestamptz rejects far-future/nonfinite
-- ---------------------------------------------------------------------------
select is(public.bulk_import_safe_timestamptz('2026-09-01T09:00:00Z'), '2026-09-01T09:00:00Z'::timestamptz,
  'safe_timestamptz: valid value passes');
select is(public.bulk_import_safe_timestamptz('infinity'), null, 'safe_timestamptz: infinity -> null');
select is(public.bulk_import_safe_timestamptz('-infinity'), null, 'safe_timestamptz: -infinity -> null');
select is(public.bulk_import_safe_timestamptz('2100-01-01T00:00:00Z'), null,
  'safe_timestamptz: far-future finite -> null');

-- ---------------------------------------------------------------------------
-- raw column UPDATE grants reject poison via the CHECKs (authenticated)
-- ---------------------------------------------------------------------------
create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t0', '2026-09-01T09:00:00Z'), ('t1', '2026-09-01T10:00:00Z'), ('t2', '2026-09-01T11:00:00Z');
grant select on table ts to authenticated;
create function pg_temp.ts_txt(k text) returns text language sql as
  $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') from ts where ts.k = $1 $$;
create function pg_temp.ts_at(k text) returns timestamptz language sql as
  $$ select t from ts where ts.k = $1 $$;

select tests.create_supabase_user('user_a');
select tests.authenticate_as('user_a');

-- profile + day entry via sync_push (owner becomes primary_guardian)
insert into r select 'setup', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Alice', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', null)),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(101), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'light', 'tags', '[]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(201), 'day_entry_id', tests.ulid(101), 'profile_id', tests.ulid(1),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'cramps', 'code', 'mild',
    'value_num', 1, 'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('setup') -> 'rejected', '[]'::jsonb, 'setup: nothing rejected');

-- profiles
select throws_ok(
  $$ update public.profiles set updated_at = 'infinity' where id = tests.ulid(1) $$,
  null, null, 'profiles: raw PATCH updated_at = infinity rejected');
select throws_ok(
  $$ update public.profiles set updated_at = '-infinity' where id = tests.ulid(1) $$,
  null, null, 'profiles: raw PATCH updated_at = -infinity rejected');
select throws_ok(
  $$ update public.profiles set updated_at = '2100-01-01T00:00:00Z' where id = tests.ulid(1) $$,
  null, null, 'profiles: raw PATCH updated_at = 2100 rejected');
select throws_ok(
  $$ update public.profiles set created_at = '1969-01-01T00:00:00Z' where id = tests.ulid(1) $$,
  null, null, 'profiles: raw PATCH created_at pre-epoch rejected');

-- day_entries
select throws_ok(
  $$ update public.day_entries set updated_at = 'infinity' where id = tests.ulid(101) $$,
  null, null, 'day_entries: raw PATCH updated_at = infinity rejected');
select throws_ok(
  $$ update public.day_entries set updated_at = '2100-01-01T00:00:00Z' where id = tests.ulid(101) $$,
  null, null, 'day_entries: raw PATCH updated_at = 2100 rejected');

-- observations
select throws_ok(
  $$ update public.observations set updated_at = 'infinity' where id = tests.ulid(201) $$,
  null, null, 'observations: raw PATCH updated_at = infinity rejected');
select throws_ok(
  $$ update public.observations set updated_at = '-infinity' where id = tests.ulid(201) $$,
  null, null, 'observations: raw PATCH updated_at = -infinity rejected');
select throws_ok(
  $$ update public.observations set updated_at = '2100-01-01T00:00:00Z' where id = tests.ulid(201) $$,
  null, null, 'observations: raw PATCH updated_at = 2100 rejected');

-- a healthy raw write still lands
update public.day_entries
   set updated_at = pg_temp.ts_at('t2')::timestamptz, note = 'still works'
 where id = tests.ulid(101);
select is((select note from public.day_entries where id = tests.ulid(101)), 'still works',
  'day_entries: a healthy raw write is not blocked');

-- ---------------------------------------------------------------------------
-- sync_push lower/nonfinite edge is rejected per-row (CHECK violation -> rejected)
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select tests.authenticate_as('user_a');
insert into r select 'rpc_lower', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Bob', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', '-infinity', 'deleted_at', null)),
  '[]'::jsonb);
select is(pg_temp.resp('rpc_lower') -> 'rejected', jsonb_build_array(jsonb_build_object('id', tests.ulid(2), 'rejected', true)),
  'sync_push: -infinity updated_at is rejected per-row');
select is((select count(*) from public.profiles where id = tests.ulid(2)), 0::bigint,
  'sync_push: the -infinity row was not stored');

-- an ordinary supported push still lands after the rejection
insert into r select 'rpc_ok', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Bob', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', pg_temp.ts_txt('t2'), 'deleted_at', null)),
  '[]'::jsonb);
select is(pg_temp.resp('rpc_ok') -> 'rejected', '[]'::jsonb, 'sync_push: a supported push lands');

select * from finish();
rollback;
