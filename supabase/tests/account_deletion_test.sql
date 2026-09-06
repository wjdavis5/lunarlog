-- Regression coverage for public.delete_account_data() (Issue #17, Unit U1):
-- the row-deletion half of in-app account deletion. Reuses the
-- create_supabase_user / authenticate_as handshake idiom already established
-- in sync_push_test.sql and profile_guardians_rls_test.sql, and the
-- pg_temp-result-table idiom from sync_push_test.sql for snapshot
-- comparisons.
begin;
select plan(61);

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
select is(pg_temp.snap('a_result') -> 'day_entries_rehomed', '0'::jsonb,
  'result: day_entries_rehomed is 0 (A owns every profile these entries are on)');
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
    'day_entries', 0, 'day_entries_rehomed', 0, 'guardian_invitations', 0,
    'profile_guardians', 0, 'profiles', 0, 'settings', 0,
    'notification_preferences', 0, 'push_devices', 0,
    'notification_outbox', 0, 'profile_reminder_windows', 0,
    'missed_entry_alert_state', 0
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

-- ---------------------------------------------------------------------------
-- 8. P0 regression: day_entries.user_id is `not null references auth.users
--    (id) on delete cascade`. AE3 above never actually deletes D's
--    auth.users row (only calls the RPC), so it could not have caught this:
--    before the fix, deleting a caregiver's real auth.users row cascaded
--    away every day_entries row still stamped with their user_id, including
--    ones logged on a profile they do not own - silently and irreversibly
--    destroying another family's minors' health data, exactly what R7
--    forbids. This exercises the real end-to-end order: the RPC first, then
--    the auth.users row gone for real, mirroring what the delete-account
--    Edge Function does last (KTD4).
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_g'); -- owner
select tests.create_supabase_user('user_h'); -- caregiver, deleted for real

select tests.authenticate_as('user_g');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(6), 'Riley G', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(6), 'caregiver', 'H',
  'abababababababababababababababababababababababababababababababab', 48
);

select tests.authenticate_as('user_h');
select public.accept_guardian_invitation(
  'abababababababababababababababababababababababababababababababab', 'H'
);

-- H logs an entry directly on G's shared profile: user_id defaults to
-- auth.uid() at insert time (H), per the initial sync schema - the exact
-- caregiver-on-someone-else's-profile row this fix re-homes.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(40), tests.ulid(6), '2026-09-05', 'UTC', 'medium', '2026-09-05T00:00:00Z',
        tests.get_supabase_uid('user_h'), tests.get_supabase_uid('user_h'));

-- H deletes their account: the RPC first (as the Edge Function does), then
-- the auth.users row for real (unlike section 6's AE3 fixture above, which
-- only calls the RPC) - exactly the order the delete-account Edge Function
-- runs in (KTD4). Clear authentication before the auth.users delete: in
-- production this runs via auth.admin.deleteUser on GoTrue's own service
-- connection, which carries no JWT claims (auth.uid() is null there, same
-- as the migration/operational-tooling exemption
-- enforce_day_entry_attribution documents) - not H's session. Deleting
-- while still authenticated as H would make the FK's own
-- logged_by_user_id -> null cascade look like H forging their own
-- attribution column and trip that trigger's guard, which is a test-fixture
-- artifact, not a real production path.
select public.delete_account_data();
select tests.clear_authentication();
select tests.delete_supabase_user('user_h');

select is(
  (select count(*) from public.profiles where id = tests.ulid(6)),
  1::bigint, 'P0: G''s profile survives H''s real auth.users deletion'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(6)),
  1::bigint,
  'P0: the entry H logged on G''s profile survives H''s real auth.users deletion'
);
select is(
  (select user_id from public.day_entries where id = tests.ulid(40)),
  tests.get_supabase_uid('user_g'),
  'P0: the entry is re-homed to G (the profile''s actual owner), so the auth.users cascade no longer reaches it'
);
select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(40)),
  null,
  'P0: logged_by_user_id still nulls out via its own on-delete-set-null FK once H''s auth.users row is gone'
);

