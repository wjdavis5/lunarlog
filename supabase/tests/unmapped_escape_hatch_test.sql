-- Coverage for Issue #199 (P0, epic: Import): the unmapped-data escape
-- hatch at every database layer. `public.observations.raw jsonb` (added by
-- 20260908160000_observations.sql, Issue #240) receives the full original
-- `{date, type, value}` datapoint whenever a Clue `type`/`value` shape is
-- unrecognised; unknown tag codes and observation options are accepted and
-- preserved at the table CHECK and `sync_push` layers alike (the client
-- write path never consults the taxonomy — Issues #237/#240 — and neither
-- does any layer here); `raw` is payload, so every tombstoning path clears
-- it while provenance (`source`/`source_id`) survives (Issue #159).
--
-- No migration ships with this file: every column, CHECK, grant, and RPC
-- branch it pins already exists. This suite proves the escape hatch the
-- importer (`lib/data/import/clue_importer.dart`) relies on, so a future
-- `sync_push` re-emission that silently dropped `raw` (the 20260904020000
-- precedent for tags) fails loudly instead of shipping.
begin;
select plan(20);

-- ---------------------------------------------------------------------------
-- Fixtures: two independent families, each with one profile and one day
-- entry to attach observations to.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('other_parent');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(902), tests.ulid(901), '2026-09-05', 'UTC', 'medium', '2026-09-05T09:00:00Z');

select tests.authenticate_as('other_parent');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(951), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(952), tests.ulid(951), '2026-09-05', 'UTC', 'none', '2026-09-05T09:00:00Z');

-- ---------------------------------------------------------------------------
-- raw round-trips through sync_push, and updates through it.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L,
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'unmapped',
      'code', 'hot_flashes', 'source', 'clue_import', 'source_id', 'clue:test:2026-09-05:hot_flashes:0',
      'raw', jsonb_build_object('date', '2026-09-05', 'type', 'hot_flashes',
        'value', jsonb_build_object('option', 'moderate')),
      'updated_at', '2026-09-05T10:00:00Z')))$sql$,
    tests.ulid(910), tests.ulid(902), tests.ulid(901)),
  'an unmapped datapoint pushes without error');
select is(
  (select raw from public.observations where id = tests.ulid(910)),
  jsonb_build_object('date', '2026-09-05', 'type', 'hot_flashes',
    'value', jsonb_build_object('option', 'moderate')),
  'raw round-trips the full original datapoint');

select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L,
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'unmapped',
      'code', 'hot_flashes', 'source', 'clue_import', 'source_id', 'clue:test:2026-09-05:hot_flashes:0',
      'raw', jsonb_build_object('date', '2026-09-05', 'type', 'hot_flashes',
        'value', jsonb_build_object('option', 'severe')),
      'updated_at', '2026-09-05T10:30:00Z')))$sql$,
    tests.ulid(910), tests.ulid(902), tests.ulid(901)),
  'raw updates through a later push');
select is(
  (select raw -> 'value' ->> 'option' from public.observations where id = tests.ulid(910)),
  'severe',
  'the updated raw value is stored');

-- ---------------------------------------------------------------------------
-- Unknown categories, codes, and tag codes are accepted, never rejected.
-- ---------------------------------------------------------------------------
select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L,
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'weight',
      'code', 'morning_weigh_in',
      'updated_at', '2026-09-05T11:00:00Z')))$sql$,
    tests.ulid(911), tests.ulid(902), tests.ulid(901)),
  'an unknown category pushes without error');
select is(
  (select category from public.observations where id = tests.ulid(911)),
  'weight',
  'the unknown category is preserved as-is');

select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L,
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'pain',
      'code', 'mystery_symptom',
      'updated_at', '2026-09-05T11:30:00Z')))$sql$,
    tests.ulid(912), tests.ulid(902), tests.ulid(901)),
  'an unknown option on a known category pushes without error');
select is(
  (select code from public.observations where id = tests.ulid(912)),
  'mystery_symptom',
  'the unknown option is preserved as-is');

