-- Regression coverage for the revocation bypass (Issues #81 and #82): a
-- revoked guardian could previously redeem an invitation they still held to
-- restore their own access, with no action by the primary guardian. Reuses
-- the create_guardian_invitation / accept_guardian_invitation RPC-handshake
-- idiom from profile_guardians_rls_test.sql.
begin;
select plan(7);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');

-- ---------------------------------------------------------------------------
-- Setup: Mom creates a profile and sends Dad two invitations (mirrors the
-- #81 repro: a second, unrelated invitation sits unredeemed alongside the
-- one Dad actually accepts). Dad accepts the first as co_parent.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(701), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(701), 'co_parent', 'Dad',
  '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a', 48
);
-- The "spare" invitation: still live and unredeemed when Dad is revoked.
select public.create_guardian_invitation(
  tests.ulid(701), 'co_parent', 'Dad (spare)',
  '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b', 48
);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a', 'Dad'
);

-- ---------------------------------------------------------------------------
-- (a) revoke_guardian cancels the still-live spare invitation (#81).
-- Proves: revocation reaches guardian_invitations, not just
-- profile_guardians.status. Would fail (revoked_at stays null, and the
-- later accept attempt would succeed instead of throwing) if #81 regressed
-- and revoke_guardian went back to only flipping status.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.revoke_guardian(tests.ulid(701), tests.get_supabase_uid('dad'));

select isnt(
  (select revoked_at from public.guardian_invitations
    where token_hash = '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b'),
  null,
  'revoke_guardian cancels a still-live invitation for the profile (#81)'
);

select tests.authenticate_as('dad');
select throws_ok(
  $$select public.accept_guardian_invitation('2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b')$$,
  '55000', null,
  'The spare invitation is no longer redeemable after revocation (#81)'
);

select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(701) and user_id = tests.get_supabase_uid('dad')),
  'revoked',
  'Dad''s membership is still revoked after the blocked redemption attempt'
);

-- ---------------------------------------------------------------------------
-- (b) accept_guardian_invitation independently refuses a stale token, even
-- when it is somehow still live - defence in depth for #82, isolated from
-- #81. This directly undoes #81's cancellation on the spare invitation (as
-- if it had never run) to prove #82's own guard does not depend on it.
-- Proves: a revoked membership cannot be flipped back to accepted by
-- redeeming an old token. Would fail (status flips to 'accepted' instead of
-- throwing) if the upsert in accept_guardian_invitation went back to
-- setting status = 'accepted' unconditionally.
-- ---------------------------------------------------------------------------
-- Issue #3 gap-closure plan (Unit U1, KTD2) withdrew the direct
-- `update (revoked_at)` grant entirely, so this test-only rewind (never a
-- capability the app itself has) now needs the table owner's bypass rather
-- than an authenticated session.
select tests.clear_authentication();
update public.guardian_invitations
   set revoked_at = null
 where token_hash = '2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b';

select tests.authenticate_as('dad');
select throws_ok(
  $$select public.accept_guardian_invitation('2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b')$$,
  '55000', null,
  'A stale token is refused independent of invitation-side cancellation (#82)'
);

select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(701) and user_id = tests.get_supabase_uid('dad')),
  'revoked',
  'Dad''s membership remains revoked - not flipped back by the stale token (#82)'
);

-- ---------------------------------------------------------------------------
-- (c) a genuinely new invitation issued after the revocation still works -
-- the judgement call that revocation must not permanently bar deliberate
-- re-invitation. The sleep is timing insurance, not a functional
-- requirement: created_at/revoked_at both use clock_timestamp(), which
-- already advances between separate statements, but the two events here are
-- close together.
-- Proves: revoking someone does not permanently block re-adding them
-- through a fresh invitation. Would fail (throws instead of succeeding) if
-- the #82 guard were widened to reject any invitation for a previously
-- revoked user rather than only ones that predate the revocation.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select pg_sleep(0.01);
select public.create_guardian_invitation(
  tests.ulid(701), 'co_parent', 'Dad (re-invited)',
  '3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c', 48
);

select tests.authenticate_as('dad');
select is(
  (select public.accept_guardian_invitation(
    '3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c', 'Dad'
  ) ->> 'role'),
  'co_parent',
  'A fresh invitation issued after the revocation lets Dad be re-added'
);

select is(
  (select status from public.profile_guardians
    where profile_id = tests.ulid(701) and user_id = tests.get_supabase_uid('dad')),
  'accepted',
  'Dad''s membership is accepted again after redeeming the fresh invitation'
);

rollback;
