-- Coverage for Issue #128 (P2): shared care notes and visit-prep list --
-- schema shape (RLS, policies, grants, indexes, triggers), the day-entries
-- write ladder (any accepted guardian reads; primary/co_parent/caregiver
-- write; viewer rejected in-RPC and by RLS), the sync_push round trip
-- through p_care_notes/p_visit_prep_items (attribution stamping,
-- server-stamped check state, tombstone clearing, per-id LWW, concurrent
-- offline adds converging), the server-side length bounds (rejected, never
-- truncated), the notification-payload exclusion (structural: no outbox
-- column can hold the content and no trigger on either table feeds the
-- outbox), the revoked/stranger read exclusion, old-arity calls,
-- delete_account_data()'s new counts, and the reconcile guard.
-- Fixture style: profile_modes_cycle_overrides_test.sql /
-- observations_test.sql.
begin;
select plan(85);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.rejected_ids(n text) returns text[] language sql as
  $$ select array_agg(e ->> 'id') from r, jsonb_array_elements(r.v -> 'rejected') e where r.name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape: tables, RLS, policies, grants, indexes, triggers.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'care_notes');
select tests.rls_forced('public', 'care_notes');
select tests.rls_enabled('public', 'visit_prep_items');
select tests.rls_forced('public', 'visit_prep_items');

select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'care_notes'),
  3, 'care_notes carries exactly the three documented policies (select, insert, update)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'care_notes' and roles <> '{authenticated}'),
  0, 'every care_notes policy is scoped to authenticated');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'care_notes' and cmd = 'DELETE'),
  0, 'care_notes has no DELETE policy (tombstone-only, matching every other synced table)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'visit_prep_items'),
  3, 'visit_prep_items carries exactly the three documented policies (select, insert, update)');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'visit_prep_items' and roles <> '{authenticated}'),
  0, 'every visit_prep_items policy is scoped to authenticated');
select is(
  (select count(*)::integer from pg_policies
    where schemaname = 'public' and tablename = 'visit_prep_items' and cmd = 'DELETE'),
  0, 'visit_prep_items has no DELETE policy (tombstone-only, matching every other synced table)');

select is(
  (select has_table_privilege('authenticated', 'public.care_notes', 'DELETE')),
  false, 'authenticated holds no DELETE grant on care_notes');
select is(
  (select has_table_privilege('authenticated', 'public.visit_prep_items', 'DELETE')),
  false, 'authenticated holds no DELETE grant on visit_prep_items');
select is(
  (select has_table_privilege('anon', 'public.care_notes', 'SELECT')),
  false, 'anon holds no SELECT grant on care_notes');
select is(
  (select has_table_privilege('anon', 'public.visit_prep_items', 'SELECT')),
  false, 'anon holds no SELECT grant on visit_prep_items');
select is(
  (select has_column_privilege('authenticated', 'public.care_notes', 'server_version', 'UPDATE')),
  false, 'server_version is not client-updatable on care_notes');
select is(
  (select has_column_privilege('authenticated', 'public.visit_prep_items', 'server_version', 'UPDATE')),
  false, 'server_version is not client-updatable on visit_prep_items');
select is(
  (select has_column_privilege('authenticated', 'public.care_notes', 'logged_by_user_id', 'UPDATE')),
  false, 'logged_by_user_id is not client-updatable on care_notes (server-stamped, immutable)');
select is(
  (select has_column_privilege('authenticated', 'public.visit_prep_items', 'logged_by_user_id', 'UPDATE')),
  false, 'logged_by_user_id is not client-updatable on visit_prep_items (server-stamped, immutable)');

select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'care_notes'
      and indexname = 'care_notes_profile_id_idx'),
  1, 'care_notes read-path index (profile_id) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'visit_prep_items'
      and indexname = 'visit_prep_items_profile_id_idx'),
  1, 'visit_prep_items read-path index (profile_id) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'care_notes'
      and indexname = 'care_notes_server_version_idx'),
  1, 'care_notes pull-path index (server_version) exists');
select is(
  (select count(*)::integer from pg_indexes
    where schemaname = 'public' and tablename = 'visit_prep_items'
      and indexname = 'visit_prep_items_server_version_idx'),
  1, 'visit_prep_items pull-path index (server_version) exists');

