-- Coverage for public.scan_missed_entry_reminders(),
-- public.sweep_notification_outbox(), and public.upsert_reminder_window()
-- (Issue #5, Unit U3). Runs on a stack started without pg_cron/pg_net
-- (AGENTS.md's `supabase start -x ...` exclusion list) -- these functions
-- are exercised directly, proving KTD9's guard: the scan/sweep logic never
-- depends on the cron schedule actually existing.
begin;
select plan(33);

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
-- Group 510 (#8 review fix): two co-guardians on the same profile with
-- different missed_entry_days thresholds must be deduped independently --
-- one guardian being enqueued for a window must never silently suppress a
-- co-guardian's own alert for that same window.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s10');
select tests.create_supabase_user('dad_s10');
select tests.create_supabase_user('step_s10');

select tests.authenticate_as('mom_s10');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(510), 'S10', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(510), 'co_parent', 'Dad',
  '6767676767676767676767676767676767676767676767676767676767676767', 48
);
select tests.authenticate_as('dad_s10');
select public.accept_guardian_invitation(
  '6767676767676767676767676767676767676767676767676767676767676767', 'Dad'
);
select tests.authenticate_as('mom_s10');
select public.create_guardian_invitation(
  tests.ulid(510), 'caregiver', 'Step',
  '6868686868686868686868686868686868686868686868686868686868686868', 48
);
select tests.authenticate_as('step_s10');
select public.accept_guardian_invitation(
  '6868686868686868686868686868686868686868686868686868686868686868', 'Step'
);

-- dad's threshold (1 day) is already met; step's (3 days, the max the
-- check constraint allows) is not yet -- the entry below is exactly 3 days
-- old, and eligibility requires strictly more than the threshold. Each
-- guardian inserts their own preference row (RLS requires user_id =
-- auth.uid()), so authenticate as each in turn.
select tests.authenticate_as('dad_s10');
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s10'), tests.ulid(510), 1);
select tests.authenticate_as('step_s10');
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('step_s10'), tests.ulid(510), 3);
select public.upsert_reminder_window(tests.ulid(510), (current_date - 1), false);

select tests.authenticate_as('mom_s10');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5100), tests.ulid(510), (current_date - 3), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(510), tests.get_supabase_uid('dad_s10')), 1::bigint,
  '#8: dad (threshold 1, already met) gets his one row on the first scan');
select is(pg_temp.outbox_count(tests.ulid(510), tests.get_supabase_uid('step_s10')), 0::bigint,
  '#8: step (threshold 5, not yet met) gets nothing on the first scan');

-- step's threshold now retroactively met (same window, same estimated_next_
-- start, no new entry, no app restart) -- exactly the scenario a co-guardian
-- with a longer threshold hits in practice as more days pass.
select tests.authenticate_as('step_s10');
update public.notification_preferences
   set missed_entry_days = 1
 where user_id = tests.get_supabase_uid('step_s10') and profile_id = tests.ulid(510);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(510), tests.get_supabase_uid('step_s10')), 1::bigint,
  '#8: step gets her own row on the second scan -- not silently suppressed by dad''s already-set marker for the same window');
select is(pg_temp.outbox_count(tests.ulid(510), tests.get_supabase_uid('dad_s10')), 1::bigint,
  '#8: dad still has exactly one row -- per-guardian dedupe still holds for him across the second scan');

