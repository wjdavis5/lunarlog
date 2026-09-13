-- Migration: 20260913022000_finite_timestamp_policy.sql
--
-- Issue #641 · LLA-058 (P2): "Alternate writes accept future and nonfinite
-- timestamps". The RPC-side +5-minute future ceiling (#566) only guards
-- `sync_push` itself. This migration closes the OTHER write boundaries —
-- the tables' raw `authenticated` column UPDATE grants (a direct PostgREST
-- `PATCH updated_at: "2100-01-01"` or `"infinity"` bypasses sync_push
-- entirely), and `bulk_import_entries` — plus the RPC's lower/nonfinite
-- edge (-infinity / pre-1970 values pass #566's future check). The Dart
-- timestamp decoder cannot represent `infinity`, so a nonfinite `updated_at`
-- stored through any path freezes LWW or fails pull decoding.
--
-- Approach: a single IMMUTABLE predicate, enforced as table CHECKs on the
-- three client-synced LWW tables, covers every write path at once — a raw
-- PATCH, `bulk_import_entries`, and `sync_push` (its per-row exception
-- handler turns the CHECK violation into a rejected row). No re-emission of
-- the ~900-line `sync_push` is required. The CHECK is deliberately a loose
-- finiteness/sanity backstop (1970..2100), NOT the tight +5-minute ceiling
-- that remains `sync_push`'s own job (#566): a real-world device clock is
-- never within decades of the bounds, while 2100 and `infinity` — the two
-- values the issue names — both fail.
--
-- What changed, by boundary:
--
--  1. `public.is_supported_timestamp(timestamptz)` (IMMUTABLE, search_path
--      locked): finite AND within [1970-01-01, 2100-01-01). `isfinite()`
--      rejects `infinity`/`-infinity`/`NaN`; the bounds reject absurd-but-
--      finite values (2100) and pre-1970 poison (-infinity, 1969, ...).
--      `NaN` on a `timestamptz` is rejected by `isfinite()` like the
--      infinities (a bare `ts = ts` self-comparison is the classic NaN
--      guard, but `isfinite` already excludes it).
--
--   2. `bulk_import_safe_timestamptz(text)` create-or-replaced (carrying
--      its prior 20260908190000 body verbatim plus one new arm): a parsed
--      value outside the supported finite range returns NULL, so
--      `bulk_import_entries`' existing per-row validation rejects the row
--      cleanly ("updated_at is not a valid timestamp") instead of letting
--      the value reach the INSERT and aborting the whole batch on the new
--      table CHECK.
--
--   3. Table CHECK constraints on the timestamp columns of the three
--      client-synced LWW tables:
--        profiles.updated_at/deleted_at/created_at
--        day_entries.updated_at/deleted_at
--        observations.updated_at/deleted_at
--      Each added `not valid` then `validate constraint`ed (the schema's
--      established pattern), so a pre-existing poison row surfaces as a
--      loud `validate` failure rather than being silently accepted — and,
--      before the CHECK is added, this migration cleans any historical
--      poison it finds by clamping nonfinite/out-of-range values to the
--      server's own `clock_timestamp()`. Clamping (rather than deleting or
--      failing) is the least-bad recovery for a value that freezes LWW:
--      the row stays recognisable, and its clock is un-poisong so a later
--      push can win normally again. Migrations run with `auth.uid()` NULL,
--      so `enforce_day_entry_attribution()`'s exemption lets these
--      statements run.
--
-- Coverage: supabase/tests/timestamp_policy_test.sql (new file) — raw
-- PATCH +inf/-inf/far-future on each table, a bulk row with a far-future
-- stamp rejected per-row (not batch-aborted), and the helper's own bounds.
--
-- No grants, policies, or trigger wiring change. `sync_push` is untouched
-- (its per-row handler + the new CHECKs already cover its edge).

-- ---------------------------------------------------------------------------
-- 1. is_supported_timestamp(timestamptz) -- the single predicate.
-- ---------------------------------------------------------------------------
create or replace function public.is_supported_timestamp(p_ts timestamptz)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_ts is not null
     and isfinite(p_ts)
     and p_ts >= '1970-01-01 00:00:00+00'::timestamptz
     and p_ts <  '2100-01-01 00:00:00+00'::timestamptz;
$$;

comment on function public.is_supported_timestamp(timestamptz) is
  'Issue #641 LLA-058: the finite/sane timestamp predicate. Finite (rejects '
  'infinity/-infinity/NaN) and within [1970-01-01, 2100-01-01) -- a '
  'deliberately loose backstop: a real device clock is never within decades '
  'of the bounds, while 2100 and infinity (the values the finding names) '
  'both fail. Enforced as table CHECKs so every write path (raw column '
  'UPDATE grants, bulk_import_entries, sync_push) is covered at once.';

