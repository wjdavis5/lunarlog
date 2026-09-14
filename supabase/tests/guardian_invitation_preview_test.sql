-- Coverage for preview_guardian_invitation (Issue #594): a valid token
-- returns the profile name, role, and expiry; every other token state
-- (wrong, expired, revoked, already accepted, or pointing at a
-- soft-deleted profile) returns the identical uniform "not available"
-- result; the call never mutates anything; and the grants/rate-limit match
-- the security posture in this RPC's own migration.
begin;
select plan(21);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('stranger');
select tests.create_supabase_user('rate_limit_tester');
select tests.create_supabase_user('sweep_tester');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile (P1, live) and a second profile (P2) that will be
-- soft-deleted after its own invitation is created.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(850), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(851), 'Ghost', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- tL: a live, unexpired caregiver invitation on P1 - the success case.
-- Its expires_at is captured into a temp table while still authenticated as
-- mom (an accepted guardian, admitted by guardian_invitations_select) -
-- 'stranger' below can redeem preview_guardian_invitation's own
-- SECURITY DEFINER access to the row, but a direct table read as a
-- non-guardian would itself be RLS-filtered to nothing, so the *expected*
-- value has to be captured before switching identities, not alongside the
-- assertion.
create temporary table tmp_live_invite as
  select (public.create_guardian_invitation(
    tests.ulid(850), 'caregiver', 'Sitter',
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a', 48
  ) ->> 'expires_at')::timestamptz as expires_at;

-- tA: a co_parent invitation on P1 that dad will accept - the
-- already-accepted case.
select public.create_guardian_invitation(
  tests.ulid(850), 'co_parent', 'Dad',
  '4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b', 'Dad'
);

-- tG: a live invitation on P2, whose profile is then soft-deleted - the
-- soft-deleted-profile case. tR/tE below are fabricated directly (a revoked
-- and a pre-expired row) - neither state is producible through the
-- ordinary RPC surface.
select tests.authenticate_as('mom');
select public.create_guardian_invitation(
  tests.ulid(851), 'viewer', 'Grandma',
  '4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c', 48
);
update public.profiles set deleted_at = now() where id = tests.ulid(851);

select tests.clear_authentication();
insert into public.guardian_invitations
  (profile_id, invited_by, token_hash, role, recipient_label, expires_at, revoked_at)
values
  (tests.ulid(850), tests.get_supabase_uid('mom'),
   '4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d',
   'caregiver', 'Revoked', now() + interval '48 hours', now());
insert into public.guardian_invitations
  (profile_id, invited_by, token_hash, role, recipient_label, expires_at)
values
  (tests.ulid(850), tests.get_supabase_uid('mom'),
   '4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e',
   'viewer', 'Long Gone', now() - interval '1 hour');

-- ---------------------------------------------------------------------------
-- 1. A live, unexpired token, previewed by a caller who is not a guardian
--    of the profile (possession of the hash is the credential - the same
--    model accept_guardian_invitation already uses), returns exactly
--    profile_display_name, role and expires_at - nothing else.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');
select is(
  (select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  ) ->> 'profile_display_name'),
  'Riley',
  'A live invitation previews the profile''s display name'
);
select is(
  (select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  ) ->> 'role'),
  'caregiver',
  'A live invitation previews the offered role'
);
select is(
  ((select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  ) ->> 'expires_at')::timestamptz),
  (select expires_at from tmp_live_invite),
  'A live invitation previews its real expires_at'
);
select is(
  (select array_agg(k order by k) from jsonb_object_keys(public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  )) as k),
  array['expires_at', 'profile_display_name', 'role'],
  'Exactly three keys are returned - no profile id, no other guardians, nothing extra'
);

-- ---------------------------------------------------------------------------
-- 2. Read-only: previewing never creates a profile_guardians row for the
--    caller (no membership change). accepted_at is proven unchanged
--    separately for tA below (a row 'stranger' cannot see directly).
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.profile_guardians
    where profile_id = tests.ulid(850)
      and user_id = tests.get_supabase_uid('stranger')),
  0::bigint,
  'Previewing never creates a profile_guardians row'
);

-- ---------------------------------------------------------------------------
-- 3. Every non-live state returns the identical uniform "not available"
--    result (SQL null) - a wrong token, revoked, expired, already accepted,
--    and a live token whose profile was soft-deleted.
-- ---------------------------------------------------------------------------
select is(
  public.preview_guardian_invitation(
    '4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f'
  ),
  null,
  'A nonexistent token_hash returns null'
);
select is(
  public.preview_guardian_invitation(
    '4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d'
  ),
  null,
  'A revoked invitation returns null'
);
select is(
  public.preview_guardian_invitation(
    '4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e4e'
  ),
  null,
  'An expired invitation returns null'
);
select is(
  public.preview_guardian_invitation(
    '4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b4b'
  ),
  null,
  'An already-accepted invitation returns null'
);
select is(
  public.preview_guardian_invitation(
    '4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c4c'
  ),
  null,
  'A live invitation whose profile was soft-deleted returns null'
);

