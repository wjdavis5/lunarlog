-- Coverage for 20260915200001_sync_push_tombstone_resurrection_guard.sql
-- (Coordinator review of PR #705, #263/#189, blocking finding 1): once
-- enforce_retention() (20260915200000_nightly_retention_job.sql)
-- hard-deletes a day_entries tombstone older than 180 days, "no stored row
-- for this id" is no longer only "a brand-new entry" -- it is also the
-- exact state left behind by a purge. sync_push's day_entries loop must
-- reject (never insert) an unknown id whose own updated_at already predates
-- that same 180-day window, while leaving every other path -- a fresh
-- unknown id, and an LWW decision against a row that still exists --
-- completely unaffected.
begin;
select plan(9);

select tests.create_supabase_user('mom_srg');

select tests.authenticate_as('mom_srg');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(950), 'display_name', 'Riley', 'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);

-- ---------------------------------------------------------------------------
-- 1. A stale (>180 days) push of an UNKNOWN id is rejected, not inserted.
-- ---------------------------------------------------------------------------
create temp table stale_unknown_result (v jsonb);
insert into stale_unknown_result select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(960), 'profile_id', tests.ulid(950), 'local_date', '2025-01-01',
    'tz', 'UTC', 'flow', 'light',
    'updated_at', to_char((now() - interval '181 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));

select is(
  (select jsonb_array_length(v -> 'rejected') from stale_unknown_result),
  1,
  'a 181-day-old push of an unknown day_entries id is rejected'
);
select is(
  (select count(*) from public.day_entries where id = tests.ulid(960)),
  0::bigint,
  'the stale unknown-id push never lands in day_entries -- no resurrection'
);

-- ---------------------------------------------------------------------------
-- 2. A FRESH push of an unknown id is inserted exactly as before -- the
--    guard only ever fires on a push older than the retention window.
-- ---------------------------------------------------------------------------
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(961), 'profile_id', tests.ulid(950), 'local_date', '2026-09-02',
    'tz', 'UTC', 'flow', 'medium', 'updated_at', '2026-09-02T00:00:00Z')));

select is(
  (select flow from public.day_entries where id = tests.ulid(961)),
  'medium',
  'a fresh push of an unknown day_entries id is still inserted normally'
);

-- ---------------------------------------------------------------------------
-- 3. Boundary: 179 days old (inside the window) is still inserted; 181 days
--    old (outside it) is rejected -- already proven above. Pins the exact
--    threshold rather than only "some old timestamp".
-- ---------------------------------------------------------------------------
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(962), 'profile_id', tests.ulid(950), 'local_date', '2025-01-02',
    'tz', 'UTC', 'flow', 'light',
    'updated_at', to_char((now() - interval '179 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));

select is(
  (select count(*) from public.day_entries where id = tests.ulid(962)),
  1::bigint,
  'a 179-day-old push of an unknown id -- still inside the window -- is inserted'
);

-- ---------------------------------------------------------------------------
-- 4. A stale UPDATE against a row that still EXISTS is completely
--    unaffected by this guard -- it follows ordinary LWW (declined, server
--    copy handed back in `resolved`), never the new "too old to accept as
--    new" rejection path, and the stored row is untouched.
-- ---------------------------------------------------------------------------
-- The initial insert must itself land inside the 180-day window (this is
-- an ordinary, unremarkable new entry, not the subject under test) -- the
-- point of this group is what happens on a LATER push against an id that
-- now EXISTS, however old that later push's own updated_at is.
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(963), 'profile_id', tests.ulid(950), 'local_date', '2025-01-03',
    'tz', 'UTC', 'flow', 'heavy',
    'updated_at', to_char((now() - interval '1 day') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));

select is(
  (select flow from public.day_entries where id = tests.ulid(963)),
  'heavy',
  'setup: a fresh, ordinary new entry is stored so the next push has something to decline against'
);

-- A push against that now-EXISTING id, carrying an updated_at older than
-- 180 days (i.e. inside the range the new guard would reject an UNKNOWN id
-- for), must still be handled as an ordinary LWW decline -- never as a
-- rejection -- because the guard only ever fires on the "no stored row"
-- branch. The stored row's own updated_at (-1 day) is newer than this
-- push's (-250 days), so LWW declines it regardless of the guard's
-- existence.
create temp table stale_update_result (v jsonb);
insert into stale_update_result select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(963), 'profile_id', tests.ulid(950), 'local_date', '2025-01-03',
    'tz', 'UTC', 'flow', 'light',
    'updated_at', to_char((now() - interval '250 days') at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))));

select is(
  (select jsonb_array_length(v -> 'rejected') from stale_update_result),
  0,
  'a stale update to an EXISTING row is never rejected by this guard -- it is an LWW decision, not a resurrection'
);
select is(
  (select jsonb_array_length(v -> 'resolved') from stale_update_result),
  1,
  'the stale update to an existing row is declined via ordinary LWW (server copy in resolved)'
);
select is(
  (select flow from public.day_entries where id = tests.ulid(963)),
  'heavy',
  'the existing row keeps its own (newer) value -- the older push never overwrote it'
);

-- ---------------------------------------------------------------------------
-- Structural: the function comment documents this migration's addition.
-- ---------------------------------------------------------------------------
select ok(
  (select obj_description('public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)'::regprocedure)
     like '%tombstone-purge window%'),
  'the sync_push function comment documents the resurrection guard'
);

select * from finish();
rollback;
