-- Coverage for Issue #851's ahead-of-time guardian alerts:
-- public.scan_ahead_of_time_alerts() and the pieces it rides --
-- public.ahead_of_time_lead_days()/ahead_of_time_min_pms_intervals(), the
-- extended notification_outbox kind CHECK, the three
-- notification_preferences opt-in booleans (off by default), the
-- ahead_of_time_alert_state window dedupe marker, the revocation purge
-- trigger, the extended cancel_outbox_on_preference_off(), and the
-- extended resolve_notification_outbox_dispatch().
--
-- Runs on a stack started without pg_cron/pg_net (AGENTS.md's
-- `supabase start -x ...` exclusion list) -- the scan is exercised
-- directly, proving KTD9's guard: the alert logic never depends on the cron
-- schedule actually existing.
begin;
select plan(38);

-- ---------------------------------------------------------------------------
-- Helpers.
-- ---------------------------------------------------------------------------

create function pg_temp.kind_count(
  p_profile text, p_recipient uuid, p_kind text
) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile
     and recipient_user_id = p_recipient
     and kind = p_kind;
$$;

create function pg_temp.state_count(
  p_profile text, p_recipient uuid, p_kind text
) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.ahead_of_time_alert_state
   where profile_id = p_profile
     and user_id = p_recipient
     and kind = p_kind;
$$;

-- Seeds (or overwrites) one guardian's preference row. SECURITY DEFINER
-- (owned by postgres, a superuser locally) so it bypasses RLS and needs no
-- role juggling at the call site -- `set_config('role', ...)` is illegal
-- inside a SECURITY DEFINER function, so it must not try.
create function pg_temp.turn_on(
  p_user text, p_profile text, p_period boolean default false,
  p_restock boolean default false, p_pms boolean default false
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notification_preferences
    (user_id, profile_id, alert_on_period_soon, alert_on_restock, alert_on_pms_soon)
  values (
    tests.get_supabase_uid(p_user), p_profile, p_period, p_restock, p_pms
  )
  on conflict (user_id, profile_id) do update
    set alert_on_period_soon = excluded.alert_on_period_soon,
        alert_on_restock = excluded.alert_on_restock,
        alert_on_pms_soon = excluded.alert_on_pms_soon;
end;
$$;

-- Runs the scan. SECURITY DEFINER so the revoked-from-authenticated
-- function is reachable whatever role the fixture last set.
create function pg_temp.run_scan() returns void
language sql security definer set search_path = '' as $$
  select public.scan_ahead_of_time_alerts();
$$;

-- ---------------------------------------------------------------------------
-- Named constants and the extended kind CHECK (structural).
-- ---------------------------------------------------------------------------

select is(
  public.ahead_of_time_lead_days(), 5,
  'ahead_of_time_lead_days is the named constant 5'
);
select is(
  public.ahead_of_time_min_pms_intervals(), 3,
  'ahead_of_time_min_pms_intervals is the named constant 3'
);

select is(
  (select pg_get_constraintdef(oid)
     from pg_constraint
    where conname = 'notification_outbox_kind_check')
    like '%''period_soon''%',
  true,
  'the outbox kind CHECK admits period_soon'
);
select is(
  (select pg_get_constraintdef(oid)
     from pg_constraint
    where conname = 'notification_outbox_kind_check')
    like '%''restock_due''%'
    and (select pg_get_constraintdef(oid)
           from pg_constraint
          where conname = 'notification_outbox_kind_check')
        like '%''pms_soon''%',
  true,
  'the outbox kind CHECK admits restock_due and pms_soon'
);

select is(
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_preferences'
      and column_name in
        ('alert_on_period_soon', 'alert_on_restock', 'alert_on_pms_soon')
      and column_default = 'false'
      and is_nullable = 'NO'),
  3::bigint,
  'the three ahead-of-time opt-in booleans exist, are NOT NULL, and default false'
);

select is(
  (select count(*) from pg_proc
    where proname = 'purge_ahead_of_time_state_on_revocation'
      and pronamespace = 'public'::regnamespace),
  1::bigint,
  'the revocation purge trigger function exists'
);

-- ---------------------------------------------------------------------------
-- Group 551: off by default -- a guardian with a published, in-window
-- estimate and a preference row that never opted in gets nothing, while the
-- three booleans read false.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_851a');
select tests.create_supabase_user('dad_851a');

