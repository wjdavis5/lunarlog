-- RLS isolation, privilege, and constraint proof for the three sync tables
-- (plan U2: AE1, AE2, AE12, column-list grants, CHECKs, server_version, anon).
begin;
select plan(52);

-- ---------------------------------------------------------------------------
-- Fixtures: users A and B each own one profile, one day entry, one setting.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('user_a');
select tests.create_supabase_user('user_b');

select tests.authenticate_as('user_a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
  values (tests.ulid(1), 'Alice', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, note, updated_at)
  values (tests.ulid(2), tests.ulid(1), '2026-09-01', 'America/New_York', 'light', '["cramps"]', 'a-note', '2026-09-01T10:00:00Z');
insert into public.settings (key, value) values ('theme', 'dark');
select tests.clear_authentication();

select tests.authenticate_as('user_b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
  values (tests.ulid(11), 'Bob', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
  values (tests.ulid(12), tests.ulid(11), '2026-09-01', 'UTC', 'none', '2026-09-01T10:00:00Z');
insert into public.settings (key, value) values ('lang', 'en');

-- ---------------------------------------------------------------------------
-- RLS enabled and forced on every table
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public');
select tests.rls_forced('public', 'profiles');
select tests.rls_forced('public', 'day_entries');
select tests.rls_forced('public', 'settings');

-- ---------------------------------------------------------------------------
-- AE1: as B, A's rows are invisible, unmodifiable, and cannot be created
-- ---------------------------------------------------------------------------
select is((select count(*) from public.profiles where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'B selects zero of A''s profiles');
select is((select count(*) from public.day_entries where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'B selects zero of A''s day entries');
select is((select count(*) from public.settings where user_id = tests.get_supabase_uid('user_a')),
  0::bigint, 'B selects zero of A''s settings');
select is((select count(*) from public.profiles), 1::bigint, 'B sees only own profile');
select is((select count(*) from public.day_entries), 1::bigint, 'B sees only own day entry');
select is((select count(*) from public.settings), 1::bigint, 'B sees only own setting');

with u as (update public.profiles set display_name = 'pwned' where id = tests.ulid(1) returning 1)
  select is(count(*), 0::bigint, 'B updates zero of A''s profiles') from u;
with u as (update public.day_entries set note = 'pwned' where id = tests.ulid(2) returning 1)
  select is(count(*), 0::bigint, 'B updates zero of A''s day entries') from u;
with u as (update public.settings set value = 'pwned' where key = 'theme' returning 1)
  select is(count(*), 0::bigint, 'B updates zero of A''s settings') from u;

select throws_ok(
  $$insert into public.profiles (id, user_id, display_name, updated_at)
      values (tests.ulid(21), tests.get_supabase_uid('user_a'), 'x', now())$$,
  '42501', null, 'B cannot insert a profile with user_id = A (with check)');
select throws_ok(
  $$insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, updated_at)
      values (tests.ulid(22), tests.get_supabase_uid('user_a'), tests.ulid(1), '2026-09-02', 'UTC', 'none', now())$$,
  '42501', null, 'B cannot insert a day entry with user_id = A (with check)');
select throws_ok(
  $$insert into public.settings (user_id, key, value)
      values (tests.get_supabase_uid('user_a'), 'x', 'y')$$,
  '42501', null, 'B cannot insert a setting with user_id = A (with check)');

select throws_ok($$delete from public.profiles where id = tests.ulid(11)$$,
  '42501', 'permission denied for table profiles', 'delete on profiles is refused at the privilege layer');
select throws_ok($$delete from public.day_entries where id = tests.ulid(12)$$,
  '42501', 'permission denied for table day_entries', 'delete on day_entries is refused at the privilege layer');
select throws_ok($$delete from public.settings where key = 'lang'$$,
  '42501', 'permission denied for table settings', 'delete on settings is refused at the privilege layer');

-- ---------------------------------------------------------------------------
-- AE2: composite FK stops B attaching a day entry to A's profile
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values (tests.ulid(23), tests.ulid(1), '2026-09-02', 'UTC', 'none', now())$$,
  '23503', null, 'B cannot reference A''s profile_id (composite foreign key)');

-- ---------------------------------------------------------------------------
-- AE12: reusing A's ULID lands as B's own row, no unique violation
-- ---------------------------------------------------------------------------
select lives_ok(
  $$insert into public.profiles (id, display_name, updated_at)
      values (tests.ulid(1), 'Bob two', now())$$,
  'B inserts a profile whose id equals A''s ULID as an own row');
select lives_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values (tests.ulid(2), tests.ulid(11), '2026-09-03', 'UTC', 'none', now())$$,
  'B inserts a day entry whose id equals A''s ULID as an own row');
select is((select user_id from public.profiles where id = tests.ulid(1)),
  tests.get_supabase_uid('user_b'), 'the reused profile id is owned by B from B''s view');

-- ---------------------------------------------------------------------------
-- Column-list UPDATE grant: user_id and server_version are not updatable
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.profiles set user_id = tests.get_supabase_uid('user_a') where id = tests.ulid(11)$$,
  '42501', 'permission denied for table profiles', 'B cannot reassign profiles.user_id');
select throws_ok(
  $$update public.profiles set server_version = 1 where id = tests.ulid(11)$$,
  '42501', 'permission denied for table profiles', 'B cannot set profiles.server_version');
select throws_ok(
  $$update public.day_entries set user_id = tests.get_supabase_uid('user_a') where id = tests.ulid(12)$$,
  '42501', 'permission denied for table day_entries', 'B cannot reassign day_entries.user_id');
select throws_ok(
  $$update public.day_entries set server_version = 1 where id = tests.ulid(12)$$,
  '42501', 'permission denied for table day_entries', 'B cannot set day_entries.server_version');
select throws_ok(
  $$update public.settings set user_id = tests.get_supabase_uid('user_a') where key = 'lang'$$,
  '42501', 'permission denied for table settings', 'B cannot reassign settings.user_id');
select throws_ok(
  $$update public.settings set server_version = 1 where key = 'lang'$$,
  '42501', 'permission denied for table settings', 'B cannot set settings.server_version');

-- ---------------------------------------------------------------------------
-- CHECK constraints on direct writes
-- ---------------------------------------------------------------------------
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, note, updated_at)
      values (tests.ulid(31), tests.ulid(11), '2026-09-04', 'UTC', 'none', repeat('n', 2001), now())$$,
  '23514', null, 'note longer than 2000 chars is rejected');
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, updated_at)
      values (tests.ulid(32), tests.ulid(11), '2026-09-04', 'UTC', 'none', '{"a":1}', now())$$,
  '23514', null, 'non-array tags is rejected');
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, updated_at)
      values (tests.ulid(33), tests.ulid(11), '2026-09-04', 'UTC', 'none',
              (select jsonb_agg(to_jsonb('t' || g)) from generate_series(1, 33) g), now())$$,
  '23514', null, 'tags array longer than 32 is rejected');
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values (tests.ulid(34), tests.ulid(11), '2026-09-04', 'UTC', 'gushing', now())$$,
  '23514', null, 'unknown flow is rejected');
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
      values ('not-a-ulid', tests.ulid(11), '2026-09-04', 'UTC', 'none', now())$$,
  '23514', null, 'day entry id that is not a 26-char Crockford ULID is rejected');
