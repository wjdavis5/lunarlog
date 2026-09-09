-- Regression coverage for public.export_account_data() (Issue #248): the
-- server-side right-of-access export RPC. Reuses the
-- create_supabase_user / authenticate_as handshake and the pg_temp snapshot
-- idiom already established in account_deletion_test.sql.
begin;
select plan(69);

create temp table snap (name text primary key, v jsonb);
grant all on table snap to authenticated;

create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into snap values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.snap(n text) returns jsonb language sql as
  $$ select v from snap where name = n $$;

-- Small jsonb navigation helpers, scoped to this file's pg_temp schema.
create function pg_temp.profile_by_id(doc jsonb, p_id text) returns jsonb language sql as
  $$ select value from jsonb_array_elements(coalesce(doc -> 'profiles', '[]'::jsonb))
     where value ->> 'id' = p_id limit 1 $$;
create function pg_temp.day_entry_ids(profile_json jsonb) returns text[] language sql as
  $$ select coalesce(array_agg(value ->> 'id' order by value ->> 'id'), array[]::text[])
     from jsonb_array_elements(coalesce(profile_json -> 'day_entries', '[]'::jsonb)) $$;
create function pg_temp.count_in(doc jsonb, key text) returns bigint language sql as
  $$ select jsonb_array_length(coalesce(doc -> key, '[]'::jsonb)) $$;
create function pg_temp.guardian_user_ids_for(doc jsonb, p_id text) returns uuid[] language sql as
  $$ select coalesce(array_agg((value ->> 'user_id')::uuid order by value ->> 'user_id'), array[]::uuid[])
     from jsonb_array_elements(coalesce(doc -> 'profile_guardians', '[]'::jsonb))
     where value ->> 'profile_id' = p_id $$;
create function pg_temp.invitation_inviters_for(doc jsonb, p_id text) returns uuid[] language sql as
  $$ select coalesce(array_agg((value ->> 'invited_by')::uuid order by value ->> 'invited_by'), array[]::uuid[])
     from jsonb_array_elements(coalesce(doc -> 'guardian_invitations', '[]'::jsonb))
     where value ->> 'profile_id' = p_id $$;
-- Sorts an arbitrary uuid list the same way the two helpers above already
-- sort their jsonb results (by text form) - random uuids have no natural
-- order, so an expected-value literal must be sorted identically or an
-- otherwise-correct assertion could fail on uuid draw order alone.
create function pg_temp.sorted_uuids(variadic ids uuid[]) returns uuid[] language sql as
  $$ select array_agg(u order by u::text) from unnest(ids) as u $$;

select tests.create_supabase_user('user_a'); -- owner, family A
select tests.create_supabase_user('user_b'); -- co_parent on A's profile, family A
select tests.create_supabase_user('user_c'); -- owner, family C (isolation target)
select tests.create_supabase_user('user_d'); -- caregiver on C's profile, family C
select tests.create_supabase_user('user_e'); -- owner, family E; also an accepted
                                              -- caregiver on C's profile - the
                                              -- cross-family case

-- ---------------------------------------------------------------------------
-- 1. Function shape: security definer, search_path = '', authenticated-only.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_proc
     where proname = 'export_account_data'
       and pronamespace = 'public'::regnamespace
  ),
  'public.export_account_data() exists'
);

select is(
  (select prosecdef from pg_proc
    where proname = 'export_account_data' and pronamespace = 'public'::regnamespace),
  true,
  'export_account_data is security definer'
);

select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'export_account_data' and pronamespace = 'public'::regnamespace
       and c.setting = 'search_path=""'
  ),
  'export_account_data pins search_path to exactly empty, not merely some search_path setting'
);

select ok(
  has_function_privilege('authenticated', 'public.export_account_data()', 'execute'),
  'authenticated can execute export_account_data'
);

