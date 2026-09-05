-- Migration: 20260905100000_realtime_publication.sql
-- Issue #77: make Supabase Realtime actually deliver co-caregiver sync
-- events. The client-side RealtimeSyncCoordinator was wired in PR #80, but
-- nothing added its two tables to the `supabase_realtime` publication, so
-- Realtime's `postgres_changes` never emitted anything for it to hear.
--
-- PRIVACY BOUNDARY (R3, KTD2) -- READ BEFORE EDITING:
-- public.day_entries stores `note` (up to 2000 chars), `tags`, and `flow` in
-- plaintext server-side. The coordinator only needs a wake signal -- it
-- discards the payload and calls syncEngine.requestSync(), with the
-- authoritative read staying on the RLS-checked sync pull -- so publishing
-- whole rows would broadcast minors' health-log content over a websocket to
-- every authorized subscriber on every write. The column lists below carry
-- only what RLS evaluation, filtering, and replica identity need:
--   * public.profiles:    id, user_id, updated_at, deleted_at, server_version
--   * public.day_entries: id, user_id, profile_id, updated_at, deleted_at,
--                          server_version
-- DO NOT widen either list to a bare `add table` (whole-row publication),
-- and DO NOT set `replica identity full` on either table "to fix" a missing
-- old-row image -- both would defeat this boundary by putting the excluded
-- columns back into the change payload. Both tables already use the default
-- replica identity (their primary key, (id, user_id)), and every column in
-- that key is already in the lists above, so no replica identity change is
-- needed at all.
--
-- `supabase_realtime` is created by the Supabase platform's own base
-- migrations, not by this repo. This migration guards for its existence and
-- checks `pg_publication_rel` before adding each table, so it is safe to
-- re-run (e.g. a local `db reset`) without erroring on an already-published
-- table.
--
-- OPERATIONAL WARNING: the guard below only checks *membership* -- if either
-- table is already a member of `supabase_realtime` (most plausibly because
-- someone flipped Supabase Studio's per-table "Enable Realtime" toggle,
-- which issues a bare whole-row `add table`), this migration sees it as
-- already present and skips it, silently leaving the whole-row publication
-- in place. Never use that dashboard toggle for `public.profiles` or
-- `public.day_entries` -- it bypasses the column-list guard above.

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception
      'supabase_realtime publication does not exist -- expected to already '
      'exist, created by the Supabase platform''s own base migrations';
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profiles'
  ) then
    alter publication supabase_realtime
      add table public.profiles (id, user_id, updated_at, deleted_at, server_version);
  end if;

  if not exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entries'
  ) then
    alter publication supabase_realtime
      add table public.day_entries (id, user_id, profile_id, updated_at, deleted_at, server_version);
  end if;
end $$;
