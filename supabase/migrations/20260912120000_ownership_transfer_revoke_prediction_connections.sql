-- Migration: 20260912120000_ownership_transfer_revoke_prediction_connections.sql
-- Issue #496: accept_ownership_transfer must revoke active prediction
-- connections and pending invites for the profile.
--
-- Prior behavior:
-- When accept_ownership_transfer completed, it moved profiles.user_id to the
-- child/acceptor, demoted the parent, cancelled outstanding ownership_transfers,
-- and revoked pending guardian_invitations. However, prediction_connections
-- (Issue #151) was not touched. Any active prediction connection created by
-- the arming parent survived, allowing external prediction recipients to
-- continue calling get_prediction_projection() for the child's future periods,
-- fertile window, and PMS days without the child's consent or awareness.
-- Any pending unaccepted prediction invite tokens also remained redeemable.
--
-- Fix:
-- In accept_ownership_transfer, update public.prediction_connections setting
-- revoked_at = clock_timestamp() for all rows on the profile where revoked_at
-- is null. The existing prediction_connections_projection_gc AFTER trigger
-- automatically deletes the profile's published prediction_projections snapshot
-- in the same transaction, immediately severing recipient access.

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
  -- Issue #296: transferred_to_user_id is stamped with the same accepting
  -- uid, in the same statement, so the profile row itself carries WHO the
  -- last transfer targeted - the signal the client-side health-sync minor
  -- gate (#153) requires (`transferredToUserId == signedInUserId`) before
  -- a transferred minor profile may bind. Server-owned like
  -- transferred_at: no client grant, no sync_push write path.
  update public.profiles
     set user_id = v_uid,
         transferred_at = clock_timestamp(),
         transferred_to_user_id = v_uid,
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

  -- Issue #496: the ex-parent's live prediction connections for this profile
  -- must be revoked upon transfer. Prediction connections give access to
  -- derived cycle predictions (period, fertile window, PMS days), which the
  -- child (now sole primary guardian and owner) must have sole control over.
  -- The prediction_connections_projection_gc trigger fires per revoked row
  -- and clears profile_prediction_projections in the same transaction.
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
  'Single SECURITY DEFINER transaction (KTD3): moves profiles.user_id and
   the accepted primary_guardian membership to the accepting user, demotes
   the arming parent to their chosen role, re-homes day_entries.user_id via
   the KTD4 attribution-guard bypass, marks the transfer single-use,
   revokes outstanding guardian invitations, and (Issue #496) revokes all
   active and pending prediction connections for the profile.
   Commits together or not at all - a client-orchestrated multi-call
   sequence could otherwise strand a profile with zero or two primary
   guardians mid-handover.';

revoke all on function public.accept_ownership_transfer(text, text, text) from public, anon;
grant execute on function public.accept_ownership_transfer(text, text, text) to authenticated;
