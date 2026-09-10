-- Regression coverage for public.delete_profile_data() (Issue #264): the
-- hard purge of a single profile, as distinct from
-- public.delete_account_data()'s whole-account wipe. Mirrors
-- account_deletion_test.sql's style: the create_supabase_user /
-- authenticate_as handshake, the pg_temp snap idiom for before/after
-- byte-comparisons, and service_role for the no-grant tables
-- (notification_outbox, missed_entry_alert_state, ownership_transfers,
-- prediction_connections, prediction_projections).
--
-- Groups:
--   A. Function shape: security definer, search_path = '', grants, and the
--      RLS-never-weakened checks (no new table DELETE grants anywhere).
--   B. No-JWT refusals.
--   C. Authority matrix: accepted primary_guardian only; every other rung
--      (co_parent, caregiver, viewer, invited-but-not-accepted, revoked,
--      outsider, nonexistent profile) raises the identical
--      enumeration-safe error and deletes nothing.
--   D. Full purge: every landed per-profile table emptied, per-table counts
--      returned in the delete_account_data() shape, the co-guardian's own
--      entries on the purged profile gone WITH it (deliberate, explicit),
--      and the co-guardian's / an outsider family's data on OTHER profiles
--      byte-identical. Not idempotent: a second call raises.
--   E. p_source variant: exact-match per-table scope (Issue #159
--      provenance), authority-checked and source-validated, profile and
--      guardians surviving, full purge still available afterwards.

begin;
select plan(71);

create temp table snap (name text primary key, v jsonb);
grant all on table snap to authenticated, service_role;

create function pg_temp.snapshot(n text, v jsonb) returns void language sql as
  $$ insert into snap values (n, v) on conflict (name) do update set v = excluded.v $$;
create function pg_temp.snap(n text) returns jsonb language sql as
  $$ select v from snap where name = n $$;

-- The exact enumeration-safe authority error every refusal below asserts.
-- Keeping it in one place makes an intentional message change a one-line
-- edit rather than a dozen.
create function pg_temp.auth_err() returns text language sql immutable as
  $$ select 'profile not found or caller is not its accepted primary_guardian' $$;

select tests.create_supabase_user('a'); -- accepted primary_guardian of profile 1 and 4
select tests.create_supabase_user('b'); -- co_parent on profile 1; primary of own profile 3
select tests.create_supabase_user('c'); -- caregiver on profile 1
select tests.create_supabase_user('d'); -- viewer on profile 1 (revoked in group C)
select tests.create_supabase_user('e'); -- outsider: primary of profile 2 only
select tests.create_supabase_user('f'); -- invited to profile 1, never accepts
select tests.create_supabase_user('g'); -- primary of profile 5 (p_source group)
select tests.create_supabase_user('h'); -- co_parent on profile 5

-- ---------------------------------------------------------------------------
-- A. Function shape, grants, and RLS-never-weakened.
-- ---------------------------------------------------------------------------

select ok(
  exists (
    select 1 from pg_proc
     where proname = 'delete_profile_data'
       and pronamespace = 'public'::regnamespace
  ),
  'public.delete_profile_data(text, text) exists'
);

select is(
  (select prosecdef from pg_proc
    where proname = 'delete_profile_data' and pronamespace = 'public'::regnamespace),
  true,
  'delete_profile_data is security definer'
);

select ok(
  exists (
    select 1 from pg_proc, unnest(proconfig) as c(setting)
     where proname = 'delete_profile_data' and pronamespace = 'public'::regnamespace
       and c.setting like 'search_path=%'
  ),
  'delete_profile_data sets search_path = '''''
);

select ok(
  has_function_privilege('authenticated', 'public.delete_profile_data(text, text)', 'execute'),
  'authenticated can execute delete_profile_data'
);

select is(
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
    where n.nspname = 'public' and p.proname = 'delete_profile_data'
      and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint,
  'PUBLIC and anon hold no EXECUTE on delete_profile_data'
);

select ok(
  not has_function_privilege('anon', 'public.delete_profile_data(text, text)', 'execute'),
  'anon cannot execute delete_profile_data'
);

-- RLS never weakened: the RPC is the ONLY delete path, so no client-facing
-- role may gain a table DELETE grant anywhere in the purge scope.
select ok(
  not has_table_privilege('authenticated', 'public.profiles', 'delete'),
  'authenticated still has no DELETE grant on profiles'
);
select ok(
  not has_table_privilege('authenticated', 'public.day_entries', 'delete'),
  'authenticated still has no DELETE grant on day_entries'
);
select ok(
  not has_table_privilege('authenticated', 'public.observations', 'delete'),
  'authenticated still has no DELETE grant on observations'
);
select ok(
  not has_table_privilege('authenticated', 'public.care_notes', 'delete'),
  'authenticated still has no DELETE grant on care_notes'
);
select ok(
  not has_table_privilege('authenticated', 'public.visit_prep_items', 'delete'),
  'authenticated still has no DELETE grant on visit_prep_items'
);
select ok(
  not has_table_privilege('authenticated', 'public.profile_guardians', 'delete'),
  'authenticated still has no DELETE grant on profile_guardians'
);
select ok(
  not has_table_privilege('authenticated', 'public.profile_modes', 'delete'),
  'authenticated still has no DELETE grant on profile_modes'
);
select ok(
  not has_table_privilege('authenticated', 'public.cycle_overrides', 'delete'),
  'authenticated still has no DELETE grant on cycle_overrides'
);

-- ---------------------------------------------------------------------------
-- B. No JWT: anon is refused by the grant; an authenticated role with no
--    claims is refused by the function's own auth.uid() check.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select tests.authenticate_as_anon();
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', null,
  'anon cannot execute delete_profile_data'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'authenticated', true);
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', null,
  'an authenticated role with no JWT claims is refused (auth.uid() is null)'
);

select tests.clear_authentication();
select is(
  (select count(*) from public.profiles where id = tests.ulid(1)),
  1::bigint,
  'neither unauthenticated attempt deleted anything'
);

-- ---------------------------------------------------------------------------
-- C. Authority matrix. Fixtures: a invites b (co_parent), c (caregiver),
--    d (viewer) - all accept; f (caregiver) never accepts. Every refusal
--    raises the IDENTICAL message (nonexistent profile and unauthorized
--    caller are indistinguishable) and deletes nothing.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('a');
select public.create_guardian_invitation(tests.ulid(1), 'co_parent', 'B', repeat('b1', 32), 48);
select public.create_guardian_invitation(tests.ulid(1), 'caregiver', 'C', repeat('c1', 32), 48);
select public.create_guardian_invitation(tests.ulid(1), 'viewer', 'D', repeat('d1', 32), 48);
select public.create_guardian_invitation(tests.ulid(1), 'caregiver', 'F', repeat('f1', 32), 48);

select tests.authenticate_as('b');
select public.accept_guardian_invitation(repeat('b1', 32), 'B');
select tests.authenticate_as('c');
select public.accept_guardian_invitation(repeat('c1', 32), 'C');
select tests.authenticate_as('d');
select public.accept_guardian_invitation(repeat('d1', 32), 'D');

select tests.authenticate_as('b');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: an accepted co_parent is refused'
);

select tests.authenticate_as('c');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: an accepted caregiver is refused'
);

select tests.authenticate_as('d');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: an accepted viewer is refused'
);

select tests.authenticate_as('e');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: an authenticated non-guardian is refused'
);

select tests.authenticate_as('f');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: an invited-but-not-accepted caller (no membership row) is refused'
);

select tests.authenticate_as('a');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(999))$$,
  '42501', pg_temp.auth_err(),
  'C: a nonexistent profile raises the identical enumeration-safe error'
);

select is(
  (select count(*) from public.profiles where id = tests.ulid(1)),
  1::bigint,
  'C: every failed authority attempt left the profile in place'
);

-- A revoked membership is no authority either (revoke_guardian stamps the
-- row revoked; the accepted-only role lookup sees neither role nor row).
select public.revoke_guardian(tests.ulid(1), tests.get_supabase_uid('d'));
select tests.authenticate_as('d');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'C: a revoked ex-viewer is refused'
);

-- ---------------------------------------------------------------------------
-- D. Full purge. Fixture order matters: every day_entries/observations
--    insert happens BEFORE the notification_preferences inserts (alerts
--    default off), so the enqueue triggers fire nothing and the two
--    service_role outbox rows below are the only outbox rows in play.
-- ---------------------------------------------------------------------------

-- The purged profile's own content (a's entries) plus a second entry logged
-- by co-guardian b - the deliberate "co-guardian's own entries die with the
-- profile" case the issue calls out.
select tests.authenticate_as('a');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values
  (tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z'),
  (tests.ulid(12), tests.ulid(1), '2026-09-03', 'UTC', 'none', '2026-09-03T00:00:00Z');

select tests.authenticate_as('b');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(11), tests.ulid(1), '2026-09-02', 'UTC', 'medium', '2026-09-02T00:00:00Z');

-- a's OTHER profile, b's OWN profile, and e's own profile: all must survive
-- a's purge of profile 1 untouched.
select tests.authenticate_as('a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(4), 'Second', false, 1, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(41), tests.ulid(4), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z');

select tests.authenticate_as('b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(3), 'B own', false, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(31), tests.ulid(3), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z');

select tests.authenticate_as('e');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2), 'Bailey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(21), tests.ulid(2), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z');
insert into public.settings (user_id, key, value)
values (tests.get_supabase_uid('e'), 'e-key', 'e-value');

select tests.authenticate_as('a');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, source, updated_at)
values
  (tests.ulid(100), tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'other', 'manual', '2026-09-01T00:00:00Z'),
  (tests.ulid(101), tests.ulid(11), tests.ulid(1), '2026-09-02', 'UTC', 'other', 'apple_health', '2026-09-02T00:00:00Z');

-- The #188 mode row and cycle override, the #128 care note (logged by the
-- caregiver - their content dies too) and visit-prep item.
insert into public.profile_modes (profile_id, updated_at)
values (tests.ulid(1), '2026-09-01T00:00:00Z');
insert into public.cycle_overrides (id, profile_id, cycle_start_date, updated_at)
values (tests.ulid(110), tests.ulid(1), '2026-09-01', '2026-09-01T00:00:00Z');

select tests.authenticate_as('c');
insert into public.care_notes (id, profile_id, body, updated_at)
values (tests.ulid(111), tests.ulid(1), 'Note from caregiver', '2026-09-01T00:00:00Z');

select tests.authenticate_as('a');
insert into public.visit_prep_items (id, profile_id, body, updated_at)
values (tests.ulid(112), tests.ulid(1), 'Bring chart', '2026-09-01T00:00:00Z');

-- Issue #167 import job (audit row only).
insert into public.import_jobs (profile_id, source, total_rows, created_by)
values (tests.ulid(1), 'clue_import', 3, tests.get_supabase_uid('a'));

-- Per-user tables survive a profile purge by design - fixtures for the
-- survival asserts below.
insert into public.settings (user_id, key, value)
values (tests.get_supabase_uid('a'), 'a-key', 'a-value');
select tests.authenticate_as('b');
insert into public.push_devices (id, user_id, token, platform)
values ('00000000-0000-0000-0000-000000000951'::uuid, tests.get_supabase_uid('b'), 'token-b-1', 'ios');

-- Alert fixtures, now that no more entry inserts are coming.
select tests.authenticate_as('a');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('a'), tests.ulid(1), true);
select tests.authenticate_as('b');
insert into public.notification_preferences (user_id, profile_id, alert_on_log)
values (tests.get_supabase_uid('b'), tests.ulid(1), true);

select tests.authenticate_as('a');
select public.upsert_reminder_window(tests.ulid(1), '2026-09-12', false);

-- No-grant tables (notification_outbox, missed_entry_alert_state,
-- ownership_transfers, prediction_*): fixture as service_role.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
insert into public.missed_entry_alert_state (profile_id, user_id, last_enqueued_for)
values
  (tests.ulid(1), tests.get_supabase_uid('a'), '2026-09-05'),
  (tests.ulid(1), tests.get_supabase_uid('b'), '2026-09-06');
insert into public.notification_outbox (profile_id, recipient_user_id, kind)
values
  (tests.ulid(1), tests.get_supabase_uid('a'), 'logged'),
  (tests.ulid(1), tests.get_supabase_uid('b'), 'logged');
insert into public.ownership_transfers
  (profile_id, initiated_by, token_hash, parent_post_transfer_role, expires_at)
values
  (tests.ulid(1), tests.get_supabase_uid('a'), repeat('aa', 32), 'viewer', now() + interval '24 hours');
insert into public.prediction_connections
  (profile_id, owner_user_id, token_hash, expires_at)
values
  (tests.ulid(1), tests.get_supabase_uid('a'), repeat('bb', 32), now() + interval '24 hours');
insert into public.prediction_projections (profile_id, projection, published_by)
values
  (tests.ulid(1), '{"generated_at":"2026-09-10"}', tests.get_supabase_uid('a'));

-- Fixture sanity: the profile's sync_signals row exists (every insert above
-- rode touch_sync_signal), and the entry count is what the purge should
-- report.
select is(
  (select count(*) from public.sync_signals where profile_id = tests.ulid(1)),
  1::bigint,
  'D: fixture has the profile''s single sync_signals row'
);
select is(
  (select count(*) from public.day_entries where profile_id = tests.ulid(1)),
  3::bigint,
  'D: fixture has three day_entries on profile 1 (two a''s, one b''s)'
);

-- Before-snapshots of the data that must survive, read as service_role so
-- RLS visibility (b and e can both still see their own rows) cannot
-- masquerade as survival.
select pg_temp.snapshot('b_own_before', jsonb_build_object(
  'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p where p.id = tests.ulid(3)),
  'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d where d.id = tests.ulid(31)),
  'push_devices', (select jsonb_agg(to_jsonb(pd) order by pd.id) from public.push_devices pd
                    where pd.user_id = tests.get_supabase_uid('b'))
));
select pg_temp.snapshot('e_own_before', jsonb_build_object(
  'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p where p.id = tests.ulid(2)),
  'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d where d.id = tests.ulid(21)),
  'settings', (select jsonb_agg(to_jsonb(s) order by s.key) from public.settings s
                where s.user_id = tests.get_supabase_uid('e'))
));

-- The purge itself: one-arg call, proving the p_source default resolves.
select tests.authenticate_as('a');
select pg_temp.snapshot('purge_result', public.delete_profile_data(tests.ulid(1)));

select is(
  pg_temp.snap('purge_result'),
  jsonb_build_object(
    'day_entries', 3,
    'observations', 2,
    'profile_modes', 1,
    'cycle_overrides', 1,
    'care_notes', 1,
    'visit_prep_items', 1,
    'profile_reminder_windows', 1,
    'missed_entry_alert_state', 2,
    'notification_preferences', 2,
    'notification_outbox', 2,
    'guardian_invitations', 4,
    'profile_guardians', 4,
    'import_jobs', 1,
    'ownership_transfers', 1,
    'prediction_connections', 1,
    'prediction_projections', 1,
    'sync_signals', 1,
    'profiles', 1
  ),
  'D: returned jsonb carries the exact per-table counts (delete_account_data shape)'
);

-- Post-purge reads as service_role: a purged row that RLS merely hides would
-- be indistinguishable from a surviving one under an authenticated role that
-- just lost its guardian rows.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is((select count(*) from public.profiles where id = tests.ulid(1)), 0::bigint,
  'D: the profile row itself is gone');
select is((select count(*) from public.day_entries where profile_id = tests.ulid(1)), 0::bigint,
  'D: zero day_entries remain on the purged profile');
select is((select count(*) from public.day_entries where id = tests.ulid(11)), 0::bigint,
  'D: the co-guardian''s OWN entry on the purged profile is gone with it (deliberate)');
select is((select count(*) from public.observations where profile_id = tests.ulid(1)), 0::bigint,
  'D: zero observations remain (both, across sources)');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(1)), 0::bigint,
  'D: the #188 mode row is gone');
select is((select count(*) from public.cycle_overrides where profile_id = tests.ulid(1)), 0::bigint,
  'D: the #188 cycle override is gone');
select is((select count(*) from public.care_notes where profile_id = tests.ulid(1)), 0::bigint,
  'D: the #128 care note is gone (caregiver-authored content included)');
select is((select count(*) from public.visit_prep_items where profile_id = tests.ulid(1)), 0::bigint,
  'D: the #128 visit-prep item is gone');
select is((select count(*) from public.profile_reminder_windows where profile_id = tests.ulid(1)), 0::bigint,
  'D: the reminder window is gone');
select is((select count(*) from public.missed_entry_alert_state where profile_id = tests.ulid(1)), 0::bigint,
  'D: BOTH guardians'' missed-entry markers are gone');
select is((select count(*) from public.notification_preferences where profile_id = tests.ulid(1)), 0::bigint,
  'D: BOTH guardians'' notification preferences are gone');
select is((select count(*) from public.notification_outbox where profile_id = tests.ulid(1)), 0::bigint,
  'D: BOTH pending outbox rows are gone');
select is((select count(*) from public.guardian_invitations where profile_id = tests.ulid(1)), 0::bigint,
  'D: every invitation row for the profile is gone (accepted and outstanding alike)');
select is((select count(*) from public.profile_guardians where profile_id = tests.ulid(1)), 0::bigint,
  'D: ALL FOUR guardian memberships are gone (primary, co_parent, caregiver, revoked viewer)');
select is((select count(*) from public.import_jobs where profile_id = tests.ulid(1)), 0::bigint,
  'D: the import job is gone');
select is((select count(*) from public.ownership_transfers where profile_id = tests.ulid(1)), 0::bigint,
  'D: the ownership transfer is gone');
select is((select count(*) from public.prediction_connections where profile_id = tests.ulid(1)), 0::bigint,
  'D: the prediction connection is gone');
select is((select count(*) from public.prediction_projections where profile_id = tests.ulid(1)), 0::bigint,
  'D: the prediction projection is gone');
select is((select count(*) from public.sync_signals where profile_id = tests.ulid(1)), 0::bigint,
  'D: the profile''s sync_signals row is gone (touch_sync_signal existence check)');

select is(
  jsonb_build_object(
    'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p where p.id = tests.ulid(3)),
    'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d where d.id = tests.ulid(31)),
    'push_devices', (select jsonb_agg(to_jsonb(pd) order by pd.id) from public.push_devices pd
                      where pd.user_id = tests.get_supabase_uid('b'))
  ),
  pg_temp.snap('b_own_before'),
  'D: co-guardian b''s OWN profile, entry, and push device are byte-identical'
);
select is(
  jsonb_build_object(
    'profiles', (select jsonb_agg(to_jsonb(p) order by p.id) from public.profiles p where p.id = tests.ulid(2)),
    'day_entries', (select jsonb_agg(to_jsonb(d) order by d.id) from public.day_entries d where d.id = tests.ulid(21)),
    'settings', (select jsonb_agg(to_jsonb(s) order by s.key) from public.settings s
                  where s.user_id = tests.get_supabase_uid('e'))
  ),
  pg_temp.snap('e_own_before'),
  'D: outsider e''s profile, entry, and settings are byte-identical'
);
select is((select count(*) from public.day_entries where profile_id = tests.ulid(4)), 1::bigint,
  'D: the caller''s OTHER profile keeps its entry');
select is(
  (select count(*) from public.settings where user_id = tests.get_supabase_uid('a')),
  1::bigint,
  'D: the caller''s per-user settings survive a profile purge'
);

-- Not idempotent: the profile (and with it the caller's accepted
-- primary_guardian membership) is gone, so a retry raises rather than
-- reporting zeros.
select tests.authenticate_as('a');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(1))$$,
  '42501', pg_temp.auth_err(),
  'D: a second call on a purged profile raises (not idempotent, unlike delete_account_data)'
);

-- ---------------------------------------------------------------------------
-- E. p_source variant (Issue #159 provenance): exact-match scope per table;
--    profile, guardians, and every other-source row survive.
-- ---------------------------------------------------------------------------

select tests.authenticate_as('g');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(5), 'Sam', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, source)
values
  (tests.ulid(51), tests.ulid(5), '2026-09-01', 'UTC', 'light', '2026-09-01T00:00:00Z', 'healthkit'),
  (tests.ulid(52), tests.ulid(5), '2026-09-02', 'UTC', 'medium', '2026-09-02T00:00:00Z', 'healthkit'),
  (tests.ulid(53), tests.ulid(5), '2026-09-03', 'UTC', 'none', '2026-09-03T00:00:00Z', 'manual'),
  (tests.ulid(54), tests.ulid(5), '2026-09-04', 'UTC', 'spotting', '2026-09-04T00:00:00Z', 'clue_import');
insert into public.import_jobs (profile_id, source, total_rows, created_by)
values
  (tests.ulid(5), 'healthkit', 2, tests.get_supabase_uid('g')),
  (tests.ulid(5), 'clue_import', 1, tests.get_supabase_uid('g'));
insert into public.profile_modes (profile_id, updated_at)
values (tests.ulid(5), '2026-09-01T00:00:00Z');
insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, source, updated_at)
values
  -- observations.source has no 'healthkit' (its vocabulary is
  -- apple_health/health_connect/wearable/...), so an Apple-Health-imported
  -- observation rides a healthkit day_entry under 'apple_health'.
  (tests.ulid(510), tests.ulid(51), tests.ulid(5), '2026-09-01', 'UTC', 'other', 'apple_health', '2026-09-01T00:00:00Z'),
  (tests.ulid(511), tests.ulid(53), tests.ulid(5), '2026-09-03', 'UTC', 'other', 'manual', '2026-09-03T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(5), 'co_parent', 'H', repeat('e1', 32), 48);
select tests.authenticate_as('h');
select public.accept_guardian_invitation(repeat('e1', 32), 'H');

-- Authority applies to the source variant too.
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(5), 'healthkit')$$,
  '42501', pg_temp.auth_err(),
  'E: the co_parent is refused on the source variant as well'
);

-- Source validation: a typo raises invalid_parameter_value and touches
-- nothing - it must not silently delete zero rows while looking successful.
select tests.authenticate_as('g');
select throws_ok(
  $$select public.delete_profile_data(tests.ulid(5), 'nope')$$,
  '22023', null,
  'E: an unknown source raises invalid_parameter_value'
);
select is((select count(*) from public.day_entries where profile_id = tests.ulid(5)), 4::bigint,
  'E: the failed source call deleted nothing');

-- A valid source with no rows on the profile: an honest all-zero result.
select is(
  public.delete_profile_data(tests.ulid(5), 'wearable'),
  jsonb_build_object('source', 'wearable', 'day_entries', 0, 'observations', 0, 'import_jobs', 0),
  'E: a valid but unmatched source reports all-zero counts'
);
select is((select count(*) from public.day_entries where profile_id = tests.ulid(5)), 4::bigint,
  'E: the zero-count call deleted nothing');

select tests.authenticate_as('g');
select pg_temp.snapshot('source_result', public.delete_profile_data(tests.ulid(5), 'healthkit'));
select tests.clear_authentication();

select is(
  pg_temp.snap('source_result'),
  jsonb_build_object('source', 'healthkit', 'day_entries', 2, 'observations', 0, 'import_jobs', 1),
  'E: healthkit purge counts: two entries, one import job, zero DIRECT observations '
  '(the apple_health observation dies via the day_entries cascade, not this filter)'
);

select is((select count(*) from public.day_entries where profile_id = tests.ulid(5)), 2::bigint,
  'E: only the two healthkit day_entries are gone');
select is(
  (select count(*) from public.day_entries
    where profile_id = tests.ulid(5) and source = 'manual'),
  1::bigint,
  'E: the manually-logged entry survives'
);
select is(
  (select count(*) from public.day_entries
    where profile_id = tests.ulid(5) and source = 'clue_import'),
  1::bigint,
  'E: the other-source (clue_import) entry survives'
);
select is((select count(*) from public.observations where profile_id = tests.ulid(5)), 1::bigint,
  'E: the apple_health observation on a deleted healthkit entry cascaded away');
select is(
  (select count(*) from public.observations
    where profile_id = tests.ulid(5) and source = 'manual'),
  1::bigint,
  'E: the manual observation on the surviving entry survives'
);
select is((select count(*) from public.import_jobs where profile_id = tests.ulid(5)), 1::bigint,
  'E: only the healthkit import job is gone');
select is(
  (select count(*) from public.import_jobs
    where profile_id = tests.ulid(5) and source = 'clue_import'),
  1::bigint,
  'E: the clue_import job row survives'
);
select is((select count(*) from public.profiles where id = tests.ulid(5)), 1::bigint,
  'E: the profile itself survives a source-scoped purge');
select is((select count(*) from public.profile_guardians where profile_id = tests.ulid(5)), 2::bigint,
  'E: both guardian memberships survive a source-scoped purge');
select is((select count(*) from public.profile_modes where profile_id = tests.ulid(5)), 1::bigint,
  'E: the mode row survives a source-scoped purge');

-- The full purge is still available afterwards.
select tests.authenticate_as('g');
select pg_temp.snapshot('after_source_full_result', public.delete_profile_data(tests.ulid(5)));
select is(pg_temp.snap('after_source_full_result') -> 'day_entries', '2'::jsonb,
  'E: a full purge after a source purge removes the surviving entries');
select is(pg_temp.snap('after_source_full_result') -> 'profiles', '1'::jsonb,
  'E: the full purge after a source purge removes the profile row');
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);
select is((select count(*) from public.profiles where id = tests.ulid(5)), 0::bigint,
  'E: profile 5 is fully gone after the follow-up full purge');

select tests.clear_authentication();

select * from finish();
rollback;
