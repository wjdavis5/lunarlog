-- RLS and permission tests for multi-guardian access (Issue #8, Unit U1).
begin;
select plan(35);

-- ---------------------------------------------------------------------------
-- Setup users: Mom (creator), Dad (co_parent), Sitter (caregiver), Doctor (viewer), Stranger
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('sitter');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('stranger');

-- ---------------------------------------------------------------------------
-- 1. RLS enabled and forced
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public');
select tests.rls_forced('public', 'profile_guardians');
select tests.rls_forced('public', 'guardian_invitations');

-- ---------------------------------------------------------------------------
-- 2. Mom creates Maya's profile -> trigger creates primary_guardian
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(101), 'Maya', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select is(
  (select count(*) from public.profile_guardians where profile_id = tests.ulid(101) and user_id = tests.get_supabase_uid('mom') and role = 'primary_guardian' and status = 'accepted'),
  1::bigint,
  'Trigger automatically creates primary_guardian entry for profile creator'
);

-- Mom inserts a day entry
insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, note, updated_at)
values (tests.ulid(102), tests.ulid(101), '2026-09-01', 'America/New_York', 'medium', '["cramps"]', 'Maya started period', '2026-09-01T08:15:00Z');

select is(
  (select count(*) from public.day_entries where id = tests.ulid(102)),
  1::bigint,
  'Mom can insert and select day entry'
);

-- ---------------------------------------------------------------------------
-- 3. Stranger cannot see Maya's profile or entries
-- ---------------------------------------------------------------------------
select tests.authenticate_as('stranger');

select is(
  (select count(*) from public.profiles where id = tests.ulid(101)),
  0::bigint,
  'Stranger cannot see Maya profile'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(101)),
  0::bigint,
  'Stranger cannot see Maya day entries'
);
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
    values (tests.ulid(103), tests.ulid(101), '2026-09-02', 'UTC', 'none', now())$$,
  '42501', null, 'Stranger cannot insert day entry for Maya'
);

-- ---------------------------------------------------------------------------
-- 4. Mom adds Dad as co_parent (via the invitation handshake - membership
--    rows are never writable by direct INSERT, see section 7 below)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

select public.create_guardian_invitation(
  tests.ulid(101),
  'co_parent',
  'Dad',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  48
);

select tests.authenticate_as('dad');

select public.accept_guardian_invitation(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'Dad'
);

-- Dad can see Maya, update Maya profile, and log entries
select is(
  (select count(*) from public.profiles where id = tests.ulid(101)),
  1::bigint,
  'Dad (co-parent) can see Maya profile'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(101)),
  1::bigint,
  'Dad (co-parent) can see Maya day entries'
);

-- Dad logs a second day entry
insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, note, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(104), tests.ulid(101), '2026-09-02', 'America/New_York', 'light', '[]', 'Dad logged flow', '2026-09-02T10:00:00Z', tests.get_supabase_uid('dad'), tests.get_supabase_uid('dad'));

select is(
  (select count(*) from public.day_entries where id = tests.ulid(104)),
  1::bigint,
  'Dad can insert day entry for Maya'
);

-- Dad can update Maya's display name or sort order
with u as (
  update public.profiles set display_name = 'Maya Davis' where id = tests.ulid(101) returning 1
) select is(count(*), 1::bigint, 'Dad can update Maya profile metadata') from u;

-- ---------------------------------------------------------------------------
-- 5. Mom adds Sitter as caregiver (via the invitation handshake)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

select public.create_guardian_invitation(
  tests.ulid(101),
  'caregiver',
  'Babysitter Sue',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  48
);

select tests.authenticate_as('sitter');

select public.accept_guardian_invitation(
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'Babysitter Sue'
);

select is(
  (select count(*) from public.profiles where id = tests.ulid(101)),
  1::bigint,
  'Sitter (caregiver) can see Maya profile'
);

