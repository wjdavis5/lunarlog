-- Coverage for Issue #617, LLA-081 (P2): public.feedback_tickets_rate_limit()
-- (R17) counted the caller's recent tickets and rejected a 6th, but the
-- count-then-insert was not serialized against a concurrent insert from the
-- same caller - two transactions could each run the count before either
-- committed, both see e.g. 4, both pass the `>= 5` check, and both commit.
--
-- True concurrency (two sessions racing) cannot be reproduced inside one
-- pgTAP transaction, so this file proves the fix structurally (mirroring
-- guardian_role_authority_lock_test.sql, Issue #618/LLA-054): the
-- function's source is inspected (via pg_get_functiondef, which returns a
-- plpgsql function's body verbatim from pg_proc.prosrc, so exact substring
-- positions are meaningful) to confirm a per-user pg_advisory_xact_lock is
-- taken BEFORE the count query it must serialize - not merely present
-- somewhere in the body. Every structural assertion in this file is written
-- to FAIL against the pre-fix body (verified by reverting this migration
-- locally and re-running this file).
--
-- Also exercises the full happy path, the still-enforced rate limit, and
-- per-user independence end to end, to prove the locking rewrite didn't
-- change observable behavior - feedback_rls_test.sql already covers the
-- rate-limit threshold and status-machine matrix exhaustively, so this file
-- keeps its own behavioral coverage minimal and focused on the lock.
begin;
select plan(6);

create function pg_temp.body(sig text) returns text language sql as $$
  select pg_get_functiondef(sig::regprocedure);
$$;

-- ---------------------------------------------------------------------------
-- 1-3. Structural proof: a per-user pg_advisory_xact_lock precedes the
-- count query, uses the collision-resistant hashtextextended (int8) form
-- this schema standardized on since Issue #521 (not hashtext/int4, which
-- can collide across different uuids), and is keyed on new.user_id (the
-- caller whose rate the count is about) rather than some unrelated value.
-- ---------------------------------------------------------------------------
select ok(
  position('pg_advisory_xact_lock' in pg_temp.body('public.feedback_tickets_rate_limit()')) > 0
  and position('pg_advisory_xact_lock' in pg_temp.body('public.feedback_tickets_rate_limit()'))
    < position('select count(*)' in pg_temp.body('public.feedback_tickets_rate_limit()')),
  'LLA-081: feedback_tickets_rate_limit locks per-user (pg_advisory_xact_lock) '
    'before its count query, not only via the trigger''s implicit row lock'
);

select ok(
  position('hashtextextended' in pg_temp.body('public.feedback_tickets_rate_limit()')) > 0,
  'LLA-081: the lock key uses hashtextextended (int8, collision-resistant '
    'across different uuids), matching this schema''s Issue #521 convention '
    '- not the collision-prone hashtext (int4)'
);

select ok(
  position('new.user_id' in
    substring(pg_temp.body('public.feedback_tickets_rate_limit()')
      from position('pg_advisory_xact_lock' in pg_temp.body('public.feedback_tickets_rate_limit()'))
      for 60)) > 0,
  'LLA-081: the lock is keyed on new.user_id - the caller the count is about'
);

-- ---------------------------------------------------------------------------
-- Setup: two callers.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('fb_lock_a');
select tests.create_supabase_user('fb_lock_b');

-- ---------------------------------------------------------------------------
-- 4. Happy path still works end to end after the locking rewrite.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_lock_a');
insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('fb_lock_a'), 'a@example.com', 'bug', 'lock test ticket 1');

select is(
  (select count(*) from public.feedback_tickets where user_id = tests.get_supabase_uid('fb_lock_a')),
  1::bigint,
  'LLA-081: a single insert still lands normally after the locking rewrite'
);

-- ---------------------------------------------------------------------------
-- 5. The rate limit itself still trips at the 6th ticket within the hour -
-- proving the lock's own acquisition and release didn't change the
-- threshold or error code (feedback_rls_test.sql covers this exhaustively
-- for a fresh user too; this is the locked-function's own regression check).
-- ---------------------------------------------------------------------------
insert into public.feedback_tickets (user_id, reply_email, category, message)
values
  (tests.get_supabase_uid('fb_lock_a'), 'a@example.com', 'bug', 'lock test ticket 2'),
  (tests.get_supabase_uid('fb_lock_a'), 'a@example.com', 'bug', 'lock test ticket 3'),
  (tests.get_supabase_uid('fb_lock_a'), 'a@example.com', 'bug', 'lock test ticket 4'),
  (tests.get_supabase_uid('fb_lock_a'), 'a@example.com', 'bug', 'lock test ticket 5');

select throws_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message)
    values (auth.uid(), 'a@example.com', 'bug', 'lock test ticket 6')$$,
  '55000', 'feedback rate limit exceeded',
  'LLA-081: the rate limit still refuses a 6th ticket within the trailing hour'
);

-- ---------------------------------------------------------------------------
-- 6. A different caller's own lock key is independent: fb_lock_b is
-- unaffected by fb_lock_a already holding five tickets (and having just
-- taken/released its own advisory lock five times over).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_lock_b');
select lives_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message)
    values (auth.uid(), 'b@example.com', 'bug', 'fb_lock_b is unaffected by fb_lock_a''s lock/count')$$,
  'LLA-081: a different caller''s own per-user lock key does not serialize '
    'against, or get rate-limited by, another caller''s tickets'
);

select * from finish();
rollback;
