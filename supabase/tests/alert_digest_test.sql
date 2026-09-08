-- Coverage for Issue #125: digest cadence, the coalescing window, the
-- per-guardian daily push ceiling, self-authored-event suppression (AC3,
-- pinned here as a regression test), and sweep_alert_digests() (the daily
-- digest sweep, including its quiet-hours interaction). Runs on a stack
-- started without pg_cron/pg_net like the rest of the suite -- the sweep
-- is exercised directly, proving it never depends on the cron schedule
-- existing.
--
-- Coalescing-window note: the window is driven by
-- app.settings.alert_coalesce_window (default 30 minutes). Groups below
-- set it explicitly per group -- pgTAP runs each file in one transaction,
-- so every live trigger insert shares one frozen now(), which makes
-- "inside the window" deterministic without waiting out a real 30 minutes.
begin;
select plan(43);

create function pg_temp.count_rows(p_profile text, p_recipient uuid, p_kind text, p_state text)
returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile
     and recipient_user_id = p_recipient
     and (p_kind is null or kind = p_kind)
     and case p_state
           when 'held' then deliver_after = 'infinity'::timestamptz and sent_at is null
           when 'deliverable' then deliver_after <= now()
                                and deliver_after < 'infinity'::timestamptz
                                and sent_at is null and claimed_at is null
           when 'immediate' then deliver_after < 'infinity'::timestamptz
           when 'absorbed' then deliver_after = 'infinity'::timestamptz and sent_at is not null
           else true
         end;
$$;

-- ---------------------------------------------------------------------------
-- Named constants and pure helpers.
-- ---------------------------------------------------------------------------

select set_config('app.settings.alert_coalesce_window', '', true);
select is(
  public.alert_coalesce_window(), interval '30 minutes',
  'alert_coalesce_window returns the 30-minute default when the GUC is unset'
);

select set_config('app.settings.alert_coalesce_window', '7 minutes', true);
select is(
  public.alert_coalesce_window(), interval '7 minutes',
  'alert_coalesce_window honors a valid GUC override'
);

select set_config('app.settings.alert_coalesce_window', 'not-an-interval', true);
select is(
  public.alert_coalesce_window(), interval '30 minutes',
  'alert_coalesce_window degrades to the default on an invalid GUC override (never raises)'
);

select set_config('app.settings.alert_coalesce_window', '30 minutes', true);
select is(
  public.alert_daily_push_ceiling(), 6,
  'alert_daily_push_ceiling is the named constant 6'
);

select is(
  public.local_day_start('2026-09-08T14:30:00Z'::timestamptz, 'UTC'),
  '2026-09-08T00:00:00Z'::timestamptz,
  'local_day_start returns UTC midnight for a UTC zone'
);
select is(
  public.local_day_start('2026-09-08T14:30:00Z'::timestamptz, 'Asia/Tokyo'),
  '2026-09-07T15:00:00Z'::timestamptz,
  'local_day_start returns local midnight for a non-UTC zone (23:30 JST same UTC instant -> that local day''s 00:00 JST = the previous UTC day 15:00Z)'
);
select is(
  public.local_day_start('2026-09-08T14:30:00Z'::timestamptz, 'Not/ARealZone'),
  '2026-09-08T00:00:00Z'::timestamptz,
  'local_day_start degrades an unrecognized zone to UTC instead of raising'
);

-- ---------------------------------------------------------------------------
-- Group 601 (AC2): the coalescing window, at its 30-minute default.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_1');
select tests.create_supabase_user('dad_1');

select tests.authenticate_as('mom_1');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(601), 'Riley 601', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(601), 'co_parent', 'Dad',
  '8080808080808080808080808080808080808080808080808080808080808080', 48
);
select tests.authenticate_as('dad_1');
select public.accept_guardian_invitation(
  '8080808080808080808080808080808080808080808080808080808080808080', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_1'), tests.ulid(601), true);

-- Five routine (non-bleed, non-boundary) events, all inside the same
-- 30-minute window (one frozen transaction now()): one push, not five.
select tests.authenticate_as('mom_1');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6010), tests.ulid(601), '2026-09-01', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6011), tests.ulid(601), '2026-09-02', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6012), tests.ulid(601), '2026-09-03', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6013), tests.ulid(601), '2026-09-04', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6014), tests.ulid(601), '2026-09-05', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(601), tests.get_supabase_uid('dad_1'), 'logged', 'immediate'),
  1::bigint,
  'AC2: five qualifying logged events inside the coalescing window produce one immediate row, not five'
);

