-- RLS coverage for public.notification_preferences (Issue #5, Unit U1).
begin;
select plan(11);

-- #14 (review fix): TRUNCATE bypasses RLS entirely (there is no per-row
-- check for it), so authenticated must not carry the table's default
-- TRUNCATE privilege the way it would if the universal
-- `revoke all ... from public, anon, authenticated` were missing.
select is(
  has_table_privilege('authenticated', 'public.notification_preferences', 'TRUNCATE'),
  false,
  'authenticated cannot TRUNCATE notification_preferences'
);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('stranger');

select tests.rls_forced('public', 'notification_preferences');

-- Mom creates Maya's profile; Dad joins as co-parent via the existing
-- invitation handshake (Issue #8) so both are accepted guardians.
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(201), 'Maya', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(201), 'co_parent', 'Dad',
  '1111111111111111111111111111111111111111111111111111111111111111', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '1111111111111111111111111111111111111111111111111111111111111111', 'Dad'
);

-- 1. An accepted guardian can insert and then select their own row.
select tests.authenticate_as('mom');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('mom'), tests.ulid(201), true);

select is(
  (select alert_on_log from public.notification_preferences
    where user_id = tests.get_supabase_uid('mom') and profile_id = tests.ulid(201)),
  true,
  'An accepted guardian can insert and select their own preference row'
);

-- 2. A guardian cannot select another guardian's row for the same profile.
select tests.authenticate_as('dad');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('dad'), tests.ulid(201), false);

select is(
  (select count(*) from public.notification_preferences
    where user_id = tests.get_supabase_uid('mom')),
  0::bigint,
  'A guardian cannot select another guardian''s preference row'
);

-- 3. A stranger (guards nothing) cannot insert a row for this profile.
select tests.authenticate_as('stranger');
select throws_ok(
  $$insert into public.notification_preferences (user_id, profile_id, alert_on_log)
    values (tests.get_supabase_uid('stranger'), tests.ulid(201), true)$$,
  '42501', null,
  'A user who guards nothing cannot insert a preference row for this profile'
);

-- 4. Revoking a guardian closes both read and write on their row.
select tests.authenticate_as('mom');
select public.revoke_guardian(tests.ulid(201), tests.get_supabase_uid('dad'));

select tests.authenticate_as('dad');
select is(
  (select count(*) from public.notification_preferences
    where user_id = tests.get_supabase_uid('dad')),
  0::bigint,
  'A revoked guardian can no longer select their own previously-readable row'
);
with u as (
  update public.notification_preferences
     set alert_on_log = true
   where user_id = tests.get_supabase_uid('dad')
  returning 1
) select is(count(*), 0::bigint, 'A revoked guardian cannot update their previously-readable row') from u;

-- 5. missed_entry_days check constraint.
select tests.authenticate_as('mom');
select throws_ok(
  format(
    $$update public.notification_preferences set missed_entry_days = 0
       where user_id = %L and profile_id = %L$$,
    tests.get_supabase_uid('mom'), tests.ulid(201)
  ),
  '23514', null,
  'missed_entry_days = 0 is rejected by the check constraint'
);
select throws_ok(
  format(
    $$update public.notification_preferences set missed_entry_days = 4
       where user_id = %L and profile_id = %L$$,
    tests.get_supabase_uid('mom'), tests.ulid(201)
  ),
  '23514', null,
  'missed_entry_days = 4 is rejected by the check constraint'
);
with u as (
  update public.notification_preferences set missed_entry_days = null
   where user_id = tests.get_supabase_uid('mom') and profile_id = tests.ulid(201)
  returning 1
) select is(count(*), 1::bigint, 'missed_entry_days = null is accepted') from u;

-- 6. anon has no grant at all.
select tests.authenticate_as_anon();
select throws_ok(
  $$select * from public.notification_preferences$$,
  '42501', null,
  'anon has no grant on notification_preferences'
);

rollback;
