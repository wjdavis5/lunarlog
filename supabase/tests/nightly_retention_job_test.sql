-- Coverage for 20260915200000_nightly_retention_job.sql (Issue #263): the
-- nightly public.enforce_retention() purge for notification_outbox,
-- day_entries tombstones, day_entry_history (guarded -- Issue #170 has not
-- landed, no table exists yet), and resolved feedback_tickets with no
-- attachments (Coordinator review of PR #705, blocking finding 2 -- a
-- ticket that still references a Storage object is left alone, since SQL
-- cannot remove that object). Also covers blocking finding 3 (a failed
-- sub-block's failure surfaces in the returned jsonb's `errors` key,
-- absent on a healthy run). Runs as postgres (superuser) throughout --
-- none of the four tables grant authenticated any access relevant here
-- (notification_outbox has no authenticated policy at all; the others are
-- exercised for direct-row survival, not RLS), so no
-- tests.authenticate_as() call is needed.
begin;
select plan(29);

-- ---------------------------------------------------------------------------
-- Fixtures: one guardian/profile pair for notification_outbox and
-- day_entries, and one ticket owner for feedback_tickets.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('retention_owner');
select tests.create_supabase_user('retention_recipient');

insert into public.profiles (id, user_id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(900), tests.get_supabase_uid('retention_owner'), 'Retention', false, 0,
  '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Group A: notification_outbox boundary rows.
-- ---------------------------------------------------------------------------
insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, created_at, deliver_after, sent_at)
values
  (gen_random_uuid(), tests.ulid(900), tests.get_supabase_uid('retention_recipient'), 'logged',
   now() - interval '40 days', now() - interval '40 days', now() - interval '31 days'),
  (gen_random_uuid(), tests.ulid(900), tests.get_supabase_uid('retention_recipient'), 'logged',
   now() - interval '35 days', now() - interval '35 days', now() - interval '29 days'),
  (gen_random_uuid(), tests.ulid(900), tests.get_supabase_uid('retention_recipient'), 'logged',
   now() - interval '5 days', now(), null);

select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900)),
  3::bigint, 'setup: three notification_outbox rows exist before the purge'
);

-- ---------------------------------------------------------------------------
-- Group B: day_entries tombstone boundary rows, plus one live (never
-- tombstoned) row that must never be purged regardless of age.
-- ---------------------------------------------------------------------------
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at, deleted_at)
values
  (tests.ulid(910), tests.get_supabase_uid('retention_owner'), tests.ulid(900), '2025-01-01', 'UTC', 'none',
   now() - interval '181 days', now() - interval '181 days'),
  (tests.ulid(911), tests.get_supabase_uid('retention_owner'), tests.ulid(900), '2025-01-02', 'UTC', 'none',
   now() - interval '179 days', now() - interval '179 days'),
  (tests.ulid(912), tests.get_supabase_uid('retention_owner'), tests.ulid(900), '2020-01-01', 'UTC', 'medium',
   now() - interval '2000 days', null);

select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(900)),
  3::bigint, 'setup: three day_entries rows exist before the purge'
);

-- ---------------------------------------------------------------------------
-- Group C: feedback_tickets boundary rows -- one resolved-and-old with no
-- attachments (with a reply, to prove the cascade), one resolved-but-fresh,
-- one old-but-open, and one resolved-and-old WITH an attachment (Coordinator
-- review of PR #705, blocking finding 2 -- must be kept regardless of age,
-- since SQL cannot remove the Storage object it still references).
-- ---------------------------------------------------------------------------
insert into public.feedback_tickets
  (id, user_id, reply_email, category, message, status, created_at, updated_at, attachment_paths)
values
  -- Ticket 1's status/updated_at below are placeholders, overwritten by the
  -- explicit UPDATE after the reply insert (see the comment there for why).
  ('90000000-0000-0000-0000-000000000001', tests.get_supabase_uid('retention_owner'), 'a@example.test', 'bug',
   'an old resolved ticket', 'new', now() - interval '400 days', now() - interval '400 days', '{}'),
  ('90000000-0000-0000-0000-000000000002', tests.get_supabase_uid('retention_owner'), 'a@example.test', 'bug',
   'a recently resolved ticket', 'resolved', now() - interval '400 days', now() - interval '364 days', '{}'),
  ('90000000-0000-0000-0000-000000000003', tests.get_supabase_uid('retention_owner'), 'a@example.test', 'support',
   'a still-open old ticket', 'new', now() - interval '400 days', now() - interval '400 days', '{}'),
  ('90000000-0000-0000-0000-000000000004', tests.get_supabase_uid('retention_owner'), 'a@example.test', 'bug',
   'an old resolved ticket with a screenshot', 'resolved', now() - interval '400 days', now() - interval '366 days',
   array[tests.get_supabase_uid('retention_owner')::text || '/t4/shot.png']);

