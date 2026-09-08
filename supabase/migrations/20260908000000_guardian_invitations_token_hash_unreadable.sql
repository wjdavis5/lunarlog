-- Migration: 20260908000000_guardian_invitations_token_hash_unreadable.sql
-- Implements Issue #114: guardian_invitations.token_hash is table-readable.
--
-- The attack: `guardian_invitations` carries a table-wide
-- `grant select ... to authenticated`
-- (20260904010000_multi_guardian_schema.sql, Privileges section), and the
-- `guardian_invitations_select` RLS policy admits every accepted
-- primary_guardian / co_parent of the profile (plus the row's inviter). The
-- stored hash *is* the credential - `accept_guardian_invitation(p_token_hash)`
-- compares the client-supplied hash directly, so possession of the hash alone
-- is sufficient to redeem an invitation. Any guardian admitted by that policy
-- could therefore `select token_hash` on a still-live invitation intended for
-- someone else and redeem it before the intended recipient, without ever
-- holding the raw token.
--
-- The fix: reading the table must never yield a redeemable credential. The
-- table-wide SELECT is revoked and re-granted on every column except
-- token_hash. Referencing a column anywhere in a query (projection, filter,
-- or `*` expansion) requires SELECT privilege on it, so an `authenticated`
-- session can neither read the hash nor even use it as a WHERE-clause
-- comparison oracle; a full-row `select *` fails closed with 42501 because
-- `*` expands to every column including the ungranted one.
--
-- Nothing else changes semantics:
-- - create_guardian_invitation / accept_guardian_invitation /
--   revoke_guardian(_invitation) are SECURITY DEFINER and run as the function
--   owner, which is the table owner - column grants on `authenticated` never
--   apply to them (proven by the full invitation lifecycle in
--   profile_guardians_rls_test.sql).
-- - The one client read path, SupabaseSharingService.listPendingInvites
--   (lib/data/sharing/supabase_sharing_service.dart), selects an explicit
--   column list that excludes token_hash and filters only on granted columns
--   (accepted_at, revoked_at, expires_at), so it keeps working unchanged.
-- - RLS is untouched: the `guardian_invitations_select` policy's own
--   expressions reference only granted columns (invited_by, profile_id), and
--   policy quals are not subject to the caller's column grants in any case.
-- - service_role keeps its default-privilege table-wide grant; this revoke
--   targets `authenticated` only.

revoke select on table public.guardian_invitations from authenticated;

grant select (
  id,
  profile_id,
  invited_by,
  role,
  recipient_label,
  expires_at,
  accepted_at,
  accepted_by,
  revoked_at,
  created_at
) on table public.guardian_invitations to authenticated;
