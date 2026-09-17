-- Coverage for 20260915180000_pin_search_path_four_functions.sql
-- (Issue #194, D-3): asserts all four functions the migration pins carry a
-- pinned search_path, that each still behaves correctly afterward (a smoke
-- call per function -- ALTER FUNCTION SET search_path does not change a
-- body, but the whole point of pinning it is that an unqualified reference
-- to something outside pg_catalog would now fail to resolve, so each
-- function is actually invoked here, not just inspected in the catalog),
-- and the repo-wide invariant the issue is really after: every function in
-- `public` has a pinned search_path, with no exceptions -- unlike an
-- earlier draft of this migration, all four known offenders are fixed
-- here, so this assertion needs no allowlist.
begin;
select plan(10);

-- ---------------------------------------------------------------------------
-- Catalog: each of the four functions carries a pinned, empty search_path.
-- ---------------------------------------------------------------------------
select is(
  (select p.proconfig
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'is_valid_tags_array'),
  array['search_path=""']::text[],
  'is_valid_tags_array carries a pinned, empty search_path (Issue #194, D-3)'
);

select is(
  (select p.proconfig
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'resolve_deliver_after'),
  array['search_path=""']::text[],
  'resolve_deliver_after carries a pinned, empty search_path (Issue #194, D-3)'
);

select is(
  (select p.proconfig
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'is_valid_tracking_preferences'),
  array['search_path=""']::text[],
  'is_valid_tracking_preferences carries a pinned, empty search_path (Issue #194, D-3)'
);

select is(
  (select p.proconfig
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'is_valid_flow_level'),
  array['search_path=""']::text[],
  'is_valid_flow_level carries a pinned, empty search_path (Issue #194, D-3)'
);

-- ---------------------------------------------------------------------------
-- Smoke calls: each function still executes and returns the right answer
-- after pinning. ALTER FUNCTION never touched the body, but a pinned
-- search_path is exactly the change that would surface an unqualified
-- reference to something outside pg_catalog, so each is actually invoked,
-- not just inspected in the catalog.
-- ---------------------------------------------------------------------------
select ok(
  public.is_valid_tags_array('["cramps", "bloating"]'::jsonb),
  'is_valid_tags_array still accepts a valid tag array after pinning'
);

select ok(
  not public.is_valid_tags_array('"not-an-array"'::jsonb),
  'is_valid_tags_array still rejects a non-array after pinning'
);

select is(
  public.resolve_deliver_after(
    '2026-01-01T23:00:00+00'::timestamptz, '22:00'::time, '07:00'::time, 'UTC'
  ),
  '2026-01-02T07:00:00+00'::timestamptz,
  'resolve_deliver_after still resolves a wrapped quiet-hours window after pinning'
);

select ok(
  public.is_valid_tracking_preferences('{"period": {"enabled": true, "sort_order": 0}}'::jsonb),
  'is_valid_tracking_preferences still accepts a valid document after pinning'
);

select ok(
  public.is_valid_flow_level('light'),
  'is_valid_flow_level still accepts a valid flow value after pinning'
);

-- ---------------------------------------------------------------------------
-- Repo-wide invariant: every function in `public` has a pinned search_path.
-- No allowlist -- all four known offenders are fixed by this migration.
-- ---------------------------------------------------------------------------
select is(
  (select coalesce(array_agg(p.proname order by p.proname), array[]::name[])
     from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.prokind = 'f'
      and (p.proconfig is null or not exists (
             select 1 from unnest(p.proconfig) c where c like 'search_path=%'
           ))
  ),
  array[]::name[],
  'every function in public has a pinned search_path (Issue #194, D-3)'
);

select * from finish();
rollback;