-- A cycle_start event inside the same window is a different kind: the
-- window is per (recipient, profile, kind), so it still enqueues.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6015), tests.ulid(601), '2026-09-06', 'UTC', 'medium', now());

select is(
  pg_temp.count_rows(tests.ulid(601), tests.get_supabase_uid('dad_1'), 'cycle_start', 'immediate'),
  1::bigint,
  'the coalescing window is per kind: a cycle_start in the same window still enqueues'
);

-- Disabling the window (the operator GUC) lets the next logged event
-- through again -- proving the guard was the window, not anything else.
select set_config('app.settings.alert_coalesce_window', '0', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6016), tests.ulid(601), '2026-09-07', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(601), tests.get_supabase_uid('dad_1'), 'logged', 'immediate'),
  2::bigint,
  'with the coalescing window set to zero, a further logged event enqueues again'
);

-- ---------------------------------------------------------------------------
-- Group 602 (AC1/AC6): per-kind cadence and per-guardian independence.
-- Window stays 0 for the rest of this file so immediate-row counts stay
-- exact.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_2');
select tests.create_supabase_user('dad_2');
select tests.create_supabase_user('step_2');

select tests.authenticate_as('mom_2');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(602), 'Riley 602', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(602), 'co_parent', 'Dad',
  '8181818181818181818181818181818181818181818181818181818181818181', 48
);
select tests.authenticate_as('dad_2');
select public.accept_guardian_invitation(
  '8181818181818181818181818181818181818181818181818181818181818181', 'Dad'
);
select tests.authenticate_as('mom_2');
select public.create_guardian_invitation(
  tests.ulid(602), 'caregiver', 'Step',
  '8282828282828282828282828282828282828282828282828282828282828282', 48
);
select tests.authenticate_as('step_2');
select public.accept_guardian_invitation(
  '8282828282828282828282828282828282828282828282828282828282828282', 'Step'
);

-- Dad: routine logging on a daily digest; cycle-start stays immediate.
-- Step: today's behaviour (immediate). Cadence is per guardian.
select tests.authenticate_as('dad_2');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence)
values (tests.get_supabase_uid('dad_2'), tests.ulid(602), true, 'daily_digest');
select tests.authenticate_as('step_2');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('step_2'), tests.ulid(602), true);

select tests.authenticate_as('mom_2');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6020), tests.ulid(602), '2026-09-01', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(602), tests.get_supabase_uid('dad_2'), 'logged', 'held'),
  1::bigint,
  'AC1: a routine event for a daily-digest guardian is held (deliver_after = infinity), not pushed'
);
select is(
  pg_temp.count_rows(tests.ulid(602), tests.get_supabase_uid('step_2'), 'logged', 'immediate'),
  1::bigint,
  'cadence is per guardian: the co-guardian choosing immediate still gets an immediate row from the same event'
);

-- Two more routine events accumulate into the held set (the sweep below
-- collapses them into one push).
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6021), tests.ulid(602), '2026-09-02', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6022), tests.ulid(602), '2026-09-03', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(602), tests.get_supabase_uid('dad_2'), 'logged', 'held'),
  3::bigint,
  'digest-cadence events accumulate as held rows until the sweep collapses them'
);

-- AC6: a cycle-start event (bleed day with no prior bleed day) goes
-- immediate for dad while his routine log alerts are on digest.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6023), tests.ulid(602), '2026-09-10', 'UTC', 'medium', now());

select is(
  pg_temp.count_rows(tests.ulid(602), tests.get_supabase_uid('dad_2'), 'cycle_start', 'immediate'),
  1::bigint,
  'AC6: cycle_start stays immediate for the same guardian and profile whose log alerts are on digest'
);

