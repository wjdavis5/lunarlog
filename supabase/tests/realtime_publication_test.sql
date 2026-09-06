-- Proof for the `supabase_realtime` publication (plan U2 as revised for the
-- PR #92 review; R2, R3, R5). An earlier version of this migration tried to
-- keep entry content off the websocket by publishing `public.day_entries`/
-- `public.profiles` directly with a narrow *publication* column list. That
-- does not work: Realtime's WALRUS decodes with wal2json, which only honors
-- a publication as a table-level membership list -- publication column
-- lists are a pgoutput-only feature and are inert for wal2json/Realtime. The
-- actual filter Realtime applies is `has_column_privilege(...)`, and this
-- schema grants table-wide `select` on `day_entries` to `authenticated`, so
-- a narrow *publication* column list would not have stopped full rows
-- (`note`/`tags`/`flow`) from reaching the websocket.
--
-- The fix verified here: `public.day_entries` and `public.profiles` are
-- never published at all (in any form), and the only table published is
-- `public.sync_signals`, a dedicated table that structurally cannot carry
-- health content (it has exactly two columns: `profile_id`, `updated_at`).
-- `RealtimeSyncCoordinator` treats any event on it purely as a wake signal
-- and always re-reads through the RLS-checked sync pull.
--
-- Verified from pgTAP against catalog state plus trigger behavior, not an
-- end-to-end Realtime test, because `AGENTS.md` and
-- `.github/workflows/ci.yml` both start local Supabase with `-x realtime` --
-- there is no Realtime container in this pgTAP run to assert delivery
-- against. A cloud, non-CI check against the real Realtime container is
-- still required before every merge touching this migration -- see
-- AGENTS.md and README.md's "Known limitations". Catalog-only assertions are
-- exactly the false guarantee the PR #92 review flagged for the old
-- publish-with-column-list approach, so this file additionally proves the
-- *behavioral* half: that profiles/day_entries writes actually populate
-- `sync_signals` (the trigger path Realtime's payload would ride on), and
-- that a non-guardian cannot read another family's signal rows.
begin;
select plan(28);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('stranger');

-- ---------------------------------------------------------------------------
-- RLS: sync_signals is enabled + forced, same as every other table here.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'sync_signals');
select tests.rls_forced('public', 'sync_signals');

-- ---------------------------------------------------------------------------
-- Publication membership: sync_signals is published; day_entries and
-- profiles are NOT -- the core assertion that gives this fix teeth. Unlike
-- the superseded column-list approach, this is a true privacy boundary:
-- wal2json only decodes tables that are publication members at all.
-- ---------------------------------------------------------------------------
select ok(
  exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'sync_signals'
  ),
  'public.sync_signals is a member of supabase_realtime'
);

select ok(
  not exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'day_entries'
  ),
  'public.day_entries is NOT published -- wal2json/WALRUS never decodes it, '
  || 'so note/tags/flow cannot reach the websocket via this mechanism'
);

select ok(
  not exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'profiles'
  ),
  'public.profiles is NOT published'
);

-- ---------------------------------------------------------------------------
-- sync_signals publishes exactly profile_id and updated_at -- belt-and-
-- braces on top of the table only having those two columns to begin with.
-- ---------------------------------------------------------------------------
select ok(
  (select attnames from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_signals')
    @> array['profile_id', 'updated_at']::name[],
  'sync_signals publishes profile_id and updated_at'
);

select is(
  (select array_length(attnames, 1) from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_signals'),
  2,
  'sync_signals publishes exactly 2 columns -- no unexpected additions'
);

-- ---------------------------------------------------------------------------
-- sync_signals itself carries no health-content columns at all, structurally
-- (not just "not published") -- so even a future whole-table publish of it
-- could not leak note/tags/flow.
-- ---------------------------------------------------------------------------
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'sync_signals'),
  2,
  'sync_signals has exactly 2 columns total (profile_id, updated_at)'
);

-- ---------------------------------------------------------------------------
-- Privileges: no direct client write to sync_signals -- only the SECURITY
-- DEFINER trigger populates it.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(401), 'Test Child', true, 0, now(), now());

select throws_ok(
  $$insert into public.sync_signals (profile_id, updated_at) values (tests.ulid(999), now())$$,
  '42501', null, 'authenticated cannot insert into sync_signals directly'
);
select throws_ok(
  $$update public.sync_signals set updated_at = now() where profile_id = tests.ulid(401)$$,
  '42501', null, 'authenticated cannot update sync_signals directly'
);
select throws_ok(
  $$delete from public.sync_signals where profile_id = tests.ulid(401)$$,
  '42501', null, 'authenticated cannot delete from sync_signals directly'
);

-- ---------------------------------------------------------------------------
-- Behavioral proof: inserting a profile touches its sync_signals row (the
-- profiles trigger).
-- ---------------------------------------------------------------------------
select ok(
  exists(select 1 from public.sync_signals where profile_id = tests.ulid(401)),
  'inserting a profile touches its sync_signals row (profiles trigger)'
);

-- Reset the signal (as an unrestricted role, bypassing RLS/grants -- test
-- setup only) so the next assertion proves the day_entries trigger
-- independently, not a leftover from the profiles insert above.
select tests.clear_authentication();
delete from public.sync_signals where profile_id = tests.ulid(401);
select tests.authenticate_as('mom');

