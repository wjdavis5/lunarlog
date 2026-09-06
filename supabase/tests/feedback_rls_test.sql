-- RLS, constraint, and trigger tests for feedback_tickets / feedback_replies
-- (Issue #6, Unit U1).
begin;
select plan(24);

-- ---------------------------------------------------------------------------
-- Setup users
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('fb_a');
select tests.create_supabase_user('fb_b');

-- ---------------------------------------------------------------------------
-- 1. RLS enabled and forced
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public');
select tests.rls_forced('public', 'feedback_tickets');
select tests.rls_forced('public', 'feedback_replies');

-- ---------------------------------------------------------------------------
-- 2. Happy path: A inserts a valid ticket ("the bug ticket", referenced by
--    its unique message text throughout this file rather than a captured
--    id, matching the by-content scoping used elsewhere in this suite).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_a');

insert into public.feedback_tickets (user_id, reply_email, category, message, device_info)
values (
  tests.get_supabase_uid('fb_a'),
  'a@example.com',
  'bug',
  'the bug ticket: crashed opening the calendar',
  '{"os": "iOS", "os_version": "18.0", "model": "iPhone15,2", "app_version": "1.0.0", "build_number": "42", "locale": "en_US", "breadcrumbs": ["nav:overview", "nav:calendar"]}'::jsonb
);

select is(
  (select status from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar'),
  'new',
  'A''s freshly inserted ticket is visible to A with status new'
);

-- ---------------------------------------------------------------------------
-- 3. Covers AE1: B cannot see A's tickets
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_b');

select is(
  (select count(*) from public.feedback_tickets where user_id = tests.get_supabase_uid('fb_a')),
  0::bigint,
  'AE1: B selects feedback_tickets and sees none of A''s rows'
);

-- ---------------------------------------------------------------------------
-- 4. Covers AE2: B cannot insert a ticket claiming A's user_id
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.feedback_tickets (user_id, reply_email, category, message)
      values (%L, 'b@example.com', 'bug', 'forged ticket')$$,
    tests.get_supabase_uid('fb_a')
  ),
  '42501', null, 'AE2: B cannot insert a ticket with user_id set to A''s uid'
);

-- ---------------------------------------------------------------------------
-- 5. Covers AE3: B cannot insert a reply on A's ticket
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.feedback_replies (ticket_id, author_type, message)
      values ((select id from public.feedback_tickets where message = %L), 'user', 'not my ticket')$$,
    'the bug ticket: crashed opening the calendar'
  ),
  '42501', null, 'AE3: B cannot insert a reply on A''s ticket'
);

-- ---------------------------------------------------------------------------
-- 6. Covers AE4: device_info allowlist
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_a');

select throws_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message, device_info)
    values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'bug', 'has a stray key',
            '{"os": "iOS", "note": "cramps started today"}'::jsonb)$$,
  '23514', null, 'AE4: device_info with a non-allowlisted key (note) is rejected'
);

-- Edge case: only allowlisted keys, breadcrumbs as a JSON array, is accepted.
insert into public.feedback_tickets (user_id, reply_email, category, message, device_info)
values (
  tests.get_supabase_uid('fb_a'),
  'a@example.com',
  'support',
  'how do I export my data',
  '{"os": "Android", "breadcrumbs": []}'::jsonb
);

select is(
  (select count(*) from public.feedback_tickets
    where user_id = tests.get_supabase_uid('fb_a') and category = 'support'),
  1::bigint,
  'device_info with only allowlisted keys plus an empty breadcrumbs array is accepted'
);

-- ---------------------------------------------------------------------------
-- 7. Error paths: message length, category
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message)
    values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'bug', '')$$,
  '23514', null, 'A zero-length message is rejected by the named length check'
);

select throws_ok(
  format(
    $$insert into public.feedback_tickets (user_id, reply_email, category, message)
      values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'bug', %L)$$,
    repeat('x', 4001)
  ),
  '23514', null, 'A 4001-character message is rejected by the named length check'
);

select throws_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message)
    values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'praise', 'great app')$$,
  '23514', null, 'An unknown category (praise) is rejected by the category check'
);

-- ---------------------------------------------------------------------------
-- 8. Error path: status is not client-writable
-- ---------------------------------------------------------------------------
-- Unlike an RLS policy rejection (which filters to 0 rows), a column not in
-- the UPDATE grant list is a privilege check Postgres enforces at rewrite
-- time: it raises 42501 immediately rather than silently updating 0 rows.
select throws_ok(
  $$update public.feedback_tickets set status = 'resolved'
    where message = 'the bug ticket: crashed opening the calendar'$$,
  '42501', null, 'A cannot set status directly (column not granted)'
);