select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'export_account_data'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint,
  'PUBLIC and anon hold no EXECUTE on export_account_data'
);

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.export_account_data()$$,
  '42501', null,
  'anon cannot execute export_account_data'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'authenticated', true);
select throws_ok(
  $$select public.export_account_data()$$,
  '42501', null,
  'an authenticated role with no JWT claims is refused (auth.uid() is null)'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 2. Family A fixture: A owns profile 1; B is an accepted co_parent on it.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
insert into public.profiles (id, display_name, is_minor, sort_order, birth_year, relationship, created_at, updated_at)
values (tests.ulid(1), 'Riley A', true, 0, 2015, 'daughter', '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(1), 'co_parent', 'B',
  'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0', 48
);

select tests.authenticate_as('user_b');
select public.accept_guardian_invitation(
  'a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0a0', 'B'
);

-- A logs one entry; B (now co_parent) logs another on the same shared
-- profile - the exact "entries they authored" case the shared-profile
-- scoping must isolate.
select tests.authenticate_as('user_a');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z',
        tests.get_supabase_uid('user_a'), tests.get_supabase_uid('user_a'));

select tests.authenticate_as('user_b');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(11), tests.ulid(1), '2026-09-02', 'UTC', 'medium', '2026-09-02T00:00:00Z',
        tests.get_supabase_uid('user_b'), tests.get_supabase_uid('user_b'));

-- B (co_parent) may invite a caregiver/viewer (R3) - a second, distinct
-- inviter on the same profile, exercising the "invitations the caller
-- personally created" shared-profile predicate.
select public.create_guardian_invitation(
  tests.ulid(1), 'caregiver', 'X',
  'b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0', 48
);

-- Distinct preference values per guardian so "whose row is this" is provable
-- from content, not just presence.
insert into public.notification_preferences (user_id, profile_id, alert_on_log, missed_entry_days)
values (tests.get_supabase_uid('user_b'), tests.ulid(1), false, 1);

select tests.authenticate_as('user_a');
insert into public.notification_preferences (user_id, profile_id, alert_on_log, missed_entry_days)
values (tests.get_supabase_uid('user_a'), tests.ulid(1), true, 2);

insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-0000000000a1'::uuid, tests.get_supabase_uid('user_a'), 'token-family-a-AAAA1111', 'ios');

select tests.authenticate_as('user_b');
insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-0000000000b1'::uuid, tests.get_supabase_uid('user_b'), 'token-family-b-BBBB2222', 'android');

select tests.authenticate_as('user_a');
select public.upsert_reminder_window(tests.ulid(1), '2026-09-15', false);

select public.create_ownership_transfer(
  tests.ulid(1), 'co_parent',
  'c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0c0',
  'reserve for B', 72
);

-- missed_entry_alert_state has no authenticated grant at all - owned
-- exclusively by scan_missed_entry_reminders() - so its fixture rows go in
-- directly as service_role, mirroring account_deletion_test.sql section 10.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
values
  (tests.ulid(1), tests.get_supabase_uid('user_a'), '2026-09-10'),
  (tests.ulid(1), tests.get_supabase_uid('user_b'), '2026-09-11');

-- A submits a feedback ticket with an admin reply (service_role - no
-- authenticated policy admits author_type = 'admin') and a follow-up user
-- reply (A, the ticket owner).
select tests.authenticate_as('user_a');
insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('user_a'), 'a@test.local', 'bug', 'Something broke');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.feedback_replies (ticket_id, author_type, message)
select id, 'admin', 'Thanks, looking into it' from public.feedback_tickets
 where user_id = tests.get_supabase_uid('user_a');

select tests.authenticate_as('user_a');
insert into public.feedback_replies (ticket_id, author_type, message)
select id, 'user', 'Any update?' from public.feedback_tickets
 where user_id = tests.get_supabase_uid('user_a');

-- ---------------------------------------------------------------------------
-- 3. Family C fixture: an entirely unrelated household (isolation target).
--    C owns profile 2; D is an accepted caregiver on it.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_c');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2), 'Riley C', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(2), 'caregiver', 'D',
  'd0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0', 48
);

