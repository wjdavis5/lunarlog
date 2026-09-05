-- Proof for the `supabase_realtime` publication migration (plan U2; R2, R3,
-- R5). Verified from pgTAP against catalog state rather than an end-to-end
-- Realtime test, because `AGENTS.md` and `.github/workflows/ci.yml` both
-- start local Supabase with `-x realtime` -- there is no Realtime container
-- in CI to assert against (KTD4). This gives exact, fast coverage of both
-- publication membership and the privacy boundary (KTD2): the negative
-- assertions that `note`/`tags`/`flow` are NOT published are what give that
-- boundary teeth.
begin;
select plan(11);

-- ---------------------------------------------------------------------------
-- Membership: both tables are published.
-- ---------------------------------------------------------------------------
select ok(
  exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'profiles'
  ),
  'public.profiles is a member of supabase_realtime'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'day_entries'
  ),
  'public.day_entries is a member of supabase_realtime'
);

-- ---------------------------------------------------------------------------
-- day_entries: published columns include exactly the RLS/filter/replica-
-- identity columns the coordinator and Realtime need.
-- ---------------------------------------------------------------------------
select ok(
  (select attnames from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'day_entries')
    @> array['id', 'user_id', 'profile_id', 'updated_at', 'deleted_at', 'server_version']::name[],
  'day_entries publishes id, user_id, profile_id, updated_at, deleted_at, server_version'
);

-- ---------------------------------------------------------------------------
-- day_entries: the privacy assertion (KTD2) -- entry content never crosses
-- the websocket. This is the negative check that gives KTD2 teeth.
-- ---------------------------------------------------------------------------
select ok(
  not (
    (select attnames from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'day_entries')
      && array['note', 'tags', 'flow', 'local_date', 'tz']::name[]
  ),
  'day_entries publication excludes note, tags, flow, local_date, and tz'
);

select is(
  (select array_length(attnames, 1) from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'day_entries'),
  6,
  'day_entries publishes exactly 6 columns -- no unexpected additions'
);

-- ---------------------------------------------------------------------------
-- profiles: published columns include what RLS/filtering need and exclude
-- display_name.
-- ---------------------------------------------------------------------------
select ok(
  (select attnames from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles')
    @> array['id', 'user_id', 'updated_at', 'deleted_at', 'server_version']::name[],
  'profiles publishes id, user_id, updated_at, deleted_at, server_version'
);

select ok(
  not (
    (select attnames from pg_catalog.pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles')
      @> array['display_name']::name[]
  ),
  'profiles publication excludes display_name'
);

select is(
  (select array_length(attnames, 1) from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'profiles'),
  5,
  'profiles publishes exactly 5 columns -- no unexpected additions'
);

-- ---------------------------------------------------------------------------
-- Replica identity stays default (primary key), never full -- `full` would
-- restore the excluded columns to the old-row image on UPDATE/DELETE.
-- ---------------------------------------------------------------------------
select is(
  (select relreplident from pg_catalog.pg_class
    where oid = 'public.day_entries'::regclass),
  'd'::"char",
  'day_entries replica identity is default (primary key), not full'
);

select is(
  (select relreplident from pg_catalog.pg_class
    where oid = 'public.profiles'::regclass),
  'd'::"char",
  'profiles replica identity is default (primary key), not full'
);

-- ---------------------------------------------------------------------------
-- Idempotence: re-running the migration's guarded add-table logic is a
-- no-op, not an error (a local `db reset` re-applies every migration).
-- ---------------------------------------------------------------------------
select lives_ok(
  $$
  do $body$
  begin
    if not exists (
      select 1
        from pg_catalog.pg_publication_rel pr
        join pg_catalog.pg_class pc on pc.oid = pr.prrelid
        join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
        join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
       where pp.pubname = 'supabase_realtime'
         and pn.nspname = 'public'
         and pc.relname = 'profiles'
    ) then
      alter publication supabase_realtime
        add table public.profiles (id, user_id, updated_at, deleted_at, server_version);
    end if;

    if not exists (
      select 1
        from pg_catalog.pg_publication_rel pr
        join pg_catalog.pg_class pc on pc.oid = pr.prrelid
        join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
        join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
       where pp.pubname = 'supabase_realtime'
         and pn.nspname = 'public'
         and pc.relname = 'day_entries'
    ) then
      alter publication supabase_realtime
        add table public.day_entries (id, user_id, profile_id, updated_at, deleted_at, server_version);
    end if;
  end $body$;
  $$,
  'the migration''s guarded add-table logic is a no-op on a second run'
);

select * from finish();
rollback;
