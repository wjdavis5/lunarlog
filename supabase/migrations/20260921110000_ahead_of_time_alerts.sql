-- ===========================================================================
-- 20260921110000_ahead_of_time_alerts.sql
-- Issue #851 (the deferred half of PR #988): ahead-of-time guardian alerts.
--
-- The supplies kit and the in-app restock nudge shipped in
-- 20260920130000_supplies_kit.sql / lib/domain/logistics/restock_nudge.dart.
-- This migration adds the server-side, forward-looking half the owner
-- approved on 2026-09-20: three new content-free outbox kinds -- `period_soon`,
-- `restock_due`, and `pms_soon` -- enqueued by a new nightly scan off the
-- SAME client-published `profile_reminder_windows.estimated_next_start` the
-- missed-entry scan already reads. Push copy stays the fixed generic string
-- (supabase/functions/_shared/notification_copy.ts, pinned character-for-
-- character to lib/domain/notifications/scheduling.dart's kReminderTitle/
-- kReminderBody); no new column on notification_outbox can ever carry health
-- content.
--
-- What each kind means:
--   * period_soon  -- the next estimate is within `ahead_of_time_lead_days()`
--                     (5) days of today, mirroring the issue's own
--                     `estimate - today <= 5` and the in-app rule's
--                     `kRestockLeadDays`. An estimate already past today
--                     counts (the window is open; the heads-up is still
--                     useful), exactly like restockNudgeFor().
--   * restock_due  -- period_soon's window AND at least one live, unstocked
--                     `visit_prep_items` row with kind = 'supply'. This is
--                     lib/domain/logistics/restock_nudge.dart's rule,
--                     expressed in SQL against the synced table rather than a
--                     client-published low-supply flag -- the server already
--                     holds the same rows.
--   * pms_soon     -- period_soon's window AND at least
--                     `ahead_of_time_min_pms_intervals()` (3) logged PMS
--                     intervals (`day_entries.pms`, maximal strictly
--                     consecutive runs, the same derivation
--                     lib/domain/prediction/pms.dart's derivePmsIntervals()
--                     uses). Fewer than three usable intervals is the same
--                     hard minimum the local prediction applies
--                     (kMinPmsIntervalsForPrediction); below it the server
--                     never fires rather than guessing.
--
-- All three are OFF by default, per guardian, and independently toggled
-- (notification_preferences.alert_on_period_soon / alert_on_restock /
-- alert_on_pms_soon). The scan's guards still respect the existing machinery:
-- quiet hours via resolve_deliver_after(), and the per-guardian daily push
-- ceiling -- overflow is held with deliver_after = 'infinity' so
-- sweep_alert_digests() rolls it into the guardian's next digest, which is
-- what "respect the digest cadence" means for kinds that carry no cadence
-- column of their own.
--
-- Dedupe is per (recipient, profile, kind, window). Rather than a second
-- state table, public.missed_entry_alert_state is generalised with a `kind`
-- discriminator (defaulting to 'missed_entry' for every existing row) and a
-- (profile_id, user_id, kind) primary key: each row records the
-- estimated_next_start last enqueued for, so a nightly re-run over an
-- unchanged window enqueues nothing and only a freshly published estimate
-- re-arms the alert -- the same shape the missed-entry scan already uses.
-- Generalising that table (rather than adding an analogous one) means
-- revocation (revoke_guardian deletes by (profile, user)), account/profile
-- deletion, and export_account_data() all keep covering the marker with no
-- further wiring, and the Issue #292 user-keyed-table guard stays satisfied.
--
-- This file only adds and `create or replace`s; no merged migration is
-- edited in place. The replaced functions below carry their prior bodies
-- verbatim plus exactly the new steps.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The three new outbox kinds. The CHECK is a named constraint, so it is
--    dropped and re-added rather than replaced in place.
-- ---------------------------------------------------------------------------

alter table public.notification_outbox
  drop constraint notification_outbox_kind_check;