select tests.authenticate_as('user_d');
select public.accept_guardian_invitation(
  'd0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0d0', 'D'
);

insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(20), tests.ulid(2), '2026-09-01', 'UTC', 'heavy', '2026-09-01T00:00:00Z',
        tests.get_supabase_uid('user_d'), tests.get_supabase_uid('user_d'));

insert into public.notification_preferences (user_id, profile_id, alert_on_log, missed_entry_days)
values (tests.get_supabase_uid('user_d'), tests.ulid(2), true, 3);

insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-0000000000d1'::uuid, tests.get_supabase_uid('user_d'), 'token-family-c-DDDD9999', 'ios');

select tests.authenticate_as('user_c');
insert into public.notification_preferences (user_id, profile_id, alert_on_log, missed_entry_days)
values (tests.get_supabase_uid('user_c'), tests.ulid(2), true, 3);

insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-0000000000c1'::uuid, tests.get_supabase_uid('user_c'), 'token-family-c-CCCC8888', 'ios');

select public.upsert_reminder_window(tests.ulid(2), '2026-09-20', false);

select public.create_ownership_transfer(
  tests.ulid(2), 'viewer',
  'e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0',
  'reserve for D', 72
);

insert into public.feedback_tickets (user_id, reply_email, category, message)
values (tests.get_supabase_uid('user_c'), 'c@test.local', 'support', 'Question about C');

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
values
  (tests.ulid(2), tests.get_supabase_uid('user_c'), '2026-09-12'),
  (tests.ulid(2), tests.get_supabase_uid('user_d'), '2026-09-13');

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 4. A's export (owner): full data for the owned profile, plus proof that
--    none of family C's rows leak in.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_a');
select pg_temp.snapshot('a_result', public.export_account_data());

select is(
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.snap('a_result')) k),
  array['exported_at', 'feedback_tickets', 'guardian_invitations', 'missed_entry_alert_state',
        'notification_preferences', 'ownership_transfers', 'profile_guardians',
        'profile_reminder_windows', 'profiles', 'push_devices', 'schema_version'],
  'A: export document has exactly the expected top-level keys'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'profiles'), 1::bigint,
  'A: exactly one profile (family C''s profile is not present)');

select is(
  pg_temp.profile_by_id(pg_temp.snap('a_result'), tests.ulid(1)) ->> 'owned',
  'true',
  'A: owned profile is marked owned = true'
);

select is(
  pg_temp.day_entry_ids(pg_temp.profile_by_id(pg_temp.snap('a_result'), tests.ulid(1))),
  array[tests.ulid(10), tests.ulid(11)],
  'A: owned profile carries every live day entry, including the one B (co_parent) logged'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'profile_guardians'), 2::bigint,
  'A: profile_guardians includes both A''s and B''s membership rows (owned profile, full data)');

select is(
  pg_temp.guardian_user_ids_for(pg_temp.snap('a_result'), tests.ulid(1)),
  pg_temp.sorted_uuids(tests.get_supabase_uid('user_a'), tests.get_supabase_uid('user_b')),
  'A: profile_guardians for the owned profile names both guardians'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'guardian_invitations'), 2::bigint,
  'A: guardian_invitations includes both A''s and B''s invitations (owned profile, full data)');

select is(
  pg_temp.invitation_inviters_for(pg_temp.snap('a_result'), tests.ulid(1)),
  pg_temp.sorted_uuids(tests.get_supabase_uid('user_a'), tests.get_supabase_uid('user_b')),
  'A: guardian_invitations for the owned profile names both inviters'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'notification_preferences'), 1::bigint,
  'A: notification_preferences includes only A''s own row, never B''s');

select is(
  ((pg_temp.snap('a_result') -> 'notification_preferences') -> 0 ->> 'missed_entry_days')::int,
  2,
  'A: the one notification_preferences row is A''s own (missed_entry_days = 2, not B''s 1)'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'push_devices'), 1::bigint,
  'A: push_devices includes only A''s own device');

