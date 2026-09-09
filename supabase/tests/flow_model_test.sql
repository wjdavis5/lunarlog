-- Coverage for 20260908200000_flow_model.sql (issue #247, P1, epic:
-- tracking-model): the day_entries_flow_check re-emission (super_heavy/
-- not_bleeding accepted, garbage still rejected, every previously-accepted
-- value still accepted), sync_push round-tripping both new values (proving
-- the flow allow-list change is the only substantive difference from
-- 20260908180000_timezone_contract.sql's body), and the one-off spotting
-- backfill (exactly one observations row per live spotting day_entries row,
-- idempotent via on conflict do nothing, trigger-storm-safe via the
-- disable/enable pattern, day_entries.flow itself left untouched), and
-- (review follow-up, PR #335) the re-emitted enqueue_caregiver_alerts():
-- not_bleeding is never a false cycle_start, super_heavy is high severity.
begin;
select plan(31);

-- Outbox reads under an authenticated role hit notification_outbox's RLS/grant
-- wall (review fix on #335): count through a SECURITY DEFINER helper created
-- before the first authenticate_as, mirroring alert_digest_test.sql's
-- pg_temp.count_rows.
create function pg_temp.flow_outbox_count(p_profile text, p_recipient uuid, p_kind text)
returns bigint language sql security definer set search_path = '' as $$
  select count(*) from public.notification_outbox
   where profile_id = p_profile and recipient_user_id = p_recipient
     and (p_kind is null or kind = p_kind)
$$;

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t1', '2026-09-08T10:00:00Z'),
  ('t2', '2026-09-08T11:00:00Z');
grant select on table ts to authenticated;

create function pg_temp.ts_txt(k text) returns text language sql as
  $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') from ts where ts.k = $1 $$;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

select tests.create_supabase_user('flow247');
select tests.authenticate_as('flow247');

insert into r select 'p_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(24700), 'display_name', 'Riley', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', null)),
  '[]'::jsonb);
select is((select display_name from public.profiles where id = tests.ulid(24700)), 'Riley',
  'setup: profile lands via sync_push');

-- ---------------------------------------------------------------------------
-- 1. day_entries_flow_check: super_heavy/not_bleeding accepted, garbage
--    still rejected, every previously-accepted value still accepted.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from pg_catalog.pg_constraint
    where conrelid = 'public.day_entries'::regclass
      and conname = 'day_entries_flow_check'),
  1::bigint,
  'day_entries_flow_check exists on public.day_entries');

select tests.clear_authentication();
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(24701), tests.get_supabase_uid('flow247'), tests.ulid(24700), '2026-09-08', 'UTC',
   'super_heavy', now(), tests.get_supabase_uid('flow247'), tests.get_supabase_uid('flow247'));
select is((select flow from public.day_entries where id = tests.ulid(24701)), 'super_heavy',
  'a raw insert with flow = super_heavy is accepted by the CHECK');

insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(24702), tests.get_supabase_uid('flow247'), tests.ulid(24700), '2026-09-09', 'UTC',
   'not_bleeding', now(), tests.get_supabase_uid('flow247'), tests.get_supabase_uid('flow247'));
select is((select flow from public.day_entries where id = tests.ulid(24702)), 'not_bleeding',
  'a raw insert with flow = not_bleeding is accepted by the CHECK');

select throws_ok(
  format($$insert into public.day_entries
    (id, user_id, profile_id, local_date, tz, flow, updated_at,
     logged_by_user_id, last_modified_by_user_id)
    values (%L, %L, %L, '2026-09-10', 'UTC', 'torrential', now(), %L, %L)$$,
    tests.ulid(24703), tests.get_supabase_uid('flow247'), tests.ulid(24700),
    tests.get_supabase_uid('flow247'), tests.get_supabase_uid('flow247')),
  '23514',
  null,
  'a raw insert with an unrecognised flow value is still rejected by the CHECK');

