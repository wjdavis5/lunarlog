-- Issue #801: guardian_notes -- per-guardian dated notes on a child's day.
--
-- Pins: table/RLS/policy/grant/index/trigger shape, the open read ladder
-- (any accepted guardian -- viewer included -- reads every note; only
-- primary_guardian/co_parent/caregiver write), author ownership (only the
-- original author may edit or tombstone, enforced in sync_push), the
-- distinct-ULID per author per date invariant (two authors on the same day
-- both survive -- no cross-author merge), tombstone payload clearing, and
-- the notification-outbox content-free guarantee.
--
-- Visibility (issue #800, decided): open and transparent. There is no
-- per-note visibility column, and this test pins that too.
begin;
select plan(33);

-- ---------------------------------------------------------------------------
-- temp helpers
-- ---------------------------------------------------------------------------
create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'guardian_notes');       -- 1
select tests.rls_forced('public', 'guardian_notes');        -- 2
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'guardian_notes'),
  3, 'guardian_notes carries exactly the three documented policies (select, insert, update)'); -- 3
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'guardian_notes'
      and roles <> '{authenticated}'),
  0, 'every guardian_notes policy is scoped to authenticated'); -- 4
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'guardian_notes' and cmd = 'DELETE'),
  0, 'guardian_notes has no DELETE policy (tombstone-only, matching every other synced table)'); -- 5
select is(
  (select has_table_privilege('authenticated', 'public.guardian_notes', 'DELETE')),
  false, 'authenticated holds no DELETE grant on guardian_notes'); -- 6
select is(
  (select has_table_privilege('anon', 'public.guardian_notes', 'SELECT')),
  false, 'anon holds no SELECT grant on guardian_notes'); -- 7
select is(
  (select has_column_privilege('authenticated', 'public.guardian_notes', 'server_version', 'UPDATE')),
  false, 'server_version is not client-updatable on guardian_notes'); -- 8
select is(
  (select has_column_privilege('authenticated', 'public.guardian_notes', 'logged_by_user_id', 'UPDATE')),
  false, 'logged_by_user_id is not client-updatable (author-immutable)'); -- 9
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'guardian_notes'
      and indexname = 'guardian_notes_profile_local_date_idx'),
  1, 'guardian_notes read-path index (profile_id, local_date) exists'); -- 10
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'guardian_notes'
      and indexname = 'guardian_notes_server_version_idx'),
  1, 'guardian_notes pull-path index (server_version) exists'); -- 11
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'guardian_notes' and t.tgname = 'guardian_notes_set_server_version'),
  1, 'guardian_notes stamps server_version via the shared trigger'); -- 12
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'guardian_notes' and t.tgname = 'guardian_notes_after_change_signal'),
  1, 'guardian_notes fires touch_sync_signal() -- rides the existing wake signal'); -- 13
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'guardian_notes' and t.tgname like 'guardian_notes_attribution_%'),
  2, 'guardian_notes carries both attribution guards (insert + update)'); -- 14
select is(
  (select count(*)::integer from pg_publication_rel pr
     join pg_class c on c.oid = pr.prrelid
     join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and c.relname = 'guardian_notes'),
  0, 'guardian_notes is not in the supabase_realtime publication'); -- 15
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_outbox'
      and column_name in ('body', 'guardian_note', 'guardian_notes', 'note', 'local_date', 'tz')),
  0, 'notification_outbox has no column able to hold guardian-note content'); -- 16
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'guardian_notes'
      and column_name in ('guardians_only', 'visibility', 'hidden', 'is_hidden')),
  0, 'guardian_notes carries no per-note visibility/hidden column (issue #800: open and transparent)'); -- 17

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) with dad (co_parent) and doc (viewer) on
-- one profile; a second family (other_parent) whose guardian must see
-- nothing.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doc');
select tests.create_supabase_user('other_parent');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(901), 'co_parent', 'Dad',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 48);
select public.create_guardian_invitation(tests.ulid(901), 'viewer', 'Doc',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 48);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Dad');
select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'Doc');

select tests.authenticate_as('other_parent');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(951), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- AC1: two guardians each write a note for the SAME date -- both survive,
-- each attributed, no merge.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', 'Seemed withdrawn this week.',
    'updated_at', '2026-09-12T10:00:00Z')));

