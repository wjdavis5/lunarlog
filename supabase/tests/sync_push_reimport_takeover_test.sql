-- Coverage for 20261006163211_sync_push_reimported_record_takeover.sql
-- (Issue #1576, bug/P2): a health-store record re-imported after its
-- deleted row has left the phone (the phone sweeps clean tombstones two
-- days after they sync) arrives under a fresh id the server cannot map to
-- the deleted row. The partial unique index covers deleted rows, so the
-- insert broke the index, the row sat rejected on the phone forever, and
-- the day showed on that phone and nowhere else.
--
-- The fix: on the day_entries and observations write paths, when the
-- incoming row carries a non-null source_id and a DIFFERENT row holding
-- the same (profile_id, source, source_id) is itself deleted, sync_push
-- releases that holder's key (source_id := null) and proceeds -- the live
-- row takes the record over, the tombstone stays (other devices still
-- learn of the deletion by id). A LIVE holder under another id is left
-- alone, so the write still collides and the row is still rejected.
begin;
select plan(33);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('mom_1576');
select tests.authenticate_as('mom_1576');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(810), 'display_name', 'Riley', 'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);

-- ---------------------------------------------------------------------------
-- 1. Day entries, insert path: a re-imported record takes over from its
--    deleted row (issue case 1 -- "Remove imported data", import again
--    after the tombstone has left the phone).
-- ---------------------------------------------------------------------------
-- The imported day, as first synced.
insert into r select 'de_live', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(820), 'profile_id', tests.ulid(810), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'light', 'source', 'healthkit', 'source_id', 'rec-A',
    'updated_at', '2026-09-10T10:00:00Z')));
select is(pg_temp.resp('de_live') -> 'rejected', '[]'::jsonb,
  'setup: the imported day is accepted');

-- "Remove imported data": the row is tombstoned. The tombstone push omits
-- the provenance keys entirely, pinning the #159 rule the fix relies on
-- (a key-omitting delete must not clear the stored key).
insert into r select 'de_gone', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(820), 'profile_id', tests.ulid(810), 'local_date', '2026-09-10',
    'tz', 'UTC', 'updated_at', '2026-09-11T10:00:00Z', 'deleted_at', '2026-09-11T10:00:00Z')));
select is(pg_temp.resp('de_gone') -> 'rejected', '[]'::jsonb,
  'setup: the tombstone is accepted');
select is((select source_id from public.day_entries where id = tests.ulid(820)), 'rec-A',
  'setup: the deleted row keeps its record key (issue #159)');

-- The re-import, under a fresh id (the phone no longer knows the old one).
insert into r select 'de_reimport', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(821), 'profile_id', tests.ulid(810), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'medium', 'source', 'healthkit', 'source_id', 'rec-A',
    'updated_at', '2026-09-12T10:00:00Z')));
select is(pg_temp.resp('de_reimport') -> 'rejected', '[]'::jsonb,
  'a re-imported day is accepted even though a deleted row held its key');
select is((select source_id from public.day_entries where id = tests.ulid(821)), 'rec-A',
  'the live row holds the record key');
select is((select deleted_at is not null from public.day_entries where id = tests.ulid(820)), true,
  'the old row is still a tombstone (it keeps its id)');
select is((select source_id from public.day_entries where id = tests.ulid(820)), null,
  'the old row released the key');

-- ---------------------------------------------------------------------------
-- 2. Day entries: a LIVE row holding the key under another id still
--    rejects -- the takeover only ever releases a deleted holder.
-- ---------------------------------------------------------------------------
insert into r select 'de_live_conflict', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(822), 'profile_id', tests.ulid(810), 'local_date', '2026-09-11',
    'tz', 'UTC', 'flow', 'heavy', 'source', 'healthkit', 'source_id', 'rec-A',
    'updated_at', '2026-09-13T10:00:00Z')));
select is(jsonb_array_length(pg_temp.resp('de_live_conflict') -> 'rejected'), 1,
  'a second live row claiming the same record is still rejected');
select is((select count(*) from public.day_entries where id = tests.ulid(822)), 0::bigint,
  'the colliding row never lands');
-- The incoming row would have WON the same-date resolver against the
-- live holder (it is newer); the rejection rolls that resolver work
-- back with the row, and the takeover (ahead of the resolver, and
-- deleted-holders-only) never released the live holder's key.
select is((select deleted_at is null from public.day_entries where id = tests.ulid(821)), true,
  'the rejected push did not disturb the live holder, resolver included');
select is((select source_id from public.day_entries where id = tests.ulid(821)), 'rec-A',
  'the live holder keeps its record key through the rejected push');