-- The per-kind off switch.
select tests.authenticate_as('dad_2');
update public.notification_preferences
   set log_cadence = 'off'
 where user_id = tests.get_supabase_uid('dad_2') and profile_id = tests.ulid(602);

select tests.authenticate_as('mom_2');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6024), tests.ulid(602), '2026-09-11', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(602), tests.get_supabase_uid('dad_2'), null, 'any'),
  4::bigint,
  'off cadence suppresses routine events for that kind (dad still has only his 3 held + 1 immediate cycle_start)'
);

-- ---------------------------------------------------------------------------
-- Group 603 (AC3): self-authored-event suppression, pinned. The trigger
-- computes the writer as coalesce(last_modified_by_user_id, user_id) --
-- exactly what sync_push stamps from the acting device's auth.uid(), so a
-- guardian's own edit arriving from their second device never pages them.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_3');
select tests.create_supabase_user('dad_3');
select tests.create_supabase_user('step_3');

select tests.authenticate_as('mom_3');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(603), 'Riley 603', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(603), 'co_parent', 'Dad',
  '8383838383838383838383838383838383838383838383838383838383838383', 48
);
select tests.authenticate_as('dad_3');
select public.accept_guardian_invitation(
  '8383838383838383838383838383838383838383838383838383838383838383', 'Dad'
);
select tests.authenticate_as('mom_3');
select public.create_guardian_invitation(
  tests.ulid(603), 'caregiver', 'Step',
  '8484848484848484848484848484848484848484848484848484848484848484', 48
);
select tests.authenticate_as('step_3');
select public.accept_guardian_invitation(
  '8484848484848484848484848484848484848484848484848484848484848484', 'Step'
);
-- Mom first logs an entry while nobody has preferences yet, so the only
-- writes observed below are the two dad-authored ones.
select tests.authenticate_as('mom_3');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, note, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(6031), tests.ulid(603), '2026-09-02', 'UTC', 'none', 'original', now(),
   tests.get_supabase_uid('mom_3'), tests.get_supabase_uid('mom_3'));

select tests.authenticate_as('dad_3');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_3'), tests.ulid(603), true);
select tests.authenticate_as('step_3');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('step_3'), tests.ulid(603), true);

-- Dad logs his own entry from his device: no row for dad, one for step.
select tests.authenticate_as('dad_3');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(6030), tests.ulid(603), '2026-09-01', 'UTC', 'none', now(),
   tests.get_supabase_uid('dad_3'), tests.get_supabase_uid('dad_3'));

select is(
  pg_temp.count_rows(tests.ulid(603), tests.get_supabase_uid('dad_3'), null, 'any'),
  0::bigint,
  'AC3: a guardian''s own insert produces no row for them (writer exclusion)'
);

-- Dad edits mom's existing entry from his second device: sync_push stamps
-- last_modified_by_user_id = dad, so the write is still dad's own -- no
-- row for dad, but step (not the writer) is notified.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
update public.day_entries
   set note = 'dad''s second-device edit',
       last_modified_by_user_id = tests.get_supabase_uid('dad_3'),
       updated_at = now()
 where id = tests.ulid(6031);

select is(
  pg_temp.count_rows(tests.ulid(603), tests.get_supabase_uid('dad_3'), null, 'any'),
  0::bigint,
  'AC3: a guardian''s own change synced from their second device (last_modified_by = them) produces no push to them'
);
select is(
  pg_temp.count_rows(tests.ulid(603), tests.get_supabase_uid('step_3'), null, 'any'),
  2::bigint,
  'AC3: a non-writer co-guardian is still notified of both events'
);

-- ---------------------------------------------------------------------------
-- Group 604: sweep_alert_digests -- the daily digest (AC1), its quiet-hours
-- interaction (AC5), idempotence, and the no-preference-row drop. Held
-- rows are inserted directly as service_role with a backdated created_at
-- (the trigger can only stamp now(), and a digest is due only once its
-- time has passed -- backdating two hours and choosing a digest time one
-- hour ago lands the candidate strictly between the oldest row and now in
-- every time-of-day case, including across UTC midnight).
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_4');
select tests.create_supabase_user('dad_4');

