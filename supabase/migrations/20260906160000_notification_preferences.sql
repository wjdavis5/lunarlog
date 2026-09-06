-- Migration: 20260906160000_notification_preferences.sql
-- Issue #5, Unit U1: the two guardian-owned tables behind caregiver alerts
-- and reminders -- notification_preferences (what a guardian wants to be
-- told, per profile) and push_devices (where to tell them). Neither table
-- is written by anything but the guardian themselves; the enqueue trigger
-- and dispatcher added in later units read them with a security-definer
-- function or the service-role key, never through these RLS policies.
--
-- RLS follows the shape 20260904010000_multi_guardian_schema.sql and
-- 20260905090000_close_guardian_revocation_bypass.sql already settled:
-- public.is_profile_guardian(profile_id, user_id) checks status = 'accepted'
-- (a revoked guardian's status is 'revoked', so revocation already closes
-- this without a separate revoked_at check) plus an explicit
-- `user_id = auth.uid()` so a guardian can only ever touch their own
-- preference row, never a co-guardian's (R1, R2, R5).

create table public.notification_preferences (
  user_id uuid not null
    references auth.users (id) on delete cascade,
  profile_id text not null
    references public.profiles (id) on delete cascade,
  alert_on_log boolean not null default false,
  alert_on_cycle_start_only boolean not null default false,
  alert_on_high_severity boolean not null default false,
  -- null means "off" (R3, R4's opt-in default); 1/2/3 days of silence.
  missed_entry_days smallint
    constraint notification_preferences_missed_entry_days_check
    check (missed_entry_days between 1 and 3),
  quiet_hours_start time,
  quiet_hours_end time,
  -- IANA zone name (e.g. 'America/New_York'); resolved client-side via
  -- lib/domain/util/timezone.dart. Null means "no quiet hours resolvable".
  time_zone text,
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);

comment on table public.notification_preferences is
  'Per (guardian, profile) caregiver alert preferences (Issue #5). Off by '
  'default (R4) -- a profile with no row here sends that guardian nothing. '
  'Read and written only by the owning guardian through RLS below; the '
  'day_entries enqueue trigger and the missed-entry scan (U2/U3) read this '
  'as SECURITY DEFINER, not through these policies.';

create index notification_preferences_profile_id_idx
  on public.notification_preferences (profile_id);

alter table public.notification_preferences enable row level security;
alter table public.notification_preferences force row level security;

create policy "notification_preferences_select" on public.notification_preferences
  for select to authenticated
  using (
    user_id = (select auth.uid())
    and public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "notification_preferences_insert" on public.notification_preferences
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "notification_preferences_update" on public.notification_preferences
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and public.is_profile_guardian(profile_id, (select auth.uid()))
  )
  with check (
    user_id = (select auth.uid())
    and public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "notification_preferences_delete" on public.notification_preferences
  for delete to authenticated
  using (
    user_id = (select auth.uid())
  );

-- #14 (review): every RLS table in this schema revokes all from
-- authenticated too, before re-granting the specific privileges below --
-- otherwise authenticated keeps its default TRUNCATE privilege, which
-- bypasses RLS entirely (TRUNCATE has no row-level check).
revoke all on table public.notification_preferences from public, anon, authenticated;
grant select, insert, update, delete on table public.notification_preferences to authenticated;

-- ---------------------------------------------------------------------------
-- push_devices: one row per (device, user). No cross-guardian visibility at
-- all -- a caregiver never needs to see another guardian's device, and the
-- push-dispatch Edge Function (U5) reaches this table with the service-role
-- key, which bypasses RLS entirely.
-- ---------------------------------------------------------------------------

create table public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references auth.users (id) on delete cascade,
  token text not null,
  platform text not null
    constraint push_devices_platform_check
    check (platform in ('ios', 'android')),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz
);

comment on table public.push_devices is
  'FCM registration tokens (Issue #5), one row per device. Plain '
  '`user_id = auth.uid()` RLS -- no cross-guardian read at all. '
  'push-dispatch (U5) reads this with the service-role key.';

create unique index push_devices_token_uq on public.push_devices (token);
create index push_devices_user_id_idx on public.push_devices (user_id);

alter table public.push_devices enable row level security;
alter table public.push_devices force row level security;

create policy "push_devices_select" on public.push_devices
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "push_devices_insert" on public.push_devices
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy "push_devices_update" on public.push_devices
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "push_devices_delete" on public.push_devices
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- #14 (review): see the matching comment above notification_preferences'
-- revoke -- authenticated's default TRUNCATE privilege bypasses RLS and
-- must be revoked here too.
revoke all on table public.push_devices from public, anon, authenticated;
grant select, insert, update, delete on table public.push_devices to authenticated;

-- ---------------------------------------------------------------------------
-- register_push_device (round-2 review #1 -- round-1 #1's "half (b)"):
-- SECURITY DEFINER because a plain client-side upsert conflicting on `id`
-- cannot recover from a stale row a *previous* account on this install left
-- behind. That happens whenever this device's deregistration on sign-out
-- fails (an offline sign-out is the ordinary case, not the exotic one, and
-- PushRegistrationCoordinator's removal is best-effort/swallowed by design):
-- the row keeps the previous user_id, `push_devices_id`'s conflict target is
-- the same persisted device id, and the update half of that upsert is denied
-- by the push_devices_update policy (`user_id = auth.uid()` does not match
-- the caller) -- with no INSERT fallback once the conflict target already
-- exists, the whole statement silently affects zero rows. The previous
-- account then keeps receiving this device's alerts, and the new account can
-- never register on this install again. `token` is checked too, not just
-- `id`: the same physical FCM install typically keeps the same token across
-- an account switch, and push_devices_token_uq would otherwise raise 23505
-- on the fresh-id insert path.
-- ---------------------------------------------------------------------------

create or replace function public.register_push_device(
  p_id uuid,
  p_token text,
  p_platform text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Reassign, don't merely refuse: any row matching this device id or this
  -- FCM token that belongs to someone else is stale (a prior account's
  -- deregistration that never completed), never a live conflict worth
  -- preserving -- the same install can only be registered to one account at
  -- a time.
  delete from public.push_devices
   where (id = p_id or token = p_token)
     and user_id <> v_uid;

  insert into public.push_devices (id, user_id, token, platform, disabled_at, updated_at)
  values (p_id, v_uid, p_token, p_platform, null, now())
  on conflict (id) do update
    set user_id = excluded.user_id,
        token = excluded.token,
        platform = excluded.platform,
        disabled_at = null,
        updated_at = now();
end;
$$;

comment on function public.register_push_device(uuid, text, text) is
  'Registers/refreshes p_id''s push_devices row under the caller (round-2 '
  'review #1, round-1 #1 half (b)). SECURITY DEFINER so it can first delete '
  'any row matching p_id or p_token owned by a *different* user -- a stale '
  'row left behind by a previous account on this install whose sign-out '
  'deregistration failed -- which a plain client-side upsert cannot do '
  '(RLS denies the update half of the upsert, and there is no insert '
  'fallback once the conflict target already exists), permanently blocking '
  'the next account from ever registering while the previous account keeps '
  'receiving this device''s alerts.';

revoke all on function public.register_push_device(uuid, text, text) from public, anon;
grant execute on function public.register_push_device(uuid, text, text) to authenticated;
