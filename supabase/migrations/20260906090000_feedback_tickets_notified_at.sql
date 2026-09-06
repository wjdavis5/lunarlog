-- Migration: 20260906090000_feedback_tickets_notified_at.sql
-- Closes a feedback-notify abuse vector found in PR #105 review: the
-- function re-read any caller-supplied ticket_id with the service-role key
-- and emailed the admin with no ownership check and no replay guard, so a
-- signed-in account could invoke it repeatedly (its own tickets, or a
-- guessed id) to flood the support inbox and burn the Resend send quota.
--
-- This migration supplies the replay/rate half of that fix: notified_at,
-- claimed by feedback-notify (service role only - not in any authenticated
-- grant) via a conditional `UPDATE ... WHERE notified_at IS NULL`, run
-- BEFORE the function attempts to send anything. That conditional update is
-- the atomic claim: the first invocation for a ticket matches the row and
-- proceeds to send; every other concurrent/overlapping or later invocation
-- for the same ticket matches zero rows and is a no-op, regardless of how
-- many times or how close together the caller invokes the function. If the
-- claiming invocation's send then fails, it clears notified_at back to null
-- (releasing its own claim) so a legitimate retry can still send - the net
-- effect is that notified_at ends up non-null if and only if the alert was
-- actually sent. The ownership half (the calling user's auth id must match
-- the ticket's user_id) lives in the function itself, since it needs the
-- caller's JWT, not a schema change.

alter table public.feedback_tickets
  add column notified_at timestamptz;

comment on column public.feedback_tickets.notified_at is
  'Claimed by feedback-notify (service role, via UPDATE ... WHERE notified_at IS NULL) before it attempts to send, and cleared back to null if that send fails - so it is non-null if and only if the new-ticket admin alert was actually sent. Never in any authenticated grant, so only the function can set or clear it - this is what makes concurrent/overlapping or repeated feedback-notify calls for the same ticket send at most one email.';
