-- Migration: 20260914104000_notification_push_correctness.sql
-- Whole-repository audit bundle: #613, #630 (LLA-073, LLA-074, LLA-075,
-- LLA-076). Per the repo's standing rule, no merged migration is edited in
-- place -- every function below is `create or replace`d from its current
-- body on `main` (see each section's header for the exact source file),
-- plus exactly the fix each finding asks for.
--
-- ---------------------------------------------------------------------------
-- LLA-073 (#613): trigger_push_dispatch() checked a pg_net signature that
-- has never existed on the installed extension, so it always no-op'd --
-- `to_regprocedure` returned null every time, even with pg_net installed
-- and configured, and the function silently skipped the HTTP enqueue on
-- every call (nightly job, 15-minute drain, and every Database Webhook
-- fallback path that routes through it).
--
-- The real installed signature (pg_net 0.20.4, confirmed against the
-- extension's own published signature -- context7 /supabase/pg_net):
--   net.http_post(
--     url text,
--     body jsonb default '{}'::jsonb,
--     params jsonb default '{}'::jsonb,
--     headers jsonb default '{"Content-Type": "application/json"}'::jsonb,
--     timeout_milliseconds int default 1000
--   ) returns bigint
-- five arguments (url, body, params, headers, timeout_milliseconds), not
-- the four (url, body, headers, timeout) the old check probed for. The
-- call below already passes named arguments in the correct shape (url,
-- headers, body) -- only the availability probe was wrong.
--
-- Body carried forward verbatim from 20260906230000_reminder_windows_and_cron.sql
-- (the only migration that has ever defined this function) except the one
-- `to_regprocedure(...)` line.
-- ---------------------------------------------------------------------------

create or replace function public.trigger_push_dispatch() returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text := current_setting('app.settings.push_dispatch_url', true);
  v_secret text := current_setting('app.settings.push_dispatch_webhook_secret', true);
begin
  if v_url is null or v_url = '' or v_secret is null or v_secret = '' then
    raise notice 'trigger_push_dispatch: app.settings.push_dispatch_url/_webhook_secret not configured, skipping (see docs/ops/supabase-go-live.md)';
    return;
  end if;

  -- LLA-073 fix: the real installed pg_net signature is five arguments
  -- (url, body, params, headers, timeout_milliseconds) -- the previous
  -- four-argument probe (url, body, headers, timeout) never matched any
  -- registered function, so this always fell through to the "pg_net not
  -- available" branch even when pg_net was installed and configured.
  if to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)') is null then
    raise notice 'trigger_push_dispatch: pg_net not available, skipping';
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-dispatch-webhook-secret', v_secret
    ),
    body := '{}'::jsonb
  );
exception
  when others then
    -- Best-effort: a failed sweep-triggered dispatch is recovered by the
    -- Database Webhook (immediacy path) and the next nightly sweep, per
    -- KTD3 -- it must never fail the cron job that also runs the scan and
    -- sweep above.
    raise notice 'trigger_push_dispatch: dispatch call failed, will retry next cycle';
end;
$$;

comment on function public.trigger_push_dispatch() is
  'Fires push-dispatch via pg_net from the cron wrappers (nightly job, '
  '15-minute drain) when app.settings.push_dispatch_url/_webhook_secret '
  'are configured. LLA-073 (#613): the pg_net availability probe now '
  'matches the extension''s real 5-argument net.http_post signature (url, '
  'body, params, headers, timeout_milliseconds) -- the old 4-argument '
  'probe never matched anything, so this always skipped the HTTP call even '
  'with pg_net installed and configured. Never raises out to the caller.';

