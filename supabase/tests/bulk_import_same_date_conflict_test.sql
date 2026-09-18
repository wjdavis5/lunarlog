-- Regression coverage for Issue #332 (epic: Import):
-- public.bulk_import_entries(p_import_id uuid, p_rows jsonb,
-- p_on_date_conflict text default 'reject') -- the opt-in same-date mode
-- (supabase/migrations/20260918140000_bulk_import_entries_same_date_conflict.sql).
--
-- General bulk_import_entries coverage, including the pre-existing
-- reject-mode collision case, lives in bulk_import_test.sql and is not
-- duplicated here; this file pins the NEW surface: the parameter's shape
-- and default, its validation, and the conservative `'merge'` policy (a
-- conflict-free merge-mode batch imports; a batch that would need a
-- same-date merge is refused with a typed error, nothing written).
-- Reuses the create_supabase_user / authenticate_as / pg_temp snapshot
-- idiom already established in bulk_import_test.sql.
begin;
select plan(27);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated, service_role;
create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into r values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('mom'); -- owner / primary_guardian
select tests.create_supabase_user('eve'); -- non-guardian (attacker)

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(900), 'Riley', true, 0, '2026-09-08T00:00:00Z', '2026-09-08T00:00:00Z');

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(900), 'clue_import', 'pending', 100, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job1', to_jsonb((select id from ins)::text));
create function pg_temp.job1() returns uuid language sql as
  $$ select (pg_temp.resp('job1') #>> '{}')::uuid $$;

-- Fixture day entries. authenticated holds no INSERT grant on day_entries
-- (Issue #201), so these land as service_role with auth.uid() still mom.
--   E1/E1b/E2/E4/E5: manual (different provenance from the clue_import job)
--   E3: clue_import, source_id 'arb-src' (the (source, source_id) arbiter)
--   X:  clue_import, source_id 'move-src', on D8 (moved onto D7 in test 25)
--   Rt: clue_import, source_id 'rev-src', tombstoned (revived in test 23)
select set_config('role', 'service_role', true);
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, tags, note, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(910), tests.ulid(900), '2026-11-01', 'UTC', 'light', '["manual"]', 'manual note', now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(911), tests.ulid(900), '2026-11-02', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(912), tests.ulid(900), '2026-11-03', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(913), tests.ulid(900), '2026-11-04', 'UTC', 'medium', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(914), tests.ulid(900), '2026-11-06', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(915), tests.ulid(900), '2026-11-10', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(916), tests.ulid(900), '2026-11-09', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(917), tests.ulid(900), '2026-11-08', 'UTC', 'light', '[]'::jsonb, null, now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));
update public.day_entries
   set source = 'clue_import', source_id = 'arb-src'
 where id = tests.ulid(913);
update public.day_entries
   set source = 'clue_import', source_id = 'move-src'
 where id = tests.ulid(915);
update public.day_entries
   set source = 'clue_import', source_id = 'rev-src',
       deleted_at = now(), flow = 'none', tags = '[]'::jsonb, note = null, updated_at = now()
 where id = tests.ulid(917);
select set_config('role', 'authenticated', true);

-- ---------------------------------------------------------------------------
-- 1. Function shape: the 3-argument signature is the only overload,
--    authenticated executes, PUBLIC/anon are revoked, and the default is
--    the pre-existing 'reject'.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from pg_proc
    where proname = 'bulk_import_entries' and pronamespace = 'public'::regnamespace),
  1::bigint, 'exactly one bulk_import_entries overload exists (the 2-arg one was dropped)');
select ok(
  has_function_privilege('authenticated', 'public.bulk_import_entries(uuid,jsonb,text)', 'execute'),
  'authenticated can execute the 3-argument bulk_import_entries');
select ok(
  (select pg_get_function_arguments(p.oid) from pg_proc p
    where proname = 'bulk_import_entries' and pronamespace = 'public'::regnamespace)
    like '%DEFAULT ''reject''::text%',
  'p_on_date_conflict defaults to ''reject''');
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.bulk_import_entries('00000000-0000-0000-0000-000000000000'::uuid, '[]'::jsonb, 'merge')$$,
  '42501', null, 'anon cannot execute bulk_import_entries');