select is(
  (pg_temp.snap('a_result') -> 'push_devices') -> 0 ->> 'token_last4',
  '1111',
  'A: push_devices token is redacted to its last 4 characters'
);

select ok(
  not (((pg_temp.snap('a_result') -> 'push_devices') -> 0) ? 'token'),
  'A: push_devices never carries the raw token field'
);

select ok(
  position('token-family-a-AAAA1111' in pg_temp.snap('a_result')::text) = 0,
  'A: the raw pre-redaction fixture token string is absent from the document text, only its last 4 characters survive'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'missed_entry_alert_state'), 1::bigint,
  'A: missed_entry_alert_state includes only A''s own marker, never B''s');

select is(
  ((pg_temp.snap('a_result') -> 'missed_entry_alert_state') -> 0 ->> 'profile_id'),
  tests.ulid(1),
  'A: the one missed_entry_alert_state row is on the owned profile'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'feedback_tickets'), 1::bigint,
  'A: feedback_tickets includes A''s own ticket');

select is(
  jsonb_array_length(((pg_temp.snap('a_result') -> 'feedback_tickets') -> 0 -> 'replies')),
  2,
  'A: the ticket carries both the admin reply and A''s own follow-up reply'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'profile_reminder_windows'), 1::bigint,
  'A: profile_reminder_windows includes the owned profile''s published window');

select is(
  ((pg_temp.snap('a_result') -> 'profile_reminder_windows') -> 0 ->> 'profile_id'),
  tests.ulid(1),
  'A: the one profile_reminder_windows row is on the owned profile'
);

select is(pg_temp.count_in(pg_temp.snap('a_result'), 'ownership_transfers'), 1::bigint,
  'A: ownership_transfers includes the transfer A initiated');

select is(
  ((pg_temp.snap('a_result') -> 'ownership_transfers') -> 0 ->> 'profile_id'),
  tests.ulid(1),
  'A: the one ownership_transfers row is on the profile A initiated a transfer for'
);

select ok(
  position(tests.get_supabase_uid('user_c')::text in pg_temp.snap('a_result')::text) = 0,
  'A: export contains none of family C''s owner id anywhere'
);

select ok(
  position(tests.get_supabase_uid('user_d')::text in pg_temp.snap('a_result')::text) = 0,
  'A: export contains none of family C''s caregiver id anywhere'
);

select ok(
  position(tests.ulid(2) in pg_temp.snap('a_result')::text) = 0,
  'A: export contains none of family C''s profile id anywhere'
);

select ok(
  not jsonb_path_exists(pg_temp.snap('a_result'), '$.**.token_hash'),
  'A: no token_hash anywhere in the export document'
);

-- Deterministic ordering: a second call against unchanged data, in the same
-- transaction (so `now()` - and thus exported_at - is identical), produces
-- a byte-identical jsonb document.
select pg_temp.snapshot('a_result2', public.export_account_data());
select is(
  pg_temp.snap('a_result'),
  pg_temp.snap('a_result2'),
  'A: two calls against unchanged data produce identical jsonb (deterministic key/array ordering)'
);

-- ---------------------------------------------------------------------------
-- 5. B's export (co_parent, shared profile): scoped to B's own memberships,
--    preferences, and self-authored entries only - never A's.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_b');
select pg_temp.snapshot('b_result', public.export_account_data());

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'profiles'), 1::bigint,
  'B: exactly one profile (the shared one)');

select is(
  pg_temp.profile_by_id(pg_temp.snap('b_result'), tests.ulid(1)) ->> 'owned',
  'false',
  'B: the shared profile is marked owned = false'
);

