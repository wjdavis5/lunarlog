-- Migration: 20260906170000_ownership_transfers.sql
-- Plan 2026-09-06-001 (Issue #4), Unit U2: the ownership_transfers table and
-- two structural invariants this feature needs (R6, R8, R22).
--
-- 1. public.ownership_transfers - a dedicated table (KTD2) rather than a flag
--    on guardian_invitations, since that table's role CHECK forbids the
--    role a transfer must grant (primary_guardian) and a transfer carries a
--    field (parent_post_transfer_role) an invitation has no place for. Same
--    proven shape as guardian_invitations: SHA-256 hex token_hash unique,
--    plaintext never stored, server-computed expires_at, accepted_at/
--    accepted_by/cancelled_at in place of a status column.
-- 2. ownership_transfers_one_live_uq (KTD6): at most one outstanding,
--    unresolved transfer per profile. now() is not immutable, so the
--    predicate cannot reference expiry directly - U3's
--    create_ownership_transfer instead cancels the caller's own
--    outstanding-but-expired row before inserting a new one.
-- 3. profile_guardians_one_primary_uq (KTD5, R22): exactly one accepted
--    primary_guardian per profile at every committed state. Nothing enforced
--    this before - this feature is the first operation able to promote an
--    arbitrary account into that role, so the invariant becomes structural
--    here. The migration asserts the existing data satisfies it first and
--    raises loudly (naming the offending profile ids) if it does not, rather
--    than silently half-applying.
--
-- Filename ordering: sorts after 20260906160000 (U1), before 20260906180000
-- (U3, which depends on this table).

-- ---------------------------------------------------------------------------
-- 1. ownership_transfers table
-- ---------------------------------------------------------------------------

create table public.ownership_transfers (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  initiated_by uuid not null
    references auth.users (id) on delete cascade,
  token_hash text not null unique
    constraint ownership_transfers_token_hash_check
    check (token_hash ~ '^[0-9a-f]{64}$'),
  parent_post_transfer_role text not null
    constraint ownership_transfers_parent_role_check
    check (parent_post_transfer_role in ('co_parent', 'viewer')),
  recipient_label text
    constraint ownership_transfers_recipient_label_check
    check (recipient_label is null or char_length(recipient_label) <= 80),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid
    references auth.users (id) on delete set null,
  cancelled_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.ownership_transfers is
  'Single-use expiring tokens (SHA-256 hashed) that hand a profile''s
   ownership from its accepted primary_guardian to another account (Issue
   #4). Every mutation goes through the SECURITY DEFINER RPCs in
   20260906180000_ownership_transfer_rpcs.sql - there is no INSERT, UPDATE,
   or DELETE policy or grant for authenticated.';

create index ownership_transfers_profile_id_idx on public.ownership_transfers (profile_id);
create index ownership_transfers_token_hash_idx on public.ownership_transfers (token_hash);

-- KTD6: at most one live (unresolved) transfer per profile. now() is not
-- immutable, so this cannot also require expires_at > now() - an expired,
-- never-cancelled row still counts as "live" for this index, and
-- create_ownership_transfer cancels the caller's own such row before
-- inserting a fresh one (a deliberate cancel-then-create).
create unique index ownership_transfers_one_live_uq
  on public.ownership_transfers (profile_id)
  where accepted_at is null and cancelled_at is null;

-- ---------------------------------------------------------------------------
-- 2. Row-Level Security
-- ---------------------------------------------------------------------------

alter table public.ownership_transfers enable row level security;
alter table public.ownership_transfers force row level security;

-- Select-only: the arming parent, or any accepted primary_guardian of the
-- profile (covers the case where the transfer is being re-checked from a
-- second device, or a co-parent who is not the arming primary_guardian -
-- excluded, matching R6's "only the primary guardian can arm" scope).
-- Deliberately no policy admits a holder of the raw token: an invitee must
-- not be able to read this row through PostgREST before calling the
-- acceptance RPC, exactly like guardian_invitations.
create policy "ownership_transfers_select" on public.ownership_transfers
  for select to authenticated
  using (
    initiated_by = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian'])
  );

-- No INSERT, UPDATE, or DELETE policy: every transfer mutation
-- (create/cancel/accept) runs through U3's SECURITY DEFINER RPCs, which
-- enforce R6 (only the accepted primary_guardian can arm), R7 (a valid
-- post-transfer role), R8 (a bounded TTL), R9 (only the arming parent can
-- cancel), and R11/R18/R20 (acceptance's many prerequisite checks) - none of
-- which a `with check` clause here could express, since it can only
-- constrain the calling role, never arbitrary business rules about the row
-- being written.

-- ---------------------------------------------------------------------------
-- 3. Privileges
-- ---------------------------------------------------------------------------

revoke all on table public.ownership_transfers from public, anon, authenticated;
grant select on table public.ownership_transfers to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Realtime - deliberately excluded (KTD11 / this table's own comment).
-- ownership_transfers carries a token hash and must never cross the
-- websocket. It is not added to the supabase_realtime publication here, and
-- a future Studio "Enable Realtime" toggle on this table would be reverted
-- by public.reconcile_realtime_publication() the next time
-- 20260905100000_realtime_publication.sql's migration file runs (a from-
-- scratch db reset) - see that migration and AGENTS.md's note on the
-- periodic-reconciliation follow-up for the gap between deploys.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 5. R22: exactly one accepted primary_guardian per profile, made structural.
-- This feature (U3's accept_ownership_transfer) is the first operation able
-- to promote an arbitrary account into primary_guardian, so the invariant
-- that was previously only a convention (revoke_guardian merely counts
-- primaries at self-leave time) becomes a partial unique index here. Assert
-- the existing data satisfies it before creating the index, and fail loudly
-- - naming the offending profile ids - if it does not, rather than
-- half-applying a structural guarantee.
-- ---------------------------------------------------------------------------

do $$
declare
  v_bad text[];
begin
  select array_agg(profile_id) into v_bad
    from (
      select profile_id
        from public.profile_guardians
       where role = 'primary_guardian' and status = 'accepted'
       group by profile_id
      having count(*) > 1
    ) s;

  if v_bad is not null then
    raise exception 'R22 pre-flight failed: profiles with multiple accepted primary guardians: %', v_bad
      using errcode = 'integrity_constraint_violation';
  end if;
end $$;

create unique index profile_guardians_one_primary_uq
  on public.profile_guardians (profile_id)
  where role = 'primary_guardian' and status = 'accepted';

comment on index public.profile_guardians_one_primary_uq is
  'R22: a profile has exactly one accepted primary_guardian at every
   committed state. Structural as of Issue #4 (ownership transfer) - the
   first operation able to promote an arbitrary account into this role.
   accept_ownership_transfer demotes the outgoing parent before promoting
   the incoming owner (see that RPC) so this index is never transiently
   violated mid-transaction.';
