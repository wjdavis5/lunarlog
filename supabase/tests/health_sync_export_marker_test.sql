-- Coverage for Issue #186 (P1, epic: health-sync) server half: the
-- `observations.exported_to_platform_at` round-trip-write marker column and
-- sync_push's acceptance of it (INSERT, UPDATE behind the `v_row ? 'key'`
-- containment guard, and provenance-survives-a-tombstone). The per-profile
-- health-sync consent flag (`profile_modes.health_sync_consent`) that #186
-- also requires already landed with #188's profile_modes table; its own
-- coverage lives in profile_modes_cycle_overrides_test.sql.
begin;
select plan(11);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

-- Fixture: one family, one profile, one day entry to attach observations to.
select tests.create_supabase_user('mom');
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(9001), 'Riley', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(9002), tests.ulid(9001), '2026-09-05', 'UTC', 'medium', '2026-09-05T09:00:00Z');

-- ---------------------------------------------------------------------------
-- Schema shape: the column exists, is nullable, and carries no grant of its
-- own (the table-wide authenticated grants #240 established cover it).
-- ---------------------------------------------------------------------------
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'observations'
      and column_name = 'exported_to_platform_at'),
  'YES', 'observations.exported_to_platform_at exists and is nullable');
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'observations'
      and column_name = 'exported_to_platform_at'),
  1, 'observations has exactly one exported_to_platform_at column');
select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'observations'
      and column_name = 'exported_to_platform_at'),
  'timestamp with time zone', 'exported_to_platform_at is a timestamptz');

-- ---------------------------------------------------------------------------
-- INSERT: a push carrying the marker persists it.
-- ---------------------------------------------------------------------------
insert into r select 'mom_export_insert', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(9010), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'migraine',
    'exported_to_platform_at', '2026-09-06T08:00:00Z', 'updated_at', '2026-09-05T10:00:00Z')));
select is((select exported_to_platform_at from public.observations where id = tests.ulid(9010)),
  '2026-09-06T08:00:00Z'::timestamptz,
  'round trip: exported_to_platform_at persisted on insert');

-- ---------------------------------------------------------------------------
-- UPDATE with the key present: a newer push overwrites it.
-- ---------------------------------------------------------------------------
insert into r select 'mom_export_update', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(9010), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'migraine',
    'exported_to_platform_at', '2026-09-07T08:00:00Z', 'updated_at', '2026-09-05T12:00:00Z')));
select is((select exported_to_platform_at from public.observations where id = tests.ulid(9010)),
  '2026-09-07T08:00:00Z'::timestamptz,
  'round trip: a newer push with the key present overwrites exported_to_platform_at');

-- ---------------------------------------------------------------------------
-- UPDATE with the key ABSENT (an old pre-#186 client, or a tombstone push
-- omitting the key): the containment guard leaves the stored value intact.
-- ---------------------------------------------------------------------------
insert into r select 'mom_export_absent', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(9010), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'migraine',
    'updated_at', '2026-09-05T13:00:00Z')));
select is((select exported_to_platform_at from public.observations where id = tests.ulid(9010)),
  '2026-09-07T08:00:00Z'::timestamptz,
  'an old client omitting the key never clears an already-stored exported_to_platform_at (v_row ? containment guard)');

-- ---------------------------------------------------------------------------
-- Tombstone: exported_to_platform_at is provenance, not health content, and
-- survives a tombstone (the #159 source_id/import_id rule applied to the
-- round-trip marker) -- a deleted row stays recognisable as already-written
-- to a health store so a future re-import dedupe never re-writes it.
-- ---------------------------------------------------------------------------
insert into r select 'mom_export_tombstone', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(9010), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain',
    'updated_at', '2026-09-05T14:00:00Z', 'deleted_at', '2026-09-05T14:00:00Z')));
select isnt((select deleted_at from public.observations where id = tests.ulid(9010)), null,
  'tombstone sets deleted_at');
select is((select category from public.observations where id = tests.ulid(9010)), null,
  'tombstone clears payload (category) as before');
select is((select exported_to_platform_at from public.observations where id = tests.ulid(9010)),
  '2026-09-07T08:00:00Z'::timestamptz,
  'tombstone keeps exported_to_platform_at (provenance survives, #159 rule applied)');

-- A tombstone push that omits the key entirely also keeps the stored marker
-- (the containment guard, not merely the tombstone parse branch).
insert into r select 'mom_export_tombstone_absent', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(9010), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain',
    'updated_at', '2026-09-05T15:00:00Z', 'deleted_at', '2026-09-05T15:00:00Z')));
select is((select exported_to_platform_at from public.observations where id = tests.ulid(9010)),
  '2026-09-07T08:00:00Z'::timestamptz,
  'a tombstone push omitting the key keeps the stored exported_to_platform_at (containment guard)');

-- An unknown key on observations is still rejected (the new key is the only
-- addition, nothing else loosened).
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(9011), 'day_entry_id', tests.ulid(9002), 'profile_id', tests.ulid(9001),
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain', 'code', 'x',
      'exported_to_platform_at', '2026-09-06T08:00:00Z', 'updated_at', '2026-09-05T10:00:00Z')))$$,
  'exported_to_platform_at is accepted; the observations key allowlist was widened only by the new key');

rollback;