select throws_ok(
  $$insert into public.profiles (id, display_name, updated_at)
      values (tests.ulid(35), repeat('d', 81), now())$$,
  '23514', null, 'display_name longer than 80 chars is rejected');
select throws_ok(
  $$insert into public.profiles (id, display_name, updated_at)
      values ('01ARZ3NDEKTSV4RRFFQ69G5FAI', 'x', now())$$,
  '23514', null, 'profile id with a non-Crockford character is rejected');
select throws_ok(
  $$insert into public.settings (key, value) values ('big', repeat('v', 4001))$$,
  '23514', null, 'settings.value longer than 4000 chars is rejected');

-- ---------------------------------------------------------------------------
-- server_version: trigger-assigned, strictly increasing, client value ignored
-- ---------------------------------------------------------------------------
insert into public.profiles (id, display_name, updated_at, server_version)
  values (tests.ulid(41), 'Versioned', now(), 999999);
select isnt((select server_version from public.profiles where id = tests.ulid(41)),
  999999::bigint, 'server_version supplied on insert is overwritten by the trigger');
create temp table sv (n int, v bigint);
insert into sv select 1, server_version from public.profiles where id = tests.ulid(41);
update public.profiles set display_name = 'Versioned 2' where id = tests.ulid(41);
insert into sv select 2, server_version from public.profiles where id = tests.ulid(41);
update public.profiles set display_name = 'Versioned 3' where id = tests.ulid(41);
insert into sv select 3, server_version from public.profiles where id = tests.ulid(41);
select cmp_ok((select v from sv where n = 2), '>', (select v from sv where n = 1),
  'server_version increases on the first update');
