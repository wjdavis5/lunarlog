-- Migration: 20260908100000_ownership_transfers_token_hash_unreadable.sql
-- Implements Issue #242: ownership_transfers.token_hash is table-readable.
-- Mirrors 20260908000000_guardian_invitations_token_hash_unreadable.sql
-- (issue #114, PR #219) onto the ownership-transfer table.
--
-- The attack: `ownership_transfers` carries a table-wide
-- `grant select ... to authenticated`
-- (20260906170000_ownership_transfers.sql, Privileges section), and the
-- `ownership_transfers_select` RLS policy admits the arming parent
-- (initiated_by = auth.uid()) plus any accepted primary_guardian of the
-- profile - a set evaluated at read time, not frozen at arm time. The
-- stored hash *is* the credential - `accept_ownership_transfer(p_token_hash)`
-- compares the client-supplied hash directly, so possession of the hash
-- alone is sufficient to redeem a transfer and move ownership of the
-- profile (and every entry on it) to the caller's account. Any account
-- admitted by that policy could therefore `select token_hash` on a
-- still-live transfer and redeem it, without ever holding the raw token
-- the arming parent delivered out-of-band.
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
-- - create_ownership_transfer / cancel_ownership_transfer /
--   accept_ownership_transfer are SECURITY DEFINER and run as the function
--   owner, which is the table owner - column grants on `authenticated`
--   never apply to them (proven by the full transfer lifecycle in
--   ownership_transfer_test.sql). revoke_guardian's cancellation update on
--   this table (20260906240000) and delete_account_data() are SECURITY
--   DEFINER for the same reason.
-- - The one client read path, SupabaseOwnershipTransferService.
--   getActiveTransfer (lib/data/sharing/supabase_ownership_transfer_service.dart),
--   selects an explicit column list that excludes token_hash and filters
--   only on granted columns (profile_id, accepted_at, cancelled_at,
--   expires_at), so it keeps working unchanged.
-- - RLS is untouched: the `ownership_transfers_select` policy's own
--   expressions reference only granted columns (initiated_by, profile_id),
--   and policy quals are not subject to the caller's column grants in any
--   case.
-- - service_role keeps its default-privilege table-wide grant; this revoke
--   targets `authenticated` only.

revoke select on table public.ownership_transfers from authenticated;

grant select (
  id,
  profile_id,
  initiated_by,
  parent_post_transfer_role,
  recipient_label,
  expires_at,
  accepted_at,
  accepted_by,
  cancelled_at,
  created_at
) on table public.ownership_transfers to authenticated;
