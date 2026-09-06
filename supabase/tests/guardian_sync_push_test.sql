-- Unit test for guardian sync_push and invitations RPCs (Issue #8, Unit U2).
begin;
select plan(32);

-- ---------------------------------------------------------------------------
-- Setup test users: mom (creator), dad (co-parent), nanny (caregiver), doc (viewer), eve (attacker)
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('nanny');
select tests.create_supabase_user('doc');
select tests.create_supabase_user('eve');

-- ---------------------------------------------------------------------------
-- 1. Mom creates profile via sync_push
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object('id', tests.ulid(301), 'display_name', 'Emma', 'updated_at', '2026-09-01T00:00:00Z')),
    '[]'::jsonb
  ) -> 'rejected',
  '[]'::jsonb,
  'Mom pushes Emma profile: accepted'
);

select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(301) and user_id = tests.get_supabase_uid('mom') and role = 'primary_guardian'),
  1::bigint,
  'Mom is automatically registered as primary_guardian'
);

-- ---------------------------------------------------------------------------
-- 2. Invitations Handshake: Mom invites Dad as co_parent
-- ---------------------------------------------------------------------------
-- Dad token: SHA256 of "secret_token_for_dad_12345678901234567890123456"
-- Let hash = 64 hex chars
create temp table invite_res as
  select public.create_guardian_invitation(
    tests.ulid(301),
    'co_parent',
    'Dad',
    '1111111111111111111111111111111111111111111111111111111111111111',
    48
  ) as data;

select is(
  (select (data ->> 'role') from invite_res),
  'co_parent',
  'Mom creates invite for Dad with role co_parent'
);

-- Dad accepts invite
select tests.authenticate_as('dad');

select is(
  (select public.accept_guardian_invitation(
    '1111111111111111111111111111111111111111111111111111111111111111',
    'Dad'
  ) ->> 'role'),
  'co_parent',
  'Dad accepts invitation successfully'
);

select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(301) and user_id = tests.get_supabase_uid('dad') and role = 'co_parent' and status = 'accepted'),
  1::bigint,
  'Dad is now active co_parent in profile_guardians'
);

-- Eve attempts to replay the already accepted invitation
select tests.authenticate_as('eve');
select throws_ok(
  $$select public.accept_guardian_invitation('1111111111111111111111111111111111111111111111111111111111111111')$$,
  '55000',
  null,
  'Replay of accepted invitation is rejected'
);

-- ---------------------------------------------------------------------------
-- 3. Dad (co-parent) invites Nanny as caregiver and Doc as viewer
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');

select public.create_guardian_invitation(
  tests.ulid(301),
  'caregiver',
  'Nanny',
  '2222222222222222222222222222222222222222222222222222222222222222',
  48
);

-- R3: a co-parent may not mint co-parent invitations (primary only).
select throws_ok(
  $$select public.create_guardian_invitation(
    tests.ulid(301), 'co_parent', 'Fake Co-Parent',
    '4444444444444444444444444444444444444444444444444444444444444444', 48)$$,
  '42501',
  null,
  'Co-parent cannot create a co-parent invitation'
);

select public.create_guardian_invitation(
  tests.ulid(301),
  'viewer',
  'Dr. Green',
  '3333333333333333333333333333333333333333333333333333333333333333',
  48
);

select tests.authenticate_as('nanny');
select public.accept_guardian_invitation(
  '2222222222222222222222222222222222222222222222222222222222222222',
  'Nanny Sarah'
);

select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  '3333333333333333333333333333333333333333333333333333333333333333',
  'Dr. Green'
);

-- ---------------------------------------------------------------------------
-- 4. Attribution and Role Restrictions in sync_push
-- ---------------------------------------------------------------------------
-- Nanny pushes a day entry: server stamps logged_by_user_id = Nanny's UID
select tests.authenticate_as('nanny');

select is(
  public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(302),
      'profile_id', tests.ulid(301),
      'local_date', '2026-09-01',
      'tz', 'UTC',
      'flow', 'medium',
      'note', 'Nanny logged flow',
      'logged_by_user_id', tests.get_supabase_uid('mom'), -- Spoof attempt
      'updated_at', '2026-09-01T12:00:00Z'
    ))
  ) -> 'rejected',
  '[]'::jsonb,
  'Nanny pushes day entry: accepted'
);

