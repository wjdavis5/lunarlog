-- pgTAP pre-test hook for lunarlog (runs first: pg_prove sorts files by name).
--
-- Self-contained test helpers in the `tests` schema, API-compatible with the
-- subset of basejump/supabase_test_helpers the other files use
-- (tests.create_supabase_user, tests.get_supabase_uid, tests.authenticate_as,
-- tests.clear_authentication, tests.rls_enabled). The dbdev/basejump install
-- needs an outbound HTTP call from inside the database container to
-- api.database.dev, which is not something CI should depend on, so the
-- helpers are inlined here instead. They are created outside a transaction
-- so they persist for the following files; they only ever exist in the local
-- test database (never in a migration).

create extension if not exists pgtap with schema extensions;

create schema if not exists tests;
grant usage on schema tests to anon, authenticated, service_role;

-- Creates a confirmed auth user tagged with `identifier` and returns its uuid.
create or replace function tests.create_supabase_user(
  identifier text,
  email text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, email_change,
    email_change_token_new, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
    coalesce(email, v_uid::text || '@test.local'), 'not-a-real-hash',
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('test_identifier', identifier),
    now(), now(), '', '', '', ''
  );
  return v_uid;
end;
$$;

-- Looks up the uuid of a user created by tests.create_supabase_user.
create or replace function tests.get_supabase_uid(identifier text)
returns uuid
language sql
security definer
set search_path = ''
as $$
  select id from auth.users
  where raw_user_meta_data ->> 'test_identifier' = identifier
  limit 1;
$$;

-- Switches the transaction to the `authenticated` role with a JWT claim set
-- whose `sub` is the user's uuid, exactly as PostgREST would.
create or replace function tests.authenticate_as(identifier text)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := tests.get_supabase_uid(identifier);
begin
  if v_uid is null then
    raise exception 'no test user with identifier %', identifier;
  end if;
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Switches the transaction to the `anon` role with no claims.
create or replace function tests.authenticate_as_anon()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);
end;
$$;

-- Returns to the session's own role (postgres) with no claims.
create or replace function tests.clear_authentication()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'none', true);
end;
$$;

-- pgTAP assertion: every ordinary table in the schema has RLS enabled.
create or replace function tests.rls_enabled(testing_schema text)
returns text
language sql
as $$
  select is(
    (select count(*)::integer
       from pg_catalog.pg_class pc
       join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      where pn.nspname = rls_enabled.testing_schema
        and pc.relkind = 'r'
        and pc.relrowsecurity = false),
    0,
    'All tables in the ' || testing_schema || ' schema should have row level security enabled');
$$;

-- pgTAP assertion: one table has RLS enabled.
create or replace function tests.rls_enabled(testing_schema text, testing_table text)
returns text
language sql
as $$
  select is(
    (select count(*)::integer
       from pg_catalog.pg_class pc
       join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      where pn.nspname = rls_enabled.testing_schema
        and pc.relname = rls_enabled.testing_table
        and pc.relkind = 'r'
        and pc.relrowsecurity = true),
    1,
    testing_schema || '.' || testing_table || ' should have row level security enabled');
$$;

-- pgTAP assertion: one table has RLS forced (applies to the owner too).
create or replace function tests.rls_forced(testing_schema text, testing_table text)
returns text
language sql
as $$
  select is(
    (select count(*)::integer
       from pg_catalog.pg_class pc
       join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      where pn.nspname = rls_forced.testing_schema
        and pc.relname = rls_forced.testing_table
        and pc.relkind = 'r'
        and pc.relforcerowsecurity = true),
    1,
    testing_schema || '.' || testing_table || ' should have row level security forced');
$$;

-- Deterministic valid ULID for fixtures: a fixed 23-char prefix plus `n`
-- encoded as three Crockford base32 digits (n in 0..32767).
create or replace function tests.ulid(n integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select '01ARZ3NDEKTSV4RRFFQ69G5'
    || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', ((n / 1024) % 32) + 1, 1)
    || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', ((n / 32) % 32) + 1, 1)
    || substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', (n % 32) + 1, 1);
$$;

-- The helpers are called while the transaction is running as `authenticated`
-- or `anon`, so those roles need EXECUTE.
grant execute on all functions in schema tests to anon, authenticated, service_role;

-- Verify the hook itself with a no-op test.
begin;
select plan(1);
select ok(true, 'Pre-test hook completed successfully');
select * from finish();
rollback;