-- Sitter logs cramps on 2026-09-03
insert into public.day_entries (id, profile_id, local_date, tz, flow, tags, note, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(105), tests.ulid(101), '2026-09-03', 'America/New_York', 'spotting', '["cramps"]', 'Mild cramps', '2026-09-03T14:00:00Z', tests.get_supabase_uid('sitter'), tests.get_supabase_uid('sitter'));

select is(
  (select count(*) from public.day_entries where id = tests.ulid(105)),
  1::bigint,
  'Sitter (caregiver) can log day entry for Maya'
);

-- Sitter cannot update profile metadata
with u as (
  update public.profiles set display_name = 'Hacked by Sitter' where id = tests.ulid(101) returning 1
) select is(count(*), 0::bigint, 'Sitter cannot update profile metadata (0 rows updated)') from u;

-- Sitter cannot forge attribution: logged_by_user_id is not even granted
-- for direct UPDATE, and a forged last_modified_by_user_id value trips the
-- attribution guard trigger (R11/AE2 beyond the sync_push path).
select throws_ok(
  $$update public.day_entries set logged_by_user_id = tests.get_supabase_uid('mom') where id = tests.ulid(105)$$,
  '42501', null, 'Sitter cannot UPDATE logged_by_user_id directly (column not granted)'
);
select throws_ok(
  $$update public.day_entries set last_modified_by_user_id = tests.get_supabase_uid('mom') where id = tests.ulid(105)$$,
  '42501', null, 'Sitter cannot forge last_modified_by_user_id (trigger enforces caller uid)'
);

-- ---------------------------------------------------------------------------
-- 6. Mom adds Doctor as viewer (via the invitation handshake)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

select public.create_guardian_invitation(
  tests.ulid(101),
  'viewer',
  'Dr. Smith',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  48
);

select tests.authenticate_as('doctor');

select public.accept_guardian_invitation(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  'Dr. Smith'
);

select is(
  (select count(*) from public.profiles where id = tests.ulid(101)),
  1::bigint,
  'Doctor (viewer) can see Maya profile'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(101)),
  3::bigint,
  'Doctor (viewer) can see all Maya day entries'
);

-- Doctor cannot insert day entry
select throws_ok(
  $$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
    values (tests.ulid(106), tests.ulid(101), '2026-09-04', 'America/New_York', 'none', now())$$,
  '42501', null, 'Doctor (viewer) cannot insert day entries'
);

-- Doctor cannot update day entry
with u as (
  update public.day_entries set note = 'Doctor changed note' where id = tests.ulid(102) returning 1
) select is(count(*), 0::bigint, 'Doctor (viewer) cannot update day entries (0 rows updated)') from u;

-- ---------------------------------------------------------------------------
-- 7. Direct-write negatives on profile_guardians / guardian_invitations
-- ---------------------------------------------------------------------------
-- These are the actors the old policies actually admitted (an accepted
-- co-parent), not a stranger the policy was never going to let in. Both
-- tables carry no INSERT grant for `authenticated` at all (KTD15):
-- membership rows and invitations are created exclusively by the SECURITY
-- DEFINER paths (the profiles trigger, accept_guardian_invitation, and
-- create_guardian_invitation), so any direct INSERT - regardless of who the
-- caller is or what the row contains - fails with insufficient privilege.
select tests.authenticate_as('dad');

select throws_ok(
  $$insert into public.profile_guardians (profile_id, user_id, role, status)
    values (tests.ulid(101), tests.get_supabase_uid('stranger'), 'primary_guardian', 'accepted')$$,
  '42501', null, 'Accepted co-parent cannot direct-insert an arbitrary primary_guardian membership'
);

