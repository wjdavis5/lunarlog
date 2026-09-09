-- Coverage for 20260908140000_tombstone_flow_clear.sql (issue #224, P1):
-- a tombstoned day_entries row must always carry flow = 'none', matching
-- the schema comment ("tombstones keep the id but carry no payload",
-- 20260903014208_initial_sync_schema.sql) and storage.dart's own doc
-- comment. Three sync_push branches can produce a tombstone, and all three
-- are exercised here: the direct client soft-delete push, the same-date
-- resolver's "incoming wins" branch (which tombstones the *other*, already
-- stored row), and the resolver's "incoming loses" branch (which tombstones
-- the *incoming* row itself). Also covers the enqueue_caregiver_alerts
-- guard (a tombstone must never enqueue an alert, even under an armed
-- pipeline), the one-off backfill statement (simulate-then-reconcile,
-- mirroring tags_element_length_check_test.sql), and the structural CHECK
-- constraint that backstops all of the above independent of sync_push.
begin;
select plan(18);

-- Issue #125 added a coalescing window to the immediate alert path (30
-- minutes by default); this file's fixtures create several same-kind events
-- inside one transaction on purpose, so its subject (per-event eligibility)
-- stays meaningful rather than accidentally exercising the window instead.
-- Same disabling as notification_outbox_test.sql / alert_digest_test.sql.
select set_config('app.settings.alert_coalesce_window', '0', true);

create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t1', '2026-09-01T10:00:00Z'),
  ('t2', '2026-09-01T11:00:00Z'),
  ('t3', '2026-09-01T12:00:00Z');
grant select on table ts to authenticated;

create function pg_temp.ts_txt(k text) returns text language sql as
  $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') from ts where ts.k = $1 $$;

-- Helper: inspect the outbox as service_role (no authenticated policy
-- exists on this table at all, by design - same helper shape as
-- notification_outbox_test.sql / tags_element_length_check_test.sql).
create function pg_temp.outbox_count(p_profile text, p_recipient uuid) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient;
$$;

-- ---------------------------------------------------------------------------
-- Fixture: Mom owns a minor profile; Dad is an accepted co_parent with
-- alert_on_log armed, so every assertion below that a tombstone enqueues no
-- *additional* alert is meaningful rather than vacuous (the pipeline is
-- live throughout). Mom has no preference row, so she is never eligible -
-- outbox_count(dad224) is therefore the only meaningful counter in this
-- file; every count below is cumulative across the whole file, in the
-- order the pushes run.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom224');
select tests.create_supabase_user('dad224');

select tests.authenticate_as('mom224');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(224), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(224), 'co_parent', 'Dad',
  '2424242424242424242424242424242424242424242424242424242424242424', 48
);
select tests.authenticate_as('dad224');
select public.accept_guardian_invitation(
  '2424242424242424242424242424242424242424242424242424242424242424', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad224'), tests.ulid(224), true);

-- ---------------------------------------------------------------------------
-- 1. Direct client soft-delete: even a client that (bug or old build) still
--    sends its stale flow value alongside deleted_at gets overridden by the
--    server - the fix does not merely trust a well-behaved client.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom224');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(225), 'profile_id', tests.ulid(224), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["cramps"]'::jsonb, 'note', 'a heavy day',
    'updated_at', pg_temp.ts_txt('t1'))));

-- Control: the live insert above is an ordinary logged entry under an armed
-- preference, so it enqueues exactly one alert for Dad - proof the pipeline
-- is live before the tombstoning push below, so that push's "still exactly
-- one" is meaningful rather than vacuous.
select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  1::bigint,
  'setup: the live insert enqueues exactly one alert for Dad - the pipeline is armed'
);

select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(225), 'profile_id', tests.ulid(224), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'heavy', -- stale/buggy client value; server must not trust it
    'updated_at', pg_temp.ts_txt('t2'), 'deleted_at', pg_temp.ts_txt('t2'))));

select is(
  (select flow from public.day_entries where id = tests.ulid(225)),
  'none',
  'issue #224: a fresh direct soft-delete forces flow to none even when the client push still carries a stale value'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(225)),
  '[]'::jsonb,
  'the direct soft-delete still clears tags, as before'
);
select is(
  (select note from public.day_entries where id = tests.ulid(225)),
  null,
  'the direct soft-delete still clears note, as before'
);
select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  1::bigint,
  'the tombstoning push enqueues no additional alert for Dad - still exactly the one from the earlier live insert'
);

-- ---------------------------------------------------------------------------
-- 2. Same-date resolver, "incoming wins" branch: the *other*, already
--    stored row is tombstoned by a direct UPDATE. Mirrors
--    same_date_tag_merge_test.sql's setup, adding the flow assertion that
--    file does not make.
-- ---------------------------------------------------------------------------
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(226), 'profile_id', tests.ulid(224), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom''s note',
    'updated_at', pg_temp.ts_txt('t1'))));

select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  2::bigint,
  'setup: this ordinary live insert enqueues one more alert for Dad (writer is Mom)'
);

select tests.authenticate_as('dad224');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(227), 'profile_id', tests.ulid(224), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["heavy_flow"]'::jsonb, 'note', 'dad''s note',
    'updated_at', pg_temp.ts_txt('t2'))));

