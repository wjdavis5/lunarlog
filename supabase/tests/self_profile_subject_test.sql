-- Coverage for Issue #1499 (20261005143105_self_profile_subject.sql): the
-- person who creates a profile for herself is its subject.
--
-- The rule: on a profile whose relationship is 'self', the accepted
-- primary_guardian membership carries profile_guardians.is_subject (#802).
-- This file pins, through the real RPCs wherever a client would use one:
--
--   1. Catalog: the three triggers, their SECURITY DEFINER / search_path /
--      EXECUTE posture, and that the marker is still unwritable by a client.
--   2. Creation: a 'self' profile makes its creator the subject; a profile
--      created with another relationship (or none) does not.
--   3. Relationship changes by the owner: to 'self' stamps, away from
--      'self' clears, and an edit that does not move the relationship
--      across 'self' writes nothing to the membership row.
--   4. Ownership transfer: a transferred profile keeps its subject whatever
--      the relationship then does, and transferring a self-stamped profile
--      ends with one subject.
--   5. One subject per profile: a profile that already has an invited
--      subject is left alone, and accepting a subject invitation on a
--      self-stamped profile ends with exactly one subject.
--   6. Private-note masking (#849) now protects the self-owner's private
--      note from another guardian, and she can still edit it herself.
--   7. Whose relationship edit moves the marker: only the owner's own
--      (the caller is the profile's accepted primary guardian), through
--      sync_push as each role and with no auth.uid() at all; and the
--      owner's own edit away from 'self' never clears while a live day
--      entry carries a private note.
--   8. A primary_guardian row that becomes accepted is stamped by the same
--      rule, and not beside an invited subject.
--   9. The backfill (simulate-then-reconcile, the caregiver_mode_backfill
--      precedent): rows that match and rows that do not, then the
--      migration's statement verbatim, then idempotence. Last on purpose:
--      the statement is table-wide, so every section above has already
--      asserted what the triggers alone do.
--
-- Pull visibility (the migration's "Reaching devices" claim) is asserted
-- beside each write rather than in a section of its own: a device that has
-- already synced holds a cursor at the highest membership server_version it
-- was given, and every stamped or cleared row -- the backfilled ones
-- included -- must come back from sync_pull past that cursor.
begin;
select plan(75);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

-- A profile write through the real sync_push, as the current caller. Every
-- fixture push must be APPLIED (not rejected, and not declined as stale),
-- so the helper raises otherwise. updated_at is the wall clock: later
-- pushes to one profile are strictly newer, including after an ownership
-- transfer has stamped the profile's updated_at with clock_timestamp().
create function pg_temp.push_profile(p_id text, p_patch jsonb)
returns void language plpgsql as $$
declare
  v_result jsonb;
begin
  v_result := public.sync_push(
    jsonb_build_array(
      jsonb_build_object('id', p_id, 'updated_at', clock_timestamp()) || p_patch),
    '[]'::jsonb);
  if v_result -> 'rejected' <> '[]'::jsonb or v_result -> 'resolved' <> '[]'::jsonb then
    raise exception 'fixture push for % was not applied: %', p_id, v_result;
  end if;
end;
$$;

-- One membership row as role:status:is_subject, read past RLS so an
-- assertion reads the stored row whichever role is current.
create function pg_temp.marker(p_profile text, p_user text)
returns text language sql security definer set search_path = '' as $$
  select g.role || ':' || g.status || ':' || coalesce(g.is_subject::text, 'null')
    from public.profile_guardians g
   where g.profile_id = p_profile
     and g.user_id = tests.get_supabase_uid(p_user)
$$;

create function pg_temp.subject_count(p_profile text)
returns bigint language sql security definer set search_path = '' as $$
  select count(*)
    from public.profile_guardians g
   where g.profile_id = p_profile
     and g.status = 'accepted'
     and g.is_subject is true
$$;

-- "A device that has already synced": the highest membership
-- server_version the current caller's own full pull returns.
create temp table cur (name text primary key, v bigint not null);
grant all on table cur to authenticated;

create function pg_temp.remember_cursor(p_name text)
returns void language sql as $$
  insert into cur (name, v)
  select p_name, coalesce(max((g ->> 'server_version')::bigint), 0)
    from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'profile_guardians') g
  on conflict (name) do update set v = excluded.v
$$;

-- What the current caller's incremental pull past that cursor carries for
-- one membership row: its is_subject ('true' / 'false' / 'null'), or
-- 'absent' when the row is not in the page (nothing was written to it).
create function pg_temp.pulled_marker(p_name text, p_profile text, p_user text)
returns text language sql as $$
  select coalesce(
    (select coalesce(g ->> 'is_subject', 'null')
       from jsonb_array_elements(
              public.sync_pull(
                jsonb_build_object('profile_guardians', (select v from cur where name = p_name)))
              -> 'profile_guardians') g
      where g ->> 'profile_id' = p_profile
        and g ->> 'user_id' = tests.get_supabase_uid(p_user)::text),
    'absent')
$$;

select tests.create_supabase_user('ana');
select tests.create_supabase_user('bea');
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('kid');
select tests.create_supabase_user('tess');
select tests.create_supabase_user('riley');
select tests.create_supabase_user('cora');
select tests.create_supabase_user('eve');
select tests.create_supabase_user('gus');

-- ---------------------------------------------------------------------------
-- 1. Catalog: the triggers exist; their functions are SECURITY DEFINER with
--    an empty search_path and executable by no client role; and the marker
--    is still unwritable by a client (no policy or grant changed).
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from pg_catalog.pg_trigger t
    where not t.tgisinternal
      and (t.tgrelid, t.tgname) in (
        ('public.profile_guardians'::regclass, 'profile_guardians_stamp_self_subject'),
        ('public.profile_guardians'::regclass, 'profile_guardians_after_subject_yield_self'),
        ('public.profiles'::regclass, 'profiles_after_relationship_self_subject'))),
  3::bigint,
  'catalog: the three issue #1499 triggers exist on their tables'
);
select is(
  (select count(*) from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('stamp_self_profile_subject_membership',
                        'sync_self_profile_subject_marker',
                        'yield_self_profile_subject_marker')
      and p.prosecdef
      and p.proconfig = array['search_path=""']::text[]),
  3::bigint,
  'catalog: the three trigger functions are SECURITY DEFINER with an empty search_path'
);
-- Counted over pg_proc (rather than naming each signature) so the
-- assertion fails, instead of raising, where a function is missing. A
-- grant to PUBLIC would show up here too: both roles inherit it.
select is(
  (select count(*) from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('stamp_self_profile_subject_membership',
                        'sync_self_profile_subject_marker',
                        'yield_self_profile_subject_marker')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')),
  3::bigint,
  'catalog: none of the three functions is executable by anon or authenticated'
);
select ok(
  not has_column_privilege('authenticated', 'public.profile_guardians', 'is_subject', 'UPDATE')
  and not has_column_privilege('authenticated', 'public.profile_guardians', 'is_subject', 'INSERT')
  and not has_column_privilege('anon', 'public.profile_guardians', 'is_subject', 'UPDATE'),
  'catalog: no client role gained a write privilege on profile_guardians.is_subject'
);

-- ---------------------------------------------------------------------------
-- 2. Creation.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('ana');
select pg_temp.push_profile(tests.ulid(9101), '{"display_name":"Ana","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9101), 'ana'),
  'primary_guardian:accepted:true',
  'creation: creating a self profile makes its creator the subject'
);
select is(
  (select g ->> 'is_subject'
     from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'profile_guardians') g
    where g ->> 'profile_id' = tests.ulid(9101)),
  'true',
  'creation: her own first pull carries the marker on her membership row'
);
-- The marker is the server's alone: she cannot clear (or set) it herself.
select throws_ok(
  format($$update public.profile_guardians set is_subject = false where profile_id = %L$$, tests.ulid(9101)),
  '42501', null,
  'creation: the subject cannot write her own marker through the table'
);

select tests.authenticate_as('mom');
select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley","relationship":"daughter","is_minor":true}');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:null',
  'creation: a profile created for a daughter does not make its creator the subject'
);
select pg_temp.push_profile(tests.ulid(9103), '{"display_name":"Unlabelled"}');
select is(
  pg_temp.marker(tests.ulid(9103), 'mom'),
  'primary_guardian:accepted:null',
  'creation: a profile created with no relationship does not make its creator the subject'
);

