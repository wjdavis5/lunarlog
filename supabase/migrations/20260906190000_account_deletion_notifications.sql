-- Migration: 20260906190000_account_deletion_notifications.sql
-- Issue #5, Unit U4: extends account deletion and guardian revocation so
-- neither leaves a row behind in the four tables this feature added
-- (R20), and so revocation stops a guardian's alerts "immediately" (R5),
-- not merely "the next time something reads profile_guardians.status".
--
-- Per the repo's standing rule, this is a new migration file only; no
-- merged migration is edited in place -- both functions below are
-- `create or replace`, carrying their prior bodies verbatim plus the new
-- steps, mirroring how 20260906120000_account_deletion_final_rehome.sql and
-- 20260905090000_close_guardian_revocation_bypass.sql each layered onto an
-- earlier version of the same functions.
--
-- Round-2 review #8: this file's own `missed_entry_alert_state` (added by
-- 20260906180000_reminder_windows_and_cron.sql, review #8) was itself never
-- wired into either function below when first written -- neither the
-- profile nor the revoked guardian's auth.users row is deleted by a plain
-- revocation, so the stale `last_enqueued_for` marker survives it. A
-- guardian who is revoked and later re-invited, with the same
-- estimated_next_start still published, would be silently skipped by the
-- scan's `is distinct from` dedupe gate -- re-creating exactly the
-- co-guardian suppression bug review #8 was filed to remove. It is also
-- residual data about a minor's profile retained for someone whose access
-- was revoked (R5). Both `create or replace`s below add the missing delete.