select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 2. Mode validation: a null or out-of-set p_on_date_conflict is a typed
--    invalid_parameter_value, not silently treated as 'reject'. An empty
--    array under 'merge' is a normal zero-row result (no collision can
--    exist), proving the mode guard does not reject valid empty batches.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.bulk_import_entries(%L::uuid, '[]'::jsonb, 'bogus')$$, pg_temp.job1()),
  '22023', null, 'an out-of-set p_on_date_conflict is rejected with a typed error');
select throws_ok(
  format($$select public.bulk_import_entries(%L::uuid, '[]'::jsonb, null::text)$$, pg_temp.job1()),
  '22023', null, 'a null p_on_date_conflict is rejected with a typed error');
insert into r select 'empty_merge', public.bulk_import_entries(pg_temp.job1(), '[]'::jsonb, 'merge');
select is(pg_temp.resp('empty_merge') -> 'inserted', '0'::jsonb,
  'an empty merge-mode batch returns zeros, not an error');

-- ---------------------------------------------------------------------------
-- 3. Explicit 'reject' is byte-for-byte the pre-existing behaviour: the
--    per-row reason is the same as the defaulted 2-argument call's, and
--    the rest of the batch still lands.
-- ---------------------------------------------------------------------------
insert into r select 'reject_explicit', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(920), 'profile_id', tests.ulid(900), 'local_date', '2026-11-01',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'reject-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(921), 'profile_id', tests.ulid(900), 'local_date', '2026-11-14',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'reject-2', 'updated_at', now()::text)
), 'reject');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('reject_explicit') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'date already has a live entry', 'explicit ''reject'' rejects the colliding row per row');
select is(pg_temp.resp('reject_explicit') -> 'inserted', '1'::jsonb,
  'the non-colliding row in the same explicit-reject batch still lands');

insert into r select 'reject_default', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(922), 'profile_id', tests.ulid(900), 'local_date', '2026-11-02',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'reject-3', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('reject_default') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'date already has a live entry', 'the defaulted 2-argument call keeps the identical reject reason');

-- ---------------------------------------------------------------------------
-- 4. 'merge' with no collisions is indistinguishable from reject: the rows
--    import normally.
-- ---------------------------------------------------------------------------
insert into r select 'merge_clean', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(923), 'profile_id', tests.ulid(900), 'local_date', '2026-11-11',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'merge-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(924), 'profile_id', tests.ulid(900), 'local_date', '2026-11-12',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'merge-2', 'updated_at', now()::text)
), 'merge');
select is(pg_temp.resp('merge_clean') -> 'inserted', '2'::jsonb,
  'a collision-free merge-mode batch imports normally');
select is(pg_temp.resp('merge_clean') -> 'rejected', '[]'::jsonb,
  'a collision-free merge-mode batch reports no rejections');

-- ---------------------------------------------------------------------------
-- 5. 'merge' that WOULD need a same-date merge (a live row on a date an
--    existing live row of different provenance occupies) rejects the whole
--    BATCH with a typed error, and writes nothing.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.bulk_import_entries(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-11-03',
      'tz', 'UTC', 'flow', 'heavy', 'source_id', 'merge-collide', 'updated_at', now()::text)), 'merge')$$,
    pg_temp.job1(), tests.ulid(925), tests.ulid(900)),
  '22023', null, 'a merge-mode batch containing a same-date collision is rejected with a typed error');
select is(
  (select count(*) from public.day_entries where id = tests.ulid(925)),
  0::bigint, 'the rejected merge-mode batch wrote nothing');
select is(
  (select count(*) from public.day_entries
    where profile_id = tests.ulid(900) and local_date = '2026-11-03' and deleted_at is null),
  1::bigint, 'the pre-existing live row is untouched by the refused merge-mode batch');

-- ---------------------------------------------------------------------------
-- 6. The collision check is provenance-aware: a row sharing the SAME
--    (source, source_id) as the existing live row on a date is the
--    (source, source_id) arbiter's job, not a same-date collision -- so
--    merge mode proceeds and updates that row.
-- ---------------------------------------------------------------------------
insert into r select 'merge_arbiter', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(926), 'profile_id', tests.ulid(900), 'local_date', '2026-11-04',
    'tz', 'UTC', 'flow', 'super_heavy', 'source_id', 'arb-src', 'updated_at', now()::text)
), 'merge');
select is(pg_temp.resp('merge_arbiter') -> 'updated', '1'::jsonb,
  'a merge-mode row sharing (source, source_id) with the live row updates it (no collision)');