insert into public.feedback_replies (id, ticket_id, author_type, message, created_at)
values (gen_random_uuid(), '90000000-0000-0000-0000-000000000001', 'admin', 'we looked into it',
  now() - interval '370 days');

-- feedback_replies_touch_ticket (R18) just moved ticket 1 to status =
-- 'replied' with updated_at = clock_timestamp() as a side effect of the
-- insert above -- realistic (an admin reply moves a ticket to replied), but
-- this fixture needs ticket 1 old-and-resolved for the purge test, i.e. the
-- state after that reply thread was later closed out. Set it explicitly,
-- after the reply exists, so the reply-thread-cascade assertion below is
-- exercised against a ticket that genuinely has a reply.
update public.feedback_tickets
   set status = 'resolved', updated_at = now() - interval '366 days'
 where id = '90000000-0000-0000-0000-000000000001';

select is(
  (select count(*) from public.feedback_tickets where user_id = tests.get_supabase_uid('retention_owner')),
  4::bigint, 'setup: four feedback_tickets rows exist before the purge'
);
select is(
  (select count(*) from public.feedback_replies where ticket_id = '90000000-0000-0000-0000-000000000001'),
  1::bigint, 'setup: the old resolved ticket has one reply before the purge'
);

-- ---------------------------------------------------------------------------
-- Structural guard: day_entry_history does not exist yet (Issue #170 not
-- landed) -- proves the guard branch, rather than the "table exists" branch,
-- is what this run actually exercises below.
-- ---------------------------------------------------------------------------
select ok(to_regclass('public.day_entry_history') is null,
  'Issue #170''s day_entry_history table does not exist yet -- the guard branch is what this run exercises');

-- ---------------------------------------------------------------------------
-- Run 1: the purge itself. Captured in a temp table so the "no errors key"
-- assertion below can inspect the same call's result without re-running
-- the purge (which would otherwise find nothing left to purge the second
-- time and prove nothing new).
-- ---------------------------------------------------------------------------
create temp table run1_result (v jsonb);
insert into run1_result select public.enforce_retention();

select is(
  (select v from run1_result),
  jsonb_build_object(
    'notification_outbox', 1,
    'day_entries_tombstones', 1,
    'day_entry_history', 0,
    'feedback_tickets', 1,
    'day_entry_merge_events', 0
  ),
  'enforce_retention purges exactly the expired row in each of the four categories'
);
select ok(
  not ((select v from run1_result) ? 'errors'),
  'a healthy run''s result carries no errors key (Coordinator review, blocking finding 3)'
);

-- notification_outbox: expired sent_at is gone; within-window sent_at and
-- the never-sent row both survive.
select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900) and sent_at < now() - interval '30 days'),
  0::bigint, 'the 31-day-old sent notification_outbox row is purged'
);
select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900)
    and sent_at is not null and sent_at >= now() - interval '30 days'),
  1::bigint, 'the 29-day-old sent notification_outbox row is kept (still inside the 30-day window)'
);
select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900) and sent_at is null),
  1::bigint, 'the never-sent notification_outbox row is kept regardless of created_at age'
);

-- day_entries: the 181-day tombstone is hard-deleted; the 179-day tombstone
-- (still needed by a client that has not reconciled since) and the live row
-- both survive.
select is(
  (select count(*) from public.day_entries where id = tests.ulid(910)),
  0::bigint, 'the 181-day-old tombstone is purged (past the sync-safe window)'
);
select is(
  (select count(*) from public.day_entries where id = tests.ulid(911) and deleted_at is not null),
  1::bigint, 'the 179-day-old tombstone is kept -- still inside the sync-safe window a slow client might need'
);
select is(
  (select count(*) from public.day_entries where id = tests.ulid(912) and deleted_at is null),
  1::bigint, 'a live (never-tombstoned) row is kept regardless of how old its local_date/updated_at is'
);

