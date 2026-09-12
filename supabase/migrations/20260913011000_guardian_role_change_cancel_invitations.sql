-- Migration: 20260913011000_guardian_role_change_cancel_invitations.sql
--
-- Issue #519 (P1): update_guardian_role's demotion leaves the demoted
-- guardian's own still-live invitations redeemable.
--
-- Both sibling narrowing operations already close this door: revoke_guardian
-- (20260906240000_account_deletion_notifications.sql:288-306) and
-- accept_ownership_transfer (#4) each cancel every still-live invitation for
-- the profile once a guardian's authority narrows, because a
-- guardian_invitations row carries no invitee identity (only a token hash -
-- see 20260906240000's own comment on this) and so cannot be reliably tied
-- to just the one user being narrowed. update_guardian_role
-- (20260909140004_update_guardian_role.sql) never got the same treatment;
-- its own header even says so ("...and it never touches invitations or
-- transfers").
--
-- Fix: re-emit update_guardian_role (same body as 20260909140004, the only
-- migration to define it) with one addition, placed immediately after the
-- role UPDATE and before the return - when the caller narrows a target away
-- from an invite-capable role (primary_guardian or co_parent) down to
-- caregiver or viewer, cancel every still-live invitation for the profile,
-- using the EXACT same predicate and rationale as revoke_guardian's
-- guardian_invitations update (accepted_at is null and revoked_at is null,
-- no invited_by scoping - see that migration's comment for why "cancel
-- every live invitation for the profile" is the safe default here too).
--
-- primary_guardian is included in the "narrowing away from" check for
-- completeness/defense-in-depth even though update_guardian_role's own
-- AC5 (`p_new_role = 'primary_guardian'` is never assignable) means a
-- target's role realistically can only ever be primary_guardian if there
-- were ever more than one such row on a profile, which nothing else in
-- this schema produces - ownership only ever moves via the dedicated
-- ownership-transfer handshake (20260906180000_ownership_transfer_rpcs.sql).
--
-- No table, policy, grant, or trigger changes - this migration only
-- re-creates the one function body.
--
-- Coverage: supabase/tests/guardian_role_change_test.sql (new case group).

create or replace function public.update_guardian_role(
  p_profile_id text,
  p_target_user_id uuid,
  p_new_role text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target_role text;
  v_invitations_cancelled bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- AC5: primary_guardian is never assignable through this path. Checked
  -- before the generic role validation so the rejection message names the
  -- forbidden grant explicitly.
  if p_new_role = 'primary_guardian' then
    raise exception 'primary_guardian cannot be granted through update_guardian_role'
      using errcode = 'insufficient_privilege';
  end if;

  if p_new_role is null or p_new_role not in ('co_parent', 'caregiver', 'viewer') then
    raise exception 'invalid role: %', coalesce(p_new_role, '<null>')
      using errcode = 'invalid_parameter_value';
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

  -- AC4: no caller may change their own role - in particular, not escalate
  -- it. The primary guardian demoting/promoting themselves is rejected the
  -- same way; ownership moves only through the transfer flow.
  if v_uid = p_target_user_id then
    raise exception 'cannot change your own role'
      using errcode = 'insufficient_privilege';
  end if;

  select role into v_target_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = p_target_user_id
     and status = 'accepted';

  if v_target_role is null then
    raise exception 'target is not an active guardian of this profile'
      using errcode = 'no_data_found';
  end if;

  -- Idempotent no-op: already at the requested role reports back without
  -- writing, so a retried tap never churns updated_at/server_version.
  if v_target_role = p_new_role then
    return jsonb_build_object(
      'profile_id', p_profile_id,
      'role', p_new_role,
      'updated', false
    );
  end if;

  -- Role ladder, consistent with revoke_guardian: the primary guardian may
  -- change anyone's role (to any of the three assignable roles); a
  -- co_parent may move a caregiver/viewer to caregiver/viewer only - never
  -- touching the primary guardian's role, never minting a peer co_parent.
  -- Caregivers and viewers may change nothing.
  if v_caller_role = 'primary_guardian' then
    null;
  elsif v_caller_role = 'co_parent'
    and v_target_role in ('caregiver', 'viewer')
    and p_new_role in ('caregiver', 'viewer') then
    null;
  else
    raise exception 'insufficient permission to change this guardian''s role'
      using errcode = 'insufficient_privilege';
  end if;

  -- AC6: only the membership row's own columns move. day_entries
  -- (logged_by_user_id / last_modified_by_user_id), invitations, transfers,
  -- and notification state are untouched by this statement. updated_at moves
  -- strictly forward so the row re-pulls deterministically; server_version
  -- advances via the existing profile_guardians_set_server_version trigger.
  update public.profile_guardians
     set role = p_new_role,
         updated_at = greatest(updated_at, clock_timestamp())
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  -- Issue #519: narrowing a target away from an invite-capable role
  -- (primary_guardian/co_parent, who can create invitations) down to
  -- caregiver/viewer (who cannot) must close the same door revoke_guardian
  -- already closes on a full revocation - a still-live invitation the
  -- narrowed guardian created before losing that authority stays
  -- redeemable otherwise, handing whoever holds the raw token access under
  -- withdrawn authority. guardian_invitations carries no invitee identity
  -- (only a token hash), so - exactly like revoke_guardian - this cancels
  -- every still-live invitation for the PROFILE, not just ones provably
  -- created by the narrowed user; the cost (an unrelated pending invite
  -- must be re-sent) is the same accepted trade revoke_guardian's own
  -- comment documents.
  if v_target_role in ('primary_guardian', 'co_parent')
     and p_new_role in ('caregiver', 'viewer') then
    update public.guardian_invitations
       set revoked_at = clock_timestamp()
     where profile_id = p_profile_id
       and accepted_at is null
       and revoked_at is null;
    get diagnostics v_invitations_cancelled = row_count;
  end if;

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'role', p_new_role,
    'updated', true,
    'invitations_cancelled', v_invitations_cancelled
  );
end;
$$;

comment on function public.update_guardian_role(text, uuid, text) is
  'Changes an accepted guardian''s role without revoke-and-reinvite '
  '(Issue #127): the primary guardian may change anyone''s role; a '
  'co_parent may move a caregiver/viewer to caregiver/viewer only. '
  'primary_guardian is never grantable here and no caller may change their '
  'own role. Issue #519: narrowing a target away from an invite-capable '
  'role (primary_guardian/co_parent) down to caregiver/viewer cancels every '
  'still-live invitation for the profile - the same guardian_invitations '
  'cleanup revoke_guardian performs on a full revocation, applied here so a '
  'demotion cannot leave a stale invitation redeemable under withdrawn '
  'authority. SECURITY DEFINER - updates profile_guardians.role (and, when '
  'the narrowing condition above applies, guardian_invitations.revoked_at) '
  'only, so entry attribution is untouched and both changes propagate on '
  'the next sync pull via their own set_server_version triggers.';

revoke all on function public.update_guardian_role(text, uuid, text) from public, anon;
grant execute on function public.update_guardian_role(text, uuid, text) to authenticated;
