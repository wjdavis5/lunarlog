-- Migration: 20260906120000_account_deletion_final_rehome.sql
-- Issue #17, P1 fix (item 5, 2026-09-06): narrows the residual cross-family
-- data-loss window in account deletion.
--
-- `delete_account_data()`'s day_entries re-home (the P0 fix in
-- 20260905110000_account_deletion.sql) runs exactly once, at the start of
-- that function's own transaction. But the `delete-account` Edge Function
-- (U2) then spends real time afterward - Apple's revocation endpoint round
-- trip when the account has an Apple identity, plus the
-- `auth.admin.deleteUser` call itself - before the caller's `auth.users`
-- row (and day_entries.user_id's `on delete cascade` FK) is actually
-- removed. A stray write from this caller's own device that lands in that
-- gap, on a profile they don't own, would not have been caught by the
-- one-time re-home and would still be destroyed by that cascade the moment
-- the user row goes - a real, if narrow, gap in R7's guarantee (the
-- previous migration's comment already called this out as day_entries
-- ownership being scoped "point-in-time").
--
-- Options considered (see the issue #17 P1 review):
--   (a) Pause/block sync for this account for the duration of the deletion
--       flow. The most complete fix, but it needs a lock/flag the sync
--       engine checks on every push, which is a sync-engine change with its
--       own surface area (What if the client crashes before doing so? Now
--       every account deletion must also carry a "resume sync" story) -
--       too large for this PR.
--   (b) Run a final re-home pass immediately before auth.admin.deleteUser,
--       as close to atomic with that one irreversible step as this
--       shape (an RPC call, then a separate Admin API call) allows. Chosen
--       here: it's a small, self-contained, idempotent addition that
--       shrinks the exposure from however long Apple's round trip takes to,
--       in practice, whatever the Admin API call itself takes - typically
--       well under a second, and with no persistent lock/flag state to get
--       stuck in a bad configuration.
--   (c) Document the residual risk and narrow the window as much as
--       practical. Not a fix on its own, but this migration's approach is
--       (b) with (c)'s honesty about what's left: even after this second
--       call, a write landing in the remaining gap (this RPC's own network
--       round trip, plus the Admin API call after it) could in principle
--       still slip through. Fully closing that would need (a). Tracked as
--       a deliberate, documented residual risk rather than a further
--       expansion of this PR's scope.
--
-- Mechanically: extract the re-home UPDATE out of delete_account_data()
-- into its own SECURITY DEFINER function so the Edge Function can call it a
-- second time on its own, without re-running (or duplicating) everything
-- else delete_account_data() does. delete_account_data() itself is
-- re-declared here (create or replace) to call the extracted function for
-- its step 0 instead of inlining the UPDATE - same behavior, same returned
-- `day_entries_rehomed` count, provably so by the unchanged existing pgTAP
-- assertions in account_deletion_test.sql plus the new ones this migration
-- adds coverage for.
--
-- Per the repo's standing rule, this is a new migration file only; no
-- merged migration is edited in place.
--
-- #17 P1 round 2 fix (2026-09-06, same day, same unmerged PR): the first
-- version of this migration granted EXECUTE on rehome_stray_day_entries()
-- to `authenticated` and had it key off `auth.uid()`, on the theory that it
-- was "just" a second call to the same self-service re-home
-- delete_account_data() already runs as its own step 0. That reasoning
-- missed that `day_entries.user_id` is *excluded* from the ordinary
-- `authenticated` column grant (see 20260903014208_initial_sync_schema.sql)
-- precisely so a caregiver cannot write it directly - this SECURITY DEFINER
-- wrapper reopened exactly that door: ANY authenticated caller, including a
-- guardian already `revoke_guardian`'d off a family, could call it directly
-- naming themselves and re-stamp `last_modified_by_user_id` on that
-- family's `day_entries` rows, bumping `server_version` and waking their
-- Realtime subscribers for a family they no longer have access to -
-- exactly the revocation-bypass class of bug closed elsewhere in this repo
-- (#81/#82). Fixed here (this file is not yet merged, so it is edited in
-- place rather than layered under a further migration) by:
--   * taking an explicit `p_user_id` parameter instead of reading
--     `auth.uid()`, so the function no longer has any notion of "the
--     caller is the subject" for a client to exploit;
--   * revoking `EXECUTE` from `authenticated` (and `anon`/`PUBLIC`)
--     entirely - nobody but the function's owner and `service_role` can
--     call it now;
--   * calling it only from `delete_account_data()`'s own internal
--     (security-definer, so it runs as the owner regardless of grants)
--     call, and from the delete-account Edge Function's service-role
--     client immediately before `auth.admin.deleteUser` - never from
--     client code.

create or replace function public.rehome_stray_day_entries(p_user_id uuid)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rehomed bigint := 0;
begin
  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = 'invalid_parameter_value';
  end if;

  -- Re-home (to the profile's actual owner) any live day_entries
  -- p_user_id logged as a caregiver on a profile they do not own.
  -- Idempotent: a row already re-homed no longer matches
  -- `d.user_id = p_user_id`, so a second call in a row finds nothing left
  -- to move (see the pgTAP coverage below).
  update public.day_entries d
     set user_id = p.user_id,
         last_modified_by_user_id = p_user_id
    from public.profiles p
   where d.profile_id = p.id
     and d.user_id = p_user_id
     and p.user_id <> p_user_id;
  get diagnostics v_rehomed = row_count;

  return v_rehomed;
end;
$$;

comment on function public.rehome_stray_day_entries(uuid) is
  'Re-homes (to the profile''s actual owner) any live day_entries '
  'p_user_id logged as a caregiver on a profile they do not own. '
  'Idempotent - a second call finds nothing left to move. Takes an '
  'explicit p_user_id rather than reading auth.uid(), and EXECUTE is not '
  'granted to authenticated/anon/PUBLIC (#17 P1 round 2 fix): a client-'
  'callable, auth.uid()-keyed version of this function let any '
  'authenticated caller - including a guardian already revoked from a '
  'family - re-stamp last_modified_by_user_id on that family''s '
  'day_entries rows, a revocation-bypass class of bug this repo already '
  'closed elsewhere (#81/#82). Called only from delete_account_data()''s '
  'own internal (security-definer) call as its step 0, and, standalone, '
  'from the delete-account Edge Function''s service-role client '
  'immediately before auth.admin.deleteUser, to narrow the window between '
  'the row-deletion RPC and the actual auth.users removal in which a '
  'stray write could otherwise still be reached by that row''s '
  'on-delete-cascade (#17 P1 item 5 - see this migration''s header for '
  'the residual risk that remains even so).';

revoke all on function public.rehome_stray_day_entries(uuid) from public, anon, authenticated;

-- Re-point delete_account_data()'s step 0 at the shared function above
-- instead of duplicating its UPDATE inline. No behavior change: same
-- predicate, same returned count.
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
    'day_entries_rehomed', v_day_entries_rehomed,
    'guardian_invitations', v_invitations_deleted,
    'profile_guardians', v_guardians_deleted,
    'profiles', v_profiles_deleted,
    'settings', v_settings_deleted
  );
end;
$$;

comment on function public.delete_account_data() is
  'Deletes every row the calling user (auth.uid()) owns across profiles, '
  'day_entries, settings, profile_guardians and guardian_invitations, '
  'first calling public.rehome_stray_day_entries(auth.uid()) to re-home '
  'any day_entries this caller logged as a caregiver on a profile they do '
  'not own, so the auth.users on delete cascade the Edge Function '
  'triggers afterwards cannot reach them (#17 P0 fix). That call runs as '
  'this function''s own security-definer owner, so it succeeds regardless '
  'of rehome_stray_day_entries()''s own (revoked, #17 P1 round 2 fix) '
  'grants. Takes no parameters itself - the caller is always the subject, '
  'so no other account can be named in the call. Called by the '
  'delete-account Edge Function before it revokes Apple and deletes the '
  'auth.users row (#17 KTD1/KTD4); that same function calls '
  'rehome_stray_day_entries() a second time, standalone, on its '
  'service-role client with an explicit p_user_id, immediately before the '
  'auth.users deletion (#17 P1 item 5; round 2 fix).';

revoke all on function public.delete_account_data() from public, anon;
grant execute on function public.delete_account_data() to authenticated;
