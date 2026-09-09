-- Coverage for Issue #180 (P1, epic: health-sync):
-- 20260908180000_timezone_contract.sql -- public.is_valid_timezone(text)
-- (including its strict null behaviour), the observations_tz_valid/
-- day_entries_tz_valid CHECK constraints, the observations_derive_local_date
-- trigger (including through sync_push's p_observations path), and
-- sync_push's own local_date derivation fix (review finding): the per-day
-- cap and same-date (category, code) dedup must evaluate against the
-- DERIVED local_date, not the stale client-supplied one, on both an insert
-- and an observed_at-only update that moves a row across a day boundary.
begin;
select plan(37);

-- ---------------------------------------------------------------------------
-- Function shape: immutable, search_path pinned, exception-safe.
-- ---------------------------------------------------------------------------
select is(
  (select provolatile from pg_proc
    where proname = 'is_valid_timezone' and pronamespace = 'public'::regnamespace),
  'i'::"char",
  'is_valid_timezone is IMMUTABLE (see the migration header for why that is safe despite calling now())'
);
select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'is_valid_timezone' and pronamespace = 'public'::regnamespace
       and c.setting like 'search_path=%'
  ),
  'is_valid_timezone sets search_path = '''''
);
select is(public.is_valid_timezone('UTC'), true, 'UTC is a valid zone');
select is(public.is_valid_timezone('America/New_York'), true, 'America/New_York is a valid zone');
select is(public.is_valid_timezone('Mars/Olympus'), false,
  'an unrecognized zone name returns false rather than raising -- proves the bare '
  || '"exception when others" handler is not narrower than what this input actually raises '
  || '(review consideration: narrowing to invalid_parameter_value only, rejected -- see migration header)');
select is(public.is_valid_timezone(''), false,
  'an empty string returns false rather than raising -- same narrowing consideration as above');
select is(public.is_valid_timezone(null), null,
  'is_valid_timezone(null) is null (strict), not false -- review fix; a null CHECK result is never a '
  || 'violation, so this cannot itself cause a CHECK rejection on either tz column (both are not null '
  || 'today, so this path is unreachable in practice, but the function''s own null-safety no longer '
  || 'depends on that being true)');

-- Judgement call under test: no revoke on this pure predicate (matching
-- is_valid_tags_array/merge_tag_arrays/is_allowed_device_info), but an
-- explicit grant to authenticated is still present.
select is(
  (select has_function_privilege('authenticated', 'public.is_valid_timezone(text)', 'EXECUTE')),
  true, 'authenticated holds an explicit EXECUTE grant on is_valid_timezone');
select is(
  (select has_function_privilege('anon', 'public.is_valid_timezone(text)', 'EXECUTE')),
  true, 'anon retains the default PUBLIC EXECUTE grant (deliberately not revoked -- see migration header)');

-- ---------------------------------------------------------------------------
-- CHECK constraints: present and validated on both tables.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.observations'::regclass and conname = 'observations_tz_valid'),
  1, 'observations_tz_valid exists');
select is(
  (select convalidated from pg_constraint
    where conrelid = 'public.observations'::regclass and conname = 'observations_tz_valid'),
  true, 'observations_tz_valid is validated (not left NOT VALID)');
select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.day_entries'::regclass and conname = 'day_entries_tz_valid'),
  1, 'day_entries_tz_valid exists');
select is(
  (select convalidated from pg_constraint
    where conrelid = 'public.day_entries'::regclass and conname = 'day_entries_tz_valid'),
  true, 'day_entries_tz_valid is validated (not left NOT VALID)');

-- ---------------------------------------------------------------------------
-- Trigger: exists, enabled, before insert or update.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'observations' and t.tgname = 'observations_derive_local_date'),
  1, 'observations_derive_local_date trigger exists');
select is(
  (select t.tgenabled from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'observations' and t.tgname = 'observations_derive_local_date'),
  'O'::"char",
  'observations_derive_local_date is enabled');

-- ---------------------------------------------------------------------------
-- Fixture: one guardian, one profile, one day entry to attach observations to.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('tz_mom');
select tests.authenticate_as('tz_mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1800), 'Riley', true, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(1801), tests.ulid(1800), '2026-01-01', 'UTC', 'none', '2026-01-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- CHECK rejects a bad tz on both tables, sqlstate 23514.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$insert into public.day_entries
             (id, profile_id, local_date, tz, flow, updated_at)
           values (%L, %L, '2026-01-02', 'Mars/Olympus', 'none', now())$$,
         tests.ulid(1802), tests.ulid(1800)),
  '23514', null,
  'day_entries_tz_valid rejects an unrecognized zone name');
select throws_ok(
  format($$insert into public.observations
             (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
           values (%L, %L, %L, '2026-01-02', 'Mars/Olympus', 'pain', now())$$,
         tests.ulid(1803), tests.ulid(1801), tests.ulid(1800)),
  '23514', null,
  'observations_tz_valid rejects an unrecognized zone name');
select throws_ok(
  format($$insert into public.observations
             (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
           values (%L, %L, %L, '2026-01-02', '', 'pain', now())$$,
         tests.ulid(1804), tests.ulid(1801), tests.ulid(1800)),
  '23514', null,
  'observations_tz_valid rejects an empty-string zone (passes the length CHECK, fails is_valid_timezone)');

-- ---------------------------------------------------------------------------
-- Trigger derivation: DST spring-forward (America/New_York, 2026-03-08
-- 02:00 -> 03:00 local) and fall-back (2026-11-01 02:00 -> 01:00 local).
-- Each insert deliberately supplies a WRONG local_date so a passing
-- assertion proves the trigger overwrote it from observed_at/tz, not that
-- the supplied value happened to already be right.
-- ---------------------------------------------------------------------------

-- Mid-day, safely after the local 02:00 jump: unambiguous sanity check.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1810), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-03-08T12:00:00Z', 'America/New_York', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1810)), '2026-03-08'::date,
  'spring-forward day, mid-day instant: local_date derives to 2026-03-08 (EDT, -04:00)');

-- Boundary the day after the jump: an instant whose UTC clock time would
-- read as the day before under a bug that forgot the jump already happened
-- and kept using EST (-05:00) instead of EDT (-04:00).
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1811), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-03-09T04:30:00Z', 'America/New_York', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1811)), '2026-03-09'::date,
  'spring-forward boundary: 2026-03-09T04:30Z is 2026-03-09 00:30 EDT, not 2026-03-08 23:30 EST '
  || '(a fixed-EST bug would land one day early)');

-- Mid-day, safely after the local 02:00 rollback: unambiguous sanity check.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1812), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-11-01T12:00:00Z', 'America/New_York', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1812)), '2026-11-01'::date,
  'fall-back day, mid-day instant: local_date derives to 2026-11-01 (EST, -05:00)');

-- Boundary the day after the rollback: an instant whose UTC clock time
-- would read as the day after under a bug that forgot the rollback already
-- happened and kept using EDT (-04:00) instead of EST (-05:00).
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1813), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-11-02T04:30:00Z', 'America/New_York', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1813)), '2026-11-01'::date,
  'fall-back boundary: 2026-11-02T04:30Z is 2026-11-01 23:30 EST, not 2026-11-02 00:30 EDT '
  || '(a fixed-EDT bug would land one day late)');

-- ---------------------------------------------------------------------------
-- Midnight-boundary instants across zones with opposite-sign offsets from
-- UTC -- neither derivation ever consults a device zone, only the row's own
-- tz, so this proves the same instant lands on different local dates in
-- each.
-- ---------------------------------------------------------------------------

-- Pacific/Auckland (NZST +12:00 in June, no DST): a late-UTC-day instant
-- already reflects the NEXT local calendar date, ahead of UTC.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1814), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-06-14T23:30:00Z', 'Pacific/Auckland', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1814)), '2026-06-15'::date,
  'Pacific/Auckland (+12:00): 2026-06-14T23:30Z is already 2026-06-15 11:30 local -- a day ahead of the UTC date');

-- America/Los_Angeles (PDT -07:00 in June): a UTC-midnight instant lands on
-- the PREVIOUS local calendar date, behind UTC.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at)
values
  (tests.ulid(1815), tests.ulid(1801), tests.ulid(1800), '1999-01-01',
   '2026-06-15T00:00:00Z', 'America/Los_Angeles', 'bbt', now());
select is((select local_date from public.observations where id = tests.ulid(1815)), '2026-06-14'::date,
  'America/Los_Angeles (-07:00): 2026-06-15T00:00Z is still 2026-06-14 17:00 local -- a day behind the UTC date');

-- ---------------------------------------------------------------------------
-- Null observed_at: local_date is left exactly as supplied, on both insert
-- and a later update -- the honest "date-only" (Clue import) case.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(1816), tests.ulid(1801), tests.ulid(1800), '2026-05-01', null, 'UTC', 'flow',
   now(), tests.get_supabase_uid('tz_mom'), tests.get_supabase_uid('tz_mom'));
select is((select local_date from public.observations where id = tests.ulid(1816)), '2026-05-01'::date,
  'null observed_at on insert: local_date is left exactly as supplied');

update public.observations
   set intensity = 2, last_modified_by_user_id = tests.get_supabase_uid('tz_mom')
 where id = tests.ulid(1816);
select is((select local_date from public.observations where id = tests.ulid(1816)), '2026-05-01'::date,
  'null observed_at on a later update: local_date is still untouched');

-- ---------------------------------------------------------------------------
-- Through sync_push's p_observations path: the trigger applies to its
-- inserts/updates automatically. sync_push ALSO now derives v_local_date
-- itself, ahead of the trigger, precisely so its own per-day cap and
-- same-date dedup checks (below) see the same corrected value the trigger
-- will independently recompute -- see the migration header, item 4 (review
-- fix), and the three collision-focused blocks that follow this one.
-- ---------------------------------------------------------------------------
select public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1817), 'day_entry_id', tests.ulid(1801), 'profile_id', tests.ulid(1800),
    -- Deliberately wrong local_date -- sync_push accepts whatever the
    -- client sent for it, but the trigger must overwrite it from
    -- observed_at/tz before the row is actually stored.
    'local_date', '1999-01-01', 'observed_at', '2026-03-08T12:00:00Z', 'tz', 'America/New_York',
    'category', 'bbt', 'updated_at', '2026-03-08T12:05:00Z')));
select is((select local_date from public.observations where id = tests.ulid(1817)), '2026-03-08'::date,
  'sync_push p_observations: the trigger derives local_date from observed_at/tz, overriding the client-supplied value');

select public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1818), 'day_entry_id', tests.ulid(1801), 'profile_id', tests.ulid(1800),
    'local_date', '2026-04-15', 'tz', 'UTC',
    'category', 'flow', 'updated_at', '2026-04-15T09:00:00Z')));
select is((select local_date from public.observations where id = tests.ulid(1818)), '2026-04-15'::date,
  'sync_push p_observations: with no observed_at, local_date is preserved exactly as sent (date-only import via the RPC)');

-- ---------------------------------------------------------------------------
-- (a) Review fix regression: sync_push's per-day cap must be evaluated on
-- the DERIVED local_date (from observed_at/tz), not the client-supplied
-- local_date key. Seed 200 live observations on 2026-07-01 (the cap),
-- then push a 201st whose client-supplied local_date is a DIFFERENT
-- (uncapped) day but whose observed_at derives (tz UTC) to 2026-07-01 --
-- the already-full day. Before the fix, this push's cap check ran against
-- the client-supplied day (empty, so it would pass) and only landed on
-- the capped day once the trigger corrected local_date afterwards,
-- silently exceeding the 200 cap. After the fix, the cap check itself
-- runs against 2026-07-01 and rejects the row.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code, updated_at,
   logged_by_user_id, last_modified_by_user_id)
select
  tests.ulid(2000 + i), tests.ulid(1801), tests.ulid(1800), '2026-07-01',
  ('2026-07-01T08:00:00Z'::timestamptz), 'UTC', 'cap_fixture', 'cap_' || i,
  '2026-07-01T08:00:00Z'::timestamptz,
  tests.get_supabase_uid('tz_mom'), tests.get_supabase_uid('tz_mom')
  from generate_series(0, 199) as i;
select is(
  (select count(*)::integer from public.observations
    where profile_id = tests.ulid(1800) and local_date = '2026-07-01' and deleted_at is null),
  200, 'fixture: 2026-07-01 is seeded at the 200-observation cap');

select public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2201), 'day_entry_id', tests.ulid(1801), 'profile_id', tests.ulid(1800),
    -- Client-supplied local_date is a DIFFERENT, uncapped day; observed_at
    -- derives (UTC) to 2026-07-01, the already-full day.
    'local_date', '2026-07-02', 'observed_at', '2026-07-01T12:00:00Z', 'tz', 'UTC',
    'category', 'cap_fixture', 'code', 'cap_new', 'updated_at', '2026-07-01T12:05:00Z')));
select is(
  (select count(*)::integer from public.observations
    where profile_id = tests.ulid(1800) and local_date = '2026-07-01' and deleted_at is null),
  200,
  'review fix: a push deriving onto an already-capped day is rejected by the per-day cap '
  || '(evaluated on the derived date, not the stale client-supplied local_date)');
select is(
  (select count(*)::integer from public.observations where id = tests.ulid(2201)),
  0, 'the capped push was never stored at all (rejected inside sync_push''s per-row exception block)');

-- ---------------------------------------------------------------------------
-- (b) Review fix regression: sync_push's same-date (category, code) dedup
-- must resolve against the DERIVED local_date. A live sibling already
-- exists on 2026-08-01 for (category='pain', code='cramp'); the incoming
-- push's client-supplied local_date is a DIFFERENT day, but observed_at
-- derives (tz UTC) to 2026-08-01 -- the sibling's day -- with a later
-- updated_at, so it must win head-to-head and only one live row must
-- remain on 2026-08-01 for that (category, code). Before the fix, no
-- sibling lookup ever ran against 2026-08-01 (the check ran against the
-- client-supplied day, which has no sibling), so both rows would have
-- ended up live there once the trigger corrected the new row's stored
-- local_date -- two live rows for the same (category, code) on the same
-- day, exactly the invariant this dedup exists to prevent.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(2300), tests.ulid(1801), tests.ulid(1800), '2026-08-01',
   '2026-08-01T09:00:00Z', 'UTC', 'pain', 'cramp', '2026-08-01T09:00:00Z',
   tests.get_supabase_uid('tz_mom'), tests.get_supabase_uid('tz_mom'));

select public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2301), 'day_entry_id', tests.ulid(1801), 'profile_id', tests.ulid(1800),
    -- Client-supplied local_date is a DIFFERENT day; observed_at derives
    -- (UTC) to 2026-08-01, where the live sibling above already lives.
    'local_date', '2026-08-02', 'observed_at', '2026-08-01T15:00:00Z', 'tz', 'UTC',
    'category', 'pain', 'code', 'cramp', 'updated_at', '2026-08-01T15:05:00Z')));

select is(
  (select count(*)::integer from public.observations
    where profile_id = tests.ulid(1800) and local_date = '2026-08-01'
      and category = 'pain' and code = 'cramp' and deleted_at is null),
  1,
  'review fix: an insert deriving onto a day with a live same-(category, code) sibling resolves '
  || 'head-to-head -- exactly one live row remains on the derived day');
select is(
  (select local_date from public.observations where id = tests.ulid(2301)), '2026-08-01'::date,
  'the incoming row (later updated_at) wins and is stored live at the derived date, not the '
  || 'stale client-supplied one');
select is(
  (select deleted_at is not null from public.observations where id = tests.ulid(2300)), true,
  'the previously-live sibling loses head-to-head and becomes a tombstone');

-- ---------------------------------------------------------------------------
-- (c) Review fix regression: an UPDATE that changes ONLY observed_at (the
-- client-supplied local_date key is left exactly as it was) must still be
-- treated as a date move -- v_obs_check_collision must fire against the
-- newly-derived day, not the row's already-stored (and still
-- client-supplied) local_date. A row is created live on 2026-09-01; a
-- second, unrelated live sibling already occupies 2026-09-02 for the same
-- (category, code). The row is then updated with the SAME local_date key
-- ('2026-09-01', stale/unchanged) but a NEW observed_at that derives (tz
-- UTC) to 2026-09-02 -- the sibling's day -- and a later updated_at, so it
-- must win head-to-head there too.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(2400), tests.ulid(1801), tests.ulid(1800), '2026-09-01',
   '2026-09-01T10:00:00Z', 'UTC', 'mood', 'anxious', '2026-09-01T10:00:00Z',
   tests.get_supabase_uid('tz_mom'), tests.get_supabase_uid('tz_mom'));
insert into public.observations
  (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(2402), tests.ulid(1801), tests.ulid(1800), '2026-09-02',
   '2026-09-02T10:00:00Z', 'UTC', 'mood', 'anxious', '2026-09-02T10:00:00Z',
   tests.get_supabase_uid('tz_mom'), tests.get_supabase_uid('tz_mom'));

select public.sync_push('[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2400), 'day_entry_id', tests.ulid(1801), 'profile_id', tests.ulid(1800),
    -- Same id as the already-stored row above (this is an UPDATE); the
    -- client-supplied local_date key is UNCHANGED from what is already
    -- stored -- only observed_at moves, across a day boundary.
    'local_date', '2026-09-01', 'observed_at', '2026-09-02T10:30:00Z', 'tz', 'UTC',
    'category', 'mood', 'code', 'anxious', 'updated_at', '2026-09-02T10:35:00Z')));

select is(
  (select count(*)::integer from public.observations
    where profile_id = tests.ulid(1800) and local_date = '2026-09-02'
      and category = 'mood' and code = 'anxious' and deleted_at is null),
  1,
  'review fix: an UPDATE that changes only observed_at across a day boundary is treated as a date '
  || 'move -- the same-date dedup on the destination day (2026-09-02) still fires even though the '
  || 'client-supplied local_date key on the update never changed');
select is(
  (select local_date from public.observations where id = tests.ulid(2400)), '2026-09-02'::date,
  'the updated row (later updated_at) wins the move-in and is stored live at the derived '
  || '(new) date');
select is(
  (select deleted_at is not null from public.observations where id = tests.ulid(2402)), true,
  'the pre-existing sibling on the destination day loses head-to-head and becomes a tombstone');

select * from finish();
rollback;