-- ---------------------------------------------------------------------------
-- 3. Day entries, update path: a hand-logged day taking on an imported
--    value (issue case 2) is accepted too, with the same deleted-only
--    release -- and still rejected against a live holder.
-- ---------------------------------------------------------------------------
-- A second record, imported then deleted, holding rec-B.
insert into r select 'de_b_live', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(823), 'profile_id', tests.ulid(810), 'local_date', '2026-09-14',
    'tz', 'UTC', 'flow', 'light', 'source', 'healthkit', 'source_id', 'rec-B',
    'updated_at', '2026-09-14T10:00:00Z')));
insert into r select 'de_b_gone', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(823), 'profile_id', tests.ulid(810), 'local_date', '2026-09-14',
    'tz', 'UTC', 'updated_at', '2026-09-15T10:00:00Z', 'deleted_at', '2026-09-15T10:00:00Z')));
-- The hand-logged day she kept.
insert into r select 'de_hand', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(824), 'profile_id', tests.ulid(810), 'local_date', '2026-09-16',
    'tz', 'UTC', 'flow', 'none', 'tags', '["cramps"]'::jsonb,
    'updated_at', '2026-09-16T10:00:00Z')));
-- The next import fills the hand-logged day's empty flow and keys it.
insert into r select 'de_hand_filled', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(824), 'profile_id', tests.ulid(810), 'local_date', '2026-09-16',
    'tz', 'UTC', 'flow', 'light', 'tags', '["cramps"]'::jsonb,
    'source', 'healthkit', 'source_id', 'rec-B',
    'updated_at', '2026-09-17T10:00:00Z')));
select is(pg_temp.resp('de_hand_filled') -> 'rejected', '[]'::jsonb,
  'a hand-logged day taking on an imported value is accepted');
select is((select source_id from public.day_entries where id = tests.ulid(824)), 'rec-B',
  'the hand-logged row now holds the record key');
select is((select source_id from public.day_entries where id = tests.ulid(823)), null,
  'the deleted row released the key on the update path too');
-- ... but not against the live holder of rec-A.
insert into r select 'de_hand_live_conflict', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(824), 'profile_id', tests.ulid(810), 'local_date', '2026-09-16',
    'tz', 'UTC', 'flow', 'light', 'tags', '["cramps"]'::jsonb,
    'source', 'healthkit', 'source_id', 'rec-A',
    'updated_at', '2026-09-18T10:00:00Z')));
select is(jsonb_array_length(pg_temp.resp('de_hand_live_conflict') -> 'rejected'), 1,
  'an update claiming a live row''s record is still rejected');
select is((select source_id from public.day_entries where id = tests.ulid(824)), 'rec-B',
  'the rejected update changed nothing -- the row keeps its own key');

-- ---------------------------------------------------------------------------
-- 4. Observations, insert path: the same takeover, and the same live
--    rejection. (Days carry `healthkit`, the entries on them
--    `apple_health` on an iPhone.)
-- ---------------------------------------------------------------------------
insert into r select 'ob_parent', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(830), 'profile_id', tests.ulid(810), 'local_date', '2026-09-20',
    'tz', 'UTC', 'flow', 'none', 'updated_at', '2026-09-20T10:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(840), 'day_entry_id', tests.ulid(830), 'profile_id', tests.ulid(810),
    'local_date', '2026-09-20', 'tz', 'UTC', 'category', 'mood', 'code', 'low',
    'source', 'apple_health', 'source_id', 'obs-A', 'updated_at', '2026-09-20T10:00:00Z')));
select is(pg_temp.resp('ob_parent') -> 'rejected', '[]'::jsonb,
  'setup: parent day and imported entry accepted');

insert into r select 'ob_gone', public.sync_push(
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(840), 'day_entry_id', tests.ulid(830), 'profile_id', tests.ulid(810),
    'local_date', '2026-09-20', 'tz', 'UTC',
    'updated_at', '2026-09-21T10:00:00Z', 'deleted_at', '2026-09-21T10:00:00Z')));
select is((select source_id from public.observations where id = tests.ulid(840)), 'obs-A',
  'setup: the deleted entry keeps its record key');

insert into r select 'ob_reimport', public.sync_push(
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(841), 'day_entry_id', tests.ulid(830), 'profile_id', tests.ulid(810),
    'local_date', '2026-09-20', 'tz', 'UTC', 'category', 'mood', 'code', 'low',
    'source', 'apple_health', 'source_id', 'obs-A', 'updated_at', '2026-09-22T10:00:00Z')));
select is(pg_temp.resp('ob_reimport') -> 'rejected', '[]'::jsonb,
  'a re-imported entry is accepted even though a deleted row held its key');
select is((select source_id from public.observations where id = tests.ulid(841)), 'obs-A',
  'the live entry holds the record key');
