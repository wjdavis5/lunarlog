-- Proof for issue #175 (`20260916000000_pull_path_indexes.sql`): the
-- incremental pull path's (server_version) indexes exist, the two
-- advisor-confirmed-unused day_entries indexes are gone, and the nine FK
-- covering indexes the migration adds are present with the partial
-- predicates they were created with.
--
-- Catalog assertions only (the `realtime_publication_test.sql` pattern):
-- a plan-level assertion that the pull query actually uses
-- day_entries_server_version_idx is not deterministic on an empty
-- pgTAP-reset database - the planner correctly prefers a sequential scan +
-- sort for a handful of rows - so the EXPLAIN ANALYZE proof for the pull
-- shape (seeded, under RLS, before/after) lives in the issue #175 PR body,
-- not here. What this file pins is the structural half: no future
-- migration can silently drop a pull-path index, re-add the two unused
-- day_entries indexes, or lose a partial predicate that keeps an import_id
-- index from indexing the manual-row common case.
begin;
select plan(20);

-- ---------------------------------------------------------------------------
-- The incremental pull's predicate/order indexes. The three bare
-- (server_version) indexes were created by
-- 20260913014000_sync_server_version_indexes_and_pull.sql (issue #525), not
-- by this issue's own migration - asserted here anyway because issue #175
-- is the tracking issue for the pull path's indexing and these are the
-- indexes its AC names. observations' three (issue #175 item 4, created by
-- 20260908160000_observations.sql) are pinned for the same reason.
-- ---------------------------------------------------------------------------
select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'day_entries'
       and indexname = 'day_entries_server_version_idx'
  ),
  'day_entries_server_version_idx exists - the day_entries pull '
  || '(where server_version > cursor order by server_version limit n) '
  || 'has a leading-column match'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'profiles'
       and indexname = 'profiles_server_version_idx'
  ),
  'profiles_server_version_idx exists - the profiles pull has a '
  || 'leading-column match'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'profile_guardians'
       and indexname = 'profile_guardians_server_version_idx'
  ),
  'profile_guardians_server_version_idx exists - the profile_guardians '
  || 'pull has a leading-column match'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'observations'
       and indexname = 'observations_server_version_idx'
  ),
  'observations_server_version_idx exists (issue #175 item 4)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'observations'
       and indexname = 'observations_profile_id_local_date_idx'
  ),
  'observations_profile_id_local_date_idx exists (issue #175 item 4)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'observations'
       and indexname = 'observations_profile_id_category_local_date_idx'
  ),
  'observations_profile_id_category_local_date_idx exists (issue #175 item 4)'
);

-- ---------------------------------------------------------------------------
-- Issue #175 item 2: the two advisor-confirmed-unused indexes are gone.
-- Their FK coverage survives on other indexes (day_entries_user_id_fkey on
-- day_entries_user_id_server_version_idx; day_entries_profile_fk on
-- day_entries_live_profile_date_uq) - asserted below so the coverage claim
-- cannot silently rot either.
-- ---------------------------------------------------------------------------
select ok(
  not exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'day_entries'
       and indexname = 'day_entries_user_id_idx'
  ),
  'day_entries_user_id_idx is dropped (production advisor: never used)'
);

select ok(
  not exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'day_entries'
       and indexname = 'day_entries_profile_id_user_id_idx'
  ),
  'day_entries_profile_id_user_id_idx is dropped (production advisor: '
  || 'never used; day_entries_profile_fk stays covered by '
  || 'day_entries_live_profile_date_uq)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and tablename = 'day_entries'
       and indexname = 'day_entries_user_id_server_version_idx'
  ),
  'day_entries_user_id_server_version_idx still exists - it is what keeps '
  || 'day_entries_user_id_fkey covered after the drops'
);

-- ---------------------------------------------------------------------------
-- Issue #175 item 3: the nine FK covering indexes this migration adds.
-- ---------------------------------------------------------------------------
select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'day_entries_import_id_idx'
  ),
  'day_entries_import_id_idx exists (day_entries_import_id_fkey: '
  || 'delete_account_data / delete_profile_data import cleanup)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'observations_import_id_idx'
  ),
  'observations_import_id_idx exists (observations_import_id_fkey: '
  || 'delete_account_data / delete_profile_data import cleanup)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'observations_logged_by_idx'
  ),
  'observations_logged_by_idx exists (day_entries attribution precedent)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'observations_last_modified_by_idx'
  ),
  'observations_last_modified_by_idx exists (day_entries attribution '
  || 'precedent)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'visit_prep_items_checked_by_idx'
  ),
  'visit_prep_items_checked_by_idx exists (delete_account_data keys its '
  || 'uncheck update on this column)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'notification_outbox_profile_id_idx'
  ),
  'notification_outbox_profile_id_idx exists (delete_profile_data deletes '
  || 'the outbox by profile_id)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'guardian_invitations_invited_by_idx'
  ),
  'guardian_invitations_invited_by_idx exists (delete_account_data deletes '
  || 'invitations by invited_by)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'ownership_transfers_initiated_by_idx'
  ),
  'ownership_transfers_initiated_by_idx exists (delete_account_data '
  || 'deletes transfers by initiated_by)'
);

select ok(
  exists(
    select 1 from pg_catalog.pg_indexes
     where schemaname = 'public'
       and indexname = 'prediction_connections_owner_idx'
  ),
  'prediction_connections_owner_idx exists (delete_account_data deletes '
  || 'connections by owner_user_id; mirrors prediction_connections_recipient_idx)'
);

-- ---------------------------------------------------------------------------
-- The two import_id indexes are PARTIAL - `where import_id is not null` -
-- so manual rows (the common case) are never indexed and the sync write
-- path pays nothing for them. Pin the predicate so a future re-creation
-- cannot quietly widen the index.
-- ---------------------------------------------------------------------------
select is(
  (
    select pg_get_expr(ix.indpred, ix.indrelid)
      from pg_catalog.pg_index ix
      join pg_catalog.pg_class ci on ci.oid = ix.indexrelid
      join pg_catalog.pg_class ct on ct.oid = ix.indrelid
      join pg_catalog.pg_namespace n on n.oid = ct.relnamespace
     where n.nspname = 'public'
       and ci.relname = 'day_entries_import_id_idx'
  ),
  '(import_id IS NOT NULL)',
  'day_entries_import_id_idx keeps its partial predicate'
);

select is(
  (
    select pg_get_expr(ix.indpred, ix.indrelid)
      from pg_catalog.pg_index ix
      join pg_catalog.pg_class ci on ci.oid = ix.indexrelid
      join pg_catalog.pg_class ct on ct.oid = ix.indrelid
      join pg_catalog.pg_namespace n on n.oid = ct.relnamespace
     where n.nspname = 'public'
       and ci.relname = 'observations_import_id_idx'
  ),
  '(import_id IS NOT NULL)',
  'observations_import_id_idx keeps its partial predicate'
);

-- The ten remaining unindexed-FK findings (care_notes x2, visit_prep_items
-- logged_by/last_modified_by, guardian_invitations.accepted_by,
-- missed_entry_alert_state.user_id, ownership_transfers.accepted_by,
-- prediction_projections.published_by, profile_guardians.invited_by,
-- profiles.transferred_to_user_id) are deliberately ACCEPTED with named
-- reasons in 20260916000000_pull_path_indexes.sql's section 3 - asserted
-- absent nowhere on purpose: absence assertions would just make a future,
-- deliberate index on one of them fail this suite instead of pass review.

select * from finish();
rollback;
