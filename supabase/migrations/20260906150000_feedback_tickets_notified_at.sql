-- Migration: 20260906150000_feedback_tickets_notified_at.sql
-- Renamed from an original 20260906090000_ prefix (PR #105 review, item 3;
-- see 20260906130000_feedback_tickets.sql's header for why).
--
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
-- (releasing its own claim) so a legitimate retry can still send - in the
-- ordinary case (the claiming invocation actually runs to completion, one
-- way or the other), notified_at ends up non-null if and only if the alert
-- was actually sent. The ownership half (the calling user's auth id must
-- match the ticket's user_id) lives in the function itself, since it needs
-- the caller's JWT, not a schema change.
--
-- PR #105 review round 5: claiming BEFORE the send (rather than after, as
-- an earlier version of the function did) is what makes the claim atomic
-- under concurrency - but it also means a claim can be committed with the
-- send still in flight. `_shared/email.ts`'s Resend fetch now carries an
-- `AbortSignal.timeout` so a hung send fails in time for feedback-notify's
-- normal release-claim-on-failure path to run - closing the ordinary "send
-- takes too long" case. What that timeout cannot close: if the function's
-- own process/isolate is killed between the claim and either the send
-- resolving or the timeout firing (e.g. a host crash, or a platform-level
-- kill that pre-empts even the timeout), notified_at stays committed with
-- no alert ever sent and nothing to trigger a release. This is a narrower
-- window than the one this fix replaced (an unbounded hang, not just an
-- external kill) but it is not literally zero, so "if and only if" above is
-- the intended invariant, not a claim that it is airtight against every
-- failure mode. Closing it fully would need a periodic reconciliation job
-- (clear notified_at on any claim older than N minutes with no
-- corresponding sent record) - not implemented; tracked as a follow-up in
-- AGENTS.md rather than added to this migration's scope.

alter table public.feedback_tickets
  add column notified_at timestamptz;

comment on column public.feedback_tickets.notified_at is
  'Claimed by feedback-notify (service role, via UPDATE ... WHERE notified_at IS NULL) before it attempts to send, and cleared back to null if that send fails (including a timed-out Resend call, see _shared/email.ts) - so it is non-null if and only if the new-ticket admin alert was actually sent, EXCEPT for the narrow window where the function''s own process is killed between the claim and the send resolving/timing out (e.g. a host crash) - see this migration''s header comment. Never in any authenticated grant, so only the function can set or clear it - this is what makes concurrent/overlapping or repeated feedback-notify calls for the same ticket send at most one email.';
