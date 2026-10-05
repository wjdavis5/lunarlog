-- Coverage for Issue #1499 (20261005143105_self_profile_subject.sql): the
-- person who creates a profile for herself is its subject.
--
-- The rule: on a profile whose relationship is 'self', the accepted
-- primary_guardian membership carries profile_guardians.is_subject (#802).
-- This file pins, through the real RPCs wherever a client would use one:
--
--   1. Catalog: the four triggers, their SECURITY DEFINER / search_path /
--      EXECUTE posture, and that the marker is still unwritable by a client.
--   2. Creation: a 'self' profile makes its creator the subject; a profile
--      created with another relationship (or none) does not.
--   3. Relationship changes by the owner: to 'self' stamps, away from
--      'self' clears, and an edit that does not move the relationship
--      across 'self' writes nothing to the membership row.
--   4. Ownership transfer: a transferred profile keeps its subject whatever
--      the relationship then does, and transferring a profile whose owner
--      is the subject ends with exactly one subject, the acceptor, whether
--      or not she was already a member.
--   5. One subject per profile, and whoever holds the marker keeps it: a
--      subject invitation is refused while the profile has an accepted
--      subject (for a co-parent and for the owner alike), a subject
--      invitation created earlier and accepted later joins its invitee
--      without the marker, and the route by which a co-parent could read
--      the owner's private note through a second account is closed.
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
select plan(95);

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

-- A private day note written through the real sync_push, as the current
-- caller. Raises when the server rejects it.
create function pg_temp.push_private_note(p_entry text, p_profile text, p_text text)
returns void language plpgsql as $$
declare
  v_result jsonb;
begin
  v_result := public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', p_entry, 'profile_id', p_profile, 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'light', 'note', p_text, 'note_private', true,
      'updated_at', '2026-09-01T10:00:00Z')));
  if v_result -> 'rejected' <> '[]'::jsonb then
    raise exception 'fixture private note % was rejected: %', p_entry, v_result;
  end if;
end;
$$;

-- What the current caller's own full pull shows for one day entry's note:
-- its text; '<masked>' when the entry arrives with note NULL and
-- note_private true; or 'absent' when the entry is not in her pull at all.
create function pg_temp.pulled_note(p_entry text)
returns text language sql as $$
  select coalesce(
    (select case
              when (e ->> 'note') is null and (e ->> 'note_private') = 'true' then '<masked>'
              else coalesce(e ->> 'note', '<null>')
            end
       from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'day_entries') e
      where e ->> 'id' = p_entry),
    'absent')
$$;

create function pg_temp.private_note_masked(p_entry text)
returns boolean language sql as $$
  select pg_temp.pulled_note(p_entry) = '<masked>'
$$;

