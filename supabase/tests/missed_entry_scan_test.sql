-- Coverage for public.scan_missed_entry_reminders(),
-- public.sweep_notification_outbox(), and public.upsert_reminder_window()
-- (Issue #5, Unit U3). Runs on a stack started without pg_cron/pg_net
-- (AGENTS.md's `supabase start -x ...` exclusion list) -- these functions
-- are exercised directly, proving KTD9's guard: the scan/sweep logic never
-- depends on the cron schedule actually existing.
begin;
select plan(15);

create function pg_temp.outbox_count(p_profile text, p_recipient uuid) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient and kind = 'missed_entry';
$$;

-- ---------------------------------------------------------------------------
-- Group 508: no preference row at all -- the scan touches nothing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s8');
select tests.create_supabase_user('dad_s8');

select tests.authenticate_as('mom_s8');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(508), 'S8', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(508), 'co_parent', 'Dad',
  '6060606060606060606060606060606060606060606060606060606060606060', 48
);
select tests.authenticate_as('dad_s8');
select public.accept_guardian_invitation(
  '6060606060606060606060606060606060606060606060606060606060606060', 'Dad'
);
select tests.authenticate_as('mom_s8');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5080), tests.ulid(508), (current_date - 10), 'UTC', 'heavy', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(508), tests.get_supabase_uid('dad_s8')), 0::bigint,
  'No preference row with a threshold: the scan enqueues nothing');

-- ---------------------------------------------------------------------------
-- Group 502: the main threshold/dedupe/re-arm flow.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s2');
select tests.create_supabase_user('dad_s2');

select tests.authenticate_as('mom_s2');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(502), 'S2', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(502), 'co_parent', 'Dad',
  '6161616161616161616161616161616161616161616161616161616161616161', 48
);
select tests.authenticate_as('dad_s2');
select public.accept_guardian_invitation(
  '6161616161616161616161616161616161616161616161616161616161616161', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s2'), tests.ulid(502), 2);
select public.upsert_reminder_window(tests.ulid(502), (current_date - 1), false);

select tests.authenticate_as('mom_s2');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5020), tests.ulid(502), (current_date - 3), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(502), tests.get_supabase_uid('dad_s2')), 1::bigint,
  'Threshold 2, newest entry 3 days old, predicted start already passed: exactly one missed_entry row');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(502), tests.get_supabase_uid('dad_s2')), 1::bigint,
  'Same state, scan called twice: still exactly one row (last_enqueued_for dedupe)');

-- The window advances (a fresh estimate is published, e.g. after a new
-- entry); the underlying staleness is unchanged, so the dedupe key alone
-- decides whether a later scan can fire again.
select tests.authenticate_as('dad_s2');
select public.upsert_reminder_window(tests.ulid(502), (current_date - 5), false);
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(502), tests.get_supabase_uid('dad_s2')), 2::bigint,
  'Same state, then the window advances: a later scan can enqueue again');

-- ---------------------------------------------------------------------------
-- Group 503: predicted start in the future, no episode open -- nothing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s3');
select tests.create_supabase_user('dad_s3');

select tests.authenticate_as('mom_s3');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(503), 'S3', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(503), 'co_parent', 'Dad',
  '6262626262626262626262626262626262626262626262626262626262626262', 48
);
select tests.authenticate_as('dad_s3');
select public.accept_guardian_invitation(
  '6262626262626262626262626262626262626262626262626262626262626262', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s3'), tests.ulid(503), 2);
select public.upsert_reminder_window(tests.ulid(503), (current_date + 10), false);

select tests.authenticate_as('mom_s3');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5030), tests.ulid(503), (current_date - 3), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(503), tests.get_supabase_uid('dad_s3')), 0::bigint,
  'Threshold 2, newest entry 3 days old, but predicted start is in the future and no episode is open: nothing enqueued');

-- ---------------------------------------------------------------------------
-- Group 504: newest entry only 1 day old -- nothing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s4');
select tests.create_supabase_user('dad_s4');

select tests.authenticate_as('mom_s4');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(504), 'S4', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(504), 'co_parent', 'Dad',
  '6363636363636363636363636363636363636363636363636363636363636363', 48
);
select tests.authenticate_as('dad_s4');
select public.accept_guardian_invitation(
  '6363636363636363636363636363636363636363636363636363636363636363', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s4'), tests.ulid(504), 2);
select public.upsert_reminder_window(tests.ulid(504), (current_date - 1), false);

select tests.authenticate_as('mom_s4');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5040), tests.ulid(504), (current_date - 1), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(504), tests.get_supabase_uid('dad_s4')), 0::bigint,
  'Threshold 2, newest entry 1 day old: nothing enqueued');

