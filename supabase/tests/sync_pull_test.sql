-- Coverage for public.sync_pull(p_cursors jsonb) (Issue #525, server half):
-- tenant scoping (an outsider's profile never appears), cursor filtering,
-- multi-table pages in one call, and the profile_guardians "every guardian
-- on a shared profile, not just the caller's own row" contract.
begin;
select plan(30);

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

-- The outsider's full fixture set (2026-10-10 review finding: nine of the
-- eleven pull branches had no foreign-row assertion): one row in every
-- synced table mom's pull must never return. The day entry goes first so
-- the observation can reference it; the second same-date push gives the
-- resolver a merge event and the history trigger a row, both carrying the
-- outsider's profile_id.
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(20), 'profile_id', tests.ulid(2), 'local_date', '2026-09-02',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-02T00:00:00Z'))
);
select public.sync_push(
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(30), 'day_entry_id', tests.ulid(20), 'profile_id', tests.ulid(2),
    'local_date', '2026-09-02', 'tz', 'UTC', 'category', 'bbt',
    'value_num', 36.5, 'unit', 'celsius', 'updated_at', '2026-09-02T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'profile_id', tests.ulid(2), 'mode', 'tracking',
    'updated_at', '2026-09-02T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(31), 'profile_id', tests.ulid(2), 'cycle_start_date', '2026-08-20',
    'excluded_from_average', false, 'manual_start', false,
    'updated_at', '2026-09-02T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(32), 'profile_id', tests.ulid(2), 'body', 'outsider care note',
    'updated_at', '2026-09-02T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(33), 'profile_id', tests.ulid(2), 'body', 'outsider prep item',
    'is_checked', false, 'updated_at', '2026-09-02T00:00:00Z')),
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(34), 'profile_id', tests.ulid(2), 'code', 'outsider_tag',
    'display_name', 'Outsider tag', 'category', 'custom', 'intensity_enabled', false,
    'updated_at', '2026-09-02T00:00:00Z'))
);
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(21), 'profile_id', tests.ulid(2), 'local_date', '2026-09-02',
    'tz', 'UTC', 'flow', 'medium', 'updated_at', '2026-09-01T00:00:00Z'))
);

-- The fixtures are real: the outsider's own pull carries them. Without
-- this, every "mom sees none" assertion below could pass vacuously.
select is(
  (select jsonb_array_length(public.sync_pull() -> 'observations')), 1,
  'fixture: the outsider''s own pull carries their observation');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_modes')), 1,
  'fixture: the outsider''s own pull carries their profile mode');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'cycle_overrides')), 1,
  'fixture: the outsider''s own pull carries their cycle override');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'care_notes')), 1,
  'fixture: the outsider''s own pull carries their care note');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'visit_prep_items')), 1,
  'fixture: the outsider''s own pull carries their prep item');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_tag_registry')), 1,
  'fixture: the outsider''s own pull carries their registry tag');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'day_entry_merge_events')), 1,
  'fixture: the same-date collision left the outsider a merge event');
select cmp_ok(
  (select jsonb_array_length(public.sync_pull() -> 'day_entry_history')), '>=', 1,
  'fixture: the outsider''s day-entry writes left history rows');
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_guardians')), 1,
  'fixture: the outsider''s own membership rides their pull');

-- ---------------------------------------------------------------------------
-- Tenant isolation: mom's pull never returns the outsider's rows, in ANY of
-- the eleven branches (the 2026-10-10 review found only profiles/day_entries
-- pinned).
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
select is(
  (select jsonb_array_length(public.sync_pull() -> 'observations')), 0,
  'mom''s pull carries no observations rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_modes')), 0,
  'mom''s pull carries no profile_modes rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'cycle_overrides')), 0,
  'mom''s pull carries no cycle_overrides rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'care_notes')), 0,
  'mom''s pull carries no care_notes rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'visit_prep_items')), 0,
  'mom''s pull carries no visit_prep_items rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'profile_tag_registry')), 0,
  'mom''s pull carries no profile_tag_registry rows (the outsider''s stay out)'
);
select is(
  (select jsonb_array_length(public.sync_pull() -> 'day_entry_merge_events')), 0,
  'mom''s pull carries no day_entry_merge_events rows (the outsider''s stay out)'
);
select is(
  (select count(*)::integer from jsonb_array_elements(public.sync_pull() -> 'day_entry_history') e
    where e ->> 'profile_id' = tests.ulid(2)),
  0,
  'mom''s pull carries no day_entry_history rows from the outsider''s profile'
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
select is(
  (select count(*)::integer from jsonb_array_elements(public.sync_pull() -> 'profile_guardians') e
    where e ->> 'profile_id' = tests.ulid(2)),
  0,
  'mom''s pull carries no guardian rows from the outsider''s profile'
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