alter table public.notification_outbox
  add constraint notification_outbox_kind_check
  check (kind in (
    'logged', 'cycle_start', 'high_severity', 'missed_entry',
    'period_soon', 'restock_due', 'pms_soon'
  ));

comment on constraint notification_outbox_kind_check on public.notification_outbox is
  'Issue #5 then Issue #851: the closed set of alert kinds a guardian can '
  'receive. The four pre-#851 kinds are entry-reactive; the three #851 kinds '
  'are ahead-of-time (period_soon, restock_due, pms_soon), enqueued by '
  'public.scan_ahead_of_time_alerts() off the published cycle estimate. '
  'Every kind is content-free.';

-- ---------------------------------------------------------------------------
-- 2. The three per-guardian opt-ins (all off by default, R4's posture).
-- ---------------------------------------------------------------------------

alter table public.notification_preferences
  add column alert_on_period_soon boolean not null default false,
  add column alert_on_restock boolean not null default false,
  add column alert_on_pms_soon boolean not null default false;

comment on column public.notification_preferences.alert_on_period_soon is
  'Issue #851: opt-in for the ahead-of-time period_soon alert. Off by '
  'default, like every other caregiver alert (R4).';
comment on column public.notification_preferences.alert_on_restock is
  'Issue #851: opt-in for the restock_due alert (unstocked supplies within '
  'the upcoming-period window). Off by default.';
comment on column public.notification_preferences.alert_on_pms_soon is
  'Issue #851: opt-in for the pms_soon heads-up. Off by default, and only '
  'ever fires for a profile with at least three logged PMS intervals.';

-- ---------------------------------------------------------------------------
-- 3. Named constants (a named constant, not a magic number).
-- ---------------------------------------------------------------------------

-- The lead window for all three ahead-of-time kinds. 5 days is the issue's
-- own `period_soon` threshold and mirrors
-- lib/domain/logistics/restock_nudge.dart's kRestockLeadDays.
create or replace function public.ahead_of_time_lead_days() returns integer
language sql
immutable
set search_path = ''
as $$
  select 5;
$$;

comment on function public.ahead_of_time_lead_days() is
  'The named lead window (Issue #851): how many days ahead of the published '
  'next-period estimate period_soon / restock_due / pms_soon fire. 5, '
  'mirroring the in-app restock rule (kRestockLeadDays).';

-- The PMS sample floor: fewer than this many logged PMS intervals and
-- pms_soon never fires. Mirrors lib/domain/prediction/pms.dart's
-- kMinPmsIntervalsForPrediction (3).
create or replace function public.ahead_of_time_min_pms_intervals() returns integer
language sql
immutable
set search_path = ''
as $$
  select 3;
$$;

comment on function public.ahead_of_time_min_pms_intervals() is
  'The named PMS sample floor (Issue #851): the minimum number of logged PMS '
  'intervals below which pms_soon never fires -- no heads-up on a sample too '
  'thin to mean anything. 3, mirroring kMinPmsIntervalsForPrediction.';

revoke all on function public.ahead_of_time_lead_days() from public, anon, authenticated;
revoke all on function public.ahead_of_time_min_pms_intervals() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Generalise missed_entry_alert_state with a kind discriminator. Every
--    existing row reads back as kind = 'missed_entry', and the primary key
--    becomes (profile_id, user_id, kind). Owned exclusively by the two scans
--    (scan_missed_entry_reminders and scan_ahead_of_time_alerts); no
--    policies, no grants; both FKs already cascade.
-- ---------------------------------------------------------------------------

alter table public.missed_entry_alert_state
  add column kind text not null default 'missed_entry'
    constraint missed_entry_alert_state_kind_check
    check (kind in ('missed_entry', 'period_soon', 'restock_due', 'pms_soon'));

alter table public.missed_entry_alert_state
  drop constraint missed_entry_alert_state_pkey;

alter table public.missed_entry_alert_state
  add primary key (profile_id, user_id, kind);

comment on table public.missed_entry_alert_state is
  'Per-(recipient, profile, kind) cycle-window dedupe marker, shared by '
  'public.scan_missed_entry_reminders() (kind = ''missed_entry'') and '
  'public.scan_ahead_of_time_alerts() (Issue #851: ''period_soon'', '
  '''restock_due'', ''pms_soon''). Records the estimated_next_start the last '
  'alert was enqueued for, so a nightly re-run over an unchanged window '
  'enqueues nothing and a freshly published estimate re-arms it. Owned '
  'exclusively by the two scans (SECURITY DEFINER); no policies, no grants. '
  'Issue #851 generalised this from a per-(profile, guardian) marker: a '
  'dedicated second table would have needed its own revocation cleanup, '
  'export projection, and Issue #292 accounting, while this one already has '
  'all three.';

comment on column public.missed_entry_alert_state.kind is
  'Issue #851: which alert kind this marker dedupes -- ''missed_entry'' for '
  'the pre-#851 scan, or one of the ahead-of-time kinds. An existing row '
  'defaults to ''missed_entry'', preserving the missed-entry scan''s exact '
  'prior behaviour.';

-- ---------------------------------------------------------------------------
-- 5. scan_ahead_of_time_alerts: the nightly ahead-of-time scan (Issue #851).
--    SECURITY DEFINER -- it reads day_entries/visit_prep_items across
--    families but never their note/tag content. Per-row exception isolation
--    mirrors scan_missed_entry_reminders' round-2 review #7 fix: one
--    tenant's failure must never abort the scan for every other tenant.
-- ---------------------------------------------------------------------------

create or replace function public.scan_ahead_of_time_alerts() returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := current_date;
  v_lead integer := public.ahead_of_time_lead_days();
  v_min_pms integer := public.ahead_of_time_min_pms_intervals();
  v_count integer := 0;
  v_row record;
  v_est date;
  v_within boolean;
  v_has_low_supply boolean;
  v_pms_intervals integer;
  v_kind text;
  v_last date;
  v_pushes_today bigint;
begin
  for v_row in
    select p.user_id, p.profile_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           p.alert_on_period_soon, p.alert_on_restock, p.alert_on_pms_soon,
           w.estimated_next_start
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id and g.user_id = p.user_id
      join public.profile_reminder_windows w
        on w.profile_id = p.profile_id
     where g.status = 'accepted'
       and (p.alert_on_period_soon or p.alert_on_restock or p.alert_on_pms_soon)
  loop
    begin
      v_est := v_row.estimated_next_start;
      -- An estimate already past today counts (the window is open) -- the
      -- same reading restockNudgeFor() uses. Only the upper bound is a gate.
      v_within := v_est is not null and v_est <= v_today + v_lead;

      -- restock_due needs the supply check only inside the window; skip the
      -- query otherwise so an out-of-window row costs nothing.
      if v_within and v_row.alert_on_restock then
        select exists (
          select 1
            from public.visit_prep_items i
           where i.profile_id = v_row.profile_id
             and i.kind = 'supply'
             and i.deleted_at is null
             and not i.is_checked
        ) into v_has_low_supply;
      else
        v_has_low_supply := false;
      end if;

      -- Logged PMS intervals: maximal runs of strictly consecutive live PMS
      -- days -- the same islands derivation derivePmsIntervals() applies.
      if v_within and v_row.alert_on_pms_soon then
        select count(distinct grp) into v_pms_intervals
          from (
            select d.local_date
                   - (row_number() over (order by d.local_date))::int as grp
              from (
                select distinct local_date
                  from public.day_entries
                 where profile_id = v_row.profile_id
                   and deleted_at is null
                   and pms
              ) d
          ) g;
      else
        v_pms_intervals := 0;
      end if;

      for v_kind in
        select k
          from unnest(array['period_soon', 'restock_due', 'pms_soon']) k
         where (k = 'period_soon' and v_row.alert_on_period_soon)
            or (k = 'restock_due' and v_row.alert_on_restock)
            or (k = 'pms_soon' and v_row.alert_on_pms_soon)
      loop
        if not v_within then
          continue;
        end if;
        if v_kind = 'restock_due' and not v_has_low_supply then
          continue;
        end if;
        if v_kind = 'pms_soon' and v_pms_intervals < v_min_pms then
          continue;
        end if;

        -- Per (recipient, profile, kind, window) dedupe: only a change in
        -- the published estimate re-arms the alert.
        select s.last_enqueued_for into v_last
          from public.missed_entry_alert_state s
         where s.profile_id = v_row.profile_id
           and s.user_id = v_row.user_id
           and s.kind = v_kind;
        if v_last = v_est then
          continue;
        end if;

        -- Respect the per-guardian daily push ceiling exactly like the
        -- immediate entry-alert path: overflow is held with deliver_after =
        -- 'infinity' so sweep_alert_digests() rolls it into the next digest.
        select count(*) into v_pushes_today
          from public.notification_outbox o
         where o.recipient_user_id = v_row.user_id
           and o.profile_id = v_row.profile_id
           and o.kind <> 'missed_entry'
           and o.deliver_after < 'infinity'::timestamptz
           and o.created_at >= public.local_day_start(now(), v_row.time_zone);

        if v_pushes_today >= public.alert_daily_push_ceiling() then
          insert into public.notification_outbox
            (profile_id, recipient_user_id, kind, deliver_after)
          values (
            v_row.profile_id, v_row.user_id, v_kind, 'infinity'::timestamptz
          );
        else
          insert into public.notification_outbox
            (profile_id, recipient_user_id, kind, deliver_after)
          values (
            v_row.profile_id, v_row.user_id, v_kind,
            public.resolve_deliver_after(
              now(), v_row.quiet_hours_start, v_row.quiet_hours_end,
              v_row.time_zone
            )
          );
        end if;

        insert into public.missed_entry_alert_state
          (profile_id, user_id, kind, last_enqueued_for)
        values (v_row.profile_id, v_row.user_id, v_kind, v_est)
        on conflict (profile_id, user_id, kind) do update
          set last_enqueued_for = excluded.last_enqueued_for;

        v_count := v_count + 1;
      end loop;
    exception
      when others then
        raise notice 'scan_ahead_of_time_alerts: profile % / user % failed: %',
          v_row.profile_id, v_row.user_id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

comment on function public.scan_ahead_of_time_alerts() is
  'The ahead-of-time half of the nightly caregiver alert job (Issue #851). '
  'For each accepted guardian who opted in, enqueues content-free '
  'period_soon / restock_due / pms_soon rows when the published '
  'estimated_next_start is within ahead_of_time_lead_days(): period_soon '
  'always, restock_due only with a live unstocked supply item, pms_soon only '
  'with at least ahead_of_time_min_pms_intervals() logged PMS intervals. '
  'Deduped per (recipient, profile, kind, window) via '
  'missed_entry_alert_state, quiet-hours shifted with resolve_deliver_after, '
  'and subject to the same daily push ceiling as immediate alerts (overflow '
  'held for the digest). Each row is isolated in its own begin/exception '
  'block so one tenant never aborts the scan for the rest. Returns the number '
  'of alert rows enqueued.';

revoke all on function public.scan_ahead_of_time_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. Re-emit scan_missed_entry_reminders: the marker table gained `kind`, so
--    its join and insert must stay scoped to kind = 'missed_entry' (a bare
--    (profile, user) join would now match every ahead-of-time kind's marker
--    and the conflict target must name the new key). Body carried forward
--    verbatim from 20260906230000_reminder_windows_and_cron.sql; the join
--    predicate, the inserted `kind`, and the conflict target are the only
--    edits.
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
      -- see missed_entry_alert_state's comment. Issue #851 narrowed the
      -- join to kind = 'missed_entry' so an ahead-of-time marker can never
      -- masquerade as a missed-entry marker. A guardian with no row yet
      -- here has never been enqueued for anything, hence the left join.
      left join public.missed_entry_alert_state s
        on s.profile_id = p.profile_id and s.user_id = p.user_id
       and s.kind = 'missed_entry'
     where p.missed_entry_days is not null
       and g.status = 'accepted'
  loop
    -- #7 (round-2 review): round-1 #15 asked for two things -- splitting
    -- the cron statements (done, see run_nightly_caregiver_alerts_job()
    -- below) *and* per-row exception isolation in this loop. Only the cron
    -- split landed the first time. Without this begin/exception, any error
    -- on one tenant's row (a concurrent profile or user deletion racing the
    -- notification_outbox FK insert, for instance) aborts the whole
    -- cross-tenant scan, silently starving every other guardian's
    -- missed-entry reminder for that run.
    begin
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

        insert into public.missed_entry_alert_state
          (profile_id, user_id, kind, last_enqueued_for)
        values (v_row.profile_id, v_row.user_id, 'missed_entry', v_row.estimated_next_start)
        on conflict (profile_id, user_id, kind) do update
          set last_enqueued_for = excluded.last_enqueued_for;

        v_count := v_count + 1;
      end if;
    exception
      when others then
        raise notice 'scan_missed_entry_reminders: profile % / user % failed: %',
          v_row.profile_id, v_row.user_id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;

comment on function public.scan_missed_entry_reminders() is
  'Enqueues one missed_entry alert per (guardian, profile) whose newest '
  'live entry is older than the guardian''s threshold and whose published '
  'reminder window says the estimate has passed or an episode is open '
  '(R14). Deduped per (profile, guardian, kind = ''missed_entry'') via '
  'missed_entry_alert_state (KTD8, #8 review fix; Issue #851 generalised the '
  'marker table with a kind discriminator), so a re-run before a fresh '
  'window is published enqueues nothing (R15), and one guardian being '
  'enqueued never suppresses a co-guardian with a different threshold on the '
  'same profile. Each row is isolated in its own begin/exception block '
  '(round-2 review #7) so one tenant''s failure can never abort the scan for '
  'every other tenant.';

revoke all on function public.scan_missed_entry_reminders() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. Wire the scan into the nightly job, in its own isolated sub-block,
--    right after the missed-entry scan. The 15-minute drain deliberately
--    does not run it (its window granularity is whole days, exactly like the
--    missed-entry scan). Prior body carried forward verbatim from
--    20260908110000_alert_digest_cadence.sql.
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
    perform public.scan_ahead_of_time_alerts();
  exception
    when others then
      raise notice 'run_nightly_caregiver_alerts_job: scan_ahead_of_time_alerts failed: %', sqlerrm;
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
  'Runs the missed-entry scan, the Issue #851 ahead-of-time scan, the outbox '
  'sweep, the alert-digest sweep (Issue #125), and a dispatch nudge, each '
  'isolated in its own sub-block (#15 review fix) so one tenant''s bad data '
  'or any other single-step failure cannot silently stop the others from '
  'running, for every tenant, until the next deploy.';

revoke all on function public.run_nightly_caregiver_alerts_job() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. cancel_outbox_on_preference_off: extend the transactional cancel
--    (LLA-076) to the three new booleans. Prior body carried forward
--    verbatim from 20260914104000_notification_push_correctness.sql; three
--    new branches appended.
-- ---------------------------------------------------------------------------

create or replace function public.cancel_outbox_on_preference_off()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- 'logged': off when the master alert_on_log switch is now false, or its
  -- own cadence column is now 'off'.
  if (not new.alert_on_log or new.log_cadence = 'off')
     and (old.alert_on_log is distinct from new.alert_on_log
          or old.log_cadence is distinct from new.log_cadence) then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'logged'
       and sent_at is null;
  end if;

  -- 'cycle_start': same master switch, gated by its own cadence column.
  if (not new.alert_on_log or new.cycle_start_cadence = 'off')
     and (old.alert_on_log is distinct from new.alert_on_log
          or old.cycle_start_cadence is distinct from new.cycle_start_cadence) then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'cycle_start'
       and sent_at is null;
  end if;

  -- 'high_severity': same master switch, gated by its own cadence column.
  if (not new.alert_on_log or new.high_severity_cadence = 'off')
     and (old.alert_on_log is distinct from new.alert_on_log
          or old.high_severity_cadence is distinct from new.high_severity_cadence) then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'high_severity'
       and sent_at is null;
  end if;

  -- 'missed_entry': its own off/immediate control (missed_entry_days
  -- null = off), independent of alert_on_log.
  if new.missed_entry_days is null
     and old.missed_entry_days is distinct from new.missed_entry_days then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'missed_entry'
       and sent_at is null;
  end if;

  -- Issue #851: the three ahead-of-time kinds, each gated by its own
  -- boolean opt-in (there is no master switch for them).
  if not new.alert_on_period_soon
     and old.alert_on_period_soon is distinct from new.alert_on_period_soon then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'period_soon'
       and sent_at is null;
  end if;

  if not new.alert_on_restock
     and old.alert_on_restock is distinct from new.alert_on_restock then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'restock_due'
       and sent_at is null;
  end if;

  if not new.alert_on_pms_soon
     and old.alert_on_pms_soon is distinct from new.alert_on_pms_soon then
    delete from public.notification_outbox
     where recipient_user_id = new.user_id
       and profile_id = new.profile_id
       and kind = 'pms_soon'
       and sent_at is null;
  end if;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

comment on function public.cancel_outbox_on_preference_off() is
  'AFTER UPDATE trigger on notification_preferences (LLA-076, issue #630; '
  'extended by Issue #851): when a kind''s governing preference transitions '
  'to off, deletes every unsent notification_outbox row of that kind for '
  'this (user, profile) -- immediate rows not yet claimed and '
  'daily_digest-held rows alike. As well as the alert_on_log master switch '
  'and the per-kind cadences / missed_entry_days, this now covers the #851 '
  'ahead-of-time booleans (alert_on_period_soon, alert_on_restock, '
  'alert_on_pms_soon), each gated only by itself. Deliberately fires per '
  'changed kind only (the OLD/NEW comparison), so an unrelated preference '
  'edit (e.g. quiet hours) never touches another kind''s queue.';

revoke execute on function public.cancel_outbox_on_preference_off() from public, anon, authenticated;

drop trigger if exists notification_preferences_cancel_outbox_on_off
  on public.notification_preferences;

create trigger notification_preferences_cancel_outbox_on_off
  after update on public.notification_preferences
  for each row
  when (
    old.alert_on_log is distinct from new.alert_on_log
    or old.log_cadence is distinct from new.log_cadence
    or old.cycle_start_cadence is distinct from new.cycle_start_cadence
    or old.high_severity_cadence is distinct from new.high_severity_cadence
    or old.missed_entry_days is distinct from new.missed_entry_days
    or old.alert_on_period_soon is distinct from new.alert_on_period_soon
    or old.alert_on_restock is distinct from new.alert_on_restock
    or old.alert_on_pms_soon is distinct from new.alert_on_pms_soon
  )
  execute function public.cancel_outbox_on_preference_off();

-- ---------------------------------------------------------------------------
-- 9. resolve_notification_outbox_dispatch: the dispatch-time revalidation
--    (LLA-074/075/076) now knows the three new kinds' governing booleans.
--    Prior body carried forward verbatim from
--    20260914104000_notification_push_correctness.sql; the preference fetch
--    and the kind branch are the only edits.
-- ---------------------------------------------------------------------------

create or replace function public.resolve_notification_outbox_dispatch(
  p_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_pref record;
  v_deliver_at timestamptz;
  v_cadence text;
begin
  select o.profile_id, o.recipient_user_id, o.kind
    into v_row
    from public.notification_outbox o
   where o.id = p_id;

  if not found then
    -- LLA-074/LLA-076: already deleted by a revocation (revoke_guardian)
    -- or a preference-off (cancel_outbox_on_preference_off() above) that
    -- landed between this invocation's claim and this check. Nothing to
    -- cancel -- it is already gone.
    return jsonb_build_object('action', 'cancel', 'reason', 'missing');
  end if;

  select g.status,
         p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
         p.alert_on_log, p.log_cadence, p.cycle_start_cadence,
         p.high_severity_cadence, p.missed_entry_days,
         p.alert_on_period_soon, p.alert_on_restock, p.alert_on_pms_soon
    into v_pref
    from public.profile_guardians g
    join public.notification_preferences p
      on p.profile_id = g.profile_id and p.user_id = g.user_id
   where g.profile_id = v_row.profile_id
     and g.user_id = v_row.recipient_user_id;

  -- LLA-074: no guardian/preference row at all, or membership no longer
  -- 'accepted' -- a revocation whose own outbox delete hasn't reached
  -- this row yet (or reached it via a different path than revoke_guardian).
  if not found or v_pref.status is distinct from 'accepted' then
    return jsonb_build_object('action', 'cancel', 'reason', 'revoked');
  end if;

  if v_row.kind = 'missed_entry' then
    if v_pref.missed_entry_days is null then
      return jsonb_build_object('action', 'cancel', 'reason', 'preference_off');
    end if;
  elsif v_row.kind in ('period_soon', 'restock_due', 'pms_soon') then
    -- Issue #851: each ahead-of-time kind is governed solely by its own
    -- boolean opt-in -- no cadence column, no master switch.
    if (v_row.kind = 'period_soon' and not v_pref.alert_on_period_soon)
       or (v_row.kind = 'restock_due' and not v_pref.alert_on_restock)
       or (v_row.kind = 'pms_soon' and not v_pref.alert_on_pms_soon) then
      return jsonb_build_object('action', 'cancel', 'reason', 'preference_off');
    end if;
  else
    if not v_pref.alert_on_log then
      return jsonb_build_object('action', 'cancel', 'reason', 'preference_off');
    end if;
    v_cadence := case v_row.kind
      when 'cycle_start' then v_pref.cycle_start_cadence
      when 'high_severity' then v_pref.high_severity_cadence
      else v_pref.log_cadence
    end;
    if v_cadence = 'off' then
      return jsonb_build_object('action', 'cancel', 'reason', 'preference_off');
    end if;
  end if;

  -- LLA-075: quiet hours resolved against *now*, not the enqueue-time
  -- value already baked into deliver_after -- a delayed dispatch must not
  -- slip into a window that has opened since.
  v_deliver_at := public.resolve_deliver_after(
    now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_pref.time_zone
  );
  if v_deliver_at > now() then
    return jsonb_build_object('action', 'defer', 'deliver_after', v_deliver_at);
  end if;

  return jsonb_build_object('action', 'send');
end;
$$;

comment on function public.resolve_notification_outbox_dispatch(uuid) is
  'Issue #630 (LLA-074, LLA-075, LLA-076; extended by Issue #851): '
  're-validates one just-claimed notification_outbox row immediately before '
  'push-dispatch/index.ts touches any device. Returns {"action": "cancel", '
  '"reason": ...} when the row is gone or the recipient''s guardian '
  'membership or governing preference no longer allows it -- for the #851 '
  'ahead-of-time kinds that governing preference is the kind''s own boolean '
  'rather than alert_on_log/cadence (LLA-074/LLA-076 -- the caller deletes '
  'the row rather than sending), {"action": "defer", "deliver_after": ...} '
  'when quiet hours have opened since the row became due (LLA-075 -- the '
  'caller clears the claim and updates deliver_after without counting it as '
  'a failed attempt), or {"action": "send"} when still eligible. The window '
  'between a send already handed to FCM and this check cannot be closed by '
  'any database-side mechanism -- that send cannot be recalled -- so this is '
  '"checked immediately before handoff", not a guarantee against every '
  'possible race.';

revoke all on function public.resolve_notification_outbox_dispatch(uuid) from public, anon, authenticated;
