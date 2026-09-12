-- Migration: 20260913015000_sync_watermark.sql
--
-- Issue #521 (P1) - SERVER HALF ONLY (the client's cursor-clamping change
-- against this RPC is Dart-side and out of scope for this PR).
--
-- =============================================================================
-- The problem, restated
-- =============================================================================
-- `server_version` comes from `nextval('public.sync_version_seq')`, called
-- PRE-COMMIT inside `set_server_version()`. `nextval()` order is
-- ASSIGNMENT order, not COMMIT order: transaction A can grab version 100
-- and then take longer to commit than transaction B, which grabs 101 and
-- commits first. A client polling `server_version > cursor` between the
-- two commits sees only 101, advances its cursor to 101, and - because the
-- pull is a strict `>` - can NEVER see version 100 once A finally commits
-- (100 < 101). `sync_push`'s per-USER advisory lock
-- (`pg_advisory_xact_lock(hashtext(v_uid::text))`, issue #14) does not
-- close this: two different guardians writing the SAME shared profile
-- take DIFFERENT locks (20260910171042_sync_push_lock_order.sql says so
-- outright), and several writers - `bulk_import_entries`,
-- `accept_guardian_invitation`, `revoke_guardian`, `update_guardian_role`,
-- `accept_ownership_transfer`, the `profiles_after_insert_guardian`
-- trigger - take no lock at all.
--
-- =============================================================================
-- Why a bookkeeping table, not a snapshot-xmin mapping
-- =============================================================================
-- The issue's preferred fix asks for a watermark "derived from
-- pg_snapshot_xmin(pg_current_snapshot())". That function reports the
-- oldest transaction ID that was STILL RUNNING when the snapshot was
-- taken - a property of TRANSACTION IDs, not of `server_version` (a
-- separate, ordinary bigint sequence with no defined relationship to xid
-- order: two transactions can commit in either order regardless of which
-- one grabbed the lower `nextval()` value first, and a single transaction
-- can call `nextval()` many times across many rows). There is no
-- catalog-derivable function from "oldest in-progress xid" to "highest
-- server_version safe to expose" - you would need to know, for every
-- in-progress xid, the LOWEST server_version IT PERSONALLY has claimed
-- (not claimed by any other xid), which nothing in `pg_current_snapshot()`
-- or `pg_snapshot_xmin()` tracks. That mapping has to be recorded by the
-- code doing the claiming - hence the issue's own fallback: "you may need
-- a sync_inflight(xid, server_version) bookkeeping approach."
--
-- =============================================================================
-- Design
-- =============================================================================
-- `public.sync_inflight(xid bigint primary key, min_version bigint not
-- null, created_at timestamptz not null default clock_timestamp())`:
-- one row per transaction that has claimed at least one server_version
-- this commit cycle, recording the LOWEST version it claimed (the first
-- `nextval()` call in a transaction is its own floor - every later call in
-- the SAME transaction only claims a higher value, which is already
-- covered by the floor). `set_server_version()` (re-emitted below,
-- SECURITY DEFINER now instead of INVOKER so it can write to this table
-- without needing a new column grant for every synced-table writer -
-- `authenticated` gets no direct grant on sync_inflight at all, matching
-- KTD15) inserts this row with `on conflict (xid) do nothing`, so only the
-- FIRST call within a transaction actually claims the floor; a rollback
-- discards the row automatically (it was inserted in the same,
-- now-aborted transaction); a commit leaves it behind, resolved, until
-- cleanup removes it (see below).
--
-- `public.sync_watermark()`: the commit-safe cursor ceiling. Computes
-- `min(min_version) - 1` over every `sync_inflight` row whose xid
-- `txid_status()` still reports 'in progress' (a row whose transaction has
-- committed, aborted, or aged out of the commit log entirely -
-- `txid_status` returns NULL for the last case, which the `= 'in
-- progress'` filter also excludes - no longer counts, since that
-- transaction's fate is already decided one way or another). With no
-- in-progress writer at all, the watermark is simply the sequence's
-- current `last_value` - the highest version anyone has ever been given,
-- safe to expose in full since everything at or below it is resolved.
--
-- Client contract: `newCursor = min(maxVersion(page), sync_watermark())`
-- (the issue's own clamp formula) - a Dart-side change, out of scope here.
--
-- Cleanup, so the bookkeeping table cannot grow unbounded even before any
-- client adopts sync_watermark() (which would otherwise be the only thing
-- ever deleting a row): `set_server_version()` itself opportunistically
-- deletes a bounded batch of resolved rows on ~1% of its own invocations -
-- cheap (a `random()` guard keeps it off the hot path almost always) and
-- makes correctness independent of adoption timing.
--
-- Also folds in the issue's second, one-line fix: `hashtext()` is `int4`
-- and can collide across different UUIDs; every advisory-lock call in this
-- schema keyed on a UUID should use `hashtextextended(text, 0)` (`int8`,
-- collision-astronomically-unlikely) instead. sync_push's own
-- `pg_advisory_xact_lock(hashtext(v_uid::text))` call is switched in
-- 20260913016000_sync_push_hardening.sql (the consolidated sync_push
-- re-emission) rather than here, since it requires re-emitting that
-- function's full body per this task's migration-authoring rule.
--
-- Coverage: supabase/tests/sync_watermark_test.sql.

-- ---------------------------------------------------------------------------
-- 1. public.sync_inflight
-- ---------------------------------------------------------------------------

create table if not exists public.sync_inflight (
  xid bigint primary key,
  min_version bigint not null,
  created_at timestamptz not null default clock_timestamp()
);

comment on table public.sync_inflight is
  'Issue #521: one row per transaction currently holding at least one '
  'unclaimed (not-yet-committed) public.sync_version_seq value, recording '
  'the LOWEST such value it claimed. Written by set_server_version(); read '
  'and opportunistically cleaned by both set_server_version() (~1%% of '
  'calls) and public.sync_watermark(). No client-facing grant - see this '
  'migration''s header.';

revoke all on table public.sync_inflight from public, anon, authenticated;

-- RLS enabled (even with no grant to any client-facing role and no policy
-- at all, so it is unreadable and unwritable by anything but a SECURITY
-- DEFINER function running as the table owner) purely for schema hygiene -
-- this repo's own pgTAP suite asserts every public table has RLS enabled
-- (tests.rls_enabled), regardless of whether a table is client-facing.
alter table public.sync_inflight enable row level security;
alter table public.sync_inflight force row level security;

-- ---------------------------------------------------------------------------
-- 2. set_server_version(): re-emitted SECURITY DEFINER (was INVOKER) so it
--    can write sync_inflight without a new grant; behaviourally identical
--    for every existing caller (nextval() needs no privilege a SECURITY
--    DEFINER call lacks - it never needed a caller-specific grant beyond
--    USAGE on the sequence, which the function owner already holds).
-- ---------------------------------------------------------------------------

create or replace function public.set_server_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version bigint;
begin
  v_version := nextval('public.sync_version_seq');
  new.server_version := v_version;

  insert into public.sync_inflight (xid, min_version)
  values (txid_current(), v_version)
  on conflict (xid) do nothing;

  -- Opportunistic, bounded cleanup (~1% of calls) so the table never
  -- depends on sync_watermark() actually being called to stay small.
  if random() < 0.01 then
    delete from public.sync_inflight
     where xid in (
       select xid from public.sync_inflight
        where txid_status(xid) is distinct from 'in progress'
        limit 500
     );
  end if;

  return new;
end;
$$;

comment on function public.set_server_version() is
  'Stamps server_version from public.sync_version_seq on every insert/update '
  '(the pull cursor, KTD2), and records this transaction''s floor claim in '
  'public.sync_inflight for public.sync_watermark() (Issue #521). SECURITY '
  'DEFINER (changed from INVOKER) so it can write sync_inflight without a '
  'grant on that table for any synced-table writer.';

-- ---------------------------------------------------------------------------
-- 3. sync_watermark()
-- ---------------------------------------------------------------------------

create or replace function public.sync_watermark()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_min_inflight bigint;
  v_last_issued bigint;
begin
  if v_uid is null then
    raise exception 'sync_watermark requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  -- Opportunistic cleanup here too - a client that adopts sync_watermark()
  -- and calls it every sync cycle keeps the table small on its own.
  delete from public.sync_inflight
   where xid in (
     select xid from public.sync_inflight
      where txid_status(xid) is distinct from 'in progress'
      limit 500
   );

  select min(min_version) into v_min_inflight
    from public.sync_inflight
   where txid_status(xid) = 'in progress';

  select last_value into v_last_issued from public.sync_version_seq;

  return coalesce(v_min_inflight - 1, v_last_issued);
end;
$$;

comment on function public.sync_watermark() is
  'Issue #521: the commit-safe pull-cursor ceiling. Returns min_version - 1 '
  'over every still-in-progress transaction in public.sync_inflight (or the '
  'sync sequence''s current last_value when nothing is in flight) - the '
  'highest server_version a client can safely advance its cursor to without '
  'risking a later-committing, lower-numbered row becoming permanently '
  'unreachable (`server_version > cursor` is a strict pull, so a gap is '
  'never revisited). Client contract: `newCursor = min(maxVersion(page), '
  'sync_watermark())` - Dart-side adoption is out of scope for this '
  'migration. See this migration''s header for the full design and why an '
  'xmin-to-server_version mapping is not derivable from catalog state '
  'alone.';

revoke all on function public.sync_watermark() from public, anon;
grant execute on function public.sync_watermark() to authenticated;
