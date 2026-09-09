-- Regression coverage for Issue #167 (P0, epic: Import):
-- bulk_import_entries RPC and the import_jobs table for large imports
-- (supabase/migrations/20260908190000_bulk_import.sql). Reuses the
-- create_supabase_user / authenticate_as handshake and the pg_temp
-- snapshot idiom already established in sync_push_test.sql and
-- guardian_sync_push_test.sql. delete_account_data()/export_account_data()
-- coverage for import_jobs lives in account_deletion_test.sql/
-- export_account_data_test.sql, not duplicated here; rls_isolation_test.sql
-- carries the shared PUBLIC/anon-privilege and authenticated-DELETE/
-- TRUNCATE catalog guards import_jobs joins.
begin;
select plan(87);

create temp table r (name text primary key, v jsonb);
-- service_role too: section 4 below reads pg_temp.job1() (backed by this
-- table) for the first time while role = service_role, and a first-time
-- read under a role that never read it before needs its own grant (a role
-- that already read the same key once under `authenticated` earlier does
-- not hit this -- see account_deletion_test.sql's identical grant note).
grant all on table r to authenticated, service_role;
create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into r values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('mom');   -- owner / primary_guardian
select tests.create_supabase_user('dad');   -- co_parent
select tests.create_supabase_user('nanny'); -- caregiver
select tests.create_supabase_user('doc');   -- viewer
select tests.create_supabase_user('eve');   -- non-guardian (attacker)

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(700), 'Riley', true, 0, '2026-09-08T00:00:00Z', '2026-09-08T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(700), 'co_parent', 'Dad',
  '7000000000000000000000000000000000000000000000000000000000000700', 48
);
select public.create_guardian_invitation(
  tests.ulid(700), 'caregiver', 'Nanny',
  '7000000000000000000000000000000000000000000000000000000000000701', 48
);
select public.create_guardian_invitation(
  tests.ulid(700), 'viewer', 'Doc',
  '7000000000000000000000000000000000000000000000000000000000000702', 48
);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '7000000000000000000000000000000000000000000000000000000000000700', 'Dad');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad'), tests.ulid(700), true);

select tests.authenticate_as('nanny');
select public.accept_guardian_invitation(
  '7000000000000000000000000000000000000000000000000000000000000701', 'Nanny');

select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  '7000000000000000000000000000000000000000000000000000000000000702', 'Doc');

select tests.authenticate_as('mom');
with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(700), 'clue_import', 'pending', 10, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job1', to_jsonb((select id from ins)::text));
create function pg_temp.job1() returns uuid language sql as
  $$ select (pg_temp.resp('job1') #>> '{}')::uuid $$;

-- ---------------------------------------------------------------------------
-- 1. Function shape: bulk_import_entries exists, security definer,
--    search_path = '', authenticated executes, PUBLIC/anon revoked.
-- ---------------------------------------------------------------------------
select ok(
  exists(select 1 from pg_proc where proname = 'bulk_import_entries' and pronamespace = 'public'::regnamespace),
  'public.bulk_import_entries() exists');
select is(
  (select prosecdef from pg_proc where proname = 'bulk_import_entries' and pronamespace = 'public'::regnamespace),
  true, 'bulk_import_entries is security definer');
select ok(
  exists(
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'bulk_import_entries' and pronamespace = 'public'::regnamespace
       and c.setting = 'search_path=""'),
  'bulk_import_entries pins search_path to exactly empty');
select ok(
  has_function_privilege('authenticated', 'public.bulk_import_entries(uuid,jsonb)', 'execute'),
  'authenticated can execute bulk_import_entries');
select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'bulk_import_entries'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint, 'PUBLIC and anon hold no EXECUTE on bulk_import_entries');
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.bulk_import_entries('00000000-0000-0000-0000-000000000000'::uuid, '[]'::jsonb)$$,
  '42501', null, 'anon cannot execute bulk_import_entries');
select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 2. import_jobs table shape: RLS enabled/forced, three policies scoped to
--    authenticated, no client DELETE policy or grant at all.
-- ---------------------------------------------------------------------------
select tests.rls_forced('public', 'import_jobs');
select is((select count(*) from pg_policies where schemaname = 'public' and tablename = 'import_jobs'),
  3::bigint, 'import_jobs carries exactly three policies (select/insert/update)');