select tests.authenticate_as('mom_4');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(604), 'Riley 604', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(604), 'co_parent', 'Dad',
  '8585858585858585858585858585858585858585858585858585858585858585', 48
);
select tests.authenticate_as('dad_4');
select public.accept_guardian_invitation(
  '8585858585858585858585858585858585858585858585858585858585858585', 'Dad'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence, digest_local_time, time_zone)
values (
  tests.get_supabase_uid('dad_4'), tests.ulid(604), true, 'daily_digest',
  ((now() at time zone 'UTC')::time - interval '1 hour'), 'UTC'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.notification_outbox
  (id, profile_id, recipient_user_id, kind, deliver_after, created_at)
values
  ('00000000-0000-0000-0000-000000000941'::uuid, tests.ulid(604),
   tests.get_supabase_uid('dad_4'), 'logged', 'infinity', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-000000000942'::uuid, tests.ulid(604),
   tests.get_supabase_uid('dad_4'), 'logged', 'infinity', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-000000000943'::uuid, tests.ulid(604),
   tests.get_supabase_uid('dad_4'), 'logged', 'infinity', now() - interval '2 hours');

select is(
  public.sweep_alert_digests(), 1,
  'AC1: a due digest group is released exactly once'
);
select is(
  pg_temp.count_rows(tests.ulid(604), tests.get_supabase_uid('dad_4'), null, 'deliverable'),
  1::bigint,
  'AC1: three held events collapse into exactly one deliverable digest row'
);
select is(
  pg_temp.count_rows(tests.ulid(604), tests.get_supabase_uid('dad_4'), null, 'absorbed'),
  2::bigint,
  'AC1: the other two held rows are absorbed (sent as part of the one digest push, no push of their own)'
);

-- Idempotence, including against sweep_notification_outbox: an absorbed
-- row carries sent_at, so the stuck-claim sweep can never resurrect it.
select public.sweep_notification_outbox();
select is(
  public.sweep_alert_digests(), 0,
  're-running the digest sweep with nothing due releases nothing'
);
select is(
  pg_temp.count_rows(tests.ulid(604), tests.get_supabase_uid('dad_4'), null, 'deliverable'),
  1::bigint,
  'the released digest row survives a stuck-claim sweep and a digest-sweep re-run unchanged'
);

-- An event after the digest was delivered starts the next day's held set:
-- its oldest row is newer than every digest moment that already passed
-- today, so nothing more is due (exactly one push per day).
insert into public.notification_outbox
  (id, profile_id, recipient_user_id, kind, deliver_after, created_at)
values (
  '00000000-0000-0000-0000-000000000944'::uuid, tests.ulid(604),
  tests.get_supabase_uid('dad_4'), 'logged', 'infinity', now()
);
select is(
  public.sweep_alert_digests(), 0,
  'a post-digest event is held for tomorrow''s digest, not delivered in today''s (exactly one digest push per day)'
);
select is(
  pg_temp.count_rows(tests.ulid(604), tests.get_supabase_uid('dad_4'), null, 'held'),
  1::bigint,
  'the post-digest event stays held'
);

-- AC5, case (a): the digest time falls inside quiet hours whose end is
-- still in the future -- the digest shifts to the boundary and is NOT
-- delivered now (and not dropped either: the rows stay held).
select tests.create_supabase_user('mom_4q');
select tests.authenticate_as('mom_4q');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(614), 'Riley 614', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence, digest_local_time, time_zone,
   quiet_hours_start, quiet_hours_end)
values (
  tests.get_supabase_uid('mom_4q'), tests.ulid(614), true, 'daily_digest',
  ((now() at time zone 'UTC')::time - interval '1 hour'), 'UTC',
  ((now() at time zone 'UTC')::time - interval '3 hours'),
  ((now() at time zone 'UTC')::time + interval '1 hour')
);
insert into public.notification_outbox
  (id, profile_id, recipient_user_id, kind, deliver_after, created_at)
