-- Migration: 20260913015000_day_entries_column_grants.sql
--
-- Issue #562 (P2): column grants on day_entries/observations/care_notes/
-- visit_prep_items let a guardian move entries between profiles via a raw
-- PostgREST PATCH, and let a PATCH create a payload-bearing tombstone on
-- day_entries (the tombstone CHECK covers flow and pms only, not note/tags).
--
-- =============================================================================
-- 1. Drop `profile_id` from the UPDATE grant on all four tables
-- =============================================================================
--
-- sync_push's own "a day entry/observation/care note/visit-prep item never
-- legitimately changes profiles" invariant (checked via `v_stored.profile_id
-- is distinct from v_profile_id` -> raise) is enforced only in the RPC, not
-- structurally. observations/care_notes/visit_prep_items' own UPDATE
-- statements in sync_push never assign `profile_id` in their SET clause
-- (verified against the latest body, 20260912000000_health_sync_export_marker.sql),
-- so revoking the column grant here is a pure tightening for those three -
-- no RPC change needed. day_entries' UPDATE statement DOES currently assign
-- `profile_id = v_profile_id` unconditionally (even though the value is
-- already proven equal by the immutability check a few lines earlier) -
-- revoking the column grant here would make THAT statement fail with a
-- permission error the moment sync_push (security invoker - verified,
-- 20260912000000:70) tries to run it. The matching sync_push edit (drop
-- `profile_id` from the day_entries UPDATE's SET clause - a no-op
-- functionally, since the value can only ever already match) lands in
-- 20260913016000_sync_push_hardening.sql, the consolidated sync_push
-- re-emission. That migration is numbered BEFORE this one deliberately: on
-- a real `supabase db push` (migrations applied one at a time, in filename
-- order), sync_push must already be able to run without the profile_id
-- grant before this migration revokes it, or a sync_push call landing in
-- the gap between the two migrations would fail with a permission error.
--
-- Column-level REVOKE removes exactly the named column from the existing
-- aggregate grant (Postgres tracks column privileges independently); every
-- other granted column on each table is untouched.

revoke update (profile_id) on table public.day_entries from authenticated;
revoke update (profile_id) on table public.observations from authenticated;
revoke update (profile_id) on table public.care_notes from authenticated;
revoke update (profile_id) on table public.visit_prep_items from authenticated;

-- =============================================================================
-- 2. Extend day_entries' tombstone CHECK to note and tags
-- =============================================================================
--
-- day_entries_tombstone_flow_check (20260908140000, issue #224) and
-- day_entries_tombstone_pms_check (20260909160000, issue #220) cover flow
-- and pms; note and tags - the two fields a raw PATCH could otherwise leave
-- intact on an otherwise-tombstoned row ("a delete that does not delete") -
-- never got the same structural backstop, even though sync_push's own
-- tombstone-producing branches already clear both (the same "tombstones
-- carry no payload" precedent every other clearing follows). Backfill
-- first (issue #224's own precedent: safe to add as a VALIDATING
-- constraint, not NOT VALID, once every existing violation is cleared) in
-- case any stray pre-#224-era tombstone still carries a leftover note or
-- tags array from before sync_push's tombstone branches cleared them.

update public.day_entries
   set note = null,
       tags = '[]'::jsonb
 where deleted_at is not null
   and (note is not null or tags <> '[]'::jsonb);

alter table public.day_entries
  add constraint day_entries_tombstone_note_check
  check (deleted_at is null or note is null);

comment on constraint day_entries_tombstone_note_check on public.day_entries is
  'Issue #562: a tombstoned row (deleted_at is not null) always carries '
  'note = null - the structural backstop day_entries_tombstone_flow_check '
  'already provides for flow, extended to note so a raw PATCH cannot leave '
  'note text on an otherwise-deleted row (Issue #201''s "profile_id can '
  'move" sibling gap).';

alter table public.day_entries
  add constraint day_entries_tombstone_tags_check
  check (deleted_at is null or tags = '[]'::jsonb);

comment on constraint day_entries_tombstone_tags_check on public.day_entries is
  'Issue #562: a tombstoned row (deleted_at is not null) always carries '
  'tags = ''[]''::jsonb - the same structural backstop as '
  'day_entries_tombstone_note_check, applied to tags.';
