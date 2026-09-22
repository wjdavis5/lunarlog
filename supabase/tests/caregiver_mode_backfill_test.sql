-- Issue #850 U3: `caregiver` is retired as a care MODE -- a profile's
-- per-viewer posture is now the guardian *lens* (a membership-identity fact,
-- `lib/domain/sharing/guardian_lens.dart`), so the server runs a one-time
-- data pass folding every stored `mode = 'caregiver'` row to `standard`
-- (20260921120000_caregiver_mode_backfill.sql). This file pins the three
-- server-side guarantees of that change, mirroring the #853 `irregular`
-- precedent (profile_irregular_framing_test.sql):
--
--   1. The backfill converts existing rows. Simulate-then-reconcile
--      (tombstone_flow_clear_test.sql): stand up a legacy `caregiver` row
--      through the real RPC, re-run the migration's exact statement
--      verbatim, assert the fold -- plus a `standard` control row it must
--      not touch, and a second run proving idempotence.
--   2. The legacy `caregiver` wire value still parses and stores.
--      `profiles_mode_check` is deliberately unchanged, so an old-arity
--      `sync_push` carrying `mode='caregiver'` is accepted and stored as-is
--      (the server maps nothing; the client read boundary folds it on
--      read). This is asserted both before and after the backfill.
--   3. The CHECK is still live and still refuses a genuinely out-of-set
--      value -- the retired value is tolerated on purpose, garbage is not.
begin;
select plan(12);

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('ally');
select tests.authenticate_as('ally');

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- 1. Legacy `caregiver` profile through the real RPC, using the OLDEST
--    arity (two arguments) -- exactly what a pre-#850 client sends. The
--    stored value must be the caller's, unmapped.
insert into r select 'p_legacy', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Old Client Caregiver',
    'mode', 'caregiver',
    'updated_at', '2026-09-10T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('p_legacy') -> 'rejected', '[]'::jsonb,
  'wire: an old-arity push carrying mode=caregiver is accepted (profiles_mode_check unchanged)');
select is((select mode from public.profiles where id = tests.ulid(1)), 'caregiver',
  'wire: the legacy value is stored as-is (the fold is the client read boundary''s job)');

-- 2. Control row: an ordinary `standard` profile the backfill must leave
--    alone.
insert into r select 'p_plain', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Plain Standard',
    'mode', 'standard',
    'updated_at', '2026-09-10T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('p_plain') -> 'rejected', '[]'::jsonb,
  'setup: the standard control profile is accepted');
select is((select mode from public.profiles where id = tests.ulid(2)), 'standard',
  'setup: the control profile stores standard');

-- ---------------------------------------------------------------------------
-- 3. The backfill (simulate-then-reconcile): re-run the migration's exact
--    statement verbatim as the migration role and assert the fold.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();

update public.profiles
   set mode = 'standard'
 where mode = 'caregiver';

select is((select mode from public.profiles where id = tests.ulid(1)), 'standard',
  'backfill: a stored caregiver row is converted to standard');
select is((select mode from public.profiles where id = tests.ulid(2)), 'standard',
  'backfill: the standard control row is untouched');

-- Idempotence: the same statement run again matches nothing and changes
-- nothing (an interrupted/replayed migration is a no-op).
update public.profiles
   set mode = 'standard'
 where mode = 'caregiver';
select is((select mode from public.profiles where id = tests.ulid(1)), 'standard',
  'backfill: re-running the statement is idempotent (still standard)');

-- ---------------------------------------------------------------------------
-- 4. The CHECK is still live: it names the legacy value (deliberately
--    tolerated) and still rejects a genuinely out-of-set value.
-- ---------------------------------------------------------------------------
select ok(
  pg_get_constraintdef((
    select oid from pg_catalog.pg_constraint
     where conrelid = 'public.profiles'::regclass
       and conname = 'profiles_mode_check')) like '%caregiver%',
  'check: profiles_mode_check still accepts the legacy caregiver value');

select lives_ok(
  format($$update public.profiles set mode = 'caregiver' where id = %L$$, tests.ulid(1)),
  'check: a raw write to the legacy caregiver value is still permitted');

select throws_ok(
  format($$update public.profiles set mode = 'nonsense' where id = %L$$, tests.ulid(1)),
  '23514',
  null,
  'check: a genuinely out-of-set value is still refused');

-- ---------------------------------------------------------------------------
-- 5. The wire value survives the backfill: an old client's push after the
--    data pass is still accepted and still stored as-is (not silently
--    remapped server-side).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('ally');

insert into r select 'p_old_again', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(3), 'display_name', 'Old Client Still',
    'mode', 'caregiver',
    'updated_at', '2026-09-11T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('p_old_again') -> 'rejected', '[]'::jsonb,
  'wire after backfill: an old-arity push carrying mode=caregiver is still accepted');
select is((select mode from public.profiles where id = tests.ulid(3)), 'caregiver',
  'wire after backfill: the stored value is still the caller''s, unmapped by the server');

select * from finish();
rollback;
