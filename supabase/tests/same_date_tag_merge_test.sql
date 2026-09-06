-- Coverage for the same-date tag merge (Issue #3 gap-closure plan, Unit U4):
-- merge_tag_arrays itself, and sync_push's same-date resolver unioning tags
-- onto the surviving row instead of destroying the loser's tags outright.
-- supabase/tests/sync_push_test.sql (87 assertions, one updated for this
-- plan - see its "equal ts" block) and guardian_sync_push_test.sql (26
-- assertions, untouched) are the characterization suite for everything else
-- sync_push does and must keep passing unmodified.
begin;
select plan(25);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create temp table ts (k text primary key, t timestamptz);
insert into ts values
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
select tests.create_supabase_user('doctor');

-- ---------------------------------------------------------------------------
-- merge_tag_arrays: the pure helper, independent of sync_push.
-- ---------------------------------------------------------------------------
select is(
  public.merge_tag_arrays('["b", "a"]'::jsonb, '["c"]'::jsonb),
  '["a", "b", "c"]'::jsonb,
  'merge_tag_arrays unions two disjoint arrays, sorted, no duplicates'
);
select is(
  public.merge_tag_arrays('["c"]'::jsonb, '["b", "a"]'::jsonb),
  public.merge_tag_arrays('["b", "a"]'::jsonb, '["c"]'::jsonb),
  'merge_tag_arrays is commutative'
);
select is(
  public.merge_tag_arrays(public.merge_tag_arrays('["a"]'::jsonb, '["b"]'::jsonb), '["a", "b"]'::jsonb),
  public.merge_tag_arrays('["a"]'::jsonb, '["b"]'::jsonb),
  'merge_tag_arrays is idempotent when applied to its own output (R9)'
);
select is(public.merge_tag_arrays(null, null), '[]'::jsonb, 'merge_tag_arrays(null, null) = []');
select is(public.merge_tag_arrays('[]'::jsonb, '[]'::jsonb), '[]'::jsonb, 'merge_tag_arrays([], []) = []');
select is(public.merge_tag_arrays('[]'::jsonb, '["a"]'::jsonb), '["a"]'::jsonb,
  'merge_tag_arrays([], ["a"]) = ["a"]');
select is(public.merge_tag_arrays('["a", "a"]'::jsonb, '["a"]'::jsonb), '["a"]'::jsonb,
  'merge_tag_arrays deduplicates a tag already present on both sides');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile (P1), shared with Dad (co-parent) and Doctor (viewer).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select public.create_guardian_invitation(
  tests.ulid(901), 'co_parent', 'Dad',
  '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', 48
);
select public.create_guardian_invitation(
  tests.ulid(901), 'viewer', 'Doctor',
  '9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a9a', 'Dad'
);
select tests.authenticate_as('doctor');
select public.accept_guardian_invitation(
  '9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b', 'Doctor'
);

-- ---------------------------------------------------------------------------
-- Mom logs cramps offline; Dad later logs heavy_flow offline for the same
-- date as a distinct row id. Mom's push lands first (older), Dad's second
-- (newer, wins). R7/R12: the surviving row carries both tags; the loser is
-- a payload-free tombstone.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_push', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom''s note',
    'updated_at', pg_temp.ts_txt('t1'))));

select tests.authenticate_as('dad');
insert into r select 'dad_push', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["heavy_flow"]'::jsonb, 'note', 'dad''s note',
    'updated_at', pg_temp.ts_txt('t2'))));

select is(
  (select tags from public.day_entries where id = tests.ulid(911)),
  '["cramps", "heavy_flow"]'::jsonb,
  'R7: the surviving (newer) row carries the union of both caregivers'' tags'
);
select is(
  (select note from public.day_entries where id = tests.ulid(911)),
  'dad''s note',
  'R8: the winner''s note is unaffected by the tag merge (last-writer-wins)'
);
select is(
  (select flow from public.day_entries where id = tests.ulid(911)),
  'heavy',
  'R8: the winner''s flow is unaffected by the tag merge (last-writer-wins)'
);
select is(
  (select deleted_at from public.day_entries where id = tests.ulid(910)),
  pg_temp.ts_at('t2'),
  'the loser is tombstoned at the winner''s updated_at'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(910)),
  '[]'::jsonb,
  'R12: the loser is still a payload-free tombstone - tags cleared'
);
select is(
  (select note from public.day_entries where id = tests.ulid(910)),
  null,
  'R12: the loser is still a payload-free tombstone - note cleared'
);
select is(
  (select logged_by_user_id from public.day_entries where id = tests.ulid(911)),
  tests.get_supabase_uid('dad'),
  'logged_by_user_id on the surviving row is unchanged (Dad logged it)'
);
select is(
  (select last_modified_by_user_id from public.day_entries where id = tests.ulid(911)),
  tests.get_supabase_uid('dad'),
  'last_modified_by_user_id is the pushing caller (attribution triggers still fire)'
);
select is(
  pg_temp.resolved_row('dad_push', tests.ulid(910)) -> 'tags',
  '[]'::jsonb,
  'R11: resolved carries the loser''s server copy (still payload-free)'
);

