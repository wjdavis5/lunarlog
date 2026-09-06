-- Coverage for public.notification_outbox and the day_entries enqueue
-- trigger (Issue #5, Unit U2).
begin;
select plan(21);

-- Helper: inspect the outbox as service_role (bypasses RLS -- no
-- authenticated policy exists on this table at all, by design).
create function pg_temp.outbox_count(p_profile text, p_recipient uuid) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient;
$$;

create function pg_temp.outbox_kind(p_profile text, p_recipient uuid) returns text
language sql security definer set search_path = '' as $$
  select kind from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient
   order by created_at desc limit 1;
$$;

create function pg_temp.resolve_deliver_after(p_now timestamptz, p_start time, p_end time, p_zone text)
returns timestamptz
language sql security definer set search_path = '' as $$
  select public.resolve_deliver_after(p_now, p_start, p_end, p_zone);
$$;

-- ---------------------------------------------------------------------------
-- Group A (profile 401): base eligibility, writer exclusion, two guardians,
-- revocation, tombstones, and updates.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_a');
select tests.create_supabase_user('dad_a');
select tests.create_supabase_user('sitter_a');

select tests.authenticate_as('mom_a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(401), 'Alex', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(401), 'co_parent', 'Dad',
  '2222222222222222222222222222222222222222222222222222222222222222', 48
);
select tests.authenticate_as('dad_a');
select public.accept_guardian_invitation(
  '2222222222222222222222222222222222222222222222222222222222222222', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_a'), tests.ulid(401), true);

select tests.authenticate_as('mom_a');
select public.create_guardian_invitation(
  tests.ulid(401), 'caregiver', 'Sitter',
  '3333333333333333333333333333333333333333333333333333333333333333', 48
);
select tests.authenticate_as('sitter_a');
select public.accept_guardian_invitation(
  '3333333333333333333333333333333333333333333333333333333333333333', 'Sitter'
);
-- Sitter deliberately has no preference row yet.

-- Entry 1: mom logs a non-bleed day. Dad (alert_on_log) is eligible;
-- sitter (no preference row) is not.
select tests.authenticate_as('mom_a');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, tags, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(410), tests.ulid(401), '2026-09-01', 'UTC', 'none', '["cramps"]', now(),
   tests.get_supabase_uid('mom_a'), tests.get_supabase_uid('mom_a'));

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 1::bigint,
  'A guardian with alert_on_log gets exactly one outbox row when the holder inserts an entry');
select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('sitter_a')), 0::bigint,
  'A guardian with no preference row gets nothing');

-- alert_on_log false overrides even with the other flags on.
select tests.authenticate_as('dad_a');
update public.notification_preferences
   set alert_on_log = false, alert_on_cycle_start_only = true, alert_on_high_severity = true
 where user_id = tests.get_supabase_uid('dad_a') and profile_id = tests.ulid(401);

select tests.authenticate_as('mom_a');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(411), tests.ulid(401), '2026-09-02', 'UTC', 'heavy', now(),
   tests.get_supabase_uid('mom_a'), tests.get_supabase_uid('mom_a'));

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 1::bigint,
  'A guardian with alert_on_log false gets nothing even when the other flags are true');

-- Restore dad to the baseline (alert_on_log only) and give sitter the same,
-- for the writer-exclusion and two-guardian scenarios below.
select tests.authenticate_as('dad_a');
update public.notification_preferences
   set alert_on_log = true, alert_on_cycle_start_only = false, alert_on_high_severity = false
 where user_id = tests.get_supabase_uid('dad_a') and profile_id = tests.ulid(401);

select tests.authenticate_as('sitter_a');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('sitter_a'), tests.ulid(401), true);

-- Dad logs his own entry: he must not alert himself.
select tests.authenticate_as('dad_a');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(412), tests.ulid(401), '2026-09-03', 'UTC', 'light', now(),
   tests.get_supabase_uid('dad_a'), tests.get_supabase_uid('dad_a'));

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 1::bigint,
  'A guardian who is also the writer gets no row for their own write');

-- Two eligible guardians on one profile produce exactly two rows, one each.
select tests.authenticate_as('mom_a');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(413), tests.ulid(401), '2026-09-04', 'UTC', 'none', now(),
   tests.get_supabase_uid('mom_a'), tests.get_supabase_uid('mom_a'));

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 2::bigint,
  'Two eligible guardians: dad gets his row');
select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('sitter_a')), 2::bigint,
  'Two eligible guardians: sitter gets her row');

-- A revoked guardian produces no row even though their preference row
-- still says alert_on_log.
select public.revoke_guardian(tests.ulid(401), tests.get_supabase_uid('sitter_a'));
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(414), tests.ulid(401), '2026-09-05', 'UTC', 'none', now(),
   tests.get_supabase_uid('mom_a'), tests.get_supabase_uid('mom_a'));

-- U4 (revoke_guardian, R5) also purges the revoked guardian's existing
-- unsent outbox rows immediately, so sitter's count drops to zero here
-- rather than merely stopping growth.
select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('sitter_a')), 0::bigint,
  'A revoked guardian produces no row');
select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 3::bigint,
  'A still-accepted guardian keeps receiving rows');

-- A tombstoned update produces no row.
update public.day_entries set deleted_at = now() where id = tests.ulid(414);

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 3::bigint,
  'A tombstoned (deleted_at set) update produces no row');

