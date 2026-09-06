-- Migration: 20260906180000_ownership_transfer_rpcs.sql
-- Plan 2026-09-06-001 (Issue #4), Unit U3: create_ownership_transfer,
-- cancel_ownership_transfer, accept_ownership_transfer, and a one-case
-- widening of enforce_day_entry_attribution() (KTD4).
--
-- Lock order across this file's RPCs matches the existing invitation/
-- membership RPCs (accept_guardian_invitation, revoke_guardian): the
-- transfer row first, then profiles, then profile_guardians - so this
-- family of RPCs cannot deadlock against that one under concurrent calls.
--
-- KTD4 in full: the day_entries re-home in accept_ownership_transfer must
-- move day_entries.user_id (a cascade anchor - see
-- 20260906120000_account_deletion_final_rehome.sql's header for how that
-- column already gets special re-home treatment elsewhere) without
-- restamping last_modified_by_user_id, which would falsify "Modified by
-- Mom" across every historical entry and break R16.
-- enforce_day_entry_attribution() therefore grows exactly one new permitted
-- case: an UPDATE is allowed when a transaction-local GUC
-- (lunarlog.ownership_transfer) is 'on' AND every column of the row except
-- user_id is byte-identical before and after. set_config() lives in
-- pg_catalog, is not a PostgREST-reachable RPC, and this GUC is set only by
-- accept_ownership_transfer below (transaction-local: the third argument to
-- set_config is `true`) - so `authenticated` cannot arm this bypass
-- directly, and even a hypothetical leak of the GUC could not forge
-- attribution, since the second conjunct forbids changing anything but the
-- one column this whole feature exists to move.
--
-- Fix-forward from the plan's Approach sketch: that text scoped the
-- day_entries re-home to `where user_id = v_transfer.initiated_by`, which
-- would skip any entry a caregiver logged (their own user_id, not the
-- parent's). R15 ("for every entry on the profile") and AE1 ("all 400
-- carry user_id = B") are explicit that every entry moves, not only the
-- ones the outgoing parent happened to hold - Product Contract requirements
-- and acceptance examples outrank an Implementation Unit's own SQL sketch
-- per this plan's stated authority hierarchy. accept_ownership_transfer
-- below re-homes every day_entries row on the profile.

-- ---------------------------------------------------------------------------
-- 1. enforce_day_entry_attribution(): the KTD4 bypass case
-- ---------------------------------------------------------------------------

create or replace function public.enforce_day_entry_attribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    return new;
  end if;
  if tg_op = 'INSERT' then
    -- NULL attribution (legacy rows, direct inserts) is allowed; a value
    -- other than the caller's own uid is a forgery.
    if (new.logged_by_user_id is not null
          and new.logged_by_user_id is distinct from v_uid)
       or (new.last_modified_by_user_id is not null
             and new.last_modified_by_user_id is distinct from v_uid) then
      raise exception 'attribution columns are server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
  else
    -- KTD4: ownership-transfer re-home bypass. Permitted only when the
    -- transaction-local GUC is on AND every column but user_id is
    -- unchanged - so this path can move the cascade anchor and nothing
    -- else, never attribution. See this migration's header for the full
    -- reasoning and why `authenticated` cannot reach this GUC.
    if current_setting('lunarlog.ownership_transfer', true) = 'on'
       and (to_jsonb(new) - 'user_id') is not distinct from (to_jsonb(old) - 'user_id') then
      return new;
    end if;

    if new.logged_by_user_id is distinct from old.logged_by_user_id then
      raise exception 'logged_by_user_id is server-authoritative'
        using errcode = 'insufficient_privilege';
    end if;
    if new.last_modified_by_user_id is distinct from v_uid then
      raise exception 'last_modified_by_user_id must be the calling user'
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;

comment on function public.enforce_day_entry_attribution() is
  'BEFORE INSERT/UPDATE guard on day_entries: attribution columns are
   server-authoritative for every path except accept_ownership_transfer''s
   re-home (KTD4, Issue #4), which sets a transaction-local GUC
   (lunarlog.ownership_transfer) and changes only user_id. authenticated
   holds no surface that can set that GUC.';

revoke execute on function public.enforce_day_entry_attribution() from public, anon;

-- ---------------------------------------------------------------------------
-- 2. create_ownership_transfer
-- ---------------------------------------------------------------------------

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
  v_transfer_id uuid;
  v_ttl int;
  v_now timestamptz;
  v_expires_at timestamptz;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- R6: only the accepted primary_guardian can arm a transfer. A co-parent
  -- cannot, even though co-parents can edit profile metadata elsewhere.
  if not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian']) then
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
  -- deliberate cancel-then-create: close out the caller's own
  -- outstanding-but-expired row for this profile before inserting.
  update public.ownership_transfers
     set cancelled_at = clock_timestamp()
   where profile_id = p_profile_id
     and initiated_by = v_uid
     and accepted_at is null
     and cancelled_at is null
     and expires_at <= clock_timestamp();

  v_now := clock_timestamp();
  v_expires_at := v_now + (v_ttl || ' hours')::interval;

  -- A still-live (unexpired, un-superseded) transfer for this profile
  -- violates ownership_transfers_one_live_uq here (R6) - the index is the
  -- backstop, this function is the friendly error path for everything else.
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

revoke all on function public.create_ownership_transfer(text, text, text, text, int) from public, anon;
grant execute on function public.create_ownership_transfer(text, text, text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. cancel_ownership_transfer
-- ---------------------------------------------------------------------------

create or replace function public.cancel_ownership_transfer(
  p_transfer_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_transfer public.ownership_transfers%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into v_transfer
    from public.ownership_transfers
   where id = p_transfer_id
   for update;

  if not found then
    raise exception 'transfer not found' using errcode = 'no_data_found';
  end if;

  -- R9: only the arming parent can cancel. Not the profile's other
  -- guardians, not a co-parent, not the recipient (who has no read access
  -- to this row anyway - see the SELECT policy).
  if v_transfer.initiated_by <> v_uid then
    raise exception 'only the arming parent can cancel this transfer'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent: an already-terminal row (accepted or already cancelled)
  -- returns true without a further write, matching revoke_guardian's
  -- idempotency on an already-revoked target.
  if v_transfer.accepted_at is null and v_transfer.cancelled_at is null then
    update public.ownership_transfers
       set cancelled_at = clock_timestamp()
     where id = p_transfer_id;
  end if;

  return true;
end;
$$;

revoke all on function public.cancel_ownership_transfer(uuid) from public, anon;
grant execute on function public.cancel_ownership_transfer(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. accept_ownership_transfer
-- ---------------------------------------------------------------------------

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

  -- R11: the arming parent cannot accept their own transfer.
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

  -- Stale-link guards: the armer must still be both the owner and the
  -- accepted primary_guardian at accept time. Either can have changed since
  -- arming (a second transfer accepted in the meantime, a revocation, a
  -- role change) - refuse rather than complete a handover from an account
  -- that no longer actually holds the profile.
  if v_profile.user_id is distinct from v_transfer.initiated_by then
    raise exception 'the arming parent no longer owns this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if not public.is_guardian_with_roles(v_transfer.profile_id, v_transfer.initiated_by, array['primary_guardian']) then
    raise exception 'the arming parent is no longer the primary guardian of this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Review item #1 (P0), acceptor-freshness check: the mirror of
  -- accept_guardian_invitation's #82 guard, applied to the acceptor rather
  -- than the arming parent. revoke_guardian (below) now cancels every live
  -- transfer for a profile the moment any guardian on it is revoked, but a
  -- transfer row revoked before that fix existed, or a race between the two
  -- calls, must not leave a back door: if the accepting user already holds a
  -- *revoked* profile_guardians row for this profile, and this transfer's
  -- created_at predates that revocation, the token is stale and must be
  -- refused - exactly as a stale guardian_invitations token is. A transfer
  -- armed *after* the revocation (a deliberate handover to someone
  -- previously removed) still works, matching #82's carve-out.
  select * into v_existing
    from public.profile_guardians
   where profile_id = v_transfer.profile_id
     and user_id = v_uid
   for update;

  if found and v_existing.status = 'revoked' then
    if v_existing.revoked_at is null or v_transfer.created_at <= v_existing.revoked_at then
      raise exception 'guardian access to this profile was revoked; a new transfer link is required'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end if;

  -- KTD4: arm the transaction-local bypass so the re-home below can move
  -- day_entries.user_id without restamping attribution. Set exactly once,
  -- transaction-local (third arg true), and never read back or exposed.
  perform set_config('lunarlog.ownership_transfer', 'on', true);

  -- R12: profiles.user_id moves to the accepting user; transferred_at is
  -- stamped. updated_at must move strictly forward (clock_timestamp(), not
  -- now()) or a client's own LWW comparison could discard this pulled row
  -- as stale; server_version advances via the existing
  -- profiles_set_server_version trigger.
  update public.profiles
     set user_id = v_uid,
         transferred_at = clock_timestamp(),
         updated_at = greatest(updated_at, clock_timestamp())
   where id = v_transfer.profile_id;

  -- R15/R16/R17: re-point the cascade anchor for EVERY entry on the
  -- profile, not only the ones currently anchored to the arming parent.
  -- day_entries.user_id already means "the profile's actual owner"
  -- elsewhere in this schema (see rehome_stray_day_entries() and its
  -- callers) - a caregiver's own logged entry on a shared profile can carry
  -- day_entries.user_id = that caregiver (stamped from auth.uid() at insert
  -- by sync_push) until something re-homes it, and R15/AE1 are explicit
  -- that ALL of a profile's entries carry the new owner's user_id after a
  -- transfer, not just the subset the outgoing parent happened to hold. No
  -- other column is named, which is what satisfies the attribution guard's
  -- second conjunct - logged_by_user_id and last_modified_by_user_id (and
  -- every other column) are untouched on every row this UPDATE reaches,
  -- including a caregiver's rows swept up by this broader predicate.
  update public.day_entries
     set user_id = v_uid
   where profile_id = v_transfer.profile_id;
  get diagnostics v_day_entries_rehomed = row_count;

  -- R14: demote the parent to their chosen role BEFORE promoting the child,
  -- so profile_guardians_one_primary_uq (R22) is never transiently violated
  -- by two accepted primary_guardian rows existing at once.
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

  -- R18: single-use. Mark accepted so a second presentation of the same
  -- token is refused by the accepted_at check above.
  update public.ownership_transfers
     set accepted_at = clock_timestamp(),
         accepted_by = v_uid
   where id = v_transfer.id;

  -- Any other still-live transfer for this profile is now moot - the
  -- profile has a new owner. Cancel rather than leave dangling.
  update public.ownership_transfers
     set cancelled_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and id <> v_transfer.id
     and accepted_at is null
     and cancelled_at is null;

  -- Review item #4 (P1): the ex-parent's own still-live guardian invitations
  -- for this profile are decisions made under an ownership that no longer
  -- holds. guardian_invitations carries no invitee identity (see #81's
  -- rationale in 20260905090000_close_guardian_revocation_bypass.sql), so
  -- there is no way to tell which of them the new owner would still want
  -- honored - the safe default, matching #81, is to cancel every still-live
  -- one for the profile rather than leave a side door the new owner never
  -- consented to. A co_parent's own invite permission (create_guardian_invitation's
  -- R3) means this is not limited to invitations the arming parent personally
  -- sent, same as #81's own scope.
  update public.guardian_invitations
     set revoked_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and accepted_at is null
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
  'Single SECURITY DEFINER transaction (KTD3): moves profiles.user_id and
   the accepted primary_guardian membership to the accepting user, demotes
   the arming parent to their chosen role, re-homes day_entries.user_id via
   the KTD4 attribution-guard bypass, and marks the transfer single-use.
   Commits together or not at all - a client-orchestrated multi-call
   sequence could otherwise strand a profile with zero or two primary
   guardians mid-handover.';

revoke all on function public.accept_ownership_transfer(text, text, text) from public, anon;
grant execute on function public.accept_ownership_transfer(text, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. revoke_guardian - cancel the profile's live ownership transfers too
--    (review item #1, P0)
-- ---------------------------------------------------------------------------
--
-- Fix-forward per the "do not edit a merged migration in place" rule: this
-- function was last defined (with the #81/#82 fixes) in
-- 20260905090000_close_guardian_revocation_bypass.sql, which predates this
-- feature and is already merged - so this is a `create or replace`, not an
-- edit to that file. Full body carried forward verbatim other than the one
-- new block called out inline below.
--
-- Without this, a revoked guardian who holds (or later obtains) the raw
-- token of a still-live ownership transfer for the profile could call
-- accept_ownership_transfer and become the profile's sole owner - the
-- revocation closed their membership but left the transfer row untouched.
-- ownership_transfers has no invitee identity either (same as
-- guardian_invitations - see #81 below), so the safe default mirrors #81
-- exactly: cancel every still-live transfer for the profile whenever any
-- revocation happens on it, not just one provably addressed to the revoked
-- user. accept_ownership_transfer's own acceptor-freshness check (this
-- migration, section 4) is the defence-in-depth backstop for a transfer
-- revoked before this fix existed, or a race between the two calls.
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

  -- Review item #1 (P0): close the ownership-transfer bypass. This update
  -- runs first, ahead of the guardian_invitations and profile_guardians
  -- updates below, so the lock order here - ownership_transfers, then
  -- guardian_invitations, then profile_guardians - matches
  -- accept_ownership_transfer's own order (transfer row, then profiles,
  -- then profile_guardians; see this migration's header) and the two RPCs
  -- cannot deadlock against each other.
  update public.ownership_transfers
     set cancelled_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and cancelled_at is null;

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

comment on function public.revoke_guardian(text, uuid) is
  'Revokes a guardian''s membership and, in the same transaction, cancels
   every still-live guardian_invitations row (#81) and ownership_transfers
   row (Issue #4 review item #1) for the profile - both invitation and
   transfer tokens carry no invitee identity, so neither can be reliably
   tied to the revoked user before redemption, and the safe default is to
   close every outstanding door whenever any revocation happens on the
   profile.';

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;
