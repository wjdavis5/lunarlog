-- Migration: 20260915010000_db_integrity_bundle.sql
--
-- Bundle of four whole-repository-audit findings (pinned snapshot
-- 9901f35c17a05ba8c1bea1ea07f310eca2f663cc), grouped into one PR because
-- they touch the same handful of guardian/ownership/observation surfaces:
--
--   * Issue #618, LLA-054 (P1): role-authority TOCTOU. update_guardian_role,
--     revoke_guardian, create_ownership_transfer, and
--     accept_ownership_transfer each read a caller's or a target's
--     profile_guardians role with a plain (unlocked) SELECT, then decide
--     whether the caller may proceed based on that read - a concurrent
--     transaction can commit a role change to the same row between the
--     read and this function's own final mutation, so the ladder/authority
--     check runs against data that is already stale by the time it takes
--     effect. Fixed by locking every profile_guardians row a decision
--     depends on with `for update`, BEFORE the check that reads it, in
--     every one of these four RPCs - not just the row this function
--     itself ends up writing to, so a competing call blocks at the lock
--     rather than proceeding on borrowed time.
--
--     Lock order convention (binding across all four RPCs below, so no
--     two of them - called with any pair of users - can deadlock against
--     each other): whenever an RPC locks two DISTINCT profile_guardians
--     rows for the same profile_id, it locks them in ascending user_id
--     order. A function that only ever needs to lock its caller's own row
--     (create_ownership_transfer) has nothing to order against this rule.
--
--   * Issue #636, LLA-056 (P2): is_profile_guardian(), is_guardian_with_
--     roles(), and owns_feedback_ticket() are SECURITY DEFINER and, per
--     20260908121000_revoke_anon_execute_guardian_feedback_functions.sql's
--     own comment, EXECUTE must stay granted to `authenticated` because
--     RLS policies on profiles/day_entries/profile_guardians/observations/
--     notification_preferences/feedback_replies/etc. call them directly
--     inside `using`/`with check` clauses evaluated AS the querying role -
--     so simply revoking EXECUTE (as was done for anon) would break RLS
--     for every authenticated user. But that same EXECUTE grant means an
--     authenticated caller who is a stranger to a given family can invoke
--     `/rpc/is_profile_guardian` (or the other two) directly with an
--     arbitrary p_user_id and a profile/ticket id they merely know, and
--     get a definitive true/false about a relationship they have no part
--     in - an authenticated-outsider family-membership oracle. Every
--     legitimate call site in this schema (every RLS policy, and every
--     other SECURITY DEFINER function) already passes p_user_id =
--     auth.uid() - the one exception, accept_ownership_transfer checking
--     the ARMING PARENT's role (not the caller's), is refactored below to
--     query profile_guardians directly instead. So all three helpers are
--     re-emitted with one added guard: they only ever answer about the
--     calling user (`p_user_id is not distinct from (select auth.uid())`),
--     a no-op for every real call site and a hard `false` for the oracle
--     case. EXECUTE stays granted to authenticated; nothing about the
--     grant posture changes.
--
--   * Issue #616, LLA-057 (P2): observations.day_entry_id and
--     observations.profile_id are two independent FKs (to day_entries(id)
--     and profiles(id) respectively) with no relationship enforced between
--     them at the constraint level, and the table grants
--     (20260908160000_observations.sql section 4) let `authenticated`
--     INSERT/UPDATE the table directly, not only through sync_push. The
--     RPC re-validates "day_entry_id belongs to profile_id" and the
--     200-observations-per-day cap on every push, but a raw client write
--     bypasses both, letting an authenticated guardian of profile A link
--     an observation onto profile B's day_entries row (cross-profile
--     linkage the RLS predicate on `observations.profile_id` alone cannot
--     catch, since it never looks at day_entry_id) or blow past the
--     per-day content cap outright. Fixed with a new BEFORE INSERT/UPDATE
--     trigger enforcing both invariants for every write, not only the
--     RPC's own. profile_id is made fully immutable (it never legitimately
--     moves post-insert); day_entry_id is re-validated whenever it is set
--     or changes - not made immutable outright, since
--     20260914010000_sync_push_observation_reparent.sql's same-date
--     day-entry resolver legitimately reparents a losing entry's live
--     observations onto the surviving entry, always within the same
--     profile_id, which this trigger's composite check permits.
--
--   * Issue #616, LLA-059 (P2): profiles.transferred_at and
--     profiles.transferred_to_user_id are ownership-transfer state,
--     server-owned, and stamped only inside accept_ownership_transfer -
--     the UPDATE grant to `authenticated` (20260903014208_initial_sync_
--     schema.sql) already omits both columns. But the INSERT grant on the
--     same table is table-wide (`grant select, insert on table
--     public.profiles to authenticated`, no column list), and Postgres
--     INSERT privilege is not implicitly scoped by an UPDATE column list -
--     so a raw authenticated INSERT of a BRAND-NEW profile row could still
--     supply both columns directly in the payload, forging transfer
--     evidence a future consumer (the client-side health-sync minor gate,
--     issue #153/#296) might trust. Fixed with a new BEFORE INSERT/UPDATE
--     trigger: rejects any INSERT that sets either column (no legitimate
--     INSERT path - sync_push's own explicit column list never names
--     them - ever needs to), and permits an UPDATE that changes them only
--     inside accept_ownership_transfer's existing KTD4
--     `lunarlog.ownership_transfer` bypass, the one legitimate write path.
--
-- Both new triggers (observations, profiles) exempt an unauthenticated
-- write (`auth.uid() is null`) exactly the way enforce_day_entry_
-- attribution()/enforce_observation_attribution() already do: a
-- service_role session already bypasses RLS and holds unrestricted table
-- access regardless of any trigger here, so there is nothing this closes
-- for that context; the actual boundary these two triggers add is between
-- an authenticated client's own sync_push call and the same client's raw
-- table write.
--
-- Part 5 (below): LLA-056 fallout inside accept_prediction_connection(),
-- which also read someone other than the caller (the sharer) through
-- is_guardian_with_roles() and needed the same inline-query fix
-- accept_ownership_transfer gets in Part 2 - found by running the full
-- pgTAP suite against Parts 1-4, not by the original audit.
--
-- Coverage: supabase/tests/guardian_role_authority_lock_test.sql (new,
-- LLA-054), supabase/tests/relationship_helper_oracle_test.sql (new,
-- LLA-056), supabase/tests/observation_parent_invariants_test.sql (new,
-- LLA-057 + LLA-059).

-- =============================================================================
-- Part 1 - Issue #636, LLA-056: relationship helpers only answer for the
-- calling user.
-- =============================================================================

create or replace function public.is_profile_guardian(p_profile_id text, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select
    p_user_id is not distinct from (select auth.uid())
    and exists (
      select 1
        from public.profile_guardians
       where profile_id = p_profile_id
         and user_id = p_user_id
         and status = 'accepted'
    );
$$;

comment on function public.is_profile_guardian(text, uuid) is
  'RLS/internal helper (security definer to avoid recursive profile_guardians '
  'policy evaluation). Issue #636, LLA-056: only ever answers about the '
  'CALLING user (p_user_id must equal auth.uid()) - every RLS policy and '
  'every other SECURITY DEFINER caller in this schema already passes '
  'auth.uid() as p_user_id, so this is a no-op for every legitimate call '
  'site; it closes an authenticated-outsider oracle that could otherwise '
  'pass an arbitrary p_user_id via a direct PostgREST RPC call and learn '
  'whether some OTHER user is a guardian of a profile the caller has no '
  'access to. EXECUTE stays granted to authenticated (revoked already from '
  'public/anon in 20260908121000_revoke_anon_execute_guardian_feedback_'
  'functions.sql) because RLS policies on profiles/day_entries/'
  'profile_guardians/observations/notification_preferences/etc. call this '
  'directly and need it.';

create or replace function public.is_guardian_with_roles(p_profile_id text, p_user_id uuid, p_roles text[])
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select
    p_user_id is not distinct from (select auth.uid())
    and exists (
      select 1
        from public.profile_guardians
       where profile_id = p_profile_id
         and user_id = p_user_id
         and status = 'accepted'
         and role = any(p_roles)
    );
$$;

comment on function public.is_guardian_with_roles(text, uuid, text[]) is
  'RLS/internal helper (security definer to avoid recursive profile_guardians '
  'policy evaluation). Issue #636, LLA-056: only ever answers about the '
  'CALLING user (p_user_id must equal auth.uid()), same restriction and '
  'rationale as is_profile_guardian() above. accept_ownership_transfer''s '
  'one call site that needed to check a DIFFERENT user''s role (the arming '
  'parent''s, not the accepting caller''s) no longer goes through this '
  'helper - it queries profile_guardians directly, inline, under its own '
  'lock (see that function''s re-emission below, Issue #618/LLA-054). '
  'EXECUTE stays granted to authenticated for the same RLS reason as '
  'is_profile_guardian().';

create or replace function public.owns_feedback_ticket(p_ticket_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select
    p_user_id is not distinct from (select auth.uid())
    and exists (
      select 1
        from public.feedback_tickets
       where id = p_ticket_id
         and user_id = p_user_id
    );
$$;

comment on function public.owns_feedback_ticket(uuid, uuid) is
  'RLS helper (security definer to avoid recursive feedback_tickets policy '
  'evaluation): true when p_user_id owns the ticket p_ticket_id. Issue '
  '#636, LLA-056: only ever answers about the CALLING user (p_user_id must '
  'equal auth.uid()), same restriction as is_profile_guardian()/'
  'is_guardian_with_roles() above - every existing call site already '
  'passes auth.uid(), so this closes an outsider oracle without changing '
  'behavior for any legitimate caller.';

-- =============================================================================
-- Part 2 - Issue #618, LLA-054: serialize role authority checks.
-- =============================================================================

-- Re-emitted from its 20260913011000_guardian_role_change_cancel_
-- invitations.sql body (the current definition on main) plus locked reads
-- of both the caller's and the target's profile_guardians rows, in
-- ascending user_id order, ahead of every check that depends on them.
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

  -- AC4: no caller may change their own role - checked ahead of the
  -- locked reads below since it needs no role data. The primary guardian
  -- demoting/promoting themselves is rejected the same way; ownership
  -- moves only through the transfer flow.
  if v_uid = p_target_user_id then
    raise exception 'cannot change your own role'
      using errcode = 'insufficient_privilege';
  end if;

  -- LLA-054: lock both rows BEFORE reading the roles the checks below
  -- depend on - a plain (unlocked) SELECT here would let a concurrent
  -- revoke_guardian / update_guardian_role / accept_ownership_transfer
  -- call commit a role change to either row between this read and this
  -- function's own final UPDATE, so the ladder check below could
  -- authorize against data that is already stale by the time it takes
  -- effect. Locked in ascending user_id order (this migration's binding
  -- convention) so this can never deadlock against revoke_guardian or
  -- accept_ownership_transfer locking the same pair of rows.
  if v_uid < p_target_user_id then
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
     for update;
    select role into v_target_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = p_target_user_id and status = 'accepted'
     for update;
  else
    select role into v_target_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = p_target_user_id and status = 'accepted'
     for update;
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
     for update;
  end if;

  if v_caller_role is null then
    raise exception 'caller is not a guardian of this profile'
      using errcode = 'insufficient_privilege';
  end if;

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
  -- Caregivers and viewers may change nothing. v_caller_role/v_target_role
  -- were both read under lock above, so this decision cannot be stale.
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

  update public.profile_guardians
     set role = p_new_role,
         updated_at = greatest(updated_at, clock_timestamp())
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  -- Issue #519: narrowing a target away from an invite-capable role
  -- (primary_guardian/co_parent) down to caregiver/viewer cancels every
  -- still-live invitation for the profile - see
  -- 20260913011000_guardian_role_change_cancel_invitations.sql for the
  -- full rationale, carried forward verbatim.
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
  'still-live invitation for the profile. Issue #618, LLA-054: both the '
  'caller''s and the target''s profile_guardians rows are locked (`for '
  'update`, ascending user_id order) before either role is read, so a '
  'concurrent role change cannot leave this function''s ladder check '
  'deciding against stale data. SECURITY DEFINER - updates '
  'profile_guardians.role (and, when the narrowing condition applies, '
  'guardian_invitations.revoked_at) only.';

revoke all on function public.update_guardian_role(text, uuid, text) from public, anon;
grant execute on function public.update_guardian_role(text, uuid, text) to authenticated;

-- Re-emitted from its 20260909200000_prediction_connections.sql body (the
-- current definition on main) plus the same locked-read fix as
-- update_guardian_role above.
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

  -- LLA-054: same lock-before-check fix as update_guardian_role above -
  -- see its comment for the TOCTOU this closes. Self-leave (v_uid =
  -- p_target_user_id) locks a single row and needs no ordering; otherwise
  -- locked in ascending user_id order, this migration's binding
  -- convention, so this can never deadlock against update_guardian_role
  -- or accept_ownership_transfer locking the same pair of rows.
  if v_uid = p_target_user_id then
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
     for update;
    v_target_role := v_caller_role;
  elsif v_uid < p_target_user_id then
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
     for update;
    select role into v_target_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = p_target_user_id and status = 'accepted'
     for update;
  else
    select role into v_target_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = p_target_user_id and status = 'accepted'
     for update;
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
     for update;
  end if;

  if v_caller_role is null then
    raise exception 'caller is not a guardian of this profile'
      using errcode = 'insufficient_privilege';
  end if;

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

  -- Issue #4, U3, review item #1 (P0): close the ownership-transfer bypass.
  update public.ownership_transfers
     set cancelled_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and cancelled_at is null;

  -- #81: revocation must close every door, not just the one the revoked
  -- user already walked through.
  update public.guardian_invitations
     set revoked_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and revoked_at is null;

  -- Issue #151: a guardian revocation also revokes every live prediction
  -- connection for the profile.
  update public.prediction_connections
     set revoked_at = v_now
   where profile_id = p_profile_id
     and revoked_at is null;

  update public.profile_guardians
     set status = 'revoked',
         updated_at = v_now,
         revoked_at = v_now
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  -- Issue #5, U4 (R5): stop the revoked guardian's alerts for this profile
  -- immediately.
  delete from public.notification_preferences
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  delete from public.notification_outbox
   where profile_id = p_profile_id
     and recipient_user_id = p_target_user_id
     and sent_at is null;

  -- Round-2 review #8: also drop the revoked guardian's missed-entry dedupe
  -- marker for this profile.
  delete from public.missed_entry_alert_state
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  return true;
end;
$$;

comment on function public.revoke_guardian(text, uuid) is
  'Revokes p_target_user_id''s guardianship of p_profile_id (see prior '
  'migrations for the #81/#82 fixes, Issue #5 U4''s alert cleanup, and '
  'Issue #151''s prediction_connections revocation). Issue #618, LLA-054: '
  'both the caller''s and the target''s profile_guardians rows are locked '
  '(`for update`, ascending user_id order, or a single lock on self-leave) '
  'before either role is read, so a concurrent role change cannot leave '
  'this function''s authority check deciding against stale data.';

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;

-- Re-emitted from its 20260906180000_ownership_transfer_rpcs.sql body (the
-- current definition on main) plus a locked read of the caller's own
-- profile_guardians row ahead of the authority check that depends on it.
create or replace function public.create_ownership_transfer(
  p_profile_id text,
  p_parent_post_transfer_role text,
  p_token_hash text,
  p_recipient_label text default null,
  p_ttl_hours int default 72
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_transfer_id uuid;
  v_ttl int;
  v_now timestamptz;
  v_expires_at timestamptz;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- LLA-054: lock the caller's own profile_guardians row before checking
  -- authority against it - see update_guardian_role's identical comment
  -- for the TOCTOU this closes (a concurrent revoke_guardian /
  -- update_guardian_role commit could otherwise withdraw the caller's
  -- primary_guardian role immediately after an unlocked read passed). Only
  -- one row is ever locked here (the caller's own), so there is nothing to
  -- order against this migration's ascending-user_id convention.
  select role into v_caller_role
    from public.profile_guardians
   where profile_id = p_profile_id and user_id = v_uid and status = 'accepted'
   for update;

  -- R6: only the accepted primary_guardian can arm a transfer. A co-parent
  -- cannot, even though co-parents can edit profile metadata elsewhere.
  if v_caller_role is distinct from 'primary_guardian' then
    raise exception 'only the accepted primary guardian can transfer ownership of this profile'
      using errcode = 'insufficient_privilege';
  end if;

  -- R7: the parent must choose their own post-transfer role up front.
  if p_parent_post_transfer_role is null or p_parent_post_transfer_role not in ('co_parent', 'viewer') then
    raise exception 'invalid parent_post_transfer_role: %', p_parent_post_transfer_role
      using errcode = 'invalid_parameter_value';
  end if;

  -- R8: the TTL is server-bounded, default 72, caller-overridable 1-168.
  v_ttl := coalesce(p_ttl_hours, 72);
  if v_ttl < 1 or v_ttl > 168 then
    raise exception 'p_ttl_hours must be between 1 and 168'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  if p_recipient_label is not null and char_length(p_recipient_label) > 80 then
    raise exception 'recipient_label must be at most 80 characters' using errcode = 'invalid_parameter_value';
  end if;

  -- KTD6: ownership_transfers_one_live_uq cannot itself reference now() (not
  -- immutable), so re-issuing a link after the old one lapsed is a
  -- deliberate cancel-then-create.
  update public.ownership_transfers
     set cancelled_at = clock_timestamp()
   where profile_id = p_profile_id
     and initiated_by = v_uid
     and accepted_at is null
     and cancelled_at is null
     and expires_at <= clock_timestamp();

  v_now := clock_timestamp();
  v_expires_at := v_now + (v_ttl || ' hours')::interval;

  insert into public.ownership_transfers
    (profile_id, initiated_by, token_hash, parent_post_transfer_role, recipient_label, expires_at, created_at)
  values
    (p_profile_id, v_uid, p_token_hash, p_parent_post_transfer_role, p_recipient_label, v_expires_at, v_now)
  returning id into v_transfer_id;

  return jsonb_build_object(
    'id', v_transfer_id,
    'profile_id', p_profile_id,
    'parent_post_transfer_role', p_parent_post_transfer_role,
    'expires_at', v_expires_at
  );
end;
$$;

comment on function public.create_ownership_transfer(text, text, text, text, int) is
  'Arms a single-use ownership-transfer link for p_profile_id (Issue #4). '
  'Only the accepted primary_guardian may call this. Issue #618, LLA-054: '
  'the caller''s own profile_guardians row is locked (`for update`) before '
  'its role is checked, so a concurrent revocation or role change cannot '
  'leave this decision based on stale data.';

revoke all on function public.create_ownership_transfer(text, text, text, text, int) from public, anon;
grant execute on function public.create_ownership_transfer(text, text, text, text, int) to authenticated;

-- Re-emitted from its 20260913030000_ownership_transfer_revoke_prediction_
-- connections.sql body (the current definition on main) plus: locked reads
-- of both the initiator's and the acceptor's own profile_guardians rows in
-- ascending user_id order (LLA-054), replacing the initiator's role check,
-- which previously went through is_guardian_with_roles() - an unlocked
-- read of someone OTHER than the caller's own membership row, exactly the
-- shape LLA-056 (above) closed that helper off for. Both fixes land on the
-- same replacement: an inline, locked, direct profile_guardians query.
create or replace function public.accept_ownership_transfer(
  p_token_hash text,
  p_child_display_name text default null,
  p_parent_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_transfer public.ownership_transfers%rowtype;
  v_profile public.profiles%rowtype;
  v_initiator public.profile_guardians%rowtype;
  v_existing public.profile_guardians%rowtype;
  v_day_entries_rehomed bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- Lock order: ownership_transfers, then profiles, then profile_guardians -
  -- matches accept_guardian_invitation / revoke_guardian's own order, so
  -- the two RPC families cannot deadlock against each other.
  select * into v_transfer
    from public.ownership_transfers
   where token_hash = p_token_hash
   for update;

  if not found then
    raise exception 'transfer not found' using errcode = 'no_data_found';
  end if;

  -- R20: each terminal state gets a distinguishable reason.
  if v_transfer.accepted_at is not null then
    raise exception 'transfer was already accepted' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_transfer.cancelled_at is not null then
    raise exception 'transfer was cancelled' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_transfer.expires_at <= clock_timestamp() then
    raise exception 'transfer has expired' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- R11: the arming parent cannot accept their own transfer. Guarantees
  -- v_transfer.initiated_by <> v_uid below, so the two profile_guardians
  -- locks that follow are always on two distinct rows.
  if v_uid = v_transfer.initiated_by then
    raise exception 'the arming parent cannot accept their own transfer'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into v_profile
    from public.profiles
   where id = v_transfer.profile_id
   for update;

  if not found then
    raise exception 'profile not found' using errcode = 'no_data_found';
  end if;

  -- Stale-link guard (1 of 2): the armer must still own the profile.
  if v_profile.user_id is distinct from v_transfer.initiated_by then
    raise exception 'the arming parent no longer owns this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- LLA-054/LLA-056: lock the initiator's and the acceptor's own
  -- profile_guardians rows before checking either's authority, in
  -- ascending user_id order - this migration's binding convention, so
  -- this can never deadlock against update_guardian_role or
  -- revoke_guardian locking the same pair of rows. Previously the
  -- initiator's role was read via
  -- is_guardian_with_roles(v_transfer.profile_id, v_transfer.initiated_by,
  -- array['primary_guardian']) - an UNLOCKED read of someone else's
  -- membership row (LLA-054's TOCTOU) through a helper that LLA-056 (Part
  -- 1 above) now refuses to answer for any p_user_id other than the
  -- caller's own auth.uid() anyway (LLA-056). Querying profile_guardians
  -- directly, inline, under a lock, fixes both at once.
  if v_transfer.initiated_by < v_uid then
    select * into v_initiator
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_transfer.initiated_by
       and status = 'accepted'
     for update;
    select * into v_existing
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_uid
     for update;
  else
    select * into v_existing
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_uid
     for update;
    select * into v_initiator
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_transfer.initiated_by
       and status = 'accepted'
     for update;
  end if;

  -- Stale-link guard (2 of 2): the armer must still be the accepted
  -- primary_guardian. v_initiator.role reads null (distinct from
  -- 'primary_guardian') both when no row exists at all and when one exists
  -- but is not status = 'accepted' (the WHERE clause above already
  -- excludes it), matching is_guardian_with_roles()'s original semantics
  -- exactly.
  if v_initiator.role is distinct from 'primary_guardian' then
    raise exception 'the arming parent is no longer the primary guardian of this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Review item #1 (P0), acceptor-freshness check: the mirror of
  -- accept_guardian_invitation's #82 guard, applied to the acceptor rather
  -- than the arming parent. v_existing.user_id is not null stands in for
  -- the old `found` (unreliable here, since which SELECT ran last differs
  -- by branch above).
  if v_existing.user_id is not null and v_existing.status = 'revoked' then
    if v_existing.revoked_at is null or v_transfer.created_at <= v_existing.revoked_at then
      raise exception 'guardian access to this profile was revoked; a new transfer link is required'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end if;

  -- KTD4: arm the transaction-local bypass so the re-home below can move
  -- day_entries.user_id (and, per Issue #616/LLA-059 below, profiles.
  -- transferred_at/transferred_to_user_id) without tripping either
  -- attribution/authoritative-field guard.
  perform set_config('lunarlog.ownership_transfer', 'on', true);

  -- R12: profiles.user_id moves to the accepting user; transferred_at is
  -- stamped. Issue #296: transferred_to_user_id is stamped with the same
  -- accepting uid, in the same statement.
  update public.profiles
     set user_id = v_uid,
         transferred_at = clock_timestamp(),
         transferred_to_user_id = v_uid,
         updated_at = greatest(updated_at, clock_timestamp())
   where id = v_transfer.profile_id;

  -- R15/R16/R17: re-point the cascade anchor for EVERY entry on the
  -- profile, not only the ones currently anchored to the arming parent.
  update public.day_entries
     set user_id = v_uid
   where profile_id = v_transfer.profile_id;
  get diagnostics v_day_entries_rehomed = row_count;

  -- R14: demote the parent to their chosen role BEFORE promoting the child,
  -- so profile_guardians_one_primary_uq (R22) is never transiently violated.
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, updated_at, revoked_at)
  values
    (v_transfer.profile_id, v_transfer.initiated_by, v_transfer.parent_post_transfer_role, 'accepted',
     p_parent_display_name, clock_timestamp(), null)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null;

  -- R13: promote the child to the profile's sole primary_guardian.
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, invited_by, updated_at, revoked_at)
  values
    (v_transfer.profile_id, v_uid, 'primary_guardian', 'accepted', p_child_display_name,
     v_transfer.initiated_by, clock_timestamp(), null)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null;

  -- R18: single-use.
  update public.ownership_transfers
     set accepted_at = clock_timestamp(),
         accepted_by = v_uid
   where id = v_transfer.id;

  -- Any other still-live transfer for this profile is now moot.
  update public.ownership_transfers
     set cancelled_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and id <> v_transfer.id
     and accepted_at is null
     and cancelled_at is null;

  -- Review item #4 (P1): the ex-parent's own still-live guardian invitations
  -- for this profile are decisions made under an ownership that no longer
  -- holds.
  update public.guardian_invitations
     set revoked_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and accepted_at is null
     and revoked_at is null;

  -- Issue #496: the ex-parent's live prediction connections for this
  -- profile must be revoked upon transfer.
  update public.prediction_connections
     set revoked_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and revoked_at is null;

  return jsonb_build_object(
    'profile_id', v_transfer.profile_id,
    'profile_name', v_profile.display_name,
    'parent_role', v_transfer.parent_post_transfer_role,
    'day_entries_rehomed', v_day_entries_rehomed
  );
end;
$$;

comment on function public.accept_ownership_transfer(text, text, text) is
  'Single SECURITY DEFINER transaction (KTD3): moves profiles.user_id and '
  'the accepted primary_guardian membership to the accepting user, demotes '
  'the arming parent to their chosen role, re-homes day_entries.user_id via '
  'the KTD4 attribution-guard bypass, marks the transfer single-use, '
  'revokes outstanding guardian invitations, and (Issue #496) revokes all '
  'active and pending prediction connections for the profile. Issue #618, '
  'LLA-054: the initiator''s and the acceptor''s profile_guardians rows are '
  'both locked (`for update`, ascending user_id order) before either''s '
  'authority is checked - no longer via the shared is_guardian_with_roles() '
  'helper, which Issue #636/LLA-056 now refuses to answer for anyone other '
  'than the calling user. Commits together or not at all.';

revoke all on function public.accept_ownership_transfer(text, text, text) from public, anon;
grant execute on function public.accept_ownership_transfer(text, text, text) to authenticated;

-- =============================================================================
-- Part 3 - Issue #616, LLA-057: observation parent invariants and per-day
-- cap enforced on every write, not only sync_push's own.
-- =============================================================================

create or replace function public.enforce_observation_parent_invariants()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_observations_per_day constant integer := 200;
  v_uid uuid := (select auth.uid());
  v_day_entry_profile_id text;
  v_check_cap boolean;
  v_obs_count integer;
begin
  -- Matches enforce_day_entry_attribution()/enforce_observation_
  -- attribution()'s own escape hatch: an unauthenticated write
  -- (service_role, a migration, import tooling) already bypasses RLS
  -- entirely, so there is nothing this guard protects there that raw
  -- table access does not already grant - the invariant it actually
  -- closes is an AUTHENTICATED client writing observations directly
  -- instead of through sync_push (LLA-057).
  if v_uid is null then
    return new;
  end if;

  if tg_op = 'UPDATE' and new.profile_id is distinct from old.profile_id then
    raise exception 'observations.profile_id is immutable'
      using errcode = 'insufficient_privilege';
  end if;

  -- Composite parent/profile consistency: day_entry_id and profile_id are
  -- two independent FKs with no relationship to each other at the
  -- constraint level, so an ordinary authenticated INSERT/UPDATE (the
  -- table grants allow both - 20260908160000_observations.sql section 4)
  -- could otherwise link a profile the caller legitimately guards to a
  -- DIFFERENT profile's day_entries row. sync_push already re-validates
  -- this on every push ("day_entry_id does not belong to profile_id");
  -- this trigger is the same check enforced for every write. Only
  -- re-checked when day_entry_id is being set (INSERT) or actually
  -- changes - the observation-reparent path
  -- (20260914010000_sync_push_observation_reparent.sql's same-date
  -- day-entry resolver) moves day_entry_id between two day_entries rows
  -- that share the same profile_id by construction, so this never rejects
  -- that legitimate path; an unchanged day_entry_id was already validated
  -- the last time it was set.
  if tg_op = 'INSERT' or new.day_entry_id is distinct from old.day_entry_id then
    select profile_id into v_day_entry_profile_id
      from public.day_entries
     where id = new.day_entry_id;
    if v_day_entry_profile_id is distinct from new.profile_id then
      raise exception 'day_entry_id does not belong to profile_id'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  -- Per-day cap, mirroring sync_push's own c_max_observations_per_day
  -- check and its v_obs_check_collision predicate exactly: only
  -- re-counted when this write will land a live row under a (profile_id,
  -- local_date) that was not already counted - a brand-new live row, a
  -- revive (tombstone -> live), or a local_date move - never a plain
  -- content edit that keeps its own live row in place. Runs after
  -- observations_derive_local_date (this trigger's name sorts after it
  -- alphabetically, and BEFORE triggers on the same table/event fire in
  -- name order) so new.local_date is already the corrected value when
  -- observed_at/tz derive a different day than the client-supplied key.
  v_check_cap := new.deleted_at is null and (
    tg_op = 'INSERT'
    or old.deleted_at is not null
    or old.local_date is distinct from new.local_date
  );
  if v_check_cap then
    select count(*) into v_obs_count
      from public.observations
     where profile_id = new.profile_id
       and local_date = new.local_date
       and deleted_at is null
       and id <> new.id;
    if v_obs_count >= c_max_observations_per_day then
      raise exception 'profile % already has % observations for %, at the % cap',
        new.profile_id, v_obs_count, new.local_date, c_max_observations_per_day
        using errcode = 'invalid_parameter_value';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_observation_parent_invariants() is
  'BEFORE INSERT/UPDATE guard on observations (Issue #616, LLA-057): '
  'profile_id is immutable; day_entry_id, whenever set or changed, must '
  'belong to the same profile_id (closing a raw-write cross-profile link '
  'sync_push already checks but the table grants alone do not); and the '
  '200-observations-per-(profile,day) cap sync_push enforces in the RPC is '
  're-enforced here for any write that adds a live row to that day, so a '
  'raw authenticated INSERT/UPDATE cannot bypass either invariant. '
  'Unauthenticated writes (service_role) are exempt, matching '
  'enforce_observation_attribution()''s own convention. Does not replicate '
  'sync_push''s same-date (category, code) merge-dedup - that is a '
  'convenience/data-quality behavior, not an integrity invariant, and (by '
  'existing design) never covers null-code rows anyway; left RPC-only.';

create trigger observations_enforce_parent_invariants
  before insert or update on public.observations
  for each row execute function public.enforce_observation_parent_invariants();

revoke execute on function public.enforce_observation_parent_invariants() from public, anon;

-- =============================================================================
-- Part 4 - Issue #616, LLA-059: profiles.transferred_at/transferred_to_
-- user_id are server-authoritative on every path, not only UPDATE.
-- =============================================================================

create or replace function public.enforce_profile_transfer_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  -- Same escape hatch as every other attribution-style guard in this
  -- schema - see enforce_observation_parent_invariants() above.
  if v_uid is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.transferred_at is not null or new.transferred_to_user_id is not null then
      raise exception 'transferred_at/transferred_to_user_id are server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
  else
    if new.transferred_at is distinct from old.transferred_at
       or new.transferred_to_user_id is distinct from old.transferred_to_user_id then
      -- KTD4 bypass: accept_ownership_transfer's legitimate stamp, the
      -- only path that ever changes either column post-insert.
      if current_setting('lunarlog.ownership_transfer', true) = 'on' then
        null;
      else
        raise exception 'transferred_at/transferred_to_user_id are server-authoritative'
          using errcode = 'insufficient_privilege';
      end if;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_profile_transfer_fields() is
  'BEFORE INSERT/UPDATE guard on profiles (Issue #616, LLA-059): the table '
  'INSERT grant to authenticated is not column-scoped (unlike the UPDATE '
  'grant, which already omits transferred_at/transferred_to_user_id - '
  '20260903014208_initial_sync_schema.sql), so a raw authenticated INSERT '
  'could otherwise forge transfer evidence on a brand-new profile row. '
  'Rejects any INSERT that sets either column - no legitimate INSERT path '
  'ever needs to, sync_push''s own explicit column list never names them. '
  'Permits an UPDATE that changes them only inside accept_ownership_'
  'transfer''s existing KTD4 lunarlog.ownership_transfer bypass, the one '
  'legitimate write path. Unauthenticated writes (service_role) are '
  'exempt, matching every other attribution-style guard in this schema.';

create trigger profiles_enforce_transfer_fields
  before insert or update on public.profiles
  for each row execute function public.enforce_profile_transfer_fields();

revoke execute on function public.enforce_profile_transfer_fields() from public, anon;

-- =============================================================================
-- Part 5 - Issue #636, LLA-056 fallout: accept_prediction_connection() also
-- checked someone OTHER than the caller (the sharer, v_conn.owner_user_id)
-- through is_guardian_with_roles() - the exact shape Part 1 above closed
-- that helper off for. Re-emitted from its 20260913019000_prediction_
-- minor_gate_durable.sql body (the current definition on main) verbatim,
-- with that one check replaced by a direct, inline profile_guardians
-- query - the same fix accept_ownership_transfer's re-emission (Part 2)
-- applies to its own equivalent check. Not part of the LLA-054 lock-order
-- convention (this RPC is outside that issue's named scope and its
-- pre-fix behavior was already unlocked here too), so no `for update` is
-- added - this is purely the LLA-056 compatibility fix, restoring the
-- pre-fix accuracy this function depended on without reopening the
-- outsider oracle Part 1 closed.
-- =============================================================================

create or replace function public.accept_prediction_connection(
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conn public.prediction_connections%rowtype;
  v_profile public.profiles%rowtype;
  v_mode text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_conn
    from public.prediction_connections
   where token_hash = p_token_hash
   for update;
  if not found then
    raise exception 'prediction connection not found' using errcode = 'no_data_found';
  end if;

  if v_conn.accepted_at is not null then
    raise exception 'prediction connection was already accepted'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if v_conn.revoked_at is not null then
    raise exception 'prediction connection was revoked'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if v_conn.expires_at <= clock_timestamp() then
    raise exception 'prediction connection has expired'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_uid = v_conn.owner_user_id then
    raise exception 'the sharer cannot accept their own prediction connection'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into v_profile
    from public.profiles
   where id = v_conn.profile_id
   for update;
  if not found then
    raise exception 'profile not found' using errcode = 'no_data_found';
  end if;

  -- Issue #518: widened from is_minor alone (re-checked at redemption:
  -- the flag, and now the derived age, can both change between arming and
  -- redemption).
  if public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Issue #636, LLA-056: was `if not public.is_guardian_with_roles(
  -- v_conn.profile_id, v_conn.owner_user_id, array['primary_guardian'])` -
  -- an unlocked read of someone OTHER than the caller's own membership row
  -- through a helper that now refuses to answer for any p_user_id but
  -- auth.uid(). Queries profile_guardians directly instead, matching the
  -- table's own is_guardian_with_roles() definition exactly (status =
  -- 'accepted' and role = 'primary_guardian').
  if not exists (
    select 1 from public.profile_guardians
     where profile_id = v_conn.profile_id
       and user_id = v_conn.owner_user_id
       and status = 'accepted'
       and role = 'primary_guardian'
  ) then
    raise exception 'the sharer is no longer the primary guardian of this profile; the code is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select mode into v_mode
    from public.profile_modes
   where profile_id = v_conn.profile_id;
  if v_mode = 'pregnancy' then
    raise exception 'prediction-only sharing is unavailable while this profile is in Pregnancy mode'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if public.is_profile_guardian(v_conn.profile_id, v_uid) then
    raise exception 'you are already a guardian of this profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if exists (
    select 1 from public.prediction_connections
     where owner_user_id = v_uid
       and recipient_user_id = v_conn.owner_user_id
       and accepted_at is not null
       and revoked_at is null
  ) then
    raise exception 'cannot share and view predictions with the same person at the same time'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  update public.prediction_connections
     set accepted_at = clock_timestamp(),
         recipient_user_id = v_uid
   where id = v_conn.id;

  return jsonb_build_object(
    'profile_id', v_conn.profile_id,
    'profile_name', v_profile.display_name,
    'connection_id', v_conn.id
  );
end;
$$;

comment on function public.accept_prediction_connection(text) is
  'Redeems a prediction-only invite (Issue #151): single-use, expiry- and '
  'revocation-checked, refused for the sharer themself, for an existing '
  'guardian, for a profile whose sharer lost the primary seat, for a '
  'minor''s profile (Issue #373/#518: is_minor OR a birth_year-implied age '
  '<= 18, re-checked at accept), for Pregnancy mode (re-checked at '
  'accept), and for a reciprocal share-with-the-same-person pair. Issue '
  '#636, LLA-056: the sharer''s role is read via a direct, inline '
  'profile_guardians query instead of the shared is_guardian_with_roles() '
  'helper, which no longer answers for anyone but the caller. The '
  'recipient gains exactly one thing: read access to '
  'get_prediction_projection() for this profile.';

revoke all on function public.accept_prediction_connection(text) from public, anon;
grant execute on function public.accept_prediction_connection(text) to authenticated;