select is(
  (select flow from public.day_entries where id = tests.ulid(226)),
  'none',
  'issue #224: the same-date resolver''s loser (the already-stored, now-tombstoned other row) has flow forced to none'
);
select is(
  (select flow from public.day_entries where id = tests.ulid(227)),
  'heavy',
  'control: the surviving winner keeps its own flow untouched (last-writer-wins, unrelated to this fix)'
);
select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  2::bigint,
  'tombstoning the loser via the resolver adds no alert (short-circuited by new.deleted_at), and the winner''s own '
  || 'insert adds none either since its writer, Dad, is the only guardian with a preference row (self-exclusion)'
);

-- ---------------------------------------------------------------------------
-- 3. Same-date resolver, "incoming loses" branch: the *incoming* row is
--    the one that becomes the tombstone, written via a plain INSERT since
--    no row with its id was stored yet. Entry 229's tags are deliberately a
--    subset of entry 228's, so the resolver's tag-union onto 228 is a
--    complete no-op (228's own row is untouched in every column the
--    enqueue trigger's WHEN clause inspects) - isolating this block's
--    outbox-count assertion to entry 229's tombstoning INSERT alone,
--    rather than conflating it with an ordinary tag-merge edit's own
--    (legitimate) alert on 228.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom224');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(228), 'profile_id', tests.ulid(224), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["a", "b"]'::jsonb, 'note', 'winner',
    'updated_at', pg_temp.ts_txt('t2'))));

select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  3::bigint,
  'setup: this ordinary live insert enqueues one more alert for Dad (writer is Mom)'
);

select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(229), 'profile_id', tests.ulid(224), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["a"]'::jsonb, 'note', 'loser',
    'updated_at', pg_temp.ts_txt('t1'))));

select is(
  (select flow from public.day_entries where id = tests.ulid(229)),
  'none',
  'issue #224: the same-date resolver''s "incoming loses" branch stores the incoming row itself as a payload-free tombstone (flow forced to none)'
);
select is(
  (select deleted_at from public.day_entries where id = tests.ulid(229)),
  (select updated_at from public.day_entries where id = tests.ulid(228)),
  'control: the incoming-loses row is still tombstoned at the winner''s timestamp, unchanged by this fix'
);
select is(
  pg_temp.outbox_count(tests.ulid(224), tests.get_supabase_uid('dad224')),
  3::bigint,
  'a row born as a tombstone via the resolver''s incoming-loses branch enqueues nothing (new.deleted_at short-circuits '
  || 'the trigger); entry 228''s own tag-merge update is a deliberate no-op here so it adds nothing to conflate with'
);

-- ---------------------------------------------------------------------------
-- 4. Structural guard (AC5): the CHECK constraint exists and is enforced
--    independently of sync_push - a raw write that bypasses the RPC
--    entirely still cannot leave a tombstone with a non-none flow.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from pg_catalog.pg_constraint
    where conrelid = 'public.day_entries'::regclass
      and conname = 'day_entries_tombstone_flow_check'),
  1::bigint,
  'day_entries_tombstone_flow_check exists on public.day_entries'
);

select tests.clear_authentication();
select throws_ok(
  format($$update public.day_entries set flow = 'heavy' where id = %L$$, tests.ulid(225)),
  '23514',
  null,
  'a raw write attempting to give a tombstoned row a non-none flow is rejected by the CHECK constraint, not just by sync_push'
);

-- ---------------------------------------------------------------------------
-- 5. Backfill (AC3/AC4): simulate-then-reconcile, mirroring
--    tags_element_length_check_test.sql - drop the guard to recreate the
--    pre-migration drift (a tombstone stored with a stale flow, the only
--    shape the old rule permitted), then re-run the migration's exact
--    backfill statement and assert it, then re-add the guard.
-- ---------------------------------------------------------------------------
alter table public.day_entries drop constraint day_entries_tombstone_flow_check;

insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, tags, note, updated_at, deleted_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(230), tests.get_supabase_uid('mom224'), tests.ulid(224), '2026-09-08', 'UTC',
   'heavy', '[]'::jsonb, null, now(), now(),
   tests.get_supabase_uid('mom224'), tests.get_supabase_uid('mom224'));

select is(
  (select flow from public.day_entries where id = tests.ulid(230)),
  'heavy',
  'setup: the drift is real - a pre-fix tombstone with a stale flow is stored (only possible with the guard dropped)'
);

update public.day_entries
   set flow = 'none'
 where deleted_at is not null
   and flow <> 'none';

select is(
  (select flow from public.day_entries where id = tests.ulid(230)),
  'none',
  'the migration''s backfill statement clears a pre-existing tombstone''s stale flow to none'
);

alter table public.day_entries
  add constraint day_entries_tombstone_flow_check
  check (deleted_at is null or flow = 'none');

select is(
  (select count(*) from pg_catalog.pg_constraint
    where conrelid = 'public.day_entries'::regclass
      and conname = 'day_entries_tombstone_flow_check'),
  1::bigint,
  'the guard is re-added and re-validates every now-corrected row without error'
);

select * from finish();
rollback;
