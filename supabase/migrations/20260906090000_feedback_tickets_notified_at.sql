-- Migration: 20260906090000_feedback_tickets_notified_at.sql
-- Closes a feedback-notify abuse vector found in PR #105 review: the
-- function re-read any caller-supplied ticket_id with the service-role key
-- and emailed the admin with no ownership check and no replay guard, so a
-- signed-in account could invoke it repeatedly (its own tickets, or a
-- guessed id) to flood the support inbox and burn the Resend send quota.
--
-- This migration supplies the replay/rate half of that fix: notified_at,
-- set exactly once by feedback-notify (service role only - not in any
-- authenticated grant) via a conditional
-- `UPDATE ... WHERE notified_at IS NULL`. That conditional update is the
-- atomic claim: the first invocation for a ticket matches the row and
-- proceeds to send; every later invocation for the same ticket matches zero
-- rows and is a no-op, regardless of how many times or how close together
-- the caller invokes the function. The ownership half (the calling user's
-- auth id must match the ticket's user_id) lives in the function itself,
-- since it needs the caller's JWT, not a schema change.

alter table public.feedback_tickets
  add column notified_at timestamptz;

comment on column public.feedback_tickets.notified_at is
  'Set once by feedback-notify (service role, via UPDATE ... WHERE notified_at IS NULL) the first time the new-ticket admin alert is actually sent. Never in any authenticated grant, so only the function can set it - this is what makes repeated feedback-notify calls for the same ticket send at most one email.';
