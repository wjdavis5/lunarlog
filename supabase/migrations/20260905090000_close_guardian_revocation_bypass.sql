-- Migration: 20260905090000_close_guardian_revocation_bypass.sql
-- Fixes Issues #81 and #82 - two halves of one exploit, both pre-existing in
-- 20260904020000_sync_push_and_invitations.sql (present verbatim at f1ea1e2,
-- not a regression): a revoked guardian could redeem an invitation they
-- already held to restore their own access, with no action by the primary
-- guardian. Per the "do not edit a merged migration in place" rule, this
-- file only adds a column and `create or replace`s the affected functions.
--
-- 1. Add profile_guardians.revoked_at, backfilled for rows already revoked.
-- 2. revoke_guardian: cancel the profile's outstanding invitations in the
--    same transaction (#81). guardian_invitations binds to a token, not a
--    recipient identity - there is no invitee column to check the target
--    user against before redemption - so this cancels every still-live
--    invitation for the profile rather than guessing which one the revoked
--    user held. See the function body for the full reasoning.
-- 3. accept_guardian_invitation: refuse to revive a revoked membership
--    through a token that predates the revocation (#82), independently of
--    whether #81 already canceled it - defence in depth. A token issued
--    *after* the revocation still works, so a primary guardian can
--    deliberately re-add someone they previously removed.
-- 4. create_guardian_invitation: stamp created_at with clock_timestamp()
--    instead of the column's now()-based default, so the #82 comparison
--    (invitation created_at vs. membership revoked_at) is meaningful even
--    when a revoke and a later re-invite land inside one transaction (e.g.
--    these RPCs' own pgTAP tests) - now()/transaction_timestamp() would
--    read identically for both calls and defeat the comparison.

-- ---------------------------------------------------------------------------
-- 1. profile_guardians.revoked_at
-- ---------------------------------------------------------------------------

alter table public.profile_guardians
  add column if not exists revoked_at timestamptz;

comment on column public.profile_guardians.revoked_at is
  'Timestamp of the revoke_guardian call that most recently set status to
   revoked. Null whenever status <> revoked. Used by accept_guardian_invitation
   (#82) to tell a fresh re-invitation from a token that predates the
   revocation. Not client-writable - see the privileges note below.';

-- Legacy rows already 'revoked' before this migration have no revoked_at.
-- Best-effort backfill: updated_at is the only timestamp the old
-- revoke_guardian touched on a revoked row, so it stands in as an
-- approximation of when the revocation happened. Caveat: the
-- profile_guardians update grant lets a primary/co-parent guardian edit
-- display_name (and updated_at) on ANY row for the profile, including a
-- revoked one, via direct PostgREST update - the RLS policy checks only the
-- caller's own role, not the target row's status - so a revoked row whose
-- display_name was edited after revocation would backfill to that later
-- edit time rather than the true revocation instant. That would treat an
-- invitation created in the gap between the real revocation and that edit
-- as "fresh" when it actually predates the revocation. No such edit is
-- known to have happened, but it is not provable from the data alone, so
-- this backfill is a best effort, not a guarantee, for pre-migration rows.
update public.profile_guardians
   set revoked_at = updated_at
 where status = 'revoked'
   and revoked_at is null;

-- No grant added: like status and role, revoked_at is membership state and
-- stays writable only through the SECURITY DEFINER RPCs below (KTD15).

-- ---------------------------------------------------------------------------
-- 2. create_guardian_invitation - clock_timestamp() for created_at
-- ---------------------------------------------------------------------------

create or replace function public.create_guardian_invitation(
  p_profile_id text,
  p_role text,
  p_recipient_label text,
  p_token_hash text,
  p_ttl_hours int default 48
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invitation_id uuid;
  v_now timestamptz;
  v_expires_at timestamptz;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian', 'co_parent']) then
    raise exception 'caller lacks permission to invite guardians for this profile'
      using errcode = 'insufficient_privilege';
  end if;

  if p_role not in ('co_parent', 'caregiver', 'viewer') then
    raise exception 'invalid role: %', p_role using errcode = 'invalid_parameter_value';
  end if;

  -- R3: only the primary guardian may create co-parent invitations; a
  -- co-parent can invite caregivers and viewers only.
  if p_role = 'co_parent'
     and not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian']) then
    raise exception 'only the primary guardian can invite a co-parent'
      using errcode = 'insufficient_privilege';
  end if;

  -- R7: the TTL is server-bounded so an authorized inviter cannot mint a
  -- multi-century (or negative) invitation.
  if coalesce(p_ttl_hours, 48) < 1 or coalesce(p_ttl_hours, 48) > 168 then
    raise exception 'p_ttl_hours must be between 1 and 168'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- clock_timestamp() rather than now(): see this migration's header. This
  -- row's created_at is compared against a profile_guardians.revoked_at in
  -- accept_guardian_invitation (#82), and now()/transaction_timestamp() is
  -- frozen for the whole transaction - it would read identically for an
  -- invitation created before a revoke and one created after it, if both
  -- happened inside the same transaction.
  v_now := clock_timestamp();
  v_expires_at := v_now + (coalesce(p_ttl_hours, 48) || ' hours')::interval;

  insert into public.guardian_invitations
    (profile_id, invited_by, token_hash, role, recipient_label, expires_at, created_at)
  values
    (p_profile_id, v_uid, p_token_hash, p_role, p_recipient_label, v_expires_at, v_now)
  returning id into v_invitation_id;

  return jsonb_build_object(
    'id', v_invitation_id,
    'profile_id', p_profile_id,
    'role', p_role,
    'expires_at', v_expires_at
  );
end;
$$;

revoke all on function public.create_guardian_invitation(text, text, text, text, int) from public, anon;
grant execute on function public.create_guardian_invitation(text, text, text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. accept_guardian_invitation - revoked is terminal for a stale token (#82)
-- ---------------------------------------------------------------------------

create or replace function public.accept_guardian_invitation(
  p_token_hash text,
  p_guardian_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invite public.guardian_invitations%rowtype;
  v_profile public.profiles%rowtype;
  v_existing public.profile_guardians%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_invite
    from public.guardian_invitations
   where token_hash = p_token_hash
   for update;

  if not found then
    raise exception 'invitation not found' using errcode = 'no_data_found';
  end if;

  if v_invite.accepted_at is not null then
    raise exception 'invitation already accepted' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_invite.revoked_at is not null then
    raise exception 'invitation was revoked' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_invite.expires_at <= now() then
    raise exception 'invitation has expired' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Lock any existing membership row for this (profile, user) up front, so
  -- the revoked-terminal check below and the upsert further down decide
  -- against the same snapshot. This also fixes the lock order to match
  -- revoke_guardian's own order (guardian_invitations row(s), then this
  -- profile_guardians row) - see that function - so the two RPCs cannot
  -- deadlock against each other under concurrent calls.
  select * into v_existing
    from public.profile_guardians
   where profile_id = v_invite.profile_id
     and user_id = v_uid
   for update;

  if found then
    if v_existing.status = 'accepted' then
      raise exception 'user is already an active guardian of this profile'
        using errcode = 'unique_violation';
    end if;

    if v_existing.status = 'revoked' then
      -- #82: revoked is terminal for a token that predates the revocation.
      -- A deliberate re-invitation issued *after* the revocation must still
      -- work (a primary guardian can always re-add someone they previously
      -- removed) - the distinguishing fact is whether this invitation's
      -- created_at is after the membership row's revoked_at. Both are
      -- stamped with clock_timestamp(), not now() (see
      -- create_guardian_invitation and revoke_guardian), so the comparison
      -- holds even across two RPC calls made inside one transaction.
      --
      -- v_existing.revoked_at is null only for a row revoked before this
      -- migration's column existed (best-effort backfilled from updated_at
      -- - see the migration header); if it is still null here there is
      -- nothing reliable to compare against, so the safer default is to
      -- refuse rather than guess.
      if v_existing.revoked_at is null or v_invite.created_at <= v_existing.revoked_at then
        raise exception 'guardian access to this profile was revoked; a new invitation is required'
          using errcode = 'object_not_in_prerequisite_state';
      end if;
      -- else: this invitation was created after the revocation - a genuine
      -- re-invitation. Fall through to the upsert below, which clears
      -- revoked_at and re-derives role from this (fresh) invitation.
    end if;
  end if;

  -- Add or revive membership in profile_guardians. The check above has
  -- already run for any existing row, so this can only reach a revoked row
  -- here via a provably fresh invitation.
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, invited_by, updated_at, revoked_at)
  values
    (v_invite.profile_id, v_uid, v_invite.role, 'accepted', p_guardian_display_name, v_invite.invited_by, now(), null)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null;

  -- Mark invitation as accepted
  update public.guardian_invitations
     set accepted_at = now(),
         accepted_by = v_uid
   where id = v_invite.id;

  select * into v_profile
    from public.profiles
   where id = v_invite.profile_id;

  return jsonb_build_object(
    'profile_id', v_profile.id,
    'profile_name', v_profile.display_name,
    'role', v_invite.role
  );
end;
$$;

revoke all on function public.accept_guardian_invitation(text, text) from public, anon;
grant execute on function public.accept_guardian_invitation(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. revoke_guardian - cancel the profile's outstanding invitations (#81)
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

  return true;
end;
$$;

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;