-- ---------------------------------------------------------------------------
-- 4. Malformed token_hash inputs are rejected outright, the same way
--    create_guardian_invitation/accept_guardian_invitation already are -
--    not a 64-char lowercase hex string (CI has previously failed a PR that
--    fabricated a hash like 'i2i2...').
-- ---------------------------------------------------------------------------
select throws_ok(
  $$select public.preview_guardian_invitation('i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2i2')$$,
  '22023', 'token_hash must be a 64-character hex string',
  'A non-hex token_hash is rejected'
);
select throws_ok(
  $$select public.preview_guardian_invitation('4a4a')$$,
  '22023', 'token_hash must be a 64-character hex string',
  'A too-short token_hash is rejected'
);

-- ---------------------------------------------------------------------------
-- 5. Authentication is required (mirrors every other guardian_invitations
--    RPC in this schema).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select throws_ok(
  $$select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  )$$,
  '42501', 'authentication required',
  'A signed-out caller cannot preview'
);

-- ---------------------------------------------------------------------------
-- 6. Grants: authenticated only, matching the client flow (a signed-out
--    recipient never reaches the accept sheet, so never reaches this
--    preview - see the migration header).
-- ---------------------------------------------------------------------------
select ok(
  has_function_privilege('authenticated', 'public.preview_guardian_invitation(text)', 'execute'),
  'authenticated can execute preview_guardian_invitation'
);
select ok(
  not has_function_privilege('anon', 'public.preview_guardian_invitation(text)', 'execute'),
  'anon cannot execute preview_guardian_invitation'
);

-- ---------------------------------------------------------------------------
-- 7. Rate limit: a caller's 21st preview attempt within a trailing minute
--    is refused, scoped per-caller (a different signed-in user is
--    unaffected by another user's rate limit). A dedicated fresh user runs
--    the 20 filler calls so this is not coupled to how many preview calls
--    happen to precede it elsewhere in this file.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('rate_limit_tester');
do $$
begin
  for i in 1..20 loop
    -- A different wrong hash each time - proves the limit throttles
    -- grinding through many *different* guesses, not just repeats of one.
    perform public.preview_guardian_invitation(
      lpad(to_hex(i), 64, '0'));
  end loop;
end;
$$;
select throws_ok(
  $$select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  )$$,
  '55000', 'too many preview attempts; wait a moment and try again',
  'A caller''s 21st preview attempt within a minute is rate-limited'
);
select tests.authenticate_as('dad');
select is(
  (select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  ) ->> 'profile_display_name'),
  'Riley',
  'The rate limit is scoped per caller - a different signed-in user is unaffected'
);

-- ---------------------------------------------------------------------------
-- 8. Read-only, proven directly on the invitation row itself: after every
--    preview above, accepted_at is still null. mom (invited_by) can see
--    this row directly - RLS admits her without needing a SECURITY
--    DEFINER helper.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select is(
  (select accepted_at from public.guardian_invitations
    where id = tests.invitation_id_by_hash(
      '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a')),
  null,
  'Previewing never sets accepted_at on the invitation row (no membership change)'
);

-- ---------------------------------------------------------------------------
-- 9. Bounded growth (round-1 review): a preview call sweeps this caller's
--    own stale attempts (older than the trailing window) before counting,
--    so the table doesn't grow without bound, and the 20/minute limit
--    still fires correctly afterward. Fixtures are backdated directly (as
--    table owner, bypassing the function) rather than produced by waiting
--    a real minute.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
insert into public.guardian_invitation_preview_attempts (user_id, attempted_at)
select tests.get_supabase_uid('sweep_tester'), now() - interval '2 minutes'
  from generate_series(1, 15);
insert into public.guardian_invitation_preview_attempts (user_id, attempted_at)
select tests.get_supabase_uid('sweep_tester'), now() - interval '10 seconds'
  from generate_series(1, 5);
select is(
  (select count(*) from public.guardian_invitation_preview_attempts
    where user_id = tests.get_supabase_uid('sweep_tester')),
  20::bigint,
  'sweep fixture: 15 stale (2 minutes old) + 5 fresh (10 seconds old) attempts'
);

select tests.authenticate_as('sweep_tester');
select public.preview_guardian_invitation(
  '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
);

select tests.clear_authentication();
select is(
  (select count(*) from public.guardian_invitation_preview_attempts
    where user_id = tests.get_supabase_uid('sweep_tester')),
  6::bigint,
  'one preview call swept the 15 stale rows; the 5 fresh rows plus this '
  'call''s own new row remain (no unbounded growth)'
);

-- Top the caller back up from 6 to 20 fresh attempts, then confirm the
-- 21st is still rate-limited - the sweep never weakens the limit itself.
select tests.authenticate_as('sweep_tester');
do $$
begin
  for i in 1..14 loop
    perform public.preview_guardian_invitation(
      lpad(to_hex(i + 1000), 64, '0'));
  end loop;
end;
$$;
select throws_ok(
  $$select public.preview_guardian_invitation(
    '4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a4a'
  )$$,
  '55000', 'too many preview attempts; wait a moment and try again',
  'the 20/minute limit still triggers correctly after the sweep'
);

rollback;
