-- Coverage for Issue #159 (P1, epic: Import): source/source_id/import_id
-- provenance columns for import dedup on day_entries and observations
-- (supabase/migrations/20260908170000_import_provenance.sql). Focuses on
-- what sync_push_test.sql and observations_test.sql don't already cover:
-- the partial unique index shape and upsert-dedup behaviour on both
-- tables, the day_entries source CHECK/length CHECK as direct structural
-- guards, observations.import_id's round trip and containment guard, and
-- provenance surviving a tombstone on both tables (day_entries needed no
-- RPC change to prove; observations reverses part of #240's original
-- source_id-clearing, so it gets the more detailed proof here).
begin;
select plan(39);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape: columns, CHECK constraints, partial unique indexes.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'source'),
  1, 'day_entries.source exists');
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'source_id'),
  1, 'day_entries.source_id exists');
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'import_id'),
  1, 'day_entries.import_id exists');
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'observations' and column_name = 'import_id'),
  1, 'observations.import_id exists');

select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'day_entries'
      and indexname = 'day_entries_profile_source_source_id_uq'),
  1, 'day_entries (profile_id, source, source_id) partial unique index exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'observations'
      and indexname = 'observations_profile_source_source_id_uq'),
  1, 'observations (profile_id, source, source_id) partial unique index exists');

-- Default backfill (issue #159 AC: "existing manual rows are unaffected by
-- the migration -- default backfills correctly"): the column's own DEFAULT
-- is the backfill mechanism (see the migration header) -- proven directly
-- by a raw insert that omits source entirely.
select tests.create_supabase_user('imp_mom');
select tests.authenticate_as('imp_mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(900), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(901), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-01', 'UTC', 'none', '2026-09-01T00:00:00Z');
select is((select source from public.day_entries where id = tests.ulid(901)), 'manual',
  'a raw insert omitting source defaults to manual (the ADD COLUMN DEFAULT that backfills pre-existing rows)');
select is((select source_id from public.day_entries where id = tests.ulid(901)), null,
  'source_id defaults to null');
select is((select import_id from public.day_entries where id = tests.ulid(901)), null,
  'import_id defaults to null');

-- Structural guard: the day_entries_source_check CHECK rejects a bad value
-- directly, independent of sync_push.
select throws_ok(
  format(
    $sql$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, updated_at)
         values (%L, %L, %L, '2026-09-02', 'UTC', 'none', 'not_a_real_source', now())$sql$,
    tests.ulid(902), tests.get_supabase_uid('imp_mom'), tests.ulid(900)),
  '23514', null,
  'day_entries_source_check rejects an out-of-set source value');

-- Structural guard: day_entries_source_id_length_check (128 chars).
select throws_ok(
  format(
    $sql$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source_id, updated_at)
         values (%L, %L, %L, '2026-09-03', 'UTC', 'none', %L, now())$sql$,
    tests.ulid(903), tests.get_supabase_uid('imp_mom'), tests.ulid(900), repeat('x', 129)),
  '23514', null,
  'day_entries_source_id_length_check rejects a 129-character source_id');

-- ---------------------------------------------------------------------------
-- Import dedup: the partial unique index rejects a raw duplicate
-- (profile_id, source, source_id) on day_entries, and an
-- `insert ... on conflict ... do update` against it -- the exact shape
-- #167's importer will use -- upserts cleanly rather than erroring.
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
values (tests.ulid(904), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-04', 'UTC', 'light', 'clue_import', 'clue-dup-1', now());
select throws_ok(
  format(
    $sql$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
         values (%L, %L, %L, '2026-09-05', 'UTC', 'medium', 'clue_import', 'clue-dup-1', now())$sql$,
    tests.ulid(905), tests.get_supabase_uid('imp_mom'), tests.ulid(900)),
  '23505', null,
  'a second day_entries row with the same (profile_id, source, source_id) is rejected by the partial unique index');

insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
values (tests.ulid(906), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-06', 'UTC', 'light', 'clue_import', 'clue-upsert-1', now())
on conflict (profile_id, source, source_id) where source_id is not null
do update set flow = excluded.flow, updated_at = excluded.updated_at,
  last_modified_by_user_id = tests.get_supabase_uid('imp_mom');
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
values (tests.ulid(907), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-06', 'UTC', 'heavy', 'clue_import', 'clue-upsert-1', now())
on conflict (profile_id, source, source_id) where source_id is not null
do update set flow = excluded.flow, updated_at = excluded.updated_at,
  last_modified_by_user_id = tests.get_supabase_uid('imp_mom');
select is((select count(*) from public.day_entries where profile_id = tests.ulid(900) and source_id = 'clue-upsert-1'), 1::bigint,
  're-running the same import (same profile_id/source/source_id) upserts one row, not two');
select is((select flow from public.day_entries where profile_id = tests.ulid(900) and source_id = 'clue-upsert-1'), 'heavy',
  'the upsert applies the second run''s values, proving it is a real update not a no-op');

-- Same shape on observations.
insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, source, source_id, updated_at)
values (tests.ulid(908), tests.ulid(901), tests.ulid(900), '2026-09-01', 'UTC', 'pain', 'clue_import', 'clue-obs-dup-1', now());
select throws_ok(
  format(
    $sql$insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, source, source_id, updated_at)
         values (%L, %L, %L, '2026-09-01', 'UTC', 'mood', 'clue_import', 'clue-obs-dup-1', now())$sql$,
    tests.ulid(909), tests.ulid(901), tests.ulid(900)),
  '23505', null,
  'a second observations row with the same (profile_id, source, source_id) is rejected by the partial unique index');

insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, source, source_id, updated_at)
values (tests.ulid(910), tests.ulid(901), tests.ulid(900), '2026-09-01', 'UTC', 'pain', 'clue_import', 'clue-obs-upsert-1', now())
on conflict (profile_id, source, source_id) where source_id is not null
do update set category = excluded.category, updated_at = excluded.updated_at,
  last_modified_by_user_id = tests.get_supabase_uid('imp_mom');
insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, source, source_id, updated_at)
values (tests.ulid(911), tests.ulid(901), tests.ulid(900), '2026-09-01', 'UTC', 'mood', 'clue_import', 'clue-obs-upsert-1', now())
on conflict (profile_id, source, source_id) where source_id is not null
do update set category = excluded.category, updated_at = excluded.updated_at,
  last_modified_by_user_id = tests.get_supabase_uid('imp_mom');
select is((select count(*) from public.observations where profile_id = tests.ulid(900) and source_id = 'clue-obs-upsert-1'), 1::bigint,
  're-running the same observation import upserts one row, not two');
select is((select category from public.observations where profile_id = tests.ulid(900) and source_id = 'clue-obs-upsert-1'), 'mood',
  'the observations upsert applies the second run''s values');

-- ---------------------------------------------------------------------------
-- observations.import_id: round trip and containment guard via sync_push.
-- Issue #167 gave import_id a real `references import_jobs(id)` FK (this
-- column was an unconstrained placeholder before that migration), so the
-- id used below must be a real import_jobs row, not an arbitrary literal
-- uuid -- a fixed id inserted directly rather than captured, since nothing
-- else in this file needs to look it back up.
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(920), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-20', 'UTC', 'none', '2026-09-20T00:00:00Z');

insert into public.import_jobs (id, profile_id, source, status, total_rows, created_by)
values ('99999999-9999-9999-9999-999999999999'::uuid, tests.ulid(900), 'clue_import', 'pending', 1,
        tests.get_supabase_uid('imp_mom'));

insert into r select 'obs_import_id_insert', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'day_entry_id', tests.ulid(920), 'profile_id', tests.ulid(900),
    'local_date', '2026-09-20', 'tz', 'UTC', 'category', 'pain', 'source', 'clue_import',
    'source_id', 'clue-921', 'import_id', '99999999-9999-9999-9999-999999999999',
    'updated_at', '2026-09-20T10:00:00Z')));
select is(pg_temp.resp('obs_import_id_insert') -> 'rejected', '[]'::jsonb,
  'an observation push carrying import_id is accepted');
select is((select import_id::text from public.observations where id = tests.ulid(921)),
  '99999999-9999-9999-9999-999999999999', 'observations.import_id round-trips through sync_push');

insert into r select 'obs_import_id_old_client', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'day_entry_id', tests.ulid(920), 'profile_id', tests.ulid(900),
    'local_date', '2026-09-20', 'tz', 'UTC', 'category', 'sleep',
    'updated_at', '2026-09-20T11:00:00Z')));
select is((select category from public.observations where id = tests.ulid(921)), 'sleep',
  'the old-client push still applies the field it did send');
select is((select import_id::text from public.observations where id = tests.ulid(921)),
  '99999999-9999-9999-9999-999999999999',
  'an old client omitting import_id does not reset the stored value (containment guard)');
select is((select source from public.observations where id = tests.ulid(921)), 'clue_import',
  '#159 review finding: an old client omitting source does not reset the stored value to manual either -- source now gets the same containment guard as source_id/import_id');

-- ---------------------------------------------------------------------------
-- Provenance survives a tombstone (this migration's judgement call,
-- reversing #240's original observations.source_id-clearing).
-- ---------------------------------------------------------------------------
insert into r select 'obs_tombstone_provenance', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'day_entry_id', tests.ulid(920), 'profile_id', tests.ulid(900),
    'local_date', '2026-09-20', 'tz', 'UTC',
    'updated_at', '2026-09-20T12:00:00Z', 'deleted_at', '2026-09-20T12:00:00Z')));
select isnt((select deleted_at from public.observations where id = tests.ulid(921)), null,
  'the observation is tombstoned');
select is((select category from public.observations where id = tests.ulid(921)), null,
  'category is still cleared on a tombstone (unchanged from #240)');
select is((select source_id from public.observations where id = tests.ulid(921)), 'clue-921',
  '#159: source_id SURVIVES an observations tombstone (reverses #240''s original clearing)');
select is((select import_id::text from public.observations where id = tests.ulid(921)),
  '99999999-9999-9999-9999-999999999999',
  '#159: import_id survives an observations tombstone');