-- A raw table insert (the PostgREST shape; the profiles INSERT grant is
-- still open) reaches the same trigger chain as sync_push.
select tests.authenticate_as('bea');
insert into public.profiles (id, display_name, relationship, sort_order, created_at, updated_at)
values (tests.ulid(9104), 'Bea', 'self', 0, '2026-09-10T00:00:00Z', '2026-09-10T00:00:00Z');
select is(
  pg_temp.marker(tests.ulid(9104), 'bea'),
  'primary_guardian:accepted:true',
  'creation: a self profile inserted directly is stamped the same way'
);

-- ---------------------------------------------------------------------------
-- 3. Relationship changes, on Mom's daughter profile (9102). Each write is
--    checked against a device that had already synced.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select pg_temp.remember_cursor('mom');
select is(
  pg_temp.pulled_marker('mom', tests.ulid(9102), 'mom'),
  'absent',
  'pull: a synced device gets no membership row back while nothing has changed'
);

select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:true',
  'relationship: changing a profile to self stamps its primary guardian'
);
select is(
  pg_temp.pulled_marker('mom', tests.ulid(9102), 'mom'),
  'true',
  'pull: the row stamped by a relationship change reaches an already-synced device'
);

-- An edit that does not carry the relationship key at all (an old client,
-- or a plain rename) leaves both the relationship and the marker alone.
select pg_temp.remember_cursor('mom');
select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley B"}');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:true',
  'relationship: a profile edit that does not touch the relationship keeps the marker'
);
select is(
  pg_temp.pulled_marker('mom', tests.ulid(9102), 'mom'),
  'absent',
  'relationship: and it writes nothing to the membership row'
);