-- feedback_tickets: the old resolved ticket (and its reply, via cascade) is
-- gone; the fresher resolved ticket and the old-but-open ticket both survive.
select is(
  (select count(*) from public.feedback_tickets where id = '90000000-0000-0000-0000-000000000001'),
  0::bigint, 'the year-old resolved feedback ticket is purged'
);
select is(
  (select count(*) from public.feedback_replies where ticket_id = '90000000-0000-0000-0000-000000000001'),
  0::bigint, 'its reply thread is gone too, via feedback_replies'' cascade'
);
select is(
  (select count(*) from public.feedback_tickets where id = '90000000-0000-0000-0000-000000000002'),
  1::bigint, 'a resolved ticket updated 364 days ago is kept (still inside the 1-year window)'
);
select is(
  (select count(*) from public.feedback_tickets where id = '90000000-0000-0000-0000-000000000003'),
  1::bigint, 'a 400-day-old but still-open (status new) ticket is never purged regardless of age'
);
select is(
  (select count(*) from public.feedback_tickets where id = '90000000-0000-0000-0000-000000000004'),
  1::bigint,
  'a resolved, year-old ticket that still has an attachment is kept -- SQL cannot remove its Storage object (Coordinator review, blocking finding 2)'
);

-- ---------------------------------------------------------------------------
-- Run 2: idempotency -- nothing left in scope for any of the four tables.
-- ---------------------------------------------------------------------------
select is(
  public.enforce_retention(),
  jsonb_build_object(
    'notification_outbox', 0,
    'day_entries_tombstones', 0,
    'day_entry_history', 0,
    'feedback_tickets', 0,
    'day_entry_merge_events', 0
  ),
  'a second run is a clean no-op -- enforce_retention is idempotent'
);

-- ---------------------------------------------------------------------------
-- Batch-bound: 1,200 expired notification_outbox rows (more than two
-- 500-row batches) are still fully drained by a single call, proving the
-- loop actually iterates rather than stopping after the first batch.
-- ---------------------------------------------------------------------------
insert into public.notification_outbox (id, profile_id, recipient_user_id, kind, created_at, deliver_after, sent_at)
select gen_random_uuid(), tests.ulid(900), tests.get_supabase_uid('retention_recipient'), 'logged',
       now() - interval '40 days', now() - interval '40 days', now() - interval '31 days'
  from generate_series(1, 1200);

select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900) and sent_at < now() - interval '30 days'),
  1200::bigint, 'setup: 1,200 expired notification_outbox rows exist before the batched purge'
);

select is(
  (public.enforce_retention() ->> 'notification_outbox')::bigint,
  1200::bigint, 'a single run drains all 1,200 expired rows across multiple 500-row batches'
);
select is(
  (select count(*) from public.notification_outbox where profile_id = tests.ulid(900) and sent_at < now() - interval '30 days'),
  0::bigint, 'no expired notification_outbox rows remain after the batched drain'
);

-- ---------------------------------------------------------------------------
-- Structural guards: SECURITY DEFINER, executable only by cron/service_role
-- (never public/anon/authenticated), and the supporting indexes exist.
-- ---------------------------------------------------------------------------
select is(
  (select prosecdef from pg_proc where proname = 'enforce_retention' and pronamespace = 'public'::regnamespace),
  true, 'enforce_retention is security definer'
);
select is(
  has_function_privilege('authenticated', 'public.enforce_retention()', 'execute'),
  false, 'authenticated has no execute grant on enforce_retention'
);
select is(
  has_function_privilege('anon', 'public.enforce_retention()', 'execute'),
  false, 'anon has no execute grant on enforce_retention'
);

select is(
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'notification_outbox_sent_at_idx'),
  1::bigint, 'notification_outbox_sent_at_idx exists'
);
select is(
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'day_entries_deleted_at_idx'),
  1::bigint, 'day_entries_deleted_at_idx exists'
);
select is(
  (select count(*) from pg_indexes where schemaname = 'public' and indexname = 'feedback_tickets_resolved_updated_at_idx'),
  1::bigint, 'feedback_tickets_resolved_updated_at_idx exists'
);

-- ---------------------------------------------------------------------------
-- Cron registration: guarded exactly like the existing two jobs, so this
-- assertion itself degrades gracefully (rather than failing db reset) on an
-- environment where pg_cron is unavailable.
-- ---------------------------------------------------------------------------
select ok(
  (not exists (select 1 from pg_available_extensions where name = 'pg_cron'))
  or exists (
    select 1 from cron.job
     where jobname = 'lunarlog-nightly-retention'
       and schedule = '30 3 * * *'
       and command = 'select public.enforce_retention();'
  ),
  'lunarlog-nightly-retention is registered with pg_cron when the extension is available'
);

select * from finish();
rollback;
