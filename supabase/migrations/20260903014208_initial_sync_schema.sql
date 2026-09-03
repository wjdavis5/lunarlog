-- lunarlog remote sync schema (plan 2026-09-02-001, unit U2).
--
-- Three per-user tables mirroring the local Drift store, isolated by
-- row-level security keyed on auth.uid(), with structural guards (KTD15):
-- per-user composite primary keys, a composite foreign key from day entries
-- to profiles, column-list UPDATE grants, no DELETE grant, and CHECK
-- constraints that bound every free-text column. server_version (KTD2) is
-- stamped from one sequence by a BEFORE trigger and never accepted from a
-- client. All identifiers are lowercase and schema-qualified.

-- ---------------------------------------------------------------------------
-- server_version sequence + trigger (KTD2)
-- ---------------------------------------------------------------------------

create sequence public.sync_version_seq as bigint;

create or replace function public.set_server_version()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.server_version := nextval('public.sync_version_seq');
  return new;
end;
$$;

comment on function public.set_server_version() is
  'Stamps server_version from public.sync_version_seq on every insert/update; the pull cursor (KTD2).';

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create table public.profiles (
  id text not null
    constraint profiles_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  display_name text not null default ''
    constraint profiles_display_name_length_check
    check (char_length(display_name) <= 80),
  is_minor boolean not null default false,
  sort_order integer not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id, user_id)
);

comment on table public.profiles is
  'Family member profiles; one owner per row (user_id = auth.uid()). Soft-deleted via deleted_at.';

create index profiles_user_id_idx
  on public.profiles (user_id);
create index profiles_user_id_server_version_idx
  on public.profiles (user_id, server_version);

create trigger profiles_set_server_version
  before insert or update on public.profiles
  for each row execute function public.set_server_version();

-- ---------------------------------------------------------------------------
-- day_entries
-- ---------------------------------------------------------------------------

create table public.day_entries (
  id text not null
    constraint day_entries_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  profile_id text not null,
  local_date date not null,
  tz text not null
    constraint day_entries_tz_length_check
    check (char_length(tz) <= 64),
  flow text not null
    constraint day_entries_flow_check
    check (flow in ('none', 'spotting', 'light', 'medium', 'heavy')),
  tags jsonb not null default '[]'::jsonb
    constraint day_entries_tags_check
    check (jsonb_typeof(tags) = 'array' and jsonb_array_length(tags) <= 32),
  note text
    constraint day_entries_note_length_check
    check (char_length(note) <= 2000),
  -- Server-only; no local counterpart, the row codec never reads or writes it.
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id, user_id),
  -- A day entry can only reference a profile owned by the same user (R8).
  constraint day_entries_profile_fk
    foreign key (profile_id, user_id)
    references public.profiles (id, user_id) on delete cascade
);

comment on table public.day_entries is
  'One row per (profile, local date) among live rows; tombstones keep the id but carry no payload.';

-- Exactly one live entry per (user, profile, date); tombstones do not compete.
create unique index day_entries_live_profile_date_uq
  on public.day_entries (user_id, profile_id, local_date)
  where deleted_at is null;

create index day_entries_user_id_idx
  on public.day_entries (user_id);
create index day_entries_user_id_server_version_idx
  on public.day_entries (user_id, server_version);
create index day_entries_profile_id_user_id_idx
  on public.day_entries (profile_id, user_id);

create trigger day_entries_set_server_version
  before insert or update on public.day_entries
  for each row execute function public.set_server_version();

-- ---------------------------------------------------------------------------
-- settings
-- ---------------------------------------------------------------------------

create table public.settings (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  key text not null
    constraint settings_key_length_check
    check (char_length(key) <= 128),
  value text not null
    constraint settings_value_length_check
    check (char_length(value) <= 4000),
  updated_at timestamptz not null default now(),
  server_version bigint not null default 0,
  primary key (user_id, key)
);

comment on table public.settings is
  'Per-user key/value settings.';

create index settings_user_id_idx
  on public.settings (user_id);
create index settings_user_id_server_version_idx
  on public.settings (user_id, server_version);

create trigger settings_set_server_version
  before insert or update on public.settings
  for each row execute function public.set_server_version();

-- ---------------------------------------------------------------------------
-- Row-level security (R7, KTD15): enabled AND forced, four policies per
-- table, every policy `to authenticated` with `(select auth.uid()) = user_id`
-- so the planner evaluates auth.uid() once per statement.
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.profiles force row level security;
alter table public.day_entries enable row level security;
alter table public.day_entries force row level security;
alter table public.settings enable row level security;
alter table public.settings force row level security;

create policy "profiles_select_own" on public.profiles
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "profiles_delete_own" on public.profiles
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "day_entries_select_own" on public.day_entries
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "day_entries_insert_own" on public.day_entries
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "day_entries_update_own" on public.day_entries
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "day_entries_delete_own" on public.day_entries
  for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "settings_select_own" on public.settings
  for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "settings_insert_own" on public.settings
  for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "settings_update_own" on public.settings
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "settings_delete_own" on public.settings
  for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ---------------------------------------------------------------------------
-- Privileges (KTD15). Supabase's default privileges grant ALL on new public
-- objects to anon, authenticated, and service_role, so start from a clean
-- slate: revoke everything, then grant exactly what the app needs.
--   select, insert            -> authenticated
--   update (column list)      -> authenticated; omits id, user_id,
--                                server_version (and day_entries.created_at)
--   delete                    -> nobody (the app only tombstones)
--   anon / PUBLIC             -> nothing
-- ---------------------------------------------------------------------------

revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.day_entries from public, anon, authenticated;
revoke all on table public.settings from public, anon, authenticated;

grant select, insert on table public.profiles to authenticated;
grant update (display_name, is_minor, sort_order, archived_at, created_at, updated_at, deleted_at)
  on table public.profiles to authenticated;

grant select, insert on table public.day_entries to authenticated;
grant update (profile_id, local_date, tz, flow, tags, note, updated_at, deleted_at)
  on table public.day_entries to authenticated;

grant select, insert on table public.settings to authenticated;
grant update (value, updated_at)
  on table public.settings to authenticated;

-- The trigger runs as the writing role, which needs to advance the sequence.
revoke all on sequence public.sync_version_seq from public, anon, authenticated;
grant usage on sequence public.sync_version_seq to authenticated;

-- Trigger functions cannot be called directly, but keep the surface minimal.
revoke execute on function public.set_server_version() from public, anon;
