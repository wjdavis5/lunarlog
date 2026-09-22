-- Coverage for Issue #849 (re-scoped): the per-note private flag.
--
-- The subject (a caregiver membership stamped is_subject, #802) may write a
-- private day note; every other accepted guardian membership -- any role,
-- including the profile's primary_guardian owner -- receives note = NULL and
-- note_private = true from sync_pull. The transition guard forbids making an
-- already-shared note private (false -> true on a non-empty stored note) and
-- clearing a private flag (true -> false); it permits a note born private and
-- a false -> true flip while the stored note is still empty. sync_push
-- round-trips the flag, and export_account_data() carries it (with the text
-- masked for a non-subject caller).
begin;
select plan(24);

create function pg_temp.token(n int) returns text language sql as
  $$ select lpad(to_hex(n), 64, '0') $$;

-- ---------------------------------------------------------------------------
-- 1. Schema shape + grants.
-- ---------------------------------------------------------------------------
select is(
  (select data_type from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'note_private'),
  'boolean',
  'day_entries.note_private is a boolean column'
);
select is(
  (select is_nullable || ':' || column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'day_entries' and column_name = 'note_private'),
  'NO:false',
  'day_entries.note_private is NOT NULL default false'
);
select ok(
  has_column_privilege('authenticated', 'public.day_entries', 'note_private', 'UPDATE'),
  'authenticated has the UPDATE column grant for note_private'
);
select ok(
  exists (select 1 from pg_trigger
           where tgname = 'day_entries_note_private_guard' and not tgisinternal),
  'the day_entries_note_private_guard trigger exists'
);
select ok(
  exists (select 1 from pg_proc where proname = 'enforce_day_entry_note_private'
            and pronamespace = 'public'::regnamespace),
  'public.enforce_day_entry_note_private() exists'
);
select ok(
  not has_function_privilege('authenticated', 'public.is_profile_subject(text,uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.profile_has_subject(text)', 'execute')
  and not has_function_privilege('authenticated', 'public.mask_day_entry_note(jsonb,uuid)', 'execute'),
  'the subject/mask helpers are not client-executable'
);

-- ---------------------------------------------------------------------------
-- 2. Setup: Mom owns minor profile P; Daughter is its subject (caregiver);
--    Dad (co_parent), Sitter (caregiver), Aunt (viewer) are plain guardians.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('daughter');
select tests.create_supabase_user('sitter');
select tests.create_supabase_user('aunt');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(940), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(940), 'co_parent', 'Dad', pg_temp.token(1), 48);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(pg_temp.token(1), 'Dad');

select tests.authenticate_as('mom');
select public.create_guardian_invitation(tests.ulid(940), 'caregiver', 'Riley', pg_temp.token(2), 48, true);
select tests.authenticate_as('daughter');
select public.accept_guardian_invitation(pg_temp.token(2), 'Riley');

select tests.authenticate_as('mom');
select public.create_guardian_invitation(tests.ulid(940), 'caregiver', 'Sitter', pg_temp.token(3), 48);
select tests.authenticate_as('sitter');
select public.accept_guardian_invitation(pg_temp.token(3), 'Sitter');

select tests.authenticate_as('mom');
select public.create_guardian_invitation(tests.ulid(940), 'viewer', 'Aunt', pg_temp.token(4), 48);
select tests.authenticate_as('aunt');
select public.accept_guardian_invitation(pg_temp.token(4), 'Aunt');

-- ---------------------------------------------------------------------------
-- 3. The subject writes a private note; sync_push round-trips the flag.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select is(
  jsonb_array_length(public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(770), 'profile_id', tests.ulid(940), 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'light', 'note', 'secret', 'note_private', true,
      'updated_at', '2026-09-01T10:00:00Z'))
  ) -> 'rejected'),
  0,
  'a private note pushes without rejection'
);

select tests.clear_authentication();
select is(
  (select note || ':' || note_private::text from public.day_entries where id = tests.ulid(770)),
  'secret:true',
  'sync_push stored note_private = true alongside the note text'
);

-- ---------------------------------------------------------------------------
-- 4. Reads: the subject sees the text; every guardian role gets NULL.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select is(
  (select e ->> 'note' from jsonb_array_elements(public.sync_pull() -> 'day_entries') e
    where e ->> 'id' = tests.ulid(770)),
  'secret',
  'the subject reads her private note in full'
);

select tests.authenticate_as('mom');
select is(
  (select (e ->> 'note') is null from jsonb_array_elements(public.sync_pull() -> 'day_entries') e
    where e ->> 'id' = tests.ulid(770)),
  true,
  'the primary_guardian owner (not the subject) reads note as NULL'
);
select tests.authenticate_as('dad');
select is(
  (select (e ->> 'note') is null from jsonb_array_elements(public.sync_pull() -> 'day_entries') e
    where e ->> 'id' = tests.ulid(770)),
  true,
  'a co_parent reads note as NULL'
);
select tests.authenticate_as('sitter');
select is(
  (select (e ->> 'note') is null from jsonb_array_elements(public.sync_pull() -> 'day_entries') e
    where e ->> 'id' = tests.ulid(770)),
  true,
  'a caregiver reads note as NULL'
);
select tests.authenticate_as('aunt');
select is(
  (select (e ->> 'note') is null from jsonb_array_elements(public.sync_pull() -> 'day_entries') e
    where e ->> 'id' = tests.ulid(770)),
  true,
  'a viewer reads note as NULL'
);