select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley B","relationship":"daughter"}');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:false',
  'relationship: changing a profile away from self clears the marker the rule stamped'
);
select is(
  pg_temp.pulled_marker('mom', tests.ulid(9102), 'mom'),
  'false',
  'pull: the cleared row reaches an already-synced device'
);

-- A change between two relationships that are both not self is not this
-- rule's business.
select pg_temp.remember_cursor('mom');
select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley B","relationship":"child"}');
select is(
  pg_temp.pulled_marker('mom', tests.ulid(9102), 'mom'),
  'absent',
  'relationship: a change between two non-self relationships writes nothing to the membership row'
);

-- Clearing the relationship altogether (an explicit null) also leaves self.
select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley B","relationship":"self"}');
select pg_temp.push_profile(tests.ulid(9102), '{"display_name":"Riley B","relationship":null}');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:false',
  'relationship: clearing the relationship (self -> null) clears the marker too'
);

-- The profiles.relationship column grant is still open to a direct update;
-- the trigger function is SECURITY DEFINER and needs no client EXECUTE.
update public.profiles set relationship = 'self' where id = tests.ulid(9103);
select is(
  pg_temp.marker(tests.ulid(9103), 'mom'),
  'primary_guardian:accepted:true',
  'relationship: a direct column update to self stamps too, with no EXECUTE granted to the caller'
);

-- ---------------------------------------------------------------------------
-- 4. Ownership transfer.
-- ---------------------------------------------------------------------------
-- 4a. Mom transfers a daughter profile to Kid: the marker is the transfer's.
select pg_temp.push_profile(tests.ulid(9105), '{"display_name":"Kit","relationship":"daughter","is_minor":true}');
select public.create_ownership_transfer(tests.ulid(9105), 'co_parent', pg_temp.token(41));
select tests.authenticate_as('kid');
select public.accept_ownership_transfer(pg_temp.token(41), 'Kit', 'Mom');
select is(
  pg_temp.marker(tests.ulid(9105), 'kid') || ' / ' || pg_temp.marker(tests.ulid(9105), 'mom'),
  'primary_guardian:accepted:true / co_parent:accepted:false',
  'transfer: the acceptor is the subject and the former owner is not (the #802 behaviour, unchanged)'
);

select pg_temp.push_profile(tests.ulid(9105), '{"display_name":"Kit","relationship":"self"}');
select is(
  pg_temp.subject_count(tests.ulid(9105)),
  1::bigint,
  'transfer: the new owner calling the profile self leaves exactly one subject'
);
select pg_temp.remember_cursor('kid');
select pg_temp.push_profile(tests.ulid(9105), '{"display_name":"Kit","relationship":"other"}');
select is(
  pg_temp.marker(tests.ulid(9105), 'kid'),
  'primary_guardian:accepted:true',
  'transfer: a transferred profile keeps its subject when the relationship leaves self'
);
select is(
  pg_temp.pulled_marker('kid', tests.ulid(9105), 'kid'),
  'absent',
  'transfer: and the relationship change writes nothing to the transferred owner''s row'
);

-- 4b. Dad transfers his own self-stamped profile to Tess: the transfer
--     itself moves the marker (it writes false on the demoted initiator),
--     so no second subject is left behind.
select tests.authenticate_as('dad');
select pg_temp.push_profile(tests.ulid(9106), '{"display_name":"Dad","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9106), 'dad'),
  'primary_guardian:accepted:true',
  'transfer: setup -- the self-stamped owner before the transfer'
);
select public.create_ownership_transfer(tests.ulid(9106), 'viewer', pg_temp.token(42));
select tests.authenticate_as('tess');
select public.accept_ownership_transfer(pg_temp.token(42), 'Tess', 'Dad');
select is(
  pg_temp.marker(tests.ulid(9106), 'tess') || ' / ' || pg_temp.marker(tests.ulid(9106), 'dad'),
  'primary_guardian:accepted:true / viewer:accepted:false',
  'transfer: transferring a self-stamped profile makes the acceptor the subject and clears the former owner'
);
select is(
  pg_temp.subject_count(tests.ulid(9106)),
  1::bigint,
  'transfer: exactly one subject remains after transferring a self-stamped profile'
);
select pg_temp.push_profile(tests.ulid(9106), '{"display_name":"Tess","relationship":"partner"}');
select is(
  pg_temp.marker(tests.ulid(9106), 'tess'),
  'primary_guardian:accepted:true',
  'transfer: the acceptor of a profile that was self keeps the marker when it leaves self'
);