-- ---------------------------------------------------------------------------
-- 9. #17 P1 item 5: public.rehome_stray_day_entries(uuid) - the re-home
--    logic extracted into its own callable function so the delete-account
--    Edge Function can call it a second time, standalone, immediately
--    before auth.admin.deleteUser (narrowing, not closing, the window
--    between delete_account_data()'s one-time re-home and the actual
--    auth.users removal - see
--    20260906120000_account_deletion_final_rehome.sql).
--
--    #17 P1 round 2 fix: this function used to take no arguments, read
--    auth.uid(), and be EXECUTE-granted to authenticated - which let ANY
--    authenticated caller, including a guardian already revoked from a
--    family, re-stamp last_modified_by_user_id on that family's
--    day_entries rows directly (a revocation-bypass class of bug closed
--    elsewhere in this repo, #81/#82). It now takes an explicit
--    p_user_id and authenticated holds no EXECUTE at all - only
--    delete_account_data()'s own internal call and a service-role caller
--    can reach it. The tests below assert the closed-off grant and prove
--    the update logic itself via service_role, mirroring how the
--    delete-account Edge Function actually calls it.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_proc
     where proname = 'rehome_stray_day_entries'
       and pronamespace = 'public'::regnamespace
  ),
  'public.rehome_stray_day_entries(uuid) exists'
);

select is(
  (select prosecdef from pg_proc
    where proname = 'rehome_stray_day_entries' and pronamespace = 'public'::regnamespace),
  true,
  'rehome_stray_day_entries is security definer'
);

