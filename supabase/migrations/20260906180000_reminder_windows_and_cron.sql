-- Migration: 20260906180000_reminder_windows_and_cron.sql
-- Issue #5, Unit U3: the client-published reminder-window snapshot, the
-- missed-entry scan that reads it, the outbox sweep that recovers a stuck
-- claim (KTD2's documented residual risk), and the nightly pg_cron job that
-- drives both. The scan never recomputes the prediction itself --
-- lib/domain/prediction/prediction.dart stays the only implementation of
-- that algorithm (KTD4 of the plan).
--
-- profile_id is `text` everywhere else in this schema (a ULID, see
-- public.profiles.id) -- the plan's pseudocode said `uuid` for
-- upsert_reminder_window's parameter, but that would not match
-- public.profiles(id) or any other function in this file; `text` is used
-- throughout below to stay consistent with the rest of the schema.

create table public.profile_reminder_windows (
  profile_id text primary key
    references public.profiles (id) on delete cascade,
  estimated_next_start date not null,
  episode_open boolean not null default false,
  updated_at timestamptz not null default now()
);

comment on table public.profile_reminder_windows is
  'Client-published snapshot of the local cycle prediction (Issue #5, KTD4): '
  'estimated next start plus whether an episode is currently open. Never '
  'computed server-side. The SELECT policy exists only for '
  '`insert ... on conflict do update` mechanics -- no UI reads this table; '
  'public.scan_missed_entry_reminders() reads it as SECURITY DEFINER. The '
  'missed-entry dedupe marker (KTD8) does not live here -- see '
  'public.missed_entry_alert_state below (#8 review fix).';

alter table public.profile_reminder_windows enable row level security;
alter table public.profile_reminder_windows force row level security;

-- A SELECT policy is required here purely for `insert ... on conflict do
-- update` mechanics (Postgres needs SELECT to evaluate the conflict target
-- even though the UPDATE SET clause below never reads the existing row) --
-- not because a client is expected to read this back. Scoped to the same
-- write-eligible guardians as the INSERT/UPDATE policies below, so it
-- widens nothing beyond "the publishing device can see what it just
-- published".
create policy "profile_reminder_windows_select" on public.profile_reminder_windows
  for select to authenticated
  using (
    public.is_guardian_with_roles(
      profile_id, (select auth.uid()),
      array['primary_guardian', 'co_parent', 'caregiver']
    )
  );

create policy "profile_reminder_windows_insert" on public.profile_reminder_windows
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(
      profile_id, (select auth.uid()),
      array['primary_guardian', 'co_parent', 'caregiver']
    )
  );

create policy "profile_reminder_windows_update" on public.profile_reminder_windows
  for update to authenticated
  using (
    public.is_guardian_with_roles(
      profile_id, (select auth.uid()),
      array['primary_guardian', 'co_parent', 'caregiver']
    )
  )
  with check (
    public.is_guardian_with_roles(
      profile_id, (select auth.uid()),
      array['primary_guardian', 'co_parent', 'caregiver']
    )
  );

revoke all on table public.profile_reminder_windows from public, anon, authenticated;
grant select, insert, update on table public.profile_reminder_windows to authenticated;