select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(302)),
  tests.get_supabase_uid('nanny'),
  'logged_by_user_id is authoritatively set to caller UID (spoof ignored)'
);

select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(302)),
  tests.get_supabase_uid('nanny'),
  'last_modified_by_user_id is stamped with caller UID'
);

-- Dad edits the day entry: last_modified_by_user_id becomes Dad, logged_by remains Nanny
select tests.authenticate_as('dad');

select is(
  public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(302),
      'profile_id', tests.ulid(301),
      'local_date', '2026-09-01',
      'tz', 'UTC',
      'flow', 'heavy',
      'note', 'Dad updated flow to heavy',
      'updated_at', '2026-09-01T14:00:00Z'
    ))
  ) -> 'rejected',
  '[]'::jsonb,
  'Dad pushes day entry update: accepted'
);

select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(302)),
  tests.get_supabase_uid('nanny'),
  'logged_by_user_id remains Nanny on update'
);

select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(302)),
  tests.get_supabase_uid('dad'),
  'last_modified_by_user_id updated to Dad'
);

-- A day entry can never move between profiles: Dad is a guardian of both
-- 301 and (below) 305, but re-pointing entry 302 to 305 is rejected.
select tests.authenticate_as('mom');
select public.sync_push(
  jsonb_build_array(jsonb_build_object('id', tests.ulid(305), 'display_name', 'Lily', 'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);
select public.create_guardian_invitation(
  tests.ulid(305), 'co_parent', 'Dad',
  '5555555555555555555555555555555555555555555555555555555555555555', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '5555555555555555555555555555555555555555555555555555555555555555',
  'Dad'
);

select is(
  public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(302),
      'profile_id', tests.ulid(305),
      'local_date', '2026-09-01',
      'tz', 'UTC',
      'flow', 'medium',
      'updated_at', '2026-09-01T16:00:00Z'
    ))
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(302), 'rejected', true)),
  'Day entry cannot be re-pointed to another profile (rejected)'
);

select is(
  (select profile_id from public.day_entries where id = tests.ulid(302)),
  tests.ulid(301),
  'Re-pointed entry stays in its original profile'
);

-- Viewer (Doc) attempts to push day entry: rejected
select tests.authenticate_as('doc');

select is(
  public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(303),
      'profile_id', tests.ulid(301),
      'local_date', '2026-09-02',
      'tz', 'UTC',
      'flow', 'light',
      'updated_at', '2026-09-02T10:00:00Z'
    ))
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(303), 'rejected', true)),
  'Viewer cannot push day entries (rejected by sync_push)'
);

-- Caregiver (Nanny) attempts to delete profile: rejected
select tests.authenticate_as('nanny');

select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(301),
      'display_name', 'Emma Deleted',
      'updated_at', '2026-09-02T10:00:00Z',
      'deleted_at', '2026-09-02T10:00:00Z'
    )),
    '[]'::jsonb
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(301), 'rejected', true)),
  'Caregiver cannot delete profile (rejected by sync_push)'
);

-- Co-Parent (Dad) attempts to delete profile: rejected (only primary_guardian can delete)
select tests.authenticate_as('dad');

select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(301),
      'display_name', 'Emma Deleted',
      'updated_at', '2026-09-02T10:00:00Z',
      'deleted_at', '2026-09-02T10:00:00Z'
    )),
    '[]'::jsonb
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(301), 'rejected', true)),
  'Co-Parent cannot delete profile (rejected by sync_push)'
);

-- Primary Guardian (Mom) can archive/delete profile
select tests.authenticate_as('mom');

select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(301),
      'updated_at', '2026-09-02T10:00:00Z',
      'archived_at', '2026-09-02T10:00:00Z'
    )),
    '[]'::jsonb
  ) -> 'rejected',
  '[]'::jsonb,
  'Primary guardian can archive profile'
);

-- ---------------------------------------------------------------------------
-- 5. Revocation & Leaving via revoke_guardian RPC
-- ---------------------------------------------------------------------------
-- Nanny attempts to revoke Dad: fails with insufficient_privilege
select tests.authenticate_as('nanny');
select throws_ok(
  $$select public.revoke_guardian(tests.ulid(301), tests.get_supabase_uid('dad'))$$,
  '42501',
  null,
  'Caregiver cannot revoke Co-Parent'
);

-- Dad (co-parent) revokes Nanny: succeeds
select tests.authenticate_as('dad');
select is(
  public.revoke_guardian(tests.ulid(301), tests.get_supabase_uid('nanny')),
  true,
  'Co-Parent can revoke Caregiver'
);

