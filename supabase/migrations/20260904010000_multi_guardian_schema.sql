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
    references auth.users (id),
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
    references auth.users (id),
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
  add column if not exists logged_by_user_id uuid references auth.users(id),
  add column if not exists last_modified_by_user_id uuid references auth.users(id);

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

create policy "profile_guardians_insert" on public.profile_guardians
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  );

create policy "profile_guardians_update" on public.profile_guardians
  for update to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  )
  with check (
    user_id = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
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

create policy "guardian_invitations_update" on public.guardian_invitations
  for update to authenticated
  using (
    invited_by = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
  )
  with check (
    invited_by = (select auth.uid())
    or public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent'])
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

revoke all on table public.profile_guardians from public, anon, authenticated;
grant select, insert on table public.profile_guardians to authenticated;
grant update (display_name, status, updated_at) on table public.profile_guardians to authenticated;

revoke all on table public.guardian_invitations from public, anon, authenticated;
grant select, insert on table public.guardian_invitations to authenticated;
grant update (revoked_at, accepted_at, accepted_by) on table public.guardian_invitations to authenticated;

grant update (logged_by_user_id, last_modified_by_user_id) on table public.day_entries to authenticated;

grant execute on function public.is_profile_guardian(text, uuid) to authenticated;
grant execute on function public.is_guardian_with_roles(text, uuid, text[]) to authenticated;