-- ---------------------------------------------------------------------------
-- Group 511 (round-2 review #7): per-row exception isolation. A trigger
-- forces the notification_outbox insert to fail for exactly one recipient
-- on the profile; the sibling co-guardian's row in the same scan loop must
-- still be enqueued, and the scan call itself must not raise. This actually
-- fails against pre-fix code (the loop body has no begin/exception), unlike
-- the earlier lives_ok smoke calls on the cron wrappers above, which never
-- set anything up to fail.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s11');
select tests.create_supabase_user('dad_s11');
select tests.create_supabase_user('step_s11');

select tests.authenticate_as('mom_s11');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(511), 'S11', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(511), 'co_parent', 'Dad',
  '6969696969696969696969696969696969696969696969696969696969696969', 48
);
select tests.authenticate_as('dad_s11');
select public.accept_guardian_invitation(
  '6969696969696969696969696969696969696969696969696969696969696969', 'Dad'
);
select tests.authenticate_as('mom_s11');
select public.create_guardian_invitation(
  tests.ulid(511), 'caregiver', 'Step',
  '7070707070707070707070707070707070707070707070707070707070707070', 48
);
select tests.authenticate_as('step_s11');
select public.accept_guardian_invitation(
  '7070707070707070707070707070707070707070707070707070707070707070', 'Step'
);

select tests.authenticate_as('dad_s11');
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s11'), tests.ulid(511), 1);
select tests.authenticate_as('step_s11');
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('step_s11'), tests.ulid(511), 1);
select public.upsert_reminder_window(tests.ulid(511), (current_date - 1), false);

select tests.authenticate_as('mom_s11');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5110), tests.ulid(511), (current_date - 3), 'UTC', 'medium', now());

-- Forces the notification_outbox insert to fail for dad's row only --
-- step's row on the same profile, in the same scan invocation, is untouched.
-- CREATE TRIGGER needs the table owner's privilege, not merely a grant --
-- tests.clear_authentication() drops back to the session's own (postgres)
-- role for this DDL, same as every other pg_temp helper's setup in this
-- suite.
select tests.clear_authentication();
create function pg_temp.explode_for_dad_s11() returns trigger
language plpgsql as $$
begin
  if new.recipient_user_id = tests.get_supabase_uid('dad_s11') then
    raise exception 'forced row failure (round-2 review #7 test)';
  end if;
  return new;
end;
$$;
create trigger explode_for_dad_s11
  before insert on public.notification_outbox
  for each row execute function pg_temp.explode_for_dad_s11();

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select lives_ok(
  $$select public.scan_missed_entry_reminders()$$,
  '#7: the scan survives one recipient''s row raising -- it does not abort the whole loop'
);
select is(pg_temp.outbox_count(tests.ulid(511), tests.get_supabase_uid('dad_s11')), 0::bigint,
  '#7: dad''s own row failed and enqueued nothing for him');
select is(pg_temp.outbox_count(tests.ulid(511), tests.get_supabase_uid('step_s11')), 1::bigint,
  '#7: step''s row on the same profile still got enqueued despite dad''s row raising first');

select tests.clear_authentication();
drop trigger explode_for_dad_s11 on public.notification_outbox;
drop function pg_temp.explode_for_dad_s11();

-- ---------------------------------------------------------------------------
-- Group 513 (round-2 review #8): a guardian revoked and then re-invited,
-- with the same estimated_next_start still published, must not be silently
-- skipped by the scan's dedupe gate. Before the #8 follow-up fix (deleting
-- missed_entry_alert_state in revoke_guardian()), the stale marker from
-- before the revocation would survive it and block this second alert.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_s13');
select tests.create_supabase_user('dad_s13');

select tests.authenticate_as('mom_s13');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(513), 'S13', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(513), 'co_parent', 'Dad',
  '7171717171717171717171717171717171717171717171717171717171717171', 48
);
select tests.authenticate_as('dad_s13');
select public.accept_guardian_invitation(
  '7171717171717171717171717171717171717171717171717171717171717171', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s13'), tests.ulid(513), 1);
select public.upsert_reminder_window(tests.ulid(513), (current_date - 1), false);

select tests.authenticate_as('mom_s13');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(5130), tests.ulid(513), (current_date - 3), 'UTC', 'medium', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(513), tests.get_supabase_uid('dad_s13')), 1::bigint,
  '#8: dad gets his one row before being revoked');

-- Revoke, then re-invite and re-accept -- same estimated_next_start still
-- published on profile_reminder_windows the whole time, so a stale marker
-- would otherwise silently block the alert a second time.
select tests.authenticate_as('mom_s13');
select public.revoke_guardian(tests.ulid(513), tests.get_supabase_uid('dad_s13'));