select is(
  pg_temp.day_entry_ids(pg_temp.profile_by_id(pg_temp.snap('b_result'), tests.ulid(1))),
  array[tests.ulid(11)],
  'B: shared profile carries only the entry B personally authored, never A''s'
);

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'profile_guardians'), 1::bigint,
  'B: profile_guardians on the shared profile is scoped to B''s own row only');

select is(
  pg_temp.guardian_user_ids_for(pg_temp.snap('b_result'), tests.ulid(1)),
  array[tests.get_supabase_uid('user_b')],
  'B: the one profile_guardians row is B''s own, never A''s'
);

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'guardian_invitations'), 1::bigint,
  'B: guardian_invitations on the shared profile is scoped to invitations B personally created');

select is(
  pg_temp.invitation_inviters_for(pg_temp.snap('b_result'), tests.ulid(1)),
  array[tests.get_supabase_uid('user_b')],
  'B: the one guardian_invitations row was invited_by B, never A''s invitation'
);

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'notification_preferences'), 1::bigint,
  'B: notification_preferences includes only B''s own row, never A''s');

select is(
  ((pg_temp.snap('b_result') -> 'notification_preferences') -> 0 ->> 'missed_entry_days')::int,
  1,
  'B: the one notification_preferences row is B''s own (missed_entry_days = 1, not A''s 2)'
);

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'push_devices'), 1::bigint,
  'B: push_devices includes only B''s own device');

select is(
  (pg_temp.snap('b_result') -> 'push_devices') -> 0 ->> 'token_last4',
  '2222',
  'B: push_devices token is B''s own, redacted to its last 4 characters'
);

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'profile_reminder_windows'), 0::bigint,
  'B: profile_reminder_windows is empty (B does not own the shared profile)');

select is(pg_temp.count_in(pg_temp.snap('b_result'), 'ownership_transfers'), 0::bigint,
  'B: ownership_transfers is empty (B neither initiated nor accepted a transfer)');

select ok(
  not jsonb_path_exists(pg_temp.snap('b_result'), '$.**.token_hash'),
  'B: no token_hash anywhere in the export document'
);

select ok(
  position(tests.get_supabase_uid('user_c')::text in pg_temp.snap('b_result')::text) = 0,
  'B: export contains none of family C''s owner id anywhere'
);

select ok(
  position(tests.get_supabase_uid('user_d')::text in pg_temp.snap('b_result')::text) = 0,
  'B: export contains none of family C''s caregiver id anywhere'
);

select ok(
  position(tests.ulid(2) in pg_temp.snap('b_result')::text) = 0,
  'B: export contains none of family C''s profile id anywhere'
);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 6. Cross-family fixture: E owns an unrelated profile (family E) and is
--    also an accepted caregiver on C's shared profile - the caller's
--    scoping must be decided per profile, never smeared across every
--    profile the caller touches in a different role.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_c');
select public.create_guardian_invitation(
  tests.ulid(2), 'caregiver', 'E',
  'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0', 48
);

select tests.authenticate_as('user_e');
select public.accept_guardian_invitation(
  'f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0', 'E'
);

insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(3), 'Riley E', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- E's own caregiver-authored entry on C's shared profile - must survive
-- scoping alongside C's and D's entries (ulid(20)), which must not.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(21), tests.ulid(2), '2026-09-03', 'UTC', 'spotting', '2026-09-03T00:00:00Z',
        tests.get_supabase_uid('user_e'), tests.get_supabase_uid('user_e'));

-- E's own entry on E's own owned profile.
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id, last_modified_by_user_id)
values (tests.ulid(30), tests.ulid(3), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z',
        tests.get_supabase_uid('user_e'), tests.get_supabase_uid('user_e'));

-- Distinct value from both C's (3) and D's (3) rows on the same profile so
-- "whose row is this" stays provable by content.
insert into public.notification_preferences (user_id, profile_id, alert_on_log, missed_entry_days)
values (tests.get_supabase_uid('user_e'), tests.ulid(2), true, 1);

select tests.clear_authentication();

