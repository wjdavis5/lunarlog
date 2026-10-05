-- ===========================================================================
-- 20261005143105_self_profile_subject.sql
-- Issue #1499: the person who creates a profile for herself is its subject.
--
-- The problem. profile_guardians.is_subject (#802) is the one fact every
-- "is this viewer the person the profile is about" decision reads: the
-- per-viewer lens (#850), which device schedules her reminders, whether she
-- may keep a note private, and the server's own private-note masking (#849,
-- is_profile_subject()/profile_has_subject()). Until now it was stamped by
-- exactly two paths -- accepting a "this is your profile" invitation and
-- accepting an ownership transfer. Creating a profile for yourself
-- (profiles.relationship = 'self') stamped nothing, so a signed-in
-- self-tracker was a guardian of her own profile, and a profile with no
-- subject has its private-note masking skipped altogether.
--
-- The rule (the owner's decision on #850, restated by #1499): on a profile
-- whose relationship is 'self', the accepted primary_guardian membership is
-- its subject. It is stamped here, on the server, where the marker lives --
-- not derived by a client, because the server's masking reads the stored
-- marker and a client offering "Keep this note private" without it would
-- promise a privacy the server does not enforce.
--
-- How the creator's membership row is made (and so where the rule is
-- hooked): public.profiles' AFTER INSERT trigger profiles_after_insert_
-- guardian (on_profile_created_add_guardian(), 20260904010000) inserts the
-- creator's (primary_guardian, accepted) row. profile_guardians.profile_id
-- references profiles(id), so a membership row can never arrive before its
-- profile: the only possible order is profile first, membership second.
--
--   1. stamp_self_profile_subject_membership() -- BEFORE INSERT OR UPDATE OF
--      role, status on profile_guardians. A row being written as the
--      accepted primary_guardian of a 'self' profile is stamped is_subject =
--      true in that same write. This is what covers profile creation: the
--      profile row already exists (with its relationship) when the creation
--      trigger inserts the membership.
--   2. sync_self_profile_subject_marker() -- AFTER UPDATE OF relationship on
--      profiles. When the owner herself changes the relationship TO 'self'
--      her accepted primary_guardian row is stamped; when she changes it
--      AWAY from 'self' the marker this rule stamped is cleared (see
--      "Telling markers apart"), unless the profile has a live private note
--      (see "Whose edit moves the marker"). Anyone else's edit moves
--      nothing.
--   3. yield_self_profile_subject_marker() -- AFTER INSERT OR UPDATE OF
--      is_subject, status on profile_guardians. One subject per profile:
--      when a non-primary membership becomes the accepted subject (a subject
--      invitation was accepted), a self-stamped owner marker on the same
--      profile is cleared as part of that same statement.
--   4. A one-time backfill by the same rule.
--
-- One subject per profile. Every stamp above is refused while the profile
-- has a different accepted subject. What the two existing writers do after
-- this change:
--   * accept_ownership_transfer writes is_subject = false on the demoted
--     initiator explicitly -- and the initiator is necessarily the accepted
--     primary_guardian, i.e. exactly the row this rule stamps -- so a
--     transfer cannot leave the self-stamped owner and the acceptor both
--     marked. Nothing to change there.
--   * accept_guardian_invitation stamps the invitee and looks at no other
--     row, so on a 'self' profile it WOULD have left two subjects (the
--     self-stamped owner plus the invited subject). Trigger 3 closes that.
--   Not created by this change and not changed by it: two different people
--   can each accept a subject invitation on one profile, and a transfer to
--   someone other than an already-invited subject leaves both marked.
--   Neither involves a self-stamped marker.
--
-- Telling markers apart (what "the marker this rule stamped" means). An
-- accepted primary_guardian row can only ever be created by the profile-
-- creation trigger or by accept_ownership_transfer: update_guardian_role
-- never grants primary_guardian, and an invitation's role is never
-- primary_guardian (a subject invitation must grant caregiver). A transfer
-- stamps profiles.transferred_to_user_id with the acceptor in the same
-- statement that makes her the owner, that column is server-authoritative
-- (enforce_profile_transfer_fields), and ownership moves by no other path.
-- So on an accepted primary_guardian row:
--   * profile.transferred_to_user_id = row.user_id  -> she owns the profile
--     because it was transferred to her; her marker is the transfer's and
--     survives any relationship change;
--   * otherwise the profile was never transferred to her, no invitation and
--     no transfer can have marked the row, and a marker on it is this
--     rule's. That is the only marker steps 2 and 3 ever clear.
--
-- Whose edit moves the marker (step 2). relationship is ordinary profile
-- metadata: a co_parent may edit it (sync_push's role check, and the
-- column's own update grant). The marker is not ordinary -- it decides
-- whose private notes the server masks from whom, and a profile with no
-- subject is not masked at all. So a relationship edit moves the marker
-- only when it is the owner's own statement about her own profile, and it
-- never unmasks a private note:
--   * Who. Step 2 acts only when the caller is the profile's accepted
--     primary guardian -- the row it would write has user_id = auth.uid().
--     A change made by anyone else (a co_parent, the service role, any
--     statement with no auth.uid()) leaves every marker exactly as it was,
--     in BOTH directions: it neither clears the owner's marker nor stamps
--     it. auth.uid() reads the request's JWT claims, so it is the caller's
--     id here even though this function and sync_push are both SECURITY
--     DEFINER. Creation is not this path: there the creator is the caller,
--     and step 1 stamps the membership as it is inserted.
--   * Private notes. When the owner herself changes the relationship away
--     from 'self', her marker is cleared only if the profile has no live
--     day entry marked private (day_entries.note_private on a row that is
--     not deleted -- note_private is the one test mask_day_entry_note,
--     sync_pull, sync_pull_day_entries and export_account_data use). If it
--     has one, the marker stays and she remains the subject: changing a
--     description field must not make her private notes readable by every
--     guardian as a side effect.
--   A consequence, accepted: a self-stamped marker can outlive the
--   relationship that produced it (a co_parent relabelled the profile, or a
--   private note held it), and a profile a co_parent labelled 'self' has an
--   unmarked owner until she says so herself. The marker follows what the
--   owner said, not what the field currently reads.
--
-- Reaching devices. The incremental pull keys on server_version
-- (sync_pull's `server_version > cursor`), stamped by the BEFORE INSERT OR
-- UPDATE trigger profile_guardians_set_server_version on every write to the
-- table; the client applies a pulled membership row by server_version
-- (conflict_rules.dart's remoteWinsByVersion). That is the same mechanism
-- that carries accept_guardian_invitation's own is_subject write. Every row
-- this migration stamps or clears is written by an INSERT or UPDATE on
-- profile_guardians -- the backfill included -- so each takes a fresh
-- server_version past any device's cursor. updated_at is deliberately not
-- touched (the #853/#850 data-pass precedent): the marker is derived, not a
-- member's edit, and no client needs the bump -- the app orders membership
-- rows by server_version, and the browser client takes a pulled row whose
-- updated_at is not older than the copy it holds, which an unchanged
-- updated_at satisfies.
--
-- Lock order. Step 2 runs inside the statement that already holds the
-- profiles row lock and then locks one profile_guardians row -- the same
-- profiles-then-profile_guardians order accept_ownership_transfer uses.
-- Step 3 locks the owner's row after the acceptor's, which is not the
-- ascending-user_id order update_guardian_role/revoke_guardian/
-- accept_ownership_transfer take a pair of rows in. Those functions only
-- wait on the acceptor's row once it is committed as accepted, with one
-- exception: the same account accepting a subject invitation and an
-- ownership transfer on one profile at the same instant after having been
-- revoked from it. Postgres resolves that as a deadlock error (40P01) for
-- one of the two calls, which the caller retries; no state is corrupted.
--
-- Nothing else changes: no policy, no grant, no role, no column grant.
-- is_subject stays unwritable by any client. The three functions are
-- trigger functions -- SECURITY DEFINER with an empty search_path (they
-- must write a column no client role may write, whichever role's statement
-- fires them), executable by no client role, and uncallable directly.
--
-- Filename ordering (AGENTS.md Migration Flow item 7): sorts after
-- 20260921150000_sync_pull_day_entries_masked_page.sql.
-- Coverage: supabase/tests/self_profile_subject_test.sql.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The membership write: an accepted primary_guardian of a 'self' profile
-- ---------------------------------------------------------------------------

create or replace function public.stamp_self_profile_subject_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The trigger's WHEN clause has already narrowed this to a row being
  -- written as an accepted primary_guardian that does not carry the marker.
  if exists (
       select 1
         from public.profiles p
        where p.id = new.profile_id
          and p.relationship = 'self'
     )
     -- One subject per profile: an accepted invited subject keeps the
     -- marker; the owner is not stamped beside her.
     and not exists (
       select 1
         from public.profile_guardians o
        where o.profile_id = new.profile_id
          and o.id <> new.id
          and o.status = 'accepted'
          and o.is_subject is true
     ) then
    new.is_subject := true;
  end if;

  return new;
end;
$$;

comment on function public.stamp_self_profile_subject_membership() is
  'Issue #1499: BEFORE INSERT OR UPDATE OF role, status guard on profile_guardians. A row written as the accepted primary_guardian of a profile whose relationship is ''self'' is stamped is_subject = true in that same write, unless the profile already has a different accepted subject. This is the path that covers profile creation: on_profile_created_add_guardian() inserts the creator''s membership after the profile row exists. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profile_guardians_stamp_self_subject
  before insert or update of role, status on public.profile_guardians
  for each row
  when (new.role = 'primary_guardian'
        and new.status = 'accepted'
        and new.is_subject is not true)
  execute function public.stamp_self_profile_subject_membership();

-- ---------------------------------------------------------------------------
-- 2. The relationship change, when it is the owner's own: to 'self' stamps,
--    away from 'self' clears unless a private note would be unmasked
-- ---------------------------------------------------------------------------

create or replace function public.sync_self_profile_subject_marker()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- The caller, from the request's JWT claims: SECURITY DEFINER changes the
  -- role this function runs as, not whose request it is, so this is the
  -- caller's id even when the profile write came from inside sync_push.
  v_uid uuid := (select auth.uid());
begin
  -- The trigger's WHEN clause has already established that the
  -- relationship changed.
  --
  -- Only the owner's own edit moves the marker. Both statements below can
  -- write one row only -- the profile's accepted primary_guardian row --
  -- and only when that row is the caller's own (g.user_id = v_uid). A
  -- co_parent's edit, the service role's, or any statement with no
  -- auth.uid() matches nothing, in either direction.
  if v_uid is null then
    return null;
  end if;

  if new.relationship = 'self' then
    update public.profile_guardians g
       set is_subject = true
     where g.profile_id = new.id
       and g.role = 'primary_guardian'
       and g.status = 'accepted'
       and g.user_id = v_uid
       and g.is_subject is not true
       -- One subject per profile (see step 1).
       and not exists (
         select 1
           from public.profile_guardians o
          where o.profile_id = new.id
            and o.id <> g.id
            and o.status = 'accepted'
            and o.is_subject is true
       );
  elsif old.relationship = 'self' then
    -- Clear only the marker this rule stamped. A profile transferred to its
    -- current owner carries the transfer's marker (see the header's
    -- "Telling markers apart"), which survives; an invited subject is never
    -- a primary_guardian, so her row is not matched at all.
    update public.profile_guardians g
       set is_subject = false
     where g.profile_id = new.id
       and g.role = 'primary_guardian'
       and g.status = 'accepted'
       and g.user_id = v_uid
       and g.is_subject is true
       and new.transferred_to_user_id is distinct from g.user_id
       -- Never unmask: a profile with no subject is not masked at all, so
       -- the marker stays while any live day entry is marked private
       -- (note_private, the test every masking path uses).
       and not exists (
         select 1
           from public.day_entries de
          where de.profile_id = new.id
            and de.deleted_at is null
            and de.note_private
       );
  end if;

  return null;
end;
$$;

comment on function public.sync_self_profile_subject_marker() is
  'Issue #1499: AFTER UPDATE OF relationship on profiles. Acts only when the caller is the profile''s accepted primary guardian (that row''s user_id = auth.uid()): her change to ''self'' stamps is_subject = true on her row (unless the profile already has a different accepted subject); her change away from ''self'' clears that marker again, except on a profile transferred to her (profiles.transferred_to_user_id = her user_id), whose marker came from accept_ownership_transfer, and except while the profile has a live day entry with note_private, so that a relationship edit never unmasks a private note. A change made by anyone else (a co_parent, the service role, no auth.uid()) leaves every marker as it was, in both directions. Never raises, so it cannot reject the profile write that fired it. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profiles_after_relationship_self_subject
  after update of relationship on public.profiles
  for each row
  when (old.relationship is distinct from new.relationship)
  execute function public.sync_self_profile_subject_marker();

-- ---------------------------------------------------------------------------
-- 3. One subject per profile: an invited subject displaces a self-stamped
--    owner marker, as part of the statement that accepts her
-- ---------------------------------------------------------------------------

create or replace function public.yield_self_profile_subject_marker()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The trigger's WHEN clause has already narrowed this to a non-primary
  -- membership that is now an accepted subject. Only a self-stamped marker
  -- yields: the owner's row on a profile that was not transferred to her.
  update public.profile_guardians g
     set is_subject = false
    from public.profiles p
   where p.id = new.profile_id
     and g.profile_id = new.profile_id
     and g.id <> new.id
     and g.role = 'primary_guardian'
     and g.status = 'accepted'
     and g.is_subject is true
     and p.transferred_to_user_id is distinct from g.user_id;

  return null;
end;
$$;

comment on function public.yield_self_profile_subject_marker() is
  'Issue #1499: AFTER INSERT OR UPDATE OF is_subject, status on profile_guardians. When a non-primary membership becomes the profile''s accepted subject (accept_guardian_invitation on a subject invitation), a self-stamped marker on the owner''s row is cleared in the same statement, so the profile keeps exactly one subject. A marker that came from an ownership transfer is left alone. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profile_guardians_after_subject_yield_self
  after insert or update of is_subject, status on public.profile_guardians
  for each row
  when (new.is_subject is true
        and new.status = 'accepted'
        and new.role <> 'primary_guardian')
  execute function public.yield_self_profile_subject_marker();

-- ---------------------------------------------------------------------------
-- 4. Privileges: trigger functions, executable by no client role
-- ---------------------------------------------------------------------------

revoke all on function public.stamp_self_profile_subject_membership() from public, anon, authenticated;
revoke all on function public.sync_self_profile_subject_marker() from public, anon, authenticated;
revoke all on function public.yield_self_profile_subject_marker() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. The column's own description
-- ---------------------------------------------------------------------------

comment on column public.profile_guardians.is_subject is
  'Issue #802: this member is the person the profile is about (the subject), distinct from role. Nullable — null and false mean the same thing (a helper membership). Written only on the server: by accept_guardian_invitation (a subject invitation), by accept_ownership_transfer, and, since issue #1499, by the triggers that mark the owner (the accepted primary_guardian) of a profile whose relationship is ''self'': when she creates it, or when she herself sets the relationship to ''self''. That marker is cleared again when she herself changes the relationship away from ''self'' and the profile has no live private note, or when an invited subject is accepted; a relationship edit by anyone else moves no marker. No authenticated column grant exists, so a client cannot set or clear it. Server-visible and synced (sync_pull selects the whole row), unlike a client-side flag (#518''s lesson). Orthogonal to profiles.is_minor/birth_year (#295): membership identity vs profile fact.';

-- ---------------------------------------------------------------------------
-- 6. Backfill, by the same rule
-- ---------------------------------------------------------------------------
-- Live profiles whose relationship is 'self': their accepted
-- primary_guardian row, only where the profile has no accepted subject.
-- The backfill reads the relationship as it stands: who set it on an
-- existing row is not recorded anywhere, so step 2's "the owner's own
-- edit" test cannot be applied to the past.
-- profile_guardians_one_primary_uq allows at most one such row per profile.
-- Idempotent: a stamped row no longer matches `is_subject is not true`.
-- The UPDATE fires profile_guardians_set_server_version for each row, so
-- every backfilled membership takes a fresh server_version and is pulled by
-- a device that has already synced.

update public.profile_guardians g
   set is_subject = true
  from public.profiles p
 where p.id = g.profile_id
   and p.relationship = 'self'
   and p.deleted_at is null
   and g.role = 'primary_guardian'
   and g.status = 'accepted'
   and g.is_subject is not true
   and not exists (
     select 1
       from public.profile_guardians o
      where o.profile_id = g.profile_id
        and o.status = 'accepted'
        and o.is_subject is true
   );
