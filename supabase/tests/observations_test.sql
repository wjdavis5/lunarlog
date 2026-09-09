-- Coverage for Issue #240 (P0, epic: Tracking Model): public.observations,
-- its RLS/grants/indexes, sync_push's third p_observations parameter (round
-- trip, tombstone payload clearing, same-date (category, code) collision
-- resolution, the per-day cap), the tags->observations backfill's
-- idempotency, and delete_account_data()'s new observations count.
begin;
select plan(41);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.resolved_row(n text, p_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'id' = p_id limit 1 $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape: table, RLS, indexes, grants.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'observations');
select tests.rls_forced('public', 'observations');

select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'observations'),
  3, 'observations carries exactly the three documented policies (select, insert, update)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'observations' and roles <> '{authenticated}'),
  0, 'every observations policy is scoped to authenticated');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'observations' and cmd = 'DELETE'),
  0, 'observations has no DELETE policy (tombstone-only, matching every other synced table)');

select is(
  (select has_table_privilege('authenticated', 'public.observations', 'DELETE')),
  false, 'authenticated holds no DELETE grant on observations');
select is(
  (select has_table_privilege('anon', 'public.observations', 'SELECT')),
  false, 'anon holds no SELECT grant on observations');

select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'observations'
      and indexname = 'observations_profile_id_local_date_idx'),
  1, 'index (profile_id, local_date) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'observations'
      and indexname = 'observations_profile_id_category_local_date_idx'),
  1, 'index (profile_id, category, local_date) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'observations'
      and indexname = 'observations_server_version_idx'),
  1, 'index (server_version) exists');

select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'observations' and t.tgname = 'observations_after_change_signal'),
  1, 'observations fires touch_sync_signal() -- no new Realtime-published table needed');
select is(
  (select count(*)::integer from pg_publication_rel pr
     join pg_class c on c.oid = pr.prrelid
     join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and c.relname = 'observations'),
  0, 'observations itself is never added to the supabase_realtime publication');

-- ---------------------------------------------------------------------------
-- Fixtures: two independent families (RLS isolation), each with one profile
-- and one day entry to attach observations to.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('other_parent');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(801), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(802), tests.ulid(801), '2026-09-05', 'UTC', 'medium', '2026-09-05T09:00:00Z');

select tests.authenticate_as('other_parent');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(851), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(852), tests.ulid(851), '2026-09-05', 'UTC', 'none', '2026-09-05T09:00:00Z');

-- ---------------------------------------------------------------------------
-- Round trip: mom logs a pain/migraine observation via sync_push.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_obs_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(810), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'migraine',
    'intensity', 3, 'source', 'manual', 'updated_at', '2026-09-05T10:00:00Z')));

select is((select category from public.observations where id = tests.ulid(810)), 'pain',
  'round trip: category persisted');
select is((select code from public.observations where id = tests.ulid(810)), 'migraine',
  'round trip: code persisted');
select is((select intensity from public.observations where id = tests.ulid(810)), 3::smallint,
  'round trip: intensity persisted');
select is((select day_entry_id from public.observations where id = tests.ulid(810)), tests.ulid(802),
  'round trip: day_entry_id persisted');
select is((select logged_by_user_id from public.observations where id = tests.ulid(810)),
  tests.get_supabase_uid('mom'), 'round trip: logged_by_user_id stamped from the caller');
select isnt((select server_version from public.observations where id = tests.ulid(810)), 0::bigint,
  'round trip: server_version stamped by the shared trigger');

-- A 2-argument sync_push call (no p_observations at all) still works,
-- exercising the default and proving the old overload was truly replaced,
-- not merely shadowed.
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb)$$,
  'a 2-argument sync_push call still works (p_observations defaults to an empty array)');

-- ---------------------------------------------------------------------------
-- Tombstone: soft-deleting the row clears its payload but keeps category
-- (issue #240 migration header's documented exception) and every identity
-- column.
-- ---------------------------------------------------------------------------
insert into r select 'mom_obs_tombstone', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(810), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain',
    'updated_at', '2026-09-05T11:00:00Z', 'deleted_at', '2026-09-05T11:00:00Z')));

select is((select code from public.observations where id = tests.ulid(810)), null,
  'tombstone clears code');
select is((select intensity from public.observations where id = tests.ulid(810)), null,
  'tombstone clears intensity');
select is((select category from public.observations where id = tests.ulid(810)), 'pain',
  'tombstone keeps category (not free text, no natural sentinel unlike flow''s none)');