-- ---------------------------------------------------------------------------
-- 5. Retroactive privacy is rejected: a shared (non-empty) note cannot be
--    made private, and a private flag cannot be cleared.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(771), 'profile_id', tests.ulid(940), 'local_date', '2026-09-02',
    'tz', 'UTC', 'flow', 'none', 'note', 'shared', 'note_private', false,
    'updated_at', '2026-09-02T10:00:00Z'))
);
select is(
  (public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(771), 'profile_id', tests.ulid(940), 'local_date', '2026-09-02',
      'tz', 'UTC', 'flow', 'none', 'note', 'shared', 'note_private', true,
      'updated_at', '2026-09-02T11:00:00Z'))
  ) -> 'rejected' -> 0 ->> 'id'),
  tests.ulid(771),
  'making an already-shared note private is rejected'
);
select tests.clear_authentication();
select is(
  (select note_private from public.day_entries where id = tests.ulid(771)),
  false,
  'the rejected retroactive-private update left the stored flag false'
);

-- false -> true while the stored note is still empty is allowed.
select tests.authenticate_as('daughter');
select public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(772), 'profile_id', tests.ulid(940), 'local_date', '2026-09-03',
    'tz', 'UTC', 'flow', 'none', 'note', null, 'note_private', false,
    'updated_at', '2026-09-03T10:00:00Z'))
);
select is(
  jsonb_array_length(public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(772), 'profile_id', tests.ulid(940), 'local_date', '2026-09-03',
      'tz', 'UTC', 'flow', 'none', 'note', 'written now', 'note_private', true,
      'updated_at', '2026-09-03T11:00:00Z'))
  ) -> 'rejected'),
  0,
  'false -> true is allowed while the stored note is still empty (the note is being written now)'
);
select tests.clear_authentication();
select is(
  (select note || ':' || note_private::text from public.day_entries where id = tests.ulid(772)),
  'written now:true',
  'the written-now private note stored both the text and the flag'
);

-- true -> false is never allowed, even on the subject's own row.
select tests.authenticate_as('daughter');
select is(
  (public.sync_push(
    '[]'::jsonb,
    jsonb_build_array(jsonb_build_object(
      'id', tests.ulid(770), 'profile_id', tests.ulid(940), 'local_date', '2026-09-01',
      'tz', 'UTC', 'flow', 'light', 'note', 'secret', 'note_private', false,
      'updated_at', '2026-09-04T10:00:00Z'))
  ) -> 'rejected' -> 0 ->> 'id'),
  tests.ulid(770),
  'clearing note_private once set is rejected'
);
select tests.clear_authentication();
select is(
  (select note_private from public.day_entries where id = tests.ulid(770)),
  true,
  'the private flag survived the rejected clear'
);

-- ---------------------------------------------------------------------------
-- 6. The trigger itself rejects a retroactive flip at the table layer.
-- ---------------------------------------------------------------------------
select throws_ok(
  $$update public.day_entries set note_private = true where id = tests.ulid(771)$$,
  '23514', null,
  'the day_entries_note_private_guard trigger raises check_violation on a retroactive flip'
);

-- ---------------------------------------------------------------------------
-- 7. Export carries the flag; the text is masked for a non-subject caller.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('daughter');
select is(
  (select de ->> 'note_private'
     from jsonb_array_elements(public.export_account_data() -> 'profiles') p,
          jsonb_array_elements(p -> 'day_entries') de
    where de ->> 'id' = tests.ulid(770)),
  'true',
  'the subject''s export carries note_private'
);
select is(
  (select de ->> 'note'
     from jsonb_array_elements(public.export_account_data() -> 'profiles') p,
          jsonb_array_elements(p -> 'day_entries') de
    where de ->> 'id' = tests.ulid(770)),
  'secret',
  'the subject''s export carries the private note text'
);

select tests.authenticate_as('mom');
select is(
  (select (de ->> 'note') is null
     from jsonb_array_elements(public.export_account_data() -> 'profiles') p,
          jsonb_array_elements(p -> 'day_entries') de
    where de ->> 'id' = tests.ulid(770)),
  true,
  'the owner''s export of a non-subject profile masks the private note text'
);
select is(
  (select de ->> 'note_private'
     from jsonb_array_elements(public.export_account_data() -> 'profiles') p,
          jsonb_array_elements(p -> 'day_entries') de
    where de ->> 'id' = tests.ulid(770)),
  'true',
  'the owner''s export still carries note_private'
);

rollback;
