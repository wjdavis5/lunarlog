-- Migration: 20260904010000_multi_guardian_schema.sql
-- Implements Issue #8: Multi-parent / co-caregiver support for shared child profiles
-- 1. Uncouple profiles.id and add unique constraint on profiles(id).
-- 2. Create public.profile_guardians join table with role and status constraints.
-- 3. Backfill existing profiles into profile_guardians as primary_guardian.
-- 4. Create trigger profiles_after_insert_guardian on public.profiles.
-- 5. Create security definer helper functions for RLS membership checks.
-- 6. Create public.guardian_invitations table for pairing tokens.
-- 7. Add logged_by_user_id and last_modified_by_user_id to public.day_entries.
-- 8. Refactor day_entries foreign key to public.profiles(id) directly.
-- 9. Refactor day_entries unique live index to (profile_id, local_date).
-- 10. Update Row-Level Security (RLS) policies on profiles, day_entries, profile_guardians, and guardian_invitations.
-- 11. Configure column-level privileges.

-- ---------------------------------------------------------------------------
-- 1. profiles unique constraint on id
-- ---------------------------------------------------------------------------

alter table public.profiles
  add constraint profiles_id_uq unique (id);

-- ---------------------------------------------------------------------------
-- 2. profile_guardians table
-- ---------------------------------------------------------------------------

create table public.profile_guardians (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  user_id uuid not null
    references auth.users (id) on delete cascade,
  role text not null
    constraint profile_guardians_role_check
    check (role in ('primary_guardian', 'co_parent', 'caregiver', 'viewer')),
  status text not null default 'accepted'
    constraint profile_guardians_status_check
    check (status in ('pending', 'accepted', 'revoked')),
  display_name text
    constraint profile_guardians_display_name_check
    check (display_name is null or char_length(display_name) <= 80),
  invited_by uuid
    references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_version bigint not null default 0,
  unique (profile_id, user_id)
);

comment on table public.profile_guardians is
  'Links authenticated users to profiles with granular roles (primary_guardian, co_parent, caregiver, viewer).';

create index profile_guardians_profile_id_idx on public.profile_guardians (profile_id);
create index profile_guardians_user_id_idx on public.profile_guardians (user_id);
create index profile_guardians_user_status_idx on public.profile_guardians (user_id, status);
create index profile_guardians_user_server_version_idx on public.profile_guardians (user_id, server_version);

create trigger profile_guardians_set_server_version
  before insert or update on public.profile_guardians
  for each row execute function public.set_server_version();

-- ---------------------------------------------------------------------------
-- 3. Backfill existing profiles into profile_guardians
-- ---------------------------------------------------------------------------

insert into public.profile_guardians (profile_id, user_id, role, status)
select id, user_id, 'primary_guardian', 'accepted'
from public.profiles
on conflict (profile_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- 4. AFTER INSERT trigger on public.profiles
-- ---------------------------------------------------------------------------

create or replace function public.on_profile_created_add_guardian()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profile_guardians (profile_id, user_id, role, status)
  values (new.id, new.user_id, 'primary_guardian', 'accepted')
  on conflict (profile_id, user_id) do nothing;
  return new;
end;
$$;

comment on function public.on_profile_created_add_guardian() is
  'Automatically adds creator as primary_guardian in profile_guardians whenever a profile is inserted.';

create trigger profiles_after_insert_guardian
  after insert on public.profiles
  for each row execute function public.on_profile_created_add_guardian();

-- ---------------------------------------------------------------------------
-- 5. Helper functions for RLS (Security Definer to prevent infinite recursion)
-- ---------------------------------------------------------------------------

create or replace function public.is_profile_guardian(p_profile_id text, p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.profile_guardians
     where profile_id = p_profile_id
       and user_id = p_user_id
       and status = 'accepted'
  );
$$;

create or replace function public.is_guardian_with_roles(p_profile_id text, p_user_id uuid, p_roles text[])
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.profile_guardians
     where profile_id = p_profile_id
       and user_id = p_user_id
       and status = 'accepted'
       and role = any(p_roles)
  );
$$;

-- ---------------------------------------------------------------------------
-- 6. guardian_invitations table
-- ---------------------------------------------------------------------------