select is((select count(*) from pg_policies
            where schemaname = 'public' and tablename = 'import_jobs' and roles <> '{authenticated}'),
  0::bigint, 'every import_jobs policy is scoped to authenticated');

select tests.authenticate_as('mom');
select throws_ok(
  format('delete from public.import_jobs where id = %L', pg_temp.job1()),
  '42501', 'permission denied for table import_jobs',
  'authenticated cannot delete an import_jobs row -- no DELETE grant exists at all');
select tests.clear_authentication();
select is((select count(*) from information_schema.role_table_grants
            where table_schema = 'public' and table_name = 'import_jobs'
              and grantee = 'authenticated' and privilege_type = 'DELETE'),
  0::bigint, 'authenticated holds no DELETE privilege on import_jobs');

-- ---------------------------------------------------------------------------
-- 3. Realtime publication: import_jobs is never published, and the
--    reconcile guard actively reverts a simulated Studio-toggle drift
--    rather than skipping an already-published table (mirroring the
--    day_entries/profiles/observations drill in realtime_publication_test.sql).
-- ---------------------------------------------------------------------------
select ok(
  not exists(select 1 from pg_catalog.pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'import_jobs'),
  'import_jobs is not published to Realtime');

alter publication supabase_realtime add table public.import_jobs;
select ok(
  exists(select 1 from pg_catalog.pg_publication_tables
          where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'import_jobs'),
  'setup: import_jobs is published whole-row (simulated Studio toggle)');
select lives_ok(
  $$select public.reconcile_realtime_publication()$$,
  'reconcile_realtime_publication() runs without error against the drifted import_jobs state');
select ok(
  not exists(select 1 from pg_catalog.pg_publication_tables
              where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'import_jobs'),
  'reconcile_realtime_publication() reverts a whole-row import_jobs publish (Issue #167)');

-- ---------------------------------------------------------------------------
-- 4. day_entries.import_id / observations.import_id FK enforcement against
--    import_jobs, left unconstrained by 20260908170000_import_provenance.sql.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select throws_ok(
  format(
    $sql$insert into public.day_entries (id, profile_id, local_date, tz, flow, import_id, updated_at)
         values (%L, %L, '2026-09-08', 'UTC', 'none', '11111111-1111-1111-1111-111111111111'::uuid, now())$sql$,
    tests.ulid(710), tests.ulid(700)),
  '23503', null, 'a day_entries row cannot reference a nonexistent import_jobs id');
insert into public.day_entries (id, profile_id, local_date, tz, flow, import_id, updated_at)
values (tests.ulid(711), tests.ulid(700), '2026-09-09', 'UTC', 'none', pg_temp.job1(), now());
select is((select import_id from public.day_entries where id = tests.ulid(711)), pg_temp.job1(),
  'a day_entries row can reference a real import_jobs id');
select tests.clear_authentication();
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
delete from public.import_jobs where id = pg_temp.job1();
select is((select import_id from public.day_entries where id = tests.ulid(711)), null,
  'deleting the referenced import_jobs row sets day_entries.import_id to null (on delete set null)');

-- Recreate the job (it was deleted above to prove the FK's on-delete
-- behavior) for the rest of this file.
select tests.authenticate_as('mom');
with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(700), 'clue_import', 'pending', 2010, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job1', to_jsonb((select id from ins)::text));

-- ---------------------------------------------------------------------------
-- 5. Authorization: a non-guardian and a viewer are both rejected; the
--    guardian-write-role check mirrors sync_push's own (v_caller_role is
--    null or 'viewer' => reject) via is_guardian_with_roles().
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
select throws_ok(
  $$select public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(720), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
      'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text)))$$,
  '42501', null, 'a non-guardian cannot call bulk_import_entries for this profile');

select tests.authenticate_as('doc');
select throws_ok(
  $$select public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(721), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
      'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text)))$$,
  '42501', null, 'a viewer cannot call bulk_import_entries (viewer holds no write role)');