values
  ('00000000-0000-0000-0000-000000000951'::uuid, tests.ulid(614),
   tests.get_supabase_uid('mom_4q'), 'logged', 'infinity', now() - interval '2 hours'),
  ('00000000-0000-0000-0000-000000000952'::uuid, tests.ulid(614),
   tests.get_supabase_uid('mom_4q'), 'logged', 'infinity', now() - interval '2 hours');

select is(
  public.sweep_alert_digests(), 0,
  'AC5: a digest scheduled inside quiet hours is not delivered while the window is still open'
);
select is(
  pg_temp.count_rows(tests.ulid(614), tests.get_supabase_uid('mom_4q'), null, 'held'),
  2::bigint,
  'AC5: the deferred digest is held, not dropped'
);

-- AC5, case (b): the same group once the quiet-hours boundary has passed
-- (the window end moved to 30 minutes ago) -- the digest delivers at the
-- boundary.
update public.notification_preferences
   set quiet_hours_end = ((now() at time zone 'UTC')::time - interval '30 minutes')
 where user_id = tests.get_supabase_uid('mom_4q') and profile_id = tests.ulid(614);

select is(
  public.sweep_alert_digests(), 1,
  'AC5: once the quiet-hours boundary has passed, the deferred digest is delivered'
);
select is(
  pg_temp.count_rows(tests.ulid(614), tests.get_supabase_uid('mom_4q'), null, 'deliverable'),
  1::bigint,
  'AC5: the quiet-hours-deferred digest collapsed to one deliverable row'
);

-- A held group whose preference row is gone has nobody to deliver to and
-- no cadence asking for it: the sweep drops it.
select tests.create_supabase_user('stray_4');
select tests.create_supabase_user('mom_4s');
select tests.authenticate_as('mom_4s');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(624), 'Riley 624', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
-- The profile exists purely as an FK anchor for the stray recipient's
-- held rows; the preference row is deliberately never inserted.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.notification_outbox
  (id, profile_id, recipient_user_id, kind, deliver_after, created_at)
values (
  '00000000-0000-0000-0000-000000000961'::uuid, tests.ulid(624),
  tests.get_supabase_uid('stray_4'), 'logged', 'infinity', now() - interval '2 hours'
);
select public.sweep_alert_digests();
select is(
  pg_temp.count_rows(tests.ulid(624), tests.get_supabase_uid('stray_4'), null, 'any'),
  0::bigint,
  'a held group with no preference row is dropped by the sweep, not delivered'
);

-- ---------------------------------------------------------------------------
-- Group 605 (AC4): the per-guardian daily push ceiling, with overflow
-- rolling into the next digest.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_5');
select tests.create_supabase_user('dad_5');

select tests.authenticate_as('mom_5');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(605), 'Riley 605', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(605), 'co_parent', 'Dad',
  '8686868686868686868686868686868686868686868686868686868686868686', 48
);
select tests.authenticate_as('dad_5');
select public.accept_guardian_invitation(
  '8686868686868686868686868686868686868686868686868686868686868686', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_5'), tests.ulid(605), true);

select tests.authenticate_as('mom_5');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6050), tests.ulid(605), '2026-09-01', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6051), tests.ulid(605), '2026-09-02', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6052), tests.ulid(605), '2026-09-03', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6053), tests.ulid(605), '2026-09-04', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6054), tests.ulid(605), '2026-09-05', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6055), tests.ulid(605), '2026-09-06', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6056), tests.ulid(605), '2026-09-07', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6057), tests.ulid(605), '2026-09-08', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(605), tests.get_supabase_uid('dad_5'), 'logged', 'immediate'),
  6::bigint,
  'AC4: the daily ceiling stops immediate pushes at the named constant (6)'
);
select is(
  pg_temp.count_rows(tests.ulid(605), tests.get_supabase_uid('dad_5'), 'logged', 'held'),
  2::bigint,
  'AC4: events past the ceiling are held for the digest, not dropped'
);