select is((select source from public.observations where id = tests.ulid(921)), 'clue_import',
  '#159 review finding: source SURVIVES an observations tombstone too (the tombstone push omits it entirely, and the containment guard added above keeps it from coalescing to manual)');

-- Structural proof: the tombstone-payload CHECK no longer forbids setting
-- source_id on an already-tombstoned row (it forbids category/code/etc.,
-- unchanged).
select lives_ok(
  format('update public.observations set source_id = %L where id = %L', 'clue-921-again', tests.ulid(921)),
  '#159: source_id can be written on an already-tombstoned observation (no longer part of observations_tombstone_payload_check)');
select throws_ok(
  format('update public.observations set category = %L where id = %L', 'pain', tests.ulid(921)),
  '23514', null,
  'category is still rejected on an already-tombstoned observation (observations_tombstone_payload_check unchanged for every other column)');

-- ---------------------------------------------------------------------------
-- A tombstoned imported row still occupies the partial unique index (it is
-- not exempted just because it is dead), and the exact
-- `on conflict (profile_id, source, source_id) where source_id is not null
-- do update set deleted_at = null, ...` shape #167's importer will use to
-- revive it succeeds rather than erroring.
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
values (tests.ulid(930), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-07', 'UTC', 'light', 'clue_import', 'clue-revive-1', now());
update public.day_entries
   set deleted_at = now(), flow = 'none', tags = '[]'::jsonb, note = null, updated_at = now(),
       last_modified_by_user_id = tests.get_supabase_uid('imp_mom')
 where id = tests.ulid(930);

select throws_ok(
  format(
    $sql$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
         values (%L, %L, %L, '2026-09-07', 'UTC', 'light', 'clue_import', 'clue-revive-1', now())$sql$,
    tests.ulid(931), tests.get_supabase_uid('imp_mom'), tests.ulid(900)),
  '23505', null,
  'a tombstoned imported row still occupies the (profile_id, source, source_id) partial unique index -- a plain second insert still collides');

select lives_ok(
  format(
    $sql$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, source_id, updated_at)
         values (%L, %L, %L, '2026-09-07', 'UTC', 'heavy', 'clue_import', 'clue-revive-1', now())
         on conflict (profile_id, source, source_id) where source_id is not null
         do update set deleted_at = null, flow = excluded.flow, updated_at = excluded.updated_at,
           last_modified_by_user_id = %L$sql$,
    tests.ulid(932), tests.get_supabase_uid('imp_mom'), tests.ulid(900), tests.get_supabase_uid('imp_mom')),
  '#167''s importer shape (on conflict ... do update set deleted_at = null, ...) revives the tombstoned row rather than failing');
select is((select deleted_at from public.day_entries where id = tests.ulid(930)), null,
  'the revived row is live again (deleted_at cleared)');
select is((select flow from public.day_entries where id = tests.ulid(930)), 'heavy',
  'the revive applied the new import run''s values, proving it is a real update not a no-op');

-- ---------------------------------------------------------------------------
-- An imported row colliding with a live *manual* same-date day_entries row:
-- the existing same-date resolver applies unchanged (issue #159 adds no
-- special-casing here) -- newer updated_at wins, the loser is tombstoned,
-- and the survivor's own provenance is left completely untouched by the
-- collision (never overwritten with the other row's source/source_id).
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, source, updated_at)
values (tests.ulid(940), tests.get_supabase_uid('imp_mom'), tests.ulid(900), '2026-09-10', 'UTC', 'light', 'manual', '2026-09-10T05:00:00Z');

insert into r select 'collision_import_vs_manual', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(941), 'profile_id', tests.ulid(900), 'local_date', '2026-09-10', 'tz', 'UTC',
    'flow', 'heavy', 'tags', jsonb_build_array('cramps'), 'source', 'clue_import', 'source_id', 'clue-940',
    -- Older than the manual row's updated_at, so the manual row wins the
    -- same-date resolver and the incoming import is the one tombstoned.
    'updated_at', '2026-09-10T01:00:00Z')), '[]'::jsonb);
select is(pg_temp.resp('collision_import_vs_manual') -> 'rejected', '[]'::jsonb,
  'the colliding import push is accepted (resolved by the same-date resolver, not rejected)');
select is((select deleted_at from public.day_entries where id = tests.ulid(940)), null,
  'the pre-existing manual row survives the collision (it has the newer updated_at)');
select is((select source from public.day_entries where id = tests.ulid(940)), 'manual',
  'the survivor''s own source is untouched by the collision -- never overwritten with the losing import''s provenance');
select is((select source_id from public.day_entries where id = tests.ulid(940)), null,
  'the survivor''s source_id likewise stays null, not adopted from the losing import');
select isnt((select deleted_at from public.day_entries where id = tests.ulid(941)), null,
  'the losing imported row is tombstoned by the same-date resolver, same as any other collision loser');
select is((select source from public.day_entries where id = tests.ulid(941)), 'clue_import',
  'the tombstoned loser keeps its own provenance too (source is never cleared on a day_entries tombstone, collision or otherwise)');

select * from finish();
rollback;