-- ---------------------------------------------------------------------------
-- 5. One subject per profile.
-- ---------------------------------------------------------------------------
-- 5a. A profile that already has an invited subject is left alone.
select tests.authenticate_as('mom');
select pg_temp.push_profile(tests.ulid(9107), '{"display_name":"Riley","relationship":"daughter","is_minor":true}');
select public.create_guardian_invitation(tests.ulid(9107), 'caregiver', 'Riley', pg_temp.token(51), 48, true);
select tests.authenticate_as('riley');
select public.accept_guardian_invitation(pg_temp.token(51), 'Riley');
select tests.authenticate_as('mom');
select pg_temp.push_profile(tests.ulid(9107), '{"display_name":"Riley","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9107), 'mom') || ' / ' || pg_temp.marker(tests.ulid(9107), 'riley'),
  'primary_guardian:accepted:null / caregiver:accepted:true',
  'one subject: a profile that already has an invited subject does not stamp its owner when it becomes self'
);
select is(
  pg_temp.subject_count(tests.ulid(9107)),
  1::bigint,
  'one subject: the invited subject is still the only one'
);

-- 5b. Accepting a subject invitation on a self-stamped profile (Ana's,
--     9101) moves the marker in that same statement.
select tests.authenticate_as('ana');
select pg_temp.remember_cursor('ana');
select public.create_guardian_invitation(tests.ulid(9101), 'caregiver', 'Cora', pg_temp.token(52), 48, true);
select tests.authenticate_as('cora');
select public.accept_guardian_invitation(pg_temp.token(52), 'Cora');
select is(
  pg_temp.marker(tests.ulid(9101), 'ana') || ' / ' || pg_temp.marker(tests.ulid(9101), 'cora'),
  'primary_guardian:accepted:false / caregiver:accepted:true',
  'one subject: accepting a subject invitation on a self-stamped profile clears the owner''s marker'
);
select is(
  pg_temp.subject_count(tests.ulid(9101)),
  1::bigint,
  'one subject: exactly one subject after a subject invitation is accepted on a self-stamped profile'
);
select tests.authenticate_as('ana');
select is(
  pg_temp.pulled_marker('ana', tests.ulid(9101), 'ana') || ' / ' || pg_temp.pulled_marker('ana', tests.ulid(9101), 'cora'),
  'false / true',
  'pull: the owner''s already-synced device receives her cleared row together with the invited subject''s'
);
-- With an accepted invited subject in place, toggling the relationship does
-- not hand the marker back to the owner.
select pg_temp.push_profile(tests.ulid(9101), '{"display_name":"Ana","relationship":"other"}');
select pg_temp.push_profile(tests.ulid(9101), '{"display_name":"Ana","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9101), 'ana') || ' / ' || pg_temp.marker(tests.ulid(9101), 'cora'),
  'primary_guardian:accepted:false / caregiver:accepted:true',
  'one subject: the relationship returning to self does not re-stamp the owner beside an invited subject'
);

-- 5c. A plain (non-subject) invitation does not disturb a self-stamped
--     owner: Bea's profile (9104) gains a co-parent.
select tests.authenticate_as('bea');
select public.create_guardian_invitation(tests.ulid(9104), 'co_parent', 'Gus', pg_temp.token(53), 48);
select tests.authenticate_as('gus');
select public.accept_guardian_invitation(pg_temp.token(53), 'Gus');
select is(
  pg_temp.marker(tests.ulid(9104), 'bea') || ' / ' || pg_temp.marker(tests.ulid(9104), 'gus'),
  'primary_guardian:accepted:true / co_parent:accepted:false',
  'one subject: a plain invitation leaves the self-stamped owner the subject'
);

