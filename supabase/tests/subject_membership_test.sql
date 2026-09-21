-- Coverage for Issue #802's subject membership ("her own profile"):
-- the is_subject marker's write-path exclusivity (only the subject-invite
-- path and accept_ownership_transfer can set it; a client cannot; a plain
-- caregiver invitation cannot), the subject invite round trip
-- (create -> preview -> accept stamps the membership), the invitation
-- parameter validation (subject preset is caregiver-only, manager-only),
-- the marker's durability under revoke/update_guardian_role, the
-- plain-re-invitation clear, ownership transfer stamping exactly one
-- primary_guardian, and the caregiver-subject's server-enforced
-- incapabilities (cannot remove a guardian, cannot edit profile
-- metadata).
begin;
select plan(28);

create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

-- ---------------------------------------------------------------------------
-- Setup: Mom (primary_guardian) owns minor profile P; Dad joins as
-- co_parent. Daughter and Sitter join through invitations below.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('daughter');
select tests.create_supabase_user('sitter');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(950), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(950), 'co_parent', 'Dad', pg_temp.token(1), 48);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(pg_temp.token(1), 'Dad');

-- ---------------------------------------------------------------------------
-- 1. Schema shape: nullable marker on profile_guardians, not-null default
--    false on guardian_invitations.
-- ---------------------------------------------------------------------------
select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_guardians' and column_name = 'is_subject'),
  'boolean',
  'profile_guardians.is_subject is a boolean column'
);
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'profile_guardians' and column_name = 'is_subject'),
  'YES',
  'profile_guardians.is_subject is nullable (null == false, catalog-only backfill)'
);
select is(
  (select is_nullable from information_schema.columns
    where table_schema = 'public' and table_name = 'guardian_invitations' and column_name = 'is_subject'),
  'NO',
  'guardian_invitations.is_subject is NOT NULL'
);
select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'guardian_invitations' and column_name = 'is_subject'),
  'false',
  'guardian_invitations.is_subject defaults to false (every pre-#802 invite stays a plain invite)'
);

-- ---------------------------------------------------------------------------
-- 2. Write-path exclusivity: no client grant covers the marker. The
--    table's authenticated update grant is (display_name, updated_at)
--    only, so PostgREST can never set or clear is_subject.
-- ---------------------------------------------------------------------------
select ok(
  not has_column_privilege('authenticated', 'public.profile_guardians', 'is_subject', 'UPDATE'),
  'authenticated has no UPDATE privilege on profile_guardians.is_subject'
);
select ok(
  not has_column_privilege('authenticated', 'public.profile_guardians', 'is_subject', 'INSERT'),
  'authenticated has no INSERT privilege on profile_guardians.is_subject (no table INSERT grant at all)'
);
select ok(
  not has_column_privilege('authenticated', 'public.guardian_invitations', 'is_subject', 'UPDATE'),
  'authenticated has no UPDATE privilege on guardian_invitations.is_subject'
);

-- ---------------------------------------------------------------------------
-- 3. Subject invite round trip: Mom invites Riley to log her own profile.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
create temp table subject_invite as
  select public.create_guardian_invitation(
    tests.ulid(950), 'caregiver', 'Riley', pg_temp.token(11), 48, true
  ) as data;

select is(
  (select (data ->> 'is_subject') from subject_invite),
  'true',
  'create_guardian_invitation echoes is_subject true for the subject preset'
);
-- Reading (or even filtering on) token_hash is closed to authenticated
-- callers by #114's column grants, so this catalog assertion runs as the
-- test role, exactly like guardian_invitation_preview_test's fabricated
-- rows do.
select tests.clear_authentication();
select is(
  (select is_subject from public.guardian_invitations where token_hash = pg_temp.token(11)),
  true,
  'The invitation row records the subject preset'
);

select tests.authenticate_as('daughter');
select is(
  (select public.accept_guardian_invitation(pg_temp.token(11), 'Riley')
     ->> 'is_subject'),
  'true',
  'accept_guardian_invitation returns is_subject true for a subject invite'
);
select is(
  (select role::text || ':' || status::text || ':' || is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('daughter')),
  'caregiver:accepted:true',
  'Accepting a subject invite yields an accepted caregiver membership stamped is_subject'
);

-- ---------------------------------------------------------------------------
-- 4. Preview carries the marker (so the accept sheet can say "this is
--    your profile" before the recipient commits). A second live subject
--    invite previews is_subject true; the result carries exactly four
--    keys.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.create_guardian_invitation(
  tests.ulid(950), 'caregiver', 'Riley again', pg_temp.token(12), 48, true
);
select tests.authenticate_as('daughter');
select is(
  (select public.preview_guardian_invitation(pg_temp.token(12)) ->> 'is_subject'),
  'true',
  'preview_guardian_invitation reports is_subject for a live subject invite'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.preview_guardian_invitation(pg_temp.token(12))) as k),
  array['expires_at', 'is_subject', 'profile_display_name', 'role'],
  'The preview object carries exactly four keys - nothing about other guardians'
);

