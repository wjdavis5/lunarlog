-- Issue #867: revoke_guardian never removes the revoked author's guardian notes,
-- contradicting PRIVACY.md; orphaned notes become un-removable.
--
-- Pins:
--   1. revoking a guardian tombstones and body-clears their guardian notes for that profile
--   2. the tombstone stamps last_modified_by_user_id to the revoking guardian
--   3. remaining guardians can pull/read the tombstoned row
--   4. the revoked guardian can no longer read any notes for the profile via RLS
--   5. self-leaving via revoke_guardian tombstones the leaving guardian's notes
--   6. when an author's account is deleted (logged_by_user_id is null):
--      - a caregiver cannot edit or tombstone the orphaned note
--      - the primary_guardian cannot edit the orphaned note (non-tombstone)
--      - the primary_guardian CAN tombstone the orphaned note via sync_push

begin;
select plan(26);

-- ---------------------------------------------------------------------------
-- temp helpers
-- ---------------------------------------------------------------------------
create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;

-- ---------------------------------------------------------------------------
-- 1. Structural check
-- ---------------------------------------------------------------------------
select ok(
  (select obj_description('public.revoke_guardian(text, uuid)'::regprocedure)
     like '%Issue #867%'),
  'revoke_guardian function comment documents Issue #867'
); -- 1

select ok(
  (select obj_description('public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)'::regprocedure)
     like '%Issue #867%'),
  'sync_push function comment documents Issue #867'
); -- 2

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian), nanny (caregiver), dad (co_parent) on
-- profile 867
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom_867');
select tests.create_supabase_user('nanny_867');
select tests.create_supabase_user('dad_867');
select tests.create_supabase_user('sitter_867');

select tests.authenticate_as('mom_867');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(867), 'Sam', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(867), 'caregiver', 'Nanny',
  '1111111111111111111111111111111111111111111111111111111111111111', 48);
select public.create_guardian_invitation(tests.ulid(867), 'co_parent', 'Dad',
  '2222222222222222222222222222222222222222222222222222222222222222', 48);

select tests.authenticate_as('nanny_867');
select public.accept_guardian_invitation(
  '1111111111111111111111111111111111111111111111111111111111111111', 'Nanny');

select tests.authenticate_as('dad_867');
select public.accept_guardian_invitation(
  '2222222222222222222222222222222222222222222222222222222222222222', 'Dad');

-- ---------------------------------------------------------------------------
-- Part 1: Nanny writes a note; Mom revokes Nanny -> note is tombstoned
-- ---------------------------------------------------------------------------
select tests.authenticate_as('nanny_867');
insert into r select 'nanny_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8671), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-15', 'tz', 'America/New_York',
    'body', 'Nanny note for Sam: ate lunch well.',
    'updated_at', '2026-09-15T12:00:00Z')));

select is((select body from public.guardian_notes where id = tests.ulid(8671)),
  'Nanny note for Sam: ate lunch well.',
  'nanny note is initially live with content'); -- 3
select is((select deleted_at from public.guardian_notes where id = tests.ulid(8671)),
  null,
  'nanny note deleted_at is null initially'); -- 4

-- Mom revokes Nanny
select tests.authenticate_as('mom_867');
select is(
  public.revoke_guardian(tests.ulid(867), tests.get_supabase_uid('nanny_867')),
  true,
  'mom revokes nanny via revoke_guardian'
); -- 5

-- Check note state after revocation
select isnt(
  (select deleted_at from public.guardian_notes where id = tests.ulid(8671)),
  null,
  'after revoke_guardian, nanny note is tombstoned (deleted_at is set)'
); -- 6

select is(
  (select body from public.guardian_notes where id = tests.ulid(8671)),
  '',
  'after revoke_guardian, nanny note body is cleared per tombstone constraint'
); -- 7

select is(
  (select last_modified_by_user_id from public.guardian_notes where id = tests.ulid(8671)),
  tests.get_supabase_uid('mom_867'),
  'after revoke_guardian, last_modified_by_user_id is stamped to revoking caller (mom)'
); -- 8

select is(
  (select logged_by_user_id from public.guardian_notes where id = tests.ulid(8671)),
  tests.get_supabase_uid('nanny_867'),
  'after revoke_guardian, logged_by_user_id attribution is preserved'
); -- 9

-- Remaining guardian (Dad) can read the tombstone
select tests.authenticate_as('dad_867');
select is(
  (select body from public.guardian_notes where id = tests.ulid(8671)),
  '',
  'remaining guardian (dad) can select the tombstoned note'
); -- 10

-- Revoked guardian (Nanny) can read 0 notes for this profile via RLS
select tests.authenticate_as('nanny_867');
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(867)),
  0::bigint,
  'revoked guardian (nanny) reads 0 notes for the profile via RLS'
); -- 11

-- ---------------------------------------------------------------------------
-- Part 2: Self-leave by co-parent (Dad) tombstones their own notes
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad_867');
insert into r select 'dad_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8672), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-16', 'tz', 'America/New_York',
    'body', 'Dad note for Sam: soccer practice.',
    'updated_at', '2026-09-16T15:00:00Z')));

select is((select body from public.guardian_notes where id = tests.ulid(8672)),
  'Dad note for Sam: soccer practice.',
  'dad note is initially live'); -- 12

-- Dad leaves profile via revoke_guardian(profile, own_uid)
select is(
  public.revoke_guardian(tests.ulid(867), tests.get_supabase_uid('dad_867')),
  true,
  'dad leaves profile via revoke_guardian'
); -- 13

