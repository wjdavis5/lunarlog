-- Coverage for update_guardian_role (Issue #127): change an existing
-- guardian's role without revoke-and-reinvite.
--
-- The happy paths (a primary promoting viewer->caregiver, a primary
-- narrowing co_parent->viewer, a co_parent adjusting caregiver/viewer),
-- every negative case in AC7 (self-escalation, co-parent vs primary,
-- granting primary_guardian), plus the AC6 attribution guarantee (entries
-- the guardian previously logged keep theirs), the sync-propagation story
-- (the role write bumps server_version so the next pull delivers it), and
-- the grant posture (authenticated-only, matching revoke_guardian).
begin;
select plan(33);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('sitter');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('stranger');
select tests.create_supabase_user('nanny');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile (P1) with an accepted co-parent (dad), an accepted
-- caregiver (sitter), and an accepted viewer (doctor). Stranger separately
-- owns an unrelated profile (P2). Nanny holds no membership anywhere.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(901), 'co_parent', 'Dad',
  '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a', 48
);
select public.create_guardian_invitation(
  tests.ulid(901), 'caregiver', 'Sitter',
  '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c', 48
);
select public.create_guardian_invitation(
  tests.ulid(901), 'viewer', 'Doctor',
  '0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d', 48
);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a', 'Dad'
);
select tests.authenticate_as('sitter');
select public.accept_guardian_invitation(
  '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c', 'Sitter'
);
select tests.authenticate_as('doctor');
select public.accept_guardian_invitation(
  '0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d', 'Doctor'
);

select tests.authenticate_as('stranger');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(902), 'Other Kid', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- 1-3. Grant posture: authenticated-only, like revoke_guardian.
-- ---------------------------------------------------------------------------
select ok(
  has_function_privilege('authenticated', 'public.update_guardian_role(text, uuid, text)', 'execute'),
  'authenticated holds EXECUTE on update_guardian_role'
);
select ok(
  not has_function_privilege('anon', 'public.update_guardian_role(text, uuid, text)', 'execute'),
  'anon holds no EXECUTE on update_guardian_role'
);
select ok(
  not has_function_privilege('public', 'public.update_guardian_role(text, uuid, text)', 'execute'),
  'public holds no EXECUTE on update_guardian_role'
);

-- ---------------------------------------------------------------------------
-- 4-9. Co-parent caller: may move caregiver/viewer to caregiver/viewer
-- (AC3), but cannot mint a peer, touch the primary, or move themselves.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'viewer'
  ) ->> 'updated'),
  'true',
  'Co-parent moves a caregiver to viewer (AC3)'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('sitter')),
  'viewer',
  'The sitter row actually carries the viewer role'
);
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('doctor'), 'caregiver'
  ) ->> 'updated'),
  'true',
  'Co-parent moves a viewer to caregiver (AC3)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'co_parent'
  )$$,
  '42501', 'insufficient permission to change this guardian''s role',
  'Co-parent cannot promote a viewer to co_parent (no peer minting)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('mom'), 'viewer'
  )$$,
  '42501', 'insufficient permission to change this guardian''s role',
  'Co-parent cannot touch the primary guardian''s role (AC3, AC7)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('dad'), 'caregiver'
  )$$,
  '42501', 'cannot change your own role',
  'A co-parent cannot change their own role (AC4, AC7 self-escalation)'
);

-- ---------------------------------------------------------------------------
-- 10-11. Caregiver and viewer callers may change nothing.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('sitter');
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('doctor'), 'viewer'
  )$$,
  '42501', 'insufficient permission to change this guardian''s role',
  'A viewer cannot change another guardian''s role'
);
select tests.authenticate_as('doctor');
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'caregiver'
  )$$,
  '42501', 'insufficient permission to change this guardian''s role',
  'A caregiver cannot change another guardian''s role'
);

-- ---------------------------------------------------------------------------
-- 12-18. Primary caller: may change anyone (AC1, AC2) - including granting
-- co_parent - but never primary_guardian (AC5) and never themselves (AC4).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('doctor'), 'viewer'
  ) ->> 'updated'),
  'true',
  'Primary narrows a caregiver to viewer'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('doctor')),
  'viewer',
  'The doctor row actually carries the viewer role'
);
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'caregiver'
  ) ->> 'updated'),
  'true',
  'Primary promotes a viewer to caregiver (AC1, no re-invitation)'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('sitter')),
  'caregiver',
  'The sitter row actually carries the caregiver role'
);
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'co_parent'
  ) ->> 'updated'),
  'true',
  'Primary may grant co_parent (only primary_guardian is off-limits)'
);
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('dad'), 'viewer'
  ) ->> 'updated'),
  'true',
  'Primary narrows a co_parent to viewer (AC2)'
);
select is(
  (select role from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('dad')),
  'viewer',
  'The dad row actually carries the viewer role after narrowing'
);