select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'care_notes' and t.tgname = 'care_notes_set_server_version'),
  1, 'care_notes stamps server_version via the shared trigger');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'visit_prep_items' and t.tgname = 'visit_prep_items_set_server_version'),
  1, 'visit_prep_items stamps server_version via the shared trigger');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'care_notes' and t.tgname = 'care_notes_after_change_signal'),
  1, 'care_notes fires touch_sync_signal() -- rides the existing wake signal');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'visit_prep_items' and t.tgname = 'visit_prep_items_after_change_signal'),
  1, 'visit_prep_items fires touch_sync_signal() -- rides the existing wake signal');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'care_notes' and t.tgname like 'care_notes_attribution_%'),
  2, 'care_notes carries both attribution guards (insert + update)');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
    where c.relname = 'visit_prep_items' and t.tgname like 'visit_prep_items_attribution_%'),
  2, 'visit_prep_items carries both attribution guards (insert + update)');
select is(
  (select count(*)::integer from pg_publication_rel pr
     join pg_class c on c.oid = pr.prrelid
     join pg_publication p on p.oid = pr.prpubid
    where p.pubname = 'supabase_realtime' and c.relname in ('care_notes', 'visit_prep_items')),
  0, 'neither new table is in the supabase_realtime publication');

-- AC5 (structural half): notification_outbox has no column able to hold
-- care content, and no trigger on either new table feeds the alert
-- pipeline -- a care note / prep item can never become a notification
-- payload, whatever the client sends.
select is(
  (select count(*)::integer from information_schema.columns
    where table_schema = 'public' and table_name = 'notification_outbox'
      and column_name in ('body', 'care_note', 'care_notes', 'visit_prep',
        'visit_prep_item', 'visit_prep_items', 'prep_item', 'prep_items',
        'note', 'is_checked', 'checked_by_user_id', 'checked_at')),
  0, 'notification_outbox has no column able to hold care content (AC5)');
select is(
  (select count(*)::integer from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_proc p on p.oid = t.tgfoid
    where c.relname in ('care_notes', 'visit_prep_items')
      and p.proname in ('enqueue_caregiver_alerts', 'scan_missed_entry_reminders')),
  0, 'no trigger on either new table feeds the caregiver-alert pipeline (AC5)');

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) with dad (co_parent), nanny (caregiver),
-- doc (viewer) on one profile; a second family (other_parent); eve a
-- stranger.
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('nanny');
select tests.create_supabase_user('doc');
select tests.create_supabase_user('eve');
select tests.create_supabase_user('other_parent');

select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(tests.ulid(901), 'co_parent', 'Dad',
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 48);
select public.create_guardian_invitation(tests.ulid(901), 'caregiver', 'Nanny',
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 48);
select public.create_guardian_invitation(tests.ulid(901), 'viewer', 'Doc',
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 48);

select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Dad');
select tests.authenticate_as('nanny');
select public.accept_guardian_invitation(
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'Nanny');
select tests.authenticate_as('doc');
select public.accept_guardian_invitation(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', 'Doc');

select tests.authenticate_as('other_parent');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(951), 'Casey', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

-- ---------------------------------------------------------------------------
-- Round trip (AC1): mom adds a care note; dad adds a prep item; both land
-- attributed to their authors with server_version stamped, and the profile's
-- sync_signals row is touched (the second guardian's pull wakes up).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_note_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901),
    'body', 'Prefers the blue inhaler.',
    'updated_at', '2026-09-02T10:00:00Z')),
  '[]'::jsonb);

select is((select body from public.care_notes where id = tests.ulid(910)), 'Prefers the blue inhaler.',
  'AC1 round trip: the care note body persisted');
select is((select logged_by_user_id from public.care_notes where id = tests.ulid(910)), tests.get_supabase_uid('mom'),
  'AC1 round trip: the care note is attributed to its author (logged_by)');
select is((select last_modified_by_user_id from public.care_notes where id = tests.ulid(910)), tests.get_supabase_uid('mom'),
  'AC1 round trip: the care note stamps last-modified to its author');