-- ---------------------------------------------------------------------------
-- 6. Per-row validation: same allowlist/length/enum shape sync_push
--    applies, evaluated set-based rather than row-by-row.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'bad_rows', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  -- profile_id mismatch (a different profile's ULID)
  jsonb_build_object('id', tests.ulid(730), 'profile_id', tests.ulid(701), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text),
  -- unknown key (source is never accepted per-row)
  jsonb_build_object('id', tests.ulid(731), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'none', 'source', 'clue_import', 'updated_at', now()::text),
  -- out-of-set flow
  jsonb_build_object('id', tests.ulid(732), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'gushing', 'updated_at', now()::text),
  -- malformed local_date
  jsonb_build_object('id', tests.ulid(733), 'profile_id', tests.ulid(700), 'local_date', 'not-a-date',
    'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text),
  -- note over 2000 chars
  jsonb_build_object('id', tests.ulid(734), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'none', 'note', repeat('n', 2001), 'updated_at', now()::text),
  -- missing updated_at
  jsonb_build_object('id', tests.ulid(735), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'none')
));
select is(jsonb_array_length(pg_temp.resp('bad_rows') -> 'rejected'), 6,
  'all six malformed rows are rejected, none aborts the batch');
select is(pg_temp.resp('bad_rows') -> 'inserted', '0'::jsonb, 'nothing is inserted from an all-rejected batch');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'profile_id does not match import job',
  'row 0 is rejected for a profile_id mismatch against the job');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 1),
  'row carries an unknown key',
  'row 1 (carrying source) is rejected as an unknown key -- source/import_id come from the job, never the payload');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 2),
  'flow is not a known level', 'row 2 is rejected for an out-of-set flow');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 3),
  'local_date is not an ISO calendar date', 'row 3 is rejected for a malformed local_date');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 4),
  'note exceeds 2000 characters', 'row 4 is rejected for an over-length note');
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 5),
  'updated_at is required', 'row 5 is rejected for a missing updated_at');

-- ---------------------------------------------------------------------------
-- 7. 2000-row cap: a typed invalid_parameter_value error, not a generic one.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.bulk_import_entries(pg_temp.job1(),
      (select jsonb_agg(jsonb_build_object(
         'id', tests.ulid(20000 + g), 'profile_id', tests.ulid(700), 'local_date', '2026-09-10',
         'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text))
         from generate_series(1, 2001) g))$$,
  '22023', null, 'a 2001-row batch is rejected with a typed invalid_parameter_value error');

-- ---------------------------------------------------------------------------
-- 8. Set-based upsert: insert, then re-run the same batch unchanged ->
--    updates, no duplicates. dad (alert_on_log) is eligible for a caregiver
--    alert on an ordinary write, proving enqueue_caregiver_alerts() no-ops
--    for imported rows (notification_outbox gains zero rows). sync_signals
--    is touched exactly once per call, proven by a temporary counting
--    trigger rather than assumed from the code shape.
-- ---------------------------------------------------------------------------
-- A trigger on a permanent table cannot call a pg_temp function (Postgres
-- forbids it - the function would vanish at session end while the trigger
-- on the permanent table would not), so this counting function lives in
-- public, not pg_temp; it and its trigger are undone regardless by this
-- whole test file's closing `rollback` like every other DDL probe here
-- (mirroring tags_element_length_check_test.sql's drop/recreate idiom).
-- `authenticated` holds no CREATE on schema public, so this DDL runs back
-- on the session's own (superuser) role, same as the file's own setup.
select tests.clear_authentication();
create temp table signal_touches (profile_id text);
grant all on table signal_touches to authenticated, service_role;
create function public.issue167_log_signal_touch() returns trigger
language plpgsql as $$
begin
  insert into signal_touches (profile_id) values (new.profile_id);
  return new;
end;
$$;
create trigger log_signal_touch_trg
  after insert or update on public.sync_signals
  for each row execute function public.issue167_log_signal_touch();

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
-- Section 4's direct (non-bulk-import) day_entries insert legitimately
-- enqueued one ordinary alert for dad -- clear it here so the assertion
-- below isolates bulk_import_entries' own zero-growth property, not
-- leftover state from an earlier, unrelated write.
delete from public.notification_outbox where profile_id = tests.ulid(700);
select is((select count(*) from public.notification_outbox where profile_id = tests.ulid(700)),
  0::bigint, 'setup: notification_outbox starts empty for the profile');
select tests.authenticate_as('mom');

insert into r select 'first_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(740), 'profile_id', tests.ulid(700), 'local_date', '2026-09-11',
    'tz', 'UTC', 'flow', 'light', 'tags', jsonb_build_array('cramps'), 'source_id', 'clue-1', 'updated_at', '2026-09-11T10:00:00Z'),
  jsonb_build_object('id', tests.ulid(741), 'profile_id', tests.ulid(700), 'local_date', '2026-09-12',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'clue-2', 'updated_at', '2026-09-12T10:00:00Z'),
  jsonb_build_object('id', tests.ulid(742), 'profile_id', tests.ulid(700), 'local_date', '2026-09-13',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'clue-3', 'updated_at', '2026-09-13T10:00:00Z')
));
select is(pg_temp.resp('first_batch') -> 'inserted', '3'::jsonb, 'first run: three rows inserted');
select is(pg_temp.resp('first_batch') -> 'updated', '0'::jsonb, 'first run: nothing updated yet');
select is(pg_temp.resp('first_batch') -> 'rejected', '[]'::jsonb, 'first run: nothing rejected');
select is((select source from public.day_entries where id = tests.ulid(740)), 'clue_import',
  'source comes from the job record, never the payload');