select ok(
  not exists(select 1 from public.sync_signals where profile_id = tests.ulid(401)),
  'signal reset before the day_entries trigger assertion'
);

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(402), tests.ulid(401), '2026-09-05', 'UTC', 'none', now());

select ok(
  exists(select 1 from public.sync_signals where profile_id = tests.ulid(401)),
  'inserting a day_entries row touches its sync_signals row independently (day_entries trigger)'
);

-- Updating (not just inserting) also re-touches the row.
select tests.clear_authentication();
delete from public.sync_signals where profile_id = tests.ulid(401);
select tests.authenticate_as('mom');

update public.day_entries
   set flow = 'light', updated_at = now(), last_modified_by_user_id = tests.get_supabase_uid('mom')
 where id = tests.ulid(402);

select ok(
  exists(select 1 from public.sync_signals where profile_id = tests.ulid(401)),
  'updating a day_entries row re-touches its sync_signals row'
);

-- ---------------------------------------------------------------------------
-- Orphan-cleanup fix (PR #92 review, round 2): a hard profile delete (e.g.
-- account deletion cascading via profiles.user_id -> auth.users(id) on
-- delete cascade) must not leave sync_signals with a row for a profile that
-- no longer exists. Deliberately NOT proven by adding
-- `references public.profiles(id) on delete cascade` to sync_signals --
-- that was tried and reverted: the cascade would remove the sync_signals
-- row first, then this trigger's own upsert would try to reinsert it
-- against a profile that is already gone and error, aborting the whole
-- profile deletion. Verified here (and separately against a real local
-- Supabase run) that the delete-not-upsert branch in touch_sync_signal()
-- avoids that failure entirely.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(405), 'Deletion Target', false, 0, now(), now());

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(406), tests.ulid(405), '2026-09-05', 'UTC', 'none', now());

select ok(
  exists(select 1 from public.sync_signals where profile_id = tests.ulid(405)),
  'setup: the profile-to-be-deleted has a sync_signals row'
);

select tests.clear_authentication();

select lives_ok(
  $$delete from public.profiles where id = tests.ulid(405)$$,
  'hard-deleting a profile with day_entries rows succeeds with no error -- '
  || 'proves the orphan-cleanup delete branch does not conflict with the '
  || 'cascaded day_entries deletion (the exact failure mode a sync_signals '
  || 'FK cascade would have produced)'
);

select ok(
  not exists(select 1 from public.day_entries where profile_id = tests.ulid(405)),
  'day_entries rows for the deleted profile are gone (cascade, unchanged by this fix)'
);

select ok(
  not exists(select 1 from public.sync_signals where profile_id = tests.ulid(405)),
  'no orphaned sync_signals row remains for the deleted profile (PR #92 review fix)'
);

-- ---------------------------------------------------------------------------
-- RLS: a stranger (no guardian membership on this profile) cannot see its
-- signal row, mirroring day_entries_select_guardians.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');

select is(
  (select count(*) from public.sync_signals where profile_id = tests.ulid(401)),
  0::bigint,
  'a non-guardian cannot see another family''s sync_signals row'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- P1 fix: the guard corrects drift instead of skipping an already-published
-- table. Simulate a Supabase Studio "Enable Realtime" toggle (a bare
-- whole-row `add table`) on day_entries, then re-run the same guard the
-- migration ran, and prove it is reverted -- not treated as already-correct.
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.day_entries;

select ok(
  exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'day_entries'
  ),
  'setup: day_entries is published whole-row (simulated Studio toggle)'
);

select lives_ok(
  $$select public.reconcile_realtime_publication()$$,
  'reconcile_realtime_publication() runs without error against drifted state'
);

select ok(
  not exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'day_entries'
  ),
  'reconcile_realtime_publication() reverts a whole-row day_entries publish -- '
  || 'correction, not silent skip (P1 fix)'
);

-- Same drill, but for a column-list drift on sync_signals itself rather
-- than a membership drift on day_entries: simulate a future column being
-- added to sync_signals and whole-row-republished (e.g. by the same Studio
-- toggle) before anyone updates this migration's intended column list. The
-- table only has 2 columns today, so a temporary probe column is added
-- (rolled back with the rest of this transaction) to actually manufacture a
-- 3-column drift rather than asserting a count that would trivially match
-- either way.
alter table public.sync_signals add column drift_probe text;
alter publication supabase_realtime drop table public.sync_signals;
alter publication supabase_realtime add table public.sync_signals;

select is(
  (select array_length(attnames, 1) from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_signals'),
  3,
  'setup: sync_signals whole-row publish now carries the drifted 3rd column'
);

select lives_ok(
  $$select public.reconcile_realtime_publication()$$,
  'reconcile_realtime_publication() runs without error against the drifted column list'
);

select ok(
  (select attnames from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sync_signals')
    = array['profile_id', 'updated_at']::name[],
  'reconcile_realtime_publication() narrows the column list back to exactly '
  || 'profile_id, updated_at -- correction, not silent skip (P1 fix)'
);

-- ---------------------------------------------------------------------------
-- Replica identity stays default (primary key) on the source tables --
-- `full` would restore excluded columns to the old-row image, which would
-- matter again the moment either table is ever reconsidered for publishing.
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

select * from finish();
rollback;
