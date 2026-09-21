-- Coverage for Issue #845: the minimum-age acknowledgement as a synced,
-- owner-only account consent record.
--
-- Pins: the table shape (CHECK, RLS forced, owner-only policies, no delete),
-- the record_minimum_age_acknowledgement RPC (shape, grants, auth guard,
-- upsert-by-user_id, invalid-consent_via rejection), cross-user RLS
-- isolation, inclusion in export_account_data(), and removal by
-- delete_account_data().
--
-- Fixture style: export_account_data_test.sql / account_deletion_progress_test.sql.
begin;
select plan(35);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- ---------------------------------------------------------------------------
-- 1. Table shape + RLS posture.
-- ---------------------------------------------------------------------------

select tests.rls_forced('public', 'account_consents');
select tests.rls_enabled('public', 'account_consents');

select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.account_consents'::regclass
      and conname = 'account_consents_consent_via_check'),
  1,
  'account_consents carries its consent_via CHECK'
);

select is(
  (select convalidated from pg_constraint
    where conrelid = 'public.account_consents'::regclass
      and conname = 'account_consents_consent_via_check'),
  true,
  'the consent_via CHECK is validated'
);

-- No DELETE policy for authenticated: the row leaves only with the account
-- or through delete_account_data().
select is(
  (select count(*)::integer from pg_policy
    where polrelid = 'public.account_consents'::regclass
      and polcmd = 'd'),
  0,
  'account_consents has no DELETE policy (owner-only select/insert/update only)'
);

select is(
  has_table_privilege('authenticated', 'public.account_consents', 'SELECT'),
  true,
  'authenticated may select its own consent row (RLS-scoped)'
);
select is(
  has_table_privilege('authenticated', 'public.account_consents', 'INSERT'),
  true,
  'authenticated may insert its own consent row (RLS-scoped)'
);
select is(
  has_table_privilege('authenticated', 'public.account_consents', 'UPDATE'),
  true,
  'authenticated may update its own consent row (RLS-scoped)'
);
select is(
  has_table_privilege('authenticated', 'public.account_consents', 'DELETE'),
  false,
  'authenticated has no DELETE privilege on account_consents'
);

-- ---------------------------------------------------------------------------
-- 2. RPC shape + grants.
-- ---------------------------------------------------------------------------

select is(
  (select prosecdef from pg_proc
    where proname = 'record_minimum_age_acknowledgement'
      and pronamespace = 'public'::regnamespace),
  true,
  'record_minimum_age_acknowledgement is security definer'
);

select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'record_minimum_age_acknowledgement'
       and pronamespace = 'public'::regnamespace
       and c.setting = 'search_path=""'
  ),
  'record_minimum_age_acknowledgement pins search_path to exactly empty'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.record_minimum_age_acknowledgement(text, text, text)',
    'execute'),
  'authenticated can execute record_minimum_age_acknowledgement'
);

select is(
  has_function_privilege(
    'anon',
    'public.record_minimum_age_acknowledgement(text, text, text)',
    'execute'),
  false,
  'anon cannot execute record_minimum_age_acknowledgement'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.record_minimum_age_acknowledgement('self_13_plus', '1.0.0+1', 'v1')$$,
  '42501', null,
  'anon is refused at the grant before the body runs'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'authenticated', true);
