-- Migration: 20260908190000_bulk_import.sql
-- Issue #167 (P0, epic: Import): bulk_import_entries RPC and import_jobs
-- table for large imports. A 10-year Clue import (~3,650 entries/profile)
-- cannot pass through sync_push -- 8 sequential 500-row batches, each
-- inside one 8s-timeout transaction, each row paying a role lookup, two
-- `select ... for update`s, an insert/update, and three AFTER triggers.
-- Realistically the batch times out, rolls back, and the client retries
-- the same doomed batch (see the issue's Context for the measured numbers).
--
-- Timestamp note: 20260908180000_timezone_contract.sql (#180, #319) merged
-- ahead of this migration and re-emits sync_push (a local_date derivation
-- fix) plus the new public.is_valid_timezone() helper this migration's own
-- validation now calls (see the tz check in bulk_import_entries below);
-- this migration sorts after it, and after 20260908170000_import_provenance.sql
-- (#159), the latest migration on `main` at dispatch time (AGENTS.md
-- Migration Flow item 7).
--
-- Binding constraint (Issue #159 review finding, AGENTS.md Migration Flow
-- item 8): sync_push resolves every day_entries row strictly by `id`, never
-- by (profile_id, source, source_id) -- so it cannot revive a tombstoned
-- imported row the way a raw `insert ... on conflict (profile_id, source,
-- source_id) where source_id is not null do update set deleted_at = null,
-- ...` can. bulk_import_entries below is exactly that raw set-based shape,
-- run directly against day_entries rather than through sync_push.
-- sync_push's own 3-arg signature and body (20260908170000) are untouched
-- by this migration -- it is a separate function, per the dispatch's scope
-- decision.
--
-- Review fix -- idempotency restructuring: the write below is now two
-- disjoint, set-based paths rather than one. A row whose `id` ALREADY
-- exists in day_entries (any provenance) is resolved first, by id, and
-- updated in place with last-writer-wins on updated_at -- mirroring
-- sync_push's own id-first resolution -- so that re-sending a chunk that
-- already landed is a real idempotent update, not a primary-key
-- collision. Only a row whose id does not yet exist falls through to the
-- ON CONFLICT (profile_id, source, source_id) arbiter, which is how a
-- tombstoned imported row gets revived without a separate "look up the
-- existing row and reuse its id" step: the arbiter finds the existing row
-- by (profile_id, source, source_id) and updates it in place, keeping
-- *its* id, regardless of what id the incoming row carried. A row that
-- reaches neither path -- no existing id AND no source_id -- is rejected
-- at the RPC boundary (`source_id is required for idempotent import`)
-- rather than falling back to a bare insert, which would collide on `id`
-- on every retry and abort the whole batch (the bug this restructuring
-- closes; see BulkImportRow's own doc comment in
-- lib/domain/import/bulk_importer.dart for the client-side half of this
-- contract).
--
-- Scope decisions (recorded here, and in the PR body):
--   * day_entries only. The issue's own Proposed change is day_entries-
--     first and its Assumptions section treats the row shape as the
--     starting point; observations' shape (per-day cap, same-date
--     (category, code) dedup from #240) is materially different and is
--     left to a follow-up rather than doubled up in this already-large
--     migration. A p_rows batch therefore carries only day_entries rows;
--     an observations-shaped row is rejected as an unknown-key row like
--     any other malformed input (its keys -- day_entry_id, category, code,
--     etc. -- are not in this RPC's allowlist).
--   * `source` and `import_id` are NOT accepted per-row. One import job
--     has exactly one source and one id (import_jobs.source /
--     p_import_id) -- every row this call writes gets those two values
--     from the job record, not from the payload. This removes an entire
--     class of per-row validation (the source closed-set check) since
--     import_jobs.source is validated once, at job-creation time, by the
--     same closed-set CHECK day_entries.source already uses. A row
--     carrying a `source` or `import_id` key is rejected as an unknown
--     key, like any other key outside the allowlist below.
--   * Fully set-based, including validation: rather than a per-row plpgsql
--     loop (which is what made sync_push's approach expensive -- see the
--     issue's Context), every row is validated by one SQL expression
--     evaluated over the whole batch via jsonb_array_elements(...) WITH
--     ORDINALITY, and the actual write is one
--     `insert ... select ... on conflict ... do update` statement. Two
--     tiny STABLE helpers (bulk_import_safe_date/timestamptz below) let
--     that validation catch a malformed date/timestamp as an ordinary
--     per-row rejection instead of raising and aborting the whole
--     statement, mirroring what a per-row exception handler would do in
--     sync_push's style but without the per-row overhead.
--   * A within-batch duplicate (two rows sharing (profile_id, source,
--     source_id)) is resolved to the later row (by array position)
--     surviving and the earlier one rejected -- ON CONFLICT DO UPDATE
--     cannot touch the same row twice in one statement (21000), so this
--     is a genuine constraint, not a style choice. A second, independent
--     within-batch duplicate rule (review fix) covers (profile_id,
--     local_date): two rows landing live on the same date under
--     different source_id resolves to the EARLIER row (by array
--     position) surviving instead -- there is no in-RPC resolver for
--     this PR (decision below), so ambiguity within one call is rejected
--     rather than silently merged or overwritten.
--   * Review fix -- every day_entries CHECK/business rule gets a per-row
--     rejection, never an aborted chunk: `tz` is checked against
--     `public.is_valid_timezone()` (20260908180000_timezone_contract.sql),
--     matching the `day_entries_tz_valid` CHECK constraint that would
--     otherwise abort the whole write statement on a bad zone. A tombstone
--     row (`deleted_at` present) has its `flow`/`tags`/`note` forced to the
--     empty tombstone payload in the parsed stage, exactly like sync_push's
--     identical branch, rather than being validated (or rejected) against
--     whatever stale payload it happens to carry. A row landing live on a
--     date that a LIVE existing day_entries row already occupies, under a
--     different id and different (source, source_id), is
--     rejected (`date already has a live entry`) rather than merged --
--     decision: no in-RPC resolver in this PR; the client surfaces the
--     conflict to the user. This does not apply to an update-by-id row
--     (already resolved by id, gated by last-writer-wins, not by date).
--   * touch_sync_signal() and enqueue_caregiver_alerts() gain the early
--     `return null` the issue specifies, guarded by a transaction-local GUC
--     (`lunarlog.bulk_import`) set only by bulk_import_entries -- the
--     lunarlog.ownership_transfer precedent in
--     20260906180000_ownership_transfer_rpcs.sql. Both triggers still
--     fire on every row this RPC writes; they simply no-op for the
--     duration of the call. bulk_import_entries touches sync_signals
--     itself, exactly once, at the end.
--   * reconcile_realtime_publication() gains import_jobs on its
--     must-never-publish list, mirroring how 20260908160000_observations.sql
--     added observations to it (day_entries/profiles's original list).
--   * delete_account_data() and export_account_data() are each
--     create-or-replaced from their latest bodies
--     (20260908160000_observations.sql and 20260908150000_export_account_data.sql
--     respectively, both still current on `main`), carried
--     forward verbatim plus one new import_jobs step each -- delete scoped
--     to `created_by = v_uid` (mirroring guardian_invitations' `invited_by`
--     predicate: a caregiver's own import on a profile they don't own is
--     still their row to delete), export scoped to owned-profile jobs plus
--     the caller's own created_by rows on any profile (mirroring
--     guardian_invitations' export scoping exactly).
--   * import_jobs.profile_id is `text references public.profiles(id)`, not
--     `uuid` as the issue's DDL sketch shows -- profiles.id is a ULID
--     stored as text throughout this schema (see
--     20260903014208_initial_sync_schema.sql), never a uuid; every other
--     profile_id FK in this codebase (day_entries, observations,
--     notification_preferences, ...) is the same `text ... references
--     public.profiles (id) on delete cascade` shape, so import_jobs
--     matches that precedent instead of the issue's literal sketch.
--     import_jobs.id itself stays `uuid` (gen_random_uuid()), matching
--     day_entries.import_id/observations.import_id's placeholder type
--     from 20260908170000_import_provenance.sql -- this migration adds the
--     real FK those columns were left unconstrained for.
--   * delete_account_data() only ever deletes an import_jobs row the
--     caller themselves created (created_by = v_uid); it never deletes a
--     job row created by a co-guardian on a profile the caller owns. But
--     day_entries.import_id_fkey/observations.import_id_fkey's
--     `on delete set null` (section 3 above) means that deleting the
--     caller's own job row can still null import_id on rows the caller
--     does not own -- a co-guardian's still-live day_entries/observations
--     rows pointing at that same job (e.g. a shared profile another
--     import chunk landed rows on before the caller's account was
--     deleted). Those rows themselves are untouched; only their import
--     provenance is cleared, same as any other on-delete-set-null FK.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. import_jobs table
-- ---------------------------------------------------------------------------

create table public.import_jobs (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  -- Same closed set as day_entries.source (day_entries_source_check,
  -- 20260908170000_import_provenance.sql) -- validated once here at job
  -- creation, so bulk_import_entries never needs to re-validate a per-row
  -- `source` (which it does not even accept -- see this file's header).
  source text not null
    constraint import_jobs_source_check
    check (source in ('manual', 'clue_import', 'healthkit', 'health_connect', 'file_import')),
  -- Free text for now (issue Assumptions: "a stricter enum can be added
  -- once the client-side error taxonomy is settled"), but bulk_import_entries
  -- itself only ever sets it via the RLS-permitted update grant below to
  -- one of pending/running/completed/failed by convention.
  status text not null default 'pending'
    constraint import_jobs_status_length_check
    check (char_length(status) <= 32),
  total_rows integer not null
    constraint import_jobs_total_rows_check check (total_rows >= 0),
  processed_rows integer not null default 0
    constraint import_jobs_processed_rows_check
    check (processed_rows >= 0 and processed_rows <= total_rows),
  error_kind text
    constraint import_jobs_error_kind_length_check
    check (error_kind is null or char_length(error_kind) <= 64),
  created_by uuid not null
    references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

comment on table public.import_jobs is
  'Issue #167: one row per client-initiated bulk import (e.g. a Clue export)
   for a profile, tracking progress across bulk_import_entries chunk calls
   so the client can show progress and resume a partially-completed import.
   No health content: source label, counts, status, and timestamps only.
   Never published to Realtime (see reconcile_realtime_publication below);
   no client DELETE (see the RLS/grants section below).';

create index import_jobs_profile_id_idx on public.import_jobs (profile_id);
create index import_jobs_created_by_idx on public.import_jobs (created_by);

-- ---------------------------------------------------------------------------
-- 2. import_jobs RLS + privileges. Same profile-guardian predicate every
--    other guardian-scoped table uses (is_profile_guardian /
--    is_guardian_with_roles, 20260904010000_multi_guardian_schema.sql).
--    Insert/update require a *writing* role (primary_guardian, co_parent,
--    caregiver -- viewer excluded), mirroring day_entries' own policies.
--    No client DELETE policy or grant at all -- a job row's lifecycle ends
--    at `completed`/`failed`, never at removal by the client (only
--    delete_account_data() and the profile's own cascade remove it).
-- ---------------------------------------------------------------------------

alter table public.import_jobs enable row level security;
alter table public.import_jobs force row level security;

create policy "import_jobs_select_guardians" on public.import_jobs
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "import_jobs_insert_guardians" on public.import_jobs
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
    and created_by = (select auth.uid())
  );

-- Column-scoped UPDATE grant below (status, processed_rows, completed_at,
-- error_kind only) is the real restriction on what an authenticated caller
-- can change; this policy governs which *rows* they may reach at all.
create policy "import_jobs_update_guardians" on public.import_jobs
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

revoke all on table public.import_jobs from public, anon, authenticated;
grant select, insert on table public.import_jobs to authenticated;
grant update (status, processed_rows, completed_at, error_kind) on table public.import_jobs to authenticated;

-- ---------------------------------------------------------------------------
-- 3. day_entries.import_id / observations.import_id: the real FK, left
--    unconstrained by 20260908170000_import_provenance.sql pending this
--    table's existence.
-- ---------------------------------------------------------------------------

alter table public.day_entries
  add constraint day_entries_import_id_fkey
  foreign key (import_id) references public.import_jobs (id) on delete set null;

alter table public.observations
  add constraint observations_import_id_fkey
  foreign key (import_id) references public.import_jobs (id) on delete set null;

-- ---------------------------------------------------------------------------
-- 4. Safe-cast helpers for the set-based validation in bulk_import_entries:
--    a malformed date/timestamp becomes an ordinary per-row rejection
--    (NULL) instead of raising and aborting the whole statement. Internal
--    only -- no grant to any app role; called from inside the
--    SECURITY DEFINER RPC below, which runs as the function owner.
-- ---------------------------------------------------------------------------

create or replace function public.bulk_import_safe_date(p_text text)
returns date
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_text is null then
    return null;
  end if;
  -- Review fix: 'infinity'/'-infinity' and the dynamic keywords 'now'/
  -- 'today' all cast successfully to date (Postgres treats them as
  -- recognized special values, not malformed input) but none of them is a
  -- real ISO calendar date -- 'now'/'today' would also make the RPC's
  -- result depend on wall-clock time at call time, breaking the
  -- set-based validation's determinism. Reject all four here as an
  -- ordinary per-row parse failure, same as any other malformed value.
  if lower(trim(p_text)) in ('infinity', '-infinity', 'now', 'today') then
    return null;
  end if;
  return p_text::date;
exception
  when others then
    return null;
end;
$$;

comment on function public.bulk_import_safe_date(text) is
  'Issue #167: text -> date that returns NULL instead of raising on a
   malformed value, so bulk_import_entries can validate a whole batch in
   one set-based SELECT without a per-row exception handler. Review fix:
   also rejects ''infinity''/''-infinity''/''now''/''today'' -- Postgres
   casts all four successfully, but none is a real ISO calendar date.';

revoke all on function public.bulk_import_safe_date(text) from public, anon, authenticated;

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
  -- Review fix: same bounds check as bulk_import_safe_date, and for the
  -- same reason -- 'infinity'/'-infinity'/'now'/'today' all cast
  -- successfully to timestamptz without raising, but none is a real,
  -- deterministic ISO timestamp.
  if lower(trim(p_text)) in ('infinity', '-infinity', 'now', 'today') then
    return null;
  end if;
  return p_text::timestamptz;
exception
  when others then
    return null;
end;
$$;

comment on function public.bulk_import_safe_timestamptz(text) is
  'Issue #167: text -> timestamptz that returns NULL instead of raising on
   a malformed value -- see bulk_import_safe_date''s comment, including the
   ''infinity''/''-infinity''/''now''/''today'' bounds check.';

revoke all on function public.bulk_import_safe_timestamptz(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. touch_sync_signal(): create-or-replaced from its only prior body
--    (20260905100000_realtime_publication.sql), carried forward verbatim,
--    gaining exactly the early return the issue specifies at the top of
--    the function -- the trigger still fires on every row
--    bulk_import_entries writes, it just no-ops for the duration of that
--    call (the RPC touches sync_signals itself, once, at the end).
-- ---------------------------------------------------------------------------

create or replace function public.touch_sync_signal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id text;
begin
  -- Issue #167: bulk_import_entries sets this transaction-local GUC for
  -- the duration of its single set-based day_entries write so this
  -- per-row trigger does not fire once per imported row -- the RPC
  -- upserts sync_signals itself, exactly once, after the write completes.
  if coalesce(current_setting('lunarlog.bulk_import', true), '') = 'on' then
    return null;
  end if;

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
  'orphaned signal row behind (Issue #77). Issue #167: no-ops entirely '
  'while lunarlog.bulk_import = ''on'' -- bulk_import_entries touches '
  'sync_signals itself, once, after its batch write completes.';

revoke execute on function public.touch_sync_signal() from public, anon;

-- ---------------------------------------------------------------------------
-- 6. enqueue_caregiver_alerts(): create-or-replaced from its latest body
--    (20260908110000_alert_digest_cadence.sql, still current on `main`),
--    carried forward verbatim, gaining the same early return at the top.
--    A bulk import is a data migration, not a "someone logged an entry"
--    event -- no guardian should be paged for it.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_caregiver_alerts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_writer_id uuid;
  v_is_bleed boolean;
  v_prev_bleed boolean;
  v_is_cycle_start boolean;
  v_is_high_severity boolean;
  v_kind text;
  v_pref record;
  v_cadence text;
  v_pushes_today bigint;
begin
  -- Issue #167: see touch_sync_signal()'s identical guard above -- a bulk
  -- import must not fan out into one notification_outbox row per eligible
  -- guardian per imported row.
  if coalesce(current_setting('lunarlog.bulk_import', true), '') = 'on' then
    return null;
  end if;

  -- A tombstoned write carries no meaningful "someone logged an entry"
  -- event.
  if new.deleted_at is not null then
    return null;
  end if;

  -- sync_push stamps last_modified_by_user_id from the caller's own
  -- auth.uid() (see 20260904010000_multi_guardian_schema.sql); a legacy or
  -- direct-insert row with it null falls back to user_id. This is the
  -- self-authored-event suppression the issue asks to verify and pin
  -- (AC3): a guardian's own edit synced from their second device carries
  -- their own id here and never pages them.
  v_writer_id := coalesce(new.last_modified_by_user_id, new.user_id);

  v_is_bleed := new.flow <> 'none';

  -- #6 (review): lib/domain/episodes/episodes.dart's deriveEpisodes() merges
  -- bleed dates at most 2 days apart into the same episode (a one-day
  -- non-bleed gap does not split it) -- probing only local_date - 1 missed
  -- that merge and flagged the day after a one-day gap as a false
  -- cycle_start. Checking the full [local_date - 2, local_date - 1] window
  -- for any prior bleed day matches deriveEpisodes' own rule exactly.
  select exists (
    select 1 from public.day_entries
     where profile_id = new.profile_id
       and local_date >= new.local_date - 2
       and local_date < new.local_date
       and deleted_at is null
       and flow <> 'none'
  ) into v_prev_bleed;

  -- R7: a cycle start is a bleed day with no bleed day in the merge window
  -- (or nothing at all -- v_prev_bleed is false either way).
  v_is_cycle_start := v_is_bleed and not v_prev_bleed;

  -- Q1: no severity marker exists in the tag taxonomy; heavy flow alone
  -- stands in for "high severity" (see 20260906220000's header).
  v_is_high_severity := new.flow = 'heavy';

  v_kind := case
    when v_is_cycle_start then 'cycle_start'
    when v_is_high_severity then 'high_severity'
    else 'logged'
  end;

  for v_pref in
    select g.user_id as guardian_user_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           p.log_cadence, p.cycle_start_cadence, p.high_severity_cadence
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id
       and g.user_id = p.user_id
     where p.profile_id = new.profile_id
       and g.status = 'accepted'
       and g.user_id is distinct from v_writer_id
       and p.alert_on_log
       -- R7: several narrowings enabled at once still yield at most one
       -- row per entry write -- this is a single boolean expression, not
       -- one insert per narrowing.
       and (not p.alert_on_cycle_start_only or v_is_cycle_start)
       and (not p.alert_on_high_severity or v_is_high_severity)
  loop
    -- Issue #125: the cadence column governing this event's kind decides
    -- delivery. 'off' is the per-kind kill switch the issue scopes; the
    -- kind-level default ('immediate') keeps pre-#125 behaviour for every
    -- existing row.
    v_cadence := case v_kind
      when 'cycle_start' then v_pref.cycle_start_cadence
      when 'high_severity' then v_pref.high_severity_cadence
      else v_pref.log_cadence
    end;

    if v_cadence = 'off' then
      continue;
    end if;

    if v_cadence = 'daily_digest' then
      -- Held for the digest sweep: deliver_after = 'infinity' keeps the
      -- row out of push-dispatch's `deliver_after <= now()` claim
      -- predicate until sweep_alert_digests() collapses the group at the
      -- guardian's chosen digest time.
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 3: the daily ceiling first, so the
    -- overflow rolls into the next digest rather than being coalesced
    -- away or dropped. Counts every non-held, non-missed_entry row for
    -- this (guardian, profile) created since the guardian's local
    -- midnight -- sent or not, each is one push made today.
    select count(*) into v_pushes_today
      from public.notification_outbox o
     where o.recipient_user_id = v_pref.guardian_user_id
       and o.profile_id = new.profile_id
       and o.kind <> 'missed_entry'
       and o.deliver_after < 'infinity'::timestamptz
       and o.created_at >= public.local_day_start(now(), v_pref.time_zone);

    if v_pushes_today >= public.alert_daily_push_ceiling() then
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 2: the coalescing window. Skip when
    -- a row of the same (recipient, profile, kind) already exists inside
    -- the window -- regardless of sent_at, because under a healthy
    -- webhook every row is sent within milliseconds and an unsent-only
    -- guard would never suppress anything.
    if exists (
      select 1 from public.notification_outbox o
       where o.recipient_user_id = v_pref.guardian_user_id
         and o.profile_id = new.profile_id
         and o.kind = v_kind
         and o.created_at > now() - public.alert_coalesce_window()
    ) then
      continue;
    end if;

    insert into public.notification_outbox
      (profile_id, recipient_user_id, kind, deliver_after)
    values (
      new.profile_id,
      v_pref.guardian_user_id,
      v_kind,
      public.resolve_deliver_after(
        now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_pref.time_zone
      )
    );
  end loop;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

-- Carries the comment forward, extended for the new guard.
comment on function public.enqueue_caregiver_alerts() is
  'AFTER INSERT and AFTER UPDATE trigger function on day_entries (Issue #5, '
  'KTD4; two separate triggers as of the #7 review fix, since a single '
  'combined trigger cannot WHEN-filter both events with one expression): '
  'fans a live write out into one public.notification_outbox row per '
  'eligible, non-writer guardian. The UPDATE trigger''s WHEN clause skips '
  'ownership-only updates and no-op resaves (#7). Runs independently of '
  'public.touch_sync_signal()''s sync_signals trigger -- the two write to '
  'different tables and neither depends on the other''s firing order. '
  'As of Issue #125 each guardian''s per-kind cadence column decides '
  'delivery: off skips, daily_digest holds the row for '
  'sweep_alert_digests(), and immediate rows are subject to the '
  'per-guardian daily push ceiling (overflow rolls into the next digest) '
  'and the alert_coalesce_window() coalescing guard. Issue #167: no-ops '
  'entirely while lunarlog.bulk_import = ''on'' -- a bulk import is not a '
  '"someone logged an entry" event and must not page anyone.';

revoke execute on function public.enqueue_caregiver_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. reconcile_realtime_publication(): create-or-replaced from its latest
--    body (20260908160000_observations.sql), gaining an import_jobs guard
--    block mirroring the day_entries/profiles/observations blocks exactly
--    -- import_jobs carries no health content, but it is a per-user
--    tracking table with no reason to ever reach the client any way other
--    than an authenticated read. Re-run at the end of this migration.
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
      'public.day_entries, public.observations, and public.import_jobs '
      'whole-row and must be fixed manually before this migration can '
      'proceed (see the migration header comment)';
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
  'observations/import_jobs (Issue #240 added observations to this list; '
  'Issue #167 added import_jobs), correcting drift (e.g. a Studio "Enable '
  'Realtime" toggle) rather than skipping an already-published table '
  '(Issue #77 P1 fix). Not an API function -- runs only from this '
  'migration and from pgTAP (as an unrestricted role); execute is revoked '
  'from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;

select public.reconcile_realtime_publication();

-- ---------------------------------------------------------------------------
-- 8. delete_account_data(): create-or-replaced from its latest body
--    (20260908160000_observations.sql, still current on `main`), carried
--    forward verbatim plus one new step: the caller's
--    own import_jobs rows, scoped by `created_by = v_uid` (mirroring
--    guardian_invitations' `invited_by = v_uid` predicate) rather than by
--    owned-profile only -- a caregiver's own import on a profile they do
--    not own is still their row. A job on a profile the caller *does* own
--    is also caught by this predicate whenever the caller ran the import
--    themselves, and separately cascades via import_jobs.profile_id's
--    `on delete cascade` when the profiles delete below removes the
--    profile outright.
-- ---------------------------------------------------------------------------

create or replace function public.delete_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day_entries_rehomed bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_observations_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_deleted bigint := 0;
  v_settings_deleted bigint := 0;
  v_notification_preferences_deleted bigint := 0;
  v_push_devices_deleted bigint := 0;
  v_notification_outbox_deleted bigint := 0;
  v_reminder_windows_deleted bigint := 0;
  v_missed_entry_alert_state_deleted bigint := 0;
  v_feedback_tickets_deleted bigint := 0;
  v_import_jobs_deleted bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Step 0 (P0 fix; #17 P1 item 5 follow-up): see
  -- public.rehome_stray_day_entries() above - the delete-account Edge
  -- Function calls it a second time, standalone (on its service-role
  -- client, with an explicit p_user_id - #17 P1 round 2 fix), immediately
  -- before auth.admin.deleteUser. This call runs inside a security-definer
  -- function, so it executes as the function owner regardless of
  -- rehome_stray_day_entries()'s own (now-revoked) grants to authenticated.
  v_day_entries_rehomed := public.rehome_stray_day_entries(v_uid);

  -- Issue #240: observations on profiles the caller owns, deleted explicitly
  -- (before the day_entries delete below, which would cascade-remove the
  -- same rows anyway) purely so this function's own returned count reflects
  -- them - see this migration's header note above.
  delete from public.observations
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_observations_deleted = row_count;

  -- day_entries on profiles the caller owns. Deliberately not
  -- `day_entries.user_id = v_uid`: that column is stamped from auth.uid()
  -- at insert time (see 20260903014208_initial_sync_schema.sql), so a
  -- caregiver's own device syncing an entry for someone else's shared
  -- profile sets it to the caregiver, not the profile owner. Deleting by
  -- that column would destroy another family's data out from under them
  -- when the caregiver's account is removed - exactly what R7 forbids.
  delete from public.day_entries
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_day_entries_deleted = row_count;

  -- Issue #5, U4: profile_reminder_windows for profiles the caller *owns*.
  -- Explicit (rather than relying on the profiles delete's cascade below)
  -- so this function's own returned count reflects it, and so it is gone
  -- before the profiles delete rather than depending on cascade ordering.
  delete from public.profile_reminder_windows
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_reminder_windows_deleted = row_count;

  -- Issue #5, U4: the caller's own pending caregiver alerts, on any
  -- profile (their own, or one they merely guard). Not scoped to owned
  -- profiles - the caller may be the *recipient* of alerts for a profile
  -- someone else owns, and those rows belong to the caller (R20), not the
  -- profile owner.
  delete from public.notification_outbox
   where recipient_user_id = v_uid;
  get diagnostics v_notification_outbox_deleted = row_count;

  -- Invitations the caller created, for any profile (their own or one they
  -- co-parent).
  delete from public.guardian_invitations
   where invited_by = v_uid;
  get diagnostics v_invitations_deleted = row_count;

  -- The caller's own guardian memberships. No status filter: a revoked
  -- membership row is still the caller's row and must go too.
  delete from public.profile_guardians
   where user_id = v_uid;
  get diagnostics v_guardians_deleted = row_count;

  -- Issue #5, U4: the caller's own notification preferences, on any
  -- profile they guard (their own, or someone else's). A co-guardian's
  -- preference row for a profile the caller also guards is not the
  -- caller's row and is untouched by this delete.
  delete from public.notification_preferences
   where user_id = v_uid;
  get diagnostics v_notification_preferences_deleted = row_count;

  -- Issue #5, U4: the caller's own registered devices.
  delete from public.push_devices
   where user_id = v_uid;
  get diagnostics v_push_devices_deleted = row_count;

  -- Round-2 review #8: the caller's own missed-entry dedupe markers, on any
  -- profile (their own, or one they merely guard) -- same scoping as
  -- notification_preferences and push_devices above. Not covered by the
  -- profiles delete's cascade below when the caller does not own the
  -- profile (e.g. a caregiver deleting their own account while remaining a
  -- guardian elsewhere is not this path, but a co-guardian's marker on a
  -- profile the caller owns is a different row and must not be touched
  -- here regardless).
  delete from public.missed_entry_alert_state
   where user_id = v_uid;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  -- Issue #243 (D-25): the caller's own feedback tickets, explicitly -
  -- rather than depending on feedback_tickets.user_id's `on delete cascade`
  -- to fire only once the Edge Function's later, separately-failable
  -- auth.admin.deleteUser call succeeds (see this migration's header).
  -- feedback_replies cascades from feedback_tickets (`on delete cascade`,
  -- see 20260906130000_feedback_tickets.sql), so no separate delete is
  -- needed for replies here.
  delete from public.feedback_tickets
   where user_id = v_uid;
  get diagnostics v_feedback_tickets_deleted = row_count;

  -- Issue #167: the caller's own import jobs, on any profile (their own,
  -- or one they merely guard) -- `created_by = v_uid`, mirroring
  -- guardian_invitations' `invited_by = v_uid` predicate immediately
  -- above. A job on a profile the caller owns is deleted here whenever the
  -- caller is also who ran the import (the common case); it is also
  -- caught by the profiles delete's own cascade below regardless of who
  -- ran it, via import_jobs.profile_id's `on delete cascade`.
  delete from public.import_jobs
   where created_by = v_uid;
  get diagnostics v_import_jobs_deleted = row_count;

  -- The caller's own profiles. Cascades any day_entries,
  -- guardian_invitations, and profile_guardians rows still tied to these
  -- specific profiles (e.g. a co-parent's membership, or an invitation
  -- someone else sent for it) - intended for an owner (R7). Also cascades
  -- any remaining notification_preferences/notification_outbox/
  -- profile_reminder_windows/import_jobs rows scoped to these profiles
  -- (Issue #5, Issue #167) - e.g. a co-guardian's own preference row for a
  -- profile the caller owned, or an import job someone else ran on a
  -- profile the caller owned, both correct: once the profile itself is
  -- gone there is nothing left to alert anyone about or import into.
  delete from public.profiles
   where user_id = v_uid;
  get diagnostics v_profiles_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'day_entries_rehomed', v_day_entries_rehomed,
    'observations', v_observations_deleted,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'push_devices', v_push_devices_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'profile_reminder_windows', v_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'feedback_tickets', v_feedback_tickets_deleted,
    'import_jobs', v_import_jobs_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations (Issue #240 - explicit for an accurate '
  'returned count; the FK cascades would remove them regardless), '
  'settings, profile_guardians, guardian_invitations, '
  'notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, missed_entry_alert_state, and feedback_tickets '
  '(feedback_replies cascades from feedback_tickets, so no separate delete '
  'is needed for those), and (Issue #167) import_jobs (`created_by = '
  'v_uid`, mirroring guardian_invitations'' `invited_by` predicate), first '
  'calling public.rehome_stray_day_entries(auth.uid()) to re-home any '
  'day_entries this caller logged as a caregiver on a profile they do not '
  'own, so the auth.users on delete cascade the Edge Function triggers '
  'afterwards cannot reach them (#17 P0 fix). That call runs as this '
  'function''s own security-definer owner, so it succeeds regardless of '
  'rehome_stray_day_entries()''s own (revoked, #17 P1 round 2 fix) grants. '
  'Takes no parameters itself - the caller is always the subject, so no '
  'other account can be named in the call. Called by the delete-account '
  'Edge Function only after it has already removed the caller''s '
  'feedback-attachments Storage objects (Issue #243, D-24); that same '
  'function then revokes Apple and deletes the auth.users row (#17 '
  'KTD1/KTD4). It also calls rehome_stray_day_entries() a second time, '
  'standalone, on its service-role client with an explicit p_user_id, '
  'immediately before the auth.users deletion (#17 P1 item 5; round 2 fix).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;

-- ---------------------------------------------------------------------------
-- 9. export_account_data(): create-or-replaced from its latest body
--    (20260908150000_export_account_data.sql, still current on `main`),
--    carried forward verbatim plus one new section: import_jobs, scoped
--    exactly like guardian_invitations -- every job on a profile the
--    caller owns, plus every job the caller personally ran (`created_by =
--    v_uid`) on any profile (owned or shared). No health content in the
--    exported fields (progress metadata only), so no redaction is needed
--    the way push_devices.token needed one.
-- ---------------------------------------------------------------------------

create or replace function public.export_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profiles jsonb;
  v_profile_guardians jsonb;
  v_guardian_invitations jsonb;
  v_ownership_transfers jsonb;
  v_notification_preferences jsonb;
  v_push_devices jsonb;
  v_missed_entry_alert_state jsonb;
  v_feedback_tickets jsonb;
  v_profile_reminder_windows jsonb;
  v_import_jobs jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- ---------------------------------------------------------------------
  -- profiles + nested day_entries. Owned profiles carry every live entry;
  -- shared profiles (the caller is an accepted guardian but not the
  -- owner) carry only entries the caller authored.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pr.id,
        'display_name', pr.display_name,
        'is_minor', pr.is_minor,
        'mode', pr.mode,
        'sort_order', pr.sort_order,
        'archived_at', pr.archived_at,
        'created_at', pr.created_at,
        'updated_at', pr.updated_at,
        'birth_year', pr.birth_year,
        'relationship', pr.relationship,
        'transferred_at', pr.transferred_at,
        'owned', (pr.user_id = v_uid),
        'day_entries', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', de.id,
              'local_date', de.local_date,
              'tz', de.tz,
              'flow', de.flow,
              'tags', de.tags,
              'note', de.note,
              'created_at', de.created_at,
              'updated_at', de.updated_at,
              'logged_by_user_id', de.logged_by_user_id,
              'last_modified_by_user_id', de.last_modified_by_user_id
            )
            order by de.local_date, de.id
          )
          from public.day_entries de
          where de.profile_id = pr.id
            and de.deleted_at is null
            and (pr.user_id = v_uid or de.logged_by_user_id = v_uid)
        ), '[]'::jsonb)
      )
      order by pr.id
    ), '[]'::jsonb
  )
  into v_profiles
  from public.profiles pr
  where pr.deleted_at is null
    and (
      pr.user_id = v_uid
      or exists (
        select 1 from public.profile_guardians g
         where g.profile_id = pr.id
           and g.user_id = v_uid
           and g.status = 'accepted'
      )
    );

  -- ---------------------------------------------------------------------
  -- profile_guardians: every membership on a profile the caller owns,
  -- plus the caller's own membership row on any profile (owned or
  -- shared) -- never a co-guardian's row on a shared profile.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'profile_id', g.profile_id,
        'user_id', g.user_id,
        'role', g.role,
        'status', g.status,
        'display_name', g.display_name,
        -- Never another user's id on a shared (non-owned) profile: the
        -- caller's own row there is the only one returned, and its
        -- invited_by names whoever invited them (often the owner) --
        -- another user's identity, out of scope per this migration's
        -- never-another-user's-data bound. Owned profiles keep it: the
        -- owner already sees every guardian's invited_by via ordinary
        -- profile_guardians_select RLS.
        'invited_by', case
          when g.profile_id in (select id from public.profiles where user_id = v_uid)
            then g.invited_by
          else null
        end,
        'created_at', g.created_at,
        'updated_at', g.updated_at,
        'revoked_at', g.revoked_at
      )
      order by g.profile_id, g.user_id
    ), '[]'::jsonb
  )
  into v_profile_guardians
  from public.profile_guardians g
  where g.profile_id in (select id from public.profiles where user_id = v_uid)
     or g.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- guardian_invitations: every invitation for a profile the caller owns,
  -- plus invitations the caller personally created for any profile (owned
  -- or shared). token_hash is never selected (see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'profile_id', i.profile_id,
        'invited_by', i.invited_by,
        'role', i.role,
        'recipient_label', i.recipient_label,
        'expires_at', i.expires_at,
        'accepted_at', i.accepted_at,
        'accepted_by', i.accepted_by,
        'revoked_at', i.revoked_at,
        'created_at', i.created_at
      )
      order by i.created_at, i.id
    ), '[]'::jsonb
  )
  into v_guardian_invitations
  from public.guardian_invitations i
  where i.profile_id in (select id from public.profiles where user_id = v_uid)
     or i.invited_by = v_uid;

  -- ---------------------------------------------------------------------
  -- ownership_transfers: the caller's own involvement only (initiated or
  -- accepted), on any profile. token_hash is never selected.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'profile_id', t.profile_id,
        'initiated_by', t.initiated_by,
        'parent_post_transfer_role', t.parent_post_transfer_role,
        'recipient_label', t.recipient_label,
        'expires_at', t.expires_at,
        'accepted_at', t.accepted_at,
        'accepted_by', t.accepted_by,
        'cancelled_at', t.cancelled_at,
        'created_at', t.created_at
      )
      order by t.created_at, t.id
    ), '[]'::jsonb
  )
  into v_ownership_transfers
  from public.ownership_transfers t
  where t.initiated_by = v_uid
     or t.accepted_by = v_uid;

  -- ---------------------------------------------------------------------
  -- notification_preferences: the caller's own rows only (never a
  -- co-guardian's, on any profile -- see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', np.profile_id,
        'alert_on_log', np.alert_on_log,
        'alert_on_cycle_start_only', np.alert_on_cycle_start_only,
        'alert_on_high_severity', np.alert_on_high_severity,
        'missed_entry_days', np.missed_entry_days,
        'quiet_hours_start', np.quiet_hours_start,
        'quiet_hours_end', np.quiet_hours_end,
        'time_zone', np.time_zone,
        'log_cadence', np.log_cadence,
        'cycle_start_cadence', np.cycle_start_cadence,
        'high_severity_cadence', np.high_severity_cadence,
        'digest_local_time', np.digest_local_time,
        'updated_at', np.updated_at
      )
      order by np.profile_id
    ), '[]'::jsonb
  )
  into v_notification_preferences
  from public.notification_preferences np
  where np.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- push_devices: the caller's own devices; `token` redacted to its last
  -- 4 characters (see header note) rather than included verbatim.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pd.id,
        'platform', pd.platform,
        'token_last4', right(pd.token, 4),
        'updated_at', pd.updated_at,
        'disabled_at', pd.disabled_at
      )
      order by pd.id
    ), '[]'::jsonb
  )
  into v_push_devices
  from public.push_devices pd
  where pd.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- missed_entry_alert_state: the caller's own dedupe markers only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', s.profile_id,
        'last_enqueued_for', s.last_enqueued_for
      )
      order by s.profile_id
    ), '[]'::jsonb
  )
  into v_missed_entry_alert_state
  from public.missed_entry_alert_state s
  where s.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- feedback_tickets + their full reply thread (the ticket owner can
  -- already read every reply on their own ticket via
  -- feedback_replies_select).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ft.id,
        'reply_email', ft.reply_email,
        'category', ft.category,
        'message', ft.message,
        'device_info', ft.device_info,
        'attachment_paths', ft.attachment_paths,
        'status', ft.status,
        'created_at', ft.created_at,
        'updated_at', ft.updated_at,
        'replies', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', fr.id,
              'author_type', fr.author_type,
              'message', fr.message,
              'created_at', fr.created_at
            )
            order by fr.created_at, fr.id
          )
          from public.feedback_replies fr
          where fr.ticket_id = ft.id
        ), '[]'::jsonb)
      )
      order by ft.created_at, ft.id
    ), '[]'::jsonb
  )
  into v_feedback_tickets
  from public.feedback_tickets ft
  where ft.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- profile_reminder_windows: owned profiles only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', w.profile_id,
        'estimated_next_start', w.estimated_next_start,
        'episode_open', w.episode_open,
        'updated_at', w.updated_at
      )
      order by w.profile_id
    ), '[]'::jsonb
  )
  into v_profile_reminder_windows
  from public.profile_reminder_windows w
  where w.profile_id in (select id from public.profiles where user_id = v_uid);

  -- ---------------------------------------------------------------------
  -- Issue #167: import_jobs -- every job on a profile the caller owns,
  -- plus every job the caller personally ran (created_by = v_uid) on any
  -- profile, mirroring guardian_invitations' scoping exactly. Progress
  -- metadata only (source label, counts, status, timestamps) -- no health
  -- content.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', j.id,
        'profile_id', j.profile_id,
        'source', j.source,
        'status', j.status,
        'total_rows', j.total_rows,
        'processed_rows', j.processed_rows,
        'error_kind', j.error_kind,
        'created_by', j.created_by,
        'created_at', j.created_at,
        'completed_at', j.completed_at
      )
      order by j.created_at, j.id
    ), '[]'::jsonb
  )
  into v_import_jobs
  from public.import_jobs j
  where j.profile_id in (select id from public.profiles where user_id = v_uid)
     or j.created_by = v_uid;

  -- schema_version stays 1 deliberately: this migration's new import_jobs
  -- key is purely additive -- every top-level key
  -- 20260908150000_export_account_data.sql's original body already
  -- returned keeps its exact prior shape. A version bump is reserved for
  -- a breaking change to an existing key's shape, not for adding a new
  -- key alongside it.
  return jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'profiles', v_profiles,
    'profile_guardians', v_profile_guardians,
    'guardian_invitations', v_guardian_invitations,
    'ownership_transfers', v_ownership_transfers,
    'notification_preferences', v_notification_preferences,
    'push_devices', v_push_devices,
    'missed_entry_alert_state', v_missed_entry_alert_state,
    'feedback_tickets', v_feedback_tickets,
    'profile_reminder_windows', v_profile_reminder_windows,
    'import_jobs', v_import_jobs
  );
