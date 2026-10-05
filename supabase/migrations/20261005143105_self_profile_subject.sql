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
--   2. keep_relationship_for_primary_guardian() -- BEFORE UPDATE OF
--      relationship on profiles. Only the profile's primary guardian can
--      change the relationship. Anyone else's value is put back, and the
--      rest of her write proceeds.
--   3. sync_self_profile_subject_marker() -- AFTER UPDATE OF relationship on
--      profiles. When the owner changes the relationship TO 'self' her
--      accepted primary_guardian row is stamped; when she changes it AWAY
--      from 'self' the marker this rule stamped is cleared (see "Telling
--      markers apart"), unless the profile has a live private note (see
--      "Who may change the relationship").
--   4. refuse_second_subject_invitation() -- BEFORE INSERT on
--      guardian_invitations. A subject invitation cannot be created while
--      the profile has an accepted subject.
--   5. unmark_second_profile_subject() -- BEFORE INSERT OR UPDATE OF
--      is_subject, status on profile_guardians. A non-primary membership
--      that would be written as an accepted subject while a different
--      accepted subject exists is written without the marker.
--   6. revoke_pending_subject_invitations() -- AFTER triggers on
--      profile_guardians and on guardian_invitations. When someone becomes
--      the profile's subject, its still-pending subject invitations are
--      revoked in that same statement, so none is left to go stale.
--   7. A one-time backfill by the same rule.
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
--   * Stamping the owner (steps 1 and 3) is refused while the profile has a
--     different accepted subject.
--   * Creating a subject invitation is refused while the profile has an
--     accepted subject (step 4), whoever asks: a co_parent, or the holder
--     herself. create_guardian_invitation is not re-emitted -- the trigger
--     raises inside its INSERT. The error is raise_exception (P0001) with
--     a message chosen so that both clients' invitation-error ladders fall
--     through to their generic failure: they read 42501 or "permission" as
--     unauthorized, 22023 or "invalid" as a bad code, and any all-digit
--     SQLSTATE of 500 or more (55000 included) as a network failure.
--   * No subject invitation is left pending once the profile has a subject
--     (step 6). A pending one can outlive the moment it was created in: it
--     is created while the profile has no subject, and someone then becomes
--     the subject. At that moment the profile's still-pending subject
--     invitations are revoked, exactly as every other revocation of an
--     invitation is made (revoked_at = clock_timestamp(); the clients list
--     pending invitations with revoked_at is null, and
--     accept_guardian_invitation refuses a revoked one). It happens when
--     the owner's row is marked -- at creation, by her own relationship
--     change, by the backfill, by a transfer -- and when a subject
--     invitation is accepted, for the profile's other ones. An ordinary
--     invitation is never touched.
--   * Accepting cannot take the marker either (step 5), should a subject
--     invitation survive all the same (it was being accepted at the instant
--     the marker was stamped, or was created in that instant). The invitee
--     still joins with the role she was invited to; her row is written
--     is_subject = false. This is the backstop: accept_guardian_invitation
--     is not re-emitted, so in that one case the object it returns still
--     echoes the INVITATION's is_subject. The stored membership row -- what
--     syncs, and what every reader and every masking function uses -- is
--     the truth.
--
-- Ownership transfer is unchanged. accept_ownership_transfer first demotes
-- the initiator (necessarily the accepted primary_guardian, i.e. exactly
-- the row this migration stamps) with is_subject = false, and only then
-- promotes the acceptor, writing role = 'primary_guardian' and is_subject =
-- true in ONE statement on both branches of its upsert. So the acceptor's
-- row is already the primary guardian's at the moment the marker is
-- written: step 5, which looks only at non-primary rows, never sees it,
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
--     only step 3 clears it.
--
-- Who may change the relationship, and whose change moves the marker
-- (steps 2 and 3). The marker decides whose private notes the server masks
-- from whom, and a profile with no subject is not masked at all, so the
-- field that drives it cannot be ordinary shared metadata:
--   * Only the primary guardian can change it (step 2). It is her statement
--     of who the profile is for. A co_parent may edit a profile, sync_push
--     writes the whole profile row, and both apps send the relationship
--     with every profile edit -- so it was not enough for step 3 to ignore
--     a co_parent's change. She could flip the column away and back; the
--     owner's device would pull the flipped value in between; and the
--     owner's own next push would carry it, as her own change, and clear
--     her own marker. So when the relationship is changing and the caller
--     is a signed-in account (auth.uid() is not null) that is not the
--     profile's accepted primary guardian, step 2 puts the old value back
--     and lets the rest of the write proceed. It does not raise: a refusal
--     would fail her whole push over a field she did not mean to change.
--     Being a BEFORE trigger it runs before the row is written, so step 3
--     (whose WHEN compares old and new) sees no change. It is on the table,
--     so it covers a direct table update as well as sync_push (the column
--     grant and the update policy still admit a co_parent). A caregiver or
--     a viewer never gets this far, as before. A statement with no
--     auth.uid() (the service role, a migration) may still change the
--     column.
--   * Whose change moves the marker (step 3). Step 3 acts only when the
--     caller is the profile's accepted primary guardian -- the row it would
--     write has user_id = auth.uid(). With step 2 in place no other
--     signed-in caller's change reaches it; the test stays as a second line
--     of defence, and it is what makes a change with no auth.uid() move no
--     marker, in either direction. auth.uid() reads the request's JWT
--     claims, so it is the caller's id here even though these functions and
--     sync_push are all SECURITY DEFINER. Creation is not this path: there
--     the creator is the caller, and step 1 stamps the membership as it is
--     inserted.
--   * Private notes. When the owner herself changes the relationship away
--     from 'self', her marker is cleared only if the profile has no live
--     day entry marked private (day_entries.note_private on a row that is
--     not deleted -- note_private is the one test mask_day_entry_note,
--     sync_pull, sync_pull_day_entries and export_account_data use). If it
--     has one, the marker stays and she remains the subject: changing a
--     description field must not make her private notes readable by every
--     guardian as a side effect.
--   What is left. The server cannot tell the owner's device echoing a stale
--   value from her own decision: a push by her that carries a different
--   relationship IS her change, and a private note sent in that same push
--   is stored after the profile row, so it does not hold the marker. What
--   step 2 guarantees is that only she -- or a statement with no auth.uid()
--   -- can put a different value on the row for her device to pick up.
--   A consequence, accepted: a self-stamped marker can outlive the
--   relationship that produced it (a private note held it, or the service
--   role changed the column). The marker follows what the owner said, not
--   what the field currently reads.
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
-- a subject" before marking a row (steps 1, 3 and 5) take one
-- transaction-scoped advisory lock per profile before they look, so two of
-- them cannot each see no subject and both mark a row -- two subject
-- invitations accepted at once, say.
--   The order they take it in matters. sync_push locks the profiles row
--   FOR UPDATE and only then, inside step 3, the advisory lock. A new
--   member's row needs a key-share lock on that same profiles row for its
--   foreign-key check, AFTER its BEFORE INSERT triggers have run. So if
--   step 5 took the advisory lock first, an accepted subject invitation
--   (advisory lock, then the profiles row) and the owner's relationship
--   change (profiles row, then the advisory lock) could deadlock. Steps 1
--   and 5 therefore take FOR KEY SHARE on the profiles row themselves,
--   before the advisory lock, whenever the row they are deciding is about
--   to be inserted -- the lock its foreign-key check would take a moment
--   later anyway. When the member already has a row (the accept UPDATEs it)
--   there is no foreign-key check and they take no lock on the profiles
--   row at all, which keeps accept_guardian_invitation from waiting on the
--   profiles row while it holds a membership row that
--   accept_ownership_transfer locks in the opposite order.
--   Step 6's revocations skip an invitation row another transaction has
--   locked, for the same reason: an invitation that is being accepted at
--   that instant is left to step 5.
-- accept_ownership_transfer does not take the advisory lock: it writes its
-- marker unconditionally.
--
-- No policy, grant, role or column grant changes, and is_subject stays
-- unwritable by any client. Three existing write paths behave differently
-- in the cases above and in no other: a profile write by anyone but the
-- primary guardian leaves the relationship as it was; create_guardian_
-- invitation can refuse a subject invitation; and a pending subject
-- invitation can be revoked, or (the backstop) accepted without the
-- marker. The six functions are trigger functions -- SECURITY DEFINER with
-- an empty search_path (they must read and write past row-level security,
-- and write columns no client role may write, whichever role's statement
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
  -- The profiles row first, when this membership row is about to be
  -- inserted: its foreign-key check would take this lock a moment later.
  if tg_op = 'INSERT'
     and not exists (
       select 1
         from public.profile_guardians g
        where g.profile_id = new.profile_id
          and g.user_id = new.user_id
     ) then
    perform 1 from public.profiles p where p.id = new.profile_id for key share;
  end if;
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
-- 2. Only the profile's primary guardian can change the relationship
-- ---------------------------------------------------------------------------

create or replace function public.keep_relationship_for_primary_guardian()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- The caller, from the request's JWT claims (see step 3).
  v_uid uuid := (select auth.uid());
begin
  -- The trigger's WHEN clause has already established that the
  -- relationship is changing.
  --
  -- No auth.uid(): the service role or a migration, which may change it.
  if v_uid is null then
    return new;
  end if;

  -- A signed-in account that is not the profile's accepted primary
  -- guardian: put the old value back and let the rest of the write
  -- proceed. Never raise -- a co_parent's device sends the whole row with
  -- every profile edit, and a refusal would fail her entire push over a
  -- field she did not mean to change.
  if not exists (
       select 1
         from public.profile_guardians g
        where g.profile_id = new.id
          and g.user_id = v_uid
          and g.role = 'primary_guardian'
          and g.status = 'accepted'
     ) then
    new.relationship := old.relationship;
  end if;

  return new;
end;
$$;

comment on function public.keep_relationship_for_primary_guardian() is
  'Issue #1499: BEFORE UPDATE OF relationship guard on profiles. Only the profile''s accepted primary guardian can change the relationship: it is her statement of who the profile is for, and it drives the subject marker. When the value is changing and the caller is a signed-in account (auth.uid() is not null) that is not that guardian, the old value is put back and the rest of the write proceeds -- it never raises, because sync_push writes the whole profile row and both apps send the relationship with every profile edit. A statement with no auth.uid() (the service role, a migration) may change the column. Runs before the row is written, so sync_self_profile_subject_marker() sees no change. Covers a direct table update as well as sync_push. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profiles_relationship_primary_guardian_only
  before update of relationship on public.profiles
  for each row
  when (old.relationship is distinct from new.relationship)
  execute function public.keep_relationship_for_primary_guardian();

-- ---------------------------------------------------------------------------
-- 3. The relationship change, when it is the owner's own: to 'self' stamps,
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
  -- Only the owner's own change moves the marker. Both statements below
  -- can write one row only -- the profile's accepted primary_guardian row
  -- -- and only when that row is the caller's own (g.user_id = v_uid). A
  -- change with no auth.uid() matches nothing, in either direction; and no
  -- other signed-in caller's change reaches this function at all (step 2),
  -- though it would match nothing either.
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
  'Issue #1499: AFTER UPDATE OF relationship on profiles (keep_relationship_for_primary_guardian() has already put back any change by a signed-in caller who is not the primary guardian). Acts only when the caller is the profile''s accepted primary guardian (that row''s user_id = auth.uid()): her change to ''self'' stamps is_subject = true on her row (unless the profile already has a different accepted subject); her change away from ''self'' clears that marker again, except on a profile transferred to her (profiles.transferred_to_user_id = her user_id), whose marker came from accept_ownership_transfer, and except while the profile has a live day entry with note_private, so that a relationship edit never unmasks a private note. A change made by anyone else (a co_parent, the service role, no auth.uid()) leaves every marker as it was, in both directions. Never raises, so it cannot reject the profile write that fired it. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profiles_after_relationship_self_subject
  after update of relationship on public.profiles
  for each row
  when (old.relationship is distinct from new.relationship)
  execute function public.sync_self_profile_subject_marker();

-- ---------------------------------------------------------------------------
-- 4. A subject invitation cannot be created while the profile has a subject
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
-- 5. Accepting cannot take the marker either: a second subject is written
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
  -- deciding the same thing (the header's "Concurrency"). The profiles row
  -- first, when this membership row is about to be inserted: its
  -- foreign-key check would take this lock a moment later. When she
  -- already has a row (the accept UPDATEs it) no lock on the profiles row
  -- is taken at all.
  if tg_op = 'INSERT'
     and not exists (
       select 1
         from public.profile_guardians g
        where g.profile_id = new.profile_id
          and g.user_id = new.user_id
     ) then
    perform 1 from public.profiles p where p.id = new.profile_id for key share;
  end if;
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
  'Issue #1499: BEFORE INSERT OR UPDATE OF is_subject, status guard on profile_guardians. A non-primary membership that would be written as an accepted subject while a DIFFERENT accepted subject exists on the profile is written with is_subject = false: the invitee joins with her role and without the marker, and the holder keeps it. This is the backstop of the one-subject rule: pending subject invitations are revoked when someone becomes the subject (revoke_pending_subject_invitations()), and this covers one that survives all the same. It never touches a primary_guardian row, so an ownership transfer is unaffected. Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

create trigger profile_guardians_unmark_second_subject
  before insert or update of is_subject, status on public.profile_guardians
  for each row
  when (new.is_subject is true
        and new.status = 'accepted'
        and new.role <> 'primary_guardian')
  execute function public.unmark_second_profile_subject();

-- ---------------------------------------------------------------------------
-- 6. No stale subject invitations: revoked when someone becomes the subject
-- ---------------------------------------------------------------------------

create or replace function public.revoke_pending_subject_invitations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Fired from two tables (the triggers below); on both, new.profile_id is
  -- the profile. When it fires for an invitation that has just been
  -- accepted, that row is no longer pending (accepted_at is set), so only
  -- the profile's OTHER subject invitations match.
  --
  -- revoked_at = clock_timestamp() is all any revocation of an invitation
  -- sets (revoke_guardian_invitation, revoke_guardian, update_guardian_role,
  -- accept_ownership_transfer). SKIP LOCKED: an invitation another
  -- transaction is accepting at this instant is left to
  -- unmark_second_profile_subject(), rather than waited for (the header's
  -- "Concurrency").
  update public.guardian_invitations i
     set revoked_at = clock_timestamp()
   where i.id in (
           select p.id
             from public.guardian_invitations p
            where p.profile_id = new.profile_id
              and p.is_subject
              and p.accepted_at is null
              and p.revoked_at is null
              for update skip locked
         );

  return null;
end;
$$;

comment on function public.revoke_pending_subject_invitations() is
  'Issue #1499: when someone becomes a profile''s subject, the profile''s still-pending subject invitations are revoked in the same statement (revoked_at = clock_timestamp(), as every other revocation of an invitation is made), so none is left to be accepted later by someone who cannot be the subject. Fired AFTER the owner''s membership row is written as the accepted subject (at creation, by her own relationship change, by the backfill, by an ownership transfer), and AFTER a subject invitation is marked accepted (for the profile''s other pending subject invitations). An ordinary invitation is never touched; an invitation another transaction has locked is skipped and left to unmark_second_profile_subject(). Trigger function only: EXECUTE revoked from public, anon, and authenticated.';

-- The owner's row. (A non-primary member becomes the subject only by
-- accepting a subject invitation, and at that moment her own invitation is
-- still pending: that path is the second trigger's, once it is accepted.)
create trigger profile_guardians_after_subject_revoke_invitations
  after insert or update of is_subject, status on public.profile_guardians
  for each row
  when (new.is_subject is true
        and new.status = 'accepted'
        and new.role = 'primary_guardian')
  execute function public.revoke_pending_subject_invitations();

create trigger guardian_invitations_after_accept_revoke_subject_invitations
  after update of accepted_at on public.guardian_invitations
  for each row
  when (new.is_subject
        and old.accepted_at is null
        and new.accepted_at is not null)
  execute function public.revoke_pending_subject_invitations();

-- ---------------------------------------------------------------------------
-- 7. Privileges: trigger functions, executable by no client role
-- ---------------------------------------------------------------------------

revoke all on function public.stamp_self_profile_subject_membership() from public, anon, authenticated;
revoke all on function public.keep_relationship_for_primary_guardian() from public, anon, authenticated;
revoke all on function public.sync_self_profile_subject_marker() from public, anon, authenticated;
revoke all on function public.refuse_second_subject_invitation() from public, anon, authenticated;
revoke all on function public.unmark_second_profile_subject() from public, anon, authenticated;
revoke all on function public.revoke_pending_subject_invitations() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. The column's own description
-- ---------------------------------------------------------------------------

comment on column public.profile_guardians.is_subject is
  'Issue #802: this member is the person the profile is about (the subject), distinct from role. Nullable — null and false mean the same thing (a helper membership). Written only on the server: by accept_guardian_invitation (a subject invitation), by accept_ownership_transfer, and, since issue #1499, by the triggers that mark the owner (the accepted primary_guardian) of a profile whose relationship is ''self'': when she creates it, or when she herself sets the relationship to ''self''. That marker is cleared again only when she herself changes the relationship away from ''self'' and the profile has no live private note. Only the primary guardian can change the relationship at all: anyone else''s value is put back. A profile has one subject and its holder keeps the marker: a subject invitation cannot be created while the profile has an accepted subject, pending ones are revoked when someone becomes the subject, and one that is accepted all the same joins its invitee without the marker. No authenticated column grant exists, so a client cannot set or clear it. Server-visible and synced (sync_pull selects the whole row), unlike a client-side flag (#518''s lesson). Orthogonal to profiles.is_minor/birth_year (#295): membership identity vs profile fact.';

-- ---------------------------------------------------------------------------
-- 9. Backfill, by the same rule
-- ---------------------------------------------------------------------------
-- Live profiles whose relationship is 'self': their accepted
-- primary_guardian row, only where the profile has no accepted subject.
-- The backfill reads the relationship as it stands: who set it on an
-- existing row is not recorded anywhere, so step 3's "the owner's own
-- edit" test cannot be applied to the past.
-- profile_guardians_one_primary_uq allows at most one such row per profile.
-- Idempotent: a stamped row no longer matches `is_subject is not true`.
-- The UPDATE fires profile_guardians_set_server_version for each row, so
-- every backfilled membership takes a fresh server_version and is pulled by
-- a device that has already synced. It also fires step 6, so a subject
-- invitation left pending on a backfilled profile is revoked.

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
