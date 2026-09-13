-- Migration: 20260913022000_account_deletion_transfers_and_connections.sql
-- Issue #499 (P2): explicitly delete ownership_transfers and
-- prediction_connections in delete_account_data().
--
-- In delete_account_data(), every table carrying caller-owned rows is
-- explicitly deleted and counted before the delete-account Edge Function
-- proceeds to revoke Apple and call auth.admin.deleteUser.
--
-- However, two tables were omitted from explicit deletion inside
-- delete_account_data():
--   1. `ownership_transfers` (where `initiated_by = v_uid`)
--   2. `prediction_connections` (where `owner_user_id = v_uid or recipient_user_id = v_uid`)
--
-- Because #522 tombstones profiles (deleted_at = v_now) instead of physically
-- deleting them, the foreign-key `on delete cascade` from `profiles(id)` does
-- not fire during delete_account_data(). Leaving them relies solely on the
-- final `auth.admin.deleteUser` call, which can fail or abort (e.g. Apple
-- revocation timeout). In that partial failure state, lingering tokens and
-- recipient records remained attached to the wiped account.
--
-- This migration create or replaces public.delete_account_data() to explicitly
-- delete from public.ownership_transfers and public.prediction_connections,
-- and includes both counts in the returned jsonb document.

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
  v_ownership_transfers_deleted bigint := 0;
  v_prediction_connections_deleted bigint := 0;
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
  -- profile_guardians row.
  v_now := clock_timestamp();
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

  -- Issue #188: profile_modes has no tombstone column and stays a hard delete,
  -- scoped to owned profiles.
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

  -- Issue #499: explicitly delete ownership_transfers initiated by the caller.
  delete from public.ownership_transfers
   where initiated_by = v_uid;
  get diagnostics v_ownership_transfers_deleted = row_count;

  -- Issue #499: explicitly delete prediction_connections where the caller is
  -- either the owner or the recipient.
  delete from public.prediction_connections
   where owner_user_id = v_uid
      or recipient_user_id = v_uid;
  get diagnostics v_prediction_connections_deleted = row_count;

  -- The caller's own guardian memberships. Safe only now that every owned
  -- profile has already been tombstoned above.
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
    'import_jobs', v_import_jobs_deleted,
    'ownership_transfers', v_ownership_transfers_deleted,
    'prediction_connections', v_prediction_connections_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations, profile_modes and cycle_overrides, care_notes '
  'and visit_prep_items, settings, profile_guardians, guardian_invitations, '
  'ownership_transfers, prediction_connections, notification_preferences, '
  'push_devices, notification_outbox, profile_reminder_windows, '
  'missed_entry_alert_state, and feedback_tickets, first calling '
  'public.rehome_stray_day_entries(auth.uid()). Issue #522: day_entries, '
  'observations, care_notes, visit_prep_items, and cycle_overrides on every '
  'OWNED profile are now tombstoned rather than hard-deleted, and each owned '
  'profile itself is tombstoned and logged in public.deleted_profiles instead '
  'of physically deleted. Issue #499: explicitly deletes ownership_transfers '
  'initiated by the caller, and prediction_connections where the caller is '
  'owner or recipient, returning both counts.';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
