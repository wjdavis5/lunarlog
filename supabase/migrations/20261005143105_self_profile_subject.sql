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
--   3. refuse_second_subject_invitation() -- BEFORE INSERT on
--      guardian_invitations. A subject invitation cannot be created while
--      the profile has an accepted subject.
--   4. unmark_second_profile_subject() -- BEFORE INSERT OR UPDATE OF
--      is_subject, status on profile_guardians. A non-primary membership
--      that would be written as an accepted subject while a different
--      accepted subject exists is written without the marker.
--   5. A one-time backfill by the same rule.
--
-- One subject per profile, and whoever holds the marker keeps it. The
-- marker decides who reads a private note in full (is_profile_subject) and
-- whether the profile's private notes are masked at all
-- (profile_has_subject), so it must not move as a side effect of someone
-- else's action. Until now nothing held a profile to one subject: anyone
-- who may invite (the primary guardian or a co_parent) could create a
-- "this is your profile" invitation at any time, and whoever accepted it
-- became a subject and read every private note. Three rules now hold it
-- to one, and none of them takes the marker from its holder:
--   * Stamping the owner (steps 1 and 2) is refused while the profile has a
--     different accepted subject.
--   * Creating a subject invitation is refused while the profile has an
--     accepted subject (step 3), whoever asks: a co_parent, or the holder
--     herself. create_guardian_invitation is not re-emitted -- the trigger
--     raises inside its INSERT. The error is raise_exception (P0001) with
--     a message chosen so that both clients' invitation-error ladders fall
--     through to their generic failure: they read 42501 or "permission" as
--     unauthorized, 22023 or "invalid" as a bad code, and any all-digit
--     SQLSTATE of 500 or more (55000 included) as a network failure.
--   * Accepting cannot take the marker either (step 4). A pending subject
--     invitation can outlive the moment it was created in: it is created
--     while the profile has no subject, the owner then becomes the subject,
--     and only then is the old invitation accepted. The invitee still joins
--     with the role she was invited to; her row is written is_subject =
--     false. accept_guardian_invitation is not re-emitted either, so the
--     object it returns still echoes the INVITATION's is_subject. The
--     stored membership row -- what syncs, and what every reader and every
--     masking function uses -- is the truth.
--
-- Ownership transfer is unchanged. accept_ownership_transfer first demotes
-- the initiator (necessarily the accepted primary_guardian, i.e. exactly
-- the row this migration stamps) with is_subject = false, and only then
-- promotes the acceptor, writing role = 'primary_guardian' and is_subject =
-- true in ONE statement on both branches of its upsert. So the acceptor's
-- row is already the primary guardian's at the moment the marker is
-- written: step 4, which looks only at non-primary rows, never sees it,
-- and transferring a profile whose owner is the subject ends with exactly
-- one subject, the acceptor.
--   Not created by this migration and not changed by it: a transfer to
--   someone other than an already-invited subject leaves both marked,
--   because the transfer writes its marker unconditionally.
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
--     rule's. That is the only marker this migration ever clears, and
--     only step 2 clears it.
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
-- Concurrency. The three writers that ask "does this profile already have
-- a subject" before marking a row (steps 1, 2 and 4) take one
-- transaction-scoped advisory lock per profile before they look, so two of
-- them cannot each see no subject and both mark a row -- the owner calling
-- her profile 'self' at the instant a stale subject invitation is
-- accepted, or two stale subject invitations accepted at once. It cannot
-- deadlock with the row locks around it: it is taken after any row lock
-- the calling statement already holds, and its holder then waits for no
-- lock another waiter can be holding (accept_guardian_invitation reads the
-- profile without locking it; a relationship edit holds the profiles row,
-- then this lock, then the owner's membership row, which is the
-- profiles-then-profile_guardians order accept_ownership_transfer uses).
-- accept_ownership_transfer does not take it: it writes its marker
-- unconditionally.
--
-- No policy, grant, role or column grant changes, and is_subject stays
-- unwritable by any client. Two existing RPCs behave differently in the
-- cases above and in no other: create_guardian_invitation can now refuse a
-- subject invitation, and accept_guardian_invitation can now write a
-- subject invitee's row without the marker. The four functions are trigger
-- functions -- SECURITY DEFINER with an empty search_path (they must read
-- and write past row-level security, and write a column no client role
-- may write, whichever role's statement fires them), executable by no
-- client role, and uncallable directly.
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
  if not exists (
       select 1
         from public.profiles p
        where p.id = new.profile_id
          and p.relationship = 'self'
     ) then
    return new;
  end if;

  -- One subject per profile: look for another subject only once no other
  -- writer can be deciding the same thing (the header's "Concurrency").
  perform pg_advisory_xact_lock(
    hashtextextended('lunarlog.profile_subject:' || new.profile_id, 0));

  -- Whoever holds the marker keeps it: the owner is not stamped beside a
  -- different accepted subject.
  if not exists (
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
  'Issue #1499: BEFORE INSERT OR UPDATE OF role, status guard on profile_guardians. A row written as the accepted primary_guardian of a profile whose relationship is ''self'' is stamped is_subject = true in that same write, unless the profile already has a different accepted subject (whoever holds the marker keeps it). This is the path that covers profile creation: on_profile_created_add_guardian() inserts the creator''s membership after the profile row exists. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

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
    -- One subject per profile: see step 1 and the header's "Concurrency".
    perform pg_advisory_xact_lock(
      hashtextextended('lunarlog.profile_subject:' || new.id, 0));

    update public.profile_guardians g
       set is_subject = true
     where g.profile_id = new.id
       and g.role = 'primary_guardian'
       and g.status = 'accepted'
       and g.user_id = v_uid
       and g.is_subject is not true
       -- Whoever holds the marker keeps it (see step 1).
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
-- 3. A subject invitation cannot be created while the profile has a subject
-- ---------------------------------------------------------------------------

create or replace function public.refuse_second_subject_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The trigger's WHEN clause has already narrowed this to a subject
  -- invitation.
  if exists (
       select 1
         from public.profile_guardians g
        where g.profile_id = new.profile_id
          and g.status = 'accepted'
          and g.is_subject is true
     ) then
    -- raise_exception (P0001) and this wording on purpose: both clients map
    -- them to their generic invitation failure (see the header).
    raise exception 'this profile already has a subject; a subject invitation cannot be created for it'
      using errcode = 'raise_exception';
  end if;

  return new;
end;
$$;

comment on function public.refuse_second_subject_invitation() is
  'Issue #1499: BEFORE INSERT guard on guardian_invitations. A subject invitation (is_subject) is refused, with raise_exception (P0001), while the profile has an accepted subject membership -- whoever asks, the holder included. A profile has one subject and an invitation never takes the marker from its holder; this is the creation half of that rule, raised inside create_guardian_invitation''s own INSERT. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger guardian_invitations_refuse_second_subject
  before insert on public.guardian_invitations
  for each row
  when (new.is_subject)
  execute function public.refuse_second_subject_invitation();

-- ---------------------------------------------------------------------------
-- 4. Accepting cannot take the marker either: a second subject is written
--    without it
-- ---------------------------------------------------------------------------

create or replace function public.unmark_second_profile_subject()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The trigger's WHEN clause has already narrowed this to a non-primary
  -- membership being written as an accepted subject. (The primary
  -- guardian's row is not this rule's: accept_ownership_transfer writes
  -- role = 'primary_guardian' and the marker in one statement.)
  --
  -- One subject per profile: look only once no other writer can be
  -- deciding the same thing (the header's "Concurrency").
  perform pg_advisory_xact_lock(
    hashtextextended('lunarlog.profile_subject:' || new.profile_id, 0));

  -- Whoever holds the marker keeps it. The invitee still joins, with the
  -- role she was invited to; she is just not marked.
  if exists (
       select 1
         from public.profile_guardians o
        where o.profile_id = new.profile_id
          and o.id <> new.id
          and o.status = 'accepted'
          and o.is_subject is true
     ) then
    new.is_subject := false;
  end if;

  return new;
end;
$$;

comment on function public.unmark_second_profile_subject() is
  'Issue #1499: BEFORE INSERT OR UPDATE OF is_subject, status guard on profile_guardians. A non-primary membership that would be written as an accepted subject while a DIFFERENT accepted subject exists on the profile is written with is_subject = false: the invitee joins with her role and without the marker, and the holder keeps it. This is the acceptance half of the one-subject rule (a subject invitation created while the profile had no subject, accepted after someone became it). It never touches a primary_guardian row, so an ownership transfer is unaffected. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profile_guardians_unmark_second_subject
  before insert or update of is_subject, status on public.profile_guardians
  for each row
  when (new.is_subject is true
        and new.status = 'accepted'
        and new.role <> 'primary_guardian')
  execute function public.unmark_second_profile_subject();

-- ---------------------------------------------------------------------------
-- 5. Privileges: trigger functions, executable by no client role
-- ---------------------------------------------------------------------------

revoke all on function public.stamp_self_profile_subject_membership() from public, anon, authenticated;
revoke all on function public.sync_self_profile_subject_marker() from public, anon, authenticated;
revoke all on function public.refuse_second_subject_invitation() from public, anon, authenticated;
revoke all on function public.unmark_second_profile_subject() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The column's own description
-- ---------------------------------------------------------------------------

comment on column public.profile_guardians.is_subject is
  'Issue #802: this member is the person the profile is about (the subject), distinct from role. Nullable — null and false mean the same thing (a helper membership). Written only on the server: by accept_guardian_invitation (a subject invitation), by accept_ownership_transfer, and, since issue #1499, by the triggers that mark the owner (the accepted primary_guardian) of a profile whose relationship is ''self'': when she creates it, or when she herself sets the relationship to ''self''. That marker is cleared again only when she herself changes the relationship away from ''self'' and the profile has no live private note; a relationship edit by anyone else moves no marker. A profile has one subject and its holder keeps the marker: a subject invitation cannot be created while the profile has an accepted subject, and one created earlier and accepted later joins its invitee without the marker. No authenticated column grant exists, so a client cannot set or clear it. Server-visible and synced (sync_pull selects the whole row), unlike a client-side flag (#518''s lesson). Orthogonal to profiles.is_minor/birth_year (#295): membership identity vs profile fact.';

-- ---------------------------------------------------------------------------
-- 7. Backfill, by the same rule
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