revoke all on function public.is_supported_timestamp(timestamptz) from public, anon;

-- ---------------------------------------------------------------------------
-- 2. bulk_import_safe_timestamptz(text) -- tightened so bulk rejects
--    far-future/nonfinite rows per-row, never batch-aborts on the CHECK.
-- ---------------------------------------------------------------------------
create or replace function public.bulk_import_safe_timestamptz(p_text text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_text is null then
    return null;
  end if;
  -- Prior body (20260908190000) carried verbatim: 'infinity'/'-infinity'/
  -- 'now'/'today' all cast to timestamptz without raising, but none is a
  -- real, deterministic ISO timestamp.
  if lower(trim(p_text)) in ('infinity', '-infinity', 'now', 'today') then
    return null;
  end if;
  -- Issue #641 LLA-058: a value that parses but falls outside the supported
  -- finite range (e.g. '2100-01-01') must also read as "not a valid
  -- timestamp" so bulk_import_entries rejects that row cleanly, instead of
  -- reaching the INSERT and tripping the new day_entries table CHECK, which
  -- would abort the whole batch.
  if not public.is_supported_timestamp(p_text::timestamptz) then
    return null;
  end if;
  return p_text::timestamptz;
exception
  when others then
    return null;
end;
$$;

comment on function public.bulk_import_safe_timestamptz(text) is
  'Issue #167: text -> timestamptz that returns NULL instead of raising on '
  'a malformed value -- see bulk_import_safe_date''s comment, including the '
  'infinity / -infinity / now / today bounds check. Issue #641 '
  'LLA-058: additionally returns NULL for any parsed value outside the '
  'supported finite range (is_supported_timestamp), so bulk import rejects '
  'far-future/nonfinite rows per-row rather than batch-aborting on the '
  'day_entries timestamp CHECK.';

revoke all on function public.bulk_import_safe_timestamptz(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. Clean historical poison, then add the table CHECKs (`not valid` then
--    `validate constraint`ed -- the schema's established pattern).
-- ---------------------------------------------------------------------------

-- Clamp any already-stored nonfinite / out-of-range timestamp to the
-- server's own clock. Only ever touches rows that would fail the CHECK below
-- (a value that freezes LWW); never rewrites healthy clocks.
update public.profiles
   set updated_at = clock_timestamp()
 where not public.is_supported_timestamp(updated_at);
update public.profiles
   set deleted_at = clock_timestamp()
 where deleted_at is not null
   and not public.is_supported_timestamp(deleted_at);
update public.profiles
   set created_at = clock_timestamp()
 where not public.is_supported_timestamp(created_at);

update public.day_entries
   set updated_at = clock_timestamp()
 where not public.is_supported_timestamp(updated_at);
update public.day_entries
   set deleted_at = clock_timestamp()
 where deleted_at is not null
   and not public.is_supported_timestamp(deleted_at);

update public.observations
   set updated_at = clock_timestamp()
 where not public.is_supported_timestamp(updated_at);
update public.observations
   set deleted_at = clock_timestamp()
 where deleted_at is not null
   and not public.is_supported_timestamp(deleted_at);

alter table public.profiles
  add constraint profiles_updated_at_supported check (public.is_supported_timestamp(updated_at))
  not valid;
alter table public.profiles
  add constraint profiles_deleted_at_supported check (deleted_at is null or public.is_supported_timestamp(deleted_at))
  not valid;
alter table public.profiles
  add constraint profiles_created_at_supported check (public.is_supported_timestamp(created_at))
  not valid;

alter table public.day_entries
  add constraint day_entries_updated_at_supported check (public.is_supported_timestamp(updated_at))
  not valid;
alter table public.day_entries
  add constraint day_entries_deleted_at_supported check (deleted_at is null or public.is_supported_timestamp(deleted_at))
  not valid;

alter table public.observations
  add constraint observations_updated_at_supported check (public.is_supported_timestamp(updated_at))
  not valid;
alter table public.observations
  add constraint observations_deleted_at_supported check (deleted_at is null or public.is_supported_timestamp(deleted_at))
  not valid;

alter table public.profiles validate constraint profiles_updated_at_supported;
alter table public.profiles validate constraint profiles_deleted_at_supported;
alter table public.profiles validate constraint profiles_created_at_supported;
alter table public.day_entries validate constraint day_entries_updated_at_supported;
alter table public.day_entries validate constraint day_entries_deleted_at_supported;
alter table public.observations validate constraint observations_updated_at_supported;
alter table public.observations validate constraint observations_deleted_at_supported;
