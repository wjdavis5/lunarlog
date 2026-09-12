-- Migration: 20260913020000_notification_outbox_retry_tracking.sql
-- Issue #526 (P1): notification_outbox retries were effectively unbounded --
-- three defects compounded into duplicate pushes:
--   (1) push-dispatch/index.ts tracked delivery per outbox row, not per
--       device: one failing device on a multi-device recipient released the
--       whole row's claim, and every already-succeeded device was re-sent on
--       every retry.
--   (2) releaseClaim did a non-atomic read-modify-write on `attempts`
--       (select, then a separate update), so a concurrent claim/release on
--       the same row could lose an increment, and any error on the read was
--       silently dropped, resetting the effective counter to 1.
--   (3) sweep_notification_outbox() released a stuck claim without touching
--       `attempts` at all, so a row stuck by a killed process retried
--       forever with no bound and no visible signal in `last_error_kind`.
--
-- This migration is the schema half of the fix (push-dispatch/index.ts
-- carries the rest -- see that file's header):
--   (a) public.notification_outbox_deliveries -- one row per (outbox row,
--       device) actually delivered to, so a retry after a partial failure
--       only re-sends to the devices that haven't succeeded yet, never the
--       ones that already have (closes defect 1).
--   (b) public.release_notification_outbox_claim(p_id, p_claimed_at,
--       p_error_kind) -- one atomic `UPDATE ... WHERE id = $1 AND
--       claimed_at = $2`, replacing the Edge Function's own
--       select-then-update. Passing back the exact `claimed_at` this
--       invocation claimed the row with acts as an optimistic-lock token: a
--       row that was somehow claimed again by a different invocation between
--       this one's claim and its release (should not happen given
--       claimBatch's own `.is("claimed_at", null)` guard, but this is cheap
--       insurance against ever silently clobbering a concurrent claim) simply
--       does not match and the release becomes a no-op rather than an
--       incorrect increment (closes defect 2).
--   (c) sweep_notification_outbox() re-declared to also increment `attempts`
--       and stamp `last_error_kind = 'stuck_claim_swept'` when it releases a
--       stuck claim, so a row a killed process abandoned mid-send is now
--       bounded by MAX_ATTEMPTS exactly like every other retry path, and is
--       diagnosable in `last_error_kind` rather than silently indistinguish-
--       able from a claim that was never even attempted (closes defect 3).
--
-- Per the repo's standing rule, this is a new migration file only; no merged
-- migration (20260906220000_notification_outbox.sql,
-- 20260906230000_reminder_windows_and_cron.sql) is edited in place.

-- ---------------------------------------------------------------------------
-- (a) Per-device delivery tracking.
-- ---------------------------------------------------------------------------

create table public.notification_outbox_deliveries (
  outbox_id uuid not null
    references public.notification_outbox (id) on delete cascade,
  device_id uuid not null
    references public.push_devices (id) on delete cascade,
  sent_at timestamptz not null default now(),
  primary key (outbox_id, device_id)
);

comment on table public.notification_outbox_deliveries is
  'Per-device delivery record for a notification_outbox row (Issue #526): '
  'push-dispatch inserts one row here immediately after a successful FCM '
  'send to a given device, and skips any device already recorded here on a '
  'later attempt at the same outbox row -- so a row released for retry '
  '(because a different device on the same row failed) never re-sends to a '
  'device that already succeeded. Content-free like notification_outbox '
  'itself: no column here can hold entry content, only the two foreign keys '
  'and a timestamp. No authenticated policy exists at all -- drained and '
  'written only by the push-dispatch Edge Function''s service-role client, '
  'which carries BYPASSRLS.';

create index notification_outbox_deliveries_device_idx
  on public.notification_outbox_deliveries (device_id);

alter table public.notification_outbox_deliveries enable row level security;
alter table public.notification_outbox_deliveries force row level security;

-- Deliberately no policies and no grants for authenticated/anon, mirroring
-- notification_outbox's own precedent (20260906220000_notification_outbox.sql):
-- RLS with zero policies denies every row to every role it applies to.
-- service_role carries BYPASSRLS and reaches this table regardless.
revoke all on table public.notification_outbox_deliveries from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- (b) Atomic claim release.
-- ---------------------------------------------------------------------------

create or replace function public.release_notification_outbox_claim(
  p_id uuid,
  p_claimed_at timestamptz,
  p_error_kind text
) returns void
language sql
security definer
set search_path = ''
as $$
  update public.notification_outbox
     set claimed_at = null,
         attempts = attempts + 1,
         last_error_kind = p_error_kind
   where id = p_id
     and claimed_at = p_claimed_at;
$$;

comment on function public.release_notification_outbox_claim(uuid, timestamptz, text) is
  'Atomically releases a notification_outbox claim this caller''s own '
  'invocation just won (Issue #526 fix (b)): one UPDATE ... WHERE id = $1 '
  'AND claimed_at = $2, replacing push-dispatch''s old non-atomic '
  'select-then-update (which could drop an attempts increment on a '
  'concurrent release, or silently reset it to 1 if the select itself '
  'failed). p_claimed_at is the exact value the caller claimed the row '
  'with, acting as an optimistic-lock token -- a row re-claimed by a '
  'different invocation in between (should not happen given claimBatch''s '
  'own `.is("claimed_at", null)` guard) simply does not match, and this '
  'becomes a no-op rather than an incorrect increment on someone else''s '
  'claim. Always increments attempts, matching every other release path '
  '(claimBatch bounds retries at MAX_ATTEMPTS).';

revoke all on function public.release_notification_outbox_claim(uuid, timestamptz, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- (c) sweep_notification_outbox now bounds retries too.
-- ---------------------------------------------------------------------------

create or replace function public.sweep_notification_outbox() returns integer
language sql
security definer
set search_path = ''
as $$
  with released as (
    update public.notification_outbox
       set claimed_at = null,
           attempts = attempts + 1,
           last_error_kind = 'stuck_claim_swept'
     where claimed_at is not null
       and sent_at is null
       and claimed_at < now() - interval '15 minutes'
    returning 1
  )
  select count(*)::integer from released;
$$;

comment on function public.sweep_notification_outbox() is
  'Releases a notification_outbox claim older than 15 minutes with no '
  'sent_at, recovering push-dispatch''s claim-before-send pattern (KTD2) '
  'from a process killed mid-send. Issue #526 fix (c): now also increments '
  '`attempts` and stamps `last_error_kind = ''stuck_claim_swept''` on every '
  'row it releases, so a row stuck by a killed process is bounded by '
  'MAX_ATTEMPTS exactly like every other retry path (previously this was '
  'the one release path with no bound at all, and no signal in '
  '`last_error_kind` either) -- returns the number of claims released.';

revoke all on function public.sweep_notification_outbox() from public, anon, authenticated;
