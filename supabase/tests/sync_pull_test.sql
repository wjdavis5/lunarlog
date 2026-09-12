-- Coverage for public.sync_pull(p_cursors jsonb) (Issue #525, server half):
-- tenant scoping (an outsider's profile never appears), cursor filtering,
-- multi-table pages in one call, and the profile_guardians "every guardian
-- on a shared profile, not just the caller's own row" contract.
begin;
select plan(12);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('outsider');

-- ---------------------------------------------------------------------------
-- Function shape and grants.
-- ---------------------------------------------------------------------------
select ok(
  exists (select 1 from pg_proc where proname = 'sync_pull' and pronamespace = 'public'::regnamespace),
  'public.sync_pull(jsonb) exists'
);
select is(
  (select prosecdef from pg_proc where proname = 'sync_pull' and pronamespace = 'public'::regnamespace),
  true,
  'sync_pull is security definer'
);
select ok(
  has_function_privilege('authenticated', 'public.sync_pull(jsonb)', 'execute'),
  'authenticated can execute sync_pull'
);
select ok(
  not has_function_privilege('anon', 'public.sync_pull(jsonb)', 'execute'),
  'anon cannot execute sync_pull'
);

-- ---------------------------------------------------------------------------
-- Setup: mom owns profile 1 (co-parented by dad); outsider owns profile 2.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Riley', 'updated_at', '2026-09-01T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(10), 'profile_id', tests.ulid(1), 'local_date', '2026-09-01',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-01T00:00:00Z'))
);
select public.create_guardian_invitation(
  tests.ulid(1), 'co_parent', 'Dad', repeat('a1', 32), 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(repeat('a1', 32), 'Dad');

select tests.authenticate_as('outsider');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Other Kid', 'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);

-- ---------------------------------------------------------------------------
-- Tenant isolation: mom's pull never returns outsider's profile or entries.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profiles')),
  1,
  'mom''s pull returns exactly one profile (her own)'
);
select is(
  (select (public.sync_pull() -> 'profiles' -> 0 ->> 'id')),
  tests.ulid(1),
  'the returned profile is mom''s own, not the outsider''s'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'day_entries')),
  1,
  'mom''s pull returns exactly one day_entries row (her own profile''s)'
);

-- ---------------------------------------------------------------------------
-- Cursor filtering: a cursor at-or-above the row's server_version excludes
-- it; one strictly below includes it.
-- ---------------------------------------------------------------------------
select is(
  (select jsonb_array_length(
    public.sync_pull(jsonb_build_object('profiles',
      (select server_version from public.profiles where id = tests.ulid(1))
    )) -> 'profiles'
  )),
  0,
  'a cursor at the row''s own server_version excludes it'
);
select is(
  (select jsonb_array_length(
    public.sync_pull(jsonb_build_object('profiles',
      (select server_version - 1 from public.profiles where id = tests.ulid(1))
    )) -> 'profiles'
  )),
  1,
  'a cursor strictly below the row''s server_version includes it'
);

-- ---------------------------------------------------------------------------
-- profile_guardians: every guardian on a shared profile round-trips, not
-- just the caller's own membership row.
-- ---------------------------------------------------------------------------
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_guardians')),
  2,
  'mom''s pull returns BOTH guardians (herself and dad) on the shared profile'
);

-- ---------------------------------------------------------------------------
-- Auth and input validation.
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.sync_pull()$$,
  '42501', null,
  'anon cannot call sync_pull (no EXECUTE grant)'
);

select tests.authenticate_as('mom');
select throws_ok(
  $$select public.sync_pull('[]'::jsonb)$$,
  '22023', null,
  'a non-object p_cursors is rejected'
);

rollback;