select tests.create_supabase_user('ana');
select tests.create_supabase_user('bea');
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('kid');
select tests.create_supabase_user('tess');
select tests.create_supabase_user('riley');
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
        ('public.profile_guardians'::regclass, 'profile_guardians_unmark_second_subject'),
        ('public.profiles'::regclass, 'profiles_after_relationship_self_subject'),
        ('public.guardian_invitations'::regclass, 'guardian_invitations_refuse_second_subject'))),
  4::bigint,
  'catalog: the four issue #1499 triggers exist on their tables'
);
select is(
  (select count(*) from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('stamp_self_profile_subject_membership',
                        'sync_self_profile_subject_marker',
                        'unmark_second_profile_subject',
                        'refuse_second_subject_invitation')
      and p.prosecdef
      and p.proconfig = array['search_path=""']::text[]),
  4::bigint,
  'catalog: the four trigger functions are SECURITY DEFINER with an empty search_path'
);
-- Counted over pg_proc (rather than naming each signature) so the
-- assertion fails, instead of raising, where a function is missing. A
-- grant to PUBLIC would show up here too: both roles inherit it.
select is(
  (select count(*) from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname in ('stamp_self_profile_subject_membership',
                        'sync_self_profile_subject_marker',
                        'unmark_second_profile_subject',
                        'refuse_second_subject_invitation')
      and not has_function_privilege('anon', p.oid, 'execute')
      and not has_function_privilege('authenticated', p.oid, 'execute')),
  4::bigint,
  'catalog: none of the four functions is executable by anon or authenticated'
);
-- Nothing takes the marker from its holder when an invitation is accepted:
-- the function that used to do that is gone.
select is(
  (select count(*) from pg_catalog.pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and p.proname = 'yield_self_profile_subject_marker')
  + (select count(*) from pg_catalog.pg_trigger t
      where t.tgname = 'profile_guardians_after_subject_yield_self'),
  0::bigint,
  'catalog: no function or trigger clears the holder''s marker when an invitation is accepted'
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

-- 4c. The same when the acceptor is already a member, so the transfer's
--     upsert UPDATEs her row instead of inserting it: Vera's self profile
--     (9123), with Will already a caregiver on it. The transfer writes the
--     primary_guardian role and the marker in one statement, so the row is
--     the primary guardian's at the moment the marker lands and the
--     second-subject rule of section 5 has nothing to strip.
select tests.create_supabase_user('vera');
select tests.create_supabase_user('will');
select tests.authenticate_as('vera');
select pg_temp.push_profile(tests.ulid(9123), '{"display_name":"Vera","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9123), 'caregiver', 'Will', pg_temp.token(43), 48);
select tests.authenticate_as('will');
select public.accept_guardian_invitation(pg_temp.token(43), 'Will');
select tests.authenticate_as('vera');
select public.create_ownership_transfer(tests.ulid(9123), 'co_parent', pg_temp.token(44));
select tests.authenticate_as('will');
select public.accept_ownership_transfer(pg_temp.token(44), 'Will', 'Vera');
select is(
  pg_temp.marker(tests.ulid(9123), 'will') || ' / ' || pg_temp.marker(tests.ulid(9123), 'vera'),
  'primary_guardian:accepted:true / co_parent:accepted:false',
  'transfer: an acceptor who was already a member ends as primary guardian and subject, the former owner unmarked'
);
select is(
  pg_temp.subject_count(tests.ulid(9123)),
  1::bigint,
  'transfer: exactly one subject, the acceptor, after a transfer to an existing member'
);

-- ---------------------------------------------------------------------------
-- 5. One subject per profile, and whoever holds the marker keeps it.
--
--    An invitation never takes the marker from its holder. A subject
--    invitation cannot be created while the profile has an accepted
--    subject; and one that was created earlier, while there was none, and
--    is accepted later joins its invitee with her role and without the
--    marker.
-- ---------------------------------------------------------------------------
-- 5a. A daughter's profile with no subject (Mom's, 9107): the subject
--     invitation is created and accepted exactly as before.
select tests.authenticate_as('mom');
select pg_temp.push_profile(tests.ulid(9107), '{"display_name":"Riley","relationship":"daughter","is_minor":true}');
select public.create_guardian_invitation(tests.ulid(9107), 'caregiver', 'Riley', pg_temp.token(51), 48, true);
select tests.authenticate_as('riley');
select public.accept_guardian_invitation(pg_temp.token(51), 'Riley');
select is(
  pg_temp.marker(tests.ulid(9107), 'mom') || ' / ' || pg_temp.marker(tests.ulid(9107), 'riley'),
  'primary_guardian:accepted:null / caregiver:accepted:true',
  'one subject: on a profile with no subject, a subject invitation is created and accepted as before'
);

-- A second subject invitation on that profile is then refused. The code
-- and the wording are pinned exactly: both clients' error ladders are
-- tested against this very message (the generic invitation failure), in
-- test/data/sharing/supabase_sharing_service_test.dart and
-- webapp/test/sharing.test.ts.
select tests.authenticate_as('mom');
select throws_ok(
  format($$select public.create_guardian_invitation(%L, 'caregiver', 'Second', %L, 48, true)$$,
         tests.ulid(9107), pg_temp.token(59)),
  'P0001',
  'this profile already has a subject; a subject invitation cannot be created for it',
  'one subject: a second subject invitation is refused while the profile has an accepted subject'
);
select tests.clear_authentication();
select is(
  (select count(*) from public.guardian_invitations where token_hash = pg_temp.token(59)),
  0::bigint,
  'one subject: and the refused invitation leaves no row'
);

-- Mom calling the profile self does not make her a second subject, however
-- often she says it.
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
select pg_temp.push_profile(tests.ulid(9107), '{"display_name":"Riley","relationship":"other"}');
select pg_temp.push_profile(tests.ulid(9107), '{"display_name":"Riley","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9107), 'mom') || ' / ' || pg_temp.marker(tests.ulid(9107), 'riley'),
  'primary_guardian:accepted:null / caregiver:accepted:true',
  'one subject: the relationship returning to self does not stamp the owner beside an invited subject'
);

-- 5b. A self profile whose owner is the subject (Pia's, 9121), with a
--     co-parent (Quin) and a private note. Before this rule Quin could
--     create a "this is your profile" invitation and have another account
--     (Rex) accept it: Rex then read Pia's private note in full, and Pia
--     lost the marker and, with it, her own note.
select tests.create_supabase_user('pia');
select tests.create_supabase_user('quin');
select tests.create_supabase_user('rex');
select tests.authenticate_as('pia');
select pg_temp.push_profile(tests.ulid(9121), '{"display_name":"Pia","relationship":"self"}');
select public.create_guardian_invitation(tests.ulid(9121), 'co_parent', 'Quin', pg_temp.token(60), 48);
select tests.authenticate_as('quin');
select public.accept_guardian_invitation(pg_temp.token(60), 'Quin');
select tests.authenticate_as('pia');
select pg_temp.push_private_note(tests.ulid(9151), tests.ulid(9121), 'only for Pia');

select tests.authenticate_as('quin');
select throws_ok(
  format($$select public.create_guardian_invitation(%L, 'caregiver', 'Rex', %L, 48, true)$$,
         tests.ulid(9121), pg_temp.token(57)),
  'P0001', null,
  'holder keeps it: a co-parent cannot create a subject invitation on a profile whose owner is the subject'
);
select tests.clear_authentication();
select is(
  (select count(*) from public.guardian_invitations
    where profile_id = tests.ulid(9121) and is_subject),
  0::bigint,
  'holder keeps it: no subject invitation exists for that profile'
);
select tests.authenticate_as('rex');
select throws_ok(
  format($$select public.accept_guardian_invitation(%L, 'Rex')$$, pg_temp.token(57)),
  'P0002', null,
  'holder keeps it: the account the co-parent meant to use has nothing to accept'
);
select is(
  pg_temp.pulled_note(tests.ulid(9151)),
  'absent',
  'holder keeps it: that account reads nothing of the profile'
);
select tests.authenticate_as('quin');
select is(
  pg_temp.pulled_note(tests.ulid(9151)),
  '<masked>',
  'holder keeps it: the co-parent''s own pull of the private note is still masked'
);
select tests.authenticate_as('pia');
select is(
  pg_temp.marker(tests.ulid(9121), 'pia') || ' / ' || pg_temp.pulled_note(tests.ulid(9151)),
  'primary_guardian:accepted:true / only for Pia',
  'holder keeps it: the owner is still the subject and still reads her own private note'
);
-- The owner herself is refused too: she holds the marker until she says
-- the profile is not her own.
select throws_ok(
  format($$select public.create_guardian_invitation(%L, 'caregiver', 'Rex', %L, 48, true)$$,
         tests.ulid(9121), pg_temp.token(61)),
  'P0001', null,
  'holder keeps it: the owner herself cannot create a subject invitation while she holds the marker'
);
-- A plain invitation on the same profile is not refused.
select lives_ok(
  format($$select public.create_guardian_invitation(%L, 'caregiver', 'Helper', %L, 48)$$,
         tests.ulid(9121), pg_temp.token(62)),
  'holder keeps it: a plain invitation is still created on that profile'
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

-- 5d. The stale invitation. A subject invitation is created while the
--     profile has no subject (Sam's, 9122, not yet called self). Sam then
--     becomes its subject and writes a private note. Only then is the old
--     invitation accepted: Tia joins with the role she was invited to, and
--     without the marker.
select tests.create_supabase_user('sam');
select tests.create_supabase_user('tia');
select tests.authenticate_as('sam');
select pg_temp.push_profile(tests.ulid(9122), '{"display_name":"Sam","relationship":"other"}');
select public.create_guardian_invitation(tests.ulid(9122), 'caregiver', 'Tia', pg_temp.token(58), 48, true);
select pg_temp.push_profile(tests.ulid(9122), '{"display_name":"Sam","relationship":"self"}');
select pg_temp.push_private_note(tests.ulid(9152), tests.ulid(9122), 'only for Sam');
select pg_temp.remember_cursor('sam');
select tests.authenticate_as('tia');
select public.accept_guardian_invitation(pg_temp.token(58), 'Tia');
select is(
  pg_temp.marker(tests.ulid(9122), 'tia'),
  'caregiver:accepted:false',
  'stale invitation: the invitee joins with her role and without the marker'
);
select is(
  pg_temp.marker(tests.ulid(9122), 'sam') || ' / ' || pg_temp.subject_count(tests.ulid(9122))::text,
  'primary_guardian:accepted:true / 1',
  'stale invitation: the owner keeps the marker and is the only subject'
);
select is(
  pg_temp.pulled_note(tests.ulid(9152)),
  '<masked>',
  'stale invitation: the invitee''s pull of the owner''s private note is masked'
);
select tests.authenticate_as('sam');
select is(
  pg_temp.pulled_note(tests.ulid(9152)),
  'only for Sam',
  'stale invitation: the owner still reads her own private note'
);
select is(
  pg_temp.pulled_marker('sam', tests.ulid(9122), 'sam') || ' / ' || pg_temp.pulled_marker('sam', tests.ulid(9122), 'tia'),
  'absent / false',
  'pull: the owner''s synced device receives the new member''s row, and nothing was written to her own'
);

-- 5e. The same on accept_guardian_invitation's other branch, where the
--     invitee already has a (revoked) row and the accept UPDATEs it. Hana's
--     profile (9109), not yet called self; Ivy is a former member.
select tests.create_supabase_user('hana');
select tests.create_supabase_user('ivy');
select tests.authenticate_as('hana');
select pg_temp.push_profile(tests.ulid(9109), '{"display_name":"Hana","relationship":"other"}');
select public.create_guardian_invitation(tests.ulid(9109), 'caregiver', 'Ivy', pg_temp.token(55), 48);
select tests.authenticate_as('ivy');
select public.accept_guardian_invitation(pg_temp.token(55), 'Ivy');
select tests.authenticate_as('hana');
select public.revoke_guardian(tests.ulid(9109), tests.get_supabase_uid('ivy'));
-- With no subject on the profile, re-inviting her as its subject marks her.
select public.create_guardian_invitation(tests.ulid(9109), 'caregiver', 'Ivy', pg_temp.token(56), 48, true);
select tests.authenticate_as('ivy');
select public.accept_guardian_invitation(pg_temp.token(56), 'Ivy');
select is(
  pg_temp.marker(tests.ulid(9109), 'ivy'),
  'caregiver:accepted:true',
  'stale invitation: a former member re-invited as the subject of a profile with none is marked (unchanged)'
);
-- She is removed again and invited again, while the profile has no accepted
-- subject; then Hana says the profile is her own. A revoked membership is
-- not a subject, so Hana is stamped.
select tests.authenticate_as('hana');
select public.revoke_guardian(tests.ulid(9109), tests.get_supabase_uid('ivy'));
select public.create_guardian_invitation(tests.ulid(9109), 'caregiver', 'Ivy', pg_temp.token(63), 48, true);
select pg_temp.push_profile(tests.ulid(9109), '{"display_name":"Hana","relationship":"self"}');
select is(
  pg_temp.marker(tests.ulid(9109), 'hana') || ' / ' || pg_temp.marker(tests.ulid(9109), 'ivy'),
  'primary_guardian:accepted:true / caregiver:revoked:true',
  'one subject: a revoked invited subject does not stop the owner being stamped when the profile becomes self'
);
select tests.authenticate_as('ivy');
select public.accept_guardian_invitation(pg_temp.token(63), 'Ivy');
select is(
  pg_temp.marker(tests.ulid(9109), 'hana') || ' / ' || pg_temp.marker(tests.ulid(9109), 'ivy'),
  'primary_guardian:accepted:true / caregiver:accepted:false',
  'stale invitation: re-accepting over a revoked row does not take the marker from its holder either'
);
select is(
  pg_temp.subject_count(tests.ulid(9109)),
  1::bigint,
  'stale invitation: exactly one subject after the re-accepted invitation'
);

-- 5f. The holder may be an owner whose marker came from a transfer (Tess's
--     profile, 9106): a subject invitation is refused there the same way.
select tests.authenticate_as('tess');
select throws_ok(
  format($$select public.create_guardian_invitation(%L, 'caregiver', 'Ines', %L, 48, true)$$,
         tests.ulid(9106), pg_temp.token(54)),
  'P0001', null,
  'holder keeps it: a subject invitation is refused on a transferred profile whose owner is the subject'
);

-- 5g. Only an ACCEPTED subject holds the marker. Once the invited subject
--     has been removed, the profile has none: the next subject invitation
--     is created, and whoever accepts it is marked (Abe's daughter profile,
--     9125; Bo, then Cy).
select tests.create_supabase_user('abe');
select tests.create_supabase_user('bo');
select tests.create_supabase_user('cy');
select tests.authenticate_as('abe');
select pg_temp.push_profile(tests.ulid(9125), '{"display_name":"Dee","relationship":"daughter","is_minor":true}');
select public.create_guardian_invitation(tests.ulid(9125), 'caregiver', 'Bo', pg_temp.token(64), 48, true);
select tests.authenticate_as('bo');
select public.accept_guardian_invitation(pg_temp.token(64), 'Bo');
select tests.authenticate_as('abe');
select public.revoke_guardian(tests.ulid(9125), tests.get_supabase_uid('bo'));
select public.create_guardian_invitation(tests.ulid(9125), 'caregiver', 'Cy', pg_temp.token(65), 48, true);
select tests.authenticate_as('cy');
select public.accept_guardian_invitation(pg_temp.token(65), 'Cy');
select is(
  pg_temp.marker(tests.ulid(9125), 'bo') || ' / ' || pg_temp.marker(tests.ulid(9125), 'cy'),
  'caregiver:revoked:true / caregiver:accepted:true',
  'one subject: a removed subject holds nothing -- the next subject invitation is created and its invitee is marked'
);

-- 5h. Unchanged, and NOT one subject: an ownership transfer writes its
--     marker unconditionally, so a transfer to someone other than the
--     invited subject leaves both marked, as it did before issue #1499
--     (Xena's daughter profile, 9124: Yara is its invited subject, Zed
--     accepts the transfer). Pinned so that the second-subject rule is
--     seen not to reach the primary guardian's row.
select tests.create_supabase_user('xena');
select tests.create_supabase_user('yara');
select tests.create_supabase_user('zed');
select tests.authenticate_as('xena');
select pg_temp.push_profile(tests.ulid(9124), '{"display_name":"Yara","relationship":"daughter","is_minor":true}');
select public.create_guardian_invitation(tests.ulid(9124), 'caregiver', 'Yara', pg_temp.token(66), 48, true);
select tests.authenticate_as('yara');
select public.accept_guardian_invitation(pg_temp.token(66), 'Yara');
select tests.authenticate_as('xena');
select public.create_ownership_transfer(tests.ulid(9124), 'co_parent', pg_temp.token(67));
select tests.authenticate_as('zed');
select public.accept_ownership_transfer(pg_temp.token(67), 'Zed', 'Xena');
select is(
  pg_temp.marker(tests.ulid(9124), 'zed') || ' / ' || pg_temp.marker(tests.ulid(9124), 'yara')
    || ' / ' || pg_temp.marker(tests.ulid(9124), 'xena'),
  'primary_guardian:accepted:true / caregiver:accepted:true / co_parent:accepted:false',
  'transfer: (unchanged) a transfer to someone other than the invited subject still marks the acceptor, leaving two subjects'
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
-- Nor does it stamp the owner beside an invited subject (Mom's profile
-- 9107: its relationship is self, and Riley is its subject).
update public.profile_guardians
   set status = 'pending'
 where profile_id = tests.ulid(9107) and user_id = tests.get_supabase_uid('mom');
update public.profile_guardians
   set status = 'accepted'
 where profile_id = tests.ulid(9107) and user_id = tests.get_supabase_uid('mom');
select is(
  pg_temp.marker(tests.ulid(9107), 'mom') || ' / ' || pg_temp.marker(tests.ulid(9107), 'riley'),
  'primary_guardian:accepted:null / caregiver:accepted:true',
  'accepted: a primary guardian row that becomes accepted beside an invited subject is not stamped'
);
-- And the holder's own row being written again is not "a second subject":
-- Riley, the only subject of 9107, keeps the marker.
update public.profile_guardians
   set status = 'accepted', is_subject = true
 where profile_id = tests.ulid(9107) and user_id = tests.get_supabase_uid('riley');
select is(
  pg_temp.marker(tests.ulid(9107), 'riley'),
  'caregiver:accepted:true',
  'accepted: writing the holder''s own row again does not unmark her'
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
-- (A subject invitation can only be created while the profile has no
-- subject, so Wen's and Val's profiles are called self after their guests
-- have accepted.)
select tests.authenticate_as('wen');
select pg_temp.push_profile(tests.ulid(9113), '{"display_name":"Wen","relationship":"other"}');
select public.create_guardian_invitation(tests.ulid(9113), 'caregiver', 'Guest', pg_temp.token(71), 48, true);
select tests.authenticate_as('wen_guest');
select public.accept_guardian_invitation(pg_temp.token(71), 'Guest');
select tests.authenticate_as('wen');
select pg_temp.push_profile(tests.ulid(9113), '{"display_name":"Wen","relationship":"self"}');
select tests.authenticate_as('val');
select pg_temp.push_profile(tests.ulid(9114), '{"display_name":"Val","relationship":"other"}');
select public.create_guardian_invitation(tests.ulid(9114), 'caregiver', 'Guest', pg_temp.token(72), 48, true);
select tests.authenticate_as('val_guest');
select public.accept_guardian_invitation(pg_temp.token(72), 'Guest');
select tests.authenticate_as('val');
select public.revoke_guardian(tests.ulid(9114), tests.get_supabase_uid('val_guest'));
select pg_temp.push_profile(tests.ulid(9114), '{"display_name":"Val","relationship":"self"}');
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
