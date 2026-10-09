-- Caregiver-alert cron registrations (issue #1741).
--
-- The two jobs below are the one piece of the push pipeline no pgTAP test
-- pinned: if a future re-run of the registration DO block in
-- `20260906230000_reminder_windows_and_cron.sql` drops or mistimes them --
-- or pg_net is unavailable at migration time and the DO block's silent
-- `return` skips them -- nothing alerts. Claims parked by a crashed
-- `push-dispatch` invocation stay claimed forever (the drain's
-- `sweep_notification_outbox()` is their only recovery), and
-- quiet-hours-deferred rows never send. This pin mirrors
-- `nightly_retention_job_test.sql`'s extension-guarded shape, so the
-- assertion itself degrades gracefully (rather than failing db reset) on
-- an environment where pg_cron is unavailable.
begin;
select plan(2);

select ok(
  (not exists (select 1 from pg_available_extensions where name = 'pg_cron'))
  or exists (
    select 1 from cron.job
     where jobname = 'lunarlog-nightly-caregiver-alerts'
       and schedule = '0 9 * * *'
       and command = 'select public.run_nightly_caregiver_alerts_job();'
  ),
  'lunarlog-nightly-caregiver-alerts is registered with pg_cron when the extension is available'
);

select ok(
  (not exists (select 1 from pg_available_extensions where name = 'pg_cron'))
  or exists (
    select 1 from cron.job
     where jobname = 'lunarlog-caregiver-alert-drain'
       and schedule = '*/15 * * * *'
       and command = 'select public.run_caregiver_alert_drain();'
  ),
  'lunarlog-caregiver-alert-drain is registered with pg_cron when the extension is available'
);

select * from finish();
rollback;