select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'rehome_stray_day_entries' and pronamespace = 'public'::regnamespace
       and c.setting like 'search_path=%'
  ),
  'rehome_stray_day_entries sets search_path = '''''
);

select ok(
  not has_function_privilege('authenticated', 'public.rehome_stray_day_entries(uuid)', 'execute'),
  'authenticated cannot execute rehome_stray_day_entries (#17 P1 round 2 fix: the revocation bypass this closes)'
);

select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'rehome_stray_day_entries'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole or a.grantee = 'authenticated'::regrole)),
  0::bigint,
  'PUBLIC, anon, and authenticated hold no EXECUTE on rehome_stray_day_entries'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.rehome_stray_day_entries('00000000-0000-0000-0000-000000000001'::uuid)$$,
  '42501', null,
  'anon cannot execute rehome_stray_day_entries'
);

-- Direct behavior fixture: a caregiver logs an entry on a profile they
-- don't own, standing in for a write that lands *after*
-- delete_account_data()'s own one-time re-home has already run (the #17 P1
-- item 5 race) - this is what the Edge Function's second, standalone call
-- catches.
select tests.create_supabase_user('user_i'); -- owner
select tests.create_supabase_user('user_j'); -- caregiver

select tests.authenticate_as('user_i');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(7), 'Riley I', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(7), 'caregiver', 'J',
  'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd', 48
);

select tests.authenticate_as('user_j');
select public.accept_guardian_invitation(
  'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd', 'J'
);

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(41), tests.ulid(7), '2026-09-06', 'UTC', 'medium', '2026-09-06T00:00:00Z',
        tests.get_supabase_uid('user_j'), tests.get_supabase_uid('user_j'));

-- The revocation-bypass this round-2 fix closes: J, still authenticated
-- (not even revoked) with a real JWT, cannot call the function directly
-- even naming themselves - the grant itself is the barrier, not an
-- auth.uid() check the caller could satisfy.
select throws_ok(
  format($$select public.rehome_stray_day_entries(%L::uuid)$$, tests.get_supabase_uid('user_j')),
  '42501', null,
  'authenticated cannot execute rehome_stray_day_entries directly, even naming themselves'
);

-- Only a service-role caller (the Edge Function's admin client in
-- production) can reach it now.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  public.rehome_stray_day_entries(tests.get_supabase_uid('user_j')),
  1::bigint,
  'service_role can call rehome_stray_day_entries, which re-homes the one stray row it finds'
);

select is(
  (select user_id from public.day_entries where id = tests.ulid(41)),
  tests.get_supabase_uid('user_i'),
  'the stray row is re-homed to the profile''s actual owner'
);

select is(
  public.rehome_stray_day_entries(tests.get_supabase_uid('user_j')),
  0::bigint,
  'a second call is idempotent: nothing left to re-home'
);

select throws_ok(
  $$select public.rehome_stray_day_entries(null)$$,
  '22023', null,
  'a null p_user_id is refused rather than silently matching every row'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 10. Issue #5, U4: account deletion cleanup for the three caregiver-alert
--     tables plus profile_reminder_windows and missed_entry_alert_state
--     (the latter added by round-2 review #8 -- missed_entry_alert_state
--     is owned exclusively by scan_missed_entry_reminders(), with no
--     authenticated grants at all, hence the direct service_role inserts
--     below rather than going through RLS).
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_k'); -- owns profile K, co-guardian on nothing else
select tests.create_supabase_user('user_l'); -- owns profile L; co-parent on K, about to delete

select tests.authenticate_as('user_l');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(50), 'Riley L', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.upsert_reminder_window(tests.ulid(50), '2026-09-10', false);
insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000950'::uuid, tests.get_supabase_uid('user_l'), 'token-l-1', 'ios');

select tests.authenticate_as('user_k');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(51), 'Riley K', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(51), 'co_parent', 'L',
  'e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5', 48
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('user_k'), tests.ulid(51), true);

select tests.authenticate_as('user_l');
select public.accept_guardian_invitation(
  'e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5', 'L'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('user_l'), tests.ulid(51), true);
select public.upsert_reminder_window(tests.ulid(51), '2026-09-12', false);

-- Round-2 review #8: missed_entry_alert_state markers -- two of L's own
-- (one on the profile L owns, one on the profile L merely co-guards) and
-- one of K's own on the co-guarded profile, which must survive L's account
-- deletion below (same "own row only" rule notification_preferences
-- already proves).
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
values
  (tests.ulid(50), tests.get_supabase_uid('user_l'), '2026-09-05'),
  (tests.ulid(51), tests.get_supabase_uid('user_l'), '2026-09-06'),
  (tests.ulid(51), tests.get_supabase_uid('user_k'), '2026-09-07');

-- K logs an entry: both guardians have alert_on_log, so L (not the writer)
-- gets an outbox row.
select tests.authenticate_as('user_k');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(510), tests.ulid(51), '2026-09-01', 'UTC', 'none', now(),
        tests.get_supabase_uid('user_k'), tests.get_supabase_uid('user_k'));

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select is(
  (select count(*) from public.notification_outbox where recipient_user_id = tests.get_supabase_uid('user_l')),
  1::bigint,
  'fixture: L has one pending outbox row for profile K before deleting'
);

-- L deletes their own account. Read the jsonb result back (pg_temp.snap is
-- SECURITY INVOKER over a session-temp table with no service_role grant)
-- before switching role for the cross-user visibility checks below.
select tests.authenticate_as('user_l');
select pg_temp.snapshot('l_result', public.delete_account_data());

select is(
  pg_temp.snap('l_result') -> 'notification_preferences', '1'::jsonb,
  'U4: result includes a non-zero notification_preferences count'
);
select is(
  pg_temp.snap('l_result') -> 'push_devices', '1'::jsonb,
  'U4: result includes a non-zero push_devices count'
);
select is(
  pg_temp.snap('l_result') -> 'notification_outbox', '1'::jsonb,
  'U4: result includes a non-zero notification_outbox count'
);
select is(
  pg_temp.snap('l_result') -> 'profile_reminder_windows', '1'::jsonb,
  'U4: result includes a non-zero profile_reminder_windows count (L''s own profile)'
);
select is(
  pg_temp.snap('l_result') -> 'missed_entry_alert_state', '2'::jsonb,
  '#8: result includes L''s two missed_entry_alert_state markers (one on each profile)'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*) from public.notification_preferences where user_id = tests.get_supabase_uid('user_l')),
  0::bigint,
  'U4: after delete_account_data, the caller has zero notification_preferences rows'
);
select is(
  (select count(*) from public.push_devices where user_id = tests.get_supabase_uid('user_l')),
  0::bigint,
  'U4: after delete_account_data, the caller has zero push_devices rows'
);
select is(
  (select count(*) from public.notification_outbox where recipient_user_id = tests.get_supabase_uid('user_l')),
  0::bigint,
  'U4: after delete_account_data, the caller has zero notification_outbox rows'
);
select is(
  (select count(*) from public.notification_preferences
    where profile_id = tests.ulid(51) and user_id = tests.get_supabase_uid('user_k')),
  1::bigint,
  'U4: a co-guardian''s preference row on a profile the deleted caller also guarded survives'
);
select is(
  (select count(*) from public.profile_reminder_windows where profile_id = tests.ulid(50)),
  0::bigint,
  'U4: profile_reminder_windows for a profile the caller owned is gone'
);
select is(
  (select count(*) from public.profile_reminder_windows where profile_id = tests.ulid(51)),
  1::bigint,
  'U4: profile_reminder_windows for a profile the caller merely guarded survives'
);
select is(
  (select count(*) from public.missed_entry_alert_state where user_id = tests.get_supabase_uid('user_l')),
  0::bigint,
  '#8: after delete_account_data, the caller has zero missed_entry_alert_state rows, on either profile'
);
select is(
  (select count(*) from public.missed_entry_alert_state
    where profile_id = tests.ulid(51) and user_id = tests.get_supabase_uid('user_k')),
  1::bigint,
  '#8: a co-guardian''s missed_entry_alert_state marker on a profile the deleted caller also guarded survives'
);

-- ---------------------------------------------------------------------------
-- 11. Issue #5, U4: revoke_guardian removes the revoked guardian's
--     preference row and unsent outbox rows for that profile, but not for a
--     different profile they still guard.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_n'); -- owner of profile N
select tests.create_supabase_user('user_o'); -- owner of profile O, also guards N

select tests.authenticate_as('user_o');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(52), 'Riley O', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('user_o'), tests.ulid(52), true);

select tests.authenticate_as('user_n');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(53), 'Riley N', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(53), 'co_parent', 'O',
  'f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6', 48
);

select tests.authenticate_as('user_o');
select public.accept_guardian_invitation(
  'f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6', 'O'
);
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('user_o'), tests.ulid(53), true);

-- Round-2 review #8: a missed_entry_alert_state marker for O on each
-- profile, mirroring the notification_preferences fixture immediately
-- above -- one on the profile being revoked from, one on a different
-- profile O still guards.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
values
  (tests.ulid(53), tests.get_supabase_uid('user_o'), '2026-09-08'),
  (tests.ulid(52), tests.get_supabase_uid('user_o'), '2026-09-09');

select tests.authenticate_as('user_n');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(530), tests.ulid(53), '2026-09-01', 'UTC', 'none', now(),
        tests.get_supabase_uid('user_n'), tests.get_supabase_uid('user_n'));

select public.revoke_guardian(tests.ulid(53), tests.get_supabase_uid('user_o'));

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*) from public.notification_preferences
    where profile_id = tests.ulid(53) and user_id = tests.get_supabase_uid('user_o')),
  0::bigint,
  'U4: after revoke_guardian, the revoked guardian''s preference row for that profile is gone'
);
select is(
  (select count(*) from public.notification_outbox
    where profile_id = tests.ulid(53) and recipient_user_id = tests.get_supabase_uid('user_o')),
  0::bigint,
  'U4: after revoke_guardian, the revoked guardian''s unsent outbox rows for that profile are gone'
);
select is(
  (select count(*) from public.notification_preferences
    where profile_id = tests.ulid(52) and user_id = tests.get_supabase_uid('user_o')),
  1::bigint,
  'U4: the revoked guardian''s preference row for a different profile they still guard survives'
);
select is(
  (select count(*) from public.missed_entry_alert_state
    where profile_id = tests.ulid(53) and user_id = tests.get_supabase_uid('user_o')),
  0::bigint,
  '#8: after revoke_guardian, the revoked guardian''s missed_entry_alert_state marker for that profile is gone'
);
select is(
  (select count(*) from public.missed_entry_alert_state
    where profile_id = tests.ulid(52) and user_id = tests.get_supabase_uid('user_o')),
  1::bigint,
  '#8: the revoked guardian''s missed_entry_alert_state marker for a different profile they still guard survives'
);

select tests.clear_authentication();

select * from finish();
rollback;
