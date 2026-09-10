-- Coverage for public.notification_outbox and the day_entries enqueue
-- trigger (Issue #5, Unit U2). Issue #256 added Groups F/G: the
-- intensity/severity predicate (flow OR a graded severity-bearing
-- observation) on the day_entries trigger, the new
-- enqueue_observation_high_severity_alerts() triggers on observations
-- themselves, and the legacy `intensity IS NULL` = "no severity recorded"
-- semantics.
begin;
select plan(62);

-- Issue #125 added a coalescing window to the immediate alert path: one
-- push per (recipient, profile, kind) per alert_coalesce_window() (30
-- minutes by default). This file's fixtures create several same-kind
-- events inside one transaction -- i.e. inside that window -- on purpose,
-- because its subject is per-event eligibility, not volume control.
-- Disable the window for this transaction so those assertions keep
-- meaning exactly what they meant; the window itself (and the digest
-- cadence and daily ceiling riding the same trigger) is covered by
-- supabase/tests/alert_digest_test.sql.
select set_config('app.settings.alert_coalesce_window', '0', true);

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

-- Issue #256: per-kind count -- same-transaction rows all share one
-- now(), so "latest row's kind" is not a stable probe; count by kind.
create function pg_temp.outbox_kind_count(p_profile text, p_recipient uuid, p_kind text)
returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient and kind = p_kind;
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
-- Group E (profile 405): Issue #321 follow-up superseded the original #3
-- scenario here -- notification_preferences.time_zone now carries
-- notification_preferences_time_zone_valid (the same is_valid_timezone
-- CHECK observations.tz/day_entries.tz already had --
-- 20260908210000_notification_tz_check.sql), so an unrecognized guardian
-- time_zone can no longer be stored in this column at all, and
-- resolve_deliver_after's ad hoc defence that used to degrade around one
-- has been removed (direct coverage of both:
-- notification_tz_check_test.sql). This group now proves (a) the CHECK
-- itself is what stops the write, at the row that used to slip through,
-- and (b) a guardian with a genuinely valid zone still doesn't block the
-- profile holder's entry write or the alert.
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

select throws_ok(
  format(
    $$insert into public.notification_preferences
        (user_id, profile_id, alert_on_log, quiet_hours_start, quiet_hours_end, time_zone)
      values (%L, %L, true, '22:00'::time, '07:00'::time, 'Not/ARealZone')$$,
    tests.get_supabase_uid('dad_e'), tests.ulid(405)
  ),
  '23514', null,
  'Issue #321: notification_preferences_time_zone_valid now rejects the same unrecognized zone '
  || 'this group used to have to insert unguarded to exercise resolve_deliver_after''s (now removed) '
  || 'ad hoc defence'
);

-- No quiet hours on this row (null start/end): resolve_deliver_after
-- returns p_now unconditionally regardless of real wall-clock time at test
-- run, keeping the alert-enqueued assertion below deterministic.
insert into public.notification_preferences (user_id, profile_id, alert_on_log, time_zone)
values (tests.get_supabase_uid('dad_e'), tests.ulid(405), true, 'America/New_York');

select tests.authenticate_as('mom_e');
select lives_ok(
  format(
    $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values (%L, %L, '2026-09-01', 'UTC', 'none', now())$$,
    tests.ulid(450), tests.ulid(405)
  ),
  'a guardian with a genuinely valid time_zone does not block the profile holder''s entry write'
);

select is(pg_temp.outbox_count(tests.ulid(405), tests.get_supabase_uid('dad_e')), 1::bigint,
  'the alert is still enqueued for a guardian with a valid time_zone');

-- ---------------------------------------------------------------------------
-- Structural stop-condition guard, service_role, and pure-function coverage.
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- Group F (profile 406, Issue #256): the day_entries trigger's severity
-- predicate -- the four AC cases (heavy-flow-only, high-intensity-only,
-- both, neither) plus the legacy semantics: an observations row with
-- intensity IS NULL means "no severity recorded" and never alerts, and a
-- severity-bearing category at intensity < 4 never alerts either. dad_f
-- is narrowed to alert_on_high_severity, so only high_severity events
-- ever reach him -- every count below is exactly a severity
-- classification, never a plain logged event.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_f');
select tests.create_supabase_user('dad_f');

select tests.authenticate_as('mom_f');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(406), 'Faye', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(406), 'co_parent', 'Dad',
  '6666666666666666666666666666666666666666666666666666666666666666', 48
);
select tests.authenticate_as('dad_f');
select public.accept_guardian_invitation(
  '6666666666666666666666666666666666666666666666666666666666666666', 'Dad'
);
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_high_severity)
values (tests.get_supabase_uid('dad_f'), tests.ulid(406), true, true);

select tests.authenticate_as('mom_f');