end;
$$;

comment on function public.export_account_data() is
  'Right-of-access export (Issue #248): a single jsonb document assembled '
  'from every table keyed to auth.uid(), scoped table-by-table with the '
  'same owner-vs-caregiver split public.delete_account_data() uses (see '
  '20260908150000_export_account_data.sql''s header for the exact '
  'predicate mirrored per table). Never selects guardian_invitations.'
  'token_hash or ownership_transfers.token_hash; push_devices.token is '
  'redacted to its last 4 characters. Issue #167: import_jobs is scoped '
  'exactly like guardian_invitations -- every job on an owned profile, '
  'plus every job the caller personally ran on any profile -- and carries '
  'no health content (progress metadata only), so no redaction is needed. '
  'Merged client-side under the local export document''s `server` key by '
  'lib/domain/export/account_export.dart -- never replaces the local '
  'profiles/dayEntries shape.';

revoke all on function public.export_account_data() from public, anon;
grant execute on function public.export_account_data() to authenticated;

-- ---------------------------------------------------------------------------
-- 10. bulk_import_entries: the RPC. See this migration's header for the
--     full design rationale (set-based validation, day_entries-only
--     scope, source/import_id from the job not the payload).
-- ---------------------------------------------------------------------------

create or replace function public.bulk_import_entries(
  p_import_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_rows constant integer := 2000;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  -- Issue #167: source/import_id are deliberately NOT in this allowlist --
  -- they come from the job record, never the payload (see this
  -- migration's header).
  c_row_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'source_id', 'updated_at', 'deleted_at'];

  v_uid uuid := (select auth.uid());
  v_job public.import_jobs%rowtype;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_revived integer := 0;
  v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'bulk_import_entries requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) > c_max_rows then
    raise exception 'p_rows exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_job from public.import_jobs where id = p_import_id for update;
  if not found then
    raise exception 'import job % does not exist', p_import_id
      using errcode = 'invalid_parameter_value';
  end if;

  -- Guardian check: the caller must be an accepted guardian of the job's
  -- profile with a *writing* role -- mirrors sync_push's day_entries check
  -- (v_caller_role is null or = 'viewer' => reject) via the same
  -- is_guardian_with_roles() helper the ownership-transfer RPCs use.
  -- Review fix: this must run BEFORE the status check below -- an
  -- unauthorised caller must learn nothing about a job's status (or, via
  -- the exception message shape, its existence beyond "some row with this
  -- id exists"), so a non-guardian probing a real job id gets the same
  -- 42501 regardless of whether that job is pending or already
  -- completed/failed.
  if not public.is_guardian_with_roles(
    v_job.profile_id, v_uid, array['primary_guardian', 'co_parent', 'caregiver']
  ) then
    raise exception 'caller is not authorized to import entries for profile %', v_job.profile_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status in ('completed', 'failed') then
    raise exception 'import job % is already %', p_import_id, v_job.status
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('inserted', 0, 'updated', 0, 'revived', 0, 'rejected', '[]'::jsonb);
  end if;

  -- Issue #167: skip touch_sync_signal()/enqueue_caregiver_alerts()'s
  -- per-row work for the duration of the write below (this RPC touches
  -- sync_signals itself, once, at the end; a bulk import never pages a
  -- guardian) -- transaction-local, per the same transaction-local-GUC
  -- pattern the ownership-transfer RPC set in
  -- 20260906180000_ownership_transfer_rpcs.sql uses.
  --
  -- Review fix: this function does NOT (and cannot) raise its own
  -- statement_timeout. `set local statement_timeout = '60s'` used to sit
  -- here, but `statement_timeout` is sampled once when a statement starts
  -- and a mid-statement `set local` on it is a documented Postgres no-op --
  -- it has no effect on the currently-executing statement, and there is no
  -- second statement in this call for it to apply to before the
  -- transaction (and the GUC's `local` scope) ends. So this call has
  -- always run under whatever statement_timeout the caller's role already
  -- had -- the platform's ordinary 8s timeout for `authenticated` -- not a
  -- 60s allowance. Every claim of a 60s bound in this migration's comments
  -- was wrong; see the pgTAP 2000-row latency case, which now measures
  -- against that real 8s ceiling instead.
  perform set_config('lunarlog.bulk_import', 'on', true);

  begin
    with parsed as (
      -- One SQL expression over the whole batch, not a per-row plpgsql
      -- loop (see this migration's header) -- ordinality gives each row
      -- its 0-based position for the `rejected` summary.
      select
        ord.idx - 1 as row_index,
        ord.value as raw,
        ord.value ->> 'id' as id,
        ord.value ->> 'profile_id' as row_profile_id,
        ord.value ->> 'local_date' as local_date_text,
        coalesce(ord.value ->> 'tz', 'UTC') as tz,
        ord.value ->> 'source_id' as source_id,
        ord.value ->> 'updated_at' as updated_at_text,
        ord.value ->> 'deleted_at' as deleted_at_text,
        -- Review fix: a tombstone row carries no payload, mirroring
        -- sync_push's identical day_entries branch
        -- (20260908180000_timezone_contract.sql) -- forced here
        -- unconditionally rather than validating whatever flow/tags/note
        -- keys a tombstone row happens to carry, so a client that sends a
        -- tombstone with a stale (non-empty) payload is not rejected for
        -- it; the payload is simply discarded, same as a live row's would
        -- be validated.
        case when (ord.value ->> 'deleted_at') is not null then 'none'
          else coalesce(ord.value ->> 'flow', 'none') end as flow,
        case when (ord.value ->> 'deleted_at') is not null then '[]'::jsonb
          else coalesce(ord.value -> 'tags', '[]'::jsonb) end as tags,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'note' end as note
      from jsonb_array_elements(p_rows) with ordinality as ord(value, idx)
    ),
    validated as (
      select
        p.*,
        public.bulk_import_safe_date(p.local_date_text) as parsed_local_date,
        public.bulk_import_safe_timestamptz(p.updated_at_text) as parsed_updated_at,
        public.bulk_import_safe_timestamptz(p.deleted_at_text) as parsed_deleted_at,
        case
          when jsonb_typeof(p.raw) <> 'object' then 'row is not an object'
          when exists (select 1 from jsonb_object_keys(p.raw) k where k <> all (c_row_keys))
            then 'row carries an unknown key'
          when p.id is null or p.id !~ c_ulid then 'id is not a ULID'
          when p.row_profile_id is null or p.row_profile_id !~ c_ulid then 'profile_id is not a ULID'
          when p.row_profile_id is distinct from v_job.profile_id then 'profile_id does not match import job'
          when public.bulk_import_safe_date(p.local_date_text) is null then 'local_date is not an ISO calendar date'
          when char_length(p.tz) > 64 then 'tz exceeds 64 characters'
          -- Review fix: a syntactically-plausible but unrecognized zone
          -- (e.g. 'Mars/Cydonia') previously passed straight through to
          -- the day_entries CHECK constraint added by
          -- 20260908180000_timezone_contract.sql, which would abort the
          -- whole batch's write statement (caught only by the
          -- unique_violation backstop's cousin, a check_violation, not
          -- handled at all) instead of rejecting just this row.
          when not public.is_valid_timezone(p.tz) then 'tz is not a known time zone'
          when p.flow not in ('none', 'spotting', 'light', 'medium', 'heavy') then 'flow is not a known level'
          when not public.is_valid_tags_array(p.tags) then 'tags failed validation'
          when p.note is not null and char_length(p.note) > 2000 then 'note exceeds 2000 characters'
          when p.source_id is not null and char_length(p.source_id) > 128 then 'source_id exceeds 128 characters'
          when p.updated_at_text is null then 'updated_at is required'
          when public.bulk_import_safe_timestamptz(p.updated_at_text) is null then 'updated_at is not a valid timestamp'
          when p.deleted_at_text is not null and public.bulk_import_safe_timestamptz(p.deleted_at_text) is null
            then 'deleted_at is not a valid timestamp'
          else null
        end as reason
      from parsed p
    ),
    by_id as (
      -- Review fix: resolve every still-valid row against an existing
      -- day_entries id FIRST, regardless of provenance -- mirrors
      -- sync_push's own id-first resolution and is what makes a retry of
      -- an already-landed chunk idempotent: a row whose id already exists
      -- (from a prior successful chunk of this same job, or any other
      -- write) is updated in place below rather than re-attempting an
      -- insert that would collide on the primary key.
      select
        v.*,
        d.id as existing_by_id_id,
        d.profile_id as existing_by_id_profile_id,
        d.updated_at as existing_by_id_updated_at,
        d.deleted_at as existing_by_id_deleted_at
      from validated v
      left join public.day_entries d on d.id = v.id
      where v.reason is null
    ),
    collision_checked as (
      -- Review fix (decision: no in-RPC resolver in this PR -- the client
      -- surfaces the conflict): a row that would land LIVE is rejected
      -- outright if (profile_id, local_date) already belongs to a
      -- different LIVE row under different provenance (e.g. a manual
      -- entry, or a different import's row) -- sync_push's own same-date
      -- merge algorithm is deliberately not reimplemented here. Exempt:
      -- only a tombstone (nothing is landing live). An update-by-id row
      -- is NOT exempt -- day_entries_live_profile_date_uq
      -- (20260904010000_multi_guardian_schema.sql) is a real partial
      -- unique index on (profile_id, local_date) where deleted_at is
      -- null, so an update that moves an existing row onto an
      -- already-occupied live date would otherwise raise a genuine
      -- unique_violation (23505) from the UPDATE statement itself and
      -- abort the whole chunk via the backstop below -- exactly the
      -- per-row-not-per-chunk failure this migration exists to prevent.
      -- `d.id <> b.id` correctly excludes the row's own currently-stored
      -- self when its date is not actually changing.
      --
      -- Review fix (blocking): compare only (source, source_id), never
      -- import_id. import_id is a job-scoped surrogate, not part of a
      -- row's provenance identity -- re-importing the same source_id under
      -- a brand-new import_jobs row (a legitimate resume/retry with a
      -- fresh job id) previously compared as "different provenance" purely
      -- because the two jobs' ids differed, rejecting every row of an
      -- otherwise-idempotent re-import. (source, source_id) alone is what
      -- actually identifies "the same imported thing" -- see
      -- import_provenance_test.sql's partial unique index on exactly that
      -- pair.
      select
        b.*,
        case
          when b.parsed_deleted_at is not null then null
          when exists (
            select 1 from public.day_entries d
             where d.profile_id = b.row_profile_id
               and d.local_date = b.parsed_local_date
               and d.deleted_at is null
               and d.id <> b.id
               and (d.source, d.source_id)
                   is distinct from (v_job.source, b.source_id)
          ) then 'date already has a live entry'
          else null
        end as collision_reason
      from by_id b
    ),
    reasoned as (
      select
        c.*,
        coalesce(
          c.collision_reason,
          -- Review fix (blocking): a row whose id already exists in
          -- day_entries but on a DIFFERENT profile is rejected outright,
          -- not silently dropped. Previously by_id's `d.id = v.id` join
          -- ignores profile_id, so a cross-profile id match still set
          -- existing_by_id_id and the row was routed into update_rows --
          -- but the actual UPDATE statement's `d.profile_id =
          -- u.row_profile_id` guard (day entries never move between
          -- profiles, mirroring sync_push) then matched zero rows,
          -- discarding the row without writing it, counting it as
          -- inserted/updated/revived, or rejecting it. It never reaches
          -- insert_rows either (existing_by_id_id is not null), so it
          -- vanished from the response entirely.
          case
            when c.existing_by_id_id is not null
              and c.existing_by_id_profile_id is distinct from c.row_profile_id
              then 'id belongs to another profile'
            else null
          end,
          -- Review fix: a row not already resolved by id needs a
          -- source_id to reach an idempotent write path at all -- the
          -- `on conflict (profile_id, source, source_id)` arbiter below
          -- is the only other route to one, and it requires source_id is
          -- not null. Without this, a brand-new row with no source_id
          -- would insert successfully once and then hit the day_entries
          -- primary key on every subsequent retry of the same chunk,
          -- aborting the whole batch -- the idempotency bug this
          -- restructuring exists to close. Documented as a hard
          -- requirement in BulkImportRow (lib/domain/import/bulk_importer.dart).
          case
            when c.existing_by_id_id is null and c.source_id is null
              then 'source_id is required for idempotent import'
            else null
          end
        ) as combined_reason
      from collision_checked c
    ),
    source_ranked as (
      -- Within-batch duplicate resolution (this migration's header): two
      -- rows sharing (profile_id, source, source_id) cannot both be
      -- affected by one ON CONFLICT DO UPDATE (21000), and would collide
      -- with each other's write regardless of which path either takes --
      -- the later row (by position) wins, the earlier is rejected as
      -- superseded. A null source_id gets its own singleton partition
      -- (never superseded here -- see the source_id-required rejection
      -- above, which already removes every row that would otherwise need
      -- one).
      select
        r.*,
        row_number() over (
          partition by coalesce(r.source_id, 'row:' || r.row_index::text)
          order by r.row_index desc
        ) as source_dupe_rank
      from reasoned r
      where r.combined_reason is null
    ),
    date_ranked as (
      -- Review fix: two rows in the same batch sharing (profile_id,
      -- local_date) under different source_id both landing live is a
      -- second, independent within-batch conflict (decision: no in-RPC
      -- resolver, same as the live-row collision check above) -- the
      -- earlier row (by position) wins, the later is rejected. Tombstones
      -- never contest a date (nothing is landing live), so they always
      -- pass through with rank 1.
      --
      -- Review fix (blocking): the row_number() window is partitioned by
      -- (profile_id, local_date, is-a-tombstone) rather than just
      -- (profile_id, local_date) -- a window function still evaluates over
      -- every row in its partition even when the CASE above discards a
      -- tombstone's computed value and hardcodes 1 instead, so a tombstone
      -- sharing a live row's date previously occupied rank 1 in the
      -- shared partition and pushed the live row (or an earlier live row)
      -- to rank 2+, rejecting it as a spurious "duplicate date" even
      -- though a tombstone never actually contests the date. Splitting
      -- tombstones into their own partition bucket means a live row's
      -- rank depends only on other live rows sharing its date, exactly as
      -- intended -- a tombstone for date D and a live row for date D in
      -- one batch now both proceed.
      select
        s.*,
        case
          when s.parsed_deleted_at is not null then 1
          else row_number() over (
            partition by s.row_profile_id, s.parsed_local_date, (s.parsed_deleted_at is not null)
            order by s.row_index asc
          )
        end as date_dupe_rank
      from source_ranked s
      where s.source_dupe_rank = 1
    ),
    to_write as (
      select d.* from date_ranked d where d.date_dupe_rank = 1
    ),
    -- -----------------------------------------------------------------
    -- Two disjoint, set-based write paths from here (review fix -- see
    -- the migration header's restructuring note):
    --   (a) update_rows: the row's id already exists in day_entries (any
    --       provenance) -- updated in place, last-writer-wins on
    --       updated_at, mirroring sync_push's own resolution. A row that
    --       loses last-writer-wins is silently skipped (not written, not
    --       counted, not rejected) -- exactly sync_push's own "declined"
    --       behaviour for a stale push.
    --   (b) insert_rows: no existing id -- source_id is guaranteed not
    --       null here (every row that would otherwise need one and lacks
    --       it was already rejected above) -- goes through the
    --       pre-existing `on conflict (profile_id, source, source_id)`
    --       upsert, which is how a tombstoned imported row gets revived.
    -- -----------------------------------------------------------------
    update_rows as (
      select
        tw.*,
        (tw.parsed_updated_at > tw.existing_by_id_updated_at
          or (tw.parsed_updated_at = tw.existing_by_id_updated_at
              and tw.parsed_deleted_at is not null
              and tw.existing_by_id_deleted_at is null)) as lww_accept
      from to_write tw
      where tw.existing_by_id_id is not null
    ),
    updated as (
      -- Review fix: apply sync_push's own `v_row ? 'key'` containment
      -- guard (20260908170000_import_provenance.sql /
      -- 20260908180000_timezone_contract.sql) to source_id/import_id here
      -- too -- `source_id` is an ordinary optional payload key (see
      -- c_row_keys above), so an update-by-id row that omits it (editing
      -- flow/tags/note only, say) must not null out the row's already-
      -- stored idempotency key. import_id is guarded by the same
      -- condition rather than its own -- it is never a payload key (it
      -- comes from p_import_id, not the row), so its only sensible update
      -- rule is "moves together with source_id": a row that isn't
      -- (re)stamping source_id has no new provenance to record either.
      update public.day_entries d set
        local_date = u.parsed_local_date,
        tz = u.tz,
        flow = u.flow,
        tags = u.tags,
        note = u.note,
        source = v_job.source,
        source_id = case when u.raw ? 'source_id' then u.source_id else d.source_id end,
        import_id = case when u.raw ? 'source_id' then p_import_id else d.import_id end,
        updated_at = u.parsed_updated_at,
        deleted_at = u.parsed_deleted_at,
        last_modified_by_user_id = v_uid
      from update_rows u
      where d.id = u.id
        -- Mirrors sync_push's own "day entry cannot move between
        -- profiles" guard -- every surviving row's profile_id already
        -- equals v_job.profile_id (validated above), so this only ever
        -- excludes the cryptographically-negligible case of a ULID
        -- collision landing on a different profile's row; profile_id
        -- itself is deliberately left out of the SET list above, same as
        -- sync_push never moves it either.
        and d.profile_id = u.row_profile_id
        and u.lww_accept
      returning u.existing_by_id_deleted_at, u.parsed_deleted_at
    ),
    insert_rows as (
      select tw.* from to_write tw where tw.existing_by_id_id is null
    ),
    insert_lookup as (
      -- Pre-classify against the live table before writing, so the
      -- inserted/revived/updated split doesn't need to be
      -- reverse-engineered from RETURNING (which only ever shows the
      -- post-write row).
      select
        ir.*,
        d.id as conflict_id,
        d.deleted_at as conflict_deleted_at
      from insert_rows ir
      left join public.day_entries d
        on d.profile_id = ir.row_profile_id
       and d.source = v_job.source
       and d.source_id = ir.source_id
       and ir.source_id is not null
    ),
    upserted as (
      insert into public.day_entries (
        id, profile_id, local_date, tz, flow, tags, note,
        source, source_id, import_id,
        updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id
      )
      select
        il.id, il.row_profile_id, il.parsed_local_date, il.tz, il.flow, il.tags, il.note,
        v_job.source, il.source_id, p_import_id,
        il.parsed_updated_at, il.parsed_deleted_at, v_uid, v_uid
      from insert_lookup il
      on conflict (profile_id, source, source_id) where source_id is not null
      do update set
        local_date = excluded.local_date,
        tz = excluded.tz,
        flow = excluded.flow,
        tags = excluded.tags,
        note = excluded.note,
        import_id = excluded.import_id,
        updated_at = excluded.updated_at,
        -- Revives a tombstoned row that a re-import's rows carry live
        -- (deleted_at is null in the incoming row): the ordinary
        -- deleted_at-clearing path, exactly as the on_conflict shape
        -- import_provenance_test.sql already pins.
        deleted_at = excluded.deleted_at,
        last_modified_by_user_id = excluded.last_modified_by_user_id
      -- xmax = 0 identifies a row this command actually inserted (as
      -- opposed to one it found and updated via the arbiter) -- the
      -- standard Postgres INSERT ... ON CONFLICT idiom for telling the
      -- two branches apart from RETURNING alone. source_id is unique
      -- within insert_lookup (source_ranked's dedup above already
      -- guarantees it), so joining back to insert_lookup on it below is
      -- exact, not approximate.
      returning source_id, (xmax = 0) as was_insert
    )
    select
      (select count(*) from upserted where was_insert),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and il.conflict_deleted_at is not null and il.parsed_deleted_at is null)
        + (select count(*) from updated
            where existing_by_id_deleted_at is not null and parsed_deleted_at is null),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and not (il.conflict_deleted_at is not null and il.parsed_deleted_at is null))
        + (select count(*) from updated
            where not (existing_by_id_deleted_at is not null and parsed_deleted_at is null)),
      (select coalesce(jsonb_agg(jsonb_build_object('row_index', x.row_index, 'reason', x.reason) order by x.row_index), '[]'::jsonb)
         from (
           select row_index, reason from validated where reason is not null
           union all
           select row_index, combined_reason as reason from reasoned where combined_reason is not null
           union all
           select row_index, 'superseded by a later row in the same batch with the same (profile_id, source, source_id)'
             from source_ranked where source_dupe_rank > 1
           union all
           select row_index, 'duplicate date in batch'
             from date_ranked where date_dupe_rank > 1
         ) x)
    into v_inserted, v_revived, v_updated, v_rejected;
  exception
    when unique_violation then
      raise exception 'a row in this batch collides with an existing day_entries row under a different identity (its id resolves to one row, its (profile_id, source, source_id) to another) -- the client must ensure a row''s id and source_id always resolve to the same existing row before retrying'
        using errcode = 'invalid_parameter_value';
  end;

  -- Issue #167: touch sync_signals exactly once for the job's profile,
  -- rather than once per row (touch_sync_signal() no-op'd above) -- only
  -- if something actually changed. now() (transaction start time), not
  -- clock_timestamp() -- consistent with touch_sync_signal() itself and
  -- every other sync_signals writer in this schema, none of which have a
  -- same-transaction reason to need statement-time precision.
  if (v_inserted + v_updated + v_revived) > 0 then
    insert into public.sync_signals (profile_id, updated_at)
    values (v_job.profile_id, now())
    on conflict (profile_id) do update set updated_at = excluded.updated_at;
  end if;

  return jsonb_build_object(
    'inserted', v_inserted,
    'updated', v_updated,
    'revived', v_revived,
    'rejected', v_rejected
  );
end;
$$;

comment on function public.bulk_import_entries(uuid, jsonb) is
  'Issue #167: set-based bulk upsert of day_entries for large imports (up '
  'to 2000 rows/call), bypassing sync_push entirely -- SECURITY DEFINER, '
  'guardian-write-role checked against the p_import_id job''s profile '
  '(before the job-status check below it, so an unauthorised caller learns '
  'nothing about a job''s status), every row''s profile_id must equal the '
  'job''s. source/import_id come from the import_jobs row, never the '
  'payload. Two disjoint set-based write paths: a row whose id already '
  'exists in day_entries (any provenance) is UPDATEd in place with '
  'last-writer-wins on updated_at, mirroring sync_push''s own resolution '
  '(a stale update is silently skipped, not rejected); every other row '
  'requires a non-null source_id (rejected otherwise -- '
  '`source_id is required for idempotent import`, documented on '
  'BulkImportRow) and goes through '
  '`insert ... select ... on conflict (profile_id, source, source_id) '
  'where source_id is not null do update` -- the same raw shape '
  'import_provenance_test.sql pins as the way to revive a tombstoned '
  'imported row, which sync_push cannot do (it resolves strictly by id; '
  'see this migration''s header and AGENTS.md Migration Flow item 8). This '
  'two-path split is what makes a retry of an already-landed chunk '
  'idempotent instead of aborting on a primary-key collision. Validation '
  'is fully set-based (jsonb_array_elements ... with ordinality plus two '
  'safe-cast helpers and public.is_valid_timezone()), not a per-row loop, '
  'so a malformed individual row is rejected (row_index, reason) rather '
  'than aborting the batch -- covering every day_entries CHECK the row '
  'shape can violate (id/profile_id ULID, local_date, tz, flow, tags, '
  'note length, source_id length, updated_at). A tombstone row (deleted_at '
  'present) has its flow/tags/note forced to the empty payload rather than '
  'validated or rejected, mirroring sync_push. Two independent '
  'within-batch duplicate rules: two rows sharing (profile_id, source, '
  'source_id) resolve to the later row (by position) winning; two rows '
  'sharing (profile_id, local_date) with different source_id resolve to '
  'the earlier row winning (`duplicate date in batch`) -- no in-RPC '
  'resolver for either kind of ambiguity. A row landing live on a date a '
  'different, differently-provenanced LIVE row already occupies is '
  'likewise rejected (`date already has a live entry`) rather than merged '
  '-- decision: no in-RPC resolver in this PR; the client surfaces the '
  'conflict. Sets lunarlog.bulk_import = ''on'' (transaction-local) for '
  'the duration of the write so touch_sync_signal()/'
  'enqueue_caregiver_alerts() no-op per row -- this function touches '
  'sync_signals itself, once, at the end, and never enqueues a caregiver '
  'alert for an imported row. Must complete within the caller''s ordinary '
  '8s role statement_timeout, like any other RPC -- an earlier draft''s '
  '`set local statement_timeout = ''60s''` was removed as a documented '
  'no-op (that GUC is sampled once at statement start; a mid-statement '
  '`set local` cannot retroactively widen it). Returns '
  '{inserted, updated, revived, rejected: [{row_index, reason}]}. Scoped '
  'to day_entries only (issue''s Proposed change is day_entries-first) -- '
  'an observations-shaped row is rejected as carrying unknown keys. The '
  'unique_violation backstop below is not purely theoretical: this '
  'function takes no day_entries row locks, so it can still fire on a '
  'genuine concurrent race with sync_push writing the same row(s) '
  '(unlike sync_push, which serialises per-user via '
  'pg_advisory_xact_lock), as well as on the id/source_id split '
  'resolution its own message describes -- either way, the client should '
  'retry the whole chunk.';

revoke all on function public.bulk_import_entries(uuid, jsonb) from public, anon;
grant execute on function public.bulk_import_entries(uuid, jsonb) to authenticated;
