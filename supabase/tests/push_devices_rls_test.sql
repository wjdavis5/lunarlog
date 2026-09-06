-- RLS coverage for public.push_devices (Issue #5, Unit U1). Also covers
-- public.register_push_device() (round-2 review #1 / round-1 #1 half (b),
-- 20260906160000_notification_preferences.sql).
begin;
select plan(15);

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

-- 6-9. register_push_device (round-2 review #1 / round-1 #1 half (b)):
-- reassigns a stale row from a previous account on the same install rather
-- than silently no-oping the way a plain client-side upsert does.

select tests.authenticate_as('mom');
select public.register_push_device(
  '00000000-0000-0000-0000-000000000401'::uuid, 'reg-token-mom', 'ios'
);
select is(
  (select user_id from public.push_devices
    where id = '00000000-0000-0000-0000-000000000401'::uuid),
  tests.get_supabase_uid('mom'),
  'register_push_device inserts a fresh row under the caller'
);

-- Simulates a shared device: dad signs into the same install, whose earlier
-- sign-out deregistration of mom's row never completed (network failure,
-- the ordinary case per the round-2 review). A plain upsert would silently
-- affect zero rows here (RLS denies the update, no insert fallback once the
-- id already exists) -- register_push_device must instead reassign it.
select tests.authenticate_as('dad');
select public.register_push_device(
  '00000000-0000-0000-0000-000000000401'::uuid, 'reg-token-dad', 'android'
);
select is(
  (select user_id from public.push_devices
    where id = '00000000-0000-0000-0000-000000000401'::uuid),
  tests.get_supabase_uid('dad'),
  'register_push_device reassigns a stale id-colliding row to the new caller'
);
select is(
  (select count(*) from public.push_devices
    where id = '00000000-0000-0000-0000-000000000401'::uuid),
  1::bigint,
  'the reassignment leaves exactly one row for this device id, not two'
);

-- Same physical FCM install can also collide on token alone (a fresh device
-- id with the previous account's still-live token) -- push_devices_token_uq
-- would otherwise raise 23505 on the insert. register_push_device must
-- clear the stale token owner's row here too.
select tests.authenticate_as('mom');
select public.register_push_device(
  '00000000-0000-0000-0000-000000000402'::uuid, 'reg-token-shared', 'ios'
);
select tests.authenticate_as('dad');
select public.register_push_device(
  '00000000-0000-0000-0000-000000000403'::uuid, 'reg-token-shared', 'android'
);
select is(
  (select count(*) from public.push_devices
    where id = '00000000-0000-0000-0000-000000000402'::uuid),
  0::bigint,
  'register_push_device deletes a stale token-colliding row owned by someone else'
);
select is(
  (select user_id from public.push_devices
    where id = '00000000-0000-0000-0000-000000000403'::uuid),
  tests.get_supabase_uid('dad'),
  'register_push_device inserts the new caller''s row under the fresh device id'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.register_push_device('00000000-0000-0000-0000-000000000404'::uuid, 'reg-token-anon', 'ios')$$,
  '42501', null,
  'anon has no grant on register_push_device'
);

rollback;
