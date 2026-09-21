-- Coverage for Issue #851 (P1): household logistics -- the per-profile
-- supplies kit, built by generalising visit_prep_items with a `kind`
-- discriminator rather than adding a second, structurally identical table.
--
-- Pins: the column shape (default + CHECK), the sync_push round trip for a
-- supply row (kind persisted, attribution stamped, check-off recorded as
-- "stocked"), the pre-#851 containment guard (a push that omits `kind`
-- never rewrites a stored kind), the invalid-kind rejection, the viewer
-- read-only ladder on the supply kind, and the tombstone discipline (body
-- and check state clear, kind survives -- identity, not health content).
-- Fixture style: care_notes_visit_prep_test.sql.
begin;
select plan(18);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;

-- ---------------------------------------------------------------------------
-- Schema shape: the kind column, its default, its CHECK, and its grant.
-- ---------------------------------------------------------------------------

select is(
  (select column_default from information_schema.columns
    where table_schema = 'public' and table_name = 'visit_prep_items'
      and column_name = 'kind'),
  '''visit_prep''::text',
  'visit_prep_items.kind exists and defaults to visit_prep (a pre-#851 row reads as a prep item)');

select is(
  (select count(*)::integer from pg_constraint
    where conrelid = 'public.visit_prep_items'::regclass
      and conname = 'visit_prep_items_kind_check'),
  1, 'kind carries its CHECK constraint (the closed visit_prep | supply set)');

select is(
  (select has_column_privilege('authenticated', 'public.visit_prep_items', 'kind', 'UPDATE')),
  true, 'kind is client-updatable -- sync_push must round-trip it');

-- ---------------------------------------------------------------------------
-- Fixtures: mom (primary_guardian) with dad (co_parent) and doc (viewer) on
-- one profile. The list lives on the profile, so every accepted guardian --
-- including a viewer -- reads it; the issue's stated direction is that the
-- subject herself can see it (a guardian on her own profile is the same
-- policy path).
-- ---------------------------------------------------------------------------
select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doc');

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

-- ---------------------------------------------------------------------------
-- Round trip: dad adds a supply item (kind = 'supply'). It lands as a
-- supply, attributed to its author, server_version stamped.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'dad_supply_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(940), 'profile_id', tests.ulid(901),
    'body', 'Panty liners',
    'kind', 'supply',
    'updated_at', '2026-09-02T10:00:00Z')));

select is((select kind from public.visit_prep_items where id = tests.ulid(940)), 'supply',
  'a supply push lands with kind = supply');
select is((select logged_by_user_id from public.visit_prep_items where id = tests.ulid(940)),
  tests.get_supabase_uid('dad'),
  'the supply item is attributed to its author (logged_by)');
select isnt((select server_version from public.visit_prep_items where id = tests.ulid(940)), 0::bigint,
  'the supply item server_version is stamped by the shared trigger');

-- A push that omits kind lands the column default (the pre-#851 shape).
select tests.authenticate_as('mom');
insert into r select 'mom_plain_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(941), 'profile_id', tests.ulid(901),
    'body', 'Ask about iron levels.',
    'updated_at', '2026-09-02T11:00:00Z')));

select is((select kind from public.visit_prep_items where id = tests.ulid(941)), 'visit_prep',
  'a push that omits kind lands the visit_prep default');

-- The containment guard: an old client editing the same supply row without
-- a `kind` key must not reset it to the default.
select tests.authenticate_as('dad');
insert into r select 'dad_supply_edit', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(940), 'profile_id', tests.ulid(901),
    'body', 'Panty liners (size 2)',
    'updated_at', '2026-09-02T12:00:00Z')));

select is((select kind from public.visit_prep_items where id = tests.ulid(940)), 'supply',
  'an old client edit that omits kind preserves the stored supply kind (containment guard)');
select is((select body from public.visit_prep_items where id = tests.ulid(940)), 'Panty liners (size 2)',
  'the same edit still lands its new text');

-- Checking a supply item reads as "stocked": who stocked it and when.
insert into r select 'dad_supply_stock', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(940), 'profile_id', tests.ulid(901),
    'body', 'Panty liners (size 2)',
    'kind', 'supply',
    'is_checked', true,
    'updated_at', '2026-09-02T13:00:00Z')));

select is((select is_checked from public.visit_prep_items where id = tests.ulid(940)), true,
  'a supply item can be marked stocked (is_checked = true)');
select is((select checked_by_user_id from public.visit_prep_items where id = tests.ulid(940)),
  tests.get_supabase_uid('dad'),
  'stocking records who did it (server-stamped, never client-sent)');
select is((select checked_at from public.visit_prep_items where id = tests.ulid(940)),
  '2026-09-02T13:00:00Z'::timestamptz,
  'stocking records when it was done');

-- An out-of-set kind is rejected by the CHECK into the opaque rejected set.
select tests.authenticate_as('mom');
insert into r select 'mom_bad_kind', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(942), 'profile_id', tests.ulid(901),
    'body', 'Unknown kind.',
    'kind', 'medicine',
    'updated_at', '2026-09-02T14:00:00Z')));

select is(
  pg_temp.resp('mom_bad_kind') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(942), 'rejected', true),
  'an out-of-set kind is rejected in-RPC (the CHECK bounds the set)');
select is((select count(*) from public.visit_prep_items where id = tests.ulid(942)), 0::bigint,
  'the invalid-kind row stored nothing');

-- ---------------------------------------------------------------------------
-- Read/write ladder on the supply kind: a viewer reads, and cannot write.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doc');
select is(
  (select count(*) from public.visit_prep_items
    where id = tests.ulid(940) and kind = 'supply'),
  1::bigint, 'a viewer reads the profile''s supply items (visible to every guardian)');

select throws_ok(
  format('insert into public.visit_prep_items (id, profile_id, body, kind, updated_at) values (%L, %L, %L, ''supply'', now())',
    tests.ulid(943), tests.ulid(901), 'Viewer supply attempt.'),
  '42501', null,
  'a viewer''s direct supply INSERT fails RLS');

with u as (
  update public.visit_prep_items set kind = 'visit_prep' where id = tests.ulid(940) returning 1
) select is((select count(*) from u), 0::bigint,
  'a viewer''s direct kind UPDATE touches 0 rows');

select tests.authenticate_as('doc');
insert into r select 'doc_supply_push', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(944), 'profile_id', tests.ulid(901),
    'body', 'Viewer supply push.',
    'kind', 'supply',
    'updated_at', '2026-09-02T15:00:00Z')));

select is(
  pg_temp.resp('doc_supply_push') -> 'rejected' -> 0,
  jsonb_build_object('id', tests.ulid(944), 'rejected', true),
  'a viewer''s supply push is an opaque rejected entry');

-- ---------------------------------------------------------------------------
-- Tombstone: body and check state clear, kind survives -- identity, not
-- health content, so a deleted supply row still converges as a supply.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_supply_tombstone', public.sync_push('[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(940), 'profile_id', tests.ulid(901),
    'body', 'Stale body on a tombstone push.',
    'kind', 'supply',
    'is_checked', true,
    'updated_at', '2026-09-03T10:00:00Z',
    'deleted_at', '2026-09-03T10:00:00Z')));

select is((select body from public.visit_prep_items where id = tests.ulid(940)), '',
  'a supply tombstone carries the empty body sentinel, not the stale push body');
select is((select kind from public.visit_prep_items where id = tests.ulid(940)), 'supply',
  'a supply tombstone preserves its kind (identity survives the delete)');

select * from finish();
rollback;
