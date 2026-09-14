-- Coverage for 20260914104000_notification_push_correctness.sql: the
-- notifications/push correctness bundle (#613, #630 -- LLA-073, LLA-074,
-- LLA-075, LLA-076).
begin;
select plan(27);

-- ---------------------------------------------------------------------------
-- LLA-073 (#613): trigger_push_dispatch() matches the real installed
-- pg_net signature (5 args: url, body, params, headers,
-- timeout_milliseconds) and actually enqueues via net.http_post, rather
-- than the old 4-argument availability probe that never matched anything
-- and always returned early. Verified against this stack's actual
-- installed net.http_post signature (checked live: `\df net.http_post`
-- reports exactly url/body/params/headers/timeout_milliseconds).
-- ---------------------------------------------------------------------------

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*)::int from net.http_request_queue
    where url = 'https://example.test/lla-073-push-dispatch'),
  0,
  'sanity: nothing queued yet for this fabricated URL'
);

select set_config('app.settings.push_dispatch_url', 'https://example.test/lla-073-push-dispatch', true);
select set_config('app.settings.push_dispatch_webhook_secret', 'fabricated-secret-lla073', true);

select public.trigger_push_dispatch();

select is(
  (select count(*)::int from net.http_request_queue
    where url = 'https://example.test/lla-073-push-dispatch'),
  1,
  'LLA-073: trigger_push_dispatch() enqueues exactly one net.http_post request once the pg_net availability '
  || 'probe matches the real 5-argument signature -- the pre-fix 4-argument probe always returned early here'
);

select is(
  (select headers->>'x-push-dispatch-webhook-secret' from net.http_request_queue
    where url = 'https://example.test/lla-073-push-dispatch'),
  'fabricated-secret-lla073',
  'the enqueued request carries the configured webhook secret header'
);

-- The pre-existing not-configured contract is untouched: clearing the URL
-- setting means no new request is queued.
select set_config('app.settings.push_dispatch_url', '', true);
select public.trigger_push_dispatch();
select is(
  (select count(*)::int from net.http_request_queue
    where url = 'https://example.test/lla-073-push-dispatch'),
  1,
  'trigger_push_dispatch() still no-ops when app.settings.push_dispatch_url is unset -- no new row queued'
);

select set_config('app.settings.push_dispatch_url', 'https://example.test/lla-073-push-dispatch', true);

-- ---------------------------------------------------------------------------
-- Shared fixture for LLA-074/075/076: one profile, one accepted guardian,
-- one notification_preferences row.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('pc_mom');
select tests.create_supabase_user('pc_dad');

select tests.authenticate_as('pc_mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(6801), 'Sage', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(6801), 'co_parent', 'Dad',
  '6801680168016801680168016801680168016801680168016801680168016801', 48
);
select tests.authenticate_as('pc_dad');
select public.accept_guardian_invitation(
  '6801680168016801680168016801680168016801680168016801680168016801', 'Dad'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence, cycle_start_cadence, high_severity_cadence, missed_entry_days)
values (
  tests.get_supabase_uid('pc_dad'), tests.ulid(6801), true, 'immediate', 'immediate', 'immediate', 2
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

create function pg_temp.insert_row(p_id uuid, p_kind text, p_sent boolean default false)
returns void
language sql security definer set search_path = '' as $$
  insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, sent_at)
  values (
    p_id, tests.ulid(6801), tests.get_supabase_uid('pc_dad'), p_kind,
    case when p_sent then now() else null end
  );
$$;

create function pg_temp.outbox_exists(p_id uuid)
returns boolean
language sql security definer set search_path = '' as $$
  select exists (select 1 from public.notification_outbox where id = p_id);
$$;

-- ---------------------------------------------------------------------------
-- LLA-076 part 1: cancel_outbox_on_preference_off (the transactional
-- cancel trigger).
-- ---------------------------------------------------------------------------

select pg_temp.insert_row('00000000-0000-0000-0000-000000006810'::uuid, 'logged');
select pg_temp.insert_row('00000000-0000-0000-0000-000000006811'::uuid, 'logged', true);  -- already sent
select pg_temp.insert_row('00000000-0000-0000-0000-000000006812'::uuid, 'cycle_start');
select pg_temp.insert_row('00000000-0000-0000-0000-000000006813'::uuid, 'high_severity');
select pg_temp.insert_row('00000000-0000-0000-0000-000000006814'::uuid, 'missed_entry');

update public.notification_preferences
   set log_cadence = 'off'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006810'::uuid), false,
  'LLA-076: turning log_cadence off deletes the unsent logged row'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006811'::uuid), true,
  'LLA-076: an already-sent logged row survives -- only sent_at IS NULL rows are cancelled'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006812'::uuid), true,
  'LLA-076: turning off only log_cadence leaves the cycle_start row untouched'
);