select is((select import_id from public.day_entries where id = tests.ulid(740)), pg_temp.job1(),
  'import_id comes from p_import_id, stamped on every written row');

insert into r select 'second_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(740), 'profile_id', tests.ulid(700), 'local_date', '2026-09-11',
    'tz', 'UTC', 'flow', 'spotting', 'tags', jsonb_build_array('cramps'), 'source_id', 'clue-1', 'updated_at', '2026-09-11T11:00:00Z'),
  jsonb_build_object('id', tests.ulid(741), 'profile_id', tests.ulid(700), 'local_date', '2026-09-12',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'clue-2', 'updated_at', '2026-09-12T11:00:00Z'),
  jsonb_build_object('id', tests.ulid(742), 'profile_id', tests.ulid(700), 'local_date', '2026-09-13',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'clue-3', 'updated_at', '2026-09-13T11:00:00Z')
));
select is(pg_temp.resp('second_batch') -> 'inserted', '0'::jsonb, 're-run: nothing newly inserted');
select is(pg_temp.resp('second_batch') -> 'updated', '3'::jsonb, 're-run: all three rows updated, not duplicated');
select is((select count(*) from public.day_entries where profile_id = tests.ulid(700) and source_id = 'clue-1'),
  1::bigint, 're-running the same import upserts one row, not two');
select is((select flow from public.day_entries where id = tests.ulid(740)), 'spotting',
  'the upsert applied the second run''s values, proving it is a real update not a no-op');

select is((select count(*) from signal_touches where profile_id = tests.ulid(700)), 2::bigint,
  'sync_signals is touched exactly once per bulk_import_entries call (two calls above, two touches, not six)');
-- notification_outbox carries no authenticated policy or grant at all (by
-- design -- see 20260906220000_notification_outbox.sql's header), so this
-- check runs as service_role, mirroring notification_outbox_test.sql.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select is((select count(*) from public.notification_outbox where profile_id = tests.ulid(700)),
  0::bigint, 'notification_outbox gains zero rows from a bulk import, even with an eligible alert_on_log guardian (dad)');

-- Back to the session's own (superuser) role to drop the probe trigger/
-- function -- `authenticated` holds no privilege to drop either.
select tests.clear_authentication();
drop trigger log_signal_touch_trg on public.sync_signals;
drop function public.issue167_log_signal_touch();
select tests.authenticate_as('mom');

-- ---------------------------------------------------------------------------
-- 9. Tombstone revival: an existing tombstoned imported row is revived by
--    an incoming live row sharing (profile_id, source, source_id) -- the
--    exact shape import_provenance_test.sql pinned, which sync_push cannot
--    do (it resolves strictly by id).
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, profile_id, local_date, tz, flow, source, source_id, updated_at)
values (tests.ulid(750), tests.ulid(700), '2026-09-14', 'UTC', 'light', 'clue_import', 'clue-revive', now());
update public.day_entries
   set deleted_at = now(), flow = 'none', tags = '[]'::jsonb, note = null, updated_at = now(),
       last_modified_by_user_id = tests.get_supabase_uid('mom')
 where id = tests.ulid(750);
