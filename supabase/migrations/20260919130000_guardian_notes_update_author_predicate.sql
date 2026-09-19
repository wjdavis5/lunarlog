-- ===========================================================================
-- 20260919130000_guardian_notes_update_author_predicate.sql
-- Issue #868 (P2, fix(sharing)): guardian_notes UPDATE policy has no author
-- predicate - any writing role can blank or tombstone another guardian's note
-- via direct PostgREST PATCH.
--
-- Changes:
--   1. Replace guardian_notes_insert_guardians: require logged_by_user_id to
--      be non-null and equal to auth.uid(). Direct INSERTs omitting
--      logged_by_user_id or forging another author are rejected by RLS.
--   2. Replace guardian_notes_update_guardians: require logged_by_user_id to
--      match auth.uid() (authors can edit or tombstone their own notes), or
--      if logged_by_user_id is null (orphaned note), allow primary_guardian
--      to tombstone it (deleted_at is not null and body = ''). Co-guardians
--      cannot update another author's note via direct PostgREST PATCH.
--   3. Revoke update (profile_id) on public.guardian_notes from authenticated,
--      preventing moving notes between profiles via raw PATCH (matching
--      the care_notes/day_entries hardening in Issue #562).
-- ===========================================================================

-- 1. Replace INSERT policy
drop policy if exists "guardian_notes_insert_guardians" on public.guardian_notes;
create policy "guardian_notes_insert_guardians" on public.guardian_notes
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
    and logged_by_user_id is not null
    and logged_by_user_id = (select auth.uid())
  );

-- 2. Replace UPDATE policy
drop policy if exists "guardian_notes_update_guardians" on public.guardian_notes;
create policy "guardian_notes_update_guardians" on public.guardian_notes
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
    and (
      logged_by_user_id = (select auth.uid())
      or (
        logged_by_user_id is null
        and public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian'])
      )
    )
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
    and (
      logged_by_user_id = (select auth.uid())
      or (
        logged_by_user_id is null
        and deleted_at is not null
        and body = ''
        and public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian'])
      )
    )
  );

-- 3. Revoke update (profile_id) from authenticated
revoke update (profile_id) on table public.guardian_notes from authenticated;

comment on table public.guardian_notes is
  'Issue #801: one dated, author-scoped guardian note per row on a profile -- the mirror gap to care_notes: date-bound AND attributed, never merged with another author''s note for the same day. Distinct ULIDs and per-id last-writer-wins by updated_at (see the migration header). Tombstones (deleted_at not null) carry the '''' body sentinel and nothing else (guardian_notes_tombstone_payload_check). Length-bounded by guardian_notes_body_length_check (2000, mirroring day_entries.note / care_notes.body). Every accepted guardian reads every row (issue #800: open and transparent, the child included); primary_guardian/co_parent/caregiver write; viewer rejected. logged_by_user_id is author-immutable and is what sync_push checks before allowing an edit or tombstone. Issue #868: UPDATE policy enforces author ownership and orphan-tombstone restriction at the RLS layer for direct PostgREST writes as well.';
