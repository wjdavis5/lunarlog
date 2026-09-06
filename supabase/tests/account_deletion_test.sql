-- Regression coverage for public.delete_account_data() (Issue #17, Unit U1):
-- the row-deletion half of in-app account deletion. Reuses the
-- create_supabase_user / authenticate_as handshake idiom already established
-- in sync_push_test.sql and profile_guardians_rls_test.sql, and the
-- pg_temp-result-table idiom from sync_push_test.sql for snapshot
-- comparisons.
begin;
select plan(26);

create temp table snap (name text primary key, v jsonb);
grant all on table snap to authenticated;

create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into snap values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.snap(n text) returns jsonb language sql as
  $$ select v from snap where name = n $$;

select tests.create_supabase_user('user_a');
select tests.create_supabase_user('user_b');

-- ---------------------------------------------------------------------------
-- 1. Function shape: security definer, search_path = '', authenticated-only.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_proc
     where proname = 'delete_account_data'
       and pronamespace = 'public'::regnamespace
  ),
  'public.delete_account_data() exists'
);

select is(
  (select prosecdef from pg_proc
    where proname = 'delete_account_data' and pronamespace = 'public'::regnamespace),
  true,
  'delete_account_data is security definer'
);

select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'delete_account_data' and pronamespace = 'public'::regnamespace
       and c.setting like 'search_path=%'
  ),
  'delete_account_data sets search_path = '''''
);

select ok(
  has_function_privilege('authenticated', 'public.delete_account_data()', 'execute'),
  'authenticated can execute delete_account_data'
);

select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'delete_account_data'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint,
  'PUBLIC and anon hold no EXECUTE on delete_account_data'
);

-- ---------------------------------------------------------------------------
-- 2. No JWT: anon is refused by the grant; an authenticated role with no
--    claims is refused by the function's own auth.uid() check (AE6).
-- ---------------------------------------------------------------------------

-- Fixture so "deletes nothing" is provable: A has one profile before either
-- unauthenticated attempt.
select tests.authenticate_as('user_a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.delete_account_data()$$,
  '42501', null,
  'anon cannot execute delete_account_data'
);

-- authenticated role, but no request.jwt.claims (auth.uid() is null).
select set_config('request.jwt.claims', '', true);
select set_config('role', 'authenticated', true);
select throws_ok(
  $$select public.delete_account_data()$$,
  '42501', null,
  'an authenticated role with no JWT claims is refused (auth.uid() is null)'
);

select tests.clear_authentication();
select is(
  (select count(*) from public.profiles where id = tests.ulid(1)),
  1::bigint,
  'neither unauthenticated attempt deleted anything'
);

-- ---------------------------------------------------------------------------
-- 3. AE2: full cascade for the owner, and B's rows are untouched.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');

-- A second profile, five entries total, three settings rows, one
-- outstanding invitation - the AE2 fixture shape from the plan.
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2), 'Sam', true, 1, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values
  (tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z'),
  (tests.ulid(11), tests.ulid(1), '2026-09-02', 'UTC', 'medium', '2026-09-02T00:00:00Z'),
  (tests.ulid(12), tests.ulid(1), '2026-09-03', 'UTC', 'none', '2026-09-03T00:00:00Z'),
  (tests.ulid(13), tests.ulid(2), '2026-09-01', 'UTC', 'spotting', '2026-09-01T00:00:00Z'),
  (tests.ulid(14), tests.ulid(2), '2026-09-02', 'UTC', 'heavy', '2026-09-02T00:00:00Z');

insert into public.settings (user_id, key, value)
values
  (tests.get_supabase_uid('user_a'), 'k1', 'v1'),
  (tests.get_supabase_uid('user_a'), 'k2', 'v2'),
  (tests.get_supabase_uid('user_a'), 'k3', 'v3');

select public.create_guardian_invitation(
  tests.ulid(1), 'caregiver', 'Grandma',
  'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1', 48
);

-- B's own data - must survive A's deletion untouched.
select tests.authenticate_as('user_b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(3), 'Bailey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(20), tests.ulid(3), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z');
insert into public.settings (user_id, key, value)
values (tests.get_supabase_uid('user_b'), 'k1', 'v1');

select pg_temp.snapshot('b_before', jsonb_build_object(
  'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p
                where user_id = tests.get_supabase_uid('user_b')),
  'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d
                   where user_id = tests.get_supabase_uid('user_b')),
  'settings', (select jsonb_agg(to_jsonb(s) order by s.key) from public.settings s
                where user_id = tests.get_supabase_uid('user_b'))
));

-- A deletes.
select tests.authenticate_as('user_a');
select pg_temp.snapshot('a_result', public.delete_account_data());

-- Check as a role that isn't relying on A's own (now-gone) guardian rows for
-- its RLS visibility: day_entries_select_guardians gates on
-- is_profile_guardian(profile_id, uid), which A can no longer satisfy for
-- these profiles regardless of whether the rows still exist, so continuing
-- to query as A would make "have: 0" indistinguishable from "hidden by RLS"
-- (the same gap this file's AE3 checks avoid).
select tests.clear_authentication();

select is(
  (select count(*) from public.profiles where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'AE2: zero profiles remain for A'
);
select is(
  (select count(*) from public.day_entries where profile_id in (tests.ulid(1), tests.ulid(2))),
  0::bigint, 'AE2: zero day_entries remain for A''s profiles'
);
select is(
  (select count(*) from public.settings where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'AE2: zero settings remain for A'
);
select is(
  (select count(*) from public.profile_guardians where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'AE2: zero profile_guardians remain for A'
);
select is(
  (select count(*) from public.guardian_invitations where invited_by = tests.get_supabase_uid('user_a')),
  0::bigint, 'AE2: zero guardian_invitations remain for A'
);

select tests.clear_authentication();
select is(
  jsonb_build_object(
    'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p
                  where user_id = tests.get_supabase_uid('user_b')),
    'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d
                     where user_id = tests.get_supabase_uid('user_b')),
    'settings', (select jsonb_agg(to_jsonb(s) order by s.key) from public.settings s
                  where user_id = tests.get_supabase_uid('user_b'))
  ),
  pg_temp.snap('b_before'),
  'AE2: B''s profiles, entries and settings are byte-identical before and after A''s deletion'
);

-- ---------------------------------------------------------------------------
-- 4. Returned jsonb carries the expected keys and correct counts.
-- ---------------------------------------------------------------------------

select is(pg_temp.snap('a_result') -> 'profiles', '2'::jsonb, 'result: profiles count is 2');
select is(pg_temp.snap('a_result') -> 'day_entries', '5'::jsonb, 'result: day_entries count is 5');
select is(pg_temp.snap('a_result') -> 'settings', '3'::jsonb, 'result: settings count is 3');
select is(pg_temp.snap('a_result') -> 'guardian_invitations', '1'::jsonb, 'result: guardian_invitations count is 1');
select is(pg_temp.snap('a_result') -> 'profile_guardians', '2'::jsonb,
  'result: profile_guardians count is 2 (A''s own primary_guardian rows on both profiles)');

-- ---------------------------------------------------------------------------
-- 5. Idempotency (supports KTD4's retry story): calling again reports zero.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
select is(
  public.delete_account_data(),
  jsonb_build_object(
    'day_entries', 0, 'guardian_invitations', 0,
    'profile_guardians', 0, 'profiles', 0, 'settings', 0
  ),
  'calling delete_account_data twice reports zero counts the second time'
);

-- ---------------------------------------------------------------------------
-- 6. AE3: a non-owner (accepted caregiver) deletes. The owner's profile and
--    entries survive; only the caregiver's own membership is removed. The
--    logged_by_user_id -> null half of AE3 rides the auth.users FK
--    (`on delete set null`) and is exercised by U2's manual smoke, not here
--    - this only asserts the membership half, per the plan.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_c'); -- owner
select tests.create_supabase_user('user_d'); -- caregiver

select tests.authenticate_as('user_c');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(4), 'Riley C', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(30), tests.ulid(4), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(4), 'caregiver', 'D',
  'd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1', 48
);

select tests.authenticate_as('user_d');
select public.accept_guardian_invitation(
  'd1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1d1', 'D'
);

-- D also logs an entry directly on C's shared profile: this row's user_id
-- defaults to auth.uid() at insert time, i.e. D, per the initial sync
-- schema's `default auth.uid()` - the exact case R7/AE3 protects.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(31), tests.ulid(4), '2026-09-02', 'UTC', 'medium', '2026-09-02T00:00:00Z',
        tests.get_supabase_uid('user_d'), tests.get_supabase_uid('user_d'));

select pg_temp.snapshot('d_result', public.delete_account_data());

-- Switch off D's now-revoked identity before checking what survives: D is no
-- longer a guardian of profile 4, so profiles_select_guardians /
-- day_entries_select_guardians / profile_guardians_select would otherwise
-- hide C's own rows from D's (still-authenticated) session by RLS, which
-- would make "have: 0" indistinguishable from "actually deleted".
select tests.clear_authentication();

select is(
  (select count(*) from public.profiles where id = tests.ulid(4)),
  1::bigint, 'AE3: C''s profile survives D''s deletion'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(4)),
  2::bigint, 'AE3: C''s profile''s entries (including the one D logged) survive'
);
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(4) and user_id = tests.get_supabase_uid('user_d')),
  0::bigint, 'AE3: D''s profile_guardians membership row is gone'
);
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(4) and user_id = tests.get_supabase_uid('user_c')),
  1::bigint, 'AE3: C''s own primary_guardian membership is untouched'
);

-- ---------------------------------------------------------------------------
-- 7. A revoked membership row for the caller is also removed.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_e'); -- owner
select tests.create_supabase_user('user_f'); -- revoked ex-caregiver

select tests.authenticate_as('user_e');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(5), 'Riley E', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(5), 'caregiver', 'F',
  'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1', 48
);

select tests.authenticate_as('user_f');
select public.accept_guardian_invitation(
  'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1', 'F'
);

select tests.authenticate_as('user_e');
select public.revoke_guardian(tests.ulid(5), tests.get_supabase_uid('user_f'));

select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(5) and user_id = tests.get_supabase_uid('user_f')),
  'revoked',
  'F''s membership is revoked before F deletes their account'
);

select tests.authenticate_as('user_f');
select public.delete_account_data();

-- As with AE3 above: check as a role that isn't relying on the very
-- membership row under test for its own RLS visibility.
select tests.clear_authentication();
select is(
  (select count(*) from public.profile_guardians where user_id = tests.get_supabase_uid('user_f')),
  0::bigint,
  'a revoked membership row for the caller is also removed'
);

select * from finish();
rollback;