-- 5d. A marker that came from a transfer is not this rule's to move: a
--     subject invitation accepted on a profile that was transferred to its
--     owner (Tess's, 9106) leaves her marker where it was before #1499.
select tests.create_supabase_user('ines');
select tests.authenticate_as('tess');
select public.create_guardian_invitation(tests.ulid(9106), 'caregiver', 'Ines', pg_temp.token(54), 48, true);
select tests.authenticate_as('ines');
select public.accept_guardian_invitation(pg_temp.token(54), 'Ines');
select is(
  pg_temp.marker(tests.ulid(9106), 'tess'),
  'primary_guardian:accepted:true',
  'one subject: an owner whose marker came from a transfer keeps it when a subject invitation is accepted (unchanged)'
);

-- 5e. The same rule on accept_guardian_invitation's other branch, where the
--     invitee already has a (revoked) row and the accept UPDATEs it. Hana's
--     self profile (9109): Ivy is invited as its subject, removed, and
--     invited again.
select tests.create_supabase_user('hana');
select tests.create_supabase_user('ivy');
select tests.authenticate_as('hana');
select pg_temp.push_profile(tests.ulid(9109), '{"display_name":"Hana","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9109), 'caregiver', 'Ivy', pg_temp.token(55), 48, true);
select tests.authenticate_as('ivy');
select public.accept_guardian_invitation(pg_temp.token(55), 'Ivy');
select tests.authenticate_as('hana');
select public.revoke_guardian(tests.ulid(9109), tests.get_supabase_uid('ivy'));
-- With the invited subject removed, the profile becoming self again stamps
-- its owner: a revoked membership is not a subject.
select pg_temp.push_profile(tests.ulid(9109), '{"display_name":"Hana","relationship":"other"}');
select pg_temp.push_profile(tests.ulid(9109), '{"display_name":"Hana","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9109), 'hana') || ' / ' || pg_temp.marker(tests.ulid(9109), 'ivy'),
  'primary_guardian:accepted:true / caregiver:revoked:true',
  'one subject: a revoked invited subject does not stop the owner being stamped when the profile becomes self'
);
select public.create_guardian_invitation(tests.ulid(9109), 'caregiver', 'Ivy', pg_temp.token(56), 48, true);
select tests.authenticate_as('ivy');
select public.accept_guardian_invitation(pg_temp.token(56), 'Ivy');
select is(
  pg_temp.marker(tests.ulid(9109), 'hana') || ' / ' || pg_temp.marker(tests.ulid(9109), 'ivy'),
  'primary_guardian:accepted:false / caregiver:accepted:true',
  'one subject: re-accepting a subject invitation over a revoked row clears the self-stamped owner too'
);
select is(
  pg_temp.subject_count(tests.ulid(9109)),
  1::bigint,
  'one subject: exactly one subject after the re-accepted subject invitation'
);

-- ---------------------------------------------------------------------------
-- 6. Private-note masking (#849) on a self profile: Bea (owner, subject)
--    and Gus (co_parent) on 9104.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('bea');
select is(
  jsonb_array_length(public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(9150), 'profile_id', tests.ulid(9104), 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'light', 'note', 'mine alone', 'note_private', true,
      'updated_at', '2026-09-01T10:00:00Z'))
  ) -> 'rejected'),
  0,
  'masking: the self-owner''s private note pushes without rejection'
);
select is(
  (select e ->> 'note' from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'day_entries') e
    where e ->> 'id' = tests.ulid(9150)),
  'mine alone',
  'masking: the self-owner reads her own private note in full'
);
select tests.authenticate_as('gus');
select is(
  (select (e ->> 'note') is null and (e ->> 'note_private') = 'true'
     from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'day_entries') e
    where e ->> 'id' = tests.ulid(9150)),
  true,
  'masking: another guardian of her profile reads the private note as NULL'
);
select is(
  (select (e ->> 'note') is null and (e ->> 'note_private') = 'true'
     from jsonb_array_elements(public.sync_pull_day_entries(0, 500)) e
    where e ->> 'id' = tests.ulid(9150)),
  true,
  'masking: the single-table page RPC hides it from that guardian too'
);
-- She is the subject to sync_push as well: her own later edit of the
-- private note is stored, not discarded as a non-subject's masked copy.
select tests.authenticate_as('bea');
select is(
  jsonb_array_length(public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(9150), 'profile_id', tests.ulid(9104), 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'light', 'note', 'mine alone, edited', 'note_private', true,
      'updated_at', '2026-09-02T10:00:00Z'))
  ) -> 'rejected'),
  0,
  'masking: the self-owner''s edit of her private note pushes without rejection'
);
select tests.clear_authentication();
select is(
  (select note from public.day_entries where id = tests.ulid(9150)),
  'mine alone, edited',
  'masking: the self-owner''s edit of her own private note is stored'
);

-- ---------------------------------------------------------------------------
-- 7. Whose relationship edit moves the marker, and what a private note
--    holds in place.
--
--    A relationship edit moves the marker only when it is the owner's own
--    statement about her own profile: the caller is the profile's accepted
--    primary guardian. Anyone else's edit -- a co-parent's, or one made with
--    no auth.uid() at all -- leaves every marker as it was, in both
--    directions. And the owner's own edit away from self does not clear her
--    marker while a live day entry of the profile carries a private note,
--    so changing a description field can never unmask one.
--
--    Every edit by a person below goes through sync_push as that person.
--    That is also the proof that the SECURITY DEFINER trigger function
--    still reads the caller's id when it fires from inside the SECURITY
--    DEFINER RPC: the owner's push moves the marker and the co-parent's
--    identical push does not.
-- ---------------------------------------------------------------------------
create function pg_temp.private_note_masked(p_entry text)
returns boolean language sql as $$
  select (e ->> 'note') is null and (e ->> 'note_private') = 'true'
    from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'day_entries') e
   where e ->> 'id' = p_entry
