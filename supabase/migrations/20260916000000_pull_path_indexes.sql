-- Migration: 20260916000000_pull_path_indexes.sql
--
-- Issue #175 - perf(backend): index the incremental pull path; drop unused
-- day_entries indexes.
--
-- Scope note (what landed where): the issue's item 1 - bare (server_version)
-- indexes on profiles, day_entries, and profile_guardians - and item 4 -
-- observations' (server_version), (profile_id, local_date), and
-- (profile_id, category, local_date) - are ALREADY on main:
-- `20260913014000_sync_server_version_indexes_and_pull.sql` (issue #525, PR
-- #582) created `profiles_server_version_idx`,
-- `day_entries_server_version_idx`, and `profile_guardians_server_version_idx`
-- (its own header calls this issue the "index half only" predecessor), and
-- `20260908160000_observations.sql` gave observations all three of its
-- indexes from day one. This migration does not re-create any of them;
-- `supabase/tests/pull_path_indexes_test.sql` pins their existence so a
-- future migration cannot silently drop them.
--
-- What this migration delivers is item 2 (the two advisor-confirmed-unused
-- day_entries index drops) and item 3 (the unindexed-foreign-key findings:
-- a covering index where a real query path or parent-side delete needs one,
-- an explicit accepting comment where one is not warranted).
--
-- The FK list was re-derived on 2026-09-14 against this branch's full
-- migration chain - NOT the issue's 2026-09-08 snapshot of 7 findings,
-- which predates care_notes, visit_prep_items, import provenance, prediction
-- connections, and the erasure/retention flows - by running
-- `npx supabase@2.116.0 db advisors --local --type performance --level info`
-- against a `db reset --local` stack: 19 unindexed-FK findings. Nine get an
-- index in section 2; ten are accepted with a named reason in section 3.
-- The advisor's unused-index findings, by contrast, require production
-- traffic (they read pg_stat), so a fresh local reset reports every index
-- as unused - the issue's own 2026-09-08 production advisor output remains
-- the authority for the two drops in section 1.
--
-- Index-only migration: no table, column, policy, grant, trigger, or
-- function is created, altered, or dropped anywhere below, so the
-- post-deploy security advisor gate (`supabase db advisors --linked --type
-- security --fail-on error` in supabase-migrate.yml) has nothing new to
-- evaluate. Indexes are built non-concurrently inside the migration
-- transaction for the same reason `20260913014000` gives: `create index
-- concurrently` cannot run inside a transaction, and production row counts
-- today (single digits on day_entries) make the SHARE-lock build instant.

-- ---------------------------------------------------------------------------
-- 1. Issue item 2: drop the two advisor-confirmed-unused day_entries indexes.
-- ---------------------------------------------------------------------------
-- Production advisor (2026-09-08, quoted in the issue):
-- `day_entries_user_id_idx` and `day_entries_profile_id_user_id_idx` have
-- never been used. No query path filters day_entries by user_id alone - RLS
-- scopes every read by guardianship via is_profile_guardian(profile_id, ...),
-- and the incremental pull filters only on server_version - so nothing can
-- use a user_id-leading (or profile_id+user_id) index on this table.
--
-- FK coverage after these drops (verified by re-running the advisor's
-- unindexed-FK check with both indexes dropped on the local stack: no new
-- finding appears):
--   * day_entries_user_id_fkey stays covered by
--     day_entries_user_id_server_version_idx (user_id, server_version).
--   * day_entries_profile_fk stays covered by
--     day_entries_live_profile_date_uq (profile_id, local_date) - the
--     issue's own coverage claim, confirmed against the advisor's actual
--     leading-column containment check, which counts partial indexes.
drop index if exists public.day_entries_user_id_idx;
drop index if exists public.day_entries_profile_id_user_id_idx;

-- ---------------------------------------------------------------------------
-- 2. Issue item 3: covering indexes for the nine FK findings that a live
--    query path or parent-side delete actually needs. Each index names the
--    FK it covers and the statement that needs it.
-- ---------------------------------------------------------------------------

-- day_entries_import_id_fkey -> import_jobs(id) on delete set null.
-- delete_account_data() (20260914103000, LLA-048) runs
--   update public.day_entries set import_id = null
--    where import_id in (select id from public.import_jobs where created_by = v_uid)
-- and both of delete_profile_data()'s branches (20260915090000) delete
-- import_jobs rows, firing the same set-null child scan per deleted job.
-- Partial: manual rows (import_id null, the common case) are not indexed at
-- all, so the sync write path pays nothing for rows that can never match.
create index if not exists day_entries_import_id_idx
  on public.day_entries (import_id)
  where import_id is not null;

-- observations_import_id_fkey -> import_jobs(id) on delete set null: the
-- same two flows as above, on the largest table in the schema.
create index if not exists observations_import_id_idx
  on public.observations (import_id)
  where import_id is not null;

-- observations_logged_by_user_id_fkey -> auth.users(id) on delete set null.
-- Mirrors the day_entries attribution precedent (day_entries_logged_by_idx,
-- 20260904010000): a departing caregiver's account deletion set-nulls
-- attribution on the rows they logged on surviving shared profiles, and
-- without an index that is a sequential scan of the biggest table.
create index if not exists observations_logged_by_idx
  on public.observations (logged_by_user_id);

-- observations_last_modified_by_user_id_fkey -> auth.users(id) on delete
-- set null: same shape as observations_logged_by_idx, mirroring
-- day_entries_last_modified_by_idx.
create index if not exists observations_last_modified_by_idx
  on public.observations (last_modified_by_user_id);

-- visit_prep_items_checked_by_user_id_fkey -> auth.users(id) on delete set
-- null. delete_account_data() (Issue #605/LLA-047) runs
--   update public.visit_prep_items
--      set is_checked = false, checked_by_user_id = null
--    where checked_by_user_id = v_uid and deleted_at is null
-- - a query keyed exactly on this column, on every account deletion.
create index if not exists visit_prep_items_checked_by_idx
  on public.visit_prep_items (checked_by_user_id);

-- notification_outbox_profile_id_fkey -> profiles(id) on delete cascade.
-- delete_profile_data() (20260915090000) runs
--   delete from public.notification_outbox where profile_id = p_profile_id
-- on both the purge-by-source and full-purge paths, and the profiles
-- cascade itself needs the same child-side lookup.
create index if not exists notification_outbox_profile_id_idx
  on public.notification_outbox (profile_id);

-- guardian_invitations_invited_by_fkey -> auth.users(id) on delete cascade.
-- delete_account_data() runs
--   delete from public.guardian_invitations where invited_by = v_uid
-- on every account deletion.
create index if not exists guardian_invitations_invited_by_idx
  on public.guardian_invitations (invited_by);

-- ownership_transfers_initiated_by_fkey -> auth.users(id) on delete
-- cascade. delete_account_data() (Issue #499) runs
--   delete from public.ownership_transfers where initiated_by = v_uid.
create index if not exists ownership_transfers_initiated_by_idx
  on public.ownership_transfers (initiated_by);

-- prediction_connections_owner_user_id_fkey -> auth.users(id) on delete
-- cascade. delete_account_data() (Issue #499) runs
--   delete from public.prediction_connections
--    where owner_user_id = v_uid or recipient_user_id = v_uid
-- - the recipient half is already covered by
-- prediction_connections_recipient_idx; this index covers the owner half.
-- Named _owner_idx to mirror prediction_connections_recipient_idx.
create index if not exists prediction_connections_owner_idx
  on public.prediction_connections (owner_user_id);

-- ---------------------------------------------------------------------------
-- 3. Issue item 3 (continued): the ten ACCEPTED findings - FKs where a
--    covering index is NOT warranted. Each is named with its reason; these
--    are deliberate acceptances (the issue's own "rarely-queried FK on a
--    small table" carve-out), not omissions.
-- ---------------------------------------------------------------------------
-- * care_notes_logged_by_user_id_fkey (auth.users, on delete set null):
--   care_notes is a per-profile standing-notes table (one row per note, not
--   per day), orders of magnitude smaller than day_entries/observations.
--   The only statement that ever touches this column outside sync_push's
--   own stamping is the auth.users set-null cascade when a note's author
--   deletes their account - one sequential scan of a small table per rare
--   event. day_entries' attribution indexes are the precedent for the
--   large tables, not a rule for every table.
-- * care_notes_last_modified_by_user_id_fkey: same table, same reason.
-- * visit_prep_items_logged_by_user_id_fkey (auth.users, on delete set
--   null): same shape as care_notes - a per-checklist-item table, tiny; only
--   the set-null cascade touches it. checked_by_user_id, the one
--   visit_prep_items attribution column a live query keys on
--   (delete_account_data, LLA-047), IS indexed in section 2.
-- * visit_prep_items_last_modified_by_user_id_fkey: same reason.
-- * guardian_invitations_accepted_by_fkey (auth.users, on delete set null):
--   invitations are single-use, short-lived rows bounded by household
--   sharing activity. invited_by - the column delete_account_data keys on -
--   is indexed in section 2; accepted_by is only ever set-null'd by a
--   departing acceptor's account deletion, one sequential scan of a tiny
--   table.
-- * missed_entry_alert_state_user_id_fkey (auth.users, on delete cascade):
--   one row per (profile, guardian) that enabled missed-entry alerts -
--   bounded by household sizes, a handful of rows. delete_account_data's
--   `delete ... where user_id = v_uid` runs once per account deletion, and
--   a sequential scan of that many rows is unmeasurable; the nightly scan
--   reads the table by profile_id, the primary key's leading column.
-- * ownership_transfers_accepted_by_fkey (auth.users, on delete set null):
--   at most one live transfer per profile (ownership_transfers_one_live_uq)
--   plus short-lived history. initiated_by - the delete_account_data key -
--   is indexed in section 2; accepted_by is set-null only.
-- * prediction_projections_published_by_fkey (auth.users, on delete
--   cascade): at most one row per profile (profile_id is the primary key) -
--   the smallest table in the schema.
-- * profile_guardians_invited_by_fkey (auth.users, on delete set null):
--   one row per (profile, guardian) membership, bounded by household sizes;
--   only the departing inviter's account deletion ever touches it, and the
--   table is already covered by profile_id/user_id-leading indexes for
--   every real lookup path.
-- * profiles_transferred_to_user_id_fkey (auth.users, on delete cascade):
--   no server-side query filters on this column (it rides sync_push and is
--   read client-side); the only lookup is the auth.users cascade when a
--   transfer recipient deletes their account - once per rare event - and
--   almost every row is null (transfers are rare), so an index would be
--   nearly all null entries.
