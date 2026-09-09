-- Coverage for the first-class PMS marker (Issue #220):
-- day_entries.pms round-trips through sync_push like any other day-level
-- field, an old client's payload that omits the pms key never clears an
-- already-stored marker (the v_row ? 'pms' containment guard, the
-- U1/#131/#159 pattern), every tombstone-producing site clears the marker
-- (direct soft-delete, the same-date resolver's loser tombstoning, and the
-- incoming-loses branch), and day_entries_tombstone_pms_check is the
-- structural backstop independent of the RPC. sync_push_test.sql and
-- guardian_sync_push_test.sql remain the characterization suite for
-- everything else sync_push does and must keep passing unmodified.
begin;
select plan(15);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t0', '2026-09-01T09:00:00Z'),
  ('t1', '2026-09-01T10:00:00Z'),
  ('t2', '2026-09-01T11:00:00Z'),
  ('t3', '2026-09-01T12:00:00Z'),
  ('t4', '2026-09-01T13:00:00Z');
grant select on table ts to authenticated;

create function pg_temp.ts_txt(k text) returns text language sql as
  $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') from ts where ts.k = $1 $$;
create function pg_temp.ts_at(k text) returns timestamptz language sql as
  $$ select t from ts where ts.k = $1 $$;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.resolved_row(n text, p_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'id' = p_id limit 1 $$;

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile (P1), shared with Dad (co-parent).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(901), 'co_parent', 'Dad',
  '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', 'Dad'
);

-- ---------------------------------------------------------------------------
-- Round-trip: Mom pushes a PMS day; the marker is stored and handed back
-- in the resolved row.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_push_1', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-04',
    'tz', 'UTC', 'flow', 'none', 'tags', '[]'::jsonb,
    'pms', true,
    'updated_at', pg_temp.ts_txt('t1'))));

select is(
  (select pms from public.day_entries where id = tests.ulid(910)),
  true,
  'the PMS marker is stored on the day entry'
);
-- A declined push echoes the server copy, proving the marker rides the
-- RPC's resolved-row shape too (an accepted insert is never echoed).
insert into r select 'mom_declined', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-04',
    'tz', 'UTC', 'flow', 'none', 'tags', '[]'::jsonb,
    'pms', false,
    'updated_at', pg_temp.ts_txt('t0'))));
select is(
  (select e ->> 'pms' from jsonb_array_elements(pg_temp.resp('mom_declined') -> 'resolved') e
   where e ->> 'id' = tests.ulid(910)),
  'true',
  'the resolved row round-trips the stored PMS marker'
);
select is(
  (select pms from public.day_entries where id = tests.ulid(910)),
  true,
  'the declined (older) push did not overwrite the stored marker'
);

-- A PMS day needs no flow at all: the marker rides an otherwise-empty day.
select is(
  (select flow from public.day_entries where id = tests.ulid(910)),
  'none',
  'a PMS-only day stores fine with flow = none'
);

-- ---------------------------------------------------------------------------
-- Containment guard: an old client (pre-#220) pushes a newer update for
-- the same row WITHOUT a pms key at all -- the stored marker survives.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'old_client_update', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-04',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'crampy',
    'updated_at', pg_temp.ts_txt('t2'))));

select is(
  (select pms from public.day_entries where id = tests.ulid(910)),
  true,
  'an old client''s pms-less update does not clear an already-stored marker (containment guard)'
);
select is(
  (select flow from public.day_entries where id = tests.ulid(910)),
  'medium',
  'the old client''s other fields still land normally'
);

-- An explicit pms: false on a newer update does clear it.
insert into r select 'explicit_false', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-04',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb,
    'pms', false,
    'updated_at', pg_temp.ts_txt('t3'))));

select is(
  (select pms from public.day_entries where id = tests.ulid(910)),
  false,
  'an explicit pms: false on a newer update clears the marker'
);

-- ---------------------------------------------------------------------------
-- Tombstone: the direct soft-delete branch clears the marker, so a
-- deleted row carries no health content.
-- ---------------------------------------------------------------------------
insert into r select 'mom_pms_again', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'none', 'tags', '[]'::jsonb,
    'pms', true,
    'updated_at', pg_temp.ts_txt('t2'))));

insert into r select 'mom_delete', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'none', 'tags', '[]'::jsonb,
    'deleted_at', pg_temp.ts_txt('t3'),
    'updated_at', pg_temp.ts_txt('t3'))));

select is(
  (select pms from public.day_entries where id = tests.ulid(920)),
  false,
  'a direct tombstone push clears the PMS marker'
);

-- ---------------------------------------------------------------------------
-- Same-date resolver: Mom logs a PMS day; Dad's newer row for the same
-- date wins. The loser is a payload-free tombstone (marker cleared), and
-- the winner keeps its own marker value (last-writer-wins, no union --
-- pms is a single boolean, not an array).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'dad_push', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(930), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'none', 'tags', '["bloating"]'::jsonb,
    'pms', true,
    'updated_at', pg_temp.ts_txt('t3'))));

select tests.authenticate_as('mom');
insert into r select 'mom_push_2', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(931), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'none', 'tags', '["cramps"]'::jsonb,
    'pms', true,
    'updated_at', pg_temp.ts_txt('t4'))));

select is(
  (select pms from public.day_entries where id = tests.ulid(930)),
  false,
  'the same-date loser is a payload-free tombstone - PMS marker cleared'
);
select is(
  (select deleted_at from public.day_entries where id = tests.ulid(930)),
  pg_temp.ts_at('t4'),
  'the loser is tombstoned at the winner''s updated_at'
);
select is(
  (select pms from public.day_entries where id = tests.ulid(931)),
  true,
  'the winner keeps its own PMS marker (last-writer-wins, no merge needed for a boolean)'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(931)),
  '["bloating", "cramps"]'::jsonb,
  'the tags union is unchanged by the PMS marker work'
);

-- ---------------------------------------------------------------------------
-- The structural backstop: NO write path can leave payload on a
-- tombstone, even one that forgets sync_push's history entirely.
-- ---------------------------------------------------------------------------
select lives_ok(
  $$ update public.day_entries set deleted_at = null, pms = true where id = tests.ulid(920) $$,
  'reviving a tombstone with pms = true is a legitimate live write'
);
select throws_ok(
  $$ update public.day_entries set pms = true where id = tests.ulid(930) $$,
  '23514',
  'new row for relation "day_entries" violates check constraint "day_entries_tombstone_pms_check"',
  'a direct write cannot put a PMS marker back on a tombstoned row (CHECK backstop)'
);
select is(
  (select count(*) from public.day_entries where deleted_at is not null and pms = true),
  0::bigint,
  'no tombstone in the table carries a PMS marker'
);

select * from finish();
rollback;