select isnt((select deleted_at from public.day_entries where id = tests.ulid(750)), null,
  'setup: the row is tombstoned before the revival import runs');

insert into r select 'revive_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(751), 'profile_id', tests.ulid(700), 'local_date', '2026-09-14',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'clue-revive', 'updated_at', '2026-09-14T12:00:00Z')
));
select is(pg_temp.resp('revive_batch') -> 'revived', '1'::jsonb, 'the tombstoned row is reported as revived');
select is(pg_temp.resp('revive_batch') -> 'inserted', '0'::jsonb, 'revival is not double-counted as an insert');
select is((select deleted_at from public.day_entries where id = tests.ulid(750)), null,
  'the revived row is live again (deleted_at cleared)');
select is((select flow from public.day_entries where id = tests.ulid(750)), 'heavy',
  'the revive applied the new import run''s values');

-- ---------------------------------------------------------------------------
-- 10. Review-fix coverage: per-row rejection covers every day_entries
--     constraint and never aborts the chunk (tz, same-date collision
--     against a live row, an in-batch duplicate date, and the
--     source_id-required idempotency contract), and a tombstone row is
--     forced to the empty payload rather than validated/rejected.
-- ---------------------------------------------------------------------------

-- (a) a bad-tz row is rejected while the rest of the batch lands.
insert into r select 'tz_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(760), 'profile_id', tests.ulid(700), 'local_date', '2026-09-21',
    'tz', 'Mars/Cydonia', 'flow', 'none', 'source_id', 'tz-bad', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(761), 'profile_id', tests.ulid(700), 'local_date', '2026-09-22',
    'tz', 'UTC', 'flow', 'none', 'source_id', 'tz-good', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('tz_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'tz is not a known time zone', 'a row with an unrecognized tz is rejected, not aborting the batch');
select is(pg_temp.resp('tz_batch') -> 'inserted', '1'::jsonb, 'the other row in the same batch still lands');

-- (b) a tombstone row with a non-'none' flow/tags/note lands as an
--     empty-payload tombstone -- forced, not rejected.
insert into r select 'tombstone_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(762), 'profile_id', tests.ulid(700), 'local_date', '2026-09-23',
    'tz', 'UTC', 'flow', 'heavy', 'tags', jsonb_build_array('cramps'), 'note', 'stale note',
    'source_id', 'tomb-1', 'updated_at', now()::text, 'deleted_at', now()::text)
));
select is(pg_temp.resp('tombstone_batch') -> 'rejected', '[]'::jsonb,
  'a tombstone row with a stale payload is not rejected');
select is((select flow from public.day_entries where id = tests.ulid(762)), 'none',
  'the tombstone lands with flow forced to none');
select is((select tags from public.day_entries where id = tests.ulid(762)), '[]'::jsonb,
  'the tombstone lands with tags forced to empty');
select is((select note from public.day_entries where id = tests.ulid(762)), null,
  'the tombstone lands with note forced to null');
select isnt((select deleted_at from public.day_entries where id = tests.ulid(762)), null,
  'the row is stored as a tombstone (deleted_at set)');

