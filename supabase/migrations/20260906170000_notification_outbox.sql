-- Migration: 20260906170000_notification_outbox.sql
-- Issue #5, Unit U2: the content-free caregiver-alert outbox (KTD1) and the
-- day_entries AFTER trigger that fans a live write out into one row per
-- eligible guardian (R6-R9, R12).
--
-- Q1 (Open Question in the plan): lib/domain/tags.dart's taxonomy has no
-- distinct "severe" subset -- every code is a plain symptom tag with no
-- severity marker. Per the plan's own fallback, "high severity" therefore
-- narrows to heavy flow alone (new.flow = 'heavy'), not an invented tag
-- list. If a future taxonomy revision adds a severity marker, update
-- public.enqueue_caregiver_alerts() to match rather than guessing here.

create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  recipient_user_id uuid not null
    references auth.users (id) on delete cascade,
  kind text not null
    constraint notification_outbox_kind_check
    check (kind in ('logged', 'cycle_start', 'high_severity', 'missed_entry')),
  created_at timestamptz not null default now(),
  deliver_after timestamptz not null default now(),
  claimed_at timestamptz,
  sent_at timestamptz,
  attempts int not null default 0,
  last_error_kind text
);

comment on table public.notification_outbox is
  'Content-free caregiver-alert delivery queue (Issue #5, KTD1). No column '
  'here can ever hold entry content -- only a profile id, a coarse kind, a '
  'recipient, and timestamps. Written only by '
  'public.enqueue_caregiver_alerts() (this file) and '
  'public.scan_missed_entry_reminders() (U3), both SECURITY DEFINER; drained '
  'only by the push-dispatch Edge Function''s service-role client (U5). No '
  'authenticated policy exists at all -- a guardian never reads their own '
  'queue (this is a delivery queue, not an inbox).';

create index notification_outbox_claim_idx
  on public.notification_outbox (claimed_at, deliver_after);
create index notification_outbox_recipient_idx
  on public.notification_outbox (recipient_user_id, profile_id, kind, created_at);

alter table public.notification_outbox enable row level security;
alter table public.notification_outbox force row level security;

-- Deliberately no policies and no grants for authenticated/anon: RLS with
-- zero policies denies every row to every role it applies to. service_role
-- carries BYPASSRLS and reaches this table regardless (the push-dispatch
-- Edge Function's client, and the SECURITY DEFINER functions below, which
-- run as their owner).
revoke all on table public.notification_outbox from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- resolve_deliver_after: pure quiet-hours resolution (KTD5). A null zone or
-- a null/zero-length quiet-hours pair means "no quiet hours" -- return
-- p_now unchanged. Otherwise resolves the *next* moment outside the window,
-- handling the same-day case and the wrap-past-midnight case (e.g.
-- 22:00-07:00) by comparing local wall-clock time only.
-- ---------------------------------------------------------------------------

create or replace function public.resolve_deliver_after(
  p_now timestamptz,
  p_quiet_start time,
  p_quiet_end time,
  p_zone text
) returns timestamptz
language plpgsql
stable
as $$
declare
  v_local_ts timestamp;
  v_local_date date;
  v_local_time time;
  v_wraps boolean;
  v_inside boolean;
  v_end_date date;