select cmp_ok((select v from sv where n = 3), '>', (select v from sv where n = 2),
  'server_version increases on the second update');

-- ---------------------------------------------------------------------------
-- From the owner's view (bypassrls): AE12 rows coexist under both users
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select is((select count(*) from public.profiles where id = tests.ulid(1)), 2::bigint,
  'the same profile ULID exists once per user');
select is((select count(*) from public.day_entries where id = tests.ulid(2)), 2::bigint,
  'the same day entry ULID exists once per user');
select is((select display_name from public.profiles
            where id = tests.ulid(1) and user_id = tests.get_supabase_uid('user_a')),
  'Alice', 'A''s profile is untouched by B''s writes');
select is((select note from public.day_entries
            where id = tests.ulid(2) and user_id = tests.get_supabase_uid('user_a')),
  'a-note', 'A''s day entry is untouched by B''s writes');

-- ---------------------------------------------------------------------------
-- anon and PUBLIC: no access to any table
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok($$select * from public.profiles$$, '42501', null, 'anon cannot read profiles');
select throws_ok($$select * from public.day_entries$$, '42501', null, 'anon cannot read day_entries');
select throws_ok($$select * from public.settings$$, '42501', null, 'anon cannot read settings');
select throws_ok($$insert into public.settings (user_id, key, value) values (gen_random_uuid(), 'k', 'v')$$,
  '42501', null, 'anon cannot insert into settings');
select tests.clear_authentication();

select is((select count(*) from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            cross join lateral aclexplode(coalesce(c.relacl, '{}'::aclitem[])) a
           where n.nspname = 'public' and c.relname in ('profiles', 'day_entries', 'settings')
             and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint, 'PUBLIC and anon hold no privilege on any sync table');
select is((select count(*) from pg_class c
            join pg_namespace n on n.oid = c.relnamespace
            cross join lateral aclexplode(coalesce(c.relacl, '{}'::aclitem[])) a
           where n.nspname = 'public' and c.relname in ('profiles', 'day_entries', 'settings')
             and a.grantee = 'authenticated'::regrole and a.privilege_type in ('DELETE', 'TRUNCATE')),
  0::bigint, 'authenticated holds no DELETE or TRUNCATE privilege on any sync table');
select is((select count(*) from pg_policies
           where schemaname = 'public' and tablename in ('profiles', 'day_entries', 'settings')),
  12::bigint, 'four policies exist on each of the three tables');
select is((select count(*) from pg_policies
           where schemaname = 'public' and tablename in ('profiles', 'day_entries', 'settings')
             and roles <> '{authenticated}'),
  0::bigint, 'every policy is scoped to authenticated');

select * from finish();
rollback;
