-- Migration: 20260909140004_update_guardian_role.sql
-- Implements Issue #127: change an existing guardian's role without
-- revoke-and-reinvite.
--
-- A guardian's role is fixed at invitation time today; the only way to move
-- someone between roles is to revoke them and send a fresh invitation they
-- must redeem again. This adds `public.update_guardian_role`, a SECURITY
-- DEFINER RPC following the pattern already established by `revoke_guardian`
-- (20260904020000_sync_push_and_invitations.sql, latest body in
-- 20260906240000_account_deletion_notifications.sql) and
-- `revoke_guardian_invitation`
-- (20260906190000_revoke_guardian_invitation.sql): the role ladder mirrors
-- the revoke ladder (the primary guardian may change anyone's role; a
-- co_parent may change only caregiver/viewer roles to caregiver/viewer),
-- and the grant posture matches (revoked from public/anon, granted to
-- authenticated only).
--
-- Design constraints from the issue, each enforced server-side:
-- - `primary_guardian` is NEVER assignable through this path. Transferring
--   primary ownership is the deliberately heavyweight, handshake-gated
--   ownership-transfer flow (20260906180000_ownership_transfer_rpcs.sql);
--   this RPC must not become a back door around it, so a `primary_guardian`
--   target role is rejected with insufficient_privilege.
-- - No caller may change their own role - in particular, not escalate it.
--   Self-change is rejected even for the primary guardian.
-- - Narrowing never orphans anything: this RPC updates only
--   `profile_guardians.role` (plus `updated_at`, which the existing
--   `profile_guardians_set_server_version` trigger turns into a
--   `server_version` bump). It never touches `day_entries`, so entries the
--   guardian previously logged keep their attribution unchanged, and it
--   never touches invitations or transfers.
-- - Propagation to the affected device rides the existing sync pull:
--   `profile_guardians` pages carry `role`, and the `server_version` bump
--   above makes the changed row land on the target's next pull - including
--   a narrowing to `viewer`, which arrives as a *known* role the client's
--   read-only enforcement (`GuardianRole.canLog` / `readOnlyReason`,
--   fail-open only for truly unknown roles) already handles. No new sync
--   shape, no new RLS policy, and no widening of the direct column grant
--   (`update (display_name, updated_at)` stays exactly as it is - role is
--   writable only through SECURITY DEFINER RPCs, per KTD15).
--
-- Per "do not edit a merged migration in place", this file is purely
-- additive: one new function plus its grants. `revoke_guardian` is left
-- untouched.

-- ---------------------------------------------------------------------------
-- 1. update_guardian_role RPC
-- ---------------------------------------------------------------------------

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

  return jsonb_build_object(
    'profile_id', p_profile_id,
    'role', p_new_role,
    'updated', true
  );
end;
$$;

comment on function public.update_guardian_role(text, uuid, text) is
  'Changes an accepted guardian''s role without revoke-and-reinvite '
  '(Issue #127): the primary guardian may change anyone''s role; a '
  'co_parent may move a caregiver/viewer to caregiver/viewer only. '
  'primary_guardian is never grantable here and no caller may change their '
  'own role. SECURITY DEFINER - updates profile_guardians.role only, so '
  'entry attribution is untouched and the new role propagates on the next '
  'sync pull via the set_server_version trigger.';

revoke all on function public.update_guardian_role(text, uuid, text) from public, anon;
grant execute on function public.update_guardian_role(text, uuid, text) to authenticated;
