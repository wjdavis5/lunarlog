-- Migration: 20260908130000_account_deletion_feedback_tickets.sql
-- (renamed from an original `20260908120000_` prefix: PR #277 independently
-- used that same timestamp for `20260908120000_profile_care_modes.sql`
-- (issue #131), merged after this one branched - the two touch disjoint
-- functions and have no interaction, but the later timestamp keeps
-- ordering unambiguous.)
-- Issue #243 (D-25): delete_account_data() never mentioned
-- public.feedback_tickets. Deletion "worked" only as a side effect of
-- feedback_tickets.user_id's `on delete cascade` to auth.users, once the
-- delete-account Edge Function's final auth.admin.deleteUser call ran - a
-- step that Function's own header comment documents as able to fail (Apple
-- revocation failure, a delete_user_failed error), in which case the
-- tickets survive with no other cleanup path. This migration deletes them
-- explicitly, as its own step, alongside every other table this function
-- already handles the same way - so ticket cleanup no longer depends on a
-- later, separately-failable step ever succeeding. feedback_replies has no
-- direct FK to auth.users (only to feedback_tickets, on delete cascade -
-- see 20260906130000_feedback_tickets.sql), so deleting the ticket rows
-- here is sufficient; no separate delete is needed for replies.
--
-- Per the repo's standing rule, this is a new migration file only; no
-- merged migration is edited in place - delete_account_data() below is
-- `create or replace`, carrying its prior body (from
-- 20260906240000_account_deletion_notifications.sql, the latest version on
-- main) verbatim plus this one new step.
--
-- Companion fix (Issue #243, D-24; reordered by the round 2 fix, 2026-09-08):
-- the delete-account Edge Function itself
-- (supabase/functions/delete-account/index.ts) now also removes the
-- caller's objects from the feedback-attachments Storage bucket - before
-- this function runs at all, not merely before auth.admin.deleteUser -
-- failing the whole request closed on any storage error rather than
-- leaving orphaned attachments behind. That half of the fix lives in the
-- Edge Function, not in SQL - a bucket object isn't reachable from a
-- plpgsql function, and storage.objects.owner is `on delete set null`
-- rather than a hard FK (see this issue's Context), so there is no cascade
-- for this migration to route around the way there is for
-- feedback_tickets.

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

  -- The caller's own profiles. Cascades any day_entries,
  -- guardian_invitations, and profile_guardians rows still tied to these
  -- specific profiles (e.g. a co-parent's membership, or an invitation
  -- someone else sent for it) - intended for an owner (R7). Also cascades
  -- any remaining notification_preferences/notification_outbox/
  -- profile_reminder_windows rows scoped to these profiles (Issue #5) -
  -- e.g. a co-guardian's own preference row for a profile the caller
  -- owned, which is correct: once the profile itself is gone there is
  -- nothing left to alert anyone about.
  delete from public.profiles
   where user_id = v_uid;
  get diagnostics v_profiles_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'day_entries_rehomed', v_day_entries_rehomed,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted,
    'notification_preferences', v_notification_preferences_deleted,
    'push_devices', v_push_devices_deleted,
    'notification_outbox', v_notification_outbox_deleted,
    'profile_reminder_windows', v_reminder_windows_deleted,
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted,
    'feedback_tickets', v_feedback_tickets_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, settings, profile_guardians, guardian_invitations, '
  'notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, missed_entry_alert_state, and (Issue #243, '
  'D-25) feedback_tickets (feedback_replies cascades from feedback_tickets, '
  'so no separate delete is needed for those), first calling '
  'public.rehome_stray_day_entries(auth.uid()) to re-home any day_entries '
  'this caller logged as a caregiver on a profile they do not own, so the '
  'auth.users on delete cascade the Edge Function triggers afterwards '
  'cannot reach them (#17 P0 fix). That call runs as this function''s own '
  'security-definer owner, so it succeeds regardless of '
  'rehome_stray_day_entries()''s own (revoked, #17 P1 round 2 fix) grants. '
  'Takes no parameters itself - the caller is always the subject, so no '
  'other account can be named in the call. Called by the delete-account '
  'Edge Function only after it has already removed the caller''s '
  'feedback-attachments Storage objects (Issue #243, D-24; reordered ahead '
  'of this call by the round 2 fix, 2026-09-08 - a separate fail-closed '
  'step in the Edge Function itself, since a Storage object isn''t '
  'reachable from this function); that same function then revokes Apple '
  'and deletes the auth.users row (#17 KTD1/KTD4). It also calls '
  'rehome_stray_day_entries() a '
  'second time, standalone, on its service-role client with an explicit '
  'p_user_id, immediately before the auth.users deletion (#17 P1 item 5; '
  'round 2 fix).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