select is((select flow from public.day_entries where source_id = 'arb-src'), 'super_heavy',
  'the arbiter update applied the incoming row''s values');
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(900) and source_id = 'arb-src'),
  1::bigint, 'no duplicate row was created for the arbiter path');

-- ---------------------------------------------------------------------------
-- 7. Same source, DIFFERENT source_id, on the same occupied date IS a
--    collision -- merge mode refuses the batch.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.bulk_import_entries(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-11-04',
      'tz', 'UTC', 'flow', 'heavy', 'source_id', 'arb-other', 'updated_at', now()::text)), 'merge')$$,
    pg_temp.job1(), tests.ulid(927), tests.ulid(900)),
  '22023', null, 'a different source_id on the same occupied date is a collision in merge mode');

-- ---------------------------------------------------------------------------
-- 8. A tombstone row never contests a date: merge mode lands it on a date
--    an existing live row occupies (nothing is landing live).
-- ---------------------------------------------------------------------------
insert into r select 'merge_tombstone', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(928), 'profile_id', tests.ulid(900), 'local_date', '2026-11-06',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'merge-tomb', 'updated_at', now()::text,
    'deleted_at', now()::text)
), 'merge');
select is(pg_temp.resp('merge_tombstone') -> 'inserted', '1'::jsonb,
  'a merge-mode tombstone row on an occupied date is inserted');
select is(pg_temp.resp('merge_tombstone') -> 'rejected', '[]'::jsonb,
  'the merge-mode tombstone row is not rejected as a date collision');
select isnt((select deleted_at from public.day_entries where id = tests.ulid(928)), null,
  'the merge-mode tombstone row is stored as a tombstone (deleted_at set)');

-- ---------------------------------------------------------------------------
-- 9. Within-batch duplicate dates are a separate, pre-existing rule:
--    merge mode still rejects the later row per row (documented deviation
--    from sync_push's sequential processing; rejecting is the safe
--    direction and loses nothing).
-- ---------------------------------------------------------------------------
insert into r select 'merge_dup_date', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(930), 'profile_id', tests.ulid(900), 'local_date', '2026-11-07',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'merge-dup-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(931), 'profile_id', tests.ulid(900), 'local_date', '2026-11-07',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'merge-dup-2', 'updated_at', now()::text)
), 'merge');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('merge_dup_date') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 1),
  'duplicate date in batch', 'merge mode still rejects the later duplicate-date row per row');
select is(pg_temp.resp('merge_dup_date') -> 'inserted', '1'::jsonb,
  'merge mode still lands the earlier duplicate-date row');

-- ---------------------------------------------------------------------------
-- 10. Tombstone revival through merge mode: a live row sharing
--     (source, source_id) with a tombstoned row revives it.
-- ---------------------------------------------------------------------------
insert into r select 'merge_revive', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(932), 'profile_id', tests.ulid(900), 'local_date', '2026-11-08',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'rev-src', 'updated_at', now()::text)
), 'merge');
select is(pg_temp.resp('merge_revive') -> 'revived', '1'::jsonb,
  'merge mode revives the tombstoned row sharing (source, source_id)');
select is((select deleted_at from public.day_entries where id = tests.ulid(917)), null,
  'the revived row is live again');

-- ---------------------------------------------------------------------------
-- 11. An update-by-id row that MOVES onto an occupied date is also a
--     same-date collision in merge mode (the update is not exempt).
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$select public.bulk_import_entries(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L, 'local_date', '2026-11-09',
      'tz', 'UTC', 'flow', 'heavy', 'source_id', 'move-src', 'updated_at', now()::text)), 'merge')$$,
    pg_temp.job1(), tests.ulid(915), tests.ulid(900)),
  '22023', null, 'a merge-mode update-by-id moving onto an occupied date is refused');

select tests.clear_authentication();

select * from finish();
rollback;
