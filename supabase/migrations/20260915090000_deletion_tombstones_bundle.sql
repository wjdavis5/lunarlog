-- Migration: 20260915090000_deletion_tombstones_bundle.sql
--
-- Server-side deletion bundle: Issues #595, #596, #599 (a follow-up review
-- bundle on top of #522/#582's tombstone-then-purge work).
--
-- =============================================================================
-- Issue #595: delete_profile_data(p_source)'s source-scoped branch now
-- tombstones instead of hard-deleting.
-- =============================================================================
--
-- delete_profile_data()'s full-purge branch (p_source null) was already
-- fixed by #522 (20260913013000_deleted_profiles_tombstone_purge.sql) to
-- tombstone day_entries/observations/care_notes/visit_prep_items/
-- cycle_overrides rather than hard-delete them, specifically so the removal
-- propagates to a co-guardian's device via the ordinary incremental pull.
-- That migration's own header explicitly left the p_source-scoped branch
-- (delete only rows of one import source, profile survives) unchanged,
-- reasoning that "the specific co-guardians-keep-a-purged-profile's-data-
-- forever failure mode does not apply to it" since the PROFILE itself
-- survives. That reasoning covered the profile-level signal, but missed the
-- per-row one: a source-scoped purge still silently erases those specific
-- day_entries/observations rows for every co-guardian's device with no
-- tombstone to pull - indistinguishable, client-side, from "nothing
-- changed", exactly the propagation gap #522 closed everywhere else.
--
-- Fix: re-emit delete_profile_data() from its only prior definition
-- (20260913013000_deleted_profiles_tombstone_purge.sql) with ONLY the
-- p_source-scoped branch changed. Authority check, source validation, and
-- the full-purge branch are carried forward byte-identical.
--
-- The two content tables move from a real DELETE to the same tombstone
-- shape tombstone_profile_content() uses (payload cleared to match each
-- table's own `*_tombstone_*_check` CHECK exactly; provenance columns
-- `source`/`source_id`/`import_id` are deliberately left untouched, per the
-- #159/#180 precedent that a deleted row must stay recognisable to a future
-- re-import). tombstone_profile_content() itself is not reused directly -
-- it tombstones every LIVE row on the whole profile, not one scoped by
-- source - so this migration writes its own source-scoped UPDATEs inline,
-- matching that function's exact clearing shape.
--
-- Cascade note (unchanged behavior, now via tombstone instead of hard
-- delete): observations are tombstoned by SOURCE first (counted), then
-- day_entries by SOURCE (counted) - tombstoning a day_entries row fires
-- cascade_day_entry_tombstone_to_observations() (an AFTER UPDATE trigger,
-- 20260913012000_cascade_tombstone_lww_guard.sql), which tombstones every
-- STILL-LIVE child observation regardless of ITS OWN source. This mirrors
-- the pre-existing hard-delete behavior exactly: deleting a day_entries row
-- of the target source already cascade-hard-deleted every child
-- observation via its FK, including a different-source one riding the same
-- entry (see the E fixture in delete_profile_data_test.sql: a healthkit day
-- entry carrying an apple_health-sourced observation) - the explicit
-- source-scoped observations statement below only changes the COUNTING
-- semantics for same-source observations, not which rows are ultimately
-- affected. import_jobs stays a hard delete (unchanged) - it is job
-- bookkeeping, never health content or PII, and is hard-deleted even in the
-- full-purge branch (see 20260913013000's "Known scope limits").
--
-- Physical DELETE for these rows is deferred to the future retention sweep
-- (#263), same as the full-purge branch.
--
-- =============================================================================
-- Issue #596: delete_account_data()'s per-table/per-profile tombstones vs.
-- the subsequent auth.admin.deleteUser cascade - investigated, no code
-- change needed.
-- =============================================================================
--
-- The issue's suggested fix ("drop the auth.users FK cascade on
-- deleted_profiles, make it a plain uuid") does not apply to the table as
-- it actually shipped in 20260913013000_deleted_profiles_tombstone_purge.sql:
-- public.deleted_profiles(profile_id text primary key, deleted_at,
-- server_version, guardian_user_ids uuid[]) carries NO foreign key to
-- auth.users or to public.profiles at all, and its RLS policy
-- (`deleted_profiles_select_former_guardians`) checks only the snapshotted
-- `guardian_user_ids` array - no join to profile_guardians or profiles.
-- So a deleted_profiles row, once written, cannot be cascade-removed by
-- auth.admin.deleteUser, and a former co-guardian's read of it does not
-- depend on either the owner's auth.users row or their own profile_guardians
-- row still existing. This is verified by a new pgTAP case (see below) that
-- performs a REAL `auth.users` deletion (tests.delete_supabase_user(), the
-- same raw delete auth.admin.deleteUser performs), not merely a call to
-- delete_account_data() in isolation - account_deletion_test.sql's existing
-- AE2 coverage of Issue #522 never actually removes the auth.users row, so
-- it could not have caught a real FK-cascade gap either way.
--
-- The second part of the issue's ask - "check whether tombstoned
-- day_entries/observations/care_notes/visit_prep_items rows on owned
-- profiles are removed by the same cascade before co-guardians pull them" -
-- is confirmed TRUE by that same new test: public.profiles.user_id
-- references auth.users(id) on delete cascade (unchanged since
-- 20260903014208_initial_sync_schema.sql), so auth.admin.deleteUser hard-
-- deletes the (already-tombstoned) profiles row, and THAT delete cascades
-- again via `profile_id references public.profiles(id) on delete cascade`
-- to hard-delete day_entries/observations/care_notes/visit_prep_items/
-- cycle_overrides for real - exactly as 20260913013000's own "IMPORTANT
-- CAVEAT" section already documented. This is why deleted_profiles is
-- deliberately the client's SOLE cross-account-deletion signal rather than
-- a per-table tombstone diff: that migration's own CONTRACT section
-- instructs a future client-side reader to treat a deleted_profiles row as
-- "delete the local profiles row and every local row scoped to that
-- profile_id, across every locally-cached table ... not merely apply a
-- per-table tombstone diff" precisely because the per-table tombstones for
-- a full account deletion only have the narrow window between
-- delete_account_data()'s commit and the Edge Function's later
-- auth.admin.deleteUser call to reach a co-guardian's pull - likely much
-- narrower than a typical sync interval. Closing that window fully would
-- need either a nullable profiles.user_id with `on delete set null`, or
-- deferring auth.admin.deleteUser - both flagged in 20260913013000 itself
-- as product/schema decisions for a dedicated follow-up, not this bundle.
-- delete_profile_data() (both branches, after this migration) is
-- unaffected by any of this - it never touches auth.users, so its
-- tombstones are durable, not merely a narrow window.
--
-- No table, policy, grant, or column changes for #596 - see the new pgTAP
-- section in account_deletion_test.sql for the regression coverage itself.
--
-- =============================================================================
-- Issue #599 (the Storage-attachment-ordering residual only - the
-- markAppleRevoked fail-closed half already landed in PR #664): no SQL
-- change. supabase/functions/delete-account/index.ts now clears the
-- caller's feedback_tickets.attachment_paths immediately after a successful
-- Storage removal, using the pre-existing owner-scoped UPDATE policy/column
-- grant on feedback_tickets (20260906130000_feedback_tickets.sql) - no new
-- RPC or grant needed. See that file's own header comment for the full
-- fix.

-- ---------------------------------------------------------------------------
-- delete_profile_data(): re-emitted from its prior definition
-- (20260913013000_deleted_profiles_tombstone_purge.sql). Authority check,
-- source validation, and the full-purge branch (p_source is null) are
-- BYTE-IDENTICAL to that version. Only the p_source-scoped branch changes -
-- see this migration's header, "Issue #595".
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
    -- Scoped purge: validate against the union of the two source
    -- vocabularies (day_entries/import_jobs vs observations - see the
    -- original 20260910110000 migration's header) so a typo'd source raises
    -- here rather than silently touching nothing. Matching itself stays
    -- exact per table. The profile and every membership survive this
    -- branch (unchanged).
    if p_source not in
       ('manual', 'clue_import', 'healthkit', 'health_connect',
        'file_import', 'apple_health', 'wearable') then
      raise exception 'unknown source: %', p_source
        using errcode = 'invalid_parameter_value';
    end if;

    v_now := clock_timestamp();

    -- Issue #595: tombstone (payload cleared, server_version bumped) rather
    -- than hard-delete, so co-guardians' devices learn about the removal
    -- via the ordinary incremental pull. Physical delete is left to a
    -- future retention sweep (#263), matching the full-purge branch below.
    -- Mirrors tombstone_profile_content()'s exact clearing shape (each
    -- table's own *_tombstone_*_check CHECK), scoped additionally by
    -- source; provenance columns (source/source_id/import_id) are never
    -- cleared (#159/#180 precedent - a tombstoned row must stay
    -- recognisable to a future re-import).
    --
    -- Observations tombstoned by source BEFORE day_entries, so the
    -- returned count reflects rows this call explicitly tombstoned by
    -- source, rather than rows the day_entries update's own AFTER trigger
    -- (cascade_day_entry_tombstone_to_observations) also tombstones as a
    -- side effect - matching the pre-existing (hard-delete-era) counting
    -- semantics exactly (see this migration's header for the cascade note).
    update public.observations
       set deleted_at = v_now,
           updated_at = greatest(updated_at, v_now),
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
       and source = p_source
       and deleted_at is null;
    get diagnostics v_observations_deleted = row_count;

    update public.day_entries
       set deleted_at = v_now,
           updated_at = greatest(updated_at, v_now),
           flow = 'none',
           note = null,
           tags = '[]'::jsonb,
           pms = false,
           last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
     where profile_id = p_profile_id
       and source = p_source
       and deleted_at is null;
    get diagnostics v_day_entries_deleted = row_count;

    -- Unchanged: import_jobs is job bookkeeping, never health content or
    -- PII, and stays a hard delete here exactly as it does in the
    -- full-purge branch below.
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
  -- per-profile table are still hard-deleted (see 20260913013000's header,
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
  'null) tombstones rather than hard-deletes day_entries, observations, '
  'care_notes, visit_prep_items, and cycle_overrides (payload cleared, '
  'server_version bumped via public.tombstone_profile_content()) and '
  'tombstones the profiles row itself (payload cleared) instead of deleting '
  'it, logging the purge in public.deleted_profiles so every former '
  'guardian''s device can learn the profile is gone via the ordinary '
  'incremental pull. Issue #595: the p_source-scoped branch now ALSO '
  'tombstones (rather than hard-deletes) day_entries/observations matching '
  'that source, for the same propagation reason - the profile and its '
  'guardians still survive that branch, only the matched content rows '
  'change from a hard delete to a tombstone. import_jobs stays a hard '
  'delete on both branches (bookkeeping, no health content/PII). See '
  '20260913013000_deleted_profiles_tombstone_purge.sql''s header for the '
  'full purge-tombstone contract and the tables deliberately left as '
  'immediate hard deletes on the full-purge branch (profile_modes, '
  'profile_guardians, guardian_invitations, ownership_transfers, '
  'prediction_connections, prediction_projections, import_jobs, '
  'notification_preferences, notification_outbox, missed_entry_alert_state, '
  'profile_reminder_windows). SECURITY DEFINER; callable only by the '
  'profile''s ACCEPTED primary_guardian; a nonexistent profile and an '
  'unauthorized caller raise the identical error. The full-purge branch is '
  'not idempotent: a second call finds no accepted primary_guardian '
  'membership left (profile_guardians was hard-deleted by the first call) '
  'and raises. The p_source branch IS idempotent-safe to repeat (a second '
  'call with the same source tombstones nothing further, since the '
  '`deleted_at is null` guard already excludes rows it tombstoned before).';

revoke execute on function public.delete_profile_data(text, text)
  from public, anon;
grant execute on function public.delete_profile_data(text, text)
  to authenticated;
