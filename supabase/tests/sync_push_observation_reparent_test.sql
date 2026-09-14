-- Issue #639 · LLA-036 (P1): same-date identity convergence must preserve
-- the losing day entry's structured observations. Proves the resolver
-- reparents the loser's live observations onto the surviving winner before
-- the loser's tombstone cascade would wipe them, in both winner directions,
-- and leaves a colliding (category, code) row alone (the partial unique
-- index owns that dedup).
begin;
select plan(19);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;
create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t0', '2026-09-01T09:00:00Z'), ('t1', '2026-09-01T10:00:00Z'),
  ('t2', '2026-09-01T11:00:00Z'), ('t3', '2026-09-01T12:00:00Z');
grant select on table ts to authenticated;
create function pg_temp.ts_txt(k text) returns text language sql as
  $$ select to_char(t at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') from ts where ts.k = $1 $$;
create function pg_temp.ts_at(k text) returns timestamptz language sql as
  $$ select t from ts where ts.k = $1 $$;

select tests.create_supabase_user('user_a');
select tests.authenticate_as('user_a');

insert into r select 'setup', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Alice', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', null)),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);
select is(pg_temp.resp('setup') -> 'rejected', '[]'::jsonb, 'setup: nothing rejected');

-- ---------------------------------------------------------------------------
-- Direction A: the incoming (newer) row wins over the stored (older) row.
-- The stored loser's disjoint observations must be reparented onto the
-- incoming winner, still live.
-- ---------------------------------------------------------------------------
insert into r select 'a1', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(101), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'light', 'tags', '["cramps"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))),
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(201), 'day_entry_id', tests.ulid(101), 'profile_id', tests.ulid(1),
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'cramps', 'code', 'mild', 'value_num', 1, 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(202), 'day_entry_id', tests.ulid(101), 'profile_id', tests.ulid(1),
      'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'energy', 'code', 'low', 'value_num', 0, 'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('a1') -> 'rejected', '[]'::jsonb, 'A1: stored row + obs accepted');

insert into r select 'a2', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["headache"]'::jsonb, 'updated_at', pg_temp.ts_txt('t2'))),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(203), 'day_entry_id', tests.ulid(102), 'profile_id', tests.ulid(1),
    'local_date', '2026-09-05', 'tz', 'UTC', 'category', 'sleep', 'code', 'bad', 'value_num', 0, 'updated_at', pg_temp.ts_txt('t2'))));
select is(pg_temp.resp('a2') -> 'rejected', '[]'::jsonb, 'A2: incoming winner accepted');

select is((select deleted_at from public.day_entries where id = tests.ulid(102)), null,
  'A: newer incoming stays live');
select is((select deleted_at from public.day_entries where id = tests.ulid(101)), pg_temp.ts_at('t2'),
  'A: older stored row is tombstoned at winner''s timestamp');

select is((select day_entry_id from public.observations where id = tests.ulid(201)), tests.ulid(102),
  'A: stored loser''s observation 201 reparented to winner');
select is((select deleted_at from public.observations where id = tests.ulid(201)), null,
  'A: reparented observation 201 is still live');
select is((select day_entry_id from public.observations where id = tests.ulid(202)), tests.ulid(102),
  'A: stored loser''s observation 202 reparented to winner');
select is((select deleted_at from public.observations where id = tests.ulid(202)), null,
  'A: reparented observation 202 is still live');
select is((select day_entry_id from public.observations where id = tests.ulid(203)), tests.ulid(102),
  'A: winner''s own observation stays on winner');

-- ---------------------------------------------------------------------------
-- Direction B: the incoming (older) row loses to the stored (newer) row.
-- The stored winner keeps its observations; the losing incoming row is
-- tombstoned and carries no surviving observations.
-- ---------------------------------------------------------------------------
insert into r select 'b1', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(112), 'profile_id', tests.ulid(1), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'light', 'tags', '["cramps"]'::jsonb, 'updated_at', pg_temp.ts_txt('t2'))),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(212), 'day_entry_id', tests.ulid(112), 'profile_id', tests.ulid(1),
    'local_date', '2026-09-06', 'tz', 'UTC', 'category', 'mood', 'code', 'low', 'updated_at', pg_temp.ts_txt('t2'))));
select is(pg_temp.resp('b1') -> 'rejected', '[]'::jsonb, 'B1: stored row accepted');

insert into r select 'b2', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(111), 'profile_id', tests.ulid(1), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'none', 'tags', '[]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is((select deleted_at from public.day_entries where id = tests.ulid(112)), null,
  'B: stored (newer) row stays live');
select is((select deleted_at from public.day_entries where id = tests.ulid(111)), pg_temp.ts_at('t2'),
  'B: incoming (older) row is tombstoned');
select is((select day_entry_id from public.observations where id = tests.ulid(212)), tests.ulid(112),
  'B: stored winner keeps its own observation');

-- ---------------------------------------------------------------------------
-- Collision: a loser observation whose (category, code) already exists live
-- on the winner is left behind (the partial unique index owns that dedup),
-- never reparented, and is cascade-wiped with its tombstoned parent.
-- ---------------------------------------------------------------------------
insert into r select 'c1', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(121), 'profile_id', tests.ulid(1), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '[]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(221), 'day_entry_id', tests.ulid(121), 'profile_id', tests.ulid(1),
    'local_date', '2026-09-07', 'tz', 'UTC', 'category', 'cramps', 'code', 'mild', 'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('c1') -> 'rejected', '[]'::jsonb, 'C1: first row accepted');

insert into r select 'c2', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(122), 'profile_id', tests.ulid(1), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'medium', 'tags', '[]'::jsonb, 'updated_at', pg_temp.ts_txt('t2'))),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(222), 'day_entry_id', tests.ulid(122), 'profile_id', tests.ulid(1),
    'local_date', '2026-09-07', 'tz', 'UTC', 'category', 'cramps', 'code', 'mild', 'value_num', 2, 'updated_at', pg_temp.ts_txt('t2'))));
select is((select day_entry_id from public.observations where id = tests.ulid(222)), tests.ulid(122),
  'C: winner''s own observation stays on winner');
select is((select day_entry_id from public.observations where id = tests.ulid(221)), tests.ulid(122),
  'C: loser''s colliding observation is reparented onto winner');
select is((select deleted_at from public.observations where id = tests.ulid(221)), pg_temp.ts_at('t2'),
  'C: colliding pair resolved by same-date dedup -- loser (older) tombstoned');
select is((select deleted_at from public.observations where id = tests.ulid(222)), null,
  'C: winner''s (newer) colliding observation stays live');

select * from finish();
rollback;