-- (c) an import row landing on a date with an existing LIVE, differently-
--     provenanced (manual) row is rejected with the reason, and the rest
--     of the batch still lands.
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(763), tests.ulid(700), '2026-09-24', 'UTC', 'light', now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));
insert into r select 'collision_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(764), 'profile_id', tests.ulid(700), 'local_date', '2026-09-24',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'collide-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(765), 'profile_id', tests.ulid(700), 'local_date', '2026-09-25',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'collide-2', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('collision_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'date already has a live entry', 'an import row landing on a date with a live manual row is rejected');
select is(pg_temp.resp('collision_batch') -> 'inserted', '1'::jsonb, 'the other row in the same batch still lands');
select is((select flow from public.day_entries where id = tests.ulid(763)), 'light',
  'the pre-existing manual live row is untouched by the rejected import row');

-- (d) two rows in the same batch sharing local_date (different source_id)
--     -- the first (by ordinality) is kept, the later is rejected.
insert into r select 'dup_date_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(766), 'profile_id', tests.ulid(700), 'local_date', '2026-09-26',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'dupdate-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(767), 'profile_id', tests.ulid(700), 'local_date', '2026-09-26',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'dupdate-2', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('dup_date_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 1),
  'duplicate date in batch', 'the second row sharing a local_date in the same batch is rejected');
select is(pg_temp.resp('dup_date_batch') -> 'inserted', '1'::jsonb, 'the first row on that date still lands');
select is(
  (select source_id from public.day_entries where profile_id = tests.ulid(700) and local_date = '2026-09-26'),
  'dupdate-1', 'the earlier row (by ordinality) is the one kept');

-- (e) a row with no existing id match and no source_id is rejected --
--     required at the RPC boundary so a retry can never fall back to a
--     bare insert that collides on id alone.
insert into r select 'no_source_id_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(768), 'profile_id', tests.ulid(700), 'local_date', '2026-09-27',
    'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(769), 'profile_id', tests.ulid(700), 'local_date', '2026-09-28',
    'tz', 'UTC', 'flow', 'none', 'source_id', 'has-source', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('no_source_id_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'source_id is required for idempotent import', 'a brand-new row with no source_id is rejected');
select is(pg_temp.resp('no_source_id_batch') -> 'inserted', '1'::jsonb,
  'the row that does carry a source_id still lands');

-- ---------------------------------------------------------------------------
-- 11. Review fix: the guardian/role check runs before the job-status
--     disclosure -- a non-guardian probing a completed job gets 42501
--     (learns nothing about its status), not the invalid_parameter_value
--     "already completed" message a guardian would see.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(700), 'clue_import', 'completed', 1, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('completed_job', to_jsonb((select id from ins)::text));
create function pg_temp.completed_job() returns uuid language sql as
  $$ select (pg_temp.resp('completed_job') #>> '{}')::uuid $$;

select tests.authenticate_as('eve');
select throws_ok(
  $$select public.bulk_import_entries(pg_temp.completed_job(), jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(770), 'profile_id', tests.ulid(700), 'local_date', '2026-09-29',
      'tz', 'UTC', 'flow', 'none', 'updated_at', now()::text)))$$,
  '42501', null,
  'a non-guardian probing a completed job gets 42501, not the status message');
select tests.authenticate_as('mom');

-- ---------------------------------------------------------------------------
-- 12. A full 2000-row batch must complete within the caller's ordinary 8s
--     role statement_timeout -- the RPC never actually raised its own (a
--     `set local statement_timeout = '60s'` here was a documented no-op,
--     removed; see the migration's header). Latency is recorded via diag()
--     for the PR body.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
create temp table perf_timing (started_at timestamptz, finished_at timestamptz, inserted int);
with batch as (
  select jsonb_agg(jsonb_build_object(
    'id', tests.ulid(21000 + g), 'profile_id', tests.ulid(700), 'local_date', (date '2015-01-01' + g)::text,
    'tz', 'UTC', 'flow', 'none', 'source_id', 'perf-' || g::text, 'updated_at', now()::text)) as rows
    from generate_series(1, 2000) g
),
timed as (
  select clock_timestamp() as t0, public.bulk_import_entries(pg_temp.job1(), batch.rows) as resp, clock_timestamp() as t1
    from batch
)
insert into perf_timing select t0, t1, (resp ->> 'inserted')::int from timed;
select is((select inserted from perf_timing), 2000, 'a full 2000-row batch inserts all 2000 rows');
select diag(
  'bulk_import_entries 2000-row batch latency: '
  || round(extract(epoch from (select finished_at - started_at from perf_timing)) * 1000)::text
  || ' ms'
);
select cmp_ok(
  (select extract(epoch from (finished_at - started_at)) from perf_timing)::float8, '<', 8::float8,
  'the 2000-row batch must complete within the caller''s 8s role timeout');

-- ---------------------------------------------------------------------------
-- 13. Round-2 review fix #1 (blocking): re-importing the same source_id
--     under a FRESH import_jobs row (a new job B, not job1/job A) is not
--     treated as "different provenance" -- the live-row collision check
--     now compares only (source, source_id), never import_id, so this
--     succeeds as an ordinary update/revive with zero rejections instead
--     of every row being rejected as a date collision.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'jobA_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(781), 'profile_id', tests.ulid(700), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'reimport-1', 'updated_at', '2026-10-01T09:00:00Z')
));
select is(pg_temp.resp('jobA_batch') -> 'inserted', '1'::jsonb, 'setup: job A inserts the row live');

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(700), 'clue_import', 'pending', 1, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('jobB', to_jsonb((select id from ins)::text));
create function pg_temp.jobB() returns uuid language sql as
  $$ select (pg_temp.resp('jobB') #>> '{}')::uuid $$;

insert into r select 'jobB_batch', public.bulk_import_entries(pg_temp.jobB(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(782), 'profile_id', tests.ulid(700), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'reimport-1', 'updated_at', '2026-10-01T10:00:00Z')
));
select is(pg_temp.resp('jobB_batch') -> 'rejected', '[]'::jsonb,
  're-importing the same source_id under a fresh job B has zero rejections');