-- ---------------------------------------------------------------------------
-- 8b. PR #105 review: feedback-notify's replay guard (notified_at) must be
--     as unwritable to authenticated as status is, or a caller could reset
--     it and re-trigger the admin alert through the client itself rather
--     than the function.
-- ---------------------------------------------------------------------------
select is(
  (select notified_at from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar'),
  null,
  'notified_at defaults to null on insert'
);

select throws_ok(
  $$update public.feedback_tickets set notified_at = now()
    where message = 'the bug ticket: crashed opening the calendar'$$,
  '42501', null, 'A cannot set notified_at directly (column not granted) - only feedback-notify (service role) can'
);

-- ---------------------------------------------------------------------------
-- 8c. PR #105 review round 7/8: feedback_tickets_update had no coverage at
--     all - neither the positive path (can the owner actually use the
--     column grant U5 depends on?) nor the negative one (can a *different*
--     owner reach it?). Both directions are covered here.
--
--     The positive case matters because Postgres AND-combines the USING
--     clauses of every applicable policy for UPDATE/DELETE: since
--     `feedback_tickets_select` already restricts row visibility to
--     `user_id = auth.uid()`, deleting `feedback_tickets_update`'s own
--     USING/WITH CHECK entirely (or the whole policy) does not by itself
--     open a cross-account write - it silently breaks the *owner's own*
--     legitimate attachment upload instead (empirically verified while
--     writing this test: with the update policy's USING loosened to
--     `true`, a same-owner update still succeeds, so a naive "loosen it and
--     see if a stranger can write" mutant check alone would have missed
--     that a from-scratch policy could be equally broken in the *other*
--     direction). A positive assertion is what catches that failure mode.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_a');

update public.feedback_tickets
   set attachment_paths = array['a-own-path.png']
 where message = 'the bug ticket: crashed opening the calendar';

select is(
  (select attachment_paths from public.feedback_tickets
    where message = 'the bug ticket: crashed opening the calendar'),
  array['a-own-path.png'],
  'A can update attachment_paths on A''s own ticket - the granted column '
  'U5''s post-submit attachment upload depends on'
);

-- ---------------------------------------------------------------------------
-- 8d. The negative direction: even with the row's own owner able to write
--     it, a *different* authenticated caller must not be able to touch it.
--     Deleting the USING clause here would not raise an error the way the
--     column-grant tests (8, 8b) do (RLS filters rows rather than
--     throwing), so this needs a row-count assertion instead of throws_ok.
--
--     Note for future maintainers: because of the AND-with-SELECT-policy
--     behavior described above, this specific assertion is not, on its
--     own, independently mutation-proof against a *lone* change to this
--     policy's own USING/WITH CHECK clause - `feedback_tickets_select`'s
--     own ownership check (exercised by AE1 in section 3 above) provides
--     the same cross-account guarantee as a structural backstop. Real
--     exploitation would require loosening both policies at once. This
--     test still documents and pins the intended, defense-in-depth
--     behavior of the policy as written.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('fb_b');

update public.feedback_tickets
   set attachment_paths = array['b-planted-path']
 where message = 'the bug ticket: crashed opening the calendar';

select is(
  (select count(*) from public.feedback_tickets
    where message = 'the bug ticket: crashed opening the calendar'
      and attachment_paths = array['b-planted-path']),
  0::bigint,
  'B cannot update A''s ticket even on a granted column (attachment_paths) - '
  'the update policy''s USING clause blocks the row match, not just the '
  'column grant'
);

select tests.authenticate_as('fb_a');

-- ---------------------------------------------------------------------------
-- 9. Error path: a user cannot insert an admin-authored reply
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.feedback_replies (ticket_id, author_type, message)
      values ((select id from public.feedback_tickets where message = %L), 'admin', 'pretending to be support')$$,
    'the bug ticket: crashed opening the calendar'
  ),
  '42501', null, 'A cannot insert a reply with author_type = admin'
);

-- ---------------------------------------------------------------------------
-- 10. Covers AE5: rate limit (5 tickets/hour)
-- ---------------------------------------------------------------------------
insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'other', 'rate limit filler 1');
insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'other', 'rate limit filler 2');
insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'other', 'rate limit filler 3');

-- A now has 5 tickets total this hour (the bug ticket + support + 3
-- fillers); the 6th must be rejected.
select is(
  (select count(*) from public.feedback_tickets where user_id = tests.get_supabase_uid('fb_a')),
  5::bigint,
  'A has exactly 5 tickets before the rate limit trips'
);

select throws_ok(
  $$insert into public.feedback_tickets (user_id, reply_email, category, message)
    values (tests.get_supabase_uid('fb_a'), 'a@example.com', 'other', 'one too many')$$,
  '55000', null, 'AE5: a 6th ticket within the hour is rejected by the rate-limit trigger'
);

select is(
  (select count(*) from public.feedback_tickets where user_id = tests.get_supabase_uid('fb_a')),
  5::bigint,
  'AE5: the rate-limited insert did not write a 6th row'
);

-- ---------------------------------------------------------------------------
-- 11. Covers AE7: reply-driven status transitions
-- ---------------------------------------------------------------------------
select tests.clear_authentication();

insert into public.feedback_replies (ticket_id, author_type, message)
select id, 'admin', 'Thanks for the report, looking into it.'
  from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar';

select is(
  (select status from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar'),
  'replied',
  'AE7: an admin reply moves the ticket to replied'
);

select tests.authenticate_as('fb_a');

insert into public.feedback_replies (ticket_id, author_type, message)
select id, 'user', 'Still happening on iOS 18.1.'
  from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar';

select is(
  (select status from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar'),
  'triage',
  'A user reply on a replied ticket moves it back to triage'
);

-- ---------------------------------------------------------------------------
-- 12. Edge case: deleting a ticket cascades its replies
-- ---------------------------------------------------------------------------
select tests.clear_authentication();

delete from public.feedback_tickets where message = 'the bug ticket: crashed opening the calendar';

select is(
  (select count(*) from public.feedback_replies fr
    where not exists (select 1 from public.feedback_tickets ft where ft.id = fr.ticket_id)),
  0::bigint,
  'Deleting a ticket cascades its replies (no orphaned reply rows remain)'
);

select * from finish();
rollback;
