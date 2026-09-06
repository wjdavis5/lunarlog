-- RLS coverage for public.push_devices (Issue #5, Unit U1).
begin;
select plan(9);

-- #14 (review fix): see the matching check in
-- notification_preferences_rls_test.sql -- TRUNCATE bypasses RLS entirely.
select is(
  has_table_privilege('authenticated', 'public.push_devices', 'TRUNCATE'),
  false,
  'authenticated cannot TRUNCATE push_devices'
);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');

select tests.rls_forced('public', 'push_devices');

-- 1. A user can insert, update, and delete only their own row.
select tests.authenticate_as('mom');
insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000301'::uuid, tests.get_supabase_uid('mom'), 'token-mom-1', 'ios');

select is(
  (select count(*) from public.push_devices where id = '00000000-0000-0000-0000-000000000301'::uuid),
  1::bigint,
  'A user can insert their own push_devices row'
);

with u as (
  update public.push_devices set platform = 'android' where id = '00000000-0000-0000-0000-000000000301'::uuid returning 1
) select is(count(*), 1::bigint, 'A user can update their own push_devices row') from u;

-- 2. Selecting another user's row returns zero rows.
select tests.authenticate_as('dad');
insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000302'::uuid, tests.get_supabase_uid('dad'), 'token-dad-1', 'android');

select is(
  (select count(*) from public.push_devices where user_id = tests.get_supabase_uid('mom')),
  0::bigint,
  'Selecting another user''s push_devices row returns zero rows'
);

-- 3. Duplicate token violates the unique index.
select throws_ok(
  format(
    $$insert into public.push_devices (id, user_id, token, platform)
      values (gen_random_uuid(), %L::uuid, 'token-mom-1', 'ios')$$,
    tests.get_supabase_uid('dad')
  ),
  '23505', null,
  'Inserting a duplicate token violates the unique index'
);

-- 4. Delete only own row.
select tests.authenticate_as('mom');
with d as (
  delete from public.push_devices where id = '00000000-0000-0000-0000-000000000302'::uuid returning 1
) select is(count(*), 0::bigint, 'A user cannot delete another user''s push_devices row') from d;

with d as (
  delete from public.push_devices where id = '00000000-0000-0000-0000-000000000301'::uuid returning 1
) select is(count(*), 1::bigint, 'A user can delete their own push_devices row') from d;

-- 5. anon has no grant.
select tests.authenticate_as_anon();
select throws_ok(
  $$select * from public.push_devices$$,
  '42501', null,
  'anon has no grant on push_devices'
);

rollback;