-- Neither: a light-flow day with no graded observation is not high
-- severity -- a high-severity-narrowed guardian gets nothing.
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(460), tests.ulid(406), '2026-09-01', 'UTC', 'light', now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 0::bigint,
  '#256 neither: a light-flow day with no observation produces no high-severity row');

-- High-intensity-only, day_entries arm: the day's entry was light and
-- alerted nobody; grading a pain observation at 4 on the same day makes
-- the day high severity. First the (unremarkable) light day entry -- no
-- row, nothing observed yet -- then the observation insert fans out its
-- own alert (the observations trigger), ...
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(461), tests.ulid(406), '2026-09-02', 'UTC', 'light', now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 0::bigint,
  '#256 high-intensity-only: the light day entry alone alerts nothing');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(470), tests.ulid(461), tests.ulid(406), '2026-09-02', 'UTC',
   'pain', 'cramps', 4, now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 1::bigint,
  '#256 high-intensity-only: the graded pain observation itself enqueues one alert');
select is(pg_temp.outbox_kind_count(tests.ulid(406), tests.get_supabase_uid('dad_f'), 'high_severity'),
  1::bigint, '#256 and that alert is kind high_severity');
-- ... then a content edit on the light-flow day entry re-runs the
-- day_entries trigger, whose severity predicate must now see the graded
-- observation even though flow is only light (the AC's replacement
-- predicate; the pre-#256 proxy would have skipped this day).
update public.day_entries set note = 'severe pain today' where id = tests.ulid(461);
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 2::bigint,
  '#256 high-intensity-only: a light-flow day with a graded pain observation is high severity to the day_entries trigger');

-- Heavy-flow-only (existing case, preserved): a heavy day with no
-- observations still alerts.
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(462), tests.ulid(406), '2026-09-03', 'UTC', 'heavy', now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 3::bigint,
  '#256 heavy-flow-only: a heavy day with no graded observation still alerts');

-- Both: heavy flow AND a graded pain observation on the same day alert
-- once per trigger (coalescing is disabled for this transaction).
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(463), tests.ulid(406), '2026-09-04', 'UTC', 'heavy', now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 4::bigint,
  '#256 both: the heavy flow arm alerts');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(471), tests.ulid(463), tests.ulid(406), '2026-09-04', 'UTC',
   'pain', 'migraine', 4, now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 both: the graded observation arm alerts in addition');

-- Legacy semantics: an observation with intensity IS NULL is "no severity
-- recorded" -- it never makes the day high severity (the day_entries
-- content edit below re-runs the predicate against it).
insert into public.day_entries
  (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(464), tests.ulid(406), '2026-09-05', 'UTC', 'light', now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(472), tests.ulid(464), tests.ulid(406), '2026-09-05', 'UTC',
   'pain', 'back_pain', null, now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
update public.day_entries set note = 'ungraded pain row present' where id = tests.ulid(464);
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 legacy: an intensity NULL observation means no severity recorded -- never high severity');

-- Below threshold: intensity 3 on a severity-bearing category never fires
-- (observations arm) and never re-classifies the day (day_entries arm).
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(473), tests.ulid(464), tests.ulid(406), '2026-09-05', 'UTC',
   'pain', 'headache', 3, now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 below threshold: intensity 3 on pain enqueues nothing');
update public.day_entries set note = 'mild pain today' where id = tests.ulid(464);
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 below threshold: a day whose only graded pain row is intensity 3 stays non-severe');

-- Wrong category: even intensity 5 on a non-severity-bearing category
-- ('mood') is never high severity, on either trigger.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(474), tests.ulid(464), tests.ulid(406), '2026-09-05', 'UTC',
   'mood', 'sad', 5, now(),
   tests.get_supabase_uid('mom_f'), tests.get_supabase_uid('mom_f'));
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 wrong category: intensity 5 on mood enqueues nothing');
update public.day_entries set note = 'intense mood entry present' where id = tests.ulid(464);
select is(pg_temp.outbox_count(tests.ulid(406), tests.get_supabase_uid('dad_f')), 5::bigint,
  '#256 wrong category: a day with only a non-severity intensity 5 row stays non-severe');

-- ---------------------------------------------------------------------------
-- Group G (profile 407, Issue #256): the observations-side trigger's own
-- guards -- preference ladder, writer exclusion, cadence, no-op resaves,
-- the crossing update, downgrades, tombstones, the bulk-import guard, and
-- the alert_on_cycle_start_only narrowing evaluated against the day's
-- stored cycle-start state.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_g');
select tests.create_supabase_user('dad_g');
select tests.create_supabase_user('carol_g');
select tests.create_supabase_user('ed_g');
select tests.create_supabase_user('frank_g');
select tests.create_supabase_user('hank_g');

select tests.authenticate_as('mom_g');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(407), 'Gus', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(407), 'co_parent', 'Dad',
  '6161616161616161616161616161616161616161616161616161616161616161', 48
);
select tests.authenticate_as('dad_g');
select public.accept_guardian_invitation(
  '6161616161616161616161616161616161616161616161616161616161616161', 'Dad'
);

