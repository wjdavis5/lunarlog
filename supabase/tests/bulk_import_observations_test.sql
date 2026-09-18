-- Regression coverage for Issue #328 (epic: Import):
-- public.bulk_import_observations(uuid, jsonb), the observations half of
-- the bulk import path #167 opened for day_entries
-- (supabase/migrations/20260918130000_bulk_import_observations.sql).
-- Reuses the create_supabase_user / authenticate_as / pg_temp snapshot
-- idiom already established in bulk_import_test.sql. General
-- bulk_import_entries coverage lives there and is not duplicated here.
begin;
select plan(41);

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
values (tests.ulid(800), 'Riley', true, 0, '2026-09-08T00:00:00Z', '2026-09-08T00:00:00Z');

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(800), 'clue_import', 'pending', 100, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job1', to_jsonb((select id from ins)::text));
create function pg_temp.job1() returns uuid language sql as
  $$ select (pg_temp.resp('job1') #>> '{}')::uuid $$;

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(800), 'healthkit', 'pending', 1, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job_healthkit', to_jsonb((select id from ins)::text));
create function pg_temp.job_healthkit() returns uuid language sql as
  $$ select (pg_temp.resp('job_healthkit') #>> '{}')::uuid $$;

with ins as (
  insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
  values (tests.ulid(800), 'clue_import', 'completed', 1, tests.get_supabase_uid('mom'))
  returning id
)
select pg_temp.snapshot('job_done', to_jsonb((select id from ins)::text));
create function pg_temp.job_done() returns uuid language sql as
  $$ select (pg_temp.resp('job_done') #>> '{}')::uuid $$;

-- Day-entry fixtures. authenticated holds no INSERT grant on day_entries
-- (Issue #201), so these land as service_role with auth.uid() still mom.
select set_config('role', 'service_role', true);
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(820), tests.ulid(800), '2026-09-11', 'UTC', 'none', now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(821), tests.ulid(800), '2026-09-12', 'UTC', 'none', now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));
update public.day_entries
   set deleted_at = now(), flow = 'none', tags = '[]'::jsonb, note = null, pms = false, updated_at = now()
 where id = tests.ulid(821);
select set_config('role', 'authenticated', true);

-- ---------------------------------------------------------------------------
-- 1. Function shape: exists, security definer, search_path = '',
--    authenticated executes, PUBLIC/anon revoked.
-- ---------------------------------------------------------------------------
select ok(
  exists(select 1 from pg_proc where proname = 'bulk_import_observations' and pronamespace = 'public'::regnamespace),
  'public.bulk_import_observations() exists');
select is(
  (select prosecdef from pg_proc where proname = 'bulk_import_observations' and pronamespace = 'public'::regnamespace),
  true, 'bulk_import_observations is security definer');
select ok(
  exists(
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'bulk_import_observations' and pronamespace = 'public'::regnamespace
       and c.setting = 'search_path=""'),
  'bulk_import_observations pins search_path to exactly empty');
select ok(
  has_function_privilege('authenticated', 'public.bulk_import_observations(uuid,jsonb)', 'execute'),
  'authenticated can execute bulk_import_observations');
select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'bulk_import_observations'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint, 'PUBLIC and anon hold no EXECUTE on bulk_import_observations');
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.bulk_import_observations('00000000-0000-0000-0000-000000000000'::uuid, '[]'::jsonb)$$,
  '42501', null, 'anon cannot execute bulk_import_observations');
select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 2. Authorization: a non-guardian is refused before the job-status check
--    (probing a completed job still gets 42501, not the status message).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
select throws_ok(
  format($$select public.bulk_import_observations(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L, 'local_date', '2026-09-20',
      'tz', 'UTC', 'category', 'pain', 'updated_at', now()::text)))$$,
    pg_temp.job1(), tests.ulid(840), tests.ulid(820), tests.ulid(800)),
  '42501', null, 'a non-guardian cannot call bulk_import_observations for this profile');
select throws_ok(
  format($$select public.bulk_import_observations(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L, 'local_date', '2026-09-20',
      'tz', 'UTC', 'category', 'pain', 'updated_at', now()::text)))$$,
    pg_temp.job_done(), tests.ulid(841), tests.ulid(820), tests.ulid(800)),
  '42501', null, 'a non-guardian probing a completed job gets 42501, not the status message');