-- ---------------------------------------------------------------------------
-- 5. A plain caregiver invitation cannot mint a subject membership.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.create_guardian_invitation(tests.ulid(950), 'caregiver', 'Sitter', pg_temp.token(13), 48);
select tests.clear_authentication();
select is(
  (select is_subject from public.guardian_invitations where token_hash = pg_temp.token(13)),
  false,
  'A plain caregiver invitation is_subject defaults to false'
);
select tests.authenticate_as('sitter');
select public.accept_guardian_invitation(pg_temp.token(13), 'Sitter');
select is(
  (select is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('sitter')),
  'false',
  'Accepting a plain caregiver invite never sets the subject marker'
);

-- ---------------------------------------------------------------------------
-- 6. Parameter validation: the preset is caregiver-only, and the caller
--    needs the ordinary invite authority.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select throws_ok(
  format('select public.create_guardian_invitation(%L, ''co_parent'', ''X'', %L, 48, true)',
         tests.ulid(950), pg_temp.token(14)),
  '22023', null,
  'A subject invitation cannot grant co_parent'
);
select throws_ok(
  format('select public.create_guardian_invitation(%L, ''viewer'', ''X'', %L, 48, true)',
         tests.ulid(950), pg_temp.token(15)),
  '22023', null,
  'A subject invitation cannot grant viewer'
);
select tests.authenticate_as('sitter');
select throws_ok(
  format('select public.create_guardian_invitation(%L, ''caregiver'', ''X'', %L, 48, true)',
         tests.ulid(950), pg_temp.token(16)),
  '42501', null,
  'A caregiver cannot create a subject invitation (same ladder as every invite)'
);

-- ---------------------------------------------------------------------------
-- 7. The caregiver subject's server-enforced incapabilities: she cannot
--    remove a guardian and cannot edit profile metadata. (Deletion is
--    primary-only and pinned by profile_guardian_only_deletion_test.)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select throws_ok(
  format('select public.revoke_guardian(%L, %L)', tests.ulid(950), tests.get_supabase_uid('dad')),
  '42501', null,
  'The caregiver subject cannot remove a guardian'
);
select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(950), 'display_name', 'Riley!', 'is_minor', true,
      'sort_order', 0, 'created_at', '2026-09-01T00:00:00Z',
      'updated_at', '2026-09-19T00:00:00Z')),
    '[]'::jsonb
  ) -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(950), 'rejected', true)),
  'The caregiver subject cannot edit profile metadata (rejected, not applied)'
);
select is(
  (select display_name from public.profiles where id = tests.ulid(950)),
  'Riley',
  'The profile row is unchanged after the subject''s rejected metadata push'
);

-- ---------------------------------------------------------------------------
-- 8. Durability: update_guardian_role and revoke_guardian leave the
--    marker alone; a plain re-invitation clears it deliberately.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.update_guardian_role(tests.ulid(950), tests.get_supabase_uid('daughter'), 'viewer');
select is(
  (select role::text || ':' || is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('daughter')),
  'viewer:true',
  'A role change does not touch the subject marker'
);
select public.update_guardian_role(tests.ulid(950), tests.get_supabase_uid('daughter'), 'caregiver');
select public.revoke_guardian(tests.ulid(950), tests.get_supabase_uid('daughter'));
select is(
  (select status::text || ':' || is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('daughter')),
  'revoked:true',
  'Revocation leaves the durable marker on the (now inactive) row'
);

-- A fresh plain invitation after the revocation is a deliberate
-- demotion back to helper: the marker must clear.
select tests.authenticate_as('mom');
select public.create_guardian_invitation(tests.ulid(950), 'caregiver', 'Riley', pg_temp.token(17), 48);
select tests.authenticate_as('daughter');
select public.accept_guardian_invitation(pg_temp.token(17), 'Riley');
select is(
  (select is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('daughter')),
  'false',
  'A plain re-invitation of a former subject deliberately clears the marker'
);

-- ---------------------------------------------------------------------------
-- 9. Ownership transfer still works on a subject row and stamps the
--    marker on the new owner: exactly one primary_guardian remains, the
--    daughter is primary + subject, Mom is demoted and not subject.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.create_ownership_transfer(tests.ulid(950), 'co_parent', pg_temp.token(18));
select tests.authenticate_as('daughter');
select public.accept_ownership_transfer(pg_temp.token(18), 'Riley', 'Mom');
select is(
  (select role::text || ':' || is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('daughter')),
  'primary_guardian:true',
  'The transfer acceptor is the sole primary_guardian and is stamped is_subject'
);
select is(
  (select role::text || ':' || is_subject::text
     from public.profile_guardians
    where profile_id = tests.ulid(950) and user_id = tests.get_supabase_uid('mom')),
  'co_parent:false',
  'The demoted parent keeps access as co_parent and is not the subject'
);
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(950) and role = 'primary_guardian' and status = 'accepted'),
  1::bigint,
  'Exactly one accepted primary_guardian remains after the transfer'
);

-- ---------------------------------------------------------------------------
-- 10. The marker is server-visible to sync: sync_pull's profile_guardians
--     page carries is_subject for the caller's own row.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select is(
  (select g ->> 'is_subject'
     from jsonb_array_elements(public.sync_pull('{}'::jsonb) -> 'profile_guardians') g
    where g ->> 'user_id' = tests.get_supabase_uid('daughter')::text),
  'true',
  'sync_pull delivers is_subject with the membership row (the durable, synced marker)'
);

select * from finish();
rollback;