select tests.authenticate_as('mom_g');
select public.create_guardian_invitation(
  tests.ulid(407), 'caregiver', 'Carol',
  '6262626262626262626262626262626262626262626262626262626262626262', 48
);
select tests.authenticate_as('carol_g');
select public.accept_guardian_invitation(
  '6262626262626262626262626262626262626262626262626262626262626262', 'Carol'
);

select tests.authenticate_as('mom_g');
select public.create_guardian_invitation(
  tests.ulid(407), 'caregiver', 'Ed',
  '6363636363636363636363636363636363636363636363636363636363636363', 48
);
select tests.authenticate_as('ed_g');
select public.accept_guardian_invitation(
  '6363636363636363636363636363636363636363636363636363636363636363', 'Ed'
);

select tests.authenticate_as('mom_g');
select public.create_guardian_invitation(
  tests.ulid(407), 'caregiver', 'Frank',
  '6464646464646464646464646464646464646464646464646464646464646464', 48
);
select tests.authenticate_as('frank_g');
select public.accept_guardian_invitation(
  '6464646464646464646464646464646464646464646464646464646464646464', 'Frank'
);

select tests.authenticate_as('mom_g');
select public.create_guardian_invitation(
  tests.ulid(407), 'caregiver', 'Hank',
  '6565656565656565656565656565656565656565656565656565656565656565', 48
);
select tests.authenticate_as('hank_g');
select public.accept_guardian_invitation(
  '6565656565656565656565656565656565656565656565656565656565656565', 'Hank'
);

-- dad_g: plain alert_on_log (gets every log event). carol_g: narrowed to
-- high severity. ed_g: high-severity cadence off (#125's per-kind kill
-- switch, reused by the observations trigger). frank_g: master switch
-- off. hank_g: cycle-start-only narrowing.
select tests.authenticate_as('dad_g');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad_g'), tests.ulid(407), true);
select tests.authenticate_as('carol_g');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_high_severity)
values (tests.get_supabase_uid('carol_g'), tests.ulid(407), true, true);
select tests.authenticate_as('ed_g');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, high_severity_cadence)
values (tests.get_supabase_uid('ed_g'), tests.ulid(407), true, 'off');
select tests.authenticate_as('frank_g');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_high_severity)
values (tests.get_supabase_uid('frank_g'), tests.ulid(407), false, true);
select tests.authenticate_as('hank_g');
insert into public.notification_preferences
  (user_id, profile_id, alert_on_log, alert_on_cycle_start_only)
values (tests.get_supabase_uid('hank_g'), tests.ulid(407), true, true);

select tests.authenticate_as('mom_g');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(480), tests.ulid(407), '2026-09-01', 'UTC', 'none', now());

-- G1: mom grades a pain observation at 4. dad_g (alert_on_log) and
-- carol_g (high-severity narrowing) are alerted; ed_g's high_severity
-- cadence is off; frank_g's master switch is off.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(490), tests.ulid(480), tests.ulid(407), '2026-09-01', 'UTC',
   'pain', 'cramps', 4, now(),
   tests.get_supabase_uid('mom_g'), tests.get_supabase_uid('mom_g'));

-- The plain day-entry insert above also legitimately produced one
-- 'logged' row for this un-narrowed guardian (Group A's base rule); the
-- graded observation must add exactly one high_severity row on top of it.
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('dad_g'), 'logged'),
  1::bigint, '#256 observation trigger: the day-entry insert still logs one plain logged row');
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('dad_g'), 'high_severity'),
  1::bigint, '#256 observation trigger: an alert_on_log guardian is alerted with kind high_severity');
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 1::bigint,
  '#256 observation trigger: a high-severity-narrowed guardian is alerted');
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('ed_g'), 'high_severity'),
  0::bigint,
  '#256 observation trigger: high_severity_cadence off (#125) receives no high_severity row');
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('frank_g')), 0::bigint,
  '#256 observation trigger: alert_on_log false (master switch) receives nothing');

-- G2: writer exclusion -- dad's own severe observation never pages
-- himself, but still pages carol.
select tests.authenticate_as('dad_g');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(491), tests.ulid(480), tests.ulid(407), '2026-09-01', 'UTC',
   'pain', 'migraine', 5, now(),
   tests.get_supabase_uid('dad_g'), tests.get_supabase_uid('dad_g'));
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('dad_g'), 'high_severity'),
  1::bigint, '#256 observation trigger: the writer is never alerted by their own write');
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 2::bigint,
  '#256 observation trigger: a second severe observation still alerts the other guardian');

