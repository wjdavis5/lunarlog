-- Coverage for public.notification_outbox and the day_entries enqueue
-- trigger (Issue #5, Unit U2).
begin;
select plan(30);

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

-- #6 (review fix): a one-day gap (Sept 6 has no entry) between Sept 5's
-- bleed day and this one still merges into the same episode per
-- lib/domain/episodes/episodes.dart's deriveEpisodes() -- probing only
-- local_date - 1 would have missed the Sept 5 bleed day and false-flagged
-- this as a new cycle_start.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(423), tests.ulid(402), '2026-09-07', 'UTC', 'medium', now());

select is(pg_temp.outbox_count(tests.ulid(402), tests.get_supabase_uid('dad_b')), 1::bigint,
  '#6: a one-day-gap bleed day merges into the prior episode -- cycle_start_only guardian gets no new row');

-- A real 3-day gap (Sept 8-9 empty) does start a new episode.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(424), tests.ulid(402), '2026-09-10', 'UTC', 'medium', now());

select is(pg_temp.outbox_count(tests.ulid(402), tests.get_supabase_uid('dad_b')), 2::bigint,
  '#6: a genuine 3-day gap still starts a new episode -- one more row');

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
-- Group D (profile 404, #7 review fix): the trigger's WHEN clause must skip
-- ownership-only updates (rehome_stray_day_entries' own shape) and no-op
-- resaves, while still firing on a genuine content edit.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_d');
select tests.create_supabase_user('dad_d');

select tests.authenticate_as('mom_d');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(404), 'Drew', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(404), 'co_parent', 'Dad',
  '7777777777777777777777777777777777777777777777777777777777777777', 48
);
select tests.authenticate_as('dad_d');
select public.accept_guardian_invitation(
  '7777777777777777777777777777777777777777777777777777777777777777', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_d'), tests.ulid(404), true);

select tests.authenticate_as('mom_d');
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, note, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(440), tests.ulid(404), '2026-09-01', 'UTC', 'none', 'original note', now(),
   tests.get_supabase_uid('mom_d'), tests.get_supabase_uid('mom_d'));

select is(pg_temp.outbox_count(tests.ulid(404), tests.get_supabase_uid('dad_d')), 1::bigint,
  '#7: baseline insert produces one row for an alert_on_log guardian');

-- An ownership-only update (rehome_stray_day_entries' own shape: user_id
-- and last_modified_by_user_id only, nothing else) must produce no row.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
update public.day_entries
   set last_modified_by_user_id = tests.get_supabase_uid('dad_d')
 where id = tests.ulid(440);

select is(pg_temp.outbox_count(tests.ulid(404), tests.get_supabase_uid('dad_d')), 1::bigint,
  '#7: an ownership-only update (attribution columns only) produces no new row');

-- A no-op resave (every tracked column identical to what is already
-- stored) must also produce no row. last_modified_by_user_id is stamped to
-- the caller (as sync_push always does) so the attribution guard trigger
-- passes; that column is deliberately not part of the WHEN clause's
-- content check.
select tests.authenticate_as('mom_d');
update public.day_entries
   set local_date = local_date, flow = flow, tags = tags, note = note,
       last_modified_by_user_id = tests.get_supabase_uid('mom_d'),
       updated_at = now()
 where id = tests.ulid(440);

select is(pg_temp.outbox_count(tests.ulid(404), tests.get_supabase_uid('dad_d')), 1::bigint,
  '#7: a no-op resave (identical local_date/flow/tags/note/deleted_at) produces no new row');

-- A genuine content edit (the note actually changes) must still notify an
-- alert_on_log guardian -- the WHEN clause narrows what counts as "an
-- entry", it does not disable the feature.
update public.day_entries set note = 'a real edit' where id = tests.ulid(440);

select is(pg_temp.outbox_count(tests.ulid(404), tests.get_supabase_uid('dad_d')), 2::bigint,
  '#7: a genuine content edit (note actually changes) still enqueues a row');

-- ---------------------------------------------------------------------------
-- Group E (profile 405, #3 review fix): an unrecognized guardian time_zone
-- must not abort the profile holder's own entry write.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_e');
select tests.create_supabase_user('dad_e');

select tests.authenticate_as('mom_e');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(405), 'Ellis', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(405), 'co_parent', 'Dad',
  '8888888888888888888888888888888888888888888888888888888888888888', 48
);
select tests.authenticate_as('dad_e');
select public.accept_guardian_invitation(
  '8888888888888888888888888888888888888888888888888888888888888888', 'Dad'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, quiet_hours_start, quiet_hours_end, time_zone)
values (
  tests.get_supabase_uid('dad_e'), tests.ulid(405), true,
  '22:00'::time, '07:00'::time, 'Not/ARealZone'
);

select tests.authenticate_as('mom_e');
select lives_ok(
  format(
    $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values (%L, %L, '2026-09-01', 'UTC', 'none', now())$$,
    tests.ulid(450), tests.ulid(405)
  ),
  '#3: an unrecognized guardian time_zone does not abort the entry write'
);

select is(pg_temp.outbox_count(tests.ulid(405), tests.get_supabase_uid('dad_e')), 1::bigint,
  '#3: the alert is still enqueued despite the invalid time_zone');

-- notification_outbox carries no authenticated grant at all (KTD1) --
-- inspecting deliver_after directly needs service_role, like every other
-- direct read of this table elsewhere in this file.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select ok(
  (select deliver_after <= now() from public.notification_outbox
    where profile_id = tests.ulid(405) and recipient_user_id = tests.get_supabase_uid('dad_e')),
  '#3: an invalid time_zone degrades to no quiet hours (deliver_after = now, not deferred)'
);

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
