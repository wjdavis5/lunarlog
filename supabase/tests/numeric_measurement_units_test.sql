-- Coverage for Issue #255 (P1, epic: tracking-model): numeric measurements
-- (BBT and weight). Owns the storage half of the issue end to end:
--   * profiles.bbt_unit / profiles.weight_unit -- the per-profile
--     display-unit preferences (column defaults, CHECK closed sets, the
--     column-scoped grant, the sync_push round trip, the old-client
--     containment guard, the role ladder, and the server export
--     projection);
--   * the numeric-observation round trip itself (value_num + unit +
--     BBT's excluded flag + non-null source -- the columns shipped by
--     #240, pinned here in their bbt/weight shapes), and
--   * the source-scoped same-date collision dedup -- a wearable-sourced
--     value and a manually-entered value at the same
--     (profile, date, category, code) coexist (A1-42: a device-sourced
--     value never overwrites or merges with a manual one), while
--     same-source rows still collapse exactly as before.
--
-- Excludes the storage container itself (RLS/grants/indexes/per-day cap),
-- which 20260908160000_observations.sql's suite already pins; only the
-- #255 deltas are re-checked here.
begin;
select plan(35);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;
create function pg_temp.live_obs(p_id text) returns bigint language sql as
  $$ select count(*) from public.observations
     where profile_id = p_id and deleted_at is null $$;

-- ---------------------------------------------------------------------------
-- Schema shape: the two new columns, their CHECKs, and the grant.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'bbt_unit' and is_nullable = 'NO'
      and column_default = '''celsius''::text'),
  1, 'profiles.bbt_unit is not null, defaulting to celsius');
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'weight_unit' and is_nullable = 'NO'
      and column_default = '''kg''::text'),
  1, 'profiles.weight_unit is not null, defaulting to kg');
select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname in ('profiles_bbt_unit_check', 'profiles_weight_unit_check')),
  2, 'both display-unit CHECK constraints exist');
select is(
  (select has_column_privilege('authenticated', 'public.profiles', 'bbt_unit', 'UPDATE')
      and has_column_privilege('authenticated', 'public.profiles', 'weight_unit', 'UPDATE')),
  true, 'authenticated holds column-scoped UPDATE on both display-unit columns');
select is(
  (select has_column_privilege('anon', 'public.profiles', 'bbt_unit', 'UPDATE')
      or has_column_privilege('anon', 'public.profiles', 'weight_unit', 'UPDATE')),
  false, 'anon holds no UPDATE on either display-unit column');

-- ---------------------------------------------------------------------------
-- Fixtures: mom owns profile 901 (with a day entry to hang observations
-- on); nanny is a caregiver on the same profile (added directly, the
-- sync_push_test.sql pattern).
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('nanny');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(902), tests.ulid(901), '2026-09-05', 'UTC', 'none', '2026-09-05T09:00:00Z');

select tests.clear_authentication();
insert into public.profile_guardians (profile_id, user_id, role, status)
values (tests.ulid(901), tests.get_supabase_uid('nanny'), 'caregiver', 'accepted');

-- ---------------------------------------------------------------------------
-- Display-unit preference round trip via sync_push.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'units_push', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(901), 'display_name', 'Riley', 'is_minor', true,
    'bbt_unit', 'fahrenheit', 'weight_unit', 'lb',
    'updated_at', '2026-09-06T10:00:00Z')),
  '[]'::jsonb);

select is((select bbt_unit from public.profiles where id = tests.ulid(901)), 'fahrenheit',
  'round trip: bbt_unit persisted');
select is((select weight_unit from public.profiles where id = tests.ulid(901)), 'lb',
  'round trip: weight_unit persisted');
select is(pg_temp.rejected_ids('units_push'), null,
  'round trip: nothing rejected');

-- A brand-new profile created through sync_push by a client that omits
-- both keys gets the column defaults (the INSERT path coalesces an absent
-- key to the default, the #131 mode pattern).
insert into r select 'units_default_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(903), 'display_name', 'Casey', 'is_minor', false,
    'updated_at', '2026-09-06T10:00:00Z')),
  '[]'::jsonb);
select is(
  (select bbt_unit from public.profiles where id = tests.ulid(903)),
  'celsius', 'a push without the keys inserts the celsius default');
