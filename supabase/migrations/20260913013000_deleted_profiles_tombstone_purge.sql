-- Migration: 20260913013000_deleted_profiles_tombstone_purge.sql
--
-- Issue #522 (P1): delete_profile_data() and delete_account_data() hard-
-- purge every per-profile table with real DELETEs. The sync protocol only
-- transports rows that EXIST - incremental pull is `server_version >
-- cursor`, and the 24h reconcile applies whatever the server returns but
-- never removes a local row the server no longer has (it is apply-only -
-- see supabase_sync_apply.dart's applyReconcilePage). A hard-deleted row is
-- therefore indistinguishable, client-side, from "nothing changed": a
-- co-guardian's device keeps every day_entry/observation/care_note/
-- visit_prep_item of a "purged" profile forever, which defeats the
-- GDPR/CCPA erasure story delete_profile_data/delete_account_data exist
-- to provide.
--
-- =============================================================================
-- Design: tombstone-then-purge, physical DELETE deferred to a later
-- retention sweep (#263)
-- =============================================================================
--
-- The fix cannot be "tombstone the children, then DELETE the profiles row
-- as before": public.day_entries/observations/care_notes/visit_prep_items/
-- cycle_overrides all carry `foreign key (profile_id) references
-- public.profiles (id) on delete cascade` (20260904010000_multi_guardian_schema.sql
-- and friends). If this function tombstones a table and THEN physically
-- deletes the profiles row in the same transaction, the cascade fires and
-- HARD-DELETES the very tombstones just written, before commit - the
-- children vanish just as completely as before, only one statement later.
-- So this migration does NOT physically delete anything new-content-bearing.
-- Every synced per-profile content table this migration touches - day_entries,
-- observations, care_notes, visit_prep_items, cycle_overrides - moves from a
-- real DELETE to `update ... set deleted_at = <now>, <payload columns
-- cleared>` (bumping server_version via the existing set_server_version
-- trigger, so the tombstone propagates through the ordinary incremental
-- pull to every guardian's device). The profiles row itself is tombstoned
-- the same way (deleted_at set, every PII/content column cleared) rather
-- than deleted, for the identical cascade reason.
--
-- Per the account-deletion PROMISE (the data must actually be gone, not
-- merely hidden): every tombstone this migration writes clears its full
-- payload, matching each table's own `*_tombstone_*_check` CHECK
-- constraint exactly - a purge tombstone is byte-for-byte the same shape a
-- normal sync_push delete produces. No health content, note text, or PII
-- survives the call; only empty placeholder rows remain, kept solely so
-- the DELETION ITSELF can propagate. The physical DELETE that finally
-- reclaims the row storage is out of scope for this migration and left to
-- the retention sweep #263 already contemplated for this purpose.
--
-- =============================================================================
-- public.deleted_profiles: the profile-level tombstone signal
-- =============================================================================
--
-- profiles.deleted_at already exists and already propagates an ordinary
-- user-initiated archive/delete (sync_push's profile branch) through the
-- normal profiles pull. This migration deliberately does NOT reuse that
-- path for a PURGE for two reasons: (1) once the profiles row is
-- tombstoned-not-deleted here, profile_guardians rows for it are still
-- hard-deleted below (unchanged from before this migration - a purge still
-- immediately revokes every membership), so a normal `is_profile_guardian`-
-- style RLS check has nothing left to authorize a read of the profiles row
-- against; and (2) a purge is a stronger, one-way action a client should
-- treat unconditionally (drop all local state for this profile id), never
-- confusable with an ordinary archive/soft-delete a user might expect to
-- see restored via undo UI.
--
-- public.deleted_profiles(profile_id, deleted_at, server_version,
-- guardian_user_ids) is an insert-only, append-only log: one row per
-- profile ever purged via delete_profile_data or delete_account_data.
-- `guardian_user_ids` snapshots every user_id that held an ACCEPTED
-- profile_guardians membership on the profile AT THE MOMENT OF PURGE,
-- captured before profile_guardians rows are removed - this is what makes
-- RLS on this table possible without needing profile_guardians to survive
-- the purge. `server_version` is stamped by the same
-- public.set_server_version() trigger every other synced table uses, so
-- the same `server_version > cursor` incremental-pull shape works
-- unmodified for a future client-side reader.
--
-- CONTRACT for the future client-side reader (per this task's brief: "a
-- separate agent will add the client-side reader for deleted_profiles"):
--   - Pull `select profile_id, deleted_at from public.deleted_profiles
--     where server_version > :cursor order by server_version` exactly like
--     any other synced table's incremental pull.
--   - On receiving a row, the client should treat it as: delete the local
--     profiles row and every local row scoped to that profile_id, across
--     every locally-cached table (day_entries, observations, profile_modes,
--     cycle_overrides, care_notes, visit_prep_items, profile_guardians) -
--     not merely apply a per-table tombstone diff. The server-side
--     per-table tombstones this migration ALSO writes (day_entries,
--     observations, care_notes, visit_prep_items, cycle_overrides) exist as
--     defense-in-depth for a client that has not yet adopted this table (or
--     pulls those tables before the deleted_profiles row on the same
--     cycle), not as the primary signal.
--   - profile_modes and profile_guardians are NOT tombstoned by this
--     migration (see "Known scope limits" below) - they are still
--     immediately hard-deleted, so a client relying solely on per-table
--     diffs for those two will never see a diff for them once purged, and
--     must key off the deleted_profiles row to clean them up locally.
--   - Rows never update or delete once written (append-only); a profile_id
--     is only ever purged once (delete_profile_data is not idempotent - a
--     second call finds no accepted primary_guardian membership left and
--     raises, unchanged from before this migration).
--
-- =============================================================================
-- Known scope limits (deliberate, documented rather than silently expanded)
-- =============================================================================
--   - profile_modes has no deleted_at/tombstone column at all (by design -
--     see 20260909000000_profile_modes_and_cycle_overrides.sql's header,
--     "one row per profile, no tombstone"). Adding tombstone semantics to a
--     table explicitly designed without them is a larger schema change out
--     of scope for this fix; it stays a hard DELETE, same as before. A
--     client that has adopted the deleted_profiles contract above drops its
--     local copy via the profile-level signal regardless.
--   - profile_guardians, guardian_invitations, ownership_transfers,
--     prediction_connections, prediction_projections, import_jobs,
--     notification_preferences, notification_outbox,
--     missed_entry_alert_state, profile_reminder_windows: unchanged, still
--     immediately hard-deleted. None of these carry health content or PII
--     that the account-deletion promise is about (membership/audit/consent
--     rows only); immediate physical removal is, if anything, MORE private,
--     not less. Related: #499 ("tables the RPC forgets").
--   - delete_profile_data's `p_source`-scoped variant (delete only rows of
--     one import source, profile survives) is UNCHANGED - still a real
--     DELETE. That path never removes a shared profile from co-guardians'
--     view (the profile and every membership survive), so the specific
--     "co-guardians keep a purged profile's data forever" failure mode this
--     issue reports does not apply to it. Narrowing the p_source path's
--     own propagation gap, if one is wanted, is left for a follow-up.
--   - IMPORTANT CAVEAT on delete_account_data() specifically (flagged for
--     reviewer scrutiny): public.profiles.user_id is `not null references
--     auth.users (id) on delete cascade` (20260903014208_initial_sync_schema.sql,
--     unchanged by this migration - making it nullable and switching to
--     `on delete set null` is a materially bigger schema change than this
--     fix's scope). delete_account_data() is always followed, moments
--     later in the delete-account Edge Function, by a SEPARATE
--     `auth.admin.deleteUser` call (a different transaction). That deletes
--     the auth.users row, which CASCADES and physically deletes the very
--     profiles row(s) this migration just tombstoned - and THAT delete
--     cascades again to their now-tombstoned-but-still-physically-present
--     day_entries/observations/care_notes/visit_prep_items/cycle_overrides,
--     removing them for real. So for a full ACCOUNT deletion, the
--     tombstone this migration writes has only the narrow window between
--     delete_account_data()'s commit and the Edge Function's subsequent
--     auth.admin.deleteUser call to reach a co-guardian's pull - likely
--     much narrower than a typical sync interval, and NOT the durable fix
--     delete_profile_data() gets (which never touches auth.users and keeps
--     its tombstones indefinitely, until the future retention sweep).
--     delete_profile_data() - the standalone "delete this one profile"
--     path with no following account deletion - gets this fix's full,
--     durable benefit; delete_account_data() gets best-effort, defense-in-
--     depth consistency with it, not a complete close of the propagation
--     gap for a full account deletion. Closing that fully needs either a
--     nullable profiles.user_id with `on delete set null`, or having the
--     Edge Function defer auth.admin.deleteUser - both product/schema
--     decisions for a dedicated follow-up, not this PR.

-- ---------------------------------------------------------------------------
-- 1. public.deleted_profiles
-- ---------------------------------------------------------------------------

create table if not exists public.deleted_profiles (
  profile_id text primary key,
  deleted_at timestamptz not null default clock_timestamp(),
  server_version bigint,
  guardian_user_ids uuid[] not null default '{}'
);

comment on table public.deleted_profiles is
  'Issue #522: append-only log of profiles purged via delete_profile_data() '
  'or delete_account_data(). See 20260913013000_deleted_profiles_tombstone_purge.sql''s '
  'header for the full pull contract. guardian_user_ids snapshots the '
  'accepted membership list at purge time (profile_guardians itself is '
  'hard-deleted by the purge), which is what RLS below keys on. Rows are '
  'never updated or deleted once written.';

create index if not exists deleted_profiles_server_version_idx
  on public.deleted_profiles (server_version);

alter table public.deleted_profiles enable row level security;
alter table public.deleted_profiles force row level security;

create policy "deleted_profiles_select_former_guardians" on public.deleted_profiles
  for select to authenticated
  using ((select auth.uid()) = any (guardian_user_ids));

-- Written only by the SECURITY DEFINER purge RPCs below (KTD15: no direct
-- client write path for anything gating sync state).
revoke all on table public.deleted_profiles from public, anon, authenticated;
grant select on table public.deleted_profiles to authenticated;

create trigger deleted_profiles_set_server_version
  before insert on public.deleted_profiles
  for each row execute function public.set_server_version();

-- ---------------------------------------------------------------------------
-- 2. public.tombstone_profile_content(profile_id, now): the shared
--    tombstone-then-purge step for the five synced content tables, used by
--    BOTH delete_profile_data and delete_account_data below. Not directly
--    callable by anyone (see grants) - it takes no caller-authority check
--    of its own and trusts the profile_id its SECURITY DEFINER callers
--    have already authorized. Every clause mirrors the exact column set
--    each table's own `*_tombstone_*_check` CHECK constraint demands, so a
--    purge tombstone is indistinguishable in shape from a normal sync_push
--    delete.
-- ---------------------------------------------------------------------------

create or replace function public.tombstone_profile_content(
  p_profile_id text,
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day_entries bigint := 0;
  v_observations bigint := 0;
  v_care_notes bigint := 0;
  v_visit_prep_items bigint := 0;
  v_cycle_overrides bigint := 0;
begin
  -- last_modified_by_user_id is set explicitly on every UPDATE below (the
  -- enforce_day_entry_attribution / enforce_observation_attribution /
  -- enforce_care_note_attribution / enforce_prep_item_attribution guards
  -- each raise, on an UPDATE, unless `new.last_modified_by_user_id` equals
  -- the calling auth.uid() exactly - the same requirement sync_push's own
  -- UPDATE branches satisfy on every row they touch). coalesce() falls
  -- back to the row's existing stamp only for a null-auth.uid() caller
  -- (migrations/service role - the attribution guards return early in that
  -- case and do not check this column at all, but the coalesce keeps the
  -- column itself sane either way). cycle_overrides carries no attribution
  -- columns and needs no such guard.
  --
  -- Counted BEFORE the day_entries update below, not via that update's own
  -- explicit UPDATE row_count: day_entries_after_tombstone_cascade_observations
  -- (20260913012000_cascade_tombstone_lww_guard.sql, greatest()-guarded)
  -- tombstones every live child observation as a side effect of the
  -- day_entries UPDATE's own AFTER trigger, BEFORE the explicit
  -- `update public.observations ... where deleted_at is null` below ever
  -- runs - so by the time that statement executes, the cascade has already
  -- excluded every row it touched from matching `deleted_at is null`, and
  -- its own row_count would undercount (report 0 even though every
  -- observation was, correctly, tombstoned - just via the cascade, not
  -- this statement). Every live observation on the profile is guaranteed
  -- to end up tombstoned by the end of this function (via the cascade, or
  -- the explicit catch-all below for the belt-and-suspenders case the
  -- cascade doesn't cover), so the pre-count here is the correct total
  -- regardless of which path actually did the write.
  select count(*) into v_observations
    from public.observations
   where profile_id = p_profile_id
     and deleted_at is null;

  update public.day_entries
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         flow = 'none',
         note = null,
         tags = '[]'::jsonb,
         pms = false,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_day_entries = row_count;

  -- Belt-and-suspenders catch-all (see the comment above): every live
  -- observation has a day_entry_id, so in practice this touches zero rows
  -- - the cascade above already got all of them - but it is not relied
  -- upon for the returned count.
  update public.observations
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         category = null,
         code = null,
         value_num = null,
         value_text = null,
         unit = null,
         intensity = null,
         excluded = false,
         raw = null,
         observed_at = null,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;

  update public.care_notes
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         body = '',
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_care_notes = row_count;

  update public.visit_prep_items
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         body = '',
         is_checked = false,
         checked_by_user_id = null,
         checked_at = null,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_visit_prep_items = row_count;

  update public.cycle_overrides
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         excluded_from_average = false,
         manual_start = false,
         note_id = null
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_cycle_overrides = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries,
    'observations', v_observations,
    'care_notes', v_care_notes,
    'visit_prep_items', v_visit_prep_items,
    'cycle_overrides', v_cycle_overrides
  );
end;
$$;

comment on function public.tombstone_profile_content(text, timestamptz) is
  'Issue #522: tombstones (deleted_at set, payload cleared to each table''s '
  'own CHECK-required shape) every live day_entries/observations/care_notes/ '
  'visit_prep_items/cycle_overrides row for one profile, bumping '
  'server_version so the tombstone propagates via the ordinary incremental '
  'pull - shared by delete_profile_data() and delete_account_data() so both '
  'purge paths tombstone content identically. Takes no caller-authority '
  'check of its own; callable only from a SECURITY DEFINER function that '
  'has already authorized p_profile_id (no EXECUTE grant to any client-facing '
  'role - see this migration''s footer).';

revoke all on function public.tombstone_profile_content(text, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. delete_profile_data(): re-emitted from its only prior definition
--    (20260910110000_delete_profile_data.sql). Authority check and the
--    p_source-scoped branch are BYTE-IDENTICAL to that version (see this
--    migration's header, "Known scope limits", for why the p_source branch
--    is deliberately left a hard delete). Only the full-purge branch
--    (p_source is null) changes: content tables move to
--    tombstone_profile_content(), and the profiles row is tombstoned
--    (payload cleared) plus logged in deleted_profiles instead of
--    physically deleted - ordered so the tombstone UPDATE runs WHILE the
--    caller's own accepted primary_guardian profile_guardians row still
--    exists, ahead of that row's own deletion further down (the #517
--    enforce_profile_guardian_only_deletion trigger would otherwise find
--    no accepted primary_guardian left and refuse this function's own
--    tombstone write).
-- ---------------------------------------------------------------------------

create or replace function public.delete_profile_data(
  p_profile_id text,
  p_source text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_caller_role text;
  v_now timestamptz;
  v_guardian_user_ids uuid[];
  v_content_counts jsonb;
  v_day_entries_deleted bigint := 0;
  v_observations_deleted bigint := 0;
  v_profile_modes_deleted bigint := 0;
  v_cycle_overrides_deleted bigint := 0;
  v_care_notes_deleted bigint := 0;
  v_visit_prep_items_deleted bigint := 0;
  v_profile_reminder_windows_deleted bigint := 0;
  v_missed_entry_alert_state_deleted bigint := 0;
  v_notification_preferences_deleted bigint := 0;
  v_notification_outbox_deleted bigint := 0;
  v_guardian_invitations_deleted bigint := 0;
  v_profile_guardians_deleted bigint := 0;
  v_import_jobs_deleted bigint := 0;
  v_ownership_transfers_deleted bigint := 0;
  v_prediction_connections_deleted bigint := 0;
  v_prediction_projections_deleted bigint := 0;
  v_sync_signals_count bigint := 0;
  v_profiles_tombstoned bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required'
      using errcode = 'insufficient_privilege';
  end if;

  -- Authority: the caller must hold an ACCEPTED primary_guardian
  -- membership on the named profile - the same rung sync_push requires
  -- for tombstone-deletion/archival. A nonexistent profile and a profile
  -- the caller is not the accepted primary_guardian of raise the
  -- identical error, so the RPC cannot be used to enumerate profile ids.
  select role into v_caller_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = v_uid
     and status = 'accepted';

  if v_caller_role is null or v_caller_role <> 'primary_guardian' then
    raise exception 'profile not found or caller is not its accepted primary_guardian'
      using errcode = 'insufficient_privilege';
  end if;

  if p_source is not null then
    -- Scoped purge (unchanged by Issue #522 - see this migration's header,
    -- "Known scope limits"): validate against the union of the two source
    -- vocabularies (day_entries/import_jobs vs observations - see the
    -- original migration's header) so a typo'd source raises here rather
    -- than silently deleting nothing. Matching itself stays exact per
    -- table. The profile and every membership survive this branch, so the
    -- "co-guardians keep a purged profile forever" failure mode does not
    -- apply to it.
    if p_source not in
       ('manual', 'clue_import', 'healthkit', 'health_connect',
        'file_import', 'apple_health', 'wearable') then
      raise exception 'unknown source: %', p_source
        using errcode = 'invalid_parameter_value';
    end if;

    -- Observations before day_entries, so the count reflects rows this
    -- call deleted rather than rows the day_entries delete cascaded.
    delete from public.observations
     where profile_id = p_profile_id
       and source = p_source;
    get diagnostics v_observations_deleted = row_count;

    delete from public.day_entries
     where profile_id = p_profile_id
       and source = p_source;
    get diagnostics v_day_entries_deleted = row_count;

    delete from public.import_jobs
     where profile_id = p_profile_id
       and source = p_source;
    get diagnostics v_import_jobs_deleted = row_count;

    return jsonb_build_object(
      'source', p_source,
      'day_entries', v_day_entries_deleted,
      'observations', v_observations_deleted,
      'import_jobs', v_import_jobs_deleted
    );
  end if;

  -- Full purge (Issue #522: tombstone-then-purge). Content tables move
  -- through the shared helper; profile_modes and every remaining
  -- per-profile table are still hard-deleted (see this migration's header,
  -- "Known scope limits") - none of them carry health content or PII the
  -- account-deletion promise is about.
  v_now := clock_timestamp();

  -- Captured BEFORE any delete below, since profile_guardians itself is
  -- hard-deleted further down - this is what lets deleted_profiles' RLS
  -- policy authorize a read with no surviving profile_guardians row to
  -- check against.
  select array_agg(user_id order by user_id) into v_guardian_user_ids
    from public.profile_guardians
   where profile_id = p_profile_id
     and status = 'accepted';

  v_content_counts := public.tombstone_profile_content(p_profile_id, v_now);
  v_day_entries_deleted := (v_content_counts ->> 'day_entries')::bigint;
  v_observations_deleted := (v_content_counts ->> 'observations')::bigint;
  v_care_notes_deleted := (v_content_counts ->> 'care_notes')::bigint;
  v_visit_prep_items_deleted := (v_content_counts ->> 'visit_prep_items')::bigint;
  v_cycle_overrides_deleted := (v_content_counts ->> 'cycle_overrides')::bigint;

  delete from public.profile_modes
   where profile_id = p_profile_id;
  get diagnostics v_profile_modes_deleted = row_count;

  -- Issue #5 tables: every guardian's rows for THIS profile go - the
  -- profile is gone from every guardian's point of view, so nothing can
  -- alert anyone about it afterwards.
  delete from public.profile_reminder_windows
   where profile_id = p_profile_id;
  get diagnostics v_profile_reminder_windows_deleted = row_count;

  delete from public.missed_entry_alert_state
   where profile_id = p_profile_id;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  delete from public.notification_preferences
   where profile_id = p_profile_id;
  get diagnostics v_notification_preferences_deleted = row_count;

  delete from public.notification_outbox
   where profile_id = p_profile_id;
  get diagnostics v_notification_outbox_deleted = row_count;

  -- Outstanding invitations for this profile, whoever sent them.
  delete from public.guardian_invitations
   where profile_id = p_profile_id;
  get diagnostics v_guardian_invitations_deleted = row_count;

  delete from public.import_jobs
   where profile_id = p_profile_id;
  get diagnostics v_import_jobs_deleted = row_count;

  -- Issue #4: live, expired, accepted, or cancelled - all of them are
  -- rows about a profile that will no longer accept new guardianship.
  delete from public.ownership_transfers
   where profile_id = p_profile_id;
  get diagnostics v_ownership_transfers_deleted = row_count;

  -- Issue #151. The projection row goes BEFORE the connection rows:
  -- deleting a connection fires prediction_connections_projection_gc(),
  -- whose own AFTER DELETE hook would remove the projection row first and
  -- leave this function's returned count at zero.
  delete from public.prediction_projections
   where profile_id = p_profile_id;
  get diagnostics v_prediction_projections_deleted = row_count;

  delete from public.prediction_connections
   where profile_id = p_profile_id;
  get diagnostics v_prediction_connections_deleted = row_count;

  -- Counted, not removed: the profile is tombstoned, not deleted, so
  -- touch_sync_signal()'s existence check never fires here - the row
  -- survives (it is content-free, so this is not a privacy concern).
  select count(*) into v_sync_signals_count
    from public.sync_signals
   where profile_id = p_profile_id;

  -- Tombstone the profile itself - see this section's header comment for
  -- why this MUST run before the profile_guardians delete below.
  update public.profiles
     set deleted_at = v_now,
         archived_at = coalesce(archived_at, v_now),
         display_name = '',
         is_minor = false,
         birth_year = null,
         relationship = null,
         mode = 'standard',
         last_period_start = null,
         typical_cycle_length_days = null,
         typical_period_length_days = null
   where id = p_profile_id;
  get diagnostics v_profiles_tombstoned = row_count;

  insert into public.deleted_profiles (profile_id, deleted_at, guardian_user_ids)
  values (p_profile_id, v_now, coalesce(v_guardian_user_ids, '{}'));

  -- Every membership on this profile, including the co-guardians'. Safe
  -- only now that the profiles tombstone above has already run (it needed
  -- this exact row to authorize itself via the #517 trigger).
  delete from public.profile_guardians
   where profile_id = p_profile_id;
  get diagnostics v_profile_guardians_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'observations', v_observations_deleted,
    'profile_modes', v_profile_modes_deleted,
    'cycle_overrides', v_cycle_overrides_deleted,
    'care_notes', v_care_notes_deleted,
    'visit_prep_items', v_visit_prep_items_deleted,
    'profile_reminder_windows', v_profile_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'guardian_invitations', v_guardian_invitations_deleted,
    'profile_guardians', v_profile_guardians_deleted,
    'import_jobs', v_import_jobs_deleted,
    'ownership_transfers', v_ownership_transfers_deleted,
    'prediction_connections', v_prediction_connections_deleted,
    'prediction_projections', v_prediction_projections_deleted,
    'sync_signals', v_sync_signals_count,
    'profiles', v_profiles_tombstoned
  );
end;
$$;

comment on function public.delete_profile_data(text, text) is
  'Issue #264: purges ONE profile; Issue #522: the full-purge branch (p_source '
  'null) now tombstones rather than hard-deletes day_entries, observations, '
  'care_notes, visit_prep_items, and cycle_overrides (payload cleared, '
  'server_version bumped via public.tombstone_profile_content()) and '
  'tombstones the profiles row itself (payload cleared) instead of deleting '
  'it, logging the purge in public.deleted_profiles so every former '
  'guardian''s device can learn the profile is gone via the ordinary '
  'incremental pull - see 20260913013000_deleted_profiles_tombstone_purge.sql''s '
  'header for the full contract, the physical-DELETE-is-cascade-unsafe '
  'reasoning, and the tables deliberately left as immediate hard deletes '
  '(profile_modes, profile_guardians, guardian_invitations, '
  'ownership_transfers, prediction_connections, prediction_projections, '
  'import_jobs, notification_preferences, notification_outbox, '
  'missed_entry_alert_state, profile_reminder_windows - none carry health '
  'content or PII). The p_source-scoped branch is unchanged: it still hard-'
  'deletes day_entries/observations/import_jobs of one source, and the '
  'profile and its guardians survive. SECURITY DEFINER; callable only by '
  'the profile''s ACCEPTED primary_guardian; a nonexistent profile and an '
  'unauthorized caller raise the identical error. Not idempotent on the '
  'full-purge branch: a second call finds no accepted primary_guardian '
  'membership left (profile_guardians was hard-deleted by the first call) '
  'and raises.';

revoke execute on function public.delete_profile_data(text, text)
  from public, anon;
grant execute on function public.delete_profile_data(text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. delete_account_data(): re-emitted from its latest prior definition
--    (20260909141503_care_notes_visit_prep.sql). Every per-user table
--    delete (settings, push_devices, feedback_tickets, notification_*,
--    missed_entry_alert_state, guardian_invitations by invited_by,
--    profile_guardians by user_id, import_jobs by created_by) is
--    UNCHANGED. What changes: the per-OWNED-profile content that used to
--    be five standalone DELETEs (observations, profile_modes minus - see
--    below, cycle_overrides, care_notes, visit_prep_items, day_entries) is
--    now a loop over every profile the caller owns, tombstoning each via
--    the same public.tombstone_profile_content() helper delete_profile_data()
--    uses, then tombstoning the profiles row itself (instead of relying on
--    the old `delete from public.profiles where user_id = v_uid`) and
--    logging it in deleted_profiles. profile_modes has no tombstone column
--    (see this migration's header) and stays a hard delete.
--
--    Ordering: the owned-profile tombstone loop runs FIRST (right after
--    rehome_stray_day_entries, before any other delete), because the
--    profiles UPDATE inside it must run while the caller's own accepted
--    primary_guardian profile_guardians row for that profile still
--    exists - `delete from public.profile_guardians where user_id = v_uid`
--    (further down, unchanged) would otherwise have already removed it,
--    and the #517 enforce_profile_guardian_only_deletion trigger would
--    refuse the tombstone.
-- ---------------------------------------------------------------------------

create or replace function public.delete_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_now timestamptz;
  v_profile_id text;
  v_guardian_user_ids uuid[];
  v_content_counts jsonb;
  v_day_entries_rehomed bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_observations_deleted bigint := 0;
  v_profile_modes_deleted bigint := 0;
  v_care_notes_deleted bigint := 0;
  v_cycle_overrides_deleted bigint := 0;
  v_visit_prep_items_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_tombstoned bigint := 0;
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
  -- public.rehome_stray_day_entries() - the delete-account Edge Function
  -- calls it a second time, standalone, immediately before
  -- auth.admin.deleteUser. Unchanged by Issue #522.
  v_day_entries_rehomed := public.rehome_stray_day_entries(v_uid);

  -- Issue #522: tombstone-then-purge every profile the caller OWNS. Must
  -- run before ANY delete below that could remove the caller's own
  -- profile_guardians row (see this section's header comment).
  v_now := clock_timestamp();
  -- `deleted_at is null` is the idempotency guard: without it, a SECOND
  -- call would re-select an already-tombstoned owned profile (the row
  -- still exists - it is tombstoned, not deleted), attempt a second
  -- deleted_profiles insert and collide with that table's primary key, and
  -- fail the #517 enforce_profile_guardian_only_deletion trigger regardless
  -- (this call's own profile_guardians delete further down already removed
  -- the caller's primary_guardian row on the first call). Scoping to
  -- still-live profiles makes a retry a true no-op, matching
  -- delete_account_data()'s documented idempotency contract.
  for v_profile_id in
    select id from public.profiles where user_id = v_uid and deleted_at is null
  loop
    select array_agg(user_id) into v_guardian_user_ids
      from public.profile_guardians
     where profile_id = v_profile_id
       and status = 'accepted';

    v_content_counts := public.tombstone_profile_content(v_profile_id, v_now);
    v_day_entries_deleted := v_day_entries_deleted + (v_content_counts ->> 'day_entries')::bigint;
    v_observations_deleted := v_observations_deleted + (v_content_counts ->> 'observations')::bigint;
    v_care_notes_deleted := v_care_notes_deleted + (v_content_counts ->> 'care_notes')::bigint;
    v_visit_prep_items_deleted := v_visit_prep_items_deleted + (v_content_counts ->> 'visit_prep_items')::bigint;
    v_cycle_overrides_deleted := v_cycle_overrides_deleted + (v_content_counts ->> 'cycle_overrides')::bigint;

    update public.profiles
       set deleted_at = v_now,
           archived_at = coalesce(archived_at, v_now),
           display_name = '',
           is_minor = false,
           birth_year = null,
           relationship = null,
           mode = 'standard',
           last_period_start = null,
           typical_cycle_length_days = null,
           typical_period_length_days = null
     where id = v_profile_id;
    v_profiles_tombstoned := v_profiles_tombstoned + 1;

    insert into public.deleted_profiles (profile_id, deleted_at, guardian_user_ids)
    values (v_profile_id, v_now, coalesce(v_guardian_user_ids, '{}'));
  end loop;

  -- Issue #188: profile_modes has no tombstone column (this migration's
  -- header, "Known scope limits") and stays a hard delete, scoped to owned
  -- profiles exactly as before this migration.
  delete from public.profile_modes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_profile_modes_deleted = row_count;

  -- Issue #5, U4: profile_reminder_windows for profiles the caller *owns*.
  delete from public.profile_reminder_windows
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_reminder_windows_deleted = row_count;

  -- Issue #5, U4: the caller's own pending caregiver alerts, on any
  -- profile (their own, or one they merely guard).
  delete from public.notification_outbox
   where recipient_user_id = v_uid;
  get diagnostics v_notification_outbox_deleted = row_count;

  -- Invitations the caller created, for any profile (their own or one they
  -- co-parent).
  delete from public.guardian_invitations
   where invited_by = v_uid;
  get diagnostics v_invitations_deleted = row_count;

  -- The caller's own guardian memberships. Safe only now that every owned
  -- profile has already been tombstoned above (see this section's header).
  delete from public.profile_guardians
   where user_id = v_uid;
  get diagnostics v_guardians_deleted = row_count;

  -- Issue #5, U4: the caller's own notification preferences, on any
  -- profile they guard.
  delete from public.notification_preferences
   where user_id = v_uid;
  get diagnostics v_notification_preferences_deleted = row_count;

  -- Issue #5, U4: the caller's own registered devices.
  delete from public.push_devices
   where user_id = v_uid;
  get diagnostics v_push_devices_deleted = row_count;

  -- Round-2 review #8: the caller's own missed-entry dedupe markers, on
  -- any profile.
  delete from public.missed_entry_alert_state
   where user_id = v_uid;
  get diagnostics v_missed_entry_alert_state_deleted = row_count;

  -- Issue #243 (D-25): the caller's own feedback tickets, explicitly.
  -- feedback_replies cascades from feedback_tickets.
  delete from public.feedback_tickets
   where user_id = v_uid;
  get diagnostics v_feedback_tickets_deleted = row_count;

  -- Issue #167: the caller's own import jobs, on any profile.
  delete from public.import_jobs
   where created_by = v_uid;
  get diagnostics v_import_jobs_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'day_entries_rehomed', v_day_entries_rehomed,
    'observations', v_observations_deleted,
    'profile_modes', v_profile_modes_deleted,
    'cycle_overrides', v_cycle_overrides_deleted,
    'care_notes', v_care_notes_deleted,
    'visit_prep_items', v_visit_prep_items_deleted,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_tombstoned,
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
  'day_entries, observations, profile_modes and cycle_overrides, care_notes '
  'and visit_prep_items, settings, profile_guardians, guardian_invitations, '
  'notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, missed_entry_alert_state, and feedback_tickets, '
  'first calling public.rehome_stray_day_entries(auth.uid()). Issue #522: '
  'day_entries, observations, care_notes, visit_prep_items, and '
  'cycle_overrides on every OWNED profile are now tombstoned (payload '
  'cleared, server_version bumped via public.tombstone_profile_content()) '
  'rather than hard-deleted, and each owned profile itself is tombstoned '
  '(payload cleared) and logged in public.deleted_profiles instead of '
  'physically deleted - so a co-guardian''s device learns the account and '
  'its profiles are gone via the ordinary incremental pull, instead of '
  'keeping stale local copies forever. See '
  '20260913013000_deleted_profiles_tombstone_purge.sql''s header for the '
  'full contract and the tables deliberately left as immediate hard '
  'deletes (profile_modes among them - see "Known scope limits"). That call '
  'runs as this function''s own security-definer owner, so it succeeds '
  'regardless of rehome_stray_day_entries()''s own (revoked) grants. Takes '
  'no parameters itself - the caller is always the subject. Called by the '
  'delete-account Edge Function only after it has already removed the '
  'caller''s feedback-attachments Storage objects; that same function then '
  'revokes Apple and deletes the auth.users row. It also calls '
  'rehome_stray_day_entries() a second time, standalone, on its '
  'service-role client, immediately before the auth.users deletion.';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
