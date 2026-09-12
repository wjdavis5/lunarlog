-- Coverage for public.account_deletion_progress (Issue #527's schema half;
-- 20260913021000_account_deletion_progress.sql). The delete-account Edge
-- Function's use of this table (skipping Steps 3/6 on a retry once
-- apple_revoked_at is set) is covered by `deno test`
-- (delete-account/index.test.ts), not here - this file only pins the
-- table's own shape, RLS, and cascade behavior.
begin;
select plan(6);

select tests.rls_forced('public', 'account_deletion_progress');

select tests.create_supabase_user('deleting_user');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.account_deletion_progress (user_id, apple_revoked_at)
values (tests.get_supabase_uid('deleting_user'), now());

select is(
  (select count(*) from public.account_deletion_progress
    where user_id = tests.get_supabase_uid('deleting_user')),
  1::bigint,
  'service_role can write an account_deletion_progress row'
);

-- user_id is the primary key: a second row for the same user_id conflicts,
-- matching the Edge Function's own upsert-by-user_id usage.
select throws_ok(
  format(
    $$insert into public.account_deletion_progress (user_id) values (%L)$$,
    tests.get_supabase_uid('deleting_user')
  ),
  '23505', null,
  'user_id is the primary key - a second insert for the same user conflicts rather than silently duplicating'
);

select tests.authenticate_as('deleting_user');
select throws_ok(
  $$select count(*) from public.account_deletion_progress$$,
  '42501', null,
  'authenticated has no grant at all on account_deletion_progress, even for their own user_id'
);
select throws_ok(
  format(
    $$update public.account_deletion_progress set apple_revoked_at = null where user_id = %L$$,
    tests.get_supabase_uid('deleting_user')
  ),
  '42501', null,
  'authenticated cannot write account_deletion_progress either'
);

-- Deleting the auth.users row cascades the progress marker away (it should
-- never survive the user it was bookkeeping for).
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select tests.delete_supabase_user('deleting_user');

select is(
  (select count(*) from public.account_deletion_progress),
  0::bigint,
  'deleting the auth.users row cascades its account_deletion_progress marker'
);

rollback;