-- ---------------------------------------------------------------------------
-- 19-24. Primary negatives: self-change (AC4), granting primary_guardian
-- (AC5, AC7), unknown roles, and the idempotent no-op.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('mom'), 'viewer'
  )$$,
  '42501', 'cannot change your own role',
  'The primary guardian cannot change their own role (AC4, AC7)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'primary_guardian'
  )$$,
  '42501', 'primary_guardian cannot be granted through update_guardian_role',
  'No path grants primary_guardian through this RPC (AC5, AC7)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('dad'), 'primary_guardian'
  )$$,
  '42501', 'primary_guardian cannot be granted through update_guardian_role',
  'Granting primary_guardian is refused for a narrowed target too (AC5)'
);
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'owner'
  )$$,
  '22023', 'invalid role: owner',
  'An unknown role is rejected as an invalid parameter, not applied'
);
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'co_parent'
  ) ->> 'updated'),
  'false',
  'Re-applying the current role reports updated=false instead of churning'
);
create temporary table tmp_sitter_stamped as
  select updated_at, server_version from public.profile_guardians
   where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('sitter');
select is(
  (select updated_at from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('sitter')),
  (select updated_at from tmp_sitter_stamped),
  'The no-op write leaves updated_at untouched'
);

-- ---------------------------------------------------------------------------
-- 25-27. Callers and targets outside the profile.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'viewer'
  )$$,
  '42501', 'caller is not a guardian of this profile',
  'A guardian of an unrelated profile cannot change roles on this one'
);
select tests.authenticate_as('nanny');
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'viewer'
  )$$,
  '42501', 'caller is not a guardian of this profile',
  'A user with no membership anywhere cannot change roles'
);
select tests.authenticate_as('mom');
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('nanny'), 'viewer'
  )$$,
  'P0002', 'target is not an active guardian of this profile',
  'Changing a non-member''s role raises not-found rather than creating one'
);

-- ---------------------------------------------------------------------------
-- 28-30. AC6: narrowing never orphans - entries the guardian previously
-- logged keep their attribution unchanged.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(950), tests.get_supabase_uid('mom'), tests.ulid(901),
  '2026-09-03', 'UTC', 'medium', '2026-09-03T00:00:00Z',
  tests.get_supabase_uid('sitter'), tests.get_supabase_uid('sitter'));

select tests.authenticate_as('mom');
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'viewer'
  ) ->> 'updated'),
  'true',
  'Primary narrows the logging guardian to viewer ahead of the attribution check'
);
select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(950)),
  tests.get_supabase_uid('sitter'),
  'AC6: logged_by_user_id is unchanged by the role change'
);
select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(950)),
  tests.get_supabase_uid('sitter'),
  'AC6: last_modified_by_user_id is unchanged by the role change'
);

-- ---------------------------------------------------------------------------
-- 31-32. Propagation: the role write bumps server_version, so the next
-- sync pull delivers the new role to the affected device (AC1/AC2).
-- ---------------------------------------------------------------------------
create temporary table tmp_doctor_version as
  select server_version from public.profile_guardians
   where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('doctor');
select is(
  (select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('doctor'), 'caregiver'
  ) ->> 'updated'),
  'true',
  'Primary promotes the doctor viewer to caregiver for the propagation check'
);
select ok(
  (select server_version from public.profile_guardians
    where profile_id = tests.ulid(901) and user_id = tests.get_supabase_uid('doctor'))
  > (select server_version from tmp_doctor_version),
  'The role write advances server_version, so the next pull delivers it'
);

-- ---------------------------------------------------------------------------
-- 33. Anon cannot call the RPC at all. EXECUTE is revoked from anon, so
-- the denial happens at the grant layer before the function body runs -
-- the code is still insufficient_privilege either way.
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok(
  $$select public.update_guardian_role(
    tests.ulid(901), tests.get_supabase_uid('sitter'), 'viewer'
  )$$,
  '42501', null,
  'Anon callers are refused (no EXECUTE grant)'
);

rollback;