select is((select profile_id from public.observations where id = tests.ulid(810)), tests.ulid(801),
  'tombstone keeps profile_id');
select isnt((select deleted_at from public.observations where id = tests.ulid(810)), null,
  'tombstone sets deleted_at');
select throws_ok(
  format('update public.observations set code = %L where id = %L', 'x', tests.ulid(810)),
  '23514', null, 'the tombstone-payload CHECK rejects a direct write that reintroduces payload on a tombstone');

-- ---------------------------------------------------------------------------
-- Two-family isolation (RLS).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('other_parent');
select is((select count(*) from public.observations where profile_id = tests.ulid(801)),
  0::bigint, 'other_parent selects zero of mom''s observations');
-- Role-check failures inside sync_push's per-row loop are caught by its own
-- `exception when others` handler and reported as an opaque rejected entry
-- (matching the existing day_entries precedent: sync_push_test.sql's
-- "batch with one foreign ULID" case) - not raised out of the call as a
-- thrown exception. Only outer, pre-loop failures (no session, malformed
-- top-level array) ever reach the caller as a Postgres exception.
insert into r select 'other_parent_sneak', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(890), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'sneak',
    'updated_at', '2026-09-05T12:00:00Z')));
select is(
  pg_temp.resp('other_parent_sneak') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(890), 'rejected', true),
  'other_parent''s push onto mom''s profile is an opaque rejected entry, not applied');
select is(
  (select count(*) from public.observations where id = tests.ulid(890)),
  0::bigint, 'the sneak observation was never stored');

-- ---------------------------------------------------------------------------
-- Same-date collision on (profile_id, local_date, category, code): two
-- brand-new rows created independently (e.g. offline on two devices) for
-- the same option collapse to one live row, the loser becoming a
-- payload-free tombstone -- the child-table analogue of merge_tag_arrays'
-- set union (there is no array to union here; see the migration header).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'collision_a', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(820), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-06', 'tz', 'UTC', 'category', 'mood', 'code', 'anxious',
    'updated_at', '2026-09-06T10:00:00Z')));
insert into r select 'collision_b', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(821), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-06', 'tz', 'UTC', 'category', 'mood', 'code', 'anxious',
    'updated_at', '2026-09-06T11:00:00Z')));

select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(801) and local_date = '2026-09-06'
      and category = 'mood' and code = 'anxious' and deleted_at is null),
  1::bigint, 'a same-date (category, code) collision leaves exactly one live row');
select is((select deleted_at from public.observations where id = tests.ulid(820)) is not null, true,
  'the older (losing) row becomes a tombstone');
select is((select code from public.observations where id = tests.ulid(820)), null,
  'the losing row''s tombstone carries no payload');
select is((select deleted_at from public.observations where id = tests.ulid(821)), null,
  'the newer (winning) row stays live');

-- A repeat category+code logged deliberately (e.g. two sexual-activity
-- entries the same day) is NOT collapsed when it round-trips as an UPDATE
-- to an already-known id -- only a brand-new id colliding with an
-- already-live sibling triggers the dedup above. Simulate a second,
-- distinct, deliberately-repeated observation by giving it a different code
-- so it is unambiguously a second entry, not a collision candidate.
insert into r select 'deliberate_repeat', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(822), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-06', 'tz', 'UTC', 'category', 'sex', 'code', 'protected',
    'updated_at', '2026-09-06T12:00:00Z')));
insert into r select 'deliberate_repeat_2', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(823), 'day_entry_id', tests.ulid(802), 'profile_id', tests.ulid(801),
    'local_date', '2026-09-06', 'tz', 'UTC', 'category', 'sex', 'code', 'unprotected',
    'updated_at', '2026-09-06T12:05:00Z')));
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(801) and local_date = '2026-09-06'
      and category = 'sex' and deleted_at is null),
  2::bigint, 'two distinct codes logged the same day/category both stay live (repetition is not collapsed)');

-- ---------------------------------------------------------------------------
-- Per-day cap: the RPC rejects a live observation once a profile/day already
-- holds 200 (the 201st distinct code in one push is rejected; the first 200
-- succeed). A CHECK cannot count sibling rows, hence this is enforced here.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(803), tests.ulid(801), '2026-09-07', 'UTC', 'none', '2026-09-07T09:00:00Z');
insert into r select 'cap_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  (select jsonb_agg(jsonb_build_object(
     'id', tests.ulid(1000 + i), 'day_entry_id', tests.ulid(803), 'profile_id', tests.ulid(801),
     'local_date', '2026-09-07', 'tz', 'UTC', 'category', 'other', 'code', 'opt_' || i,
     'updated_at', '2026-09-07T10:00:00Z'))
   from generate_series(0, 200) i));

