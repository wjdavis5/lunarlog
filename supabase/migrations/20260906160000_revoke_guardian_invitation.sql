-- Migration: 20260906160000_revoke_guardian_invitation.sql
-- Implements Issue #3 (gap-closure plan, Unit U1): per-invitation cancellation.
--
-- create_guardian_invitation mints a 48-hour link and nothing in the app can
-- list or cancel one before it expires. `guardian_invitations_select`
-- already exposes a profile's invitations to its primary guardian and
-- co-parents, and `accept_guardian_invitation` already refuses a row with
-- `revoked_at` set - what is missing is a role-laddered way to *set*
-- `revoked_at` on a single invitation. The one existing write path
-- (`grant update (revoked_at) ... to authenticated`, gated by the
-- `guardian_invitations_update` policy's `invited_by = auth.uid()`) is
-- narrower than the role ladder: a primary guardian cannot cancel a
-- co-parent's outstanding invitation through it. Per KTD2, this is closed by
-- routing cancellation through a SECURITY DEFINER RPC and withdrawing the
-- direct grant and policy, matching KTD15's existing rule that membership
-- state is only writable through the SECURITY DEFINER RPCs
-- (20260904010000_multi_guardian_schema.sql's Privileges section) - the
-- surviving column grant on guardian_invitations was the one place that
-- rule was not yet enforced.
--
-- Per "do not edit a merged migration in place", this file is purely
-- additive: a new function plus a revoke/drop of the now-unreachable grant
-- and policy.

-- ---------------------------------------------------------------------------
-- 1. revoke_guardian_invitation RPC
-- ---------------------------------------------------------------------------

create or replace function public.revoke_guardian_invitation(p_invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invite public.guardian_invitations%rowtype;
  v_caller_role text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into v_invite
    from public.guardian_invitations
   where id = p_invitation_id
   for update;

  -- Enumeration: a nonexistent invitation and an invitation belonging to a
  -- profile the caller does not guard must be indistinguishable to the
  -- caller, so both raise this exact same message.
  if not found then
    raise exception 'caller lacks permission to cancel this invitation'
      using errcode = 'insufficient_privilege';
  end if;

  select role into v_caller_role
    from public.profile_guardians
   where profile_id = v_invite.profile_id
     and user_id = v_uid
     and status = 'accepted';

  -- R3: only a primary guardian or co-parent may cancel anything.
  if v_caller_role is null or v_caller_role not in ('primary_guardian', 'co_parent') then
    raise exception 'caller lacks permission to cancel this invitation'
      using errcode = 'insufficient_privilege';
  end if;

  -- R3: a co-parent may cancel an invitation it created, plus any
  -- caregiver/viewer invitation - but not a co_parent invitation created by
  -- someone else (the primary guardian, or another co-parent).
  if v_caller_role = 'co_parent'
     and v_invite.role = 'co_parent'
     and v_invite.invited_by is distinct from v_uid then
    raise exception 'caller lacks permission to cancel this invitation'
      using errcode = 'insufficient_privilege';
  end if;

  -- R5: terminal states report their outcome rather than raising, and never
  -- alter an already-accepted membership.
  if v_invite.accepted_at is not null then
    return jsonb_build_object('outcome', 'already_accepted', 'invitation_id', v_invite.id);
  end if;

  if v_invite.revoked_at is not null then
    return jsonb_build_object('outcome', 'already_revoked', 'invitation_id', v_invite.id);
  end if;

  if v_invite.expires_at <= now() then
    -- Stamp revoked_at even though it is already inert, so the row's
    -- terminal state is unambiguous to a future reader (Q1: either choice
    -- is safe here, since accept_guardian_invitation already refuses on
    -- expiry independently of revoked_at).
    update public.guardian_invitations
       set revoked_at = clock_timestamp()
     where id = v_invite.id;
    return jsonb_build_object('outcome', 'expired', 'invitation_id', v_invite.id);
  end if;

  update public.guardian_invitations
     set revoked_at = clock_timestamp()
   where id = v_invite.id;

  return jsonb_build_object('outcome', 'revoked', 'invitation_id', v_invite.id);
end;
$$;

comment on function public.revoke_guardian_invitation(uuid) is
  'Cancels a single outstanding guardian invitation under the same role '
  'ladder as revoke_guardian: primary_guardian may cancel any invitation on '
  'the profile; a co_parent may cancel one it created, plus any '
  'caregiver/viewer invitation. SECURITY DEFINER - see '
  'docs/plans/2026-09-06-001-feat-family-sharing-invitations-plan.md (U1).';

revoke all on function public.revoke_guardian_invitation(uuid) from public, anon;
grant execute on function public.revoke_guardian_invitation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Withdraw the direct update(revoked_at) grant and its policy (KTD2)
-- ---------------------------------------------------------------------------
-- Nothing in lib/ ever used this grant - supabase_sharing_service.dart calls
-- RPCs exclusively - so there is no client to migrate. All invitation-state
-- writes (revoked_at, accepted_at, accepted_by) are now SECURITY
-- DEFINER-only, matching KTD15's rule for profile_guardians.

drop policy if exists "guardian_invitations_update" on public.guardian_invitations;

revoke update (revoked_at) on public.guardian_invitations from authenticated;
