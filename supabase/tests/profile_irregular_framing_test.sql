-- Issue #853: `irregular` is a flag composed with the care mode, not a
-- rival value of it. Server-side, that is exactly three things this file
-- pins:
--
--   1. Shape: `profiles.irregular_framing` exists, is a nullable boolean
--      with NO default (null is the meaningful "engine default" state; a
--      `false` default would make every pre-#853 profile read as an
--      explicit off, locking the teen default out).
--   2. Privilege + allowlist: `authenticated` holds UPDATE on the column,
--      and (pinned independently by sync_push_derived_allowlists_test.sql)
--      the derived c_profile_keys covers it -- the column can never be
--      silently un-syncable.
--   3. Behavior at the sync_push surface:
--      a. a payload carrying `irregular_framing` lands it (insert and
--         update paths);
--      b. a payload WITHOUT the key (an old client, or a device that never
--         chose) never clears a stored explicit choice -- the containment
--         guard;
--      c. an explicit JSON null DOES clear back to "engine default"
--         (that is a real, writable tri-state value);
--      d. the legacy `mode = 'irregular'` wire value still parses and
--         stores (profiles_mode_check keeps accepting it; the fold to
--         standard+flag is every CLIENT read boundary's job, plus this
--         migration's one-time data pass -- an old client re-storing the
--         value is harmless and self-heals on the next new-client write).
begin;
select plan(15);

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('ally');
select tests.authenticate_as('ally');

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- ---------------------------------------------------------------------------
-- 1. Shape
-- ---------------------------------------------------------------------------

select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'irregular_framing'),
  'boolean',
  'shape: profiles.irregular_framing exists as a boolean');

select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'irregular_framing'),
  'YES',
  'shape: profiles.irregular_framing is nullable (null = engine default)');

select is(
  (select column_default::text from information_schema.columns
    where table_schema = 'public' and table_name = 'profiles'
      and column_name = 'irregular_framing'),
  null::text,
  'shape: profiles.irregular_framing carries NO default (a false default would read as an explicit off)');

-- ---------------------------------------------------------------------------
-- 2. Privilege (the allowlist coverage itself is pinned by
--    sync_push_derived_allowlists_test.sql)
-- ---------------------------------------------------------------------------

select ok(
  has_column_privilege('authenticated', 'public.profiles', 'irregular_framing', 'UPDATE'),
  'privilege: authenticated may UPDATE profiles.irregular_framing');

-- ---------------------------------------------------------------------------
-- 3a. Insert path: a payload carrying the flag lands it; one without it
--     lands null (engine default), never false.
-- ---------------------------------------------------------------------------

insert into r select 'p_flagged', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Flagged Teen',
    'mode', 'teen', 'irregular_framing', true,
    'updated_at', '2026-09-10T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('p_flagged') -> 'rejected', '[]'::jsonb,
  'insert: a row carrying irregular_framing=true is accepted');
select is((select irregular_framing from public.profiles where id = tests.ulid(1)), true,
  'insert: irregular_framing=true landed');

insert into r select 'p_plain', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Plain Profile',
    'updated_at', '2026-09-10T09:00:00Z')),
  '[]'::jsonb);
select is((select irregular_framing from public.profiles where id = tests.ulid(2)), null::boolean,
  'insert: an absent key lands null (engine default), never false');

-- ---------------------------------------------------------------------------
-- 3b. Containment guard: a newer push WITHOUT the key never clears a
--     stored explicit choice.
-- ---------------------------------------------------------------------------

insert into r select 'u_nokey', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Flagged Teen',
    'updated_at', '2026-09-11T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('u_nokey') -> 'rejected', '[]'::jsonb,
  'update: a newer row without the key is accepted');
select is((select irregular_framing from public.profiles where id = tests.ulid(1)), true,
  'update: the absent key preserved the stored explicit true');

-- 3c. An explicit JSON null IS a writable value: it clears back to the
-- engine default.
insert into r select 'u_null', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Flagged Teen',
    'irregular_framing', null,
    'updated_at', '2026-09-12T09:00:00Z')),
  '[]'::jsonb);
select is((select irregular_framing from public.profiles where id = tests.ulid(1)), null::boolean,
  'update: an explicit null clears back to the engine default');

-- An explicit false lands too (the operator override in the other
-- direction).
insert into r select 'u_false', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Flagged Teen',
    'irregular_framing', false,
    'updated_at', '2026-09-13T09:00:00Z')),
  '[]'::jsonb);
select is((select irregular_framing from public.profiles where id = tests.ulid(1)), false,
  'update: an explicit false overrides the engine default');

-- ---------------------------------------------------------------------------
-- 3d. The legacy rival wire value still parses and stores (the CHECK is
--     deliberately unchanged; the fold is client-side + this migration's
--     one-time data pass).
-- ---------------------------------------------------------------------------

insert into r select 'p_legacy', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(3), 'display_name', 'Old Client Profile',
    'mode', 'irregular',
    'updated_at', '2026-09-10T09:00:00Z')),
  '[]'::jsonb);
select is(pg_temp.resp('p_legacy') -> 'rejected', '[]'::jsonb,
  'wire: a legacy mode=irregular push still parses (profiles_mode_check unchanged)');
select is((select mode from public.profiles where id = tests.ulid(3)), 'irregular',
  'wire: the stored value is the caller''s (the fold is every client read boundary''s job)');

-- And the new client's converged write of that same row lands the
-- composed shape (standard + flag), healing the legacy value.
insert into r select 'p_healed', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(3), 'display_name', 'Old Client Profile',
    'mode', 'standard', 'irregular_framing', true,
    'updated_at', '2026-09-14T09:00:00Z')),
  '[]'::jsonb);
select is(
  (select mode from public.profiles where id = tests.ulid(3)), 'standard',
  'wire: a new client write converges the row onto the composed shape (mode)');
select is(
  (select irregular_framing from public.profiles where id = tests.ulid(3)), true,
  'wire: a new client write converges the row onto the composed shape (flag)');

select * from finish();
rollback;