-- ---------------------------------------------------------------------------
-- missed_entry_alert_state (#8 review fix): the missed-entry dedupe marker,
-- keyed per (profile, guardian) rather than per profile. KTD8 originally put
-- this marker on profile_reminder_windows, which has exactly one row per
-- profile -- shared across every guardian on it. Two guardians on the same
-- profile with different missed_entry_days thresholds fire at different
-- times, but a shared marker meant whichever guardian's threshold elapsed
-- first stamped the marker for that estimated_next_start, and the scan's
-- `last_enqueued_for is distinct from estimated_next_start` check then
-- silently skipped every other guardian for the same window forever (R15
-- violation). Owned exclusively by scan_missed_entry_reminders() (SECURITY
-- DEFINER); no policies, no grants -- mirrors notification_outbox's
-- posture, since nothing but the scan itself ever needs to touch it.
-- ---------------------------------------------------------------------------

create table public.missed_entry_alert_state (
  profile_id text not null
    references public.profiles (id) on delete cascade,
  user_id uuid not null
    references auth.users (id) on delete cascade,
  last_enqueued_for date,
  primary key (profile_id, user_id)
);

comment on table public.missed_entry_alert_state is
  'Per-(profile, guardian) missed-entry dedupe marker (Issue #5 review #8), '
  'owned exclusively by public.scan_missed_entry_reminders(). Replaces the '
  'original per-profile marker on profile_reminder_windows, which let one '
  'guardian''s alert silently suppress every co-guardian''s alert for the '
  'same estimated_next_start (R15).';

alter table public.missed_entry_alert_state enable row level security;
alter table public.missed_entry_alert_state force row level security;

revoke all on table public.missed_entry_alert_state from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- upsert_reminder_window: SECURITY INVOKER so the RLS policies above decide
-- who can call it (R13). Never touches missed_entry_alert_state -- only the
-- scan below owns it.
-- ---------------------------------------------------------------------------

create or replace function public.upsert_reminder_window(
  p_profile_id text,
  p_estimated_next_start date,
  p_episode_open boolean
) returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.profile_reminder_windows
    (profile_id, estimated_next_start, episode_open, updated_at)
  values
    (p_profile_id, p_estimated_next_start, p_episode_open, now())
  on conflict (profile_id) do update
    set estimated_next_start = excluded.estimated_next_start,
        episode_open = excluded.episode_open,
        updated_at = excluded.updated_at;
$$;

comment on function public.upsert_reminder_window(text, date, boolean) is
  'Publishes the client''s current cycle prediction (R13): SECURITY INVOKER '
  'so the caller''s own RLS grant is what allows or refuses the write. '
  'Never touches missed_entry_alert_state.';

revoke all on function public.upsert_reminder_window(text, date, boolean) from public, anon;
grant execute on function public.upsert_reminder_window(text, date, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- scan_missed_entry_reminders: the missed-entry half of the feature
-- (R14, R15). SECURITY DEFINER -- it reads day_entries.local_date across
-- families, never their content.
-- ---------------------------------------------------------------------------

create or replace function public.scan_missed_entry_reminders() returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := current_date;
  v_count integer := 0;
  v_row record;
  v_newest date;
begin
  for v_row in
    select p.user_id, p.profile_id, p.missed_entry_days,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           w.estimated_next_start, w.episode_open,
           s.last_enqueued_for
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id and g.user_id = p.user_id
      join public.profile_reminder_windows w
        on w.profile_id = p.profile_id
      -- #8 (review): dedupe is per (profile, guardian), not per profile --
      -- see missed_entry_alert_state's comment above. A guardian with no
      -- row yet here has never been enqueued for anything, hence the
      -- left join rather than an inner one.
      left join public.missed_entry_alert_state s
        on s.profile_id = p.profile_id and s.user_id = p.user_id
     where p.missed_entry_days is not null
       and g.status = 'accepted'
  loop
    select max(local_date) into v_newest
      from public.day_entries
     where profile_id = v_row.profile_id
       and deleted_at is null;

    if v_newest is not null
       and (v_today - v_newest) > v_row.missed_entry_days
       and (v_row.estimated_next_start <= v_today or coalesce(v_row.episode_open, false))
       and v_row.last_enqueued_for is distinct from v_row.estimated_next_start
    then
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        v_row.profile_id, v_row.user_id, 'missed_entry',
        public.resolve_deliver_after(
          now(), v_row.quiet_hours_start, v_row.quiet_hours_end, v_row.time_zone
        )
      );

      insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
      values (v_row.profile_id, v_row.user_id, v_row.estimated_next_start)
      on conflict (profile_id, user_id) do update
        set last_enqueued_for = excluded.last_enqueued_for;

      v_count := v_count + 1;
    end if;
  end loop;

  return v_count;
end;
$$;

comment on function public.scan_missed_entry_reminders() is
  'Enqueues one missed_entry alert per (guardian, profile) whose newest '
  'live entry is older than the guardian''s threshold and whose published '
  'reminder window says the estimate has passed or an episode is open '
  '(R14). Deduped per (profile, guardian) via missed_entry_alert_state '
  '(KTD8, #8 review fix), so a re-run before a fresh window is published '
  'enqueues nothing (R15), and one guardian being enqueued never suppresses '
  'a co-guardian with a different threshold on the same profile.';

revoke all on function public.scan_missed_entry_reminders() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- sweep_notification_outbox: recovers a claim stuck by a process killed
-- between claiming and sending (KTD2's documented residual risk, mirroring
-- 20260906150000_feedback_tickets_notified_at.sql's).
-- ---------------------------------------------------------------------------

create or replace function public.sweep_notification_outbox() returns integer
language sql
security definer
set search_path = ''
as $$
  with released as (
    update public.notification_outbox
       set claimed_at = null
     where claimed_at is not null
       and sent_at is null
       and claimed_at < now() - interval '15 minutes'
    returning 1
  )
  select count(*)::integer from released;
$$;

comment on function public.sweep_notification_outbox() is
  'Releases a notification_outbox claim older than 15 minutes with no '
  'sent_at, recovering push-dispatch''s claim-before-send pattern (KTD2) '
  'from a process killed mid-send. Returns the number of claims released.';

revoke all on function public.sweep_notification_outbox() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Nightly pg_cron job (Q3: nightly is the deliberate starting cadence).
-- Guarded exactly like 20260906140000_feedback_attachments_bucket.sql's
-- storage guard (KTD9): a local stack started without pg_cron/pg_net (per
-- AGENTS.md's `supabase start -x ...` exclusion list) sees this whole block
-- no-op rather than failing db reset. Dispatching push-dispatch itself is
-- read from GUC settings (app.settings.push_dispatch_url /
-- app.settings.push_dispatch_webhook_secret) rather than hardcoded, since a
-- migration file cannot know the deployed project's function URL or shared
-- webhook secret; docs/ops/supabase-go-live.md (U9) documents setting those
-- with `alter database postgres set ...` as a go-live step. The secret is
-- sent the same way the Database Webhook config sends it -- a custom
-- `x-push-dispatch-webhook-secret` header, matching push-dispatch/index.ts's
-- own check and the feedback-reply precedent (see that function). A missing
-- setting degrades to "scan and sweep still ran, dispatch skipped" rather
-- than failing the whole job.
-- ---------------------------------------------------------------------------

create or replace function public.trigger_push_dispatch() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text := current_setting('app.settings.push_dispatch_url', true);
  v_secret text := current_setting('app.settings.push_dispatch_webhook_secret', true);
begin
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    raise notice 'trigger_push_dispatch: app.settings.push_dispatch_url/_webhook_secret not configured, skipping (see docs/ops/supabase-go-live.md)';
    return;
  end if;

  if to_regprocedure('net.http_post(text, jsonb, jsonb, integer)') is null then
    raise notice 'trigger_push_dispatch: pg_net not available, skipping';
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-dispatch-webhook-secret', v_secret
    ),
    body := '{}'::jsonb
  );
exception
  when others then
    -- Best-effort: a failed sweep-triggered dispatch is recovered by the
    -- Database Webhook (immediacy path) and the next nightly sweep, per
    -- KTD3 -- it must never fail the cron job that also runs the scan and
    -- sweep above.
    raise notice 'trigger_push_dispatch: dispatch call failed, will retry next cycle';
end;
$$;

revoke all on function public.trigger_push_dispatch() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- run_nightly_caregiver_alerts_job (#15 review fix): pg_cron runs a job's
-- command string as a single implicit transaction/statement batch, so the
-- original three bare `select ...;` statements meant one tenant's bad
-- time_zone raising out of scan_missed_entry_reminders() (or any other
-- unexpected error from either function) aborted the whole job -- the sweep
-- and dispatch legs then never ran, for every tenant, permanently (there was
-- no other periodic trigger for either). #3's fix makes resolve_deliver_after
-- itself never raise on a bad zone, but this wrapper is defense in depth
-- against *any* failure in the scan or sweep step: each step is isolated in
-- its own sub-block so a failure in one can never prevent the next from
-- running. trigger_push_dispatch() already self-guards this way internally.
-- ---------------------------------------------------------------------------

create or replace function public.run_nightly_caregiver_alerts_job() returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform public.scan_missed_entry_reminders();
  exception
    when others then
      raise notice 'run_nightly_caregiver_alerts_job: scan_missed_entry_reminders failed: %', sqlerrm;
  end;

  begin
    perform public.sweep_notification_outbox();
  exception
    when others then
      raise notice 'run_nightly_caregiver_alerts_job: sweep_notification_outbox failed: %', sqlerrm;
  end;

  -- Already self-guards (see its own exception handler above); still run
  -- from its own sub-block so a future change to it cannot regress this
  -- function's own isolation guarantee.
  begin
    perform public.trigger_push_dispatch();
  exception
    when others then
      raise notice 'run_nightly_caregiver_alerts_job: trigger_push_dispatch failed: %', sqlerrm;
  end;
end;
$$;

comment on function public.run_nightly_caregiver_alerts_job() is
  'Runs the missed-entry scan, the outbox sweep, and a dispatch nudge, each '
  'isolated in its own sub-block (#15 review fix) so one tenant''s bad data '
  'or any other single-step failure cannot silently stop the other two '
  'from running, for every tenant, until the next deploy.';

revoke all on function public.run_nightly_caregiver_alerts_job() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- run_caregiver_alert_drain (#9 review fix): the nightly job alone left
-- quiet-hours releases and retries waiting up to ~24h for the next 09:00 UTC
-- run (AE4 requires delivery promptly after the quiet-hours window ends, not
-- up to a day later). This frequent, cheap drain covers just the two
-- time-sensitive legs -- sweeping stuck claims and nudging the dispatcher --
-- so a deferred alert releases within one cadence interval of its
-- deliver_after, not one nightly run. The missed-entry scan stays nightly
-- only (its own threshold granularity is whole days, so more frequent scans
-- add load without changing outcomes) and is deliberately not duplicated
-- here. Per Q3 in the plan: "a 15-minute cadence is a one-line change."
-- ---------------------------------------------------------------------------

create or replace function public.run_caregiver_alert_drain() returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  begin
    perform public.sweep_notification_outbox();
  exception
    when others then
      raise notice 'run_caregiver_alert_drain: sweep_notification_outbox failed: %', sqlerrm;
  end;

  begin
    perform public.trigger_push_dispatch();
  exception
    when others then
      raise notice 'run_caregiver_alert_drain: trigger_push_dispatch failed: %', sqlerrm;
  end;
end;
$$;

comment on function public.run_caregiver_alert_drain() is
  'Sweeps stuck claims and nudges push-dispatch every 15 minutes (#9 review '
  'fix), so a quiet-hours release or a retry reaches the recipient within '
  'one cadence interval rather than waiting for the next 09:00 UTC nightly '
  'run (AE4). The missed-entry scan is not duplicated here -- it stays on '
  'the nightly job alone.';

revoke all on function public.run_caregiver_alert_drain() from public, anon, authenticated;

do $$
begin
  if not exists (select 1 from pg_available_extensions where name = 'pg_cron')
     or not exists (select 1 from pg_available_extensions where name = 'pg_net') then
    raise notice 'reminder_windows_and_cron: pg_cron/pg_net not available, skipping cron schedule (see docs/ops/supabase-go-live.md)';
    return;
  end if;

  create extension if not exists pg_cron;
  create extension if not exists pg_net;

  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'lunarlog-nightly-caregiver-alerts';

  perform cron.unschedule(jobid)
    from cron.job
   where jobname = 'lunarlog-caregiver-alert-drain';

  perform cron.schedule(
    'lunarlog-nightly-caregiver-alerts',
    '0 9 * * *', -- 09:00 UTC nightly (Q3: revisit cadence if too coarse)
    $cron$select public.run_nightly_caregiver_alerts_job();$cron$
  );

  perform cron.schedule(
    'lunarlog-caregiver-alert-drain',
    '*/15 * * * *', -- every 15 minutes (#9 review fix; Q3's anticipated one-line change)
    $cron$select public.run_caregiver_alert_drain();$cron$
  );
end;
$$;
