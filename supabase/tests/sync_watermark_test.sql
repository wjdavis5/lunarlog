-- Coverage for public.sync_watermark() (Issue #521): the commit-safe pull
-- cursor ceiling. A single-connection pgTAP script cannot open a second
-- real concurrent transaction, so the "writer still in flight" scenarios
-- below manipulate public.sync_inflight directly, keyed on THIS script's
-- own txid_current() - which genuinely reports 'in progress' via
-- txid_status() for the whole duration of this still-open transaction, so
-- sync_watermark() evaluates the real predicate, not a mock. authenticated
-- holds no grant on either public.sync_version_seq (USAGE only, no SELECT)
-- or public.sync_inflight (no grant at all - both deliberate, see their
-- migrations) - the helpers below are SECURITY DEFINER (owned by this
-- script's own connecting role, created before any authenticate_as() role
-- switch) so the test can manipulate them directly, exactly like
-- delete_profile_data_test.sql's pg_temp.snapshot/pg_temp.snap pattern.
begin;
select plan(9);

create function pg_temp.seq_last_value() returns bigint
  language sql security definer as $$ select last_value from public.sync_version_seq $$;
create function pg_temp.inflight_set(p_xid bigint, p_min_version bigint) returns void
  language sql security definer as $$
    insert into public.sync_inflight (xid, min_version) values (p_xid, p_min_version)
    on conflict (xid) do update set min_version = excluded.min_version
  $$;
create function pg_temp.inflight_clear(p_xid bigint) returns void
  language sql security definer as $$
    delete from public.sync_inflight where xid = p_xid
  $$;

select tests.create_supabase_user('mom');

-- ---------------------------------------------------------------------------
-- Function shape and grants.
-- ---------------------------------------------------------------------------
select ok(
  exists (select 1 from pg_proc where proname = 'sync_watermark' and pronamespace = 'public'::regnamespace),
  'public.sync_watermark() exists'
);
select is(
  (select prosecdef from pg_proc where proname = 'sync_watermark' and pronamespace = 'public'::regnamespace),
  true,
  'sync_watermark is security definer'
);
select ok(
  has_function_privilege('authenticated', 'public.sync_watermark()', 'execute'),
  'authenticated can execute sync_watermark'
);
select ok(
  not has_function_privilege('anon', 'public.sync_watermark()', 'execute'),
  'anon cannot execute sync_watermark'
);

-- ---------------------------------------------------------------------------
-- Auth.
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.sync_watermark()$$,
  '42501', null,
  'anon is refused (no EXECUTE grant)'
);

-- ---------------------------------------------------------------------------
-- Fixture: one write, so the sequence has a known, fixed last_value for the
-- rest of this test (nothing else in this script calls nextval() again).
-- Then clear the bookkeeping row THIS write's own set_server_version() call
-- created for our own (still-open) transaction, so each scenario below
-- starts from a clean, explicit slate.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Riley', 'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);

create temp table v_snap as select pg_temp.seq_last_value() as v;
select pg_temp.inflight_clear(txid_current());

-- ---------------------------------------------------------------------------
-- Baseline: with nothing in flight, the watermark equals the sequence's
-- current last_value.
-- ---------------------------------------------------------------------------
select is(
  public.sync_watermark(),
  (select v from v_snap),
  'with nothing in-flight, the watermark equals the last issued server_version'
);

-- ---------------------------------------------------------------------------
-- The gap scenario (Issue #521): a writer still holding an OLDER
-- server_version than the sequence's current last_value must cap the
-- watermark BELOW that older value - closing exactly the pull-skip gap the
-- issue reports (a naive `max(server_version)` cursor would instead
-- advance past it).
-- ---------------------------------------------------------------------------
select pg_temp.inflight_set(txid_current(), (select v from v_snap) - 1);

select is(
  public.sync_watermark(),
  (select v from v_snap) - 2,
  'an in-flight writer holding an older version caps the watermark below it (Issue #521)'
);

-- Resolve the synthetic in-flight row (simulating that writer's commit)
-- and confirm the watermark advances again once nothing is in flight.
select pg_temp.inflight_clear(txid_current());

select is(
  public.sync_watermark(),
  (select v from v_snap),
  'once the in-flight writer resolves, the watermark advances to the current last_value again'
);

-- ---------------------------------------------------------------------------
-- hashtextextended: sync_push's advisory lock now uses the int8 variant
-- (collision-astronomically-unlikely) rather than hashtext()'s int4.
-- ---------------------------------------------------------------------------
select ok(
  (select prosrc from pg_proc where proname = 'sync_push' and pronamespace = 'public'::regnamespace)
    like '%hashtextextended%',
  'Issue #521: sync_push''s advisory lock now uses hashtextextended, not hashtext'
);

rollback;