-- Updating an existing (non-bleed, non-boundary) entry produces a row for an
-- alert_on_log guardian and no row for a cycle_start_only guardian when the
-- episode boundary did not move.
select tests.authenticate_as('dad_a');
update public.notification_preferences
   set alert_on_cycle_start_only = true
 where user_id = tests.get_supabase_uid('dad_a') and profile_id = tests.ulid(401);

select tests.authenticate_as('mom_a');
update public.day_entries set note = 'updated note' where id = tests.ulid(410);

select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('dad_a')), 3::bigint,
  'Updating a non-boundary entry produces no row for a cycle_start_only guardian');
select is(pg_temp.outbox_count(tests.ulid(401), tests.get_supabase_uid('sitter_a')), 0::bigint,
  'A revoked guardian (sitter) still gets nothing on this later update');

-- authenticated selecting notification_outbox returns zero rows even for
-- their own recipient_user_id.
select tests.authenticate_as('dad_a');
select throws_ok(
  $$select count(*) from public.notification_outbox$$,
  '42501', null,
  'authenticated has no grant at all on notification_outbox, even for their own recipient_user_id'
);

-- ---------------------------------------------------------------------------
-- Group B (profile 402): cycle-start narrowing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_b');
select tests.create_supabase_user('dad_b');

select tests.authenticate_as('mom_b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(402), 'Blair', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(402), 'co_parent', 'Dad',
  '4444444444444444444444444444444444444444444444444444444444444444', 48
);
select tests.authenticate_as('dad_b');
select public.accept_guardian_invitation(
  '4444444444444444444444444444444444444444444444444444444444444444', 'Dad'
);

select tests.authenticate_as('mom_b');
-- Establishes real prior bleed-day state before dad's preference exists;
-- harmless (no preference row -> no alert).
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(420), tests.ulid(402), '2026-09-01', 'UTC', 'medium', now());

select tests.authenticate_as('dad_b');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_cycle_start_only)
values (tests.get_supabase_uid('dad_b'), tests.ulid(402), true, true);

-- A mid-cycle spotting day (preceded by a bleeding day): nothing.
select tests.authenticate_as('mom_b');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(421), tests.ulid(402), '2026-09-02', 'UTC', 'spotting', now());

select is(pg_temp.outbox_count(tests.ulid(402), tests.get_supabase_uid('dad_b')), 0::bigint,
  'cycle_start_only: an entry preceded by a bleeding day produces nothing');

-- A day that opens a new episode (a gap since the last bleed day): one row.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(422), tests.ulid(402), '2026-09-05', 'UTC', 'heavy', now());

select is(pg_temp.outbox_count(tests.ulid(402), tests.get_supabase_uid('dad_b')), 1::bigint,
  'cycle_start_only: a day that opens a new episode produces one row with kind cycle_start');
select is(
  pg_temp.outbox_kind(tests.ulid(402), tests.get_supabase_uid('dad_b')),
  'cycle_start',
  'the cycle-start row is kind = cycle_start'
);

-- ---------------------------------------------------------------------------
-- Group C (profile 403): high-severity narrowing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_c');
select tests.create_supabase_user('dad_c');

select tests.authenticate_as('mom_c');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(403), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(403), 'co_parent', 'Dad',
  '5555555555555555555555555555555555555555555555555555555555555555', 48
);
select tests.authenticate_as('dad_c');
select public.accept_guardian_invitation(
  '5555555555555555555555555555555555555555555555555555555555555555', 'Dad'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_high_severity)
values (tests.get_supabase_uid('dad_c'), tests.ulid(403), true, true);

select tests.authenticate_as('mom_c');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(430), tests.ulid(403), '2026-09-01', 'UTC', 'heavy', now());

select is(pg_temp.outbox_count(tests.ulid(403), tests.get_supabase_uid('dad_c')), 1::bigint,
  'A heavy-flow entry produces one row for a high-severity guardian');

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(431), tests.ulid(403), '2026-09-02', 'UTC', 'light', now());

select is(pg_temp.outbox_count(tests.ulid(403), tests.get_supabase_uid('dad_c')), 1::bigint,
  'A light-flow entry with no severe tag produces no additional row');

-- ---------------------------------------------------------------------------
-- Structural stop-condition guard, service_role, and pure-function coverage.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_outbox'
      and column_name in ('note', 'tags', 'flow', 'local_date')),
  0::bigint,
  'notification_outbox has no column capable of holding note, tags, flow, or local_date'
);

select is(
  pg_temp.resolve_deliver_after('2026-09-01T12:00:00Z'::timestamptz, '22:00'::time, '07:00'::time, 'UTC'),
  '2026-09-01T12:00:00Z'::timestamptz,
  'resolve_deliver_after returns p_now unchanged outside the window'
);
select is(
  pg_temp.resolve_deliver_after('2026-09-01T09:00:00Z'::timestamptz, '08:00'::time, '10:00'::time, 'UTC'),
  '2026-09-01T10:00:00Z'::timestamptz,
  'resolve_deliver_after returns the window end for a same-day window'
);
select is(
  pg_temp.resolve_deliver_after('2026-09-01T23:10:00Z'::timestamptz, '22:00'::time, '07:00'::time, 'UTC'),
  '2026-09-02T07:00:00Z'::timestamptz,
  'resolve_deliver_after returns the next morning''s end for a window that wraps midnight'
);

rollback;
