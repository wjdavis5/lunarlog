-- ===========================================================================
-- 20261009120000_guardian_notes_realtime_never_publish.sql
-- Issue #1707 (review finding, bug/P3): "reconcile_realtime_publication
-- omits guardian_notes from its never-publish list".
--
-- guardian_notes (20260918150000) is a synced content table: it carries a
-- touch_sync_signal() trigger, so co-guardians learn of a change through the
-- content-free sync_signals wake and re-read through the RLS-checked pull --
-- and it holds free-text notes a guardian writes about a child, exactly the
-- category of payload the publication boundary exists to keep off the
-- websocket. Every later-added content table had been added to the list by
-- its own migration's re-emission of this function; guardian_notes was
-- missed, so a Studio "Enable Realtime" toggle on it would have stayed
-- published: the next deploy and the weekly reconcile run the function,
-- find their curated list satisfied, and never drop it. RLS still scoped
-- what a subscriber could read, but the publication-membership boundary
-- this repo treats as inviolable had a hole for a health-content table.
--
-- Fix: re-emit reconcile_realtime_publication() from its current definition
-- (20260918000000_day_entry_history.sql, unchanged since) with
-- guardian_notes on the must-never-publish list, and update the FOR ALL
-- TABLES exception message and the function comment to match.
--
-- The accompanying test change (supabase/tests/realtime_publication_test.sql)
-- stops hand-restating the expected list: it derives every synced table from
-- information_schema.triggers (the touch_sync_signal carriers), publishes
-- them all whole-row, runs the reconcile, and asserts the publication is
-- back to exactly {sync_signals} -- so a future synced table cannot be
-- forgotten the same way.
--
-- No table/column/index change; supabase/database.types.ts is unchanged
-- (the function's signature does not change).
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- reconcile_realtime_publication(): re-emitted from its current definition
-- (20260918000000_day_entry_history.sql, unchanged since) with guardian_notes
-- on the must-never-publish list (Issue #1707).
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

  -- Issue #240 review finding: observations joins day_entries/profiles on
  -- this must-never-be-published list -- it carries the same category of
  -- sensitive per-entry content (symptom/option detail) that day_entries
  -- was excluded for, and nothing about this table was ever meant to reach
  -- the client any way other than the existing sync_signals wake-signal +
  -- an authenticated sync_push/read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'observations'
  ) then
    alter publication supabase_realtime drop table public.observations;
  end if;

  -- Issue #167: import_jobs joins this must-never-be-published list --
  -- no health content, but a per-user tracking table with no reason to
  -- reach the client any way other than an authenticated read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'import_jobs'
  ) then
    alter publication supabase_realtime drop table public.import_jobs;
  end if;

  -- Issue #188: profile_modes and cycle_overrides join this
  -- must-never-be-published list -- a profile's reproductive-life-stage
  -- state and cycle corrections are exactly the category of sensitive
  -- content day_entries/profiles/observations were excluded for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profile_modes'
  ) then
    alter publication supabase_realtime drop table public.profile_modes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'cycle_overrides'
  ) then
    alter publication supabase_realtime drop table public.cycle_overrides;
  end if;

  -- Issue #128: care_notes and visit_prep_items join this
  -- must-never-be-published list -- standing care notes and visit-prep
  -- checklists are exactly the category of sensitive health content
  -- about a minor that day_entries/profiles/observations were excluded
  -- for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'care_notes'
  ) then
    alter publication supabase_realtime drop table public.care_notes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'visit_prep_items'
  ) then
    alter publication supabase_realtime drop table public.visit_prep_items;
  end if;

  -- Issue #151: the prediction tables join the never-publish list --
  -- token hashes (prediction_connections) and the derived payload
  -- (prediction_projections) must never cross the websocket.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_connections'
  ) then
    alter publication supabase_realtime drop table public.prediction_connections;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_projections'
  ) then
    alter publication supabase_realtime drop table public.prediction_projections;
  end if;

  -- Issue #130: day_entry_merge_events joins the never-publish list -- a
  -- merge-disclosure row retains the LOSING guardian's discarded note text
  -- (health content about a minor), exactly the category of payload that
  -- must never cross the websocket. Co-guardians still learn a merge
  -- happened promptly via the table's touch_sync_signal() trigger (a
  -- content-free sync_signals wake), and re-read through the RLS-checked
  -- pull -- the same posture every content table here already uses.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entry_merge_events'
  ) then
    alter publication supabase_realtime drop table public.day_entry_merge_events;
  end if;

  -- Issue #257: profile_tag_registry joins the never-publish list -- a
  -- custom tag's user-authored display name is health vocabulary about a
  -- potentially minor profile, exactly the category of payload that must
  -- never cross the websocket. Co-guardians still learn a registry change
  -- happened via the table's touch_sync_signal() trigger (a content-free
  -- sync_signals wake) and re-read through the RLS-checked pull -- the
  -- same posture every content table here already uses.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profile_tag_registry'
  ) then
    alter publication supabase_realtime drop table public.profile_tag_registry;
  end if;

  -- Issue #170: day_entry_history joins the never-publish list -- the
  -- table is content-free by construction (column names only, CHECK-
  -- enforced), but a feed of who-changed-what metadata about a
  -- potentially minor profile's health records is still not websocket
  -- payload, and no Realtime consumer exists for it anyway: co-guardians
  -- learn a change happened from day_entries' own sync_signals wake and
  -- re-read through the RLS-checked pull -- the same posture every
  -- content table here already uses.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entry_history'
  ) then
    alter publication supabase_realtime drop table public.day_entry_history;
  end if;

  -- Issue #1707: guardian_notes joins the never-publish list -- a free-text
  -- note a guardian writes about a child is exactly the category of
  -- sensitive health content day_entries/profiles/observations were excluded
  -- for, and no Realtime consumer exists for it: co-guardians learn a note
  -- changed from the table's touch_sync_signal() trigger (a content-free
  -- sync_signals wake) and re-read through the RLS-checked pull -- the same
  -- posture every content table here already uses.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'guardian_notes'
  ) then
    alter publication supabase_realtime drop table public.guardian_notes;
  end if;

  -- If `supabase_realtime` was ever switched to FOR ALL TABLES (which would
  -- silently republish day_entries/profiles/observations/import_jobs
  -- whole-row regardless of the per-table checks above), that is a
  -- platform-level misconfiguration this function cannot safely undo (it
  -- would also drop unrelated tables this repo does not own). Fail loudly
  -- instead of pretending the guard above was sufficient.
  select puballtables into v_all_tables
    from pg_catalog.pg_publication
   where pubname = 'supabase_realtime';

  if v_all_tables then
    raise exception
      'supabase_realtime is FOR ALL TABLES -- this publishes public.profiles, '
      'public.day_entries, public.observations, public.import_jobs, '
      'public.profile_modes, public.cycle_overrides, public.care_notes, public.visit_prep_items, '
      'public.prediction_connections, public.prediction_projections, '
      'public.day_entry_merge_events, public.profile_tag_registry, '
      'public.day_entry_history, and public.guardian_notes '
      'whole-row and must be '
      'fixed manually before this migration can proceed (see the migration '
      'header comment)';
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
  'exactly profile_id, updated_at) and never public.profiles/day_entries/'
  'observations/profile_modes/cycle_overrides/care_notes/visit_prep_items/'
  'prediction_connections/prediction_projections/day_entry_merge_events/'
  'profile_tag_registry/day_entry_history/guardian_notes '
  '(Issue #240 added observations to this list; Issue #188 added the two '
  'mode tables; Issue #128 added care_notes/visit_prep_items; Issue #151 '
  'added the two prediction tables; Issue #130 added '
  'day_entry_merge_events; Issue #257 added profile_tag_registry; Issue '
  '#170 added day_entry_history; Issue #1707 added guardian_notes), drift '
  '(e.g. a Studio "Enable Realtime" toggle) rather than skipping an '
  'already-published table (Issue #77 P1 fix). '
  'Not an API function -- runs only from migrations and from pgTAP (as an '
  'unrestricted role); execute is revoked from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;

select public.reconcile_realtime_publication();