select is(pg_temp.resp('jobB_batch') -> 'updated', '1'::jsonb,
  're-importing under a new job updates the existing live row by (source, source_id), not rejects it');
select is((select count(*) from public.day_entries where profile_id = tests.ulid(700) and source_id = 'reimport-1'),
  1::bigint, 'no duplicate row is created across the two jobs');
select is((select flow from public.day_entries where profile_id = tests.ulid(700) and source_id = 'reimport-1'),
  'medium', 'job B''s values won the update');
select is((select import_id from public.day_entries where profile_id = tests.ulid(700) and source_id = 'reimport-1'),
  pg_temp.jobB(), 'the row now carries job B''s import_id (fresh provenance stamped on the update)');

-- ---------------------------------------------------------------------------
-- 14. Round-2 review fix #4: a tombstone and a live row sharing the same
--     local_date in one batch both proceed -- tombstones no longer occupy
--     the (profile_id, local_date) duplicate-date partition.
-- ---------------------------------------------------------------------------
insert into r select 'tombstone_and_live_same_date', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(783), 'profile_id', tests.ulid(700), 'local_date', '2026-10-02',
    'tz', 'UTC', 'flow', 'none', 'source_id', 'tomb-samedate', 'updated_at', now()::text, 'deleted_at', now()::text),
  jsonb_build_object('id', tests.ulid(784), 'profile_id', tests.ulid(700), 'local_date', '2026-10-02',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'live-samedate', 'updated_at', now()::text)
));
select is(pg_temp.resp('tombstone_and_live_same_date') -> 'rejected', '[]'::jsonb,
  'a tombstone and a live row sharing a local_date in one batch both proceed, neither rejected as a duplicate date');
select is(pg_temp.resp('tombstone_and_live_same_date') -> 'inserted', '2'::jsonb,
  'both the tombstone and the live row insert -- neither is rejected as a duplicate date collision');
select isnt((select deleted_at from public.day_entries where id = tests.ulid(783)), null,
  'the tombstone row lands as a tombstone');
select is((select deleted_at from public.day_entries where id = tests.ulid(784)), null,
  'the live row lands live, undisturbed by sharing a local_date with the tombstone');

-- ---------------------------------------------------------------------------
-- 15. Round-2 review fix #5: a row whose id already exists on ANOTHER
--     profile is rejected (`id belongs to another profile`), not silently
--     dropped (previously: not written, not counted, not rejected).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
-- user_id has no default under service_role (it defaults to auth.uid(),
-- which is null with no JWT claims set), and day_entries_profile_fk is a
-- composite FK on (profile_id, user_id) -> profiles (id, user_id), so
-- both rows stamp user_id explicitly as mom's uid to satisfy it.
insert into public.profiles (id, user_id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(705), tests.get_supabase_uid('mom'), 'OtherProfile', true, 0, '2026-09-08T00:00:00Z', '2026-09-08T00:00:00Z');
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(780), tests.get_supabase_uid('mom'), tests.ulid(705), '2026-09-08', 'UTC', 'none', now(),
  tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));