update public.notification_preferences
   set cycle_start_cadence = 'off'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006812'::uuid), false,
  'LLA-076: turning cycle_start_cadence off deletes the unsent cycle_start row'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006813'::uuid), true,
  'LLA-076: the high_severity row is untouched by the cycle_start change'
);

update public.notification_preferences
   set high_severity_cadence = 'off'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006813'::uuid), false,
  'LLA-076: turning high_severity_cadence off deletes the unsent high_severity row'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006814'::uuid), true,
  'LLA-076: the missed_entry row is untouched by the high_severity change'
);

update public.notification_preferences
   set missed_entry_days = null
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006814'::uuid), false,
  'LLA-076: setting missed_entry_days to null (its own off) deletes the unsent missed_entry row'
);

-- Reset preferences to all-on, then confirm the alert_on_log master
-- switch cancels every alert_on_log-gated kind in one update.
update public.notification_preferences
   set alert_on_log = true, log_cadence = 'immediate', cycle_start_cadence = 'immediate',
       high_severity_cadence = 'immediate', missed_entry_days = 2
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

select pg_temp.insert_row('00000000-0000-0000-0000-000000006820'::uuid, 'logged');
select pg_temp.insert_row('00000000-0000-0000-0000-000000006821'::uuid, 'cycle_start');
select pg_temp.insert_row('00000000-0000-0000-0000-000000006822'::uuid, 'high_severity');

update public.notification_preferences
   set alert_on_log = false
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006820'::uuid), false,
  'LLA-076: turning the alert_on_log master switch off cancels the logged row too'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006821'::uuid), false,
  'LLA-076: ...and the cycle_start row...'
);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006822'::uuid), false,
  'LLA-076: ...and the high_severity row, all in the same transactional update'
);

-- An unrelated preference edit (quiet hours) must never touch the queue.
update public.notification_preferences
   set alert_on_log = true, log_cadence = 'immediate'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select pg_temp.insert_row('00000000-0000-0000-0000-000000006823'::uuid, 'logged');
update public.notification_preferences
   set quiet_hours_start = '22:00:00', quiet_hours_end = '07:00:00', time_zone = 'UTC'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select is(
  pg_temp.outbox_exists('00000000-0000-0000-0000-000000006823'::uuid), true,
  'LLA-076: an unrelated preference change (quiet hours) never cancels the queue'
);
update public.notification_preferences
   set quiet_hours_start = null, quiet_hours_end = null, time_zone = null
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

-- ---------------------------------------------------------------------------
-- LLA-074/075/076 part 2: resolve_notification_outbox_dispatch, the
-- dispatch-time revalidation RPC.
-- ---------------------------------------------------------------------------

-- send: still eligible.
select pg_temp.insert_row('00000000-0000-0000-0000-000000006830'::uuid, 'logged');
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006830'::uuid),
  jsonb_build_object('action', 'send'),
  'resolve_notification_outbox_dispatch: a normal, still-eligible row resolves to send'
);

-- cancel/missing: the row is gone (deleted by revocation, or by the
-- trigger above -- either way, nothing to send).
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006831'::uuid),
  jsonb_build_object('action', 'cancel', 'reason', 'missing'),
  'resolve_notification_outbox_dispatch: a row that no longer exists resolves to cancel/missing (LLA-074/LLA-076)'
);

-- cancel/revoked: guardian membership no longer accepted, row still
-- present (the race LLA-074 targets -- claimed before a revocation's own
-- delete reaches this specific row).
select pg_temp.insert_row('00000000-0000-0000-0000-000000006832'::uuid, 'logged');
update public.profile_guardians
   set status = 'revoked'
 where profile_id = tests.ulid(6801) and user_id = tests.get_supabase_uid('pc_dad');
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006832'::uuid),
  jsonb_build_object('action', 'cancel', 'reason', 'revoked'),
  'LLA-074: a row whose guardian membership is no longer accepted resolves to cancel/revoked'
);
update public.profile_guardians
   set status = 'accepted'
 where profile_id = tests.ulid(6801) and user_id = tests.get_supabase_uid('pc_dad');

-- cancel/revoked (no preference row at all -- a different deletion path
-- than revoke_guardian reached it).
select pg_temp.insert_row('00000000-0000-0000-0000-000000006833'::uuid, 'logged');
delete from public.notification_preferences
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006833'::uuid),
  jsonb_build_object('action', 'cancel', 'reason', 'revoked'),
  'resolve_notification_outbox_dispatch: no preference row at all also resolves to cancel/revoked'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence, cycle_start_cadence, high_severity_cadence, missed_entry_days)
values (
  tests.get_supabase_uid('pc_dad'), tests.ulid(6801), true, 'immediate', 'immediate', 'immediate', 2
);