-- Every value the old CHECK accepted still round-trips through a raw insert
-- (existing rows are unaffected -- no UPDATE touches flow, and the old
-- allow-list is a strict subset of the new one).
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(24704), tests.get_supabase_uid('flow247'), tests.ulid(24700), '2026-09-11', 'UTC',
   'spotting', now(), tests.get_supabase_uid('flow247'), tests.get_supabase_uid('flow247'));
select is((select flow from public.day_entries where id = tests.ulid(24704)), 'spotting',
  'the pre-existing spotting value is still accepted by the re-emitted CHECK');

select tests.authenticate_as('flow247');

-- ---------------------------------------------------------------------------
-- 2. sync_push round-trips both new values -- the only substantive change
--    versus 20260908180000_timezone_contract.sql's body is the allow-list.
-- ---------------------------------------------------------------------------
insert into r select 'push_super_heavy', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(24710), 'profile_id', tests.ulid(24700), 'local_date', '2026-09-12',
    'tz', 'UTC', 'flow', 'super_heavy', 'tags', '[]'::jsonb, 'note', null,
    'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('push_super_heavy') -> 'rejected', '[]'::jsonb,
  'sync_push: pushing flow = super_heavy is not rejected');
select is((select flow from public.day_entries where id = tests.ulid(24710)), 'super_heavy',
  'sync_push: flow = super_heavy is stored verbatim');

insert into r select 'push_not_bleeding', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(24711), 'profile_id', tests.ulid(24700), 'local_date', '2026-09-13',
    'tz', 'UTC', 'flow', 'not_bleeding', 'tags', '[]'::jsonb, 'note', null,
    'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('push_not_bleeding') -> 'rejected', '[]'::jsonb,
  'sync_push: pushing flow = not_bleeding is not rejected');
select is((select flow from public.day_entries where id = tests.ulid(24711)), 'not_bleeding',
  'sync_push: flow = not_bleeding is stored verbatim');

insert into r select 'push_garbage', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(24712), 'profile_id', tests.ulid(24700), 'local_date', '2026-09-14',
    'tz', 'UTC', 'flow', 'torrential', 'tags', '[]'::jsonb, 'note', null,
    'updated_at', pg_temp.ts_txt('t1'))));
select is(jsonb_array_length(pg_temp.resp('push_garbage') -> 'rejected'), 1,
  'sync_push: an unrecognised flow value is rejected in-RPC, not just by the CHECK');
select is((select count(*) from public.day_entries where id = tests.ulid(24712)), 0::bigint,
  'sync_push: the rejected row is never stored');

-- ---------------------------------------------------------------------------
-- 3. Spotting backfill: simulate-then-reconcile (mirroring
--    tombstone_flow_clear_test.sql / observations_test.sql's own tags
--    backfill coverage) -- the migration's own backfill ran against an
--    empty day_entries table during db reset, so this re-runs its exact
--    statements against a fixture built in this test's own transaction.
-- ---------------------------------------------------------------------------
select is((select count(*) from public.observations where day_entry_id = tests.ulid(24704)),
  0::bigint, 'setup: no observation exists yet for the spotting day entry created above');

-- DDL (disable/enable trigger) needs the superuser/owner role the test
-- session originates as, not the 'authenticated' role the sync_push calls
-- above switched to -- same reason tombstone_flow_clear_test.sql's own
-- backfill section clears authentication first.
select tests.clear_authentication();

alter table public.observations disable trigger observations_after_change_signal;

insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':flow:spotting')), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz, 'spotting', 'spotting', 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
where de.deleted_at is null and de.flow = 'spotting'
on conflict (id) do nothing;

alter table public.observations enable trigger observations_after_change_signal;

insert into public.sync_signals (profile_id, updated_at)
select distinct de.profile_id, now()
  from public.day_entries de
 where de.deleted_at is null and de.flow = 'spotting'
on conflict (profile_id) do update set updated_at = excluded.updated_at;

select is((select count(*) from public.observations where day_entry_id = tests.ulid(24704)),
  1::bigint, 'the backfill inserts exactly one observation for the live spotting day entry');