select isnt((select server_version from public.care_notes where id = tests.ulid(910)), 0::bigint,
  'AC1 round trip: care_notes server_version stamped by the shared trigger');
select ok((select count(*) from public.sync_signals where profile_id = tests.ulid(901)) >= 1::bigint,
  'AC1 round trip: the care-note write touched sync_signals (the second guardian wakes up)');

select tests.authenticate_as('dad');
insert into r select 'dad_prep_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901),
    'body', 'Ask about iron levels.',
    'updated_at', '2026-09-02T11:00:00Z')));

select is((select body from public.visit_prep_items where id = tests.ulid(920)), 'Ask about iron levels.',
  'AC1 round trip: the prep item body persisted');
select is((select logged_by_user_id from public.visit_prep_items where id = tests.ulid(920)), tests.get_supabase_uid('dad'),
  'AC1 round trip: the prep item is attributed to its author (logged_by)');
select is((select is_checked from public.visit_prep_items where id = tests.ulid(920)), false,
  'AC1 round trip: a new prep item lands unchecked');

-- AC3: dad checks the item off -- the stamp names him, at the write time.
insert into r select 'dad_prep_check', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901),
    'body', 'Ask about iron levels.',
    'is_checked', true,
    'updated_at', '2026-09-02T12:00:00Z')));

select is((select is_checked from public.visit_prep_items where id = tests.ulid(920)), true,
  'AC3: the check-off is visible on the stored row');
select is((select checked_by_user_id from public.visit_prep_items where id = tests.ulid(920)), tests.get_supabase_uid('dad'),
  'AC3: the check-off records who checked it (server-stamped, not client-sent)');
select is((select checked_at from public.visit_prep_items where id = tests.ulid(920)), '2026-09-02T12:00:00Z'::timestamptz,
  'AC3: the check-off records when it was checked');

-- A text edit that leaves the check state unchanged keeps the stored stamp
-- (editing a co-guardian's checked item must not silently re-stamp it).
select tests.authenticate_as('mom');
insert into r select 'mom_prep_edit', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901),
    'body', 'Ask about iron levels and vitamin D.',
    'is_checked', true,
    'updated_at', '2026-09-02T13:00:00Z')));

select is((select checked_by_user_id from public.visit_prep_items where id = tests.ulid(920)), tests.get_supabase_uid('dad'),
  'a text edit on a checked item keeps the original checker (no silent re-stamp)');
select is((select body from public.visit_prep_items where id = tests.ulid(920)), 'Ask about iron levels and vitamin D.',
  'a text edit on a checked item still lands its new text');

-- Dad unchecks: the stamp clears with the state.
select tests.authenticate_as('dad');
insert into r select 'dad_prep_uncheck', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901),
    'body', 'Ask about iron levels and vitamin D.',
    'is_checked', false,
    'updated_at', '2026-09-02T14:00:00Z')));

select is((select is_checked from public.visit_prep_items where id = tests.ulid(920)), false,
  'an uncheck lands unchecked');
select is((select checked_by_user_id from public.visit_prep_items where id = tests.ulid(920)), null,
  'an uncheck clears who checked it');

-- ---------------------------------------------------------------------------
-- Write ladder (AC2): caregiver writes; viewer/stranger are rejected in-RPC
-- (opaque rejected entries) and denied by RLS on a direct write.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('nanny');
insert into r select 'nanny_note_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901),
    'body', 'Naps better after lunch.',
    'updated_at', '2026-09-02T15:00:00Z')),
  '[]'::jsonb);
select is((select body from public.care_notes where id = tests.ulid(911)), 'Naps better after lunch.',
  'AC2 write ladder: a caregiver can write care notes');

select tests.authenticate_as('doc');
insert into r select 'doc_note_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901),
    'body', 'Viewer note attempt.',
    'updated_at', '2026-09-02T16:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('doc_note_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(912), 'rejected', true),
  'AC2 write ladder: a viewer''s care-note push is an opaque rejected entry (42501 inside)');
select is((select count(*) from public.care_notes where id = tests.ulid(912)), 0::bigint,
  'AC2 write ladder: the viewer''s push stored nothing');

