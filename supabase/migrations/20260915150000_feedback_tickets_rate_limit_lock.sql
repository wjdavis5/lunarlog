-- Migration: 20260915150000_feedback_tickets_rate_limit_lock.sql
-- Issue #617, LLA-081 (P2): public.feedback_tickets_rate_limit() (R17,
-- 20260906130000_feedback_tickets.sql) counts the caller's tickets in the
-- trailing hour and rejects a 6th, but the count-then-insert is not
-- serialized against a concurrent insert from the same caller: two
-- transactions can each run the `select count(*)` before either commits its
-- own INSERT, both see e.g. 4, both pass the `>= 5` check, and both commit -
-- letting six (or more, with enough concurrency) tickets land within the
-- hour instead of five.
--
-- Fix: take a per-user, transaction-scoped advisory lock
-- (`pg_advisory_xact_lock`) before the count, matching this schema's
-- established per-user serialization idiom (Issue #14's `sync_push`, and
-- every RPC re-emitted since Issue #521 - see
-- 20260913016000_sync_push_hardening.sql's header) - including that same
-- issue's collision-resistant choice of `hashtextextended(text, 0)` (int8)
-- over `hashtext(text)` (int4, collision-prone across different uuids)
-- since this function keys on a uuid the same way sync_push does. A second
-- concurrent insert for the same user now blocks on the lock until the
-- first transaction commits (and its row becomes visible to the second
-- transaction's own count) or rolls back (releasing the lock with nothing
-- counted); a different user's own insert takes a different lock key and is
-- never blocked by this one. The lock is released automatically at
-- transaction end - no explicit unlock, and no change to the trigger's
-- signature, error code, or threshold.
--
-- Re-emitted verbatim from its 20260906130000_feedback_tickets.sql body
-- (the current, and only, definition on main) plus this one change - no
-- other migration between then and now has touched this function (grepped
-- for `feedback_tickets_rate_limit` across supabase/migrations/; only
-- 20260908121000_revoke_anon_execute_guardian_feedback_functions.sql
-- touches feedback function grants generally, and it does not re-emit this
-- one).

create or replace function public.feedback_tickets_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_recent_count integer;
begin
  -- LLA-081: serialize concurrent inserts by the same caller before the
  -- count below runs, so a second concurrent insert for this user_id
  -- cannot read the same pre-commit count as the first and both pass the
  -- `>= 5` check. Released automatically at transaction end.
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));

  select count(*) into v_recent_count
    from public.feedback_tickets
   where user_id = new.user_id
     and created_at > clock_timestamp() - interval '1 hour';

  if v_recent_count >= 5 then
    raise exception 'feedback rate limit exceeded' using errcode = '55000';
  end if;

  return new;
end;
$$;

comment on function public.feedback_tickets_rate_limit() is
  'R17: refuses a 6th feedback_tickets insert by the same caller within a trailing hour. A trigger (not a policy) so it is directly assertable with throws_ok. Issue #617, LLA-081: serialized per-user via pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0)), taken before the count, so two concurrent inserts from the same caller cannot both pass the count check against the same pre-commit state.';

revoke execute on function public.feedback_tickets_rate_limit() from public, anon, authenticated;
