-- Coverage for public.account_deletion_progress (Issue #527's schema half;
-- 20260913021000_account_deletion_progress.sql; tightened by Issue #605/
-- LLA-051's identity-binding column and CHECK,
-- 20260914103000_account_deletion_cross_guardian_and_identity_fixes.sql).
-- The delete-account Edge Function's use of this table (skipping Steps 3/6
-- on a retry only when apple_revoked_at is set AND apple_identity_id
-- matches the caller's *current* Apple identity) is covered by `deno test`
-- (delete-account/index.test.ts), not here - this file only pins the
-- table's own shape, RLS, and cascade behavior.
begin;
select plan(10);

select tests.rls_forced('public', 'account_deletion_progress');

-- Issue #605/LLA-051 review fix: the identity-required CHECK below is added
-- with a plain `add constraint ... check (...)`, which validates every
-- EXISTING row on deploy, not just future writes - the migration's own
-- `update ... set apple_revoked_at = null where ...` neutralises any
-- legacy row that could not satisfy it first. Pinning both that the
-- constraint exists and that it was actually validated (not left NOT VALID)
-- guards against either half of that fix silently regressing.
select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.account_deletion_progress'::regclass
      and conname = 'account_deletion_progress_identity_required_check'),
  1,
  'the identity-required CHECK constraint exists'
);
select is(
  (select convalidated from pg_constraint
    where conrelid = 'public.account_deletion_progress'::regclass
      and conname = 'account_deletion_progress_identity_required_check'),
  true,
  'the identity-required CHECK constraint is validated, not left NOT VALID'
);

select tests.create_supabase_user('deleting_user');
select tests.create_supabase_user('deleting_user_2');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.account_deletion_progress (user_id, apple_revoked_at, apple_identity_id)
values (tests.get_supabase_uid('deleting_user'), now(), 'apple-sub-abc');

select is(
  (select count(*) from public.account_deletion_progress
    where user_id = tests.get_supabase_uid('deleting_user')),
  1::bigint,
  'service_role can write an account_deletion_progress row'
);

select is(
  (select apple_identity_id from public.account_deletion_progress
    where user_id = tests.get_supabase_uid('deleting_user')),
  'apple-sub-abc',
  'apple_identity_id round-trips alongside apple_revoked_at (Issue #605/LLA-051)'
);

-- Issue #605/LLA-051: a revoked marker with no recorded identity is
-- meaningless (a retry would have nothing to compare its current identity
-- against) - the table CHECK rejects it outright rather than relying on
-- every writer to remember to set both.
select throws_ok(
  format(
    $$insert into public.account_deletion_progress (user_id, apple_revoked_at)
      values (%L, now())$$,
    tests.get_supabase_uid('deleting_user_2')
  ),
  '23514', null,
  'apple_revoked_at set with no apple_identity_id violates the identity-required CHECK'
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
  'deleting the auth.users row cascades its account_deletion_progress marker (and no other row was '
  'ever left behind by the earlier CHECK-violating insert attempt)'
);

select tests.delete_supabase_user('deleting_user_2');

rollback;