insert into r select 'doc_prep_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'profile_id', tests.ulid(901),
    'body', 'Viewer item attempt.',
    'updated_at', '2026-09-02T16:00:00Z')));
select is(
  pg_temp.resp('doc_prep_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(921), 'rejected', true),
  'AC2 write ladder: a viewer''s prep-item push is an opaque rejected entry');

-- Direct PostgREST-shape writes: viewer INSERT fails RLS, viewer UPDATE
-- touches nothing, while the viewer still reads both surfaces.
select throws_ok(
  format('insert into public.care_notes (id, profile_id, body, updated_at) values (%L, %L, %L, now())',
    tests.ulid(913), tests.ulid(901), 'Viewer direct attempt.'),
  '42501', null,
  'AC2 write ladder: a viewer''s direct care_notes INSERT fails RLS');
select is(
  (select count(*) from public.care_notes where profile_id = tests.ulid(901)),
  2::bigint, 'AC2: the viewer reads both care notes (mom''s and nanny''s)');
select is(
  (select count(*) from public.visit_prep_items where profile_id = tests.ulid(901)),
  1::bigint, 'AC2: the viewer reads the prep list');
with u as (
  update public.care_notes set body = 'Viewer overwrite.' where id = tests.ulid(910) returning 1
) select is((select count(*) from u), 0::bigint, 'AC2 write ladder: a viewer''s direct UPDATE touches 0 rows');

-- A stranger's push is rejected the same opaque way (enumeration parity:
-- no role and a foreign profile both reject, never 404-vs-403).
select tests.authenticate_as('eve');
insert into r select 'eve_note_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(914), 'profile_id', tests.ulid(901),
    'body', 'Stranger note attempt.',
    'updated_at', '2026-09-02T17:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('eve_note_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(914), 'rejected', true),
  'AC6: a stranger''s care-note push is an opaque rejected entry');
select is((select count(*) from public.care_notes where profile_id = tests.ulid(901)), 0::bigint,
  'AC6: a stranger reads nothing (the family''s notes are invisible, not merely unwritable)');

-- A row carrying checked_by_user_id is rejected as an unknown key, not
-- silently accepted -- the stamp is never client-settable via sync_push.
select tests.authenticate_as('dad');
insert into r select 'dad_forged_check', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(922), 'profile_id', tests.ulid(901),
    'body', 'Forged stamp attempt.',
    'is_checked', true,
    'checked_by_user_id', tests.get_supabase_uid('mom')::text,
    'updated_at', '2026-09-02T18:00:00Z')));
select is(
  pg_temp.resp('dad_forged_check') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(922), 'rejected', true),
  'AC3: a row carrying checked_by_user_id is rejected as an unknown key (the stamp is server-set)');

-- The same forgery via a direct PATCH is refused by the attribution guard
-- (a check must name the acting user -- here the row is checked in the
-- same statement so the checked-requires-a-stamp rule is satisfied, and the
-- forged name is what the guard rejects).
select throws_ok(
  format('update public.visit_prep_items set is_checked = true, checked_by_user_id = %L, checked_at = now() where id = %L',
    tests.get_supabase_uid('mom'), tests.ulid(920)),
  '42501', null,
  'AC3: a direct PATCH forging another guardian''s check is refused (42501)');

-- ---------------------------------------------------------------------------
-- Length bounds (AC4): over-length bodies are rejected, never truncated --
-- in-RPC (opaque rejected entries) and on a direct write (23514).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_long_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(915), 'profile_id', tests.ulid(901),
    'body', repeat('x', 2001),
    'updated_at', '2026-09-03T10:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_long_note') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(915), 'rejected', true),
  'AC4: a 2001-character care note is rejected in-RPC');
select is((select count(*) from public.care_notes where id = tests.ulid(915)), 0::bigint,
  'AC4: the over-length note stored nothing (rejected, not truncated)');

insert into r select 'mom_long_prep', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(923), 'profile_id', tests.ulid(901),
    'body', repeat('y', 501),
    'updated_at', '2026-09-03T10:00:00Z')));
select is(
  pg_temp.resp('mom_long_prep') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(923), 'rejected', true),
  'AC4: a 501-character prep item is rejected in-RPC');