select throws_ok(
  $$insert into public.guardian_invitations (profile_id, invited_by, token_hash, role, expires_at)
    values (tests.ulid(101), tests.get_supabase_uid('dad'), 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd', 'co_parent', now() + interval '48 hours')$$,
  '42501', null, 'Accepted co-parent cannot direct-insert a co_parent invitation (bypasses R3)'
);

select throws_ok(
  $$insert into public.guardian_invitations (profile_id, invited_by, token_hash, role, expires_at)
    values (tests.ulid(101), tests.get_supabase_uid('dad'), 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee', 'caregiver', now() + interval '100 years')$$,
  '42501', null, 'Accepted co-parent cannot direct-insert an invitation with a 100-year expiry (bypasses R7 TTL bound)'
);

-- R7: the TTL bound is enforced by create_guardian_invitation itself, not
-- just by the missing INSERT grant, so it holds for every future write path.
select throws_ok(
  $$select public.create_guardian_invitation(
    tests.ulid(101), 'caregiver', 'Bad TTL Low',
    '6666666666666666666666666666666666666666666666666666666666666666'::text, 0)$$,
  '22023', null, 'create_guardian_invitation rejects a 0-hour TTL'
);

select throws_ok(
  $$select public.create_guardian_invitation(
    tests.ulid(101), 'caregiver', 'Bad TTL High',
    '7777777777777777777777777777777777777777777777777777777777777777'::text, 169)$$,
  '22023', null, 'create_guardian_invitation rejects a 169-hour TTL (> 168)'
);

-- ---------------------------------------------------------------------------
-- 8. Revocation
-- ---------------------------------------------------------------------------
-- Membership state changes only through the revoke_guardian RPC: the
-- profile_guardians update policy has no self-service branch and `status`
-- is not granted for direct UPDATE.
select tests.authenticate_as('mom');

select is(
  public.revoke_guardian(tests.ulid(101), tests.get_supabase_uid('sitter')),
  true,
  'Mom revokes Sitter via the revoke_guardian RPC'
);

select tests.authenticate_as('sitter');

-- A revoked guardian must not be able to flip its own row back to accepted:
-- the self-service policy branch is gone and `status` is not granted for
-- direct UPDATE, so the attempt fails with insufficient privilege.
select throws_ok(
  $$update public.profile_guardians set status = 'accepted' where profile_id = tests.ulid(101) and user_id = tests.get_supabase_uid('sitter')$$,
  '42501', null, 'Revoked guardian cannot reactivate its own membership'
);

select tests.authenticate_as('sitter');

select is(
  (select count(*) from public.profiles where id = tests.ulid(101)),
  0::bigint,
  'Revoked sitter cannot see Maya profile'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(101)),
  0::bigint,
  'Revoked sitter cannot see Maya day entries'
);

-- ---------------------------------------------------------------------------
-- 9. Guardian Invitations
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');

-- Dad creates an invitation for Grandma via the SECURITY DEFINER RPC
select public.create_guardian_invitation(
  tests.ulid(101),
  'caregiver',
  'Grandma',
  'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  48
);

select is(
  (select count(*) from public.guardian_invitations where profile_id = tests.ulid(101)),
  1::bigint,
  'Dad can create guardian invitation'
);

-- Only the invitation's creator may modify it: even the primary guardian
-- cannot consume or revoke Dad's invitation by direct UPDATE.
select tests.authenticate_as('mom');
with u as (
  update public.guardian_invitations set revoked_at = now() where profile_id = tests.ulid(101) returning 1
) select is(count(*), 0::bigint, 'Non-creator cannot modify another guardian''s invitation (0 rows updated)') from u;

select tests.authenticate_as('dad');
with u as (
  update public.guardian_invitations set revoked_at = now() where profile_id = tests.ulid(101) returning 1
) select is(count(*), 1::bigint, 'Invitation creator can revoke its own invitation') from u;

select tests.authenticate_as('stranger');

select is(
  (select count(*) from public.guardian_invitations where profile_id = tests.ulid(101)),
  0::bigint,
  'Stranger cannot see guardian invitations'
);
select throws_ok(
  $$insert into public.guardian_invitations (profile_id, invited_by, token_hash, role, expires_at)
    values (tests.ulid(101), tests.get_supabase_uid('stranger'), 'f3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855', 'caregiver', now() + interval '48 hours')$$,
  '42501', null, 'Stranger cannot insert invitation for Maya profile'
);

rollback;
