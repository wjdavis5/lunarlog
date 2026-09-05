-- RLS and permission tests for multi-guardian access (Issue #8, Unit U1).
begin;
select plan(24);

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
-- 4. Mom adds Dad as co_parent
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profile_guardians (profile_id, user_id, role, status, display_name)
values (tests.ulid(101), tests.get_supabase_uid('dad'), 'co_parent', 'accepted', 'Dad');

-- Dad can see Maya, update Maya profile, and log entries
select tests.authenticate_as('dad');

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
-- 5. Mom adds Sitter as caregiver
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profile_guardians (profile_id, user_id, role, status, display_name)
values (tests.ulid(101), tests.get_supabase_uid('sitter'), 'caregiver', 'accepted', 'Babysitter Sue');

select tests.authenticate_as('sitter');

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

-- ---------------------------------------------------------------------------
-- 6. Mom adds Doctor as viewer
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

insert into public.profile_guardians (profile_id, user_id, role, status, display_name)
values (tests.ulid(101), tests.get_supabase_uid('doctor'), 'viewer', 'accepted', 'Dr. Smith');

select tests.authenticate_as('doctor');

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
-- 7. Revocation
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');

-- Mom revokes Sitter
update public.profile_guardians
   set status = 'revoked', updated_at = now()
 where profile_id = tests.ulid(101) and user_id = tests.get_supabase_uid('sitter');

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
-- 8. Guardian Invitations
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');

-- Dad creates an invitation for Grandma
insert into public.guardian_invitations (profile_id, invited_by, token_hash, role, recipient_label, expires_at)
values (
  tests.ulid(101),
  tests.get_supabase_uid('dad'),
  'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  'caregiver',
  'Grandma',
  now() + interval '48 hours'
);

select is(
  (select count(*) from public.guardian_invitations where profile_id = tests.ulid(101)),
  1::bigint,
  'Dad can create guardian invitation'
);

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
