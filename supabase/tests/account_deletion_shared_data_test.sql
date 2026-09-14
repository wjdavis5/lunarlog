-- Regression coverage for Issue #605's two Issue #604 findings (LLA-047,
-- LLA-048): delete_account_data() traces a departing caller can leave on
-- data they do NOT own - a checked visit_prep_items item on someone else's
-- profile, and an import_jobs row a shared/transferred entry still points
-- at - which previously made the account permanently undeletable rather
-- than merely retryable, since neither trace changes on its own between
-- attempts.
--
-- Both scenarios exercise the real failure path end to end, not merely
-- delete_account_data() in isolation:
--   * LLA-047's failure was a hard CHECK constraint
--     (visit_prep_items_checked_stamp_check) tripped by the FK cascade that
--     `auth.admin.deleteUser` fires - so this file actually deletes the
--     checker's auth.users row via tests.delete_supabase_user() (the same
--     raw `delete from auth.users` the Edge Function's admin call performs)
--     to prove the cascade has nothing left to trip.
--   * LLA-048's failure was enforce_day_entry_attribution()/
--     enforce_observation_attribution() rejecting the FK cascade's own
--     UPDATE inside delete_account_data() itself - so this file asserts
--     delete_account_data() completes without raising (lives_ok) rather
--     than aborting the whole function with no partial progress.
begin;
select plan(16);

-- ---------------------------------------------------------------------------
-- 1. LLA-047: a caregiver's checkmark on a profile they do not own must not
--    survive as a dangling reference once they delete their own account.
-- ---------------------------------------------------------------------------

select tests.create_supabase_user('owner_a');
select tests.create_supabase_user('checker_a');

select tests.authenticate_as('owner_a');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(1), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(1), 'caregiver', 'Checker',
  'c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1', 48
);

select tests.authenticate_as('checker_a');
select public.accept_guardian_invitation(
  'c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1c1', 'Checker'
);

-- The caregiver checks an item on the shared (owner-owned) profile -
-- exactly enforce_prep_item_attribution()'s ordinary sanctioned INSERT
-- shape (is_checked names the caller, checked_at is set).
insert into public.visit_prep_items
  (id, profile_id, body, is_checked, checked_by_user_id, checked_at,
   logged_by_user_id, last_modified_by_user_id, updated_at)
values
  (tests.ulid(10), tests.ulid(1), 'bring insurance card', true,
   tests.get_supabase_uid('checker_a'), '2026-09-10T00:00:00Z',
   tests.get_supabase_uid('checker_a'), tests.get_supabase_uid('checker_a'),
   '2026-09-10T00:00:00Z');

select lives_ok(
  'select public.delete_account_data()',
  'LLA-047: delete_account_data succeeds for a caregiver who checked an item on a profile they do not own'
);

-- Checked as service_role: checker_a's own guardianship is gone after the
-- call above, so their (still-authenticated) session could no longer see
-- this row by RLS regardless of whether the fix actually ran.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*) from public.visit_prep_items
    where id = tests.ulid(10) and deleted_at is null),
  1::bigint,
  'LLA-047: the item survives, not tombstoned - it still belongs to the owner''s profile'
);
select is(
  (select is_checked from public.visit_prep_items where id = tests.ulid(10)),
  false,
  'LLA-047: the item is unchecked'
);
select is(
  (select checked_by_user_id from public.visit_prep_items where id = tests.ulid(10)),
  null,
  'LLA-047: checked_by_user_id is cleared'
);
select is(
  (select checked_at from public.visit_prep_items where id = tests.ulid(10)),
  null,
  'LLA-047: checked_at is cleared'
);
select is(
  (select body from public.visit_prep_items where id = tests.ulid(10)),
  'bring insurance card',
  'LLA-047: the item''s own text is untouched - only the check state is reverted'
);
select is(
  (select count(*) from public.profiles where id = tests.ulid(1) and deleted_at is null),
  1::bigint,
  'LLA-047: the owner''s profile is untouched - the checker never owned it'
);

-- The actual regression: deleting the checker's auth.users row (the same
-- raw cascade auth.admin.deleteUser performs) used to trip
-- visit_prep_items_checked_stamp_check (23514) here, permanently, because
-- checked_by_user_id was still non-null while is_checked stayed true.
select lives_ok(
  $$select tests.delete_supabase_user('checker_a')$$,
  'LLA-047: deleting the checker''s auth.users row no longer trips visit_prep_items_checked_stamp_check'
);