$$;

-- 7a. Nora's self profile (9120) with Omar as co-parent. No private notes,
--     so nothing but the caller decides what happens here.
select tests.create_supabase_user('nora');
select tests.create_supabase_user('omar');
select tests.authenticate_as('nora');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9120), 'co_parent', 'Omar', pg_temp.token(81), 48);
select tests.authenticate_as('omar');
select public.accept_guardian_invitation(pg_temp.token(81), 'Omar');
select tests.authenticate_as('nora');
select pg_temp.remember_cursor('nora');

-- A co-parent changes self to another relationship.
select tests.authenticate_as('omar');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"partner"}');
select is(
  (select relationship from public.profiles where id = tests.ulid(9120)),
  'partner',
  'who: setup -- a co-parent''s relationship edit is itself applied to the profile'
);
select is(
  pg_temp.marker(tests.ulid(9120), 'nora'),
  'primary_guardian:accepted:true',
  'who: a co-parent changing self to another relationship leaves the owner''s marker'
);
select tests.authenticate_as('nora');
select is(
  pg_temp.pulled_marker('nora', tests.ulid(9120), 'nora'),
  'absent',
  'who: and writes nothing to the owner''s membership row'
);

-- The owner makes the same kind of edit herself (back to self, then away):
-- hers is the edit that counts.
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"self"}');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"other"}');
select is(
  pg_temp.marker(tests.ulid(9120), 'nora'),
  'primary_guardian:accepted:false',
  'who: the owner changing self to another relationship herself, with no private note, clears her marker'
);

-- A co-parent changes another relationship to self.
select tests.authenticate_as('omar');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9120), 'nora') || ' / ' || pg_temp.marker(tests.ulid(9120), 'omar'),
  'primary_guardian:accepted:false / co_parent:accepted:false',
  'who: a co-parent changing a relationship to self stamps nobody'
);

-- 7b. No auth.uid() at all (the service role): neither direction. The
--     profile stands at self with its owner unmarked; away and back to self
--     must not stamp her.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
update public.profiles set relationship = 'other' where id = tests.ulid(9120);
update public.profiles set relationship = 'self' where id = tests.ulid(9120);
select tests.clear_authentication();
select is(
  pg_temp.marker(tests.ulid(9120), 'nora'),
  'primary_guardian:accepted:false',
  'who: a change to self made with no auth.uid() (the service role) stamps nobody'
);

-- The owner says it herself (away, then to self): stamped.
select tests.authenticate_as('nora');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"other"}');
select pg_temp.push_profile(tests.ulid(9120), '{"display_name":"Nora","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9120), 'nora'),
  'primary_guardian:accepted:true',
  'who: the owner changing another relationship to self herself stamps her'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
update public.profiles set relationship = 'other' where id = tests.ulid(9120);
select tests.clear_authentication();
select is(
  pg_temp.marker(tests.ulid(9120), 'nora'),
  'primary_guardian:accepted:true',
  'who: a change away from self made with no auth.uid() (the service role) leaves the marker'
);

-- 7c. Private notes, on Bea's profile (9104): she is its subject, Gus is a
--     co-parent, and entry 9150 is a live day entry with a private note.
--     First the co-parent's edit away from self.
select tests.authenticate_as('gus');
select pg_temp.push_profile(tests.ulid(9104), '{"display_name":"Bea","relationship":"partner"}');
select is(
  pg_temp.marker(tests.ulid(9104), 'bea'),
  'primary_guardian:accepted:true',
  'private note: a co-parent changing self to another relationship leaves the owner the subject'
);
select is(
  pg_temp.private_note_masked(tests.ulid(9150)),
  true,
  'private note: and that co-parent''s pull of her private note is still masked'
);

-- Then the owner's own edit away from self, while the private note is live.
select tests.authenticate_as('bea');
select pg_temp.push_profile(tests.ulid(9104), '{"display_name":"Bea","relationship":"self"}');
select pg_temp.push_profile(tests.ulid(9104), '{"display_name":"Bea","relationship":"other"}');
select is(
  pg_temp.marker(tests.ulid(9104), 'bea'),
  'primary_guardian:accepted:true',
  'private note: the owner changing self to another relationship keeps her marker while a live entry has a private note'
);
select tests.authenticate_as('gus');
select is(
  pg_temp.private_note_masked(tests.ulid(9150)),
  true,
  'private note: and the co-parent''s pull stays masked after the owner''s own edit'
);

-- Then she deletes that entry. A private note only on a deleted entry holds
-- nothing in place.
select tests.authenticate_as('bea');
select is(
  jsonb_array_length(public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(9150), 'profile_id', tests.ulid(9104), 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'none',
      'updated_at', '2026-09-03T10:00:00Z', 'deleted_at', '2026-09-03T10:00:00Z'))
  ) -> 'rejected'),
  0,
  'private note: setup -- the owner deletes the entry that carried it'
);
select tests.clear_authentication();
select is(
  (select (deleted_at is not null)::text || ':' || note_private::text || ':' || coalesce(note, 'null')
     from public.day_entries where id = tests.ulid(9150)),
  'true:true:null',
  'private note: setup -- the deleted entry still carries note_private, and no text'
);
select tests.authenticate_as('bea');
select pg_temp.push_profile(tests.ulid(9104), '{"display_name":"Bea","relationship":"self"}');
select pg_temp.push_profile(tests.ulid(9104), '{"display_name":"Bea","relationship":"partner"}');
select is(
  pg_temp.marker(tests.ulid(9104), 'bea'),
  'primary_guardian:accepted:false',
  'private note: a private note only on a deleted entry does not hold the marker in place'
);

