-- Coverage for revoke_guardian_invitation (Issue #3 gap-closure plan, Unit
-- U1): the role ladder, the enumeration-safe error message, terminal-state
-- idempotency (R5), that a cancelled token is actually dead, and that the
-- withdrawn direct-update grant / policy are gone (R4).
begin;
select plan(24);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('sitter');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('nanny');
select tests.create_supabase_user('stranger');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile (P1) with an accepted co-parent (dad), an accepted
-- caregiver (sitter), and an accepted viewer (doctor). Stranger separately
-- guards an unrelated profile (P2), used for the enumeration test.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(801), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(801), 'co_parent', 'Dad',
  '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a', 48
);
select public.create_guardian_invitation(
  tests.ulid(801), 'caregiver', 'Sitter',
  '0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c', 48
);
select public.create_guardian_invitation(
  tests.ulid(801), 'viewer', 'Doctor',
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

-- Stranger's own, unrelated profile (P2).
select tests.authenticate_as('stranger');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(802), 'Other Kid', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Fresh invitations to exercise cancellation against. tE is a caregiver
-- invite mom creates. tF is a co_parent invite mom creates (only the primary
-- guardian may create a co_parent invitation - dad cannot cancel it, R3). tG
-- is a fresh viewer invite mom creates, for dad (co-parent) to cancel. tB is
-- a co_parent-role invitation whose invited_by is dad - this cannot be
-- produced through create_guardian_invitation (which forbids a co-parent
-- from inviting a co-parent), so it is fabricated directly as the table
-- owner (bypassing RLS, which is exactly what a co-parent cannot do - see
-- profile_guardians_rls_test.sql section 7) to prove the *cancellation*
-- ladder does not care who created the row, only the caller's own role. tK
-- is a pre-expired invitation, likewise fabricated - create_guardian_invitation
-- server-bounds the TTL to 1-168 hours (R7) and never accepts a past expiry.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.create_guardian_invitation(
  tests.ulid(801), 'caregiver', 'Fresh Caregiver',
  '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e', 48
);
select public.create_guardian_invitation(
  tests.ulid(801), 'co_parent', 'Second Co-Parent',
  '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f', 48
);
select public.create_guardian_invitation(
  tests.ulid(801), 'viewer', 'Grandma',
  '0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d', 48
);

select tests.clear_authentication();
insert into public.guardian_invitations
  (profile_id, invited_by, token_hash, role, recipient_label, expires_at)
values
  (tests.ulid(801), tests.get_supabase_uid('dad'),
   '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b',
   'co_parent', 'Fabricated', now() + interval '48 hours');
insert into public.guardian_invitations
  (profile_id, invited_by, token_hash, role, recipient_label, expires_at)
values
  (tests.ulid(801), tests.get_supabase_uid('mom'),
   '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a',
   'caregiver', 'Long Gone', now() - interval '1 hour');

-- ---------------------------------------------------------------------------
-- 1. Primary guardian cancels a caregiver invitation -> outcome revoked.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e')
  ) ->> 'outcome'),
  'revoked',
  'Primary guardian cancels a caregiver invitation -> outcome revoked'
);
select isnt(
  (select revoked_at from public.guardian_invitations
    where token_hash = '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e'),
  null,
  'revoked_at is set on the cancelled caregiver invitation'
);
create temporary table tmp_te_revoked_at as
  select revoked_at from public.guardian_invitations
   where token_hash = '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e';

-- ---------------------------------------------------------------------------
-- 2. Primary guardian cancels a co_parent invitation created by a co-parent
--    (R3: primary may cancel anything on the profile, regardless of creator).
-- ---------------------------------------------------------------------------
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b')
  ) ->> 'outcome'),
  'revoked',
  'Primary guardian cancels a co_parent invitation created by a co-parent (R3)'
);

-- ---------------------------------------------------------------------------
-- 3. Co-parent cancels a viewer invitation created by the primary guardian.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d0d1d')
  ) ->> 'outcome'),
  'revoked',
  'Co-parent cancels a viewer invitation created by the primary guardian (R3)'
);

-- ---------------------------------------------------------------------------
-- 4. Co-parent cancels a co_parent invitation it did not create ->
--    insufficient_privilege, row unchanged.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f')
  )$$,
  '42501', 'caller lacks permission to cancel this invitation',
  'Co-parent cannot cancel a co_parent invitation it did not create (R3)'
);
select is(
  (select revoked_at from public.guardian_invitations
    where token_hash = '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f'),
  null,
  'The co_parent invitation is unchanged after the rejected attempt'
);

-- ---------------------------------------------------------------------------
-- 5. Caregiver attempts to cancel any invitation on a profile they are an
--    accepted guardian of -> insufficient_privilege.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('sitter');
select throws_ok(
  $$select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f')
  )$$,
  '42501', 'caller lacks permission to cancel this invitation',
  'Caregiver cannot cancel any invitation (R3)'
);

-- ---------------------------------------------------------------------------
-- 6. Viewer attempts to cancel -> insufficient_privilege.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doctor');
select throws_ok(
  $$select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f')
  )$$,
  '42501', 'caller lacks permission to cancel this invitation',
  'Viewer cannot cancel any invitation (R3)'
);