create table public.guardian_invitations (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  invited_by uuid not null
    references auth.users (id) on delete cascade,
  token_hash text not null unique
    constraint guardian_invitations_token_hash_check
    check (token_hash ~ '^[0-9a-f]{64}$'),
  role text not null
    constraint guardian_invitations_role_check
    check (role in ('co_parent', 'caregiver', 'viewer')),
  recipient_label text
    constraint guardian_invitations_recipient_label_check
    check (recipient_label is null or char_length(recipient_label) <= 80),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid
    references auth.users (id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.guardian_invitations is
  'Single-use expiring pairing tokens (SHA-256 hashed) for inviting co-parents and caregivers.';

create index guardian_invitations_profile_id_idx on public.guardian_invitations (profile_id);
create index guardian_invitations_token_hash_idx on public.guardian_invitations (token_hash);

-- ---------------------------------------------------------------------------
-- 7. Refactor day_entries: attribution columns, FK, and unique index
-- ---------------------------------------------------------------------------

alter table public.day_entries
  add column if not exists logged_by_user_id uuid references auth.users(id) on delete set null,
  add column if not exists last_modified_by_user_id uuid references auth.users(id) on delete set null;

update public.day_entries
   set logged_by_user_id = user_id,
       last_modified_by_user_id = user_id
 where logged_by_user_id is null;

alter table public.day_entries
  drop constraint if exists day_entries_profile_fk;

alter table public.day_entries
  add constraint day_entries_profile_fk
  foreign key (profile_id)
  references public.profiles (id) on delete cascade;

drop index if exists public.day_entries_live_profile_date_uq;

create unique index day_entries_live_profile_date_uq
  on public.day_entries (profile_id, local_date)
  where deleted_at is null;

create index if not exists day_entries_logged_by_idx
  on public.day_entries (logged_by_user_id);
create index if not exists day_entries_last_modified_by_idx
  on public.day_entries (last_modified_by_user_id);

-- ---------------------------------------------------------------------------
-- 8. Row-Level Security
-- ---------------------------------------------------------------------------

alter table public.profile_guardians enable row level security;
alter table public.profile_guardians force row level security;
alter table public.guardian_invitations enable row level security;
alter table public.guardian_invitations force row level security;

-- Policies on profile_guardians
create policy "profile_guardians_select" on public.profile_guardians
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_profile_guardian(profile_id, (select auth.uid()))
  );

-- Membership rows are created by the SECURITY DEFINER invitation RPC or by
-- an existing primary_guardian / co_parent; a user must never be able to
-- self-insert membership (R16) - the `user_id = auth.uid()` self-service
-- branch would let any authenticated user grant itself any role on any
-- profile.
create policy "profile_guardians_insert" on public.profile_guardians
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

-- Membership state transitions run through the SECURITY DEFINER RPCs
-- (accept / revoke). A self-service `user_id = auth.uid()` branch here
-- would let a revoked guardian flip its own status back to 'accepted',
-- defeating revocation (R4/R5).
create policy "profile_guardians_update" on public.profile_guardians
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

-- Policies on guardian_invitations
create policy "guardian_invitations_select" on public.guardian_invitations
  for select to authenticated
  using (
    invited_by = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

create policy "guardian_invitations_insert" on public.guardian_invitations
  for insert to authenticated
  with check (
    invited_by = (select auth.uid())
    and public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

-- Only the invitation's creator may modify it (revoke it). Consumption
-- (accepted_at / accepted_by) is written exclusively by the SECURITY
-- DEFINER accept RPC; a role-based branch here would let a co-parent
-- forge-accept or un-revoke the primary guardian's invitations.
create policy "guardian_invitations_update" on public.guardian_invitations
  for update to authenticated
  using (
    invited_by = (select auth.uid())
  )
  with check (
    invited_by = (select auth.uid())
  );

-- Policies on profiles (Updated to include guardians)
drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_guardians" on public.profiles
  for select to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_profile_guardian(id, (select auth.uid()))
  );

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_guardians" on public.profiles
  for update to authenticated
  using (
    (select auth.uid()) = user_id
    or public.is_guardian_with_roles(id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  )
  with check (
    (select auth.uid()) = user_id
    or public.is_guardian_with_roles(id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

-- Policies on day_entries (Updated to include guardians)
drop policy if exists "day_entries_select_own" on public.day_entries;
create policy "day_entries_select_guardians" on public.day_entries
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

drop policy if exists "day_entries_insert_own" on public.day_entries;
create policy "day_entries_insert_guardians" on public.day_entries
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

drop policy if exists "day_entries_update_own" on public.day_entries;
create policy "day_entries_update_guardians" on public.day_entries
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

-- ---------------------------------------------------------------------------
-- 9. Privileges
-- ---------------------------------------------------------------------------
-- Least privilege (KTD15): membership state (`status`, `role`) is only
-- writable through the SECURITY DEFINER RPCs, invitation consumption only
-- through the accept RPC, and day_entries attribution only as the
-- security-invoker sync_push writes it (last_modified_by_user_id = caller;
-- logged_by_user_id is insert-only and enforced by the trigger below).

revoke all on table public.profile_guardians from public, anon, authenticated;
grant select, insert on table public.profile_guardians to authenticated;
grant update (display_name, updated_at) on table public.profile_guardians to authenticated;

revoke all on table public.guardian_invitations from public, anon, authenticated;
grant select, insert on table public.guardian_invitations to authenticated;
grant update (revoked_at) on table public.guardian_invitations to authenticated;

grant update (last_modified_by_user_id) on table public.day_entries to authenticated;

-- R11/AE2: attribution columns are server-authoritative. sync_push stamps
-- them from (select auth.uid()) and never changes logged_by_user_id on
-- UPDATE, so this trigger holds for every RPC path while making direct
-- client writes (forged logged_by / last_modified values) fail. A null
-- auth.uid() (migrations, service role) is exempt: the backfill above and
-- operational tooling run without a JWT.
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

create trigger day_entries_attribution_insert_guard
  before insert on public.day_entries
  for each row execute function public.enforce_day_entry_attribution();

create trigger day_entries_attribution_update_guard
  before update on public.day_entries
  for each row execute function public.enforce_day_entry_attribution();

revoke execute on function public.enforce_day_entry_attribution() from public, anon;

grant execute on function public.is_profile_guardian(text, uuid) to authenticated;
grant execute on function public.is_guardian_with_roles(text, uuid, text[]) to authenticated;
