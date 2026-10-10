-- Migration: 20261010120000_account_deletion_guardian_notes.sql
-- Issue #1831: account deletion now tombstones the departing guardian's own
-- live guardian notes on profiles they merely guard - the same update the
-- revoke path runs (20260918160000_revoke_guardian_notes.sql:153-160), so
-- the stronger action (deleting the account) no longer leaves behind what
-- the weaker one (removing the guardian from the profile) removes. Notes on
-- profiles the caller owns were already tombstoned by the owned-profile
-- loop, through tombstone_profile_content.
--
-- delete_account_data() is re-emitted verbatim from 20260921100000 (its last
-- definition), with the one update added after the owned-profile loop; the
-- function comment and the revoke/grant tail are carried along.

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
  -- Issue #845
  v_account_consents_deleted bigint := 0;
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
  -- Issue #1831: on profiles the caller merely guards, their own live
  -- guardian notes must go the way the revoke path takes them (the same
  -- update as 20260918160000_revoke_guardian_notes.sql:153-160). Without
  -- this, a departing guardian's notes survived on shared profiles,
  -- readable by every remaining guardian and exported to the owner, while
  -- removing the same guardian from a profile removed them.
  update public.guardian_notes
     set deleted_at = v_now,
         updated_at = greatest(updated_at, v_now),
         body = '',
         last_modified_by_user_id = v_uid
   where logged_by_user_id = v_uid
     and deleted_at is null;

  -- Issue #605/LLA-047: uncheck the caller's own checkmark on any still-live
  -- visit_prep_items row (see this migration's Part 3 header above) - items
  -- on profiles the caller owns are already tombstoned by the loop above
  -- and so no longer match `deleted_at is null`.
  update public.visit_prep_items
     set is_checked = false,
         checked_by_user_id = null,
         checked_at = null,
         updated_at = greatest(updated_at, v_now),
         last_modified_by_user_id = v_uid
   where checked_by_user_id = v_uid
     and deleted_at is null;

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

  -- Issue #605/LLA-048: null the provenance FK on every day_entries/
  -- observations row tied to an import_jobs row about to be deleted below,
  -- ourselves, before deleting it - see this migration's Part 2 header
  -- above for why relying on the FK's own ON DELETE SET NULL cascade fails
  -- closed here whenever such a row was last modified by a different
  -- guardian.
  perform set_config('lunarlog.import_cleanup', 'on', true);

  update public.day_entries
     set import_id = null
   where import_id in (select id from public.import_jobs where created_by = v_uid);

  update public.observations
     set import_id = null
   where import_id in (select id from public.import_jobs where created_by = v_uid);

  -- Issue #167: the caller's own import jobs, on any profile.
  delete from public.import_jobs
   where created_by = v_uid;
  get diagnostics v_import_jobs_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  -- Issue #845: the caller's own minimum-age consent record.
  delete from public.account_consents
   where user_id = v_uid;
  get diagnostics v_account_consents_deleted = row_count;

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
    'prediction_connections', v_prediction_connections_deleted,
    'account_consents', v_account_consents_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, observations, profile_modes and cycle_overrides, care_notes '
  'and visit_prep_items, settings, profile_guardians, guardian_invitations, '
  'ownership_transfers, prediction_connections, notification_preferences, '
  'push_devices, notification_outbox, profile_reminder_windows, '
  'missed_entry_alert_state, feedback_tickets, and account_consents (Issue '
  '#845''s minimum-age consent record), first calling '
  'public.rehome_stray_day_entries(auth.uid()). Issue #522: day_entries, '
  'observations, care_notes, visit_prep_items, and cycle_overrides on every '
  'OWNED profile are now tombstoned rather than hard-deleted, and each owned '
  'profile itself is tombstoned and logged in public.deleted_profiles instead '
  'of physically deleted. Issue #499: explicitly deletes ownership_transfers '
  'initiated by the caller, and prediction_connections where the caller is '
  'owner or recipient, returning both counts. Issue #605/LLA-047: also '
  'unchecks any still-live visit_prep_items row the caller is the recorded '
  'checker of (on a profile they do not own), so the later '
  'auth.admin.deleteUser FK cascade never has a checked-but-uncheckable row '
  'left to trip visit_prep_items_checked_stamp_check. Issue #605/LLA-048: '
  'also nulls day_entries.import_id/observations.import_id for rows tied to '
  'an import_jobs row it is about to delete (under the transaction-local '
  'lunarlog.import_cleanup bypass), so that delete never trips '
  'enforce_day_entry_attribution()/enforce_observation_attribution() on a '
  'row a different guardian has since edited.';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