select throws_ok(
  $$select public.record_minimum_age_acknowledgement('self_13_plus', '1.0.0+1', 'v1')$$,
  '42501', null,
  'an authenticated role with no JWT claims is refused (auth.uid() is null)'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 3. Fixtures: user_a writes, user_b is the isolation target.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('user_a');
select tests.create_supabase_user('user_b');

-- ---------------------------------------------------------------------------
-- 4. RPC round trip + upsert-by-user_id.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
select public.record_minimum_age_acknowledgement('self_13_plus', '1.0.0+1', '2026-09');

select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  1::bigint,
  'the RPC writes exactly one row for the caller'
);
select is(
  (select consent_via from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  'self_13_plus',
  'consent_via round-trips'
);
select isnt(
  (select acknowledged_at from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  null,
  'acknowledged_at is stamped'
);
select is(
  (select policy_version from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  '2026-09',
  'policy_version round-trips'
);

-- Second call is an upsert, not a second row: a policy change re-acknowledges
-- the same account row in place.
select public.record_minimum_age_acknowledgement('parent_invite', '1.1.0+2', '2026-10');

select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  1::bigint,
  'a second acknowledgement upserts the same row (user_id primary key)'
);
select is(
  (select policy_version from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  '2026-10',
  'the upsert overwrites policy_version'
);
select is(
  (select consent_via from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  'parent_invite',
  'the upsert overwrites consent_via'
);

-- An out-of-set consent_via is refused by the RPC's own validation.
select throws_ok(
  $$select public.record_minimum_age_acknowledgement('bogus', '1.0.0+1', '2026-09')$$,
  '22023', null,
  'the RPC rejects an unknown consent_via'
);

-- ---------------------------------------------------------------------------
-- 5. RLS isolation: user_b can neither read nor write user_a's row.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_b');

select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  0::bigint,
  'user_b cannot read user_a''s consent row'
);

select throws_ok(
  format(
    $$insert into public.account_consents
        (user_id, consent_via, acknowledged_at, app_version, policy_version)
      values (%L, 'self_13_plus', now(), '1.0.0+1', '2026-09')$$,
    tests.get_supabase_uid('user_a')
  ),
  '42501', null,
  'user_b cannot insert a consent row for user_a (RLS with-check)'
);

with u as (
  update public.account_consents
     set policy_version = 'hijacked'
   where user_id = tests.get_supabase_uid('user_a')
  returning 1
) select is((select count(*) from u), 0::bigint,
  'user_b''s direct UPDATE of user_a''s row touches 0 rows');

select throws_ok(
  format(
    $$delete from public.account_consents where user_id = %L$$,
    tests.get_supabase_uid('user_a')
  ),
  '42501', null,
  'user_b cannot delete a consent row (no DELETE grant at all)'
);

-- user_b's own row still works through the RPC.
select public.record_minimum_age_acknowledgement('self_13_plus', '1.0.0+1', '2026-09');
select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_b')),
  1::bigint,
  'user_b writes and reads its own consent row'
);

-- ---------------------------------------------------------------------------
-- 6. Export: the caller's own row is included under `account_consents`.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
insert into r select 'a_export', public.export_account_data();

select is(
  (select jsonb_array_length(pg_temp.resp('a_export') -> 'account_consents')),
  1,
  'export_account_data() carries the caller''s account_consents row'
);
select is(
  pg_temp.resp('a_export') -> 'account_consents' -> 0 ->> 'policy_version',
  '2026-10',
  'the exported consent carries the stored policy_version'
);
select is(
  pg_temp.resp('a_export') -> 'account_consents' -> 0 ->> 'consent_via',
  'parent_invite',
  'the exported consent carries the stored consent_via'
);

select tests.authenticate_as('user_b');
insert into r select 'b_export', public.export_account_data();
select is(
  pg_temp.resp('b_export') -> 'account_consents' -> 0 ->> 'user_id',
  tests.get_supabase_uid('user_b')::text,
  'user_b''s export carries only user_b''s own consent row'
);

-- ---------------------------------------------------------------------------
-- 7. Delete: delete_account_data() removes the caller's own row.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
insert into r select 'a_delete', public.delete_account_data();

select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_a')),
  0::bigint,
  'delete_account_data() removes the caller''s consent row'
);
select is(
  pg_temp.resp('a_delete') -> 'account_consents',
  '1'::jsonb,
  'delete_account_data() reports the removed consent count'
);
-- Re-authenticate as user_b: RLS would hide user_b's row from user_a, so
-- the survivor check must run as its owner.
select tests.authenticate_as('user_b');
select is(
  (select count(*) from public.account_consents
    where user_id = tests.get_supabase_uid('user_b')),
  1::bigint,
  'delete_account_data() leaves another user''s consent row untouched'
);

select * from finish();
rollback;