-- ---------------------------------------------------------------------------
-- 2. LLA-048: deleting the caller's own import_jobs row must not be blocked
--    by an attribution guard when a shared/transferred entry it is still
--    referenced by has since been edited by a different guardian.
-- ---------------------------------------------------------------------------

-- Three distinct people (importer_b's deletion must not depend on being the
-- profile owner - the crux of the original bug: delete_account_data() only
-- ever tombstones OWNED profiles' entries, so this entry survives that step
-- untouched and reaches the import_jobs cleanup with editor_b's stamp
-- still in place).
select tests.create_supabase_user('profile_owner_b');
select tests.create_supabase_user('importer_b');
select tests.create_supabase_user('editor_b');

select tests.authenticate_as('profile_owner_b');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(2), 'Sam', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');
select public.create_guardian_invitation(
  tests.ulid(2), 'co_parent', 'Importer',
  repeat('a2', 32), 48
);
select public.create_guardian_invitation(
  tests.ulid(2), 'co_parent', 'Editor',
  'e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2', 48
);

select tests.authenticate_as('importer_b');
select public.accept_guardian_invitation(
  repeat('a2', 32), 'Importer'
);

select tests.authenticate_as('editor_b');
select public.accept_guardian_invitation(
  'e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2e2', 'Editor'
);

-- Fixture written directly as service_role (bypasses every trigger/RLS,
-- auth.uid() resolves null): represents an entry importer_b originally
-- imported onto profile_owner_b's shared profile (import_id set, day_entries
-- .user_id already homed to the actual owner) that editor_b has since
-- edited via sync_push (last_modified_by_user_id = editor_b, not the
-- importer) - exactly the shape a raw FK ON DELETE SET NULL cascade would
-- otherwise choke on.
select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

insert into public.import_jobs (id, profile_id, source, status, total_rows, processed_rows, created_by)
values ('11111111-1111-1111-1111-111111111111', tests.ulid(2), 'clue_import', 'completed', 1, 1,
        tests.get_supabase_uid('importer_b'));

insert into public.day_entries
  (id, user_id, profile_id, local_date, tz, flow, updated_at, import_id,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(20), tests.get_supabase_uid('profile_owner_b'), tests.ulid(2), '2026-09-01', 'UTC',
   'light', '2026-09-01T00:00:00Z', '11111111-1111-1111-1111-111111111111',
   tests.get_supabase_uid('importer_b'), tests.get_supabase_uid('editor_b'));

insert into public.observations
  (id, day_entry_id, profile_id, local_date, tz, category, updated_at, import_id,
   logged_by_user_id, last_modified_by_user_id)
values
  (tests.ulid(21), tests.ulid(20), tests.ulid(2), '2026-09-01', 'UTC', 'pain',
   '2026-09-01T00:00:00Z', '11111111-1111-1111-1111-111111111111',
   tests.get_supabase_uid('importer_b'), tests.get_supabase_uid('editor_b'));

select tests.authenticate_as('importer_b');
select lives_ok(
  'select public.delete_account_data()',
  'LLA-048: delete_account_data succeeds even though the importer''s job is referenced by rows a ' ||
  'different guardian has since edited'
);

select set_config('request.jwt.claims', '', true);
select set_config('role', 'service_role', true);

select is(
  (select count(*) from public.import_jobs where created_by = tests.get_supabase_uid('importer_b')),
  0::bigint,
  'LLA-048: the importer''s own import_jobs row is gone'
);
select is(
  (select count(*) from public.day_entries where id = tests.ulid(20) and deleted_at is null),
  1::bigint,
  'LLA-048: the shared entry survives, not tombstoned - importer_b never owned this profile'
);
select is(
  (select count(*) from public.profiles where id = tests.ulid(2) and deleted_at is null),
  1::bigint,
  'LLA-048: profile_owner_b''s profile is untouched - the importer never owned it'
);
select is(
  (select import_id from public.day_entries where id = tests.ulid(20)),
  null,
  'LLA-048: the shared entry''s import_id is nulled'
);
select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(20)),
  tests.get_supabase_uid('editor_b'),
  'LLA-048: the shared entry''s attribution is untouched - the editor''s stamp survives, not restamped to the importer'
);
select is(
  (select import_id from public.observations where id = tests.ulid(21)),
  null,
  'LLA-048: the shared observation''s import_id is nulled'
);
select is(
  (select last_modified_by_user_id from public.observations where id = tests.ulid(21)),
  tests.get_supabase_uid('editor_b'),
  'LLA-048: the shared observation''s attribution is untouched'
);

rollback;