-- ---------------------------------------------------------------------------
-- 8. A primary_guardian row that BECOMES accepted is stamped by the same
--    rule (no client path does this today; the rule holds on any path).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
select pg_temp.push_profile(tests.ulid(9108), '{"display_name":"Eve","relationship":"self"}');
select tests.clear_authentication();
update public.profile_guardians
   set status = 'pending', is_subject = null
 where profile_id = tests.ulid(9108) and user_id = tests.get_supabase_uid('eve');
select is(
  pg_temp.marker(tests.ulid(9108), 'eve'),
  'primary_guardian:pending:null',
  'accepted: setup -- a pending primary guardian row carries no marker'
);
update public.profile_guardians
   set status = 'accepted'
 where profile_id = tests.ulid(9108) and user_id = tests.get_supabase_uid('eve');
select is(
  pg_temp.marker(tests.ulid(9108), 'eve'),
  'primary_guardian:accepted:true',
  'accepted: a primary guardian row that becomes accepted on a self profile is stamped'
);
-- The same transition on a profile that is not self stamps nothing.
update public.profile_guardians
   set status = 'pending'
 where profile_id = tests.ulid(9102) and user_id = tests.get_supabase_uid('mom');
update public.profile_guardians
   set status = 'accepted'
 where profile_id = tests.ulid(9102) and user_id = tests.get_supabase_uid('mom');