-- missed_entry_alert_state has no authenticated grant at all (mirrors
-- notification_outbox's posture) -- read it as service_role.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select is(
  (select count(*) from public.missed_entry_alert_state
    where profile_id = tests.ulid(513) and user_id = tests.get_supabase_uid('dad_s13')),
  0::bigint,
  '#8: revoke_guardian deleted dad''s missed_entry_alert_state marker'
);
-- revoke_guardian's existing behavior (predating #8) also deletes any of
-- the revoked guardian's unsent outbox rows for the profile, so the one
-- row from before the revocation is gone too -- the second scan below
-- starts from zero, not one.
select is(pg_temp.outbox_count(tests.ulid(513), tests.get_supabase_uid('dad_s13')), 0::bigint,
  '#8: revoke_guardian also removed dad''s pre-revocation unsent outbox row (pre-existing behavior)');

select tests.authenticate_as('mom_s13');
select public.create_guardian_invitation(
  tests.ulid(513), 'co_parent', 'Dad Again',
  '7272727272727272727272727272727272727272727272727272727272727272', 48
);
select tests.authenticate_as('dad_s13');
select public.accept_guardian_invitation(
  '7272727272727272727272727272727272727272727272727272727272727272', 'Dad Again'
);
insert into public.notification_preferences (user_id, profile_id, missed_entry_days)
values (tests.get_supabase_uid('dad_s13'), tests.ulid(513), 1)
on conflict (user_id, profile_id) do update set missed_entry_days = excluded.missed_entry_days;

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select public.scan_missed_entry_reminders();
select is(pg_temp.outbox_count(tests.ulid(513), tests.get_supabase_uid('dad_s13')), 1::bigint,
  '#8: after revoke-then-re-invite, dad gets a fresh row -- not silently suppressed by a stale pre-revocation marker (would stay 0 without the #8 follow-up fix)');

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

-- #15/#9 (review fix): the two cron wrapper functions carry the same grant
-- posture, and each runs end to end without raising -- their whole purpose
-- is to isolate a failure in one step from the others, so a smoke call
-- (nothing set up to fail) proves at minimum that the isolation plumbing
-- itself does not introduce a new way to raise.
select is(
  has_function_privilege('authenticated', 'public.run_nightly_caregiver_alerts_job()', 'execute'),
  false,
  '#15: authenticated cannot execute run_nightly_caregiver_alerts_job'
);
select is(
  has_function_privilege('anon', 'public.run_nightly_caregiver_alerts_job()', 'execute'),
  false,
  '#15: anon cannot execute run_nightly_caregiver_alerts_job'
);
select is(
  has_function_privilege('authenticated', 'public.run_caregiver_alert_drain()', 'execute'),
  false,
  '#9: authenticated cannot execute run_caregiver_alert_drain'
);
select is(
  has_function_privilege('anon', 'public.run_caregiver_alert_drain()', 'execute'),
  false,
  '#9: anon cannot execute run_caregiver_alert_drain'
);
-- Neither function is granted to authenticated (just proven above) -- call
-- them as service_role, like every other direct call to a SECURITY
-- DEFINER caregiver-alert function elsewhere in this file.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select lives_ok(
  $$select public.run_nightly_caregiver_alerts_job()$$,
  '#15: run_nightly_caregiver_alerts_job runs scan, sweep, and dispatch without raising'
);
select lives_ok(
  $$select public.run_caregiver_alert_drain()$$,
  '#9: run_caregiver_alert_drain runs sweep and dispatch without raising'
);

-- #8 (review fix): missed_entry_alert_state is owned exclusively by
-- scan_missed_entry_reminders() -- no policies, no grants at all, mirroring
-- notification_outbox's posture.
select is(
  has_table_privilege('authenticated', 'public.missed_entry_alert_state', 'select'),
  false,
  '#8: authenticated has no grant at all on missed_entry_alert_state'
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