select is(
  (select category from public.observations where day_entry_id = tests.ulid(24704)),
  'spotting', 'the backfilled observation carries category = spotting');
select is(
  (select code from public.observations where day_entry_id = tests.ulid(24704)),
  'spotting', 'the backfilled observation carries code = spotting');
select is(
  (select source from public.observations where day_entry_id = tests.ulid(24704)),
  'manual', 'the backfilled observation carries source = manual');
select is(
  (select excluded from public.observations where day_entry_id = tests.ulid(24704)),
  false, 'the backfilled observation is not excluded');
select is(
  (select id from public.observations where day_entry_id = tests.ulid(24704)),
  substr(upper(md5(tests.ulid(24704) || ':flow:spotting')), 1, 26),
  'the backfilled observation''s id is deterministic (derived from the day entry''s own id)');
select is((select flow from public.day_entries where id = tests.ulid(24704)), 'spotting',
  'day_entries.flow itself is left untouched by the backfill');
select is(
  (select updated_at from public.sync_signals where profile_id = tests.ulid(24700)) is not null,
  true,
  'the backfill touches sync_signals for the affected profile');

-- Re-run the identical backfill statements a second time (simulating a
-- local db reset replaying this migration from scratch): idempotent via
-- on conflict (id) do nothing.
alter table public.observations disable trigger observations_after_change_signal;

insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':flow:spotting')), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz, 'spotting', 'spotting', 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
where de.deleted_at is null and de.flow = 'spotting'
on conflict (id) do nothing;

alter table public.observations enable trigger observations_after_change_signal;

select is((select count(*) from public.observations where day_entry_id = tests.ulid(24704)),
  1::bigint, 'the backfill is idempotent: re-running it verbatim inserts nothing new');

select is(
  (select t.tgenabled from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'observations' and t.tgname = 'observations_after_change_signal'),
  'O'::"char",
  'observations_after_change_signal is enabled after both backfill runs (not left disabled)');

-- A day entry whose flow never was spotting gets no synthesised observation.
select is(
  (select count(*) from public.observations where day_entry_id = tests.ulid(24710)),
  0::bigint,
  'a non-spotting day entry (super_heavy, from the sync_push round trip above) gets no backfilled observation');

-- ---------------------------------------------------------------------------
-- 3b. Review follow-up (PR #335, blocking): the flow backfill's id is now
--     namespaced (`':flow:spotting'`, this migration's header item 5) so it
--     can never collide with 20260908160000_observations.sql's own tag
--     backfill (`md5(day_entry_id || ':' || tag)`) -- a day entry that is
--     BOTH flow = 'spotting' AND carries a literal 'spotting' tag gets two
--     distinct observation rows, not one silently dropped by the other's
--     on conflict (id) do nothing.
-- ---------------------------------------------------------------------------
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, tags, updated_at,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(24705), tests.get_supabase_uid('flow247'), tests.ulid(24700), '2026-09-15', 'UTC',
   'spotting', jsonb_build_array('spotting'), now(),
   tests.get_supabase_uid('flow247'), tests.get_supabase_uid('flow247'));

alter table public.observations disable trigger observations_after_change_signal;

-- The flow backfill (this migration, item 3/5 -- namespaced id).
insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':flow:spotting')), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz, 'spotting', 'spotting', 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
where de.deleted_at is null and de.flow = 'spotting' and de.id = tests.ulid(24705)
on conflict (id) do nothing;

-- The tag backfill (20260908160000_observations.sql, unchanged keyspace).
insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':' || tag.value)), 1, 26),
  de.id, de.profile_id, de.local_date, de.tz, 'other', tag.value, 'manual', false,
  de.logged_by_user_id, de.last_modified_by_user_id, de.updated_at, de.updated_at
from public.day_entries de
cross join lateral jsonb_array_elements_text(de.tags) as tag(value)
where de.deleted_at is null and de.id = tests.ulid(24705)
on conflict (id) do nothing;

alter table public.observations enable trigger observations_after_change_signal;

