-- request_account_deletion proof (U1; R14): the cascade removes the
-- caller's server rows plus the auth user, leaves other owners untouched,
-- and refuses anonymous and unauthenticated callers without removing
-- anything.
begin;
select plan(13);

-- The cascade is a deliberate, reviewed security-definer exception: it must
-- stay definer with an empty search path, executable by authenticated only.
select is(
  (select count(*)::integer from pg_catalog.pg_proc p
     join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'request_account_deletion'
     and p.prosecdef
     and pg_catalog.pg_get_function_identity_arguments(p.oid) = ''),
  1, 'request_account_deletion is a zero-arg security-definer function');
select ok(
  has_function_privilege('authenticated', 'public.request_account_deletion()', 'execute'),
  'authenticated may execute request_account_deletion');
select ok(
  not has_function_privilege('anon', 'public.request_account_deletion()', 'execute'),
  'anon may not execute request_account_deletion');
select ok(
  not has_function_privilege('public', 'public.request_account_deletion()', 'execute'),
  'public may not execute request_account_deletion');

-- ---------------------------------------------------------------------------
-- Fixtures: users A and B each own one profile, one day entry, one setting.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('del_a');
select tests.create_supabase_user('del_b');

create temp table del_uids (name text primary key, uid uuid);
insert into del_uids
  select 'a', tests.get_supabase_uid('del_a')
  union all
  select 'b', tests.get_supabase_uid('del_b');

select tests.authenticate_as('del_a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
  values (tests.ulid(101), 'Alice', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
  values (tests.ulid(102), tests.ulid(101), '2026-09-01', 'UTC', 'light', '2026-09-01T10:00:00Z');
insert into public.settings (key, value) values ('theme', 'dark');
select tests.clear_authentication();

select tests.authenticate_as('del_b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
  values (tests.ulid(111), 'Bob', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
  values (tests.ulid(112), tests.ulid(111), '2026-09-01', 'UTC', 'none', '2026-09-01T10:00:00Z');
insert into public.settings (key, value) values ('lang', 'en');
select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- Anonymous and unauthenticated callers are refused and remove nothing.
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.request_account_deletion()$$,
  '42501', null, 'anon cannot run the deletion cascade');
select tests.clear_authentication();
select is((select count(*) from public.profiles), 2::bigint,
  'no profile removed by the refused anon call');
select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- As A, the cascade removes A's server rows plus the auth user, and B is
-- untouched.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('del_a');
select lives_ok(
  $$select public.request_account_deletion()$$,
  'the owner''s cascade runs');
select tests.clear_authentication();

select is((select count(*) from public.profiles where user_id = (select uid from del_uids where name = 'a')),
  0::bigint, 'A''s profiles are gone');
select is((select count(*) from public.day_entries where user_id = (select uid from del_uids where name = 'a')),
  0::bigint, 'A''s day entries are gone');
select is((select count(*) from public.settings where user_id = (select uid from del_uids where name = 'a')),
  0::bigint, 'A''s settings are gone');
select is((select count(*) from auth.users where id = (select uid from del_uids where name = 'a')),
  0::bigint, 'A''s auth user is gone');
select is((select count(*) from public.profiles where user_id = (select uid from del_uids where name = 'b')),
  1::bigint, 'B''s profile survives');
select is((select count(*) from auth.users where id = (select uid from del_uids where name = 'b')),
  1::bigint, 'B''s auth user survives');

select * from finish();
rollback;
