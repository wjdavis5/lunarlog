-- Coverage for Issue #567: the four attribution guards - enforce_day_entry_attribution,
-- enforce_observation_attribution, enforce_care_note_attribution, and
-- enforce_prep_item_attribution - are structurally identical (each one a
-- copy of the first, per that migration's own history) but only
-- enforce_day_entry_attribution had behavioural tests before this file.
-- Exercises each one directly via a RAW insert/update (not through
-- sync_push, which never forges attribution in the first place), since
-- that raw path is exactly what a would-be forger would use, and it is
-- the only thing that actually calls these trigger functions' code.
--
-- Each guard, symmetrically:
--   INSERT: forging logged_by_user_id or last_modified_by_user_id to
--     someone other than the caller is refused; leaving either null, or
--     setting either to the caller's own uid, is allowed.
--   UPDATE: changing logged_by_user_id at all is refused as 42501 -
--     structurally, at the GRANT layer (authenticated holds no UPDATE
--     grant on this column at all - it is insert-only by design, per each
--     table's own migration comment), with the trigger's own
--     "logged_by_user_id is server-authoritative" branch as unreachable-
--     from-a-raw-client defense in depth (only a SECURITY DEFINER caller
--     with the column grant could ever reach it). last_modified_by_user_id
--     DOES carry an UPDATE grant and must equal the caller exactly on
--     every update - that check is the trigger's own, live enforcement.
--   A null auth.uid() (migrations, service role) is exempt from both.
begin;
select plan(24);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('eve');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- 1. enforce_day_entry_attribution (the original guard - included for
--    symmetry with the other three, which mirror it exactly). Issue #201
--    revoked authenticated's insert/update grant on day_entries entirely,
--    so this whole section runs as service_role instead (auth.uid() is
--    untouched -- it reads request.jwt.claims, a separate session GUC
--    from role) to actually reach enforce_day_entry_attribution's own
--    checks/messages, exactly as this file's header describes: the point
--    is exercising the trigger via a raw write, not the grant itself
--    (that is sync_push_sole_write_path_test.sql's job).
-- ---------------------------------------------------------------------------
select set_config('role', 'service_role', true);
insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at)
values (tests.ulid(10), tests.ulid(1), '2026-09-01', 'UTC', 'none', '2026-09-01T00:00:00Z');
select throws_ok(
  format($$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id)
           values (%L, %L, '2026-09-02', 'UTC', 'none', now(), %L)$$,
    tests.ulid(11), tests.ulid(1), tests.get_supabase_uid('eve')),
  '42501', 'attribution columns are server-authoritative',
  'day_entries INSERT: forging logged_by_user_id to another user is refused'
);
select lives_ok(
  format($$insert into public.day_entries (id, profile_id, local_date, tz, flow, updated_at, logged_by_user_id)
           values (%L, %L, '2026-09-02', 'UTC', 'none', now(), %L)$$,
    tests.ulid(11), tests.ulid(1), tests.get_supabase_uid('mom')),
  'day_entries INSERT: setting logged_by_user_id to the caller''s own uid is allowed'
);
select throws_ok(
  format('update public.day_entries set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(11)),
  '42501', null,
  'day_entries UPDATE: changing logged_by_user_id at all is refused'
);
select throws_ok(
  format('update public.day_entries set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(11)),
  '42501', 'last_modified_by_user_id must be the calling user',
  'day_entries UPDATE: last_modified_by_user_id must equal the caller'
);
select lives_ok(
  format('update public.day_entries set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('mom'), tests.ulid(11)),
  'day_entries UPDATE: last_modified_by_user_id = caller is allowed'
);

select set_config('role', 'authenticated', true);

-- ---------------------------------------------------------------------------
-- 2. enforce_observation_attribution.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$insert into public.observations
             (id, day_entry_id, profile_id, local_date, tz, category, updated_at, logged_by_user_id)
           values (%L, %L, %L, '2026-09-01', 'UTC', 'pain', now(), %L)$$,
    tests.ulid(20), tests.ulid(10), tests.ulid(1), tests.get_supabase_uid('eve')),
  '42501', 'attribution columns are server-authoritative',
  'observations INSERT: forging logged_by_user_id to another user is refused'
);
select lives_ok(
  format($$insert into public.observations
             (id, day_entry_id, profile_id, local_date, tz, category, updated_at, logged_by_user_id)
           values (%L, %L, %L, '2026-09-01', 'UTC', 'pain', now(), %L)$$,
    tests.ulid(20), tests.ulid(10), tests.ulid(1), tests.get_supabase_uid('mom')),
  'observations INSERT: setting logged_by_user_id to the caller''s own uid is allowed'
);
select throws_ok(
  format('update public.observations set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(20)),
  '42501', null,
  'observations UPDATE: changing logged_by_user_id at all is refused'
);
select throws_ok(
  format('update public.observations set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(20)),
  '42501', 'last_modified_by_user_id must be the calling user',
  'observations UPDATE: last_modified_by_user_id must equal the caller'
);
select lives_ok(
  format('update public.observations set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('mom'), tests.ulid(20)),
  'observations UPDATE: last_modified_by_user_id = caller is allowed'
);

-- ---------------------------------------------------------------------------
-- 3. enforce_care_note_attribution.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$insert into public.care_notes (id, profile_id, body, updated_at, logged_by_user_id)
           values (%L, %L, 'note', now(), %L)$$,
    tests.ulid(30), tests.ulid(1), tests.get_supabase_uid('eve')),
  '42501', 'attribution columns are server-authoritative',
  'care_notes INSERT: forging logged_by_user_id to another user is refused'
);
select lives_ok(
  format($$insert into public.care_notes (id, profile_id, body, updated_at, logged_by_user_id)
           values (%L, %L, 'note', now(), %L)$$,
    tests.ulid(30), tests.ulid(1), tests.get_supabase_uid('mom')),
  'care_notes INSERT: setting logged_by_user_id to the caller''s own uid is allowed'
);
select throws_ok(
  format('update public.care_notes set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(30)),
  '42501', null,
  'care_notes UPDATE: changing logged_by_user_id at all is refused'
);
select throws_ok(
  format('update public.care_notes set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(30)),
  '42501', 'last_modified_by_user_id must be the calling user',
  'care_notes UPDATE: last_modified_by_user_id must equal the caller'
);
select lives_ok(
  format('update public.care_notes set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('mom'), tests.ulid(30)),
  'care_notes UPDATE: last_modified_by_user_id = caller is allowed'
);

-- ---------------------------------------------------------------------------
-- 4. enforce_prep_item_attribution.
-- ---------------------------------------------------------------------------
select throws_ok(
  format($$insert into public.visit_prep_items (id, profile_id, body, updated_at, logged_by_user_id)
           values (%L, %L, 'bring chart', now(), %L)$$,
    tests.ulid(40), tests.ulid(1), tests.get_supabase_uid('eve')),
  '42501', 'attribution columns are server-authoritative',
  'visit_prep_items INSERT: forging logged_by_user_id to another user is refused'
);
select lives_ok(
  format($$insert into public.visit_prep_items (id, profile_id, body, updated_at, logged_by_user_id)
           values (%L, %L, 'bring chart', now(), %L)$$,
    tests.ulid(40), tests.ulid(1), tests.get_supabase_uid('mom')),
  'visit_prep_items INSERT: setting logged_by_user_id to the caller''s own uid is allowed'
);
select throws_ok(
  format('update public.visit_prep_items set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(40)),
  '42501', null,
  'visit_prep_items UPDATE: changing logged_by_user_id at all is refused'
);
select throws_ok(
  format('update public.visit_prep_items set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(40)),
  '42501', 'last_modified_by_user_id must be the calling user',
  'visit_prep_items UPDATE: last_modified_by_user_id must equal the caller'
);
select lives_ok(
  format('update public.visit_prep_items set last_modified_by_user_id = %L where id = %L',
    tests.get_supabase_uid('mom'), tests.ulid(40)),
  'visit_prep_items UPDATE: last_modified_by_user_id = caller is allowed'
);

-- ---------------------------------------------------------------------------
-- 5. Migrations/service-role (null auth.uid()) are exempt from all four
--    guards - the same carve-out every other attribution/authorization
--    guard in this schema has (e.g. enforce_profile_guardian_only_deletion,
--    enforce_guardian_invitation_revocation_terminal).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select lives_ok(
  format('update public.day_entries set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(11)),
  'day_entries: a null auth.uid() (migrations/service role) is exempt from the guard'
);
select lives_ok(
  format('update public.observations set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(20)),
  'observations: a null auth.uid() (migrations/service role) is exempt from the guard'
);
select lives_ok(
  format('update public.care_notes set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(30)),
  'care_notes: a null auth.uid() (migrations/service role) is exempt from the guard'
);
select lives_ok(
  format('update public.visit_prep_items set logged_by_user_id = %L where id = %L',
    tests.get_supabase_uid('dad'), tests.ulid(40)),
  'visit_prep_items: a null auth.uid() (migrations/service role) is exempt from the guard'
);

rollback;
