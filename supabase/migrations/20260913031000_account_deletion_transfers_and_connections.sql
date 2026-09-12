-- Migration: 20260912130000_account_deletion_transfers_and_connections.sql
-- Issue #499: delete_account_data() must explicitly delete ownership_transfers
-- and prediction_connections rows for the caller and report their counts.
--
-- Prior behavior:
-- delete_account_data() deleted rows across 17 tables, but omitted explicit
-- deletes for ownership_transfers (initiated_by = v_uid) and prediction_connections
-- (owner_user_id = v_uid or recipient_user_id = v_uid).
-- Relying solely on the later auth.admin.deleteUser cascade left a vulnerability
-- if subsequent Edge Function steps (Apple revocation or deleteUser) failed
-- or timed out, stranding tokens and connection records.
--
-- Fix:
-- Re-emit delete_account_data() with explicit delete statements for both tables
-- and include 'ownership_transfers' and 'prediction_connections' counts in the
-- returned jsonb document.

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
  v_profile_modes_deleted bigint := 0;
  v_care_notes_deleted bigint := 0;
  v_cycle_overrides_deleted bigint := 0;
  v_visit_prep_items_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_ownership_transfers_deleted bigint := 0;
  v_prediction_connections_deleted bigint := 0;
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
  -- public.rehome_stray_day_entries() - the delete-account Edge
  -- Function calls it a second time, standalone (on its service-role
  -- client, with an explicit p_user_id - #17 P1 round 2 fix), immediately
  -- before auth.admin.deleteUser. This call runs inside a security-definer
  -- function, so it executes as the function owner regardless of
  -- rehome_stray_day_entries()'s own (now-revoked) grants to authenticated.
  v_day_entries_rehomed := public.rehome_stray_day_entries(v_uid);

  -- Issue #240: observations on profiles the caller owns, deleted explicitly
  -- (before the day_entries delete below, which would cascade-remove the
  -- same rows anyway) purely so this function's own returned count reflects
  -- them.
  delete from public.observations
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_observations_deleted = row_count;

  -- Issue #188: profile_modes/cycle_overrides on profiles the caller
  -- owns, deleted explicitly (like observations above) purely so this
  -- function's returned count reflects them -- the profiles delete's own
  -- cascades would remove them regardless. Scoped to owned profiles only:
  -- rows on a *shared* profile are the owning family's metadata, not this
  -- caller's, and survive (the same R7 scoping observations uses).
  delete from public.profile_modes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_profile_modes_deleted = row_count;

  delete from public.cycle_overrides
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_cycle_overrides_deleted = row_count;

  -- Issue #128: care_notes/visit_prep_items on profiles the caller
  -- owns, deleted explicitly (like observations and the mode tables
  -- above) purely so this function's returned count reflects them --
  -- the profiles delete's own cascades would remove them regardless.
  -- Scoped to owned profiles only: rows on a *shared* profile are the
  -- owning family's care content, not this caller's, and survive (the
  -- same R7 scoping observations uses).
  delete from public.care_notes
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_care_notes_deleted = row_count;

  delete from public.visit_prep_items
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_visit_prep_items_deleted = row_count;

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

  -- Issue #499: ownership_transfers initiated by the caller, deleted explicitly
  -- (mirroring guardian_invitations' invited_by = v_uid scoping) so they are
  -- removed immediately and counted rather than surviving if the Edge Function's
  -- subsequent auth.admin.deleteUser call fails or aborts.
  delete from public.ownership_transfers
   where initiated_by = v_uid;
  get diagnostics v_ownership_transfers_deleted = row_count;

  -- Issue #499: prediction_connections where caller is owner or recipient.
  -- Deleted explicitly so lingering tokens and connections are wiped immediately
  -- without depending on auth.admin.deleteUser cascade, and reflected in the count.
  delete from public.prediction_connections
   where owner_user_id = v_uid
      or recipient_user_id = v_uid;
  get diagnostics v_prediction_connections_deleted = row_count;

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
  -- auth.admin.deleteUser call succeeds.
  -- feedback_replies cascades from feedback_tickets (`on delete cascade`),
  -- so no separate delete is needed for replies here.
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
    'profile_modes', v_profile_modes_deleted,
    'cycle_overrides', v_cycle_overrides_deleted,
    'care_notes', v_care_notes_deleted,
    'visit_prep_items', v_visit_prep_items_deleted,
    'guardian_invitations', v_invitations_deleted,
    'ownership_transfers', v_ownership_transfers_deleted,
    'prediction_connections', v_prediction_connections_deleted,
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
  'day_entries, observations (Issue #240), profile_modes and '
  'cycle_overrides (Issue #188), care_notes and visit_prep_items (Issue #128), '
  'guardian_invitations, ownership_transfers and prediction_connections (Issue #499), '
  'profile_guardians, settings, notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, missed_entry_alert_state, feedback_tickets, and import_jobs, '
  'first calling public.rehome_stray_day_entries(auth.uid()) to re-home any day_entries '
  'this caller logged as a caregiver on a profile they do not own.';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