-- cancel/preference_off: the cadence is off *before* the row is inserted
-- (a row inserted directly, bypassing enqueue_caregiver_alerts()'s own
-- cadence gate -- the only way this branch is ever reached now that the
-- trigger above cancels an already-queued row the instant its cadence
-- turns off; inserting after the update, rather than before, is what
-- keeps this row from being deleted by that same trigger before this
-- assertion runs).
update public.notification_preferences
   set high_severity_cadence = 'off'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select pg_temp.insert_row('00000000-0000-0000-0000-000000006834'::uuid, 'high_severity');
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006834'::uuid),
  jsonb_build_object('action', 'cancel', 'reason', 'preference_off'),
  'LLA-076: a row whose governing cadence is off resolves to cancel/preference_off'
);
update public.notification_preferences
   set high_severity_cadence = 'immediate'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

-- cancel/preference_off: missed_entry_days null, same before-insert order.
update public.notification_preferences
   set missed_entry_days = null
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);
select pg_temp.insert_row('00000000-0000-0000-0000-000000006835'::uuid, 'missed_entry');
select is(
  public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006835'::uuid),
  jsonb_build_object('action', 'cancel', 'reason', 'preference_off'),
  'LLA-076: a missed_entry row with missed_entry_days null resolves to cancel/preference_off'
);
update public.notification_preferences
   set missed_entry_days = 2
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

-- defer: quiet hours cover virtually the whole day, so "now" (frozen for
-- this transaction) falls inside the window -- LLA-075.
select pg_temp.insert_row('00000000-0000-0000-0000-000000006836'::uuid, 'logged');
update public.notification_preferences
   set quiet_hours_start = '00:00:00', quiet_hours_end = '23:59:59', time_zone = 'UTC'
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

select is(
  (public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006836'::uuid))->>'action',
  'defer',
  'LLA-075: a row whose recipient is now inside quiet hours resolves to defer, not send'
);
select ok(
  ((public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006836'::uuid))->>'deliver_after')::timestamptz > now(),
  'LLA-075: the deferred deliver_after is strictly in the future'
);
update public.notification_preferences
   set quiet_hours_start = null, quiet_hours_end = null, time_zone = null
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

-- ---------------------------------------------------------------------------
-- Review confirmation: resolve_notification_outbox_dispatch's inner join
-- treats a missing notification_preferences row as cancel/revoked (see the
-- "no preference row at all" case above). That is only the right default
-- if no enqueue path can ever create a notification_outbox row without a
-- preferences row already existing. Every current enqueue path
-- (enqueue_caregiver_alerts, enqueue_observation_high_severity_alerts,
-- scan_missed_entry_reminders) selects the enqueued guardian FROM
-- notification_preferences via an inner join, so none of them can -- this
-- proves it for the day_entries trigger path directly rather than only by
-- code inspection: delete the preferences row, fire a real day_entries
-- write that would otherwise enqueue a 'logged' row, and confirm nothing
-- new lands in the outbox for this (profile, guardian).
-- ---------------------------------------------------------------------------

delete from public.notification_preferences
 where user_id = tests.get_supabase_uid('pc_dad') and profile_id = tests.ulid(6801);

create temporary table pg_temp.outbox_count_snapshot as
select count(*) as n from public.notification_outbox
 where profile_id = tests.ulid(6801) and recipient_user_id = tests.get_supabase_uid('pc_dad');

select tests.authenticate_as('pc_mom');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(6837), tests.ulid(6801), '2026-09-10', 'UTC', 'none', now());

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*) from public.notification_outbox
    where profile_id = tests.ulid(6801) and recipient_user_id = tests.get_supabase_uid('pc_dad')),
  (select n from pg_temp.outbox_count_snapshot),
  'a day_entries write that would otherwise enqueue a logged alert creates no notification_outbox row at all '
  || 'when the recipient has no notification_preferences row -- confirms resolve_notification_outbox_dispatch''s '
  || 'missing-row-means-revoked default can never fire on a row a legitimate enqueue path created without one'
);

insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, log_cadence, cycle_start_cadence, high_severity_cadence, missed_entry_days)
values (
  tests.get_supabase_uid('pc_dad'), tests.ulid(6801), true, 'immediate', 'immediate', 'immediate', 2
);

-- ---------------------------------------------------------------------------
-- Grants: neither new function is reachable by authenticated/anon,
-- matching every other push-dispatch-only function's precedent
-- (release_notification_outbox_claim, sweep_notification_outbox).
-- ---------------------------------------------------------------------------

select tests.authenticate_as('pc_dad');
select throws_ok(
  $$select public.resolve_notification_outbox_dispatch('00000000-0000-0000-0000-000000006830'::uuid)$$,
  '42501', null,
  'authenticated has no execute grant on resolve_notification_outbox_dispatch'
);
select throws_ok(
  $$select public.cancel_outbox_on_preference_off()$$,
  '42501', null,
  'authenticated has no execute grant on cancel_outbox_on_preference_off (it is a trigger function, never '
  || 'called directly)'
);

select * from finish();
rollback;