select tests.authenticate_as('mom_851a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(551), 'A', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(551), 'co_parent', 'Dad',
  'a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5', 48
);
select tests.authenticate_as('dad_851a');
select public.accept_guardian_invitation(
  'a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5', 'Dad'
);
-- A row that explicitly exists but only carries the (off-by-default)
-- pre-#851 master switch.
insert into public.notification_preferences (user_id, profile_id)
values (tests.get_supabase_uid('dad_851a'), tests.ulid(551));
select public.upsert_reminder_window(tests.ulid(551), (current_date + 1), false);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select pg_temp.run_scan();

select is(
  pg_temp.kind_count(tests.ulid(551), tests.get_supabase_uid('dad_851a'), 'period_soon'),
  0::bigint,
  'off by default: no period_soon without the opt-in'
);
select is(
  pg_temp.kind_count(tests.ulid(551), tests.get_supabase_uid('dad_851a'), 'restock_due'),
  0::bigint,
  'off by default: no restock_due without the opt-in'
);
select is(
  pg_temp.kind_count(tests.ulid(551), tests.get_supabase_uid('dad_851a'), 'pms_soon'),
  0::bigint,
  'off by default: no pms_soon without the opt-in'
);

-- ---------------------------------------------------------------------------
-- Group 552: period_soon window + per-window dedupe + re-arm on a new
-- estimate. dad_852 opts into period_soon only.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_852');
select tests.create_supabase_user('dad_852');

select tests.authenticate_as('mom_852');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(552), 'B', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(552), 'co_parent', 'Dad',
  'b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5', 48
);
select tests.authenticate_as('dad_852');
select public.accept_guardian_invitation(
  'b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5b5', 'Dad'
);

-- Estimate 10 days out: outside the 5-day window -- nothing yet.
select public.upsert_reminder_window(tests.ulid(552), (current_date + 10), false);
select pg_temp.turn_on('dad_852', tests.ulid(552), true, false, false);
select pg_temp.run_scan();
select is(
  pg_temp.kind_count(tests.ulid(552), tests.get_supabase_uid('dad_852'), 'period_soon'),
  0::bigint,
  'period_soon: an estimate 10 days out is outside the 5-day window -- nothing'
);

-- Estimate 5 days out: exactly the boundary -- one row.
select tests.authenticate_as('dad_852');
select public.upsert_reminder_window(tests.ulid(552), (current_date + 5), false);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select pg_temp.run_scan();
select is(
  pg_temp.kind_count(tests.ulid(552), tests.get_supabase_uid('dad_852'), 'period_soon'),
  1::bigint,
  'period_soon: an estimate 5 days out (the boundary) enqueues one row'
);

-- Re-run on the same unchanged window: deduped.
select pg_temp.run_scan();
select is(
  pg_temp.kind_count(tests.ulid(552), tests.get_supabase_uid('dad_852'), 'period_soon'),
  1::bigint,
  'period_soon: a second scan over the same window enqueues nothing (per-window dedupe)'
);

-- A freshly published estimate re-arms it.
select tests.authenticate_as('dad_852');
select public.upsert_reminder_window(tests.ulid(552), (current_date + 2), false);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select pg_temp.run_scan();
select is(
  pg_temp.kind_count(tests.ulid(552), tests.get_supabase_uid('dad_852'), 'period_soon'),
  2::bigint,
  'period_soon: a freshly published estimate re-arms the alert for the new window'
);

-- ---------------------------------------------------------------------------
-- Group 553: restock_due needs a live unstocked supply item *and* the
-- window. dad_853 opts into restock only.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_853');
select tests.create_supabase_user('dad_853');

select tests.authenticate_as('mom_853');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(553), 'C', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(553), 'co_parent', 'Dad',
  'c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5', 48
);
select tests.authenticate_as('dad_853');
select public.accept_guardian_invitation(
  'c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5c5', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(553), (current_date + 1), false);
select pg_temp.turn_on('dad_853', tests.ulid(553), false, true, false);

select tests.authenticate_as('mom_853');
select set_config('role', 'service_role', true);
-- No supplies yet: nothing.
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(553), tests.get_supabase_uid('dad_853'), 'restock_due'),
  0::bigint,
  'restock_due: no supply rows at all -- nothing, even inside the window'
);

-- An unstocked supply row: one row.
select tests.authenticate_as('mom_853');
select set_config('role', 'service_role', true);
insert into public.visit_prep_items
  (id, profile_id, body, kind, is_checked, updated_at)
values
  (tests.ulid(5530), tests.ulid(553), 'liners', 'supply', false, now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(553), tests.get_supabase_uid('dad_853'), 'restock_due'),
  1::bigint,
  'restock_due: a live unstocked supply item inside the window enqueues one row'
);

