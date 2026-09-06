-- Migration: 20260905100000_account_deletion.sql
-- Implements Issue #17 (Unit U1): the row-deletion half of in-app account
-- deletion. `public.delete_account_data()` removes every row the calling
-- user owns across `profiles`, `day_entries`, `settings`, `profile_guardians`
-- and `guardian_invitations` (R4). The `auth.users` row itself, and Apple
-- token revocation, are handled by the `delete-account` Edge Function (U2),
-- which calls this RPC first, then Apple, then `auth.admin.deleteUser` last
-- (#17 KTD4) - this function never touches `auth.users`.
--
-- Per the repo's standing rule, this is a new migration file only; no merged
-- migration is edited in place.
--
-- Ownership per table (#17 U1 step 3):
--   * day_entries: scoped to profiles the caller *owns* (public.profiles.user_id
--     = caller), not to day_entries.user_id. A caregiver's own inserted rows
--     on someone else's shared profile must survive that caregiver's account
--     deletion (R7, AE3) - only their profile_guardians membership and their
--     attribution on those rows (logged_by_user_id / last_modified_by_user_id,
--     both `references auth.users(id) on delete set null`) go away, and only
--     once the Edge Function deletes the auth.users row afterwards.
--   * guardian_invitations: scoped to `invited_by` (the caller created it,
--     for any profile - their own or one they co-parent).
--   * profile_guardians: scoped to `user_id` (the caller's own membership row,
--     revoked ones included).
--   * profiles: scoped to `user_id` (the caller's own profiles). Deleting one
--     cascades its remaining day_entries, guardian_invitations and
--     profile_guardians rows via the existing `on delete cascade` FKs - other
--     guardians' membership and other people's invitations for that specific
--     profile included. That is intended for an owner (R7 only protects the
--     reverse direction - see Q3 in the plan) and unreachable for a
--     non-owner, since a non-owner holds no `profiles` row to delete.
--   * settings: scoped to `user_id`.
--
-- The explicit deletes mirror what the FK cascades already do (KTD2): this
-- makes the cascade provable by pgTAP (account_deletion_test.sql) instead of
-- depending on cascade configuration remaining correct, and the cascades
-- remain a second line of defence rather than the mechanism.

create or replace function public.delete_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day_entries_deleted bigint := 0;
  v_invitations_deleted bigint := 0;
  v_guardians_deleted bigint := 0;
  v_profiles_deleted bigint := 0;
  v_settings_deleted bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- day_entries on profiles the caller owns. Deliberately not
  -- `day_entries.user_id = v_uid`: that column is stamped from auth.uid() at
  -- insert time (see 20260903014208_initial_sync_schema.sql), so a
  -- caregiver's own device syncing an entry for someone else's shared
  -- profile sets it to the caregiver, not the profile owner. Deleting by
  -- that column would destroy another family's data out from under them
  -- when the caregiver's account is removed - exactly what R7 forbids.
  delete from public.day_entries
   where profile_id in (
     select id from public.profiles where user_id = v_uid
   );
  get diagnostics v_day_entries_deleted = row_count;

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

  -- The caller's own profiles. Cascades any day_entries,
  -- guardian_invitations, and profile_guardians rows still tied to these
  -- specific profiles (e.g. a co-parent's membership, or an invitation
  -- someone else sent for it) - intended for an owner (R7).
  delete from public.profiles
   where user_id = v_uid;
  get diagnostics v_profiles_deleted = row_count;

  delete from public.settings
   where user_id = v_uid;
  get diagnostics v_settings_deleted = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries_deleted,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, settings, profile_guardians and guardian_invitations. Takes '
  'no parameters - the caller is always the subject, so no other account can '
  'be named in the call. Called by the delete-account Edge Function before '
  'it revokes Apple and deletes the auth.users row (#17 KTD1/KTD4).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
