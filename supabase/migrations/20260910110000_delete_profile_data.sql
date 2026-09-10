-- Migration: 20260910110000_delete_profile_data.sql
--
-- Issue #264 (P2, epic: Privacy & Compliance): delete_profile_data() - a
-- hard purge of ONE profile, as distinct from delete_account_data()'s
-- all-or-nothing whole-account wipe.
--
-- The gap: a profile can only ever be tombstoned. sync_push's profile
-- branch sets `deleted_at` (20260909210000_profile_transferred_to_user_id.sql,
-- the latest re-emission, carries the same branch every version since
-- 20260906200000 had), there is no DELETE grant on public.profiles for
-- `authenticated` (20260903014208_initial_sync_schema.sql), and the only
-- hard-delete RPC is delete_account_data(), which is all-or-nothing on the
-- caller's entire account. A parent who wants one child's record gone -
-- after an ownership transfer, on the child's request, or because it was
-- created in error - had no path short of deleting their whole account,
-- and the tombstoned profile and its tombstoned entries stayed on the
-- server for every guardian indefinitely.
--
-- What this migration adds:
--
--   1. public.delete_profile_data(p_profile_id text, p_source text default null)
--      - SECURITY DEFINER, `authenticated`-only (revoked from public/anon),
--      restricted to the profile's accepted `primary_guardian` - the same
--      role rung that already governs tombstone-deletion in sync_push
--      ("only primary_guardian can delete or archive profile"). A
--      nonexistent profile and an unauthorized caller raise the identical
--      error (the revoke_guardian_invitation enumeration-safety precedent).
--
--   2. p_source null (the default): the hard purge. Every per-profile table
--      is deleted EXPLICITLY, with a count, before the profiles row itself
--      goes - exactly the delete_account_data() pattern (the explicit
--      deletes exist so the returned counts reflect the purge; the FK
--      cascades from profiles would remove the same rows regardless). The
--      explicit list, mapped to the landed tables:
--
--        day_entries                (20260903014208) - the entries
--        observations               (20260908160000, #240/#188) - child of
--                                   day_entries AND of profiles; deleted
--                                   before day_entries so its own count is
--                                   accurate (the day_entries delete would
--                                   cascade the same rows after it)
--        profile_modes              (20260909000000, #188) - the mode row
--        cycle_overrides            (20260909000000, #188)
--        care_notes                 (20260909141503, #128)
--        visit_prep_items           (20260909141503, #128)
--        profile_reminder_windows   (20260906230000, #5)
--        missed_entry_alert_state   (20260906230000, #5) - every guardian's
--                                   marker for this profile
--        notification_preferences   (20260906210000, #5) - every guardian's
--                                   row for this profile
--        notification_outbox        (20260906220000, #5) - pending alerts
--                                   for this profile, for every recipient
--        guardian_invitations       (20260904010000) - outstanding
--                                   invitations for this profile, whoever
--                                   sent them
--        profile_guardians          (20260904010000) - every membership,
--                                   including co-guardians'. This is the
--                                   deliberate, explicit behavior the issue
--                                   calls out: a co-guardian's own entries
--                                   on this profile die too - once the
--                                   profile is gone there is nothing left
--                                   for those rows to attach to.
--        import_jobs                (20260908190000, #167)
--        ownership_transfers        (20260906170000, #4) - live or expired
--        prediction_connections     (20260909200000, #151)
--        prediction_projections     (20260909200000, #151)
--        sync_signals               (20260905100000, #77) - no explicit
--                                   delete: the row is counted before the
--                                   profiles delete, and removed by the
--                                   existence check in touch_sync_signal()
--                                   when that delete fires its AFTER trigger
--                                   (realtime_publication_test.sql proves
--                                   the trigger's delete-not-upsert branch)
--        profiles                   - the row itself, last
--
--      Per-user tables are deliberately untouched: settings,
--      push_devices, feedback_tickets, and this profile's rows are not the
--      caller's account. delete_account_data() is untouched by this
--      migration (the #17-era RPC keeps its exact shape).
--
--   3. p_source non-null: the scoped purge the issue adds "so 'delete my
--      imported Health data' is a single call" (the #159 provenance columns
--      this depends on landed in 20260908170000_import_provenance.sql).
--      The profile and every guardian row SURVIVE; only rows carrying that
--      exact `source` value on the profile go:
--
--        observations where source = p_source (counted first, for the same
--                     cascade-ordering reason as above)
--        day_entries  where source = p_source (their remaining observations
--                     cascade with them regardless of the observations'
--                     own source)
--        import_jobs  where source = p_source (the audit rows that produced
--                     them - no health content, but they are rows *of that
--                     source* on the profile, which is exactly what the AC
--                     scopes)
--
--      Matching is exact per table, with no cross-table translation:
--      day_entries.source (20260908170000) and import_jobs.source
--      (20260908190000) share the closed set manual/clue_import/healthkit/
--      health_connect/file_import, while observations.source
--      (20260908160000) uses manual/apple_health/health_connect/wearable/
--      clue_import - 'healthkit' is a real day_entries value that cannot
--      appear on observations, and 'apple_health' is the reverse. Rather
--      than silently mapping one vocabulary onto the other (implicit
--      translation is impossible to reason about at 2am), the function
--      accepts the UNION of both closed sets and matches each table's own
--      column exactly. A HealthKit import kills its day_entries and every
--      observation attached to them via the cascade; an 'apple_health'
--      call exists for observations-purged-independently shapes. An
--      out-of-set value raises invalid_parameter_value and touches nothing.
--
--   4. Return shape: a flat jsonb of per-table deleted-row counts, the
--      delete_account_data() shape. The base purge names every table it
--      empties, including 'profiles' = 1 and 'sync_signals'; the p_source
--      variant names only the three tables it can touch (the profile
--      survives, so there is no 'profiles' key to misread). Unlike
--      delete_account_data(), this RPC is NOT idempotent - the second call
--      finds no profile (or no accepted primary_guardian membership) and
--      raises, which the pgTAP suite asserts explicitly.
--
-- Security posture (unchanged by this migration):
--   * RLS is never weakened. No new table policy, no new table grant, no
--     new column grant. The function is SECURITY DEFINER for the same
--     reason delete_account_data() is: an authenticated caller has no
--     DELETE grant on public.profiles at all (by design - the client's
--     only tombstone path is sync_push), and the purge must run as the
--     function's owner.
--   * `revoke execute ... from public, anon; grant execute ... to
--     authenticated` - the delete_account_data() grant shape, asserted in
--     the pgTAP suite.
--   * Authority is checked from the caller's own JWT (auth.uid()) against
--     profile_guardians; the p_profile_id parameter can never name a
--     profile the caller is not the accepted primary_guardian of.

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
  v_sync_signals_deleted bigint := 0;
  v_profiles_deleted bigint := 0;
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
    -- vocabularies (day_entries/import_jobs vs observations - see this
    -- migration's header) so a typo'd source raises here rather than
    -- silently deleting nothing. Matching itself stays exact per table.
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

  -- Full purge: every per-profile table, explicitly and counted, then the
  -- profile row itself. Order matters only for the counts (observations
  -- before day_entries, whose delete would otherwise cascade them); the
  -- FK cascades from the final profiles delete would remove whatever this
  -- list somehow missed - the list exists so the counts are exact.
  delete from public.observations
   where profile_id = p_profile_id;
  get diagnostics v_observations_deleted = row_count;

  delete from public.day_entries
   where profile_id = p_profile_id;
  get diagnostics v_day_entries_deleted = row_count;

  delete from public.profile_modes
   where profile_id = p_profile_id;
  get diagnostics v_profile_modes_deleted = row_count;

  delete from public.cycle_overrides
   where profile_id = p_profile_id;
  get diagnostics v_cycle_overrides_deleted = row_count;

  delete from public.care_notes
   where profile_id = p_profile_id;
  get diagnostics v_care_notes_deleted = row_count;

  delete from public.visit_prep_items
   where profile_id = p_profile_id;
  get diagnostics v_visit_prep_items_deleted = row_count;

  -- Issue #5 tables: every guardian's rows for THIS profile go - the
  -- profile is gone, so nothing can alert anyone about it afterwards.
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

  -- Every membership on this profile, including the co-guardians'. The
  -- issue calls this out as deliberate: once the profile is gone there is
  -- nothing left for their memberships (or their own entries on it,
  -- already deleted above) to attach to.
  delete from public.profile_guardians
   where profile_id = p_profile_id;
  get diagnostics v_profile_guardians_deleted = row_count;

  delete from public.import_jobs
   where profile_id = p_profile_id;
  get diagnostics v_import_jobs_deleted = row_count;

  -- Issue #4: live, expired, accepted, or cancelled - all of them are
  -- rows about a profile that will no longer exist.
  delete from public.ownership_transfers
   where profile_id = p_profile_id;
  get diagnostics v_ownership_transfers_deleted = row_count;

  -- Issue #151. The projection row goes BEFORE the connection rows:
  -- deleting a connection fires prediction_connections_projection_gc(),
  -- whose own AFTER DELETE hook would remove the projection row first and
  -- leave this function's returned count at zero (the same
  -- count-before-cascade reason observations is deleted before
  -- day_entries above).
  delete from public.prediction_projections
   where profile_id = p_profile_id;
  get diagnostics v_prediction_projections_deleted = row_count;

  delete from public.prediction_connections
   where profile_id = p_profile_id;
  get diagnostics v_prediction_connections_deleted = row_count;

  -- Counted, not deleted: the profiles delete's AFTER trigger runs
  -- touch_sync_signal(), whose existence check removes the row (Issue
  -- #77). Counting it here keeps the returned document complete without
  -- racing that trigger.
  select count(*) into v_sync_signals_deleted
    from public.sync_signals
   where profile_id = p_profile_id;

  delete from public.profiles
   where id = p_profile_id;
  get diagnostics v_profiles_deleted = row_count;

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
    'sync_signals', v_sync_signals_deleted,
    'profiles', v_profiles_deleted
  );
end;
$$;

comment on function public.delete_profile_data(text, text) is
  'Hard-deletes ONE profile and, via its per-profile tables (Issue #264), '
  'everything attached to it - day_entries, observations, profile_modes, '
  'cycle_overrides, care_notes, visit_prep_items, profile_reminder_windows, '
  'missed_entry_alert_state, notification_preferences, notification_outbox, '
  'guardian_invitations, profile_guardians (co-guardians'' memberships and '
  'their own entries on this profile included, deliberately), import_jobs, '
  'ownership_transfers, prediction_connections, prediction_projections, '
  'and the profile''s sync_signals row (via touch_sync_signal()''s '
  'existence check) - returning per-table deleted-row counts in the '
  'delete_account_data() shape. SECURITY DEFINER because an authenticated '
  'caller holds no DELETE grant on public.profiles (the tombstone path is '
  'sync_push); RLS and every existing grant are untouched. Callable only '
  'by the profile''s ACCEPTED primary_guardian (the sync_push '
  'delete/archive rung); a nonexistent profile and an unauthorized caller '
  'raise the identical error. With p_source set (Issue #159 provenance), '
  'only rows carrying that exact source value on the profile are deleted '
  '(day_entries, observations, import_jobs - profile and guardians '
  'survive); the accepted set is the union of day_entries.source''s and '
  'observations.source''s closed vocabularies, matched exactly per table. '
  'Not idempotent: a second call on a purged profile raises. Per-user '
  'tables (settings, push_devices, feedback_tickets) and '
  'delete_account_data() are untouched by this path.';

revoke execute on function public.delete_profile_data(text, text)
  from public, anon;
grant execute on function public.delete_profile_data(text, text)
  to authenticated;