-- The overflow appears in the next digest: choose a digest time that has
-- already passed today, backdate the held rows past it, and sweep.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
update public.notification_preferences
   set digest_local_time = ((now() at time zone 'UTC')::time - interval '1 hour'),
       time_zone = 'UTC'
 where user_id = tests.get_supabase_uid('dad_5') and profile_id = tests.ulid(605);
update public.notification_outbox
   set created_at = now() - interval '2 hours'
 where profile_id = tests.ulid(605)
   and recipient_user_id = tests.get_supabase_uid('dad_5')
   and deliver_after = 'infinity';

select is(
  public.sweep_alert_digests(), 1,
  'AC4: the ceiling overflow is released by the next due digest'
);
select is(
  pg_temp.count_rows(tests.ulid(605), tests.get_supabase_uid('dad_5'), null, 'held'),
  0::bigint,
  'AC4: the ceiling overflow is fully released (nothing left held)'
);
select is(
  pg_temp.count_rows(tests.ulid(605), tests.get_supabase_uid('dad_5'), null, 'absorbed'),
  1::bigint,
  'AC4: the two overflow rows collapsed into one digest push (one deliverable, one absorbed) -- not dropped'
);

-- ---------------------------------------------------------------------------
-- Group 606 (AC7): immediate-for-everything is preserved; grants and the
-- cron wrappers.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_6');
select tests.create_supabase_user('dad_6');

select tests.authenticate_as('mom_6');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(606), 'Riley 606', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(606), 'co_parent', 'Dad',
  '8787878787878787878787878787878787878787878787878787878787878787', 48
);
select tests.authenticate_as('dad_6');
select public.accept_guardian_invitation(
  '8787878787878787878787878787878787878787878787878787878787878787', 'Dad'
);
-- Default cadences (immediate) exactly as any pre-#125 row would have.
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_6'), tests.ulid(606), true);

select tests.authenticate_as('mom_6');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6060), tests.ulid(606), '2026-09-01', 'UTC', 'none', now());
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6061), tests.ulid(606), '2026-09-02', 'UTC', 'none', now());

select is(
  pg_temp.count_rows(tests.ulid(606), tests.get_supabase_uid('dad_6'), 'logged', 'immediate'),
  2::bigint,
  'AC7: a guardian at default settings gets one immediate row per event (with the window off), as before #125'
);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select ok(
  (select bool_and(deliver_after <= now() and deliver_after < 'infinity'::timestamptz)
     from public.notification_outbox
    where profile_id = tests.ulid(606) and recipient_user_id = tests.get_supabase_uid('dad_6')),
  'AC7: default-cadence rows are immediately deliverable, never held'
);

select is(
  has_function_privilege('authenticated', 'public.sweep_alert_digests()', 'execute'),
  false,
  'authenticated cannot execute sweep_alert_digests'
);
select is(
  has_function_privilege('anon', 'public.sweep_alert_digests()', 'execute'),
  false,
  'anon cannot execute sweep_alert_digests'
);
select is(
  has_function_privilege('authenticated', 'public.local_day_start(timestamptz, text)', 'execute'),
  false,
  'authenticated cannot execute the ceiling/window helper functions'
);

-- The wrappers now carry the digest sweep step; a smoke call proves the
-- new plumbing introduces no way to raise (per-group isolation inside the
-- sweep mirrors the scan's #7 fix).
select lives_ok(
  $$select public.run_nightly_caregiver_alerts_job()$$,
  'run_nightly_caregiver_alerts_job runs scan, sweeps, digest sweep, and dispatch without raising'
);
select lives_ok(
  $$select public.run_caregiver_alert_drain()$$,
  'run_caregiver_alert_drain runs both sweeps and dispatch without raising'
);

-- The outbox itself gained no column at all for #125 (held rows are
-- deliver_after = 'infinity'), so the content-free invariant is unchanged.
select is(
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_outbox'
      and column_name in ('note', 'tags', 'flow', 'local_date')),
  0::bigint,
  'notification_outbox still has no column capable of holding note, tags, flow, or local_date'
);

rollback;