select is((select source_id from public.observations where id = tests.ulid(840)), null,
  'the deleted entry released the key');
select is((select deleted_at is not null from public.observations where id = tests.ulid(840)), true,
  'the old entry is still a tombstone');

insert into r select 'ob_live_conflict', public.sync_push(
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(842), 'day_entry_id', tests.ulid(830), 'profile_id', tests.ulid(810),
    'local_date', '2026-09-20', 'tz', 'UTC', 'category', 'mood', 'code', 'low',
    'source', 'apple_health', 'source_id', 'obs-A', 'updated_at', '2026-09-23T10:00:00Z')));
select is(jsonb_array_length(pg_temp.resp('ob_live_conflict') -> 'rejected'), 1,
  'a second live entry claiming the same record is still rejected');
-- Even though the incoming row would have WON the same-date (category,
-- code) dedup (it is newer), the whole push rolls back: the dedup's
-- tombstone of the live holder is undone with the rejected row, and the
-- takeover (which runs ahead of the dedup, never behind it) never
-- misreads that fresh tombstone as a deleted holder.
select is((select deleted_at is null from public.observations where id = tests.ulid(841)), true,
  'the rejected push did not disturb the live holder, dedup included');
select is((select source_id from public.observations where id = tests.ulid(841)), 'obs-A',
  'the live holder keeps its record key through the rejected push');

-- ---------------------------------------------------------------------------
-- 5. bulk_import_entries still revives a deleted row that kept its key
--    (the reliance the issue asks to confirm), and after a takeover a
--    re-import updates the new live row instead.
-- ---------------------------------------------------------------------------
insert into public.import_jobs (profile_id, source, status, total_rows, created_by)
values (tests.ulid(810), 'healthkit', 'pending', 10, tests.get_supabase_uid('mom_1576'));
create function pg_temp.job_id() returns uuid language sql as
  $$ select id from public.import_jobs
      where profile_id = tests.ulid(810) and source = 'healthkit'
      order by created_at desc limit 1 $$;

-- A file import, then its deletion, then the same file again: revives.
insert into r select 'bi_first', public.bulk_import_entries(pg_temp.job_id(),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(850), 'profile_id', tests.ulid(810), 'local_date', '2026-09-24',
    'tz', 'UTC', 'flow', 'light', 'source_id', 'rec-C', 'updated_at', '2026-09-24T10:00:00Z')));
select is((pg_temp.resp('bi_first') ->> 'inserted')::int, 1,
  'file import inserts the new record');
insert into r select 'bi_gone', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(850), 'profile_id', tests.ulid(810), 'local_date', '2026-09-24',
    'tz', 'UTC', 'updated_at', '2026-09-25T10:00:00Z', 'deleted_at', '2026-09-25T10:00:00Z')));
insert into r select 'bi_reimport', public.bulk_import_entries(pg_temp.job_id(),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(851), 'profile_id', tests.ulid(810), 'local_date', '2026-09-24',
    'tz', 'UTC', 'flow', 'medium', 'source_id', 'rec-C', 'updated_at', '2026-09-26T10:00:00Z')));
select is((pg_temp.resp('bi_reimport') ->> 'revived')::int, 1,
  'a re-import revives the deleted row that kept its key');
select is((select deleted_at from public.day_entries where id = tests.ulid(850)), null,
  'the revived row is live again under its own id');

-- After the section-1 takeover (deleted 820 keyless, live 821 keyed
-- rec-A), the same file updates the live row instead of reviving.
insert into r select 'bi_takeover', public.bulk_import_entries(pg_temp.job_id(),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(852), 'profile_id', tests.ulid(810), 'local_date', '2026-09-10',
    'tz', 'UTC', 'flow', 'heavy', 'source_id', 'rec-A', 'updated_at', '2026-09-27T10:00:00Z')));
select is((pg_temp.resp('bi_takeover') ->> 'updated')::int, 1,
  'after a takeover, a re-import updates the new live row');
select is((pg_temp.resp('bi_takeover') ->> 'revived')::int, 0,
  'after a takeover, a re-import revives nothing');
select is((select flow from public.day_entries where id = tests.ulid(821)), 'heavy',
  'the live row carries the re-imported values');
select is((select deleted_at is not null from public.day_entries where id = tests.ulid(820)), true,
  'the old tombstone stays deleted');

-- ---------------------------------------------------------------------------
-- Structural: the function comment documents this migration's addition.
-- ---------------------------------------------------------------------------
select ok(
  (select obj_description('public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)'::regprocedure)
     like '%Issue #1576%'),
  'the sync_push function comment documents the re-import takeover'
);

select * from finish();
rollback;
