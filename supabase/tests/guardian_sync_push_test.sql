-- Unit test for guardian sync_push and invitations RPCs (Issue #8, Unit U2).
begin;
select plan(23);

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

rollback;