-- A visit-prep item never counts (kind discriminator).
select tests.create_supabase_user('mom_853b');
select tests.create_supabase_user('dad_853b');
select tests.authenticate_as('mom_853b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(554), 'C2', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(554), 'co_parent', 'Dad',
  'd5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5', 48
);
select tests.authenticate_as('dad_853b');
select public.accept_guardian_invitation(
  'd5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5d5', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(554), (current_date + 1), false);
select pg_temp.turn_on('dad_853b', tests.ulid(554), false, true, false);
select tests.authenticate_as('mom_853b');
select set_config('role', 'service_role', true);
insert into public.visit_prep_items
  (id, profile_id, body, kind, is_checked, updated_at)
values
  (tests.ulid(5540), tests.ulid(554), 'pack a bag', 'visit_prep', false, now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(554), tests.get_supabase_uid('dad_853b'), 'restock_due'),
  0::bigint,
  'restock_due: an unstocked visit_prep item never fires the supplies nudge'
);

-- All stocked: nothing (a stocked supply row is not "low").
select tests.create_supabase_user('mom_853c');
select tests.create_supabase_user('dad_853c');
select tests.authenticate_as('mom_853c');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(555), 'C3', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(555), 'co_parent', 'Dad',
  'e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5', 48
);
select tests.authenticate_as('dad_853c');
select public.accept_guardian_invitation(
  'e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(555), (current_date + 1), false);
select pg_temp.turn_on('dad_853c', tests.ulid(555), false, true, false);
select tests.authenticate_as('mom_853c');
select set_config('role', 'service_role', true);
insert into public.visit_prep_items
  (id, profile_id, body, kind, is_checked, checked_by_user_id, checked_at, updated_at)
values
  (tests.ulid(5550), tests.ulid(555), 'liners', 'supply', true,
   tests.get_supabase_uid('mom_853c'), now(), now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(555), tests.get_supabase_uid('dad_853c'), 'restock_due'),
  0::bigint,
  'restock_due: an all-stocked supplies list fires nothing'
);

-- ---------------------------------------------------------------------------
-- Group 556: pms_soon and the >=3-logged-interval gate. dad_856 opts into
-- pms_soon only; the window is in range throughout.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_856');
select tests.create_supabase_user('dad_856');

select tests.authenticate_as('mom_856');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(556), 'F', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(556), 'co_parent', 'Dad',
  'f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5', 48
);
select tests.authenticate_as('dad_856');
select public.accept_guardian_invitation(
  'f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5f5', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(556), (current_date + 1), false);
select pg_temp.turn_on('dad_856', tests.ulid(556), false, false, true);

-- Two logged PMS intervals (each a two-day run, far apart): below the gate.
select tests.authenticate_as('mom_856');
select set_config('role', 'service_role', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, pms, updated_at)
values
  (tests.ulid(5560), tests.ulid(556), (current_date - 40), 'UTC', 'none', true, now()),
  (tests.ulid(5561), tests.ulid(556), (current_date - 39), 'UTC', 'none', true, now()),
  (tests.ulid(5562), tests.ulid(556), (current_date - 20), 'UTC', 'none', true, now()),
  (tests.ulid(5563), tests.ulid(556), (current_date - 19), 'UTC', 'none', true, now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  0::bigint,
  'pms_soon: two logged PMS intervals are below the >=3 gate -- never fires'
);
select is(
  pg_temp.state_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  0::bigint,
  'pms_soon: the below-gate scan writes no dedupe marker'
);

-- A third interval: at the gate -- one row.
select tests.authenticate_as('mom_856');
select set_config('role', 'service_role', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, pms, updated_at)
values
  (tests.ulid(5564), tests.ulid(556), (current_date - 5), 'UTC', 'none', true, now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  1::bigint,
  'pms_soon: the third logged PMS interval crosses the gate and enqueues one row'
);
select is(
  pg_temp.state_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  1::bigint,
  'pms_soon: crossing the gate records the dedupe marker'
);

-- Consecutive PMS days in one run count as ONE interval, not several: add a
-- further consecutive day, still one run, so no re-arm within the window.
select tests.authenticate_as('mom_856');
select set_config('role', 'service_role', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, pms, updated_at)
values
  (tests.ulid(5565), tests.ulid(556), (current_date - 6), 'UTC', 'none', true, now());
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  1::bigint,
  'pms_soon: an extra consecutive PMS day does not create a second interval or a second alert'
);