-- ---------------------------------------------------------------------------
-- delete_account_data(): add the caller's own notification_preferences,
-- push_devices, and notification_outbox rows (any profile), plus
-- profile_reminder_windows rows for profiles the caller *owns* (mirroring
-- the day_entries owner-vs-caregiver distinction the account-deletion
-- functions already draw -- a co-guardian's preference row on a profile the
-- caller merely guards is not the caller's row and must survive).
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
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_deleted bigint := 0;
  v_settings_deleted bigint := 0;
  v_notification_preferences_deleted bigint := 0;
  v_push_devices_deleted bigint := 0;
  v_notification_outbox_deleted bigint := 0;
  v_reminder_windows_deleted bigint := 0;
  v_missed_entry_alert_state_deleted bigint := 0;
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
    'missed_entry_alert_state', v_missed_entry_alert_state_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, settings, profile_guardians, guardian_invitations, '
  'notification_preferences, push_devices, notification_outbox, '
  'profile_reminder_windows, and missed_entry_alert_state (Issue #5, U4; '
  'R20; the last added by round-2 review #8), first calling '
  'public.rehome_stray_day_entries(auth.uid()) to re-home any day_entries '
  'this caller logged as a caregiver on a profile they do not own, so the '
  'auth.users on delete cascade the Edge Function triggers afterwards '
  'cannot reach them (#17 P0 fix). That call runs as this function''s own '
  'security-definer owner, so it succeeds regardless of '
  'rehome_stray_day_entries()''s own (revoked, #17 P1 round 2 fix) grants. '
  'Takes no parameters itself - the caller is always the subject, so no '
  'other account can be named in the call. Called by the delete-account '
  'Edge Function before it revokes Apple and deletes the auth.users row '
  '(#17 KTD1/KTD4); that same function calls rehome_stray_day_entries() a '
  'second time, standalone, on its service-role client with an explicit '
  'p_user_id, immediately before the auth.users deletion (#17 P1 item 5; '
  'round 2 fix).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;

-- ---------------------------------------------------------------------------
-- revoke_guardian(): stop a revoked guardian's alerts for this profile
-- immediately (R5) rather than merely closing off future reads. Their
-- preference row for this profile is deleted outright (not merely
-- orphaned by the now-closed RLS read) and any of their unsent
-- notification_outbox rows for this profile are removed so nothing still
-- in flight reaches them after this call returns.
-- ---------------------------------------------------------------------------

create or replace function public.revoke_guardian(
  p_profile_id text,
  p_target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target_role text;
  v_now timestamptz;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select role into v_caller_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = v_uid
     and status = 'accepted';

  if v_caller_role is null then
    raise exception 'caller is not a guardian of this profile'
      using errcode = 'insufficient_privilege';
  end if;

  select role into v_target_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = p_target_user_id
     and status = 'accepted';

  if v_target_role is null then
    -- Already not an active guardian
    return true;
  end if;

  -- Self-leave is always allowed unless caller is the sole primary_guardian
  if v_uid = p_target_user_id then
    if v_caller_role = 'primary_guardian' and (
      select count(*) from public.profile_guardians
       where profile_id = p_profile_id and role = 'primary_guardian' and status = 'accepted'
    ) <= 1 then
      raise exception 'the sole primary guardian cannot leave the profile'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  else
    -- Revoking another user:
    -- primary_guardian can revoke anyone
    -- co_parent can revoke caregiver and viewer only
    if v_caller_role = 'primary_guardian' then
      null;
    elsif v_caller_role = 'co_parent' and v_target_role in ('caregiver', 'viewer') then
      null;
    else
      raise exception 'insufficient permission to revoke this guardian'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  v_now := clock_timestamp();

  -- #81: revocation must close every door, not just the one the revoked
  -- user already walked through. guardian_invitations binds to a token
  -- (see 20260904010000_multi_guardian_schema.sql) rather than a recipient
  -- identity - there is no invitee column, only accepted_by, which stays
  -- null until redemption - so a live, unaccepted invitation cannot be
  -- reliably tied to p_target_user_id before it is redeemed. The safe
  -- default is to cancel every still-live invitation for the profile
  -- whenever any revocation happens on it, not just one provably addressed
  -- to the revoked user; the cost is that an unrelated pending invitation
  -- (e.g. to a caregiver the target never touched) also gets canceled and
  -- must be re-sent, which is an acceptable trade for closing the bypass.
  --
  -- This update runs before the profile_guardians update below (not after)
  -- so the lock order here - guardian_invitations row(s), then the
  -- profile_guardians row - matches accept_guardian_invitation's own order
  -- and the two RPCs cannot deadlock against each other.
  update public.guardian_invitations
     set revoked_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and revoked_at is null;

  update public.profile_guardians
     set status = 'revoked',
         updated_at = v_now,
         revoked_at = v_now
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  -- Issue #5, U4 (R5): stop the revoked guardian's alerts for this profile
  -- immediately. The preference row's RLS read already closed the moment
  -- status flipped above, but deleting it (rather than leaving it orphaned)
  -- is what R5 means by "immediately" - and any of their pending, unsent
  -- alerts for this profile are removed too, so nothing already enqueued
  -- reaches them after this call returns. A already-sent alert cannot be
  -- recalled (sent_at is not null), which is unavoidable and out of scope.
  delete from public.notification_preferences
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  delete from public.notification_outbox
   where profile_id = p_profile_id
     and recipient_user_id = p_target_user_id
     and sent_at is null;

  -- Round-2 review #8: also drop the revoked guardian's missed-entry dedupe
  -- marker for this profile. Without this, a guardian who is revoked and
  -- later re-invited -- with the same estimated_next_start still published
  -- on profile_reminder_windows -- is silently skipped by the scan's
  -- `last_enqueued_for is distinct from estimated_next_start` gate,
  -- re-creating exactly the co-guardian suppression bug review #8 was filed
  -- to remove. It is also residual data about a minor's profile retained
  -- for someone whose access was just revoked (R5).
  delete from public.missed_entry_alert_state
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  return true;
end;
$$;

comment on function public.revoke_guardian(text, uuid) is
  'Revokes p_target_user_id''s guardianship of p_profile_id (see prior '
  'migrations for the #81/#82 fixes), and, as of Issue #5 U4 (R5), also '
  'deletes their notification_preferences row for this profile, any of '
  'their unsent notification_outbox rows for it, and their '
  'missed_entry_alert_state marker for it (round-2 review #8 -- otherwise a '
  'revoked-then-re-invited guardian is silently skipped by the missed-entry '
  'scan''s dedupe gate for the still-published window), so caregiver alerts '
  'stop immediately rather than merely becoming unreadable.';

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;