-- ---------------------------------------------------------------------------
-- 3. Boundary: a job source outside observations' own closed set (healthkit
--    is a day_entries-only label) is refused with a clear typed error.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.bulk_import_observations(%L::uuid, jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L, 'local_date', '2026-09-20',
      'tz', 'UTC', 'category', 'pain', 'source_id', 'hk-1', 'updated_at', now()::text)))$$,
    pg_temp.job_healthkit(), tests.ulid(842), tests.ulid(820), tests.ulid(800)),
  '22023', null, 'a healthkit job cannot write observations (clear typed error, not a CHECK abort)');

-- ---------------------------------------------------------------------------
-- 4. Happy path: insert, with source/import_id from the job, and local_date
--    derived from observed_at/tz (the supplied local_date loses when a real
--    instant is present -- #180).
-- ---------------------------------------------------------------------------
insert into r select 'first_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(850), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-11', 'observed_at', '2026-09-11T08:30:00Z', 'tz', 'UTC',
    'category', 'pain', 'code', 'cramps', 'source_id', 'obs-1', 'updated_at', '2026-09-11T09:00:00Z'),
  jsonb_build_object('id', tests.ulid(851), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-01-01', 'observed_at', '2026-09-12T08:30:00Z', 'tz', 'UTC',
    'category', 'body', 'code', 'bloating', 'source_id', 'obs-2', 'updated_at', '2026-09-12T09:00:00Z')
));
select is(pg_temp.resp('first_batch') -> 'inserted', '2'::jsonb, 'first run: two rows inserted');
select is(pg_temp.resp('first_batch') -> 'rejected', '[]'::jsonb, 'first run: nothing rejected');
select is((select source from public.observations where id = tests.ulid(850)), 'clue_import',
  'source comes from the job record, never the payload');
select is((select import_id from public.observations where id = tests.ulid(850)), pg_temp.job1(),
  'import_id comes from p_import_id, stamped on every written row');
select is((select local_date::text from public.observations where id = tests.ulid(851)), '2026-09-12',
  'local_date is derived from observed_at/tz, overriding the supplied local_date');

-- ---------------------------------------------------------------------------
-- 5. Idempotent re-run: same ids -> updates, no duplicates.
-- ---------------------------------------------------------------------------
insert into r select 'second_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(850), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-11', 'observed_at', '2026-09-11T08:30:00Z', 'tz', 'UTC',
    'category', 'pain', 'code', 'cramps', 'source_id', 'obs-1', 'value_text', 'second', 'updated_at', '2026-09-11T10:00:00Z'),
  jsonb_build_object('id', tests.ulid(851), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-12', 'observed_at', '2026-09-12T08:30:00Z', 'tz', 'UTC',
    'category', 'body', 'code', 'bloating', 'source_id', 'obs-2', 'updated_at', '2026-09-12T10:00:00Z')
));
select is(pg_temp.resp('second_batch') -> 'inserted', '0'::jsonb, 're-run: nothing newly inserted');
select is(pg_temp.resp('second_batch') -> 'updated', '2'::jsonb, 're-run: both rows updated by id, not duplicated');
select is((select count(*) from public.observations where profile_id = tests.ulid(800) and source_id = 'obs-1'),
  1::bigint, 're-running the same import upserts one row, not two');
select is((select value_text from public.observations where id = tests.ulid(850)), 'second',
  'the upsert applied the second run''s values, proving it is a real update not a no-op');

-- ---------------------------------------------------------------------------
-- 6. Tombstone revival: a new id sharing (profile_id, source, source_id)
--    with an existing tombstoned row revives it in place.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, source, source_id, updated_at, deleted_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(852), tests.ulid(820), tests.ulid(800), '2026-09-13', 'UTC', 'clue_import', 'obs-revive',
   '2026-09-13T09:00:00Z', '2026-09-13T09:30:00Z', tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));
select is((select deleted_at is not null from public.observations where id = tests.ulid(852)), true,
  'setup: the revive fixture row is tombstoned');