-- G3: a no-op resave (every payload column identical, only updated_at and
-- attribution stamped -- the sync engine's re-save shape) fires nothing
-- (#7's rationale, observations side).
select tests.authenticate_as('mom_g');
update public.observations
   set intensity = 4, code = 'cramps', category = 'pain', local_date = local_date,
       value_num = value_num, value_text = value_text, unit = unit,
       excluded = excluded, observed_at = observed_at,
       last_modified_by_user_id = tests.get_supabase_uid('mom_g'),
       updated_at = now()
 where id = tests.ulid(490);
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 2::bigint,
  '#256 observation trigger: a no-op resave produces no new row');

-- G4: crossing deeper (4 -> 5) is a new, more severe event.
update public.observations set intensity = 5, last_modified_by_user_id = tests.get_supabase_uid('mom_g'),
  updated_at = now() where id = tests.ulid(490);
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('dad_g'), 'high_severity'),
  2::bigint, '#256 observation trigger: an intensity increase is a new alert');
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 3::bigint,
  '#256 observation trigger: an intensity increase alerts the narrowed guardian too');

-- G5: a downgrade out of severity (5 -> 2) fires nothing -- the event is
-- "severe pain logged", never "severity changed".
update public.observations set intensity = 2, last_modified_by_user_id = tests.get_supabase_uid('mom_g'),
  updated_at = now() where id = tests.ulid(490);
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 3::bigint,
  '#256 observation trigger: dropping below the threshold enqueues nothing');

-- G6: a tombstone (payload cleared per observations_tombstone_payload_check)
-- fires nothing.
update public.observations
   set deleted_at = now(), category = null, code = null, intensity = null,
       value_num = null, value_text = null, unit = null, excluded = false,
       source_id = null, raw = null, observed_at = null,
       last_modified_by_user_id = tests.get_supabase_uid('mom_g'),
       updated_at = now()
 where id = tests.ulid(490);
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 3::bigint,
  '#256 observation trigger: a tombstoned write enqueues nothing');

-- G7: the #167 bulk-import guard is shared -- no outbox rows while
-- lunarlog.bulk_import = 'on'.
select set_config('lunarlog.bulk_import', 'on', true);
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(492), tests.ulid(480), tests.ulid(407), '2026-09-01', 'UTC',
   'pain', 'back_pain', 5, now(),
   tests.get_supabase_uid('mom_g'), tests.get_supabase_uid('mom_g'));
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('carol_g')), 3::bigint,
  '#256 observation trigger: a bulk-import write (lunarlog.bulk_import = on) enqueues nothing');
select set_config('lunarlog.bulk_import', '', true);

-- G8: the alert_on_cycle_start_only narrowing, evaluated against the
-- day's stored day_entries cycle-start state. Sept 1 (flow none) is not a
-- cycle start: hank's severe-pain day so far produced nothing for him.
select is(pg_temp.outbox_count(tests.ulid(407), tests.get_supabase_uid('hank_g')), 0::bigint,
  '#256 cycle_start_only: a severe observation on a non-cycle-start day produces nothing');

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(481), tests.ulid(407), '2026-09-10', 'UTC', 'heavy', now());
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('hank_g'), 'cycle_start'),
  1::bigint, '#256 cycle_start_only: the day_entries trigger still delivers the cycle start itself');

-- ... and a severe pain observation on that same cycle-start day passes
-- hank's narrowing (it is a cycle-start day), enqueuing its own
-- high_severity row on top.
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, code, intensity,
   updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(493), tests.ulid(481), tests.ulid(407), '2026-09-10', 'UTC',
   'pain', 'nausea', 4, now(),
   tests.get_supabase_uid('mom_g'), tests.get_supabase_uid('mom_g'));
select is(pg_temp.outbox_kind_count(tests.ulid(407), tests.get_supabase_uid('hank_g'), 'high_severity'),
  1::bigint,
  '#256 cycle_start_only: a severe observation on a cycle-start day passes the narrowing');

-- Structural guards: the new trigger function is security definer, never
-- executable by authenticated, and both of its triggers exist.
select is(
  (select prosecdef from pg_proc
    where proname = 'enqueue_observation_high_severity_alerts'
      and pronamespace = 'public'::regnamespace),
  true,
  '#256 enqueue_observation_high_severity_alerts is security definer'
);
select is(
  has_function_privilege('authenticated', 'public.enqueue_observation_high_severity_alerts()', 'execute'),
  false,
  '#256 authenticated has no execute grant on enqueue_observation_high_severity_alerts'
);
select is(
  (select count(*) from pg_trigger
    where tgrelid = 'public.observations'::regclass
      and tgname in ('observations_after_insert_high_severity_alert',
                     'observations_after_update_high_severity_alert')
      and not tgisinternal),
  2::bigint,
  '#256 both high-severity alert triggers exist on observations'
);

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
