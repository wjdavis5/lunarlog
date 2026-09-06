-- Migration: 20260905100000_realtime_publication.sql
-- Issue #77: make Supabase Realtime actually deliver co-caregiver sync
-- events. The client-side RealtimeSyncCoordinator was wired in PR #80, but
-- nothing published anything to the `supabase_realtime` publication, so
-- Realtime's `postgres_changes` never emitted anything for it to hear.
--
-- PRIVACY BOUNDARY (R3, KTD2) -- READ BEFORE EDITING:
-- public.day_entries stores `note` (up to 2000 chars), `tags`, and `flow` in
-- plaintext server-side. An earlier version of this migration tried to keep
-- that content off the websocket by publishing `public.day_entries`/
-- `public.profiles` directly with a narrow publication column list. THAT
-- DOES NOT WORK: Supabase Realtime's WALRUS decodes the replication stream
-- with wal2json, which only uses a publication as a table-level
-- "which tables am I watching" list -- publication column lists are a
-- pgoutput-only feature (`\d+` in psql shows them, but they are inert for
-- wal2json/Realtime). The filter Realtime actually applies per column is
-- `has_column_privilege(<role>, <table>, <column>, 'SELECT')`, and this repo
-- grants table-wide `select` on `day_entries`/`profiles` to `authenticated`
-- (20260903014208_initial_sync_schema.sql) so every column -- including
-- note/tags/flow -- passes that check and is delivered over the websocket
-- to every authorized subscriber, regardless of what the publication's
-- column list says.
--
-- The fix (this migration): never publish `public.day_entries` or
-- `public.profiles` to Realtime at all -- neither whole-row nor
-- column-scoped. Instead:
--   1. A dedicated table, `public.sync_signals`, carries only
--      (profile_id, updated_at) -- no health content, ever, by
--      construction, not by grant/policy discipline that a future migration
--      could quietly undermine.
--   2. AFTER triggers on `profiles` and `day_entries` upsert that table's
--      row for the affected profile on every insert/update/delete.
--   3. `public.sync_signals` -- not the source tables -- is the thing
--      published to `supabase_realtime`.
--   4. `RealtimeSyncCoordinator` subscribes to `sync_signals` filtered by
--      `profile_id`. It already treats every event purely as a wake signal
--      (it discards the payload and calls `syncEngine.requestSync()`), so
--      this is a transport change only -- the authoritative read stays on
--      the RLS-checked sync pull. See U3 in the plan for the client change.
-- This is the standard "dirty-signal" pattern for this exact problem: make
-- the thing that's public safe by construction, rather than trying to make
-- a sensitive table safe to publish.
--
-- DO NOT add `public.day_entries` or `public.profiles` to `supabase_realtime`
-- -- with or without a column list -- for the reasons above. If a future
-- change needs richer live data than a bare wake signal, it must go through
-- a `SECURITY DEFINER` RPC the client calls explicitly after being notified,
-- not a table publication.
--
-- `supabase_realtime` is created by the Supabase platform's own base
-- migrations, not by this repo. This migration guards for its existence.
--
-- OPERATIONAL WARNING: never use Supabase Studio's per-table "Enable
-- Realtime" toggle on `public.profiles` or `public.day_entries` -- it issues
-- a bare whole-row `alter publication ... add table`, which is exactly the
-- leak this migration exists to prevent. The guard below (`select
-- public.reconcile_realtime_publication();`, the last line of this file)
-- checks membership, `puballtables`, and the published column set for
-- `sync_signals` every time it *runs* (not just "is it a member"), and
-- actively removes `profiles`/`day_entries` if either is ever found
-- published -- but this migration file itself only runs once per
-- environment (a fresh `db reset`, or a brand-new environment applying
-- every migration from scratch). An ordinary `supabase db push` against an
-- environment where this migration has already been applied does NOT
-- re-run it -- `db push` only applies migrations not yet recorded as
-- applied, so a Studio toggle used against an already-migrated environment
-- would sit live-leaking until something else re-invokes the guard.
-- `.github/workflows/supabase-migrate.yml` closes that gap operationally:
-- its "Reconcile Realtime publication" step calls
-- `select public.reconcile_realtime_publication();` via
-- `supabase db query --linked` immediately after every `db push`, so drift
-- introduced through the Studio toggle is caught and reverted on every
-- deploy to `main`, not just on a from-scratch environment build. (There is
-- still no *periodic* reconciliation between deploys -- see the tracked
-- follow-up in AGENTS.md's Migration Flow section.)

-- ---------------------------------------------------------------------------
-- public.sync_signals: the dedicated wake-signal table. One row per profile,
-- holding nothing but its id and a timestamp -- there is no column here that
-- could ever carry health content, so there is no grant/RLS-column-privilege
-- discipline for a future change to accidentally undermine (KTD2, this file's
-- header comment).
-- ---------------------------------------------------------------------------

create table public.sync_signals (
  profile_id text not null
    constraint sync_signals_profile_id_ulid_check
    check (profile_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  updated_at timestamptz not null default now(),
  primary key (profile_id)
);

comment on table public.sync_signals is
  'Realtime wake signal (Issue #77): one row per profile, touched by triggers '
  'on profiles/day_entries. Carries no health content by construction -- this '
  'is the only table this app publishes to supabase_realtime. Clients treat '
  'any event on it as "go re-pull the real row via the RLS-checked sync '
  'pull", never as a payload to trust.';

alter table public.sync_signals enable row level security;
alter table public.sync_signals force row level security;

create policy "sync_signals_select_guardians" on public.sync_signals
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

-- No insert/update/delete grant to authenticated: the only writer is the
-- SECURITY DEFINER trigger below, which runs as the function owner and so is
-- unaffected by this revoke. A direct client write here would be pointless
-- (the row content carries no meaning beyond "something changed") but is
-- still denied on principle -- see KTD15 elsewhere in this schema.
revoke all on table public.sync_signals from public, anon, authenticated;
grant select on table public.sync_signals to authenticated;

create or replace function public.touch_sync_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id text;
begin
  if tg_table_name = 'profiles' then
    v_profile_id := coalesce(new.id, old.id);
  else
    v_profile_id := coalesce(new.profile_id, old.profile_id);
  end if;

  -- Orphan cleanup for a hard profile delete (e.g. account deletion
  -- cascading via profiles.user_id -> auth.users(id) on delete cascade),
  -- PR #92 review round 2. Deliberately NOT solved by adding
  -- `references public.profiles(id) on delete cascade` to sync_signals --
  -- that was tried and reverted: the cascade removes the sync_signals row
  -- first, then this trigger's own upsert below tries to reinsert it
  -- against a profile that no longer exists and errors, aborting the whole
  -- profile deletion.
  --
  -- Instead: whichever table fired this trigger, check whether the
  -- profile itself currently exists, and delete-not-upsert if it doesn't.
  -- This has to be an existence check rather than "only handle it in the
  -- profiles branch, and rely on trigger firing order to run last" --
  -- empirically, on a cascaded delete (profile + its day_entries in one
  -- statement) the day_entries row's own AFTER DELETE trigger fires
  -- *after* the profiles row's AFTER DELETE trigger, not before, so a
  -- profiles-only delete branch got its cleanup silently undone by the
  -- day_entries trigger's upsert running later in the same statement (this
  -- was caught by supabase/tests/realtime_publication_test.sql, not
  -- assumed). Checking existence here instead is correct regardless of
  -- which trigger runs first or last: whichever one fires last still sees
  -- the profile already gone and still deletes rather than upserts.
  if not exists (select 1 from public.profiles where id = v_profile_id) then
    delete from public.sync_signals where profile_id = v_profile_id;
    return null;
  end if;

  insert into public.sync_signals (profile_id, updated_at)
  values (v_profile_id, now())
  on conflict (profile_id) do update set updated_at = excluded.updated_at;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

comment on function public.touch_sync_signal() is
  'Upserts public.sync_signals(profile_id) on every profiles/day_entries '
  'change, unless the owning profile no longer exists (a hard profile '
  'delete), in which case it deletes the row instead -- so Realtime has a '
  'content-free row to publish and profile deletion never leaves an '
  'orphaned signal row behind (Issue #77).';

revoke execute on function public.touch_sync_signal() from public, anon;

create trigger profiles_after_change_signal
  after insert or update or delete on public.profiles
  for each row execute function public.touch_sync_signal();

create trigger day_entries_after_change_signal
  after insert or update or delete on public.day_entries
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- public.reconcile_realtime_publication(): the guard, as a callable function
-- rather than an inline anonymous block, specifically so
-- supabase/tests/realtime_publication_test.sql can corrupt the publication
-- state (simulating a Supabase Studio "Enable Realtime" toggle) and call
-- this again to prove it *corrects* rather than skips -- that is the P1 fix:
-- the old version of this migration only checked membership, so a table
-- already published whole-row read as "already correct" and was left alone.
-- Re-runnable: a local `db reset` re-applies every migration, and this
-- function's own logic is the thing making that safe.
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_realtime_publication()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signals_col_list name[] := array['profile_id', 'updated_at']::name[];
  v_current_cols name[];
  v_all_tables boolean;
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception
      'supabase_realtime publication does not exist -- expected to already '
      'exist, created by the Supabase platform''s own base migrations';
  end if;

  -- Never let day_entries or profiles be published, in any form. Checks
  -- *and corrects* rather than only checking membership, so a whole-row
  -- publication left behind by Supabase Studio's "Enable Realtime" toggle
  -- (or a future edit that widens this migration) is actively reverted
  -- instead of being treated as already-correct and skipped.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entries'
  ) then
    alter publication supabase_realtime drop table public.day_entries;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profiles'
  ) then
    alter publication supabase_realtime drop table public.profiles;
  end if;

  -- If `supabase_realtime` was ever switched to FOR ALL TABLES (which would
  -- silently republish day_entries/profiles whole-row regardless of the
  -- per-table checks above), that is a platform-level misconfiguration this
  -- function cannot safely undo (it would also drop unrelated tables this
  -- repo does not own). Fail loudly instead of pretending the guard above
  -- was sufficient.
  select puballtables into v_all_tables
    from pg_catalog.pg_publication
   where pubname = 'supabase_realtime';

  if v_all_tables then
    raise exception
      'supabase_realtime is FOR ALL TABLES -- this publishes public.profiles '
      'and public.day_entries whole-row and must be fixed manually before '
      'this migration can proceed (see the migration header comment)';
  end if;

  -- public.sync_signals: the only table this app publishes to Realtime.
  -- Correct both membership and the published column list -- not just
  -- membership -- so a Studio toggle (which would publish every column) is
  -- detected and repaired rather than skipped as "already there".
  select attnames
    into v_current_cols
    from pg_catalog.pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'sync_signals';

  if v_current_cols is null then
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  elsif (select array_agg(c order by c) from unnest(v_current_cols) as c)
        is distinct from (
          select array_agg(c order by c) from unnest(v_signals_col_list) as c
        ) then
    -- Column set drifted from what this function intends (e.g. a Studio
    -- toggle re-added the table whole-row) -- correct it rather than skip.
    alter publication supabase_realtime drop table public.sync_signals;
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  end if;
end;
$$;

comment on function public.reconcile_realtime_publication() is
  'Ensures supabase_realtime publishes only public.sync_signals (with '
  'exactly profile_id, updated_at) and never public.profiles/day_entries, '
  'correcting drift (e.g. a Studio "Enable Realtime" toggle) rather than '
  'skipping an already-published table (Issue #77 P1 fix). Not an API '
  'function -- runs only from this migration and from pgTAP (as an '
  'unrestricted role); execute is revoked from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;

select public.reconcile_realtime_publication();
