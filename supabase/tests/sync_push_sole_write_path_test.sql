-- Coverage for Issue #201: day_entries is no longer directly writable via
-- PostgREST -- sync_push (now SECURITY DEFINER) is the sole write path.
-- Proves the chosen posture (option (a)): a direct insert/update by
-- `authenticated` fails with 42501 (the revoked-grant SQLSTATE, not an RLS
-- decision -- RLS on day_entries is unchanged and still permits these very
-- writes; the grant is what is gone), while sync_push itself is completely
-- unaffected -- still succeeds for an accepted guardian and is still
-- refused for a non-member, proving the DEFINER function's OWN internal
-- auth.uid()/role/membership checks (never RLS) are what carry that weight.
begin;
select plan(11);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('outsider');

-- ---------------------------------------------------------------------------
-- Grants and function shape.
-- ---------------------------------------------------------------------------
select ok(
  not has_table_privilege('authenticated', 'public.day_entries', 'insert'),
  'authenticated has no direct insert grant on day_entries (issue #201)'
);
select ok(
  not has_table_privilege('authenticated', 'public.day_entries', 'update'),
  'authenticated has no direct update grant on day_entries (issue #201)'
);
select ok(
  has_table_privilege('authenticated', 'public.day_entries', 'select'),
  'authenticated keeps its select grant on day_entries -- only writes moved'
);
select is(
  (select prosecdef from pg_proc
    where proname = 'sync_push' and pronamespace = 'public'::regnamespace),
  true,
  'sync_push is security definer (issue #201)'
);
select ok(
  has_function_privilege('authenticated',
    'public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute'),
  'authenticated can still execute sync_push'
);
select ok(
  not has_function_privilege('anon',
    'public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute'),
  'anon cannot execute sync_push'
);

-- ---------------------------------------------------------------------------
-- Setup: mom owns a profile with one day entry, via sync_push.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Riley', 'updated_at', '2026-09-01T00:00:00Z')),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(10), 'profile_id', tests.ulid(1), 'local_date', '2026-09-01',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-01T00:00:00Z'))
);

-- ---------------------------------------------------------------------------
-- A direct write by an accepted guardian -- otherwise perfectly
-- well-formed, exactly the shape RLS would have allowed before this
-- migration -- is refused at the grant layer with 42501, never silently
-- applied. This is what closes the correctness gap the issue describes:
-- none of sync_push's invariants (same-date union, the profile-move guard,
-- the batch cap) ever structurally protected this path before.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
           values (%L, %L, '2026-09-02', 'UTC', 'light', now())$$,
    tests.ulid(11), tests.ulid(1)),
  '42501', null,
  'a direct insert on day_entries by an accepted guardian fails with 42501'
);
select throws_ok(
  format($$update public.day_entries set flow = 'heavy' where id = %L$$, tests.ulid(10)),
  '42501', null,
  'a direct update on day_entries by an accepted guardian fails with 42501'
);

-- ---------------------------------------------------------------------------
-- sync_push itself is completely unaffected by the revoke (it runs as its
-- owner, not as `authenticated`) -- still succeeds for the same guardian ...
-- ---------------------------------------------------------------------------
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(10), 'profile_id', tests.ulid(1), 'local_date', '2026-09-01',
    'tz', 'UTC', 'flow', 'heavy', 'updated_at', '2026-09-01T01:00:00Z'))
);
select is(
  (select flow from public.day_entries where id = tests.ulid(10)),
  'heavy',
  'sync_push still succeeds for an accepted guardian after the DEFINER switch'
);

-- ---------------------------------------------------------------------------
-- ... and is still refused for a non-member -- DEFINER bypasses RLS
-- entirely, so this specifically proves sync_push's own role/membership
-- check (v_role_map, derived from auth.uid()) is doing the work now, not
-- a policy RLS would otherwise have enforced for free. sync_push's
-- authorization check runs inside the per-row exception block (same shape
-- as every other per-row validation failure), so an unauthorized row is
-- reported back in `rejected` -- never a thrown exception -- and never
-- stored.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('outsider');
create temp table outsider_push_result (v jsonb);
insert into outsider_push_result select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(12), 'profile_id', tests.ulid(1), 'local_date', '2026-09-03',
    'tz', 'UTC', 'flow', 'light', 'updated_at', '2026-09-03T00:00:00Z')));
select is(
  (select jsonb_array_length(v -> 'rejected') from outsider_push_result),
  1,
  'sync_push refuses (as a per-row rejection) a non-member''s write to someone else''s profile'
);
select is(
  (select count(*) from public.day_entries where id = tests.ulid(12)),
  0::bigint,
  'the refused row from a non-member never lands in day_entries'
);

rollback;