select tests.authenticate_as('mom');
insert into r select 'cross_profile_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(780), 'profile_id', tests.ulid(700), 'local_date', '2026-09-30',
    'tz', 'UTC', 'flow', 'none', 'source_id', 'cross-1', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('cross_profile_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'id belongs to another profile', 'a row whose id exists on a different profile is rejected, not dropped');
select is(pg_temp.resp('cross_profile_batch') -> 'inserted', '0'::jsonb, 'the cross-profile row is not inserted');
select is((select profile_id from public.day_entries where id = tests.ulid(780)), tests.ulid(705),
  'the other profile''s row is untouched');

-- ---------------------------------------------------------------------------
-- 16. Round-2 review fix #6: the update-by-id path applies sync_push's own
--     `? key` containment guard to source_id/import_id -- an update-by-id
--     row that omits source_id must not null the stored idempotency key.
-- ---------------------------------------------------------------------------
insert into r select 'contain_setup', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(785), 'profile_id', tests.ulid(700), 'local_date', '2026-10-03',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'contain-1', 'updated_at', '2026-10-03T09:00:00Z')
));
select is((select source_id from public.day_entries where id = tests.ulid(785)), 'contain-1',
  'setup: the row lands with its source_id stamped');
select is((select import_id from public.day_entries where id = tests.ulid(785)), pg_temp.job1(),
  'setup: the row lands with job1''s import_id stamped');

insert into r select 'contain_omit_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(785), 'profile_id', tests.ulid(700), 'local_date', '2026-10-03',
    'tz', 'UTC', 'flow', 'heavy', 'updated_at', '2026-10-03T10:00:00Z')
));
select is(pg_temp.resp('contain_omit_batch') -> 'updated', '1'::jsonb,
  'an update-by-id row omitting source_id still updates the row');
select is((select flow from public.day_entries where id = tests.ulid(785)), 'heavy',
  'the omitted-key update still applies the other fields');
select is((select source_id from public.day_entries where id = tests.ulid(785)), 'contain-1',
  'omitting source_id on an update-by-id row does not null the stored idempotency key');
select is((select import_id from public.day_entries where id = tests.ulid(785)), pg_temp.job1(),
  'omitting source_id on an update-by-id row does not null the stored import_id either');

-- ---------------------------------------------------------------------------
-- 17. Round-2 review fix #8: bulk_import_safe_date rejects the 'infinity'
--     magic value instead of casting it -- proven end-to-end through the
--     RPC's per-row rejection path.
-- ---------------------------------------------------------------------------
insert into r select 'infinity_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(786), 'profile_id', tests.ulid(700), 'local_date', 'infinity',
    'tz', 'UTC', 'flow', 'none', 'source_id', 'infinity-1', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('infinity_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'local_date is not an ISO calendar date', 'a local_date of ''infinity'' is rejected, not cast to the infinity date');

-- ---------------------------------------------------------------------------
-- 18. Review follow-up (PR #335, issue #247): the flow allow-list gained
--     super_heavy/not_bleeding (20260908200000_flow_model.sql, item 6) --
--     proven end-to-end through the RPC, not just the day_entries CHECK.
-- ---------------------------------------------------------------------------
insert into r select 'flow247_batch', public.bulk_import_entries(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(787), 'profile_id', tests.ulid(700), 'local_date', '2026-10-04',
    'tz', 'UTC', 'flow', 'super_heavy', 'source_id', 'flow247-super-heavy', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(788), 'profile_id', tests.ulid(700), 'local_date', '2026-10-05',
    'tz', 'UTC', 'flow', 'not_bleeding', 'source_id', 'flow247-not-bleeding', 'updated_at', now()::text)
));
select is(pg_temp.resp('flow247_batch') -> 'rejected', '[]'::jsonb,
  'a super_heavy row and a not_bleeding row are not rejected by the RPC''s flow allow-list');
select is((select flow from public.day_entries where id = tests.ulid(787)), 'super_heavy',
  'a super_heavy row imports and is stored verbatim');
select is((select flow from public.day_entries where id = tests.ulid(788)), 'not_bleeding',
  'a not_bleeding row imports and is stored verbatim');

select tests.clear_authentication();

select * from finish();
rollback;
