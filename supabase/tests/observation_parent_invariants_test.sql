-- Coverage for Issue #616: LLA-057 (observation parent invariants and
-- per-day cap enforced on every write) and LLA-059 (profiles.transferred_at
-- / transferred_to_user_id are server-authoritative on every write, not
-- only UPDATE).
--
-- Both findings share one shape: sync_push already re-validates these
-- invariants on every push, but the table grants (observations: INSERT and
-- most columns' UPDATE; profiles: INSERT with no column list) let an
-- authenticated client write the table directly and skip the RPC's own
-- checks entirely. This file proves the new BEFORE INSERT/UPDATE triggers
-- close both raw-write paths without breaking sync_push's own legitimate
-- writes (the reparent path in particular).
begin;
select plan(16);

select tests.create_supabase_user('mom_l057');
select tests.create_supabase_user('outsider_l057');

select tests.authenticate_as('mom_l057');

-- Two profiles both guarded by mom, each with one day entry - the fixture
-- LLA-057's cross-profile-link case needs (mom is a legitimate write-role
-- guardian of BOTH, so RLS alone would admit the smuggling INSERT; only
-- the new trigger's composite check catches it).
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values
  (tests.ulid(2901), 'Profile A', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z'),
  (tests.ulid(2904), 'Profile B', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values
  (tests.ulid(2902), tests.ulid(2901), '2026-09-10', 'UTC', 'none', '2026-09-10T09:00:00Z'),
  (tests.ulid(2905), tests.ulid(2904), '2026-09-10', 'UTC', 'none', '2026-09-10T09:00:00Z');

-- ---------------------------------------------------------------------------
-- 1. LLA-057: a raw INSERT cannot link an observation on profile A's own
-- row to profile B's day_entries row, even though mom legitimately guards
-- both profiles (RLS alone admits this write - only the new composite
-- parent-invariant trigger catches the mismatch).
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.observations
        (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
      values (%L, %L, %L, '2026-09-10', 'UTC', 'mood', '2026-09-10T09:00:00Z')$$,
    tests.ulid(2910), tests.ulid(2905), tests.ulid(2901)
  ),
  '42501', 'day_entry_id does not belong to profile_id',
  'LLA-057: a raw INSERT cannot link an observation to another profile''s day_entries row'
);

-- ---------------------------------------------------------------------------
-- 2. A correctly-paired raw INSERT still succeeds (the fix only rejects
-- the mismatched pair, not raw writes in general).
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
values (tests.ulid(2911), tests.ulid(2902), tests.ulid(2901), '2026-09-10', 'UTC', 'mood', '2026-09-10T09:00:00Z');
select is(
  (select count(*) from public.observations where id = tests.ulid(2911))::int,
  1,
  'a correctly-paired raw INSERT still lands'
);

-- ---------------------------------------------------------------------------
-- 3. LLA-057: observations.profile_id is fully immutable at the trigger
-- level - proven structurally (pg_get_functiondef), not via a raw UPDATE
-- attempt, because issue #562
-- (20260913017000_day_entries_column_grants.sql) already revoked
-- authenticated's UPDATE grant on observations.profile_id entirely, so a
-- raw UPDATE naming that column fails on the GRANT before this trigger --
-- or any trigger -- ever runs; the trigger's own check is deliberate
-- defense in depth for any future/internal path, not the reachable
-- boundary for an authenticated client today.
select ok(
  position('observations.profile_id is immutable' in
    pg_get_functiondef('public.enforce_observation_parent_invariants()'::regprocedure)) > 0,
  'LLA-057: enforce_observation_parent_invariants() still rejects a changed profile_id (defense in depth)'
);
select throws_ok(
  format(
    $$update public.observations set profile_id = %L, updated_at = '2026-09-10T09:05:00Z' where id = %L$$,
    tests.ulid(2904), tests.ulid(2911)
  ),
  '42501', null,
  'a raw UPDATE naming observations.profile_id is refused at the GRANT layer before any trigger runs'
);

-- ---------------------------------------------------------------------------
-- 4. LLA-057: a raw UPDATE that re-points day_entry_id at a MISMATCHED
-- profile's day entry (not just a same-profile reparent) is rejected too.
-- last_modified_by_user_id must be set to the caller in every UPDATE below
-- (a pre-existing, unrelated requirement of enforce_observation_
-- attribution()) so these raw writes reach the new trigger at all.
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$update public.observations
        set day_entry_id = %L, updated_at = '2026-09-10T09:05:00Z', last_modified_by_user_id = %L
      where id = %L$$,
    tests.ulid(2905), tests.get_supabase_uid('mom_l057'), tests.ulid(2911)
  ),
  '42501', 'day_entry_id does not belong to profile_id',
  'LLA-057: a raw UPDATE cannot re-point day_entry_id at another profile''s day entry'
);