begin
  if p_quiet_start is null or p_quiet_end is null or p_zone is null
     or p_quiet_start = p_quiet_end then
    return p_now;
  end if;

  -- #3 (review): p_zone is a guardian-supplied IANA zone name
  -- (lib/domain/util/timezone.dart, unvalidated at write time) resolved
  -- here inside a day_entries AFTER trigger and inside the nightly scan
  -- (#15). An unrecognized zone must never raise out of this function --
  -- that would abort the profile holder's own entry write, or the
  -- account-deletion re-home, or the whole nightly cron command for every
  -- tenant, over one guardian's bad setting. Degrade to "no quiet hours"
  -- exactly like a null zone.
  begin
    v_local_ts := p_now at time zone p_zone;
  exception
    when others then
      return p_now;
  end;
  v_local_date := v_local_ts::date;
  v_local_time := v_local_ts::time;
  v_wraps := p_quiet_start > p_quiet_end;

  if v_wraps then
    v_inside := v_local_time >= p_quiet_start or v_local_time < p_quiet_end;
  else
    v_inside := v_local_time >= p_quiet_start and v_local_time < p_quiet_end;
  end if;

  if not v_inside then
    return p_now;
  end if;

  if v_wraps and v_local_time >= p_quiet_start then
    -- Evening portion of a wrapped window: it ends tomorrow morning.
    v_end_date := v_local_date + 1;
  else
    -- A same-day window, or the early-morning tail of a wrapped one.
    v_end_date := v_local_date;
  end if;

  return (v_end_date + p_quiet_end) at time zone p_zone;
end;
$$;

comment on function public.resolve_deliver_after(timestamptz, time, time, text) is
  'Resolves when an alert should actually deliver given the recipient''s '
  'quiet hours (KTD5, R12): p_now unchanged outside the window, or the '
  'window''s end (today or tomorrow, for a wrapped window) when inside it. '
  'A null zone, null start/end, a zero-length window, or an unrecognized '
  'IANA zone name (#3/#15 review fix) all mean no quiet hours -- an '
  'invalid p_zone degrades rather than raising, so it can never abort the '
  'caller (the day_entries trigger or the nightly scan).';

revoke all on function public.resolve_deliver_after(timestamptz, time, time, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- enqueue_caregiver_alerts: the day_entries AFTER trigger (KTD4). Eligibility
-- is computed here, in SQL, with a security-definer join across
-- profile_guardians/notification_preferences -- never in the Edge Function,
-- which never reads day_entries content at all (KTD1).
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
begin
  -- A tombstoned write carries no meaningful "someone logged an entry"
  -- event.
  if new.deleted_at is not null then
    return null;
  end if;

  -- sync_push stamps last_modified_by_user_id from the caller's own
  -- auth.uid() (see 20260904010000_multi_guardian_schema.sql); a legacy or
  -- direct-insert row with it null falls back to user_id.
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
  -- stands in for "high severity" (see this file's header).
  v_is_high_severity := new.flow = 'heavy';

  v_kind := case
    when v_is_cycle_start then 'cycle_start'
    when v_is_high_severity then 'high_severity'
    else 'logged'
  end;

  for v_pref in
    select g.user_id as guardian_user_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone
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

comment on function public.enqueue_caregiver_alerts() is
  'AFTER INSERT and AFTER UPDATE trigger function on day_entries (Issue #5, '
  'KTD4; two separate triggers as of the #7 review fix, since a single '
  'combined trigger cannot WHEN-filter both events with one expression): '
  'fans a live write out into one public.notification_outbox row per '
  'eligible, non-writer guardian. The UPDATE trigger''s WHEN clause skips '
  'ownership-only updates and no-op resaves (#7). Runs independently of '
  'public.touch_sync_signal()''s sync_signals trigger -- the two write to '
  'different tables and neither depends on the other''s firing order.';

revoke execute on function public.enqueue_caregiver_alerts() from public, anon, authenticated;

-- #7 (review): a bare `after insert or update` fires on every write,
-- including ones that carry no actual change to what was logged --
-- rehome_stray_day_entries()'s ownership-only UPDATE (user_id,
-- last_modified_by_user_id only) during account deletion, and an ordinary
-- sync_push re-save that resolves to the same content the row already had.
-- Neither is "someone logged an entry" from a guardian's point of view. The
-- WHEN clause below scopes firing to an INSERT or an UPDATE that actually
-- changes one of the columns enqueue_caregiver_alerts()'s own eligibility
-- logic (cycle-start/high-severity detection) and a guardian's mental model
-- of "an entry" depend on; attribution columns (user_id,
-- last_modified_by_user_id) and server bookkeeping (created_at, updated_at,
-- server_version) are deliberately excluded. Split into two triggers rather
-- than one combined `after insert or update` with a single WHEN: Postgres
-- rejects a WHEN clause that references OLD on the INSERT branch of a
-- combined trigger (`INSERT trigger's WHEN condition cannot reference OLD
-- values`, SQLSTATE 42P17), and a WHEN clause cannot reference TG_OP either
-- (that's only visible inside the function body, evaluated after WHEN has
-- already decided whether to fire) -- so there is no single WHEN
-- expression that works for both events at once.
create trigger day_entries_after_insert_enqueue_alerts
  after insert on public.day_entries
  for each row execute function public.enqueue_caregiver_alerts();

create trigger day_entries_after_update_enqueue_alerts
  after update on public.day_entries
  for each row
  when (
    new.local_date is distinct from old.local_date
    or new.flow is distinct from old.flow
    or new.tags is distinct from old.tags
    or new.note is distinct from old.note
    or new.deleted_at is distinct from old.deleted_at
  )
  execute function public.enqueue_caregiver_alerts();