select is(
  (select weight_unit from public.profiles where id = tests.ulid(903)),
  'kg', 'a push without the keys inserts the kg default');

-- Old-client guard (the PR #108 review item #3 lesson): a subsequent push
-- that omits both keys must not clobber the stored preferences.
insert into r select 'units_old_client', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(901), 'display_name', 'Riley Renamed',
    'updated_at', '2026-09-06T11:00:00Z')),
  '[]'::jsonb);
select is(
  (select bbt_unit from public.profiles where id = tests.ulid(901)),
  'fahrenheit', 'a pre-#255 client''s push preserves a stored bbt_unit');
select is(
  (select weight_unit from public.profiles where id = tests.ulid(901)),
  'lb', 'a pre-#255 client''s push preserves a stored weight_unit');

-- An out-of-set value lands the row in `rejected` via the column CHECK.
insert into r select 'units_bad_value', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(901), 'display_name', 'Riley Renamed',
    'bbt_unit', 'kelvin',
    'updated_at', '2026-09-06T12:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.rejected_ids('units_bad_value'), array[tests.ulid(901)],
  'an out-of-set bbt_unit lands the row in rejected');
select is(
  (select bbt_unit from public.profiles where id = tests.ulid(901)),
  'fahrenheit', 'the rejected push left the stored bbt_unit untouched');

-- Role ladder: a caregiver's push that tries to edit profile metadata
-- (units included) is rejected -- presentation, never permission.
select tests.authenticate_as('nanny');
insert into r select 'units_caregiver_edit', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(901), 'display_name', 'Nanny Rename',
    'bbt_unit', 'celsius', 'weight_unit', 'kg',
    'updated_at', '2026-09-06T13:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.rejected_ids('units_caregiver_edit'), array[tests.ulid(901)],
  'a caregiver cannot edit the display-unit preferences');
select is(
  (select weight_unit from public.profiles where id = tests.ulid(901)),
  'lb', 'the caregiver''s rejected push left the stored weight_unit untouched');

-- ---------------------------------------------------------------------------
-- Numeric measurement round trip: BBT (manual, excluded flag) and weight
-- (wearable-sourced) as observations rows.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'bbt_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-05', 'tz', 'UTC',
    'category', 'bbt', 'value_num', 36.72::numeric, 'unit', 'celsius',
    'excluded', true, 'source', 'manual',
    'updated_at', '2026-09-05T07:30:00Z')));

select is((select value_num from public.observations where id = tests.ulid(910)), 36.72::numeric,
  'BBT round trip: value_num persisted');
select is((select unit from public.observations where id = tests.ulid(910)), 'celsius',
  'BBT round trip: stored unit persisted (celsius, independent of the profile''s fahrenheit display preference)');
select is((select excluded from public.observations where id = tests.ulid(910)), true,
  'BBT round trip: the per-datapoint excluded flag persisted');
select is((select source from public.observations where id = tests.ulid(910)), 'manual',
  'BBT round trip: source persisted');
select is(
  (select bbt_unit from public.profiles where id = tests.ulid(901)),
  'fahrenheit',
  'the profile display preference (fahrenheit) differs from the stored row unit (celsius) by design');

insert into r select 'weight_push', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-05', 'tz', 'UTC',
    'category', 'weight', 'value_num', 61.2::numeric, 'unit', 'kg',
    'source', 'wearable', 'source_id', 'garmin-2026-09-05',
    'updated_at', '2026-09-05T08:00:00Z')));

select is((select value_num from public.observations where id = tests.ulid(911)), 61.2::numeric,
  'weight round trip: value_num persisted');
select is((select unit from public.observations where id = tests.ulid(911)), 'kg',
  'weight round trip: unit persisted');
select is((select source from public.observations where id = tests.ulid(911)), 'wearable',
  'weight round trip: non-manual source persisted');

-- Every numeric measurement row carries a non-null source: the column is
-- not null with a 'manual' default at the table level (#240).
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'observations'
      and column_name = 'source'),
  'NO', 'observations.source is not null');