select is((select body from public.guardian_notes where id = tests.ulid(910)),
  'Seemed withdrawn this week.',
  'AC1: mom''s guardian note body persisted'); -- 18
select is((select logged_by_user_id from public.guardian_notes where id = tests.ulid(910)),
  tests.get_supabase_uid('mom'),
  'AC1: the note is attributed to its author (logged_by)'); -- 19
select is((select last_modified_by_user_id from public.guardian_notes where id = tests.ulid(910)),
  tests.get_supabase_uid('mom'),
  'AC1: the note stamps last-modified to its author'); -- 20
select isnt((select server_version from public.guardian_notes where id = tests.ulid(910)), 0::bigint,
  'AC1: guardian_notes server_version is stamped by the shared trigger'); -- 21
select ok((select count(*) from public.sync_signals where profile_id = tests.ulid(901)) >= 1::bigint,
  'AC1: the note write touched sync_signals (the other guardian wakes up)'); -- 22

select tests.authenticate_as('dad');
insert into r select 'dad_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', 'Ask the doctor about the heavy days.',
    'updated_at', '2026-09-12T11:00:00Z')));
select is((select body from public.guardian_notes where id = tests.ulid(911)),
  'Ask the doctor about the heavy days.',
  'AC1: dad''s note on the same date persisted'); -- 23
select is(
  (select count(*)::bigint from public.guardian_notes
    where profile_id = tests.ulid(901) and local_date = '2026-09-12' and deleted_at is null),
  2::bigint,
  'AC1: two live notes for the same (profile, date) -- distinct ULIDs, no merge'); -- 24
select is(
  (select count(distinct logged_by_user_id)::integer from public.guardian_notes
    where profile_id = tests.ulid(901) and local_date = '2026-09-12'),
  2, 'AC1: the two notes are attributed to two different authors'); -- 25

-- ---------------------------------------------------------------------------
-- AC3: a guardian edits only their OWN note; the server refuses a
-- co-guardian's edit of someone else's note.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_edit', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', 'Seemed withdrawn, then rallied by the weekend.',
    'updated_at', '2026-09-13T10:00:00Z')));
select is((select body from public.guardian_notes where id = tests.ulid(910)),
  'Seemed withdrawn, then rallied by the weekend.',
  'AC3: a guardian can edit their own note'); -- 26

select tests.authenticate_as('dad');
insert into r select 'dad_edit_mom', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', 'hijacked',
    'updated_at', '2026-09-14T10:00:00Z')));
select is(pg_temp.rejected_ids('dad_edit_mom'), array[tests.ulid(910)],
  'AC3: the server rejects a co-guardian editing another author''s note'); -- 27
select is((select body from public.guardian_notes where id = tests.ulid(910)),
  'Seemed withdrawn, then rallied by the weekend.',
  'AC3: the rejected edit left the author''s note untouched'); -- 28

-- A viewer can read every note but cannot write one.
select tests.authenticate_as('doc');
insert into r select 'doc_write', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', 'viewer note',
    'updated_at', '2026-09-12T12:00:00Z')));
select is(pg_temp.rejected_ids('doc_write'), array[tests.ulid(912)],
  'AC2: a viewer''s write is rejected by the server'); -- 29
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(901)),
  2::bigint, 'AC2: the viewer''s rejected write created no row'); -- 30

-- The child/any accepted guardian reads everything; a stranger sees nothing.
select tests.authenticate_as('other_parent');
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(901)),
  0::bigint, 'a guardian on another profile sees none of this profile''s notes (RLS)'); -- 31

select tests.authenticate_as('mom');
select is(
  (select count(*)::bigint from public.guardian_notes where profile_id = tests.ulid(901)),
  2::bigint, 'an accepted guardian reads every guardian note (open and transparent)'); -- 32

-- ---------------------------------------------------------------------------
-- AC3: a guardian can remove their own note -- the tombstone clears body.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'dad_delete', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901),
    'local_date', '2026-09-12', 'tz', 'America/New_York',
    'body', '',
    'updated_at', '2026-09-15T10:00:00Z', 'deleted_at', '2026-09-15T10:00:00Z')));
select is((select body from public.guardian_notes where id = tests.ulid(911)), '',
  'AC3: a tombstone clears the body'); -- 33

select * from finish();
rollback;