-- ---------------------------------------------------------------------------
-- 7. E's export (caregiver on C, owner of an unrelated profile): proves
--    per-profile scoping, not per-caller scoping - C's other rows never
--    leak in just because E also owns a profile elsewhere.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('user_e');
select pg_temp.snapshot('e_result', public.export_account_data());

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'profiles'), 2::bigint,
  'E: two profiles - E''s own, plus the shared one E caregives on');

select is(
  pg_temp.profile_by_id(pg_temp.snap('e_result'), tests.ulid(2)) ->> 'owned',
  'false',
  'E: C''s shared profile is marked owned = false'
);

select is(
  pg_temp.profile_by_id(pg_temp.snap('e_result'), tests.ulid(3)) ->> 'owned',
  'true',
  'E: E''s own profile is marked owned = true'
);

select is(
  pg_temp.day_entry_ids(pg_temp.profile_by_id(pg_temp.snap('e_result'), tests.ulid(2))),
  array[tests.ulid(21)],
  'E: on C''s shared profile, only E''s own caregiver-authored entry is present - never C''s or D''s'
);

select is(
  pg_temp.day_entry_ids(pg_temp.profile_by_id(pg_temp.snap('e_result'), tests.ulid(3))),
  array[tests.ulid(30)],
  'E: E''s own owned profile carries E''s entry'
);

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'notification_preferences'), 1::bigint,
  'E: notification_preferences includes only E''s own row on C''s profile, never C''s or D''s');

select is(
  ((pg_temp.snap('e_result') -> 'notification_preferences') -> 0 ->> 'missed_entry_days')::int,
  1,
  'E: the one notification_preferences row is E''s own (missed_entry_days = 1, not C''s or D''s 3)'
);

-- profile_guardians carries two rows for E: the auto-created primary_guardian
-- row on E's own profile (owned -> full membership list, which for a
-- brand-new profile is just E) and E's own caregiver row on C's shared
-- profile - never C''s or D's row on that shared profile.
select is(pg_temp.count_in(pg_temp.snap('e_result'), 'profile_guardians'), 2::bigint,
  'E: profile_guardians has E''s own row on each of E''s two profiles, never a row belonging to C or D');

select is(
  pg_temp.guardian_user_ids_for(pg_temp.snap('e_result'), tests.ulid(2)),
  array[tests.get_supabase_uid('user_e')],
  'E: on C''s shared profile, profile_guardians names only E, never C or D'
);

select is(
  pg_temp.guardian_user_ids_for(pg_temp.snap('e_result'), tests.ulid(3)),
  array[tests.get_supabase_uid('user_e')],
  'E: on E''s own profile, profile_guardians names only E'
);

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'guardian_invitations'), 0::bigint,
  'E: guardian_invitations is empty - E accepted an invitation but never personally created one');

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'ownership_transfers'), 0::bigint,
  'E: ownership_transfers is empty - C''s transfer is neither initiated nor accepted by E');

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'push_devices'), 0::bigint,
  'E: push_devices is empty - E registered no device');

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'feedback_tickets'), 0::bigint,
  'E: feedback_tickets is empty');

select is(pg_temp.count_in(pg_temp.snap('e_result'), 'profile_reminder_windows'), 0::bigint,
  'E: profile_reminder_windows is empty - no window was ever published for E''s owned profile, and C''s window is not E''s to carry');

select ok(
  position(tests.get_supabase_uid('user_c')::text in pg_temp.snap('e_result')::text) = 0,
  'E: export contains none of family C''s owner id anywhere'
);

select ok(
  position(tests.get_supabase_uid('user_d')::text in pg_temp.snap('e_result')::text) = 0,
  'E: export contains none of family C''s other caregiver (D) id anywhere'
);

select ok(
  not jsonb_path_exists(pg_temp.snap('e_result'), '$.**.token_hash'),
  'E: no token_hash anywhere in the export document'
);

select tests.clear_authentication();

select * from finish();
rollback;