-- ---------------------------------------------------------------------------
-- R9: reversed push order for an equivalent pair converges to the same
-- union. Dad pushes first this time (older), Mom pushes second (newer,
-- wins) - the winner's tags still end up as the union of both.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'dad_first', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["heavy_flow"]'::jsonb, 'note', 'dad again',
    'updated_at', pg_temp.ts_txt('t1'))));
select tests.authenticate_as('mom');
insert into r select 'mom_second', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(913), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom again',
    'updated_at', pg_temp.ts_txt('t2'))));
select is(
  (select tags from public.day_entries where id = tests.ulid(913)),
  '["cramps", "heavy_flow"]'::jsonb,
  'R9: the reversed push order converges to the identical tag union'
);

-- ---------------------------------------------------------------------------
-- Re-pushing an already-merged row (idempotent, does not duplicate tags and
-- does not resurrect the tombstoned loser).
-- ---------------------------------------------------------------------------
insert into r select 'mom_repush', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(913), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps", "heavy_flow"]'::jsonb, 'note', 'mom again',
    'updated_at', pg_temp.ts_txt('t2'))));
select is(
  (select tags from public.day_entries where id = tests.ulid(913)),
  '["cramps", "heavy_flow"]'::jsonb,
  'idempotent re-push does not duplicate tags'
);
select is(
  (select deleted_at from public.day_entries where id = tests.ulid(912)),
  pg_temp.ts_at('t2'),
  'idempotent re-push does not resurrect the tombstoned loser'
);

-- ---------------------------------------------------------------------------
-- R10: the same-id convergence path is untouched - removing a tag from an
-- existing (non-colliding) entry still removes it.
-- ---------------------------------------------------------------------------
insert into r select 'same_id_setup', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["a", "b"]'::jsonb, 'note', 'x',
    'updated_at', pg_temp.ts_txt('t1'))));
insert into r select 'same_id_removed', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["a"]'::jsonb, 'note', 'x',
    'updated_at', pg_temp.ts_txt('t2'))));
select is(
  (select tags from public.day_entries where id = tests.ulid(920)),
  '["a"]'::jsonb,
  'R10: a same-id update that removes a tag still removes it - no union on the same-id path'
);

-- ---------------------------------------------------------------------------
-- A viewer pushing into a same-date collision is rejected before any merge
-- happens - the role check still runs first.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doctor');
insert into r select 'viewer_push', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["viewer-tag"]'::jsonb,
    'updated_at', pg_temp.ts_txt('t3'))));
select is(
  jsonb_array_length(pg_temp.resp('viewer_push') -> 'rejected'),
  1,
  'a viewer''s write into a same-date collision is rejected before any merge'
);
select is(
  (select tags from public.day_entries where id = tests.ulid(913)),
  '["cramps", "heavy_flow"]'::jsonb,
  'the rejected viewer write left the live row''s tags untouched'
);

-- ---------------------------------------------------------------------------
-- Three-way collision: three distinct rows on one date converge to the
-- union of all three regardless of push order.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'three_way', public.sync_push('[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(930), 'profile_id', tests.ulid(901), 'local_date', '2026-09-08',
      'tz', 'UTC', 'flow', 'none', 'tags', '["a"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(931), 'profile_id', tests.ulid(901), 'local_date', '2026-09-08',
      'tz', 'UTC', 'flow', 'none', 'tags', '["b"]'::jsonb, 'updated_at', pg_temp.ts_txt('t2')),
    jsonb_build_object('id', tests.ulid(932), 'profile_id', tests.ulid(901), 'local_date', '2026-09-08',
      'tz', 'UTC', 'flow', 'none', 'tags', '["c"]'::jsonb, 'updated_at', pg_temp.ts_txt('t3'))
  ));
select is(
  (select tags from public.day_entries where id = tests.ulid(932)),
  '["a", "b", "c"]'::jsonb,
  'three-way collision (ascending push order) converges to the union of all three'
);

insert into r select 'three_way_desc', public.sync_push('[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(940), 'profile_id', tests.ulid(901), 'local_date', '2026-09-09',
      'tz', 'UTC', 'flow', 'none', 'tags', '["c"]'::jsonb, 'updated_at', pg_temp.ts_txt('t3')),
    jsonb_build_object('id', tests.ulid(941), 'profile_id', tests.ulid(901), 'local_date', '2026-09-09',
      'tz', 'UTC', 'flow', 'none', 'tags', '["b"]'::jsonb, 'updated_at', pg_temp.ts_txt('t2')),
    jsonb_build_object('id', tests.ulid(942), 'profile_id', tests.ulid(901), 'local_date', '2026-09-09',
      'tz', 'UTC', 'flow', 'none', 'tags', '["a"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))
  ));
select is(
  (select count(*) from public.day_entries
    where profile_id = tests.ulid(901) and local_date = '2026-09-09' and deleted_at is null),
  1::bigint,
  'three-way collision (descending push order): exactly one live row remains'
);
select is(
  (select tags from public.day_entries
    where profile_id = tests.ulid(901) and local_date = '2026-09-09' and deleted_at is null),
  '["a", "b", "c"]'::jsonb,
  'three-way collision (descending push order) converges to the identical union (R9)'
);

rollback;