select is(
  pg_temp.marker(tests.ulid(9102), 'mom'),
  'primary_guardian:accepted:false',
  'accepted: the same transition on a profile that is not self stamps nothing'
);
-- Nor does it stamp the owner beside an invited subject (Ana's, 9101).
update public.profile_guardians
   set status = 'pending'
 where profile_id = tests.ulid(9101) and user_id = tests.get_supabase_uid('ana');
update public.profile_guardians
   set status = 'accepted'
 where profile_id = tests.ulid(9101) and user_id = tests.get_supabase_uid('ana');
select is(
  pg_temp.marker(tests.ulid(9101), 'ana') || ' / ' || pg_temp.marker(tests.ulid(9101), 'cora'),
  'primary_guardian:accepted:false / caregiver:accepted:true',
  'accepted: a primary guardian row that becomes accepted beside an invited subject is not stamped'
);

-- ---------------------------------------------------------------------------
-- 9. The backfill (simulate-then-reconcile). Stand the fixtures up through
--    the real RPCs, strip the markers the triggers stamped to recreate the
--    rows as they stood before the migration, then run the migration's
--    statement verbatim as the migration role.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('zoe');        -- live self profile, no subject        -> stamped
select tests.create_supabase_user('yan');        -- daughter profile                     -> untouched
select tests.create_supabase_user('xia');        -- deleted self profile                 -> untouched
select tests.create_supabase_user('wen');        -- self, accepted invited subject       -> untouched
select tests.create_supabase_user('wen_guest');
select tests.create_supabase_user('val');        -- self, invited subject since revoked  -> stamped
select tests.create_supabase_user('val_guest');
select tests.create_supabase_user('uma');        -- no relationship                      -> untouched

select tests.authenticate_as('zoe');
select pg_temp.push_profile(tests.ulid(9110), '{"display_name":"Zoe","relationship":"self"}');
select tests.authenticate_as('yan');
select pg_temp.push_profile(tests.ulid(9111), '{"display_name":"Yan child","relationship":"daughter","is_minor":true}');
select tests.authenticate_as('xia');
select pg_temp.push_profile(tests.ulid(9112), '{"display_name":"Xia","relationship":"self"}');
select tests.authenticate_as('wen');
select pg_temp.push_profile(tests.ulid(9113), '{"display_name":"Wen","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9113), 'caregiver', 'Guest', pg_temp.token(71), 48, true);
select tests.authenticate_as('wen_guest');
select public.accept_guardian_invitation(pg_temp.token(71), 'Guest');
select tests.authenticate_as('val');
select pg_temp.push_profile(tests.ulid(9114), '{"display_name":"Val","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9114), 'caregiver', 'Guest', pg_temp.token(72), 48, true);
select tests.authenticate_as('val_guest');
select public.accept_guardian_invitation(pg_temp.token(72), 'Guest');
select tests.authenticate_as('val');
select public.revoke_guardian(tests.ulid(9114), tests.get_supabase_uid('val_guest'));
select tests.authenticate_as('uma');
select pg_temp.push_profile(tests.ulid(9115), '{"display_name":"Uma child"}');
-- A transferred profile that is self and whose owner already carries the
-- marker (Kid's, 9105): the backfill must not write to it.
select tests.authenticate_as('kid');
select pg_temp.push_profile(tests.ulid(9105), '{"display_name":"Kit","relationship":"self"}');

-- Recreate the pre-migration rows: soft-delete Xia's profile, and strip
-- the marker from every self-profile owner above.
select tests.clear_authentication();
update public.profiles
   set deleted_at = now(), display_name = ''
 where id = tests.ulid(9112);
update public.profile_guardians
   set is_subject = null
 where role = 'primary_guardian'
   and profile_id in (tests.ulid(9110), tests.ulid(9112), tests.ulid(9113), tests.ulid(9114));

select is(
  pg_temp.marker(tests.ulid(9110), 'zoe') || ' / ' || pg_temp.marker(tests.ulid(9114), 'val')
    || ' / ' || pg_temp.marker(tests.ulid(9114), 'val_guest'),
  'primary_guardian:accepted:null / primary_guardian:accepted:null / caregiver:revoked:true',
  'backfill: setup -- self-profile owners with no marker, as before the migration'
);

-- Zoe's and Yan's devices have both already synced.
select tests.authenticate_as('zoe');
select pg_temp.remember_cursor('zoe');
select tests.authenticate_as('yan');
select pg_temp.remember_cursor('yan');
select tests.clear_authentication();

create temp table before_backfill as
  select id, server_version from public.profile_guardians;

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

select is(
  (select array_agg(p.display_name order by p.display_name)
     from public.profile_guardians g
     join before_backfill b on b.id = g.id
     join public.profiles p on p.id = g.profile_id
    where g.server_version <> b.server_version),
  array['Val', 'Zoe'],
  'backfill: across the whole table, exactly the two rows the rule describes were written'
);
select is(
  pg_temp.marker(tests.ulid(9110), 'zoe'),
  'primary_guardian:accepted:true',
  'backfill: the owner of a live self profile with no subject is stamped'
);
select is(
  pg_temp.marker(tests.ulid(9114), 'val') || ' / ' || pg_temp.marker(tests.ulid(9114), 'val_guest'),
  'primary_guardian:accepted:true / caregiver:revoked:true',
  'backfill: a revoked invited subject does not count -- the owner is stamped'
);
select is(
  pg_temp.marker(tests.ulid(9111), 'yan'),
  'primary_guardian:accepted:null',
  'backfill: the owner of a daughter profile is untouched'
);
select is(
  pg_temp.marker(tests.ulid(9112), 'xia'),
  'primary_guardian:accepted:null',
  'backfill: the owner of a deleted self profile is untouched'
);
select is(
  pg_temp.marker(tests.ulid(9113), 'wen') || ' / ' || pg_temp.marker(tests.ulid(9113), 'wen_guest'),
  'primary_guardian:accepted:null / caregiver:accepted:true',
  'backfill: a self profile that already has an accepted subject keeps that one subject'
);
select is(
  pg_temp.marker(tests.ulid(9115), 'uma'),
  'primary_guardian:accepted:null',
  'backfill: the owner of a profile with no relationship is untouched'
);

select tests.authenticate_as('zoe');
select is(
  pg_temp.pulled_marker('zoe', tests.ulid(9110), 'zoe'),
  'true',
  'pull: a backfilled row reaches a device that had already synced'
);
select tests.authenticate_as('yan');
select is(
  pg_temp.pulled_marker('yan', tests.ulid(9111), 'yan'),
  'absent',
  'pull: a row the backfill did not touch is not sent again'
);
select tests.clear_authentication();

-- Idempotence: the same statement again writes nothing.
create temp table before_rerun as
  select id, server_version from public.profile_guardians;

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

select is(
  (select count(*)
     from public.profile_guardians g
     join before_rerun b on b.id = g.id
    where g.server_version <> b.server_version),
  0::bigint,
  'backfill: re-running the statement is idempotent (no row is written)'
);

select * from finish();
rollback;
