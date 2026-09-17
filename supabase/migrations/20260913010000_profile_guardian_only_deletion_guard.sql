-- Migration: 20260913010000_profile_guardian_only_deletion_guard.sql
--
-- Issue #517 (P1): a co-parent can soft-delete or archive a profile via a
-- direct PostgREST PATCH, bypassing sync_push's "only primary_guardian can
-- delete or archive profile" rule (20260912000000:396-399).
--
-- Investigated fix option "drop archived_at/deleted_at/is_minor from the
-- authenticated UPDATE grant" and rejected it: public.sync_push is declared
-- `security invoker` (verified: 20260912000000_health_sync_export_marker.sql:70),
-- NOT security definer, so its own UPDATE statements on public.profiles run
-- under the calling user's privileges and NEED the column grant to write
-- archived_at/deleted_at/is_minor at all. Dropping the grant would break
-- sync_push's own (already-authorized) primary_guardian delete/archive
-- path, not just the raw-PATCH bypass. So this migration takes the other
-- option the issue offers: a BEFORE UPDATE trigger, following the
-- enforce_guardian_invitation_revocation_terminal() pattern
-- (20260906180000_ownership_transfer_rpcs.sql:641-656) - a SECURITY
-- DEFINER trigger function that re-checks the same authority rule
-- regardless of which code path (sync_push or a raw PATCH) is doing the
-- writing.
--
-- Scope: only archived_at and deleted_at are gated here, matching the
-- issue title and sync_push's own rule verbatim ("only primary_guardian can
-- delete or archive profile"). is_minor is deliberately NOT restricted to
-- primary_guardian by this trigger: sync_push already allows any
-- primary_guardian OR co_parent to write is_minor as ordinary profile
-- metadata (20260912000000:389-393, "Only primary_guardian or co_parent
-- can edit profile metadata"), and profiles_update_guardians' RLS policy
-- already enforces that ladder (co_parent/primary_guardian only - a
-- caregiver or viewer cannot UPDATE the row at all). Widening is_minor to
-- primary_guardian-only here would silently change that established,
-- tested behavior. Issue #518 separately closes the is_minor durability
-- gap (a BEFORE UPDATE trigger revoking live prediction_connections when
-- is_minor flips false -> true) without touching who may set it.
--
-- The trigger fires for EVERY update on public.profiles, including
-- sync_push's own (security invoker, so auth.uid() is the real caller
-- there too) and migrations/service-role writes (auth.uid() is null in
-- both cases, exempted below - mirrors the day_entries/guardian_invitations
-- attribution guards' own migrations/service-role carve-out). For a
-- legitimate primary_guardian delete/archive - via sync_push or a raw
-- PATCH the RLS policy already allows - the check passes and is a no-op;
-- it only blocks a co_parent (or, defensively, anyone without an accepted
-- profile_guardians row at all, which RLS should already have refused).
--
-- Coverage: supabase/tests/profile_guardian_only_deletion_test.sql.

create or replace function public.enforce_profile_guardian_only_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
begin
  -- Migrations and service-role writes (no JWT) are exempt, matching every
  -- other attribution/authorization guard in this schema.
  if v_uid is null then
    return new;
  end if;

  if new.archived_at is distinct from old.archived_at
     or new.deleted_at is distinct from old.deleted_at then
    select role into v_caller_role
      from public.profile_guardians
     where profile_id = new.id
       and user_id = v_uid
       and status = 'accepted';

    if v_caller_role is distinct from 'primary_guardian' then
      raise exception 'only primary_guardian can delete or archive profile'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  return new;
end;
$$;

comment on function public.enforce_profile_guardian_only_deletion() is
  'BEFORE UPDATE guard on profiles (Issue #517): archived_at/deleted_at may '
  'only change when the caller holds an ACCEPTED primary_guardian '
  'membership on the row being updated - the same rule sync_push already '
  'enforces in its own profile branch, now applied structurally so a raw '
  'PostgREST PATCH by a co_parent (or anyone else the profiles_update_guardians '
  'RLS policy lets touch the row at all) cannot bypass it. Exempt when '
  'auth.uid() is null (migrations, service role). is_minor is deliberately '
  'untouched here - see this migration''s header.';

create trigger profiles_guardian_only_deletion_guard
  before update on public.profiles
  for each row execute function public.enforce_profile_guardian_only_deletion();

revoke execute on function public.enforce_profile_guardian_only_deletion() from public, anon;