select throws_ok(
  format('insert into public.care_notes (id, profile_id, body, updated_at) values (%L, %L, %L, now())',
    tests.ulid(916), tests.ulid(901), repeat('x', 2001)),
  '23514', null,
  'AC4: a direct over-length care_notes INSERT violates the CHECK (23514)');

-- Boundary values still land: exactly 2000 / exactly 500.
insert into r select 'mom_bound_note', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(917), 'profile_id', tests.ulid(901),
    'body', repeat('x', 2000),
    'updated_at', '2026-09-03T11:00:00Z')),
  '[]'::jsonb);
select is((select char_length(body) from public.care_notes where id = tests.ulid(917)), 2000,
  'AC4: a 2000-character care note (the bound) still lands');

-- ---------------------------------------------------------------------------
-- Tombstones carry no payload: a soft-delete clears body (and the check
-- state) even when the push still carries a stale non-empty body, and the
-- structural CHECK rejects a direct write that reintroduces one.
-- ---------------------------------------------------------------------------
insert into r select 'mom_note_tombstone', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901),
    'body', 'Stale body on a tombstone push.',
    'updated_at', '2026-09-04T10:00:00Z',
    'deleted_at', '2026-09-04T10:00:00Z')),
  '[]'::jsonb);
select is((select body from public.care_notes where id = tests.ulid(910)), '',
  'tombstone: a soft-deleted care note carries the empty body sentinel, not the stale push body');
select ok((select deleted_at from public.care_notes where id = tests.ulid(910)) is not null,
  'tombstone: the care note is deleted');

select throws_ok(
  format('insert into public.care_notes (id, profile_id, body, updated_at, deleted_at) values (%L, %L, %L, now(), now())',
    tests.ulid(918), tests.ulid(901), 'Direct tombstone with payload.'),
  '23514', null,
  'tombstone: a direct write reintroducing body onto a tombstone violates the CHECK (23514)');

-- ---------------------------------------------------------------------------
-- Resolution (AC7): two guardians adding items concurrently offline both
-- keep their items; an edit to the SAME id races per-id LWW; a row can
-- never move between profiles.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_concurrent_add', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(930), 'profile_id', tests.ulid(901),
    'body', 'Mom offline item.',
    'updated_at', '2026-09-05T10:00:00Z')));
select tests.authenticate_as('dad');
insert into r select 'dad_concurrent_add', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(931), 'profile_id', tests.ulid(901),
    'body', 'Dad offline item.',
    'updated_at', '2026-09-05T10:05:00Z')));
select is((select count(*) from public.visit_prep_items
  where id in (tests.ulid(930), tests.ulid(931)) and deleted_at is null), 2::bigint,
  'AC7: two guardians adding items concurrently offline both keep their items (set convergence)');

-- Same id, older write: declined with the server copy handed back.
insert into r select 'dad_stale_edit', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(930), 'profile_id', tests.ulid(901),
    'body', 'Dad stale overwrite.',
    'updated_at', '2026-09-05T09:00:00Z')));
select is((select body from public.visit_prep_items where id = tests.ulid(930)), 'Mom offline item.',
  'AC7: an older same-id write is declined (last-writer-wins)');
select is(
  (select count(*) from jsonb_array_elements(pg_temp.resp('dad_stale_edit') -> 'resolved') e
    where e ->> 'id' = tests.ulid(930) and e ->> 'table' = 'visit_prep_items'),
  1::bigint, 'AC7: the declined write hands back the server copy for convergence');

-- A row can never move between profiles (the day_entries pattern).
insert into r select 'mom_note_move', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(951),
    'body', 'Re-point attempt.',
    'updated_at', '2026-09-05T11:00:00Z')),
  '[]'::jsonb);
select is(
  pg_temp.resp('mom_note_move') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(911), 'rejected', true),
  'a care note cannot move between profiles (rejected, the day_entries pattern)');

-- Older-arity calls keep working: the 5-arg (pre-#128 tip) and 2-arg
-- (pre-#240) forms resolve to the one 7-arg body with '[]' defaults.
select tests.authenticate_as('mom');
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb)$$,
  'a 5-argument sync_push call still works (both new params default)');