-- ---------------------------------------------------------------------------
-- Group 505: episode open, stale newest entry, prediction not yet passed.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s5');
select tests.create_supabase_user('dad_s5');

select tests.authenticate_as('mom_s5');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(505), 'S5', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(505), 'co_parent', 'Dad',
  '6464646464646464646464646464646464646464646464646464646464646464', 48
);
select tests.authenticate_as('dad_s5');
select public.accept_guardian_invitation(
  '6464646464646464646464646464646464646464646464646464646464646464', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s5'), tests.ulid(505), 2);
select public.upsert_reminder_window(tests.ulid(505), (current_date + 10), true);

select tests.authenticate_as('mom_s5');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5050), tests.ulid(505), (current_date - 5), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(505), tests.get_supabase_uid('dad_s5')), 1::bigint,
  'episode_open true with a stale newest entry and no passed prediction: one row');

-- ---------------------------------------------------------------------------
-- Group 506: a revoked guardian is excluded even with a threshold set.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s6');
select tests.create_supabase_user('dad_s6');

select tests.authenticate_as('mom_s6');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(506), 'S6', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(506), 'co_parent', 'Dad',
  '6565656565656565656565656565656565656565656565656565656565656565', 48
);
select tests.authenticate_as('dad_s6');
select public.accept_guardian_invitation(
  '6565656565656565656565656565656565656565656565656565656565656565', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s6'), tests.ulid(506), 2);
select public.upsert_reminder_window(tests.ulid(506), (current_date - 1), false);

select tests.authenticate_as('mom_s6');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5060), tests.ulid(506), (current_date - 3), 'UTC', 'medium', now());
select public.revoke_guardian(tests.ulid(506), tests.get_supabase_uid('dad_s6'));

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(506), tests.get_supabase_uid('dad_s6')), 0::bigint,
  'A revoked guardian with a threshold set: nothing enqueued');

-- ---------------------------------------------------------------------------
-- Group 507: RLS on upsert_reminder_window.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s7');
select tests.create_supabase_user('stranger_s7');

select tests.authenticate_as('mom_s7');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(507), 'S7', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select tests.authenticate_as('stranger_s7');
select throws_ok(
  format($$select public.upsert_reminder_window(%L, current_date, false)$$, tests.ulid(507)),
  '42501', null,
  'upsert_reminder_window called by a non-guardian is rejected by RLS'
);

-- ---------------------------------------------------------------------------
-- Grants: neither function is callable by authenticated or anon.
-- ---------------------------------------------------------------------------
select is(
  has_function_privilege('authenticated', 'public.scan_missed_entry_reminders()', 'execute'),
  false,
  'authenticated cannot execute scan_missed_entry_reminders'
);
select is(
  has_function_privilege('anon', 'public.scan_missed_entry_reminders()', 'execute'),
  false,
  'anon cannot execute scan_missed_entry_reminders'
);
select is(
  has_function_privilege('authenticated', 'public.sweep_notification_outbox()', 'execute'),
  false,
  'authenticated cannot execute sweep_notification_outbox'
);
select is(
  has_function_privilege('anon', 'public.sweep_notification_outbox()', 'execute'),
  false,
  'anon cannot execute sweep_notification_outbox'
);

-- ---------------------------------------------------------------------------
-- sweep_notification_outbox: releases a stale claim, leaves a fresh one.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s9');
select tests.authenticate_as('mom_s9');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(509), 'S9', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at)
values (
  '00000000-0000-0000-0000-000000000901'::uuid, tests.ulid(509), tests.get_supabase_uid('mom_s9'),
  'logged', now() - interval '20 minutes'
);
insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, claimed_at)
values (
  '00000000-0000-0000-0000-000000000902'::uuid, tests.ulid(509), tests.get_supabase_uid('mom_s9'),
  'logged', now() - interval '1 minute'
);

select public.sweep_notification_outbox();

select is(
  (select claimed_at from public.notification_outbox where id = '00000000-0000-0000-0000-000000000901'::uuid),
  null,
  'sweep_notification_outbox releases a claim stamped 20 minutes ago'
);
select isnt(
  (select claimed_at from public.notification_outbox where id = '00000000-0000-0000-0000-000000000902'::uuid),
  null,
  'sweep_notification_outbox leaves a claim stamped 1 minute ago alone'
);

rollback;