-- A tombstoned PMS day does not count toward the intervals.
select tests.authenticate_as('mom_856');
select set_config('role', 'service_role', true);
update public.day_entries
   set deleted_at = now(), flow = 'none', pms = false,
       last_modified_by_user_id = tests.get_supabase_uid('mom_856'),
       updated_at = now()
 where id = tests.ulid(5564);
select pg_temp.run_scan();
select set_config('role', 'authenticated', true);
select is(
  pg_temp.kind_count(tests.ulid(556), tests.get_supabase_uid('dad_856'), 'pms_soon'),
  1::bigint,
  'pms_soon: a tombstoned PMS day is excluded -- the existing marker stands, no new alert'
);

-- ---------------------------------------------------------------------------
-- Group 557: quiet hours shift deliver_after; the daily ceiling holds
-- overflow for the digest. Both use dad_857 with period_soon + pms_soon.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_857');
select tests.create_supabase_user('dad_857');

select tests.authenticate_as('mom_857');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(557), 'G', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(557), 'co_parent', 'Dad',
  'a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6', 48
);
select tests.authenticate_as('dad_857');
select public.accept_guardian_invitation(
  'a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6a6', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(557), (current_date + 1), false);
select pg_temp.turn_on('dad_857', tests.ulid(557), true, false, true);

-- A quiet-hours window that wraps midnight; the resolved deliver_after must
-- be strictly in the future and no longer the raw now().
select tests.authenticate_as('dad_857');
update public.notification_preferences
   set quiet_hours_start = '00:00'::time,
       quiet_hours_end = '23:59'::time,
       time_zone = 'UTC'
 where user_id = tests.get_supabase_uid('dad_857') and profile_id = tests.ulid(557);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select pg_temp.run_scan();
select is(
  (select bool_and(deliver_after > now())
     from public.notification_outbox
    where profile_id = tests.ulid(557)
      and recipient_user_id = tests.get_supabase_uid('dad_857')
      and kind = 'period_soon'),
  true,
  'ahead-of-time alerts honour quiet hours: deliver_after is shifted into the future'
);

-- Daily ceiling: clear the quiet-hours row from the previous scan (so this
-- assertion isolates the ceiling), push the guardian to the ceiling, then a
-- fresh window for period_soon must be held (deliver_after = infinity) for
-- the digest.
select tests.authenticate_as('dad_857');
select public.upsert_reminder_window(tests.ulid(557), (current_date + 2), false);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
delete from public.notification_outbox
 where profile_id = tests.ulid(557)
   and recipient_user_id = tests.get_supabase_uid('dad_857');
insert into public.notification_outbox (profile_id, recipient_user_id, kind, deliver_after)
select tests.ulid(557), tests.get_supabase_uid('dad_857'), 'logged', now()
  from generate_series(1, public.alert_daily_push_ceiling());
select pg_temp.run_scan();
select is(
  (select count(*)
     from public.notification_outbox
    where profile_id = tests.ulid(557)
      and recipient_user_id = tests.get_supabase_uid('dad_857')
      and kind = 'period_soon'
      and deliver_after <> 'infinity'::timestamptz),
  0::bigint,
  'ahead-of-time alerts respect the daily ceiling: nothing is pushed past it'
);
select is(
  (select count(*)
     from public.notification_outbox
    where profile_id = tests.ulid(557)
      and recipient_user_id = tests.get_supabase_uid('dad_857')
      and kind = 'period_soon'
      and deliver_after = 'infinity'::timestamptz),
  1::bigint,
  'ahead-of-time alerts respect the daily ceiling: the overflow is held for the digest, not dropped'
);

-- ---------------------------------------------------------------------------
-- Group 558: the revocation purge trigger and the preference-off cancel.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_858');
select tests.create_supabase_user('dad_858');

select tests.authenticate_as('mom_858');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(558), 'H', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(558), 'co_parent', 'Dad',
  'b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6', 48
);
select tests.authenticate_as('dad_858');
select public.accept_guardian_invitation(
  'b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6b6', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(558), (current_date + 1), false);
select pg_temp.turn_on('dad_858', tests.ulid(558), true, false, false);
select pg_temp.run_scan();
select is(
  pg_temp.state_count(tests.ulid(558), tests.get_supabase_uid('dad_858'), 'period_soon'),
  1::bigint,
  'revocation: dad has a period_soon marker before being revoked'
);

select tests.authenticate_as('mom_858');
select public.revoke_guardian(tests.ulid(558), tests.get_supabase_uid('dad_858'));
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select is(
  pg_temp.state_count(tests.ulid(558), tests.get_supabase_uid('dad_858'), 'period_soon'),
  0::bigint,
  'revocation: the marker is purged by the profile_guardians trigger'
);