select lives_ok(
  $$select public.sync_push('[]'::jsonb, '[]'::jsonb)$$,
  'a 2-argument sync_push call still works');

-- ---------------------------------------------------------------------------
-- Revocation (AC6): a revoked guardian reads nothing on either surface.
-- ---------------------------------------------------------------------------
select public.revoke_guardian(tests.ulid(901), tests.get_supabase_uid('nanny'));
select tests.authenticate_as('nanny');
select is((select count(*) from public.care_notes where profile_id = tests.ulid(901)), 0::bigint,
  'AC6: a revoked guardian reads no care notes');
select is((select count(*) from public.visit_prep_items where profile_id = tests.ulid(901)), 0::bigint,
  'AC6: a revoked guardian reads no prep items');

-- ---------------------------------------------------------------------------
-- Toggle-revert: reconcile_realtime_publication() actively reverts a
-- whole-row care_notes / visit_prep_items publish (the Issue #77 P1 fix,
-- extended here), mirroring observations_test.sql's toggle-revert setup
-- (clear back to the test-runner role: `alter publication` needs the
-- publication owner).
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
alter publication supabase_realtime add table public.care_notes;
alter publication supabase_realtime add table public.visit_prep_items;
select lives_ok(
  $$select public.reconcile_realtime_publication()$$,
  'reconcile_realtime_publication() runs without error against drifted care state');
select is(
  exists(
    select 1 from pg_publication_rel pr
      join pg_class pc on pc.oid = pr.prrelid
      join pg_namespace pn on pn.oid = pc.relnamespace
      join pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime' and pn.nspname = 'public' and pc.relname = 'care_notes'
  ),
  false,
  'reconcile_realtime_publication() reverts a whole-row care_notes publish');
select is(
  exists(
    select 1 from pg_publication_rel pr
      join pg_class pc on pc.oid = pr.prrelid
      join pg_namespace pn on pn.oid = pc.relnamespace
      join pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime' and pn.nspname = 'public' and pc.relname = 'visit_prep_items'
  ),
  false,
  'reconcile_realtime_publication() reverts a whole-row visit_prep_items publish');

-- ---------------------------------------------------------------------------
-- delete_account_data(): the new counts, owned-profile scoping (R7), and
-- shared-profile survival for a caregiver's own deletion.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('nanny');
insert into r select 'nanny_delete', public.delete_account_data();
select is((select (v ->> 'care_notes')::integer from r where name = 'nanny_delete'), 0,
  'delete_account_data: a caregiver with no owned profile deletes no care notes');
select is((select (v ->> 'visit_prep_items')::integer from r where name = 'nanny_delete'), 0,
  'delete_account_data: a caregiver with no owned profile deletes no prep items');
-- Survival is asserted as the owner: the revoked caregiver herself can no
-- longer read the family's rows at all (AC6 above), so counting as her
-- would prove nothing.
select tests.authenticate_as('mom');
select is((select count(*) from public.care_notes where profile_id = tests.ulid(901)),
  3::bigint, 'delete_account_data: the owning family''s care notes survive a caregiver''s deletion (R7)');
select is((select count(*) from public.visit_prep_items where profile_id = tests.ulid(901)),
  3::bigint, 'delete_account_data: the owning family''s prep items survive a caregiver''s deletion (R7)');

insert into r select 'mom_delete', public.delete_account_data();
select is((select (v ->> 'care_notes')::integer from r where name = 'mom_delete'), 3,
  'delete_account_data: the owner''s care notes are counted (910 tombstoned, 911, 917)');
select is((select (v ->> 'visit_prep_items')::integer from r where name = 'mom_delete'), 3,
  'delete_account_data: the owner''s prep items are counted (920, 930, 931)');
select is((select count(*) from public.care_notes where profile_id = tests.ulid(901)),
  0::bigint, 'delete_account_data: the owner''s care notes are gone');
select is((select count(*) from public.visit_prep_items where profile_id = tests.ulid(901)),
  0::bigint, 'delete_account_data: the owner''s prep items are gone');

select * from finish();
rollback;
