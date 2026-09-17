-- Regression coverage for Issue #517: a co-parent could soft-delete or
-- archive a profile via a direct PostgREST PATCH (bypassing sync_push's
-- "only primary_guardian" rule, which the raw UPDATE path never enforced).
-- Exercises the RAW `update public.profiles ...` statement directly (not
-- through sync_push), since that is exactly the bypass the issue reports.
begin;
select plan(9);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('eve');

-- ---------------------------------------------------------------------------
-- Setup: mom creates the profile via sync_push (becomes primary_guardian);
-- dad accepts a co_parent invitation.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Riley', 'is_minor', false,
    'updated_at', '2026-09-01T00:00:00Z')),
  '[]'::jsonb
);

select public.create_guardian_invitation(
  tests.ulid(1), 'co_parent', 'Dad',
  repeat('a1', 32), 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(repeat('a1', 32), 'Dad');

-- ---------------------------------------------------------------------------
-- 1. A co-parent's raw PATCH of deleted_at is refused by the trigger.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.profiles set deleted_at = clock_timestamp() where id = tests.ulid(1)$$,
  '42501', 'only primary_guardian can delete or archive profile',
  'Co-parent raw UPDATE of deleted_at is rejected (Issue #517)'
);

select is(
  (select deleted_at from public.profiles where id = tests.ulid(1)),
  null,
  'Profile is still live after the co-parent''s rejected raw UPDATE'
);

-- ---------------------------------------------------------------------------
-- 2. A co-parent's raw PATCH of archived_at is refused identically.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.profiles set archived_at = clock_timestamp() where id = tests.ulid(1)$$,
  '42501', 'only primary_guardian can delete or archive profile',
  'Co-parent raw UPDATE of archived_at is rejected (Issue #517)'
);

select is(
  (select archived_at from public.profiles where id = tests.ulid(1)),
  null,
  'Profile is still un-archived after the co-parent''s rejected raw UPDATE'
);

-- ---------------------------------------------------------------------------
-- 3. An outsider (not even a guardian) cannot touch the row at all - RLS's
--    own USING clause hides it before this trigger ever runs, so the
--    UPDATE silently affects zero rows rather than raising.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('eve');
update public.profiles set deleted_at = clock_timestamp() where id = tests.ulid(1);
select is(
  (select deleted_at from public.profiles where id = tests.ulid(1)),
  null,
  'A non-guardian''s UPDATE is invisible to RLS and changes nothing'
);

-- ---------------------------------------------------------------------------
-- 4. A co-parent's raw PATCH of ordinary metadata (not archived_at/deleted_at)
--    still works - the trigger must not over-broadly block every update.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
update public.profiles set display_name = 'Riley Renamed' where id = tests.ulid(1);
select is(
  (select display_name from public.profiles where id = tests.ulid(1)),
  'Riley Renamed',
  'Co-parent can still edit ordinary profile metadata via raw UPDATE'
);

-- is_minor is deliberately NOT restricted to primary_guardian by this
-- trigger (see the migration header) - a co-parent may still set it.
update public.profiles set is_minor = true where id = tests.ulid(1);
select is(
  (select is_minor from public.profiles where id = tests.ulid(1)),
  true,
  'Co-parent can still set is_minor via raw UPDATE (unrestricted by this guard, by design)'
);

-- ---------------------------------------------------------------------------
-- 5. The primary_guardian CAN delete/archive via raw UPDATE - the guard
--    only blocks the wrong role, not the right one.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
update public.profiles set deleted_at = clock_timestamp() where id = tests.ulid(1);
select isnt(
  (select deleted_at from public.profiles where id = tests.ulid(1)),
  null,
  'Primary guardian CAN delete the profile via raw UPDATE'
);

-- ---------------------------------------------------------------------------
-- 6. sync_push's own primary_guardian delete/archive path is unaffected
--    (regression: the trigger must not double-reject its own legitimate
--    write). Revive the profile first (mom is primary_guardian).
-- ---------------------------------------------------------------------------
update public.profiles set deleted_at = null where id = tests.ulid(1);
select is(
  public.sync_push(
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(1), 'display_name', 'Riley', 'is_minor', true,
      'deleted_at', '2026-09-05T00:00:00Z',
      'updated_at', '2026-09-05T00:00:00Z')),
    '[]'::jsonb
  ) -> 'rejected',
  '[]'::jsonb,
  'sync_push''s own primary_guardian delete still works through this new trigger'
);

rollback;