-- ---------------------------------------------------------------------------
-- 7. A stranger (accepted guardian of a different profile) targeting this
--    invitation id -> insufficient_privilege, byte-identical to not-found.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');
select throws_ok(
  $$select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f')
  )$$,
  '42501', 'caller lacks permission to cancel this invitation',
  'A guardian of an unrelated profile gets the same message as not-found (no existence oracle)'
);

-- ---------------------------------------------------------------------------
-- 8. A nonexistent invitation id -> insufficient_privilege, byte-identical
--    message.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.revoke_guardian_invitation('00000000-0000-0000-0000-000000000000'::uuid)$$,
  '42501', 'caller lacks permission to cancel this invitation',
  'A nonexistent invitation id raises the identical message (no existence oracle)'
);

-- ---------------------------------------------------------------------------
-- 9. Cancelling an already-revoked invitation -> outcome already_revoked,
--    revoked_at unchanged from its first value (R5, idempotent).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e')
  ) ->> 'outcome'),
  'already_revoked',
  'Cancelling an already-revoked invitation reports already_revoked (R5)'
);
select is(
  (select revoked_at from public.guardian_invitations
    where token_hash = '0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e'),
  (select revoked_at from tmp_te_revoked_at),
  'revoked_at is unchanged by the second cancellation (R5, idempotent)'
);

-- ---------------------------------------------------------------------------
-- 10. Cancelling an already-accepted invitation -> outcome already_accepted,
--     and the corresponding profile_guardians row is still accepted (R5).
-- ---------------------------------------------------------------------------
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a')
  ) ->> 'outcome'),
  'already_accepted',
  'Cancelling an already-accepted invitation reports already_accepted (R5)'
);
select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(801) and user_id = tests.get_supabase_uid('dad')),
  'accepted',
  'Cancellation never retro-revokes an already-accepted membership (R5)'
);

-- ---------------------------------------------------------------------------
-- 11. Cancelling an expired invitation -> outcome expired, revoked_at
--     stamped (Q1).
-- ---------------------------------------------------------------------------
select is(
  (select public.revoke_guardian_invitation(
    (select id from public.guardian_invitations where token_hash =
      '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a')
  ) ->> 'outcome'),
  'expired',
  'Cancelling an already-expired invitation reports expired'
);
select isnt(
  (select revoked_at from public.guardian_invitations
    where token_hash = '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a'),
  null,
  'An expired invitation is stamped revoked_at for an unambiguous terminal state (Q1)'
);

-- ---------------------------------------------------------------------------
-- 12. accept_guardian_invitation with a token whose invitation was just
--     cancelled -> object_not_in_prerequisite_state, no profile_guardians
--     row created (proves the cancel actually bites).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('nanny');
select throws_ok(
  $$select public.accept_guardian_invitation('0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e')$$,
  '55000', null,
  'A cancelled invitation cannot be redeemed'
);
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(801) and user_id = tests.get_supabase_uid('nanny')),
  0::bigint,
  'No membership row is created from the blocked redemption'
);

-- ---------------------------------------------------------------------------
-- 13. authenticated has no UPDATE privilege on any invitation-state column,
--     and the guardian_invitations_update policy is gone (R4).
-- ---------------------------------------------------------------------------
select ok(
  not has_column_privilege('authenticated', 'public.guardian_invitations', 'revoked_at', 'UPDATE'),
  'authenticated has no UPDATE privilege on revoked_at (R4)'
);
select ok(
  not has_column_privilege('authenticated', 'public.guardian_invitations', 'accepted_at', 'UPDATE'),
  'authenticated has no UPDATE privilege on accepted_at (R4)'
);
select ok(
  not has_column_privilege('authenticated', 'public.guardian_invitations', 'accepted_by', 'UPDATE'),
  'authenticated has no UPDATE privilege on accepted_by (R4)'
);
select is(
  (select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'guardian_invitations'
      and policyname = 'guardian_invitations_update'),
  0::bigint,
  'The guardian_invitations_update policy no longer exists (KTD2)'
);

-- ---------------------------------------------------------------------------
-- 14. A direct update as the invitation's own creator is rejected (the
--     withdrawn grant, proven behaviorally rather than only from the
--     catalog).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select throws_ok(
  $$update public.guardian_invitations set revoked_at = now()
     where token_hash = '0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f'$$,
  '42501', null,
  'A direct update by the invitation''s own creator is rejected (withdrawn grant)'
);

-- ---------------------------------------------------------------------------
-- 15. revoke_guardian still cancels the profile's outstanding invitations -
--     existing behavior unregressed. A fresh invite is created first so this
--     is not entangled with anything already cancelled above.
-- ---------------------------------------------------------------------------
select public.create_guardian_invitation(
  tests.ulid(801), 'caregiver', 'Post-revoke check',
  '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b', 48
);
select public.revoke_guardian(tests.ulid(801), tests.get_supabase_uid('sitter'));
select isnt(
  (select revoked_at from public.guardian_invitations
    where token_hash = '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b'),
  null,
  'revoke_guardian still cancels the profile''s outstanding invitations (unregressed)'
);

rollback;