insert into r select 'revive_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(853), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-13', 'tz', 'UTC', 'category', 'mood', 'code', 'calm',
    'source_id', 'obs-revive', 'updated_at', '2026-09-13T11:00:00Z')
));
select is(pg_temp.resp('revive_batch') -> 'revived', '1'::jsonb, 'the tombstoned row is reported as revived');
select is(pg_temp.resp('revive_batch') -> 'inserted', '0'::jsonb, 'revival is not double-counted as an insert');
select is((select deleted_at from public.observations where id = tests.ulid(852)), null,
  'the revived row is live again (deleted_at cleared)');
select is((select category from public.observations where id = tests.ulid(852)), 'mood',
  'the revive applied the new import run''s values');

-- ---------------------------------------------------------------------------
-- 7. Tombstone row: a stale payload is forced empty rather than rejected,
--    and provenance survives (issue #159/#224 precedent).
-- ---------------------------------------------------------------------------
insert into r select 'tombstone_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(854), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-14', 'tz', 'UTC', 'category', 'pain', 'code', 'cramps',
    'value_num', 7, 'value_text', 'stale', 'intensity', 4, 'excluded', true,
    'source_id', 'obs-tomb', 'updated_at', '2026-09-14T09:00:00Z', 'deleted_at', '2026-09-14T10:00:00Z')
));
select is(pg_temp.resp('tombstone_batch') -> 'rejected', '[]'::jsonb,
  'a tombstone row with a stale payload is not rejected');
select is((select category from public.observations where id = tests.ulid(854)), null,
  'the tombstone lands with category forced to null');
select is((select value_num from public.observations where id = tests.ulid(854)), null,
  'the tombstone lands with value_num forced to null');
select is((select source_id from public.observations where id = tests.ulid(854)), 'obs-tomb',
  'provenance (source_id) survives the tombstone');

-- ---------------------------------------------------------------------------
-- 8. source_id required per row: a brand-new row with no source_id is
--    rejected, while a row that carries one still lands.
-- ---------------------------------------------------------------------------
insert into r select 'no_source_id_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(855), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-15', 'tz', 'UTC', 'category', 'pain', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(856), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-16', 'tz', 'UTC', 'category', 'pain', 'source_id', 'has-source', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('no_source_id_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'source_id is required for idempotent import', 'a brand-new row with no source_id is rejected');
select is(pg_temp.resp('no_source_id_batch') -> 'inserted', '1'::jsonb,
  'the row that does carry a source_id still lands');

-- ---------------------------------------------------------------------------
-- 9. A row carrying an unknown key (source/import_id come from the job) is
--    rejected per row, not aborting the batch.
-- ---------------------------------------------------------------------------
insert into r select 'unknown_key_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(857), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-17', 'tz', 'UTC', 'category', 'pain', 'source', 'clue_import',
    'source_id', 'unknown-1', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('unknown_key_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'row carries an unknown key', 'a row carrying `source` is rejected as an unknown key');

-- ---------------------------------------------------------------------------
-- 10. Same-date (category, code) collision against an already-live row is
--     rejected per row; a row with different content on the same date lands.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, source, source_id, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(858), tests.ulid(820), tests.ulid(800), '2026-09-18', 'UTC', 'pain', 'headache',
   'manual', 'collide-existing', now(), tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));

insert into r select 'collision_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(859), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-18', 'tz', 'UTC', 'category', 'pain', 'code', 'headache',
    'source_id', 'collide-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(860), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-18', 'tz', 'UTC', 'category', 'pain', 'code', 'cramps',
    'source_id', 'collide-2', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('collision_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'date already has a live observation for this (category, code)',
  'a live row colliding on (category, code) with an already-live observation is rejected');
select is(pg_temp.resp('collision_batch') -> 'inserted', '1'::jsonb,
  'the other row in the same batch still lands');
select is((select count(*) from public.observations where profile_id = tests.ulid(800) and local_date = '2026-09-18'),
  2::bigint, 'the pre-existing live row is untouched by the rejected import row');

-- ---------------------------------------------------------------------------
-- 11. Within-batch duplicate (category, code): the earlier row (by position)
--     wins, the later is rejected.
-- ---------------------------------------------------------------------------
insert into r select 'dup_content_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(861), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-19', 'tz', 'UTC', 'category', 'mood', 'code', 'calm',
    'source_id', 'dup-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(862), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-19', 'tz', 'UTC', 'category', 'mood', 'code', 'calm',
    'source_id', 'dup-2', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('dup_content_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 1),
  'duplicate (category, code) in batch', 'the later row sharing (category, code) in the same batch is rejected');