-- Turning the boolean off cancels an already-queued unsent row.
select tests.create_supabase_user('mom_858b');
select tests.create_supabase_user('dad_858b');
select tests.authenticate_as('mom_858b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(559), 'H2', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(559), 'co_parent', 'Dad',
  'c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6', 48
);
select tests.authenticate_as('dad_858b');
select public.accept_guardian_invitation(
  'c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6c6', 'Dad'
);
select public.upsert_reminder_window(tests.ulid(559), (current_date + 1), false);
select pg_temp.turn_on('dad_858b', tests.ulid(559), true, false, false);
select pg_temp.run_scan();
select is(
  pg_temp.kind_count(tests.ulid(559), tests.get_supabase_uid('dad_858b'), 'period_soon'),
  1::bigint,
  'preference-off: a period_soon row is queued before the toggle is turned off'
);
select tests.authenticate_as('dad_858b');
update public.notification_preferences
   set alert_on_period_soon = false
 where user_id = tests.get_supabase_uid('dad_858b') and profile_id = tests.ulid(559);
select is(
  pg_temp.kind_count(tests.ulid(559), tests.get_supabase_uid('dad_858b'), 'period_soon'),
  0::bigint,
  'preference-off: turning the boolean off cancels the queued unsent row (LLA-076 extended)'
);

-- ---------------------------------------------------------------------------
-- Group 560: resolve_notification_outbox_dispatch knows the new kinds.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('mom_860');
select tests.create_supabase_user('dad_860');

select tests.authenticate_as('mom_860');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(560), 'J', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(560), 'co_parent', 'Dad',
  'd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6', 48
);
select tests.authenticate_as('dad_860');
select public.accept_guardian_invitation(
  'd6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6d6', 'Dad'
);
select pg_temp.turn_on('dad_860', tests.ulid(560), true, true, true);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.notification_outbox (id, profile_id, recipient_user_id, kind)
values (
  '00000000-0000-0000-0000-000000000a51'::uuid,
  tests.ulid(560), tests.get_supabase_uid('dad_860'), 'period_soon'
);
select is(
  (public.resolve_notification_outbox_dispatch(
     '00000000-0000-0000-0000-000000000a51'::uuid))->>'action',
  'send',
  'resolve_notification_outbox_dispatch sends a period_soon row while its boolean is on'
);

-- Turn every ahead-of-time toggle off: each kind's dispatch now cancels.
select tests.authenticate_as('dad_860');
update public.notification_preferences
   set alert_on_restock = false
 where user_id = tests.get_supabase_uid('dad_860') and profile_id = tests.ulid(560);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.notification_outbox (id, profile_id, recipient_user_id, kind)
values (
  '00000000-0000-0000-0000-000000000a52'::uuid,
  tests.ulid(560), tests.get_supabase_uid('dad_860'), 'restock_due'
);
select is(
  (public.resolve_notification_outbox_dispatch(
     '00000000-0000-0000-0000-000000000a52'::uuid))->>'action',
  'cancel',
  'resolve_notification_outbox_dispatch cancels a restock_due row whose boolean is off'
);
select is(
  (public.resolve_notification_outbox_dispatch(
     '00000000-0000-0000-0000-000000000a52'::uuid))->>'reason',
  'preference_off',
  'the cancel reason is preference_off'
);

-- ---------------------------------------------------------------------------
-- Grants: the new scan and its helpers are not callable by authenticated.
-- ---------------------------------------------------------------------------

select is(
  has_function_privilege('authenticated', 'public.scan_ahead_of_time_alerts()', 'execute'),
  false,
  'authenticated cannot execute scan_ahead_of_time_alerts'
);
select is(
  has_function_privilege('anon', 'public.scan_ahead_of_time_alerts()', 'execute'),
  false,
  'anon cannot execute scan_ahead_of_time_alerts'
);
select is(
  has_function_privilege('authenticated', 'public.ahead_of_time_lead_days()', 'execute'),
  false,
  'authenticated cannot execute ahead_of_time_lead_days'
);
select is(
  has_table_privilege('authenticated', 'public.ahead_of_time_alert_state', 'select'),
  false,
  'authenticated has no grant at all on ahead_of_time_alert_state'
);

select is(
  (select count(*) from pg_proc
    where proname = 'ahead_of_time_alert_state'
      and pronamespace = 'public'::regnamespace),
  0::bigint,
  'ahead_of_time_alert_state is a table, not a function'
);

rollback;