select is(
  (select count(*) from public.observations where day_entry_id = tests.ulid(24705)),
  2::bigint,
  'a spotting-flow entry that also carries a literal spotting tag gets two distinct observation rows, not one');
select isnt(
  (select id from public.observations where day_entry_id = tests.ulid(24705) and code = 'spotting'
     and id = substr(upper(md5(tests.ulid(24705) || ':flow:spotting')), 1, 26)),
  null,
  'the flow-backfilled observation keeps its namespaced id');
select is(
  (select count(distinct id) from public.observations where day_entry_id = tests.ulid(24705)),
  2::bigint,
  'the flow backfill and the tag backfill never collide on id (namespaced vs. unnamespaced keyspace)');

-- ---------------------------------------------------------------------------
-- 4. Review follow-up (PR #335, blocking): enqueue_caregiver_alerts() is
--    re-emitted (this migration's header, item 5) so not_bleeding/spotting
--    are never treated as a bleed (no false cycle_start) and super_heavy is
--    recognised as high severity.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('flow247');
select tests.create_supabase_user('flow247_dad');
select public.create_guardian_invitation(
  tests.ulid(24700), 'co_parent', 'Dad',
  '2470247024702470247024702470247024702470247024702470247024702470', 48
);
select tests.authenticate_as('flow247_dad');
select public.accept_guardian_invitation(
  '2470247024702470247024702470247024702470247024702470247024702470', 'Dad'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('flow247_dad'), tests.ulid(24700), true);

select tests.authenticate_as('flow247');

-- A not_bleeding day with no prior bleed day in the merge window must not
-- be treated as a bleed at all -- before this fix, v_is_bleed was
-- `flow <> 'none'`, which wrongly counted not_bleeding (and the deprecated
-- spotting) as a bleed and fired a false cycle_start.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(24720), tests.ulid(24700), '2026-09-20', 'UTC', 'not_bleeding', now());
select is(
  pg_temp.flow_outbox_count(tests.ulid(24700), tests.get_supabase_uid('flow247_dad'), 'cycle_start'),
  0::bigint,
  'a not_bleeding day after no prior bleed enqueues no cycle_start alert');

-- Restrict dad to high-severity-only alerts, then prove super_heavy is
-- recognised as high severity (before this fix, v_is_high_severity was
-- `flow = 'heavy'`, which never matched super_heavy). The RLS update
-- policy only lets the row's own user change it, so switch to dad first --
-- as the profile owner this update silently matches zero rows.
select tests.authenticate_as('flow247_dad');
update public.notification_preferences
   set alert_on_high_severity = true
 where user_id = tests.get_supabase_uid('flow247_dad') and profile_id = tests.ulid(24700);
select is((select alert_on_high_severity from public.notification_preferences
            where user_id = tests.get_supabase_uid('flow247_dad') and profile_id = tests.ulid(24700)),
  true, 'dad''s preference row is narrowed to high-severity-only (RLS allowed the self-update)');
select tests.authenticate_as('flow247');

-- A light bleed day the day before: not high severity, so it is filtered
-- out for dad even though it is itself a cycle_start.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(24721), tests.ulid(24700), '2026-09-21', 'UTC', 'light', now());

-- The super_heavy day follows a bleed day (light, the day before), so it is
-- not a cycle_start either -- isolating the high-severity classification.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(24722), tests.ulid(24700), '2026-09-22', 'UTC', 'super_heavy', now());

select is(
  pg_temp.flow_outbox_count(tests.ulid(24700), tests.get_supabase_uid('flow247_dad'), 'high_severity'),
  1::bigint,
  'a super_heavy day enqueues a high-severity alert');
select is(
  pg_temp.flow_outbox_count(tests.ulid(24700), tests.get_supabase_uid('flow247_dad'), 'cycle_start'),
  0::bigint,
  'with alert_on_high_severity set, the intervening light cycle_start day is filtered out for dad -- alert_on_log stays on (it is the master switch), so only the super_heavy high-severity row above is enqueued after the preference change');

select * from finish();
rollback;
