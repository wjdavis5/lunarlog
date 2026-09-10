-- Migration: 20260910000000_high_severity_intensity.sql
-- Issue #256: the intensity/severity model for tracked observations -- the
-- severity-consumer half. `observations.intensity` itself (nullable smallint,
-- CHECK 1-5) already landed with the #240 foundation
-- (20260908160000_observations.sql): column, tombstone-clearing backstop,
-- `sync_push` key allowlist/parse/insert/update paths, and the local Drift
-- mirror are all live, so this migration touches none of that storage. What
-- it replaces is the one consumer still faking severity: the caregiver-alert
-- trigger's `v_is_high_severity := new.flow = 'heavy'` proxy
-- (20260906220000_notification_outbox.sql lines 195-197, whose own header
-- documented it as a forced substitute "if a future taxonomy revision adds a
-- severity marker, update public.enqueue_caregiver_alerts() to match" -- this
-- is that update).
--
-- Why a NEW migration rather than editing the old one: a migration that has
-- reached `main` is never edited in place (house rule; a from-scratch
-- environment must replay byte-identical history). The workaround comment the
-- issue asks to remove lives inside the trigger FUNCTION body, so
-- create-or-replacing the function here removes it from the live database --
-- the merged file's historical text stays for the record, superseded.
--
-- The issue's "land it in the same migration that introduces intensity" is
-- satisfied as closely as the timeline allows: intensity landed first
-- (#240, merged), and this migration is the earliest possible follow-up, so
-- the documented proxy is never live on any environment that applies both.
--
-- What lands here:
--   1. `enqueue_caregiver_alerts()` (day_entries AFTER trigger) re-emitted
--      from its latest body (20260908200000_flow_model.sql, which carries
--      issue #125's cadence/digest/ceiling/coalescing plumbing and #167's
--      bulk-import guard) with exactly one behavioural change:
--      `v_is_high_severity` is now true when the existing flow case holds
--      (`heavy`/`super_heavy` -- preserved verbatim, per the issue: "a
--      heavy-flow day with no logged pain intensity should still alert") OR
--      a live `observations` row for the same (profile_id, local_date) has
--      `intensity >= 4` on a severity-bearing category.
--   2. A new `enqueue_observation_high_severity_alerts()` trigger function
--      plus AFTER INSERT/UPDATE triggers on `observations` themselves: a
--      day_entries write is not the only way severe pain lands (logging a
--      pain intensity from the day sheet writes an observations row and may
--      not touch the day entry at all), so the observations write must fan
--      out its own high_severity alerts -- same preference ladder, same
--      cadence/digest/ceiling/coalescing plumbing, same writer exclusion.
--
-- Severity-bearing categories: exactly `array['pain']` today, per the
-- issue's own example. The set is a named constant in both trigger
-- functions and inlined in the observations WHEN clauses (a WHEN clause is
-- parsed outside the function body and cannot see plpgsql constants) --
-- four literal sites that MUST stay in sync; each carries a pointer to the
-- others. Extending the set is a deliberate, reviewed edit here, never a
-- client-side guess.
--
-- Legacy/unknown semantics (issue AC): `intensity IS NULL` means "no
-- severity recorded" -- never "low severity". `intensity >= 4` is
-- null-rejecting in SQL (NULL comparison yields NULL, not true), so a
-- legacy or ungraded row can never satisfy the predicate; likewise a row
-- whose category is not in the severity-bearing set. A severity alert
-- fires only on an explicit, graded, severity-bearing observation.
--
-- Double-alert note: one user action can legitimately fire BOTH triggers
-- (the day sheet's autosave writes the day entry and the graded pain
-- observation). The issue explicitly wants the flow case preserved "in
-- addition to" the intensity case, so this is by design at the event level;
-- at the delivery level issue #125's alert_coalesce_window() already
-- collapses same-(recipient, profile, kind) pushes inside the window, and
-- the daily ceiling bounds the rest, so a guardian is never double-pushed
-- for one action under the default plumbing.

-- ---------------------------------------------------------------------------
-- 1. enqueue_caregiver_alerts(): re-emitted from
--    20260908200000_flow_model.sql's body verbatim except the
--    v_is_high_severity assignment and its comment (issue #256). The #125
--    cadence/digest/ceiling/coalescing plumbing, the #167 bulk-import guard,
--    the #6 episode-merge window, and the writer exclusion are untouched.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_caregiver_alerts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Issue #256: the severity-bearing observation categories. Kept in sync
  -- with the copy in public.enqueue_observation_high_severity_alerts() and
  -- the two WHEN clauses on public.observations below (all four sites).
  c_severity_bearing_categories constant text[] := array['pain'];
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
  -- Issue #167: see touch_sync_signal()'s identical guard above -- a bulk
  -- import must not fan out into one notification_outbox row per eligible
  -- guardian per imported row.
  if coalesce(current_setting('lunarlog.bulk_import', true), '') = 'on' then
    return null;
  end if;

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

  v_is_bleed := new.flow in ('light', 'medium', 'heavy', 'super_heavy');

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
       and flow in ('light', 'medium', 'heavy', 'super_heavy')
  ) into v_prev_bleed;

  -- R7: a cycle start is a bleed day with no bleed day in the merge window
  -- (or nothing at all -- v_prev_bleed is false either way).
  v_is_cycle_start := v_is_bleed and not v_prev_bleed;

  -- Issue #256, replacing 20260906220000's Q1 workaround ("heavy flow alone
  -- stands in for high severity"): a day is high severity when the flow
  -- case holds (preserved verbatim -- a heavy-flow day with no graded pain
  -- still alerts) OR any live observation that same day grades a
  -- severity-bearing category at intensity >= 4. `intensity >= 4` is
  -- null-rejecting, so a legacy/ungraded row (intensity IS NULL means "no
  -- severity recorded", never "low") can never fire this on its own.
  v_is_high_severity := new.flow in ('heavy', 'super_heavy')
    or exists (
      select 1 from public.observations o
       where o.profile_id = new.profile_id
         and o.local_date = new.local_date
         and o.deleted_at is null
         and o.intensity >= 4
         and o.category = any (c_severity_bearing_categories)
    );

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
    -- guard would never suppress anything. This is also what keeps the
    -- new observations trigger below from double-pushing a guardian the
    -- day_entries trigger (or vice versa) already pushed for the same
    -- underlying action.
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

-- Carries 20260908200000's comment forward; the severity sentence replaces
-- the Q1 workaround note.
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
  'and the alert_coalesce_window() coalescing guard. Issue #167: no-ops '
  'entirely while lunarlog.bulk_import = ''on'' -- a bulk import is not a '
  '"someone logged an entry" event and must not page anyone. Issue #256: '
  'high severity is the flow case (heavy/super_heavy, preserved) OR any '
  'live observation that day grading a severity-bearing category at '
  'intensity >= 4 (intensity NULL = "no severity recorded", never low); '
  'the observations-side trigger '
  'public.enqueue_observation_high_severity_alerts() covers the write that '
  'never touches day_entries at all.';

revoke execute on function public.enqueue_caregiver_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. enqueue_observation_high_severity_alerts(): the observations-side
--    trigger (issue #256's "AFTER INSERT/UPDATE trigger on observations
--    that enqueues a high_severity caregiver alert when intensity >= 4 on a
--    severity-bearing category"). A graded pain observation can be written
--    without any day_entries content change (a day with flow 'none' whose
--    pain row is graded from the day sheet), so the day_entries trigger
--    alone would miss it.
--
--    The fan-out loop is issue #125's plumbing, identical shape:
--    bulk-import guard (#167), writer exclusion, the
--    alert_on_cycle_start_only narrowing evaluated against the DAY's
--    stored cycle-start state (an observation does not carry flow, so the
--    day_entries-row computation is re-derived for its date), and the
--    high_severity cadence/digest/ceiling/coalescing ladder. v_kind is
--    always 'high_severity' here -- the function IS the high-severity
--    narrowing, so alert_on_high_severity needs no extra predicate (a
--    guardian with the narrowing off receives every log event, which this
--    event is a member of, exactly as on the day_entries trigger).
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_observation_high_severity_alerts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Issue #256: severity-bearing observation categories. Kept in sync with
  -- the copy in public.enqueue_caregiver_alerts() and the two WHEN clauses
  -- on public.observations below (all four sites).
  c_severity_bearing_categories constant text[] := array['pain'];
  v_writer_id uuid;
  v_is_cycle_start boolean;
  v_pref record;
  v_cadence text;
  v_pushes_today bigint;
begin
  -- Issue #167: a bulk import must not page anyone (same guard as
  -- enqueue_caregiver_alerts; bulk_import_entries() sets the GUC for the
  -- whole import transaction).
  if coalesce(current_setting('lunarlog.bulk_import', true), '') = 'on' then
    return null;
  end if;

  -- A tombstone carries no payload at all
  -- (observations_tombstone_payload_check), so it can never satisfy the
  -- predicate; the explicit guard documents the intent and keeps the
  -- function safe if the WHEN clauses above it are ever widened.
  if new.deleted_at is not null then
    return null;
  end if;

  -- The severity predicate, re-checked authoritatively (the WHEN clauses
  -- are the cheap per-row filter; this is the same test re-stated so the
  -- function stays correct even if invoked from a trigger with no WHEN).
  -- `intensity >= 4` is null-rejecting: a legacy or ungraded row
  -- (intensity IS NULL = "no severity recorded", issue AC) never fires,
  -- and neither does a category outside the severity-bearing set.
  if new.intensity is null or new.intensity < 4
     or new.category is null
     or new.category <> all (c_severity_bearing_categories) then
    return null;
  end if;

  -- sync_push stamps last_modified_by_user_id from the caller's own
  -- auth.uid(); a legacy/direct-insert row falls back to logged_by_user_id
  -- (observations has no user_id column of its own). Same self-suppression
  -- rule as the day_entries trigger: your own edit never pages you.
  v_writer_id := coalesce(new.last_modified_by_user_id, new.logged_by_user_id);

  -- The alert_on_cycle_start_only narrowing needs the day's cycle-start
  -- state. An observation carries no flow, so re-derive it from the day's
  -- stored day_entries row: a live bleed day with no bleed day in the same
  -- [local_date - 2, local_date - 1] merge window the day_entries trigger
  -- uses (#6). No live day entry (or a non-bleed one) -> not a cycle start.
  select exists (
    select 1 from public.day_entries d
     where d.profile_id = new.profile_id
       and d.local_date = new.local_date
       and d.deleted_at is null
       and d.flow in ('light', 'medium', 'heavy', 'super_heavy')
       and not exists (
         select 1 from public.day_entries p2
          where p2.profile_id = d.profile_id
            and p2.local_date >= d.local_date - 2
            and p2.local_date < d.local_date
            and p2.deleted_at is null
            and p2.flow in ('light', 'medium', 'heavy', 'super_heavy')
       )
  ) into v_is_cycle_start;

  for v_pref in
    select g.user_id as guardian_user_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           p.high_severity_cadence
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id
       and g.user_id = p.user_id
     where p.profile_id = new.profile_id
       and g.status = 'accepted'
       and g.user_id is distinct from v_writer_id
       and p.alert_on_log
       and (not p.alert_on_cycle_start_only or v_is_cycle_start)
       -- No alert_on_high_severity term: this trigger only ever emits a
       -- high_severity event, and both narrowing states pass a
       -- high-severity event on the day_entries trigger too (narrowing on
       -- = exactly these events; narrowing off = all log events, these
       -- included).
  loop
    -- Issue #125 plumbing, high_severity kind only.
    v_cadence := v_pref.high_severity_cadence;

    if v_cadence = 'off' then
      continue;
    end if;

    if v_cadence = 'daily_digest' then
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        'high_severity',
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Daily ceiling (issue #125 step 3), identical count predicate.
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
        'high_severity',
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Coalescing window (issue #125 step 2): also what prevents a
    -- double push when the day_entries trigger already alerted the same
    -- guardian for the same underlying action, and vice versa.
    if exists (
      select 1 from public.notification_outbox o
       where o.recipient_user_id = v_pref.guardian_user_id
         and o.profile_id = new.profile_id
         and o.kind = 'high_severity'
         and o.created_at > now() - public.alert_coalesce_window()
    ) then
      continue;
    end if;

    insert into public.notification_outbox
      (profile_id, recipient_user_id, kind, deliver_after)
    values (
      new.profile_id,
      v_pref.guardian_user_id,
      'high_severity',
      public.resolve_deliver_after(
        now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_pref.time_zone
      )
    );
  end loop;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

comment on function public.enqueue_observation_high_severity_alerts() is
  'AFTER INSERT and AFTER UPDATE trigger function on observations (Issue '
  '#256; two separate triggers so the UPDATE arm can WHEN-filter no-op '
  'resaves against OLD, the same reason enqueue_caregiver_alerts() is '
  'split): enqueues a high_severity caregiver alert when a live '
  'observation grades a severity-bearing category (pain today) at '
  'intensity >= 4. intensity IS NULL is "no severity recorded", never '
  'low, and never alerts. Fan-out mirrors enqueue_caregiver_alerts()''s '
  'issue #125 plumbing (cadence off/daily_digest/immediate with ceiling '
  'and coalescing window) and its #167 bulk-import and writer-exclusion '
  'guards; alert_on_cycle_start_only is evaluated against the day''s '
  'stored day_entries cycle-start state. The coalescing window also '
  'deduplicates against the day_entries trigger when one user action '
  'fires both.';

revoke execute on function public.enqueue_observation_high_severity_alerts()
  from public, anon, authenticated;

-- The WHEN clauses inline the severity-bearing set (a WHEN cannot see the
-- function's plpgsql constant) and restate the predicate the body
-- re-checks. Kept in sync with the two function bodies (all four sites).
--
-- INSERT: every freshly-inserted row is new content by definition, so no
-- OLD-diff is possible -- WHEN carries just the severity predicate.
-- UPDATE: fire when the row is severe AND something about what was logged
-- actually changed -- a no-op resave (every payload column identical, the
-- sync engine's re-save shape) must not re-page anyone (#7's rationale,
-- observations side), while a revive from a tombstone, an intensity
-- crossing into severity, or a real payload edit on an already-severe row
-- is a new event.
create trigger observations_after_insert_high_severity_alert
  after insert on public.observations
  for each row
  when (
    new.deleted_at is null
    and new.intensity >= 4
    and new.category = any (array['pain'])
  )
  execute function public.enqueue_observation_high_severity_alerts();

create trigger observations_after_update_high_severity_alert
  after update on public.observations
  for each row
  when (
    new.deleted_at is null
    and new.intensity >= 4
    and new.category = any (array['pain'])
    and (
      old.deleted_at is not null
      or old.local_date is distinct from new.local_date
      or old.intensity is distinct from new.intensity
      or old.category is distinct from new.category
      or old.code is distinct from new.code
      or old.value_num is distinct from new.value_num
      or old.value_text is distinct from new.value_text
      or old.unit is distinct from new.unit
      or old.excluded is distinct from new.excluded
      or old.observed_at is distinct from new.observed_at
      or old.raw is distinct from new.raw
    )
  )
  execute function public.enqueue_observation_high_severity_alerts();