revoke all on function public.trigger_push_dispatch() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- LLA-076 (#630), part 1 of 2 -- the transactional cancel. Turning a kind
-- off (alert_on_log false, or a per-kind cadence column set to 'off', or
-- missed_entry_days set to null) previously only changed the preference
-- row: enqueue_caregiver_alerts() and scan_missed_entry_reminders() would
-- stop creating *new* rows for that kind, but every row already queued --
-- an immediate row not yet claimed, or a digest row held with
-- deliver_after = 'infinity' -- stayed exactly as deliverable as before,
-- since sweep_alert_digests() only checks that a preference row exists at
-- all, never whether the specific kind it is about to promote is still
-- enabled.
--
-- Mirrors revoke_guardian()'s own precedent (20260909200000_prediction_
-- connections.sql, R5: "any of their pending, unsent alerts ... removed
-- too") for the *same* content-free, sent_at-is-null delete shape, but
-- scoped per (user, profile, kind) instead of per (user, profile) --
-- exactly one kind may have turned off, and the guardian's other alert
-- kinds must be untouched.
--
-- part 2 (the dispatch-time revalidation, closing the residual claim/
-- dispatch race this trigger cannot -- a row already claimed by a running
-- push-dispatch invocation before this UPDATE commits) is
-- resolve_notification_outbox_dispatch() below.
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

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

comment on function public.cancel_outbox_on_preference_off() is
  'AFTER UPDATE trigger on notification_preferences (LLA-076, issue #630): '
  'when a kind''s cadence (or missed_entry_days, or the alert_on_log '
  'master switch) transitions to off, deletes every unsent '
  'notification_outbox row of that kind for this (user, profile) -- '
  'immediate rows not yet claimed and daily_digest-held rows alike. '
  'Mirrors revoke_guardian()''s sent_at-is-null delete shape, scoped per '
  'kind instead of per profile. Deliberately fires per changed kind only '
  '(the OLD/NEW comparison), so an unrelated preference edit (e.g. quiet '
  'hours) never touches another kind''s queue.';

revoke execute on function public.cancel_outbox_on_preference_off() from public, anon, authenticated;

create trigger notification_preferences_cancel_outbox_on_off
  after update on public.notification_preferences
  for each row
  when (
    old.alert_on_log is distinct from new.alert_on_log
    or old.log_cadence is distinct from new.log_cadence
    or old.cycle_start_cadence is distinct from new.cycle_start_cadence
    or old.high_severity_cadence is distinct from new.high_severity_cadence
    or old.missed_entry_days is distinct from new.missed_entry_days
  )
  execute function public.cancel_outbox_on_preference_off();

-- ---------------------------------------------------------------------------
-- LLA-074, LLA-075, LLA-076 part 2 (#630): one dispatch-time revalidation
-- RPC, called by push-dispatch/index.ts's dispatchOneRow() right after
-- claiming a row and before any device is ever touched.
--
-- LLA-074 (revocation cannot cancel a claimed-but-not-yet-handed-off row):
-- the row itself may already be gone (revoke_guardian deletes unsent rows
-- -- "not found" below), or the guardian membership may have been revoked
-- by some other path that hasn't deleted this specific row yet; either way
-- this returns 'cancel' rather than letting a stale in-memory copy reach a
-- device. The unavoidable residual window is a row that has *already*
-- been hand off to FCM before this check runs -- a send in flight cannot
-- be recalled by any mechanism, database or otherwise; this closes the
-- window to "checked immediately before handoff" rather than "never
-- checked at all".
--
-- LLA-075 (quiet hours not rechecked at dispatch time): resolve_deliver_
-- after() is re-run against *now*, not the moment the row was enqueued --
-- a delayed dispatch (backlog, a retry, or a digest just promoted by
-- sweep_alert_digests()) that has since drifted into a quiet-hours window
-- is deferred to the window's end rather than sent.
--
-- LLA-076 part 2 (residual race): the same guardian/preference join also
-- re-checks the governing kind's cadence -- closes the window between a
-- preference-off UPDATE (part 1's trigger deletes unclaimed rows) and a
-- push-dispatch invocation that claimed the row a moment earlier.
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
         p.high_severity_cadence, p.missed_entry_days
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
  'Issue #630 (LLA-074, LLA-075, LLA-076): re-validates one just-claimed '
  'notification_outbox row immediately before push-dispatch/index.ts '
  'touches any device. Returns {"action": "cancel", "reason": ...} when '
  'the row is gone or the recipient''s guardian membership or governing '
  'kind/cadence preference no longer allows it (LLA-074/LLA-076 -- the '
  'caller deletes the row rather than sending), {"action": "defer", '
  '"deliver_after": ...} when quiet hours have opened since the row '
  'became due (LLA-075 -- the caller clears the claim and updates '
  'deliver_after without counting it as a failed attempt), or {"action": '
  '"send"} when still eligible. The window between a send already handed '
  'to FCM and this check cannot be closed by any database-side mechanism '
  '-- that send cannot be recalled -- so this is "checked immediately '
  'before handoff", not a guarantee against every possible race.';

revoke all on function public.resolve_notification_outbox_dispatch(uuid) from public, anon, authenticated;