insert into public.observations (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
values (tests.ulid(912), tests.ulid(902), tests.ulid(901), '2026-09-06', 'UTC', 'bbt',
        '2026-09-06T07:00:00Z');
select is(
  (select source from public.observations where id = tests.ulid(912)),
  'manual', 'a direct insert without source defaults to manual');

-- ---------------------------------------------------------------------------
-- Source-scoped same-date collision dedup (A1-42).
-- ---------------------------------------------------------------------------

-- (a) Two SAME-SOURCE manual pushes at the same (date, category, code)
--     still collapse: newer wins, the loser becomes a payload-free
--     tombstone. The anti-duplicate-race property is unchanged.
insert into r select 'dedup_manual_a', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-07', 'tz', 'UTC',
    'category', 'pain', 'code', 'migraine', 'intensity', 3, 'source', 'manual',
    'updated_at', '2026-09-07T09:00:00Z')));
insert into r select 'dedup_manual_b', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-07', 'tz', 'UTC',
    'category', 'pain', 'code', 'migraine', 'intensity', 4, 'source', 'manual',
    'updated_at', '2026-09-07T10:00:00Z')));
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(901) and local_date = '2026-09-07'
      and category = 'pain' and code = 'migraine' and deleted_at is null),
  1::bigint, 'same-source manual rows still collapse to one live row');
select is(
  (select deleted_at is not null from public.observations where id = tests.ulid(920)),
  true, 'the losing same-source row became a payload-free tombstone');

-- (b) A wearable-sourced value and a manually-entered value at the same
--     (date, category, code) COEXIST: neither overwrites or merges with
--     the other, whichever order they arrive in.
insert into r select 'dedup_manual_first', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(922), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-08', 'tz', 'UTC',
    'category', 'pain', 'code', 'headache', 'source', 'manual',
    'updated_at', '2026-09-08T09:00:00Z')));
insert into r select 'dedup_wearable_second', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(923), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-08', 'tz', 'UTC',
    'category', 'pain', 'code', 'headache', 'source', 'wearable',
    'source_id', 'ring-2026-09-08',
    'updated_at', '2026-09-08T08:00:00Z')));
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(901) and local_date = '2026-09-08'
      and category = 'pain' and code = 'headache' and deleted_at is null),
  2::bigint, 'a wearable row and a manual row at the same (date, category, code) coexist');
select is(
  (select deleted_at is null from public.observations where id = tests.ulid(922)),
  true, 'the manual row survived the wearable push');
select is(
  (select deleted_at is null from public.observations where id = tests.ulid(923)),
  true, 'the wearable row stayed live too');

-- (c) Purely-numeric rows (code IS NULL -- how bbt and weight are
--     actually stored) never entered the dedup at all; a manual BBT and
--     a wearable temperature row on the same date are simply two rows.
insert into r select 'numeric_manual_bbt', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(924), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-09', 'tz', 'UTC',
    'category', 'bbt', 'value_num', 36.60::numeric, 'unit', 'celsius', 'source', 'manual',
    'updated_at', '2026-09-09T07:00:00Z')));
insert into r select 'numeric_wearable_temp', public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(925), 'day_entry_id', tests.ulid(902), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-09', 'tz', 'UTC',
    'category', 'bbt', 'value_num', 36.44::numeric, 'unit', 'celsius',
    'source', 'wearable', 'source_id', 'watch-2026-09-09',
    'updated_at', '2026-09-09T06:00:00Z')));
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(901) and local_date = '2026-09-09'
      and category = 'bbt' and deleted_at is null),
  2::bigint, 'a manual BBT value and a wearable-sourced value on the same date are two live rows');
select is(
  (select value_num from public.observations
    where id = tests.ulid(924) and deleted_at is null),
  36.60::numeric, 'the manual BBT value is intact, never overwritten');

-- ---------------------------------------------------------------------------
-- Server export projection carries the new columns.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
create function pg_temp.profile_by_id(doc jsonb, p_id text) returns jsonb language sql as
  $$ select value from jsonb_array_elements(coalesce(doc -> 'profiles', '[]'::jsonb))
     where value ->> 'id' = p_id limit 1 $$;

insert into r select 'export', public.export_account_data();
select is(
  ((pg_temp.profile_by_id(pg_temp.resp('export'), tests.ulid(901))) ->> 'bbt_unit'),
  'fahrenheit', 'export_account_data() carries profiles.bbt_unit');
select is(
  ((pg_temp.profile_by_id(pg_temp.resp('export'), tests.ulid(901))) ->> 'weight_unit'),
  'lb', 'export_account_data() carries profiles.weight_unit');

select * from finish();
rollback;