-- Mom (active guardian) checks dad's note state after dad's self-leave
select tests.authenticate_as('mom_867');

select isnt(
  (select deleted_at from public.guardian_notes where id = tests.ulid(8672)),
  null,
  'after self-leave, dad note is tombstoned (deleted_at is set)'
); -- 14

select is(
  (select body from public.guardian_notes where id = tests.ulid(8672)),
  '',
  'after self-leave, dad note body is cleared'
); -- 15

select is(
  (select last_modified_by_user_id from public.guardian_notes where id = tests.ulid(8672)),
  tests.get_supabase_uid('dad_867'),
  'after self-leave, last_modified_by_user_id is dad'
); -- 16

-- Dad now reads 0 notes via RLS
select tests.authenticate_as('dad_867');
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(867)),
  0::bigint,
  'after self-leave, dad reads 0 notes via RLS'
); -- 17

-- Mom can read both tombstones
select tests.authenticate_as('mom_867');
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(867)),
  2::bigint,
  'mom can read both tombstoned notes'
); -- 18

-- ---------------------------------------------------------------------------
-- Part 3: Orphaned (authorless) note cleanup via sync_push
-- ---------------------------------------------------------------------------
-- Invite sitter as caregiver
select public.create_guardian_invitation(tests.ulid(867), 'caregiver', 'Sitter',
  '3333333333333333333333333333333333333333333333333333333333333333', 48);

select tests.authenticate_as('sitter_867');
select public.accept_guardian_invitation(
  '3333333333333333333333333333333333333333333333333333333333333333', 'Sitter');

-- Sitter logs a note
insert into r select 'sitter_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8673), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-17', 'tz', 'America/New_York',
    'body', 'Sitter note for Sam: bedtime on time.',
    'updated_at', '2026-09-17T20:00:00Z')));

-- Simulate sitter account deletion: author row removed from auth.users,
-- causing guardian_notes.logged_by_user_id to become null via ON DELETE SET NULL
select tests.clear_authentication();
delete from auth.users where id = tests.get_supabase_uid('sitter_867');

select is(
  (select logged_by_user_id from public.guardian_notes where id = tests.ulid(8673)),
  null,
  'sitter note logged_by_user_id is now null (orphaned)'
); -- 19

-- Re-invite a new caregiver: nanny2
select tests.create_supabase_user('nanny2_867');
select tests.authenticate_as('mom_867');
select public.create_guardian_invitation(tests.ulid(867), 'caregiver', 'Nanny2',
  '4444444444444444444444444444444444444444444444444444444444444444', 48);
select tests.authenticate_as('nanny2_867');
select public.accept_guardian_invitation(
  '4444444444444444444444444444444444444444444444444444444444444444', 'Nanny2');

-- Non-primary guardian (nanny2) attempts to edit the orphaned note -> rejected
insert into r select 'nanny2_edit_orphan', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8673), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-17', 'tz', 'America/New_York',
    'body', 'Attempted edit by non-author caregiver',
    'updated_at', '2026-09-18T10:00:00Z')));
select is(pg_temp.rejected_ids('nanny2_edit_orphan'), array[tests.ulid(8673)],
  'caregiver edit of orphaned note is rejected'); -- 20

-- Non-primary guardian (nanny2) attempts to tombstone the orphaned note -> rejected
insert into r select 'nanny2_tombstone_orphan', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8673), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-17', 'tz', 'America/New_York',
    'body', '',
    'updated_at', '2026-09-18T10:00:00Z',
    'deleted_at', '2026-09-18T10:00:00Z')));
select is(pg_temp.rejected_ids('nanny2_tombstone_orphan'), array[tests.ulid(8673)],
  'caregiver tombstone of orphaned note is rejected'); -- 21

-- Primary guardian (mom) attempts to EDIT the orphaned note without tombstoning -> rejected
select tests.authenticate_as('mom_867');
insert into r select 'mom_edit_orphan', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8673), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-17', 'tz', 'America/New_York',
    'body', 'Mom modifying content of someone else note',
    'updated_at', '2026-09-18T11:00:00Z')));
select is(pg_temp.rejected_ids('mom_edit_orphan'), array[tests.ulid(8673)],
  'primary_guardian edit (non-tombstone) of orphaned note is rejected'); -- 22

-- Primary guardian (mom) tombstones the orphaned note -> accepted
insert into r select 'mom_tombstone_orphan', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(8673), 'profile_id', tests.ulid(867),
    'local_date', '2026-09-17', 'tz', 'America/New_York',
    'body', '',
    'updated_at', '2026-09-18T12:00:00Z',
    'deleted_at', '2026-09-18T12:00:00Z')));
select is(pg_temp.rejected_ids('mom_tombstone_orphan'), null,
  'primary_guardian tombstone of orphaned note is accepted'); -- 23

select is(
  (select body from public.guardian_notes where id = tests.ulid(8673)),
  '',
  'orphaned note body is cleared'
); -- 24

select isnt(
  (select deleted_at from public.guardian_notes where id = tests.ulid(8673)),
  null,
  'orphaned note deleted_at is set'
); -- 25

select is(
  (select last_modified_by_user_id from public.guardian_notes where id = tests.ulid(8673)),
  tests.get_supabase_uid('mom_867'),
  'orphaned note last_modified_by_user_id is set to mom'
); -- 26

select * from finish();
rollback;