-- ---------------------------------------------------------------------------
-- 5. LLA-057: reparenting day_entry_id between two day_entries rows of the
-- SAME profile - exactly what sync_push's same-date resolver does
-- (20260914010000_sync_push_observation_reparent.sql) - is NOT blocked.
-- ---------------------------------------------------------------------------
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(2906), tests.ulid(2901), '2026-09-11', 'UTC', 'none', '2026-09-11T09:00:00Z');
update public.observations
   set day_entry_id = tests.ulid(2906), updated_at = '2026-09-10T09:05:00Z',
       last_modified_by_user_id = tests.get_supabase_uid('mom_l057')
 where id = tests.ulid(2911);
select is(
  (select day_entry_id from public.observations where id = tests.ulid(2911)),
  tests.ulid(2906),
  'LLA-057: a same-profile day_entry_id reparent is still permitted'
);

-- ---------------------------------------------------------------------------
-- 6-8. LLA-057: the 200-observations-per-day cap is enforced on a raw
-- write, not only inside sync_push.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
select
  tests.ulid(3000 + n), tests.ulid(2902), tests.ulid(2901), '2026-09-12', 'UTC', 'mood',
  '2026-09-12T09:00:00Z'::timestamptz
from generate_series(1, 199) as n;
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(2901) and local_date = '2026-09-12' and deleted_at is null)::int,
  199,
  'fixture: 199 live observations already logged for 2026-09-12'
);
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
values (tests.ulid(3200), tests.ulid(2902), tests.ulid(2901), '2026-09-12', 'UTC', 'mood', '2026-09-12T09:00:00Z');
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(2901) and local_date = '2026-09-12' and deleted_at is null)::int,
  200,
  'the 200th observation for the day is accepted (at the cap, not over it)'
);
select throws_ok(
  format(
    $$insert into public.observations
        (id, day_entry_id, profile_id, local_date, tz, category, updated_at)
      values (%L, %L, %L, '2026-09-12', 'UTC', 'mood', '2026-09-12T09:00:00Z')$$,
    tests.ulid(3201), tests.ulid(2902), tests.ulid(2901)
  ),
  '22023', null,
  'LLA-057: a raw INSERT is rejected once the day already holds 200 live observations'
);

-- ---------------------------------------------------------------------------
-- 9. A tombstone insert on the same (already-at-cap) day is still allowed
-- - the cap only ever bounds LIVE rows.
-- ---------------------------------------------------------------------------
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, updated_at, deleted_at)
values (tests.ulid(3202), tests.ulid(2902), tests.ulid(2901), '2026-09-12', 'UTC', null, '2026-09-12T09:10:00Z', '2026-09-12T09:10:00Z');
select is(
  (select count(*) from public.observations where id = tests.ulid(3202))::int,
  1,
  'a tombstone insert is never blocked by the per-day live cap'
);

-- ---------------------------------------------------------------------------
-- 10-11. LLA-059: a raw INSERT of a brand-new profile cannot forge
-- transferred_at or transferred_to_user_id.
-- ---------------------------------------------------------------------------
select throws_ok(
  format(
    $$insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at, transferred_at)
      values (%L, 'Forged', false, 0, now(), now(), now())$$,
    tests.ulid(2920)
  ),
  '42501', 'transferred_at/transferred_to_user_id are server-authoritative',
  'LLA-059: a raw INSERT cannot forge profiles.transferred_at on a new row'
);
select throws_ok(
  format(
    $$insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at, transferred_to_user_id)
      values (%L, 'Forged', false, 0, now(), now(), %L)$$,
    tests.ulid(2921), tests.get_supabase_uid('outsider_l057')
  ),
  '42501', 'transferred_at/transferred_to_user_id are server-authoritative',
  'LLA-059: a raw INSERT cannot forge profiles.transferred_to_user_id on a new row'
);

-- ---------------------------------------------------------------------------
-- 12. An ordinary profile INSERT (no transfer fields) still succeeds.
-- ---------------------------------------------------------------------------
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2922), 'Ordinary', false, 0, now(), now());
select is(
  (select transferred_at from public.profiles where id = tests.ulid(2922)),
  null,
  'an ordinary profile INSERT still succeeds and leaves transferred_at null'
);

-- ---------------------------------------------------------------------------
-- 13-15. LLA-059: accept_ownership_transfer's legitimate UPDATE (the KTD4
-- lunarlog.ownership_transfer bypass) still works through the new trigger.
-- ---------------------------------------------------------------------------
create function pg_temp.token2() returns text language sql as
  $$ select lpad(to_hex(9002), 64, '0') $$;
select is(
  (select public.create_ownership_transfer(tests.ulid(2922), 'viewer', pg_temp.token2()) ->> 'profile_id'),
  tests.ulid(2922),
  'fixture: create_ownership_transfer still arms a transfer'
);
select tests.authenticate_as('outsider_l057');
select is(
  (select public.accept_ownership_transfer(pg_temp.token2(), 'Kid', 'Mom') ->> 'profile_id'),
  tests.ulid(2922),
  'LLA-059: accept_ownership_transfer''s stamp still succeeds through the new trigger''s GUC bypass'
);
select is(
  (select transferred_to_user_id from public.profiles where id = tests.ulid(2922)),
  tests.get_supabase_uid('outsider_l057'),
  'transferred_to_user_id is actually stamped with the accepting user'
);

select * from finish();
rollback;