select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(801) and local_date = '2026-09-07' and deleted_at is null),
  200::bigint, 'exactly 200 live observations exist for the day once the cap is hit');
select is(array_length(pg_temp.rejected_ids('cap_push'), 1), 1,
  'exactly one row (the 201st) is rejected once the per-day cap of 200 is reached');

-- ---------------------------------------------------------------------------
-- Backfill idempotency: day_entries.tags -> observations, re-run verbatim.
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, updated_at)
values (tests.ulid(804), tests.ulid(801), '2026-09-08', 'UTC', 'light', '["cramps", "not_a_known_tag"]'::jsonb, '2026-09-08T09:00:00Z');

insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':' || tag.value)), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz,
  coalesce(cat.category, 'other'), tag.value, 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
cross join lateral jsonb_array_elements_text(de.tags) as tag(value)
left join (values
  ('cramps', 'pain'), ('headache', 'pain'), ('back_pain', 'pain'), ('breast_tenderness', 'pain'),
  ('bloating', 'body'), ('acne', 'body'), ('nausea', 'body'), ('fatigue', 'body'), ('dizziness', 'body'),
  ('irritable', 'mood'), ('sad', 'mood'), ('anxious', 'mood'), ('calm', 'mood'), ('energetic', 'mood'), ('sensitive', 'mood'),
  ('sleep_trouble', 'other'), ('cravings', 'other')
) as cat(code, category) on cat.code = tag.value
where de.id = tests.ulid(804) and de.deleted_at is null
on conflict (id) do nothing;

select is(
  (select category from public.observations where code = 'cramps' and day_entry_id = tests.ulid(804)),
  'pain', 'backfill maps a known tag code to its client-side TagCategory');
select is(
  (select category from public.observations where code = 'not_a_known_tag' and day_entry_id = tests.ulid(804)),
  'other', 'backfill falls back to category ''other'' for a tag code outside the curated taxonomy');
select is(
  (select count(*) from public.observations where day_entry_id = tests.ulid(804)),
  2::bigint, 'the backfill inserted exactly one observation per tag element');

-- Re-run the identical backfill statement a second time (simulating a local
-- `db reset` replaying this migration from scratch): row count is unchanged.
insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':' || tag.value)), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz,
  coalesce(cat.category, 'other'), tag.value, 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
cross join lateral jsonb_array_elements_text(de.tags) as tag(value)
left join (values
  ('cramps', 'pain'), ('headache', 'pain'), ('back_pain', 'pain'), ('breast_tenderness', 'pain'),
  ('bloating', 'body'), ('acne', 'body'), ('nausea', 'body'), ('fatigue', 'body'), ('dizziness', 'body'),
  ('irritable', 'mood'), ('sad', 'mood'), ('anxious', 'mood'), ('calm', 'mood'), ('energetic', 'mood'), ('sensitive', 'mood'),
  ('sleep_trouble', 'other'), ('cravings', 'other')
) as cat(code, category) on cat.code = tag.value
where de.id = tests.ulid(804) and de.deleted_at is null
on conflict (id) do nothing;

select is(
  (select count(*) from public.observations where day_entry_id = tests.ulid(804)),
  2::bigint, 'the backfill is idempotent: re-running it verbatim inserts nothing new');

-- ---------------------------------------------------------------------------
-- delete_account_data() reports an observations count and actually removes
-- the caller's rows (both directly-deleted and cascade-covered).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('other_parent');
insert into r select 'other_parent_obs_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(870), 'day_entry_id', tests.ulid(852), 'profile_id', tests.ulid(851),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'headache',
    'updated_at', '2026-09-05T10:00:00Z')));
insert into r select 'other_parent_deletion', public.delete_account_data();

select ok(
  (pg_temp.resp('other_parent_deletion') ->> 'observations')::bigint >= 1,
  'delete_account_data() reports a nonzero observations count for a caller who owns some');
select is(
  (select count(*) from public.observations where profile_id = tests.ulid(851)),
  0::bigint, 'delete_account_data() actually removed the caller''s observations');

select * from finish();
rollback;