select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'profile_id', %L,
      'local_date', '2026-09-06', 'tz', 'UTC', 'flow', 'none',
      'tags', jsonb_build_array('mystery_symptom', 'cramps'),
      'updated_at', '2026-09-06T10:00:00Z')))$sql$,
    tests.ulid(913), tests.ulid(901)),
  'an unknown tag code pushes without error (no taxonomy check at any layer)');
select is(
  (select tags from public.day_entries where id = tests.ulid(913)),
  jsonb_build_array('mystery_symptom', 'cramps'),
  'the unknown tag code is preserved as-is');

select is(
  public.is_valid_tags_array(jsonb_build_array('mystery_symptom', 'cramps')),
  true,
  'is_valid_tags_array accepts strings outside the client taxonomy');

-- ---------------------------------------------------------------------------
-- raw is payload: tombstoning clears it, and the CHECK backstops that.
-- ---------------------------------------------------------------------------
select lives_ok(
  format($sql$select public.sync_push('[]'::jsonb, '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', %L, 'day_entry_id', %L, 'profile_id', %L,
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'unmapped',
      'updated_at', '2026-09-05T12:00:00Z', 'deleted_at', '2026-09-05T12:00:00Z')))$sql$,
    tests.ulid(910), tests.ulid(902), tests.ulid(901)),
  'tombstoning the raw-carrying row pushes without error');
select is(
  (select raw from public.observations where id = tests.ulid(910)),
  null,
  'the tombstone cleared raw alongside every other payload column');
select throws_ok(
  format('update public.observations set raw = %L where id = %L',
    '{"date":"2026-09-05"}', tests.ulid(910)),
  '23514', null,
  'the tombstone-payload CHECK rejects a direct write reintroducing raw');

-- ---------------------------------------------------------------------------
-- Bounds the escape hatch does NOT widen.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($sql$insert into public.observations
         (id, day_entry_id, profile_id, local_date, tz, category, raw, updated_at)
       values (%L, %L, %L, '2026-09-05', 'UTC', 'unmapped',
         jsonb_build_object('blob', repeat('x', 9000)), now())$sql$,
    tests.ulid(914), tests.ulid(902), tests.ulid(901)),
  '23514', null,
  'an oversized raw is still rejected by observations_raw_size_check');
select throws_ok(
  format($sql$insert into public.observations
         (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
       values (%L, %L, %L, '2026-09-05', 'UTC', null, now())$sql$,
    tests.ulid(915), tests.ulid(902), tests.ulid(901)),
  '23514', null,
  'raw is no bypass for the required category on a live row');

-- A 33-tag push lands in `rejected`, not applied: the 32-tag bound the
-- escape hatch never widens is enforced in-RPC as well as by the CHECK.
select is(
  jsonb_array_length(
    public.sync_push('[]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'id', tests.ulid(916), 'profile_id', tests.ulid(901),
        'local_date', '2026-09-07', 'tz', 'UTC', 'flow', 'none',
        'tags', (select jsonb_agg('tag_' || g) from generate_series(1, 33) g),
        'updated_at', '2026-09-07T10:00:00Z'))) -> 'rejected'),
  1,
  'a 33-tag push is rejected, not applied (the count bound still holds)');

-- ---------------------------------------------------------------------------
-- Provenance survives the tombstone that cleared raw; isolation holds.
-- ---------------------------------------------------------------------------
select is(
  (select source from public.observations where id = tests.ulid(910)),
  'clue_import',
  'provenance (source) survives the tombstone that cleared raw');
select is(
  (select source_id from public.observations where id = tests.ulid(910)),
  'clue:test:2026-09-05:hot_flashes:0',
  'provenance (source_id) survives the tombstone that cleared raw');

select tests.authenticate_as('other_parent');
select is((select count(*) from public.observations where profile_id = tests.ulid(901)),
  0::bigint, 'other_parent selects zero of mom''s observations, raw included');

select * from finish();
rollback;