select is(pg_temp.resp('dup_content_batch') -> 'inserted', '1'::jsonb,
  'the earlier row on that (category, code) still lands');
select is(
  (select source_id from public.observations where profile_id = tests.ulid(800) and local_date = '2026-09-19'),
  'dup-1', 'the earlier row (by ordinality) is the one kept');

-- ---------------------------------------------------------------------------
-- 12. A live observation that would point at a tombstoned day entry is
--     rejected per row (#524).
-- ---------------------------------------------------------------------------
insert into r select 'tombstoned_day_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(863), 'day_entry_id', tests.ulid(821), 'profile_id', tests.ulid(800),
    'local_date', '2026-09-21', 'tz', 'UTC', 'category', 'pain', 'code', 'under-dead-day',
    'source_id', 'dead-day-1', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('tombstoned_day_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'day_entry_id is tombstoned; observation cannot be live',
  'a live observation under a tombstoned day entry is rejected');

-- ---------------------------------------------------------------------------
-- 13. Per-day 200 cap: with 200 live observations already on a day, another
--     live row is rejected (not written), while a tombstone on that day is
--     still allowed.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, source, source_id, updated_at,
   logged_by_user_id, last_modified_by_user_id)
select tests.ulid(30000 + g), tests.ulid(820), tests.ulid(800), '2026-10-01', 'UTC', 'cap', 'cap-' || g,
       'manual', 'cap-src-' || g, now(), tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')
from generate_series(1, 200) g;

insert into r select 'cap_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(864), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-10-01', 'tz', 'UTC', 'category', 'cap', 'code', 'cap-new',
    'source_id', 'cap-overflow', 'updated_at', now()::text)
));
select is(
  (select r_item ->> 'reason' from jsonb_array_elements(pg_temp.resp('cap_batch') -> 'rejected') r_item
    where (r_item ->> 'row_index')::int = 0),
  'day is at the 200-observation cap', 'a live row pushing a full day over 200 is rejected');
select is(
  (select count(*) from public.observations where profile_id = tests.ulid(800) and local_date = '2026-10-01' and deleted_at is null),
  200::bigint, 'the over-cap row was not written; the day still holds exactly 200 live rows');

-- ---------------------------------------------------------------------------
-- 14. sync_signals is touched exactly once per call, not once per row --
--     proven by a temporary counting trigger rather than assumed.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
create temp table signal_touches (profile_id text);
grant all on table signal_touches to authenticated, service_role;
create function public.issue328_log_signal_touch() returns trigger
language plpgsql as $$
begin
  insert into signal_touches (profile_id) values (new.profile_id);
  return new;
end;
$$;
create trigger log_signal_touch_trg
  after insert or update on public.sync_signals
  for each row execute function public.issue328_log_signal_touch();

select tests.authenticate_as('mom');
insert into r select 'signal_batch', public.bulk_import_observations(pg_temp.job1(), jsonb_build_array(
  jsonb_build_object('id', tests.ulid(865), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-10-02', 'tz', 'UTC', 'category', 'pain', 'code', 'sig-1',
    'source_id', 'signal-1', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(866), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-10-03', 'tz', 'UTC', 'category', 'pain', 'code', 'sig-2',
    'source_id', 'signal-2', 'updated_at', now()::text),
  jsonb_build_object('id', tests.ulid(867), 'day_entry_id', tests.ulid(820), 'profile_id', tests.ulid(800),
    'local_date', '2026-10-04', 'tz', 'UTC', 'category', 'pain', 'code', 'sig-3',
    'source_id', 'signal-3', 'updated_at', now()::text)
));
select is(pg_temp.resp('signal_batch') -> 'inserted', '3'::jsonb, 'setup: the three-row signal batch lands');
select is((select count(*) from signal_touches where profile_id = tests.ulid(800)), 1::bigint,
  'sync_signals is touched exactly once per call (three rows, one touch)');

select tests.clear_authentication();
drop trigger log_signal_touch_trg on public.sync_signals;
drop function public.issue328_log_signal_touch();

select * from finish();
rollback;
