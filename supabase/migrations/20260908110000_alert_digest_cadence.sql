-- Migration: 20260908000000_alert_digest_cadence.sql
-- Issue #125: digest cadence and rate limiting for co-guardian alerts.
--
-- Four delivery behaviors, all riding the existing content-free outbox and
-- its claim-before-send dispatcher -- no second delivery mechanism:
--
--   1. Per-alert-type cadence. notification_preferences gains a cadence
--      column per day_entries alert kind (log_cadence for 'logged',
--      cycle_start_cadence, high_severity_cadence), each
--      immediate/daily_digest/off, defaulting to 'immediate' so a guardian
--      who never touches the new settings keeps today's behaviour exactly
--      (and the all-off default -- alert_on_log false -- still means
--      nothing at all). Missed-entry alerts keep missed_entry_days as
--      their own off/immediate control: they are already deduped to at
--      most one push per (guardian, profile, window) by
--      missed_entry_alert_state, so a cadence dimension would add nothing.
--      Cadence is per guardian (a column on their own preference row),
--      never per profile: two guardians on one profile can choose
--      differently.
--
--   2. Coalescing window for immediate alerts. enqueue_caregiver_alerts
--      now skips an immediate insert when a row of the same
--      (recipient, profile, kind) was created inside the window returned
--      by public.alert_coalesce_window() -- five qualifying events inside
--      the window produce one push, not five. The check deliberately does
--      NOT filter on sent_at: with a healthy Database Webhook every row
--      is claimed and sent within milliseconds, so an unsent-only guard
--      (as sketched in the issue's parity-audit comment) would never
--      suppress anything and AC2 would fail in production while passing
--      only in a degraded dispatch-less environment.
--
--   3. Per-guardian daily push ceiling. Once a guardian has accumulated
--      alert_daily_push_ceiling() immediate pushes for a profile in their
--      current local day, further events for that profile are held for the
--      digest instead of pushed -- the overflow rolls into the next digest
--      rather than being dropped. Held rows are marked by
--      deliver_after = 'infinity' (never claimable by push-dispatch's
--      `deliver_after <= now()` predicate), so no outbox column is added
--      and the content-free structural guarantee is untouched. The count
--      excludes missed_entry rows (bounded to one a day by their own
--      dedupe marker; deferring a safety check-in behind logging fatigue
--      would trade the wrong thing) and excludes other held rows (a digest
--      is one push a day by construction).
--
--   4. The digest itself: public.sweep_alert_digests(), wired into both
--      existing cron wrappers ahead of trigger_push_dispatch(). For each
--      (recipient, profile) with pending held rows it computes the next
--      occurrence of the guardian's chosen digest_local_time (server
--      fallback 08:00) strictly after the oldest held row's created_at,
--      shifts it out of quiet hours with the same resolve_deliver_after()
--      immediate alerts already use, and -- once that moment has passed --
--      collapses every held row for the group into exactly ONE deliverable
--      row (deliver_after = now()) and marks the rest sent (absorbed: their
--      content, such as it is, was delivered as part of that one push).
--      The payload rule does not change: the digest push is the same fixed
--      generic text as every other alert, with no event count anywhere.
--      Even a count is a derived health signal (three events versus thirty
--      says something about the profile's state), and the caregiver-alerts
--      plan's standing position is that alerts carry no derived signal at
--      all -- so the digest says only "open Lunarlog", exactly like an
--      immediate alert, and volume control stays the only lever.
--
-- Self-authored-event suppression (issue AC3) is not re-implemented here:
-- enqueue_caregiver_alerts already excludes the writer via
-- `g.user_id is distinct from v_writer_id` (v_writer_id = the row's
-- last_modified_by_user_id, which sync_push stamps from the acting
-- device's auth.uid() -- so a guardian's own edit propagating from their
-- second device never pages them). It is pinned by regression tests in
-- supabase/tests/alert_digest_test.sql instead.
--
-- Per the repo's standing rule this file only adds and `create or
-- replace`s; no merged migration is edited in place. The replaced
-- functions below carry their prior bodies verbatim plus the new steps.

-- ---------------------------------------------------------------------------
-- 1. Cadence columns on notification_preferences.
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column log_cadence text not null default 'immediate'
    constraint notification_preferences_log_cadence_check
    check (log_cadence in ('immediate', 'daily_digest', 'off')),
  add column cycle_start_cadence text not null default 'immediate'
    constraint notification_preferences_cycle_start_cadence_check
    check (cycle_start_cadence in ('immediate', 'daily_digest', 'off')),
  add column high_severity_cadence text not null default 'immediate'
    constraint notification_preferences_high_severity_cadence_check
    check (high_severity_cadence in ('immediate', 'daily_digest', 'off')),
  add column digest_local_time time;

comment on column public.notification_preferences.log_cadence is
  'Delivery cadence for routine logged alerts (Issue #125): immediate '
  '(the pre-#125 behaviour), daily_digest (held for the daily digest '
  'push), or off. Default immediate, so an existing row behaves exactly '
  'as before this column existed.';
comment on column public.notification_preferences.digest_local_time is
  'The guardian''s chosen local time for the daily digest (Issue #125), '
  'in their own time_zone. Null falls back to 08:00 server-side in '
  'sweep_alert_digests(). Also bounds when ceiling overflow is delivered: '
  'an all-immediate guardian''s overflow rolls into a digest at this time '
  'too.';

-- ---------------------------------------------------------------------------
-- 2. Named constants (issue: "a named constant, not a magic number").
-- ---------------------------------------------------------------------------

-- The coalescing window for immediate alerts: 30 minutes by default
-- (the value the issue's parity-audit comment sketches). Operator-tunable
-- through the same GUC mechanism trigger_push_dispatch() already uses
-- (app.settings.*, set via `alter database postgres set ...` -- see
-- docs/ops/supabase-go-live.md); an unset, empty, or unparseable setting
-- degrades to the baked-in 30 minutes rather than raising, mirroring
-- resolve_deliver_after()'s never-raise discipline. pgTAP overrides it
-- transaction-locally with set_config to exercise both sides of the
-- guard.
create or replace function public.alert_coalesce_window() returns interval
language plpgsql
stable
set search_path = ''
as $$
declare
  v_override text := current_setting('app.settings.alert_coalesce_window', true);
begin
  if v_override is null or v_override = '' then
    return interval '30 minutes';
  end if;
  begin
    return v_override::interval;
  exception
    when others then
      return interval '30 minutes';
  end;
end;
$$;

comment on function public.alert_coalesce_window() is
  'The named coalescing-window constant for immediate caregiver alerts '
  '(Issue #125): one push per (recipient, profile, kind) per window. '
  'Defaults to 30 minutes; overridable via the '
  'app.settings.alert_coalesce_window GUC (never raises -- an invalid '
  'override degrades to the default, so it can never abort an entry '
  'write).';

-- The per-guardian daily immediate-push ceiling per profile: 6. Beyond
-- this many immediate pushes in the guardian''s current local day, further
-- events for that profile roll into the next digest instead.
create or replace function public.alert_daily_push_ceiling() returns integer
language sql
immutable
set search_path = ''
as $$
  select 6;
$$;

comment on function public.alert_daily_push_ceiling() is
  'The named per-guardian daily rate ceiling (Issue #125): the hard '
  'maximum number of immediate pushes a guardian receives for one profile '
  'per local day. Overflow rolls into the next digest, never dropped.';

-- Midnight of p_now's local day in p_zone (the anchor the daily ceiling
-- counts from). A null/empty/unrecognized zone degrades to UTC -- the same
-- never-raise discipline as resolve_deliver_after(), since this runs
-- inside the day_entries AFTER trigger.
create or replace function public.local_day_start(
  p_now timestamptz,
  p_zone text
) returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  v_zone text := coalesce(nullif(p_zone, ''), 'UTC');
  v_local_ts timestamp;
begin
  begin
    v_local_ts := p_now at time zone v_zone;
  exception
    when others then
      v_zone := 'UTC';
      v_local_ts := p_now at time zone 'UTC';
  end;
  return v_local_ts::date::timestamp at time zone v_zone;
end;
$$;

comment on function public.local_day_start(timestamptz, text) is
  'Local midnight of p_now in p_zone (Issue #125): the start of the local '
  'day the daily push ceiling counts within. A null, empty, or '
  'unrecognized zone degrades to UTC rather than raising.';

revoke all on function public.alert_coalesce_window() from public, anon, authenticated;
revoke all on function public.alert_daily_push_ceiling() from public, anon, authenticated;
revoke all on function public.local_day_start(timestamptz, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. enqueue_caregiver_alerts: cadence, ceiling, and coalescing on the
-- immediate path. Prior body (20260906220000) carried forward verbatim;
-- the loop body gains the three delivery decisions. The eligibility
-- expression, writer exclusion, tombstone skip, and cycle-start window
-- are unchanged.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_caregiver_alerts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_writer_id uuid;
  v_is_bleed boolean;
  v_prev_bleed boolean;
  v_is_cycle_start boolean;
  v_is_high_severity boolean;
  v_kind text;
  v_pref record;
  v_cadence text;
  v_pushes_today bigint;
begin
  -- A tombstoned write carries no meaningful "someone logged an entry"
  -- event.
  if new.deleted_at is not null then
    return null;
  end if;

  -- sync_push stamps last_modified_by_user_id from the caller's own
  -- auth.uid() (see 20260904010000_multi_guardian_schema.sql); a legacy or
  -- direct-insert row with it null falls back to user_id. This is the
  -- self-authored-event suppression the issue asks to verify and pin
  -- (AC3): a guardian's own edit synced from their second device carries
  -- their own id here and never pages them.
  v_writer_id := coalesce(new.last_modified_by_user_id, new.user_id);

  v_is_bleed := new.flow <> 'none';

  -- #6 (review): lib/domain/episodes/episodes.dart's deriveEpisodes() merges
  -- bleed dates at most 2 days apart into the same episode (a one-day
  -- non-bleed gap does not split it) -- probing only local_date - 1 missed
  -- that merge and flagged the day after a one-day gap as a false
  -- cycle_start. Checking the full [local_date - 2, local_date - 1] window
  -- for any prior bleed day matches deriveEpisodes' own rule exactly.
  select exists (
    select 1 from public.day_entries
     where profile_id = new.profile_id
       and local_date >= new.local_date - 2
       and local_date < new.local_date
       and deleted_at is null
       and flow <> 'none'
  ) into v_prev_bleed;

  -- R7: a cycle start is a bleed day with no bleed day in the merge window
  -- (or nothing at all -- v_prev_bleed is false either way).
  v_is_cycle_start := v_is_bleed and not v_prev_bleed;

  -- Q1: no severity marker exists in the tag taxonomy; heavy flow alone
  -- stands in for "high severity" (see 20260906220000's header).
  v_is_high_severity := new.flow = 'heavy';

  v_kind := case
    when v_is_cycle_start then 'cycle_start'
    when v_is_high_severity then 'high_severity'
    else 'logged'
  end;

  for v_pref in
    select g.user_id as guardian_user_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           p.log_cadence, p.cycle_start_cadence, p.high_severity_cadence
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id
       and g.user_id = p.user_id
     where p.profile_id = new.profile_id
       and g.status = 'accepted'
       and g.user_id is distinct from v_writer_id
       and p.alert_on_log
       -- R7: several narrowings enabled at once still yield at most one
       -- row per entry write -- this is a single boolean expression, not
       -- one insert per narrowing.
       and (not p.alert_on_cycle_start_only or v_is_cycle_start)
       and (not p.alert_on_high_severity or v_is_high_severity)
  loop
    -- Issue #125: the cadence column governing this event's kind decides
    -- delivery. 'off' is the per-kind kill switch the issue scopes; the
    -- kind-level default ('immediate') keeps pre-#125 behaviour for every
    -- existing row.
    v_cadence := case v_kind
      when 'cycle_start' then v_pref.cycle_start_cadence
      when 'high_severity' then v_pref.high_severity_cadence
      else v_pref.log_cadence
    end;

    if v_cadence = 'off' then
      continue;
    end if;

    if v_cadence = 'daily_digest' then
      -- Held for the digest sweep: deliver_after = 'infinity' keeps the
      -- row out of push-dispatch's `deliver_after <= now()` claim
      -- predicate until sweep_alert_digests() collapses the group at the
      -- guardian's chosen digest time.
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 3: the daily ceiling first, so the
    -- overflow rolls into the next digest rather than being coalesced
    -- away or dropped. Counts every non-held, non-missed_entry row for
    -- this (guardian, profile) created since the guardian's local
    -- midnight -- sent or not, each is one push made today.
    select count(*) into v_pushes_today
      from public.notification_outbox o
     where o.recipient_user_id = v_pref.guardian_user_id
       and o.profile_id = new.profile_id
       and o.kind <> 'missed_entry'
       and o.deliver_after < 'infinity'::timestamptz
       and o.created_at >= public.local_day_start(now(), v_pref.time_zone);

    if v_pushes_today >= public.alert_daily_push_ceiling() then
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 2: the coalescing window. Skip when
    -- a row of the same (recipient, profile, kind) already exists inside
    -- the window -- regardless of sent_at, because under a healthy
    -- webhook every row is sent within milliseconds and an unsent-only
    -- guard would never suppress anything.
    if exists (
      select 1 from public.notification_outbox o
       where o.recipient_user_id = v_pref.guardian_user_id
         and o.profile_id = new.profile_id
         and o.kind = v_kind
         and o.created_at > now() - public.alert_coalesce_window()
    ) then
      continue;
    end if;

    insert into public.notification_outbox
      (profile_id, recipient_user_id, kind, deliver_after)
    values (
      new.profile_id,
      v_pref.guardian_user_id,
      v_kind,
      public.resolve_deliver_after(
        now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_pref.time_zone
      )
    );
  end loop;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

-- Carries the comment forward verbatim (create or replace drops it).
comment on function public.enqueue_caregiver_alerts() is
  'AFTER INSERT and AFTER UPDATE trigger function on day_entries (Issue #5, '
  'KTD4; two separate triggers as of the #7 review fix, since a single '
  'combined trigger cannot WHEN-filter both events with one expression): '
  'fans a live write out into one public.notification_outbox row per '
  'eligible, non-writer guardian. The UPDATE trigger''s WHEN clause skips '
  'ownership-only updates and no-op resaves (#7). Runs independently of '
  'public.touch_sync_signal()''s sync_signals trigger -- the two write to '
  'different tables and neither depends on the other''s firing order. '
  'As of Issue #125 each guardian''s per-kind cadence column decides '
  'delivery: off skips, daily_digest holds the row for '
  'sweep_alert_digests(), and immediate rows are subject to the '
  'per-guardian daily push ceiling (overflow rolls into the next digest) '
  'and the alert_coalesce_window() coalescing guard.';

revoke execute on function public.enqueue_caregiver_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. sweep_alert_digests: the daily digest sweep (Issue #125). For each
-- (recipient, profile) holding unsent digest rows, computes the next
-- occurrence of the guardian's digest time strictly after the oldest held
-- row, shifts it out of quiet hours exactly as immediate alerts are, and
-- once due collapses the whole group into ONE deliverable row -- the
-- digest push. Per-group exception isolation mirrors
-- scan_missed_entry_reminders' round-2 review #7 fix: one tenant's bad
-- data must never abort the sweep for every other tenant.
-- ---------------------------------------------------------------------------

create or replace function public.sweep_alert_digests() returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer := 0;
  v_grp record;
  v_prefs record;
  v_digest_time time;
  v_zone text;
  v_local_ts timestamp;
  v_candidate timestamptz;
  v_deliver_at timestamptz;
begin
  for v_grp in
    select o.recipient_user_id, o.profile_id, min(o.created_at) as oldest_created
      from public.notification_outbox o
     where o.deliver_after = 'infinity'::timestamptz
       and o.sent_at is null
       and o.claimed_at is null
     group by o.recipient_user_id, o.profile_id
  loop
    begin
      select p.digest_local_time, p.quiet_hours_start, p.quiet_hours_end, p.time_zone
        into v_prefs
        from public.notification_preferences p
       where p.user_id = v_grp.recipient_user_id
         and p.profile_id = v_grp.profile_id;

      if not found then
        -- No preference row: the guardian is no longer configured for
        -- alerts on this profile (revocation and account deletion already
        -- delete held rows themselves; this catches a preference row
        -- deleted any other way). Drop the held digest -- there is no one
        -- to deliver it to and no cadence asking for it.
        delete from public.notification_outbox
         where recipient_user_id = v_grp.recipient_user_id
           and profile_id = v_grp.profile_id
           and deliver_after = 'infinity'::timestamptz
           and sent_at is null
           and claimed_at is null;
        continue;
      end if;

      v_digest_time := coalesce(v_prefs.digest_local_time, '08:00'::time);
      v_zone := coalesce(nullif(v_prefs.time_zone, ''), 'UTC');

      -- Resolve the zone with the same never-raise discipline as
      -- resolve_deliver_after()/local_day_start(): a bad zone degrades to
      -- UTC rather than aborting this group (or the sweep).
      begin
        v_local_ts := v_grp.oldest_created at time zone v_zone;
      exception
        when others then
          v_zone := 'UTC';
          v_local_ts := v_grp.oldest_created at time zone 'UTC';
      end;

      -- The next occurrence of the digest time strictly after the oldest
      -- held row's creation, in the guardian's local calendar: same local
      -- day when the oldest row predates today's digest moment, else the
      -- next day. A row created exactly at the digest time waits for the
      -- next day's digest (the conservative tie-break).
      v_candidate := (
        v_local_ts::date
        + (case when v_local_ts::time >= v_digest_time then 1 else 0 end)
        + v_digest_time
      ) at time zone v_zone;

      -- AC5: a digest scheduled inside quiet hours shifts to the window
      -- boundary, exactly as immediate alerts already do.
      v_deliver_at := public.resolve_deliver_after(
        v_candidate,
        v_prefs.quiet_hours_start,
        v_prefs.quiet_hours_end,
        v_prefs.time_zone
      );

      if now() >= v_deliver_at then
        -- Collapse: the oldest held row becomes the single deliverable
        -- digest push (deliver_after = now() makes it claimable by the
        -- next push-dispatch run -- the drain invoked this sweep, so that
        -- happens in the same cycle)...
        update public.notification_outbox
           set deliver_after = now()
         where id = (
           select id
             from public.notification_outbox
            where recipient_user_id = v_grp.recipient_user_id
              and profile_id = v_grp.profile_id
              and deliver_after = 'infinity'::timestamptz
              and sent_at is null
              and claimed_at is null
            order by created_at
            limit 1
         );

        -- ...and every other held row of the group is absorbed: marked
        -- sent without a push of its own, because the one digest push
        -- covers them (the payload is content-free -- there is no count
        -- to update). sent_at (not claimed_at) is the terminal state, so
        -- sweep_notification_outbox() can never resurrect an absorbed row
        -- the way it releases a stuck claim. The promoted row is excluded
        -- naturally: its deliver_after is no longer 'infinity'.
        update public.notification_outbox
           set sent_at = now()
         where recipient_user_id = v_grp.recipient_user_id
           and profile_id = v_grp.profile_id
           and deliver_after = 'infinity'::timestamptz
           and sent_at is null
           and claimed_at is null;

        v_count := v_count + 1;
      end if;
    exception
      when others then
        raise notice 'sweep_alert_digests: profile % / user % failed: %',
          v_grp.profile_id, v_grp.recipient_user_id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

comment on function public.sweep_alert_digests() is
  'The daily digest sweep (Issue #125): collapses each (recipient, '
  'profile) group of held notification_outbox rows (deliver_after = '
  '''infinity'') into exactly one deliverable row once the guardian''s '
  'chosen digest time -- shifted out of quiet hours via '
  'resolve_deliver_after(), exactly like immediate alerts -- has passed. '
  'The surviving push carries the same fixed generic copy as every other '
  'alert; absorbed rows are marked sent without their own push. A group '
  'whose preference row is gone is dropped. Each group is isolated in its '
  'own exception block (mirroring scan_missed_entry_reminders'' #7 fix) so '
  'one tenant''s failure never aborts the sweep for the others. Returns '
  'the number of digests released.';

revoke all on function public.sweep_alert_digests() from public, anon, authenticated;

-- The sweep''s driving query (held rows grouped by recipient/profile,
-- ordered by created_at) gets its own partial index -- tiny by
-- construction, since a group collapses to nothing at each digest.
create index notification_outbox_held_digest_idx
  on public.notification_outbox (recipient_user_id, profile_id, created_at)
  where deliver_after = 'infinity'::timestamptz and sent_at is null;

-- ---------------------------------------------------------------------------
-- 5. Wire the digest sweep into both cron wrappers, ahead of
-- trigger_push_dispatch() so a due digest is dispatched in the same
-- 15-minute drain that released it (the same reason the drain exists at
-- all -- review #9 of the caregiver-alerts plan). Prior bodies carried
-- forward verbatim; each step stays in its own isolated sub-block.
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
    perform public.sweep_alert_digests();
  exception
    when others then
      raise notice 'run_caregiver_alert_drain: sweep_alert_digests failed: %', sqlerrm;
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
  'Sweeps stuck claims, releases due alert digests (Issue #125), and '
  'nudges push-dispatch every 15 minutes (#9 review fix), so a '
  'quiet-hours release, a digest, or a retry reaches the recipient within '
  'one cadence interval rather than waiting for the next 09:00 UTC nightly '
  'run (AE4). The missed-entry scan is not duplicated here -- it stays on '
  'the nightly job alone.';

revoke all on function public.run_caregiver_alert_drain() from public, anon, authenticated;

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

  begin
    perform public.sweep_alert_digests();
  exception
    when others then
      raise notice 'run_nightly_caregiver_alerts_job: sweep_alert_digests failed: %', sqlerrm;
  end;

  -- Already self-guards (see its own exception handler); still run
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
  'Runs the missed-entry scan, the outbox sweep, the alert-digest sweep '
  '(Issue #125), and a dispatch nudge, each isolated in its own sub-block '
  '(#15 review fix) so one tenant''s bad data or any other single-step '
  'failure cannot silently stop the others from running, for every '
  'tenant, until the next deploy.';
