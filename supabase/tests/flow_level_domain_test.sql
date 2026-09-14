-- Coverage for Issue #303 (P2, epic: backend-data): the single
-- source-of-truth `public.flow_level` SQL domain (backed by
-- `public.is_valid_flow_level()`) that `day_entries.flow`, `sync_push`,
-- and `bulk_import_entries` now all validate against instead of three
-- hand-kept copies of the same seven-value allow-list
-- (`20260915130000_data_consistency_bundle.sql`). `flow_model_test.sql`
-- already covers the migration-era `super_heavy`/`not_bleeding` round trip
-- and `bulk_import_test.sql` already covers the exact `flow is not a known
-- level` rejection reason -- this file proves the *mechanism* (the domain,
-- its backing function, and the retyped column) rather than duplicating
-- that per-feature coverage.
begin;
select plan(14);

-- ---------------------------------------------------------------------------
-- 1. is_valid_flow_level(): the single literal allow-list, in one place.
--    Paired with test/domain/models/flow_level_test.dart's identical
--    literal list -- neither is derived from the other, but a future edit
--    to either list without the other breaks one suite or the other,
--    which is the drift guard the issue asks for.
-- ---------------------------------------------------------------------------
select is(public.is_valid_flow_level('none'), true, 'is_valid_flow_level(none) is true');
select is(public.is_valid_flow_level('spotting'), true, 'is_valid_flow_level(spotting) is true');
select is(public.is_valid_flow_level('not_bleeding'), true, 'is_valid_flow_level(not_bleeding) is true');
select is(public.is_valid_flow_level('light'), true, 'is_valid_flow_level(light) is true');
select is(public.is_valid_flow_level('medium'), true, 'is_valid_flow_level(medium) is true');
select is(public.is_valid_flow_level('heavy'), true, 'is_valid_flow_level(heavy) is true');
select is(public.is_valid_flow_level('super_heavy'), true, 'is_valid_flow_level(super_heavy) is true');
select is(public.is_valid_flow_level('torrential'), false, 'is_valid_flow_level rejects an unrecognised value');

-- ---------------------------------------------------------------------------
-- 2. The domain itself: exists, text-based, backs day_entries.flow, and
--    is the single place the allow-list is declared (the old table CHECK
--    is gone).
-- ---------------------------------------------------------------------------
select is(
  (select typname from pg_type
    where typname = 'flow_level' and typnamespace = 'public'::regnamespace),
  'flow_level',
  'public.flow_level domain exists'
);

select is(
  (select t.typbasetype::regtype::text from pg_type t
    where t.typname = 'flow_level' and t.typnamespace = 'public'::regnamespace),
  'text',
  'flow_level is backed by text'
);

-- information_schema.columns reports a domain-typed column's underlying
-- BASE type in data_type/udt_name (a standard information_schema quirk --
-- domains are transparent there); domain_name is the column that actually
-- names the domain itself.
select is(
  (select domain_name from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'flow'),
  'flow_level',
  'day_entries.flow is now typed as the flow_level domain'
);

select is(
  (select count(*) from pg_catalog.pg_constraint
    where conrelid = 'public.day_entries'::regclass
      and conname = 'day_entries_flow_check'),
  0::bigint,
  'day_entries_flow_check no longer exists -- the domain is now the single place flow is validated (AC1)'
);

-- ---------------------------------------------------------------------------
-- 3. A raw insert of a domain-invalid value is still rejected with the
--    same sqlstate (23514, check_violation) a table CHECK would have
--    given -- now enforced automatically by the domain on every write
--    path, not only sync_push's own validation.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('flow303');
select tests.authenticate_as('flow303');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(30300), 'Riley', true, 0, '2026-09-08T00:00:00Z', '2026-09-08T00:00:00Z');

select tests.clear_authentication();
select throws_ok(
  format($$insert into public.day_entries
    (id, user_id, profile_id, local_date, tz, flow, updated_at,
     logged_by_user_id, last_modified_by_user_id)
    values (%L, %L, %L, '2026-09-08', 'UTC', 'torrential', now(), %L, %L)$$,
    tests.ulid(30301), tests.get_supabase_uid('flow303'), tests.ulid(30300),
    tests.get_supabase_uid('flow303'), tests.get_supabase_uid('flow303')),
  '23514',
  null,
  'a raw insert with a domain-invalid flow value is rejected (23514, via the domain now, not a table CHECK)'
);

-- ---------------------------------------------------------------------------
-- 4. sync_push accepts every value in the domain's allow-list, proving its
--    validation is routed through is_valid_flow_level() for the full set
--    (flow_model_test.sql already covers super_heavy/not_bleeding
--    acceptance specifically).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('flow303');
do $$
declare
  v text;
  i int := 0;
begin
  foreach v in array array['none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy'] loop
    i := i + 1;
    perform public.sync_push(
      '[]'::jsonb,
      jsonb_build_array(jsonb_build_object(
        'id', tests.ulid(30310 + i), 'profile_id', tests.ulid(30300),
        'local_date', ('2026-02-' || lpad(i::text, 2, '0')),
        'tz', 'UTC', 'flow', v, 'tags', '[]'::jsonb, 'note', null,
        'updated_at', '2026-09-08T10:00:00Z')));
  end loop;
end $$;
select is(
  (select array_agg(flow::text order by local_date) from public.day_entries
    where profile_id = tests.ulid(30300) and local_date >= '2026-02-01'),
  array['none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy'],
  'sync_push accepts every value in the flow_level domain''s allow-list, routed through is_valid_flow_level()'
);

select tests.clear_authentication();

select * from finish();
rollback;
