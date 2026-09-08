-- Coverage for the pre-clean path of 20260907010000_tags_element_length_check.sql
-- (issue #94; PR #145 review items #1 and #2). The migration's one
-- data-mutating statement - the UPDATE that drops over-length tag elements
-- from already-stored rows - changes `tags`, which satisfies
-- day_entries_after_update_enqueue_alerts' WHEN clause: left unbracketed it
-- would fan real caregiver alerts out of notification_outbox for historical
-- entries nobody just logged. The migration therefore disables that one
-- trigger for exactly the pre-clean UPDATE (review item #1), and this file
-- proves both halves:
--   1. the pre-clean really cleans a stored offending row (over-length
--      elements dropped, valid ones kept in order) and the drop-and-re-add
--      re-validates it (R3/R4);
--   2. the pre-clean enqueues nothing, while the alert pipeline is proven
--      armed around it - an ordinary insert before, and an ordinary content
--      edit of the same row after, each enqueue exactly one outbox row.
-- Mirrors the simulate-then-reconcile pattern of realtime_publication_test.sql's
-- Studio-toggle block: drop day_entries_tags_check to simulate the
-- pre-migration world (where the old is_valid_tags_array let over-length
-- elements through - the only shape of stored violation the old rule
-- permitted), store offending rows, then re-run the migration's statements
-- verbatim and assert the corrected state. The reconcile statements below
-- must be kept in sync with the migration file if it ever changes.
begin;
select plan(11);

-- Helper: inspect the outbox the way the trigger's security-definer writes
-- it (no authenticated policy exists on this table at all, by design).
create function pg_temp.outbox_count(p_profile text, p_recipient uuid) returns bigint
language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient;
$$;

-- ---------------------------------------------------------------------------
-- Fixture: Mom owns a minor profile; Dad is an accepted co_parent.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(960), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(960), 'co_parent', 'Dad',
  '9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c', 'Dad'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- Simulate the drift: drop the tightened CHECK so an over-length row can be
-- stored again, then store two offending rows as Mom. No
-- notification_preferences row exists yet, so the INSERT trigger fires but
-- has no eligible guardian - the fixture starts quiet.
-- ---------------------------------------------------------------------------
alter table public.day_entries drop constraint day_entries_tags_check;

insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, tags, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(961), tests.get_supabase_uid('mom'), tests.ulid(960), '2026-09-01', 'UTC', 'none',
   jsonb_build_array('cramps', repeat('x', 65)), now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom')),
  (tests.ulid(962), tests.get_supabase_uid('mom'), tests.ulid(960), '2026-09-02', 'UTC', 'light',
   jsonb_build_array(repeat('y', 70), 'bloating', repeat('z', 80), 'headache'), now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));

select is(pg_temp.outbox_count(tests.ulid(960), tests.get_supabase_uid('dad')), 0::bigint,
  'setup: no preferences yet, so storing the offending rows enqueues nothing');
select is(
  (select tags from public.day_entries where id = tests.ulid(961)),
  jsonb_build_array('cramps', repeat('x', 65)),
  'setup: the drift is real - a 65-character element is stored (only possible with the CHECK dropped)'
);

-- ---------------------------------------------------------------------------
-- Arm the alert pipeline: Dad opts into alert_on_log. An ordinary live
-- insert now enqueues exactly one outbox row for him - proof the fixture is
-- armed BEFORE the pre-clean runs, so the later "still exactly one" below is
-- meaningful rather than vacuous.
-- ---------------------------------------------------------------------------
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad'), tests.ulid(960), true);

insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, tags, updated_at, logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(963), tests.get_supabase_uid('mom'), tests.ulid(960), '2026-09-03', 'UTC', 'none', '["calm"]', now(),
   tests.get_supabase_uid('mom'), tests.get_supabase_uid('mom'));

select is(pg_temp.outbox_count(tests.ulid(960), tests.get_supabase_uid('dad')), 1::bigint,
  'setup: the alert pipeline is armed - an ordinary live insert enqueues for Dad');

-- ---------------------------------------------------------------------------
-- Reconcile: the migration's statements, verbatim. The disable/enable
-- bracket around the pre-clean is the PR #145 review item #1 fix under test.
-- ---------------------------------------------------------------------------
alter table public.day_entries
  disable trigger day_entries_after_update_enqueue_alerts;

select lives_ok($$
  update public.day_entries d
     set tags = (
       select coalesce(jsonb_agg(e.value order by e.ordinality), '[]'::jsonb)
         from jsonb_array_elements(d.tags) with ordinality as e(value, ordinality)
        where jsonb_typeof(e.value) = 'string'
          and char_length(e.value #>> '{}') <= 64
     )
    where not public.is_valid_tags_array(d.tags)
$$, 'the pre-clean UPDATE runs without error');

alter table public.day_entries
  enable trigger day_entries_after_update_enqueue_alerts;

alter table public.day_entries
  drop constraint if exists day_entries_tags_check,
  add constraint day_entries_tags_check
    check (public.is_valid_tags_array(tags));

-- ---------------------------------------------------------------------------
-- Assert the corrected state.
-- ---------------------------------------------------------------------------
select is(
  (select tags from public.day_entries where id = tests.ulid(961)),
  '["cramps"]'::jsonb,
  'the over-length element is dropped; the valid element survives'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(962)),
  '["bloating", "headache"]'::jsonb,
  'both over-length elements are dropped and the interleaved valid ones keep their order'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(963)),
  '["calm"]'::jsonb,
  'an already-valid row is not rewritten by the pre-clean'
);
select is(pg_temp.outbox_count(tests.ulid(960), tests.get_supabase_uid('dad')), 1::bigint,
  'the pre-clean changed tags on live rows under an armed pipeline and enqueued '
  || 'nothing (review item #1: the disable bracket held)');
select is(
  (select tgenabled from pg_catalog.pg_trigger
    where tgrelid = 'public.day_entries'::regclass
      and tgname = 'day_entries_after_update_enqueue_alerts'),
  'O'::"char",
  'the UPDATE trigger is back at origin-enabled after the bracket - no residue'
);
select is(
  (select count(*) from pg_catalog.pg_constraint
    where conrelid = 'public.day_entries'::regclass
      and conname = 'day_entries_tags_check'),
  1::bigint,
  'day_entries_tags_check is re-added, having re-validated the cleaned rows without error (R3/R4)'
);

-- Kill-shot control: the SAME row, the SAME armed pipeline, one ordinary
-- content edit with the trigger back enabled enqueues exactly one more row -
-- so the silence above is attributable to the disable bracket, not to a dead
-- fixture.
update public.day_entries
   set flow = 'heavy'
 where id = tests.ulid(961);

select is(pg_temp.outbox_count(tests.ulid(960), tests.get_supabase_uid('dad')), 2::bigint,
  'control: an ordinary content edit on the same row right after still enqueues - '
  || 'the fixture was live throughout; only the pre-clean was silent');

select * from finish();
rollback;