select is(
  (select status from public.profile_guardians where profile_id = tests.ulid(301) and user_id = tests.get_supabase_uid('nanny')),
  'revoked',
  'Nanny status is now revoked'
);

-- Revoked Nanny cannot push day entries
select tests.authenticate_as('nanny');
select is(
  public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(304),
      'profile_id', tests.ulid(301),
      'local_date', '2026-09-03',
      'tz', 'UTC',
      'flow', 'light',
      'updated_at', '2026-09-03T10:00:00Z'
    ))
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(304), 'rejected', true)),
  'Revoked caregiver cannot push day entries'
);

-- Sole primary guardian (Mom) cannot leave profile
select tests.authenticate_as('mom');
select throws_ok(
  $$select public.revoke_guardian(tests.ulid(301), tests.get_supabase_uid('mom'))$$,
  '55000',
  null,
  'Sole primary guardian cannot leave profile'
);

-- Co-Parent (Dad) can self-leave
select tests.authenticate_as('dad');
select is(
  public.revoke_guardian(tests.ulid(301), tests.get_supabase_uid('dad')),
  true,
  'Co-Parent can self-leave profile'
);

select is(
  (select status from public.profile_guardians where profile_id = tests.ulid(301) and user_id = tests.get_supabase_uid('dad')),
  'revoked',
  'Dad status is now revoked after self-leave'
);

-- ---------------------------------------------------------------------------
-- AE4 / R24 regression (plan 2026-09-06-001, Unit U4): a stale offline
-- parent client cannot reclaim ownership by pushing a profile row with
-- user_id set back to itself through sync_push. sync_push's UPDATE path has
-- never included user_id in its SET list (see
-- 20260904020000_sync_push_and_invitations.sql) - this pins that behavior
-- specifically against a *post-transfer* co_parent, so a future sync_push
-- edit cannot silently reopen it. Uses co_parent rather than viewer for the
-- push (R7's other role) so the push clears the "role can edit metadata"
-- check and this assertion actually exercises the update path, not just an
-- authorization refusal.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('kid');

select tests.authenticate_as('mom');
select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(310), 'display_name', 'Riley', 'is_minor', true, 'sort_order', 0,
      'updated_at', '2026-09-06T09:00:00Z')),
    '[]'::jsonb
  ) -> 'rejected',
  '[]'::jsonb,
  'AE4 setup: Mom creates a fresh profile via sync_push'
);

select public.create_ownership_transfer(
  tests.ulid(310), 'co_parent',
  '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', null, 72
);

select tests.authenticate_as('kid');
select is(
  public.accept_ownership_transfer(
    '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', 'Kid', 'Mom'
  ) ->> 'profile_id',
  tests.ulid(310),
  'AE4 setup: Kid accepts the transfer and becomes owner'
);

select is(
  (select user_id from public.profiles where id = tests.ulid(310)),
  tests.get_supabase_uid('kid'),
  'AE4 setup: profiles.user_id is now Kid''s'
);

select tests.authenticate_as('mom');
-- accept_ownership_transfer stamped profiles.updated_at to clock_timestamp()
-- (the real wall clock, not this file's fictional 2026-09-06 timestamps), so
-- the reclaim push's own updated_at must be computed relative to the stored
-- row rather than hardcoded, or LWW would silently decline it as stale.
select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(310), 'display_name', 'Reclaimed', 'is_minor', true, 'sort_order', 0,
      'user_id', tests.get_supabase_uid('mom'),
      'updated_at', to_char(
        (select updated_at from public.profiles where id = tests.ulid(310)) + interval '1 minute',
        'YYYY-MM-DD"T"HH24:MI:SS"Z"'))),
    '[]'::jsonb
  ) -> 'rejected',
  '[]'::jsonb,
  'AE4: a post-transfer co_parent''s push carrying user_id back to itself is accepted for the metadata columns'
);

select is(
  (select display_name from public.profiles where id = tests.ulid(310)),
  'Reclaimed',
  'AE4: the metadata columns the push actually named do update'
);

select is(
  (select user_id from public.profiles where id = tests.ulid(310)),
  tests.get_supabase_uid('kid'),
  'AE4 / R24: profiles.user_id is still Kid''s - sync_push never writes user_id, tolerated-but-never-read'
);

rollback;
