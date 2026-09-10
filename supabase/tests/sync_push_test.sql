-- sync_push RPC proof (plan U2: AE3, LWW guard, resolver, tombstones,
-- idempotency, payload user_id, opaque rejections, batch limits, anon).
begin;
select plan(162);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

-- handy timestamps
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

select tests.create_supabase_user('user_a');
select tests.create_supabase_user('user_b');

-- ---------------------------------------------------------------------------
-- profiles through sync_push: insert, LWW decline, tombstone without payload
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');

insert into r select 'p_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Alice', 'is_minor', false, 'sort_order', 0,
    'created_at', pg_temp.ts_txt('t1'), 'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', null)),
  '[]'::jsonb);
select is(pg_temp.resp('p_insert') -> 'rejected', '[]'::jsonb, 'profile insert: nothing rejected');
select is(pg_temp.resp('p_insert') -> 'resolved', '[]'::jsonb, 'profile insert: nothing resolved');
select is((select display_name from public.profiles where id = tests.ulid(1)), 'Alice', 'profile landed');
select ok((pg_temp.resp('p_insert') ->> 'server_now')::timestamptz
            between now() - interval '1 minute' and now() + interval '1 minute',
  'server_now is the server clock');

insert into r select 'p_older', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(1), 'display_name', 'Stale', 'updated_at', pg_temp.ts_txt('t0'))),
  '[]'::jsonb);
select is((select display_name from public.profiles where id = tests.ulid(1)), 'Alice',
  'older incoming profile does not overwrite');
select is(pg_temp.resolved_row('p_older', tests.ulid(1)) ->> 'display_name', 'Alice',
  'older incoming profile: server copy returned in resolved');
select is(pg_temp.resolved_row('p_older', tests.ulid(1)) ->> 'table', 'profiles',
  'resolved profile entries are tagged with their table');

insert into r select 'p_tomb', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2), 'display_name', 'Secret name', 'updated_at', pg_temp.ts_txt('t1'),
    'deleted_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is((select display_name from public.profiles where id = tests.ulid(2)), '',
  'a profile tombstone is stored with display_name = ''''');

-- ---------------------------------------------------------------------------
-- AE3: same date, greater updated_at wins
-- ---------------------------------------------------------------------------
insert into r select 'e1', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(101), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'America/New_York', 'flow', 'light', 'tags', '["cramps"]'::jsonb, 'note', 'first',
    'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', null)));
select is(pg_temp.resp('e1') -> 'rejected', '[]'::jsonb, 'first live entry: nothing rejected');
select is(pg_temp.resp('e1') -> 'resolved', '[]'::jsonb, 'first live entry: nothing resolved');

insert into r select 'e2', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["headache"]'::jsonb, 'note', 'second',
    'updated_at', pg_temp.ts_txt('t2'))));
select is(pg_temp.resp('e2') -> 'rejected', '[]'::jsonb, 'AE3: nothing rejected');
select is((select deleted_at from public.day_entries where id = tests.ulid(102)), null,
  'AE3: the greater-updated_at row stays live');
select is((select note from public.day_entries where id = tests.ulid(102)), 'second',
  'AE3: the winner keeps its payload');
select is((select deleted_at from public.day_entries where id = tests.ulid(101)), pg_temp.ts_at('t2'),
  'AE3: the loser is tombstoned at the winner''s updated_at');
select is((select updated_at from public.day_entries where id = tests.ulid(101)), pg_temp.ts_at('t2'),
  'AE3: the loser''s updated_at equals the winner''s');
select is((select note from public.day_entries where id = tests.ulid(101)), null,
  'AE3: the loser''s note is cleared');
select is((select tags from public.day_entries where id = tests.ulid(101)), '[]'::jsonb,
  'AE3: the loser''s tags are cleared');
select is(jsonb_array_length(pg_temp.resp('e2') -> 'resolved'), 1, 'AE3: exactly one resolved row');
select is((pg_temp.resolved_row('e2', tests.ulid(101)) ->> 'deleted_at')::timestamptz, pg_temp.ts_at('t2'),
  'AE3: resolved carries the loser with deleted_at = winner.updated_at');
select is(pg_temp.resolved_row('e2', tests.ulid(101)) -> 'note', 'null'::jsonb,
  'AE3: resolved loser has note = null');
select is(pg_temp.resolved_row('e2', tests.ulid(101)) -> 'tags', '[]'::jsonb,
  'AE3: resolved loser has tags = []');
select is(pg_temp.resolved_row('e2', tests.ulid(101)) ->> 'table', 'day_entries',
  'AE3: resolved day entries are tagged with their table');
select is((select count(*) from public.day_entries
            where profile_id = tests.ulid(1) and local_date = '2026-09-05' and deleted_at is null),
  1::bigint, 'AE3: exactly one live row for the date');

-- ---------------------------------------------------------------------------
-- AE3: equal updated_at, the smaller ULID wins (both directions)
-- ---------------------------------------------------------------------------
-- stored 104 (larger), incoming 103 (smaller) -> incoming wins
insert into r select 'eq_a1', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(104), 'profile_id', tests.ulid(1), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'none', 'note', 'stored-larger', 'updated_at', pg_temp.ts_txt('t1'))));
insert into r select 'eq_a2', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(103), 'profile_id', tests.ulid(1), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'none', 'note', 'incoming-smaller', 'updated_at', pg_temp.ts_txt('t1'))));
select is((select deleted_at from public.day_entries where id = tests.ulid(103)), null,
  'equal ts: the smaller incoming ULID stays live');
select is((select deleted_at from public.day_entries where id = tests.ulid(104)), pg_temp.ts_at('t1'),
  'equal ts: the larger stored ULID is tombstoned at the winner''s updated_at');
select is((pg_temp.resolved_row('eq_a2', tests.ulid(104)) ->> 'deleted_at')::timestamptz, pg_temp.ts_at('t1'),
  'equal ts: resolved carries the stored loser');

-- stored 105 (smaller), incoming 106 (larger) -> incoming loses, stored as tombstone
insert into r select 'eq_b1', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(105), 'profile_id', tests.ulid(1), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'none', 'note', 'stored-smaller', 'updated_at', pg_temp.ts_txt('t1'))));
create temp table sv105 as select updated_at from public.day_entries where id = tests.ulid(105);
insert into r select 'eq_b2', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(106), 'profile_id', tests.ulid(1), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'heavy', 'note', 'incoming-larger', 'tags', '["x"]'::jsonb,
    'updated_at', pg_temp.ts_txt('t1'))));
select is((select deleted_at from public.day_entries where id = tests.ulid(105)), null,
  'equal ts: the smaller stored ULID stays live');
-- Issue #3 gap-closure plan (U4, R7/R11): the surviving winner now receives
-- the incoming loser's tags as a set union - it is no longer left untouched
-- ("not rewritten") the way it was before this plan. Its updated_at is
-- still left alone by the merge (only tags + attribution change).
select is((select updated_at from public.day_entries where id = tests.ulid(105)),
  (select updated_at from sv105),
  'equal ts: the stored winner''s updated_at is undisturbed by the tag merge (U4)');
select is((select tags from public.day_entries where id = tests.ulid(105)), '["x"]'::jsonb,
  'equal ts: the incoming loser''s tags are unioned onto the surviving winner (R7, U4)');
select is((select deleted_at from public.day_entries where id = tests.ulid(106)), pg_temp.ts_at('t1'),
  'equal ts: the larger incoming ULID lands as a tombstone at the winner''s updated_at');
select is((select note from public.day_entries where id = tests.ulid(106)), null,
  'equal ts: the incoming loser is stored without note');
select is((select tags from public.day_entries where id = tests.ulid(106)), '[]'::jsonb,
  'equal ts: the incoming loser is stored without tags');
select is((pg_temp.resolved_row('eq_b2', tests.ulid(106)) ->> 'deleted_at')::timestamptz, pg_temp.ts_at('t1'),
  'equal ts: resolved carries the incoming loser''s server copy');
select is(pg_temp.resolved_row('eq_b2', tests.ulid(106)) -> 'note', 'null'::jsonb,
  'equal ts: resolved incoming loser has note = null');

-- ---------------------------------------------------------------------------
-- LWW guard per id
-- ---------------------------------------------------------------------------
create temp table sv102 as select server_version from public.day_entries where id = tests.ulid(102);

insert into r select 'lww_older', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'none', 'note', 'stale', 'updated_at', pg_temp.ts_txt('t0'))));
select is((select note from public.day_entries where id = tests.ulid(102)), 'second',
  'older incoming leaves the stored row unchanged');
select is((select server_version from public.day_entries where id = tests.ulid(102)),
  (select server_version from sv102), 'older incoming does not rewrite the row');
select is(pg_temp.resolved_row('lww_older', tests.ulid(102)) ->> 'note', 'second',
  'older incoming: stored copy returned in resolved');

insert into r select 'lww_equal_live', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'none', 'note', 'other-device', 'updated_at', pg_temp.ts_txt('t2'))));
select is((select note from public.day_entries where id = tests.ulid(102)), 'second',
  'equal-and-live incoming leaves the stored row unchanged');
select is(pg_temp.resolved_row('lww_equal_live', tests.ulid(102)) ->> 'note', 'second',
  'equal-and-live incoming: stored copy returned in resolved');

insert into r select 'lww_equal_tomb', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'note', 'secret', 'tags', '["private"]'::jsonb,
    'updated_at', pg_temp.ts_txt('t2'), 'deleted_at', pg_temp.ts_txt('t2'))));
select is((select deleted_at from public.day_entries where id = tests.ulid(102)), pg_temp.ts_at('t2'),
  'equal-ts incoming tombstone wins');
select is((select note from public.day_entries where id = tests.ulid(102)), null,
  'a pushed tombstone is stored without note');
select is((select tags from public.day_entries where id = tests.ulid(102)), '[]'::jsonb,
  'a pushed tombstone is stored without tags');
select is(pg_temp.resp('lww_equal_tomb') -> 'resolved', '[]'::jsonb,
  'an accepted tombstone is not echoed back');

-- ---------------------------------------------------------------------------
-- Revival: a newer live write to a tombstoned id revives it with its own
-- payload and re-runs the resolver against the other live row for the date
-- ---------------------------------------------------------------------------
insert into r select 'rev_other', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(107), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'spotting', 'note', 'newcomer', 'updated_at', pg_temp.ts_txt('t2'))));
select is(pg_temp.resp('rev_other') -> 'resolved', '[]'::jsonb,
  'a live row for a date whose other rows are tombstones resolves nothing');

insert into r select 'revive', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(102), 'profile_id', tests.ulid(1), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'heavy', 'note', 'revived', 'tags', '["a"]'::jsonb,
    'updated_at', pg_temp.ts_txt('t3'))));
select is((select deleted_at from public.day_entries where id = tests.ulid(102)), null,
  'revival: the tombstoned id is live again');
select is((select note from public.day_entries where id = tests.ulid(102)), 'revived',
  'revival: the new payload is stored');
select is((select tags from public.day_entries where id = tests.ulid(102)), '["a"]'::jsonb,
  'revival: the new tags are stored');
select is((select deleted_at from public.day_entries where id = tests.ulid(107)), pg_temp.ts_at('t3'),
  'revival: the resolver tombstones the other live row at the winner''s updated_at');
select is(pg_temp.resolved_row('revive', tests.ulid(107)) -> 'note', 'null'::jsonb,
  'revival: the resolved loser carries no note');
select is((select count(*) from public.day_entries
            where profile_id = tests.ulid(1) and local_date = '2026-09-05' and deleted_at is null),
  1::bigint, 'revival: still exactly one live row for the date');

-- ---------------------------------------------------------------------------
-- Idempotency: the same payload twice changes nothing the second time
-- ---------------------------------------------------------------------------
create temp table idem_payload as select jsonb_build_array(
  jsonb_build_object(
    'id', tests.ulid(108), 'profile_id', tests.ulid(1), 'local_date', '2026-09-08',
    'tz', 'UTC', 'flow', 'light', 'note', 'idem', 'tags', '["b"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1')),
  jsonb_build_object(
    'id', tests.ulid(109), 'profile_id', tests.ulid(1), 'local_date', '2026-09-09',
    'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'), 'deleted_at', pg_temp.ts_txt('t1'))
  ) as p;
insert into r select 'idem1', public.sync_push('[]'::jsonb, (select p from idem_payload));
create temp table idem_snap as
  select id, server_version, updated_at, deleted_at, note, tags, flow
    from public.day_entries where id in (tests.ulid(108), tests.ulid(109));
insert into r select 'idem2', public.sync_push('[]'::jsonb, (select p from idem_payload));
select is(pg_temp.resp('idem2') -> 'rejected', '[]'::jsonb, 'idempotent: nothing rejected on replay');
select results_eq(
  $$select id, server_version, updated_at, deleted_at, note, tags, flow
      from public.day_entries where id in (tests.ulid(108), tests.ulid(109)) order by id$$,
  $$select id, server_version, updated_at, deleted_at, note, tags, flow from idem_snap order by id$$,
  'idempotent: replaying the payload rewrites nothing (server_version unchanged)');
select is(jsonb_array_length(pg_temp.resp('idem2') -> 'resolved'), 1,
  'idempotent: only the equal-and-live row is echoed back, the identical tombstone is silent');
select is(pg_temp.resolved_row('idem2', tests.ulid(108)) ->> 'note', 'idem',
  'idempotent: the echoed row is the stored copy');

-- ---------------------------------------------------------------------------
-- Per-row rejections are opaque and leave the rest of the batch intact
-- ---------------------------------------------------------------------------
insert into r select 'bad_rows', public.sync_push(
  jsonb_build_array(
    jsonb_build_object('id', 'not-a-ulid', 'display_name', 'x', 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(3), 'display_name', repeat('d', 81), 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(4), 'display_name', 'ok', 'updated_at', pg_temp.ts_txt('t1'), 'bogus', 1),
    jsonb_build_object('id', tests.ulid(5), 'display_name', 'Fine', 'updated_at', pg_temp.ts_txt('t1'))),
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(110), 'profile_id', tests.ulid(1), 'local_date', '2026-09-10',
      'tz', 'UTC', 'flow', 'gushing', 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(111), 'profile_id', tests.ulid(1), 'local_date', '2026-09-11',
      'tz', 'UTC', 'flow', 'none', 'note', repeat('n', 2001), 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(112), 'profile_id', tests.ulid(1), 'local_date', 'yesterday',
      'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(113), 'profile_id', tests.ulid(1), 'local_date', '2026-09-13',
      'tz', 'UTC', 'flow', 'none', 'tags', '{"a":1}'::jsonb, 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(114), 'profile_id', tests.ulid(1), 'local_date', '2026-09-14',
      'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'), 'created_at', pg_temp.ts_txt('t1')),
    '"just a string"'::jsonb,
    jsonb_build_object('id', tests.ulid(115), 'profile_id', tests.ulid(1), 'local_date', '2026-09-15',
      'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'))));
select is(jsonb_array_length(pg_temp.resp('bad_rows') -> 'rejected'), 9,
  'per-row: bad id, over-length name, unknown key, bad flow, CHECK violation, bad date, non-array tags, server-only key, non-object are each rejected');
select is((select display_name from public.profiles where id = tests.ulid(5)), 'Fine',
  'per-row: the valid profile in the same batch lands');
select is((select count(*) from public.day_entries where id = tests.ulid(115)), 1::bigint,
  'per-row: the valid day entry in the same batch lands');
select is((select count(*) from public.day_entries where id in (tests.ulid(110), tests.ulid(111), tests.ulid(112), tests.ulid(113), tests.ulid(114))),
  0::bigint, 'per-row: none of the rejected day entries land');
-- Issue #95 processes each payload loop in row-key order (deterministic lock
-- acquisition), so the rejected array follows key order, not payload order -
-- assert containment, not position.
select ok(pg_temp.resp('bad_rows') -> 'rejected'
    @> jsonb_build_array(jsonb_build_object('id', 'not-a-ulid', 'rejected', true)),
  'a rejected entry is exactly {id, rejected: true}');
select is((select count(*) from jsonb_array_elements(pg_temp.resp('bad_rows') -> 'rejected') e
            where e - 'id' <> '{"rejected": true}'::jsonb or not (e ? 'id')),
  0::bigint, 'every rejected entry has the same opaque shape regardless of cause');

-- ---------------------------------------------------------------------------
-- Batch-level rejections
-- ---------------------------------------------------------------------------
select throws_ok($$select public.sync_push('{}'::jsonb, '[]'::jsonb)$$, '22023', null,
  'a non-array p_profiles rejects the whole call');
select throws_ok($$select public.sync_push('[]'::jsonb, '"x"'::jsonb)$$, '22023', null,
  'a non-array p_day_entries rejects the whole call');
select throws_ok($$select public.sync_push(null, '[]'::jsonb)$$, '22023', null,
  'a null argument rejects the whole call');
select throws_ok(
  $$select public.sync_push('[]'::jsonb,
      (select jsonb_agg(jsonb_build_object('id', tests.ulid(2000 + g), 'profile_id', tests.ulid(1),
          'local_date', ('2020-01-01'::date + g)::text, 'tz', 'UTC', 'flow', 'none',
          'updated_at', '2026-09-01T10:00:00Z')) from generate_series(1, 501) g))$$,
  '22023', null, 'a batch of 501 rows rejects the whole call');
select lives_ok(
  $$select public.sync_push('[]'::jsonb,
      (select jsonb_agg(jsonb_build_object('id', tests.ulid(4000 + g), 'profile_id', tests.ulid(1),
          'local_date', ('2010-01-01'::date + g)::text, 'tz', 'UTC', 'flow', 'none',
          'updated_at', '2026-09-01T10:00:00Z')) from generate_series(1, 500) g))$$,
  'a batch of exactly 500 rows is accepted');

-- ---------------------------------------------------------------------------
-- As B: payload user_id is ignored, A's ULIDs are opaque
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select tests.authenticate_as('user_b');

insert into r select 'b_uid', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(11), 'user_id', tests.get_supabase_uid('user_a'), 'server_version', 1,
    'display_name', 'Bob', 'updated_at', pg_temp.ts_txt('t1'))),
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(12), 'user_id', tests.get_supabase_uid('user_a'), 'server_version', 1,
    'profile_id', tests.ulid(11), 'local_date', '2026-09-01', 'tz', 'UTC', 'flow', 'none',
    'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('b_uid') -> 'rejected', '[]'::jsonb, 'payload user_id: rows are not rejected');
select is((select user_id from public.profiles where id = tests.ulid(11)), tests.get_supabase_uid('user_b'),
  'payload user_id = A: the profile lands under B');
select is((select user_id from public.day_entries where id = tests.ulid(12)), tests.get_supabase_uid('user_b'),
  'payload user_id = A: the day entry lands under B');
select isnt((select server_version from public.profiles where id = tests.ulid(11)), 1::bigint,
  'payload server_version is ignored');

-- 499 valid rows plus one that points at A's profile ULID
insert into r select 'b_batch', public.sync_push('[]'::jsonb,
  (select jsonb_agg(jsonb_build_object('id', tests.ulid(1000 + g), 'profile_id', tests.ulid(11),
      'local_date', ('2020-01-01'::date + g)::text, 'tz', 'UTC', 'flow', 'none',
      'updated_at', pg_temp.ts_txt('t1'))) from generate_series(1, 499) g)
  || jsonb_build_array(jsonb_build_object('id', tests.ulid(1999), 'profile_id', tests.ulid(1),
      'local_date', '2026-09-20', 'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'))));
select is((select count(*) from public.day_entries where id = any (select tests.ulid(1000 + g) from generate_series(1, 499) g)),
  499::bigint, 'batch with one foreign ULID: the 499 valid rows land');
select is((select count(*) from public.day_entries where id = tests.ulid(1999)), 0::bigint,
  'batch with one foreign ULID: the row pointing at A''s profile does not land');
select is(jsonb_array_length(pg_temp.resp('b_batch') -> 'rejected'), 1,
  'batch with one foreign ULID: exactly one rejected entry');
select is(pg_temp.resp('b_batch') -> 'rejected' -> 0, jsonb_build_object('id', tests.ulid(1999), 'rejected', true),
  'the foreign-ULID rejection is the opaque {id, rejected: true} entry');

insert into r select 'b_malformed', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object('id', tests.ulid(1998), 'profile_id', tests.ulid(11),
    'local_date', '2026-09-21', 'tz', 'UTC', 'flow', 'nope', 'updated_at', pg_temp.ts_txt('t1'))));
select is((pg_temp.resp('b_batch') -> 'rejected' -> 0) - 'id', (pg_temp.resp('b_malformed') -> 'rejected' -> 0) - 'id',
  'the foreign-ULID rejection is byte-identical in shape to a malformed-row rejection');
select is(
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.resp('b_batch') -> 'rejected' -> 0) k),
  (select array_agg(k order by k) from jsonb_object_keys(pg_temp.resp('b_malformed') -> 'rejected' -> 0) k),
  'rejected entries expose the same keys regardless of cause');

-- B pushing A's profile id as an own row is rejected (globally unique profile ID)
insert into r select 'b_reuse', public.sync_push(
  jsonb_build_array(jsonb_build_object('id', tests.ulid(1), 'display_name', 'Bob two', 'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('b_reuse') -> 'rejected',
  jsonb_build_array(jsonb_build_object('id', tests.ulid(1), 'rejected', true)),
  'reusing A''s profile ULID through the RPC is rejected');

-- from the owner's view: nothing landed under A
select tests.clear_authentication();
select is((select count(*) from public.profiles
            where user_id = tests.get_supabase_uid('user_a') and id in (tests.ulid(11))),
  0::bigint, 'payload user_id = A: nothing landed under A (profiles)');
select is((select count(*) from public.day_entries
            where user_id = tests.get_supabase_uid('user_a') and id in (tests.ulid(12), tests.ulid(1999))),
  0::bigint, 'payload user_id = A: nothing landed under A (day entries)');
select is((select display_name from public.profiles
            where id = tests.ulid(1) and user_id = tests.get_supabase_uid('user_a')),
  'Alice', 'B''s reuse attempt of A''s ULID did not touch A''s row');

-- ---------------------------------------------------------------------------
-- anon and PUBLIC cannot execute sync_push
-- ---------------------------------------------------------------------------
select tests.authenticate_as_anon();
select throws_ok($$select public.sync_push('[]'::jsonb, '[]'::jsonb)$$, '42501', null,
  'anon cannot execute sync_push');
select tests.clear_authentication();
select is((select count(*) from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
            cross join lateral aclexplode(coalesce(p.proacl, '{}'::aclitem[])) a
           where n.nspname = 'public' and p.proname = 'sync_push'
             and (a.grantee = 0 or a.grantee = 'anon'::regrole)),
  0::bigint, 'PUBLIC and anon hold no EXECUTE on sync_push');
-- Issue #240: sync_push gained a third p_observations parameter (the old
-- 2-arg overload was dropped, not left to fork alongside the new one - see
-- 20260908160000_observations.sql's header); Issue #188 added
-- p_profile_modes/p_cycle_overrides the same way (dropping the 3-arg
-- overload first - see 20260909000000's header); Issue #128 adds
-- p_care_notes/p_visit_prep_items the same way (dropping the 5-arg overload
-- first) - the signature this literal must resolve is now the 7-arg one.
select ok(has_function_privilege('authenticated', 'public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)', 'execute'),
  'authenticated can execute sync_push');
select is((select prosecdef from pg_proc where proname = 'sync_push' and pronamespace = 'public'::regnamespace),
  false, 'sync_push is security invoker');

-- ---------------------------------------------------------------------------
-- advisory transaction lock (Issue #14)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');
select public.sync_push('[]'::jsonb, '[]'::jsonb);
select ok(exists(
  select 1 from pg_locks
  where locktype = 'advisory'
    and objid = hashtext(tests.get_supabase_uid('user_a')::text)
), 'sync_push acquires advisory transaction lock for the user');

-- ---------------------------------------------------------------------------
-- tags string-only validation (Issue #40)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');
select is(public.is_valid_tags_array('1'::jsonb), false,
  'tags validator rejects a non-array without raising');
insert into r select 'bad_tags', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(116), 'profile_id', tests.ulid(1), 'local_date', '2026-09-16',
      'tz', 'UTC', 'flow', 'none', 'tags', '[1, 2]'::jsonb, 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(117), 'profile_id', tests.ulid(1), 'local_date', '2026-09-17',
      'tz', 'UTC', 'flow', 'none', 'tags', '["valid", 123]'::jsonb, 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(118), 'profile_id', tests.ulid(1), 'local_date', '2026-09-18',
      'tz', 'UTC', 'flow', 'none', 'tags', '["valid", "tags"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))
  ));
select is(jsonb_array_length(pg_temp.resp('bad_tags') -> 'rejected'), 2,
  'non-string tags elements ([1, 2] and ["valid", 123]) are rejected');
select is((select count(*) from public.day_entries where id = tests.ulid(118)), 1::bigint,
  'valid string array tags in same batch lands');

select throws_ok(
  $$ insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, tags, updated_at)
     values (tests.ulid(119), tests.get_supabase_uid('user_a'), tests.ulid(1), '2026-09-19', 'UTC', 'none', '[1, 2]'::jsonb, now()) $$,
  '23514',
  null,
  'table check constraint day_entries_tags_check rejects non-string tags'
);

-- Issue #94: per-element length bound (char_length <= 64).
select is(public.is_valid_tags_array(jsonb_build_array(repeat('x', 65))), false,
  'tags validator rejects a 65-character element without raising');
select is(public.is_valid_tags_array(jsonb_build_array(repeat('x', 64))), true,
  'tags validator accepts a 64-character element (boundary is inclusive)');
select is(public.is_valid_tags_array(
  (select jsonb_agg(repeat('x', 64)) from generate_series(1, 32))), true,
  'tags validator accepts 32 elements of 64 characters (worst legal case)');
select is(public.is_valid_tags_array('[1, 2]'::jsonb), false,
  'tags validator still rejects a non-string element');
select is(public.is_valid_tags_array(
  (select jsonb_agg(g::text) from generate_series(1, 33) g)), false,
  'tags validator still rejects a 33-element array');
select is(public.is_valid_tags_array(
  '["cramps", "headache", "back_pain", "breast_tenderness", "bloating", '
  '"acne", "nausea", "fatigue", "dizziness", "irritable", "sad", "anxious", '
  '"calm", "energetic", "sensitive", "sleep_trouble", "cravings"]'::jsonb), true,
  'tags validator accepts the full curated taxonomy');

insert into r select 'long_tags', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(130), 'profile_id', tests.ulid(1), 'local_date', '2026-09-26',
      'tz', 'UTC', 'flow', 'none', 'tags', jsonb_build_array(repeat('x', 65)), 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(131), 'profile_id', tests.ulid(1), 'local_date', '2026-09-27',
      'tz', 'UTC', 'flow', 'none', 'tags', jsonb_build_array('ok', repeat('x', 65)), 'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(132), 'profile_id', tests.ulid(1), 'local_date', '2026-09-28',
      'tz', 'UTC', 'flow', 'none', 'tags', '["valid", "tags"]'::jsonb, 'updated_at', pg_temp.ts_txt('t1'))
  ));
select is(jsonb_array_length(pg_temp.resp('long_tags') -> 'rejected'), 2,
  'over-length tag elements (65 chars) are rejected by sync_push');
select is((select count(*) from public.day_entries where id = tests.ulid(132)), 1::bigint,
  'valid tags in the same batch still lands');

select throws_ok(
  $$ insert into public.day_entries (id, user_id, profile_id, local_date, tz, flow, tags, updated_at)
     values (tests.ulid(133), tests.get_supabase_uid('user_a'), tests.ulid(1), '2026-09-29', 'UTC', 'none', jsonb_build_array(repeat('x', 65)), now()) $$,
  '23514',
  null,
  'table check constraint day_entries_tags_check rejects an over-length tag element'
);

-- ---------------------------------------------------------------------------
-- U1: profile subject metadata (birth_year, relationship, transferred_at)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');

insert into r select 'meta_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(120), 'display_name', 'Meta', 'birth_year', 2011, 'relationship', 'daughter',
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('meta_insert') -> 'rejected', '[]'::jsonb,
  'U1: a push carrying birth_year and relationship is not rejected');
select is((select birth_year from public.profiles where id = tests.ulid(120)), 2011::smallint,
  'U1: birth_year round-trips through sync_push');
select is((select relationship from public.profiles where id = tests.ulid(120)), 'daughter',
  'U1: relationship round-trips through sync_push');

insert into r select 'meta_bad_relationship', public.sync_push(
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(121), 'display_name', 'Cousin', 'relationship', 'cousin',
      'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(122), 'display_name', 'Partner', 'relationship', 'partner',
      'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(jsonb_array_length(pg_temp.resp('meta_bad_relationship') -> 'rejected'), 1,
  'U1: an out-of-set relationship is rejected without aborting the batch');
select is((select count(*) from public.profiles where id = tests.ulid(121)), 0::bigint,
  'U1: the row with the invalid relationship does not land');
select is((select count(*) from public.profiles where id = tests.ulid(122)), 1::bigint,
  'U1: the valid row in the same batch still lands');

insert into r select 'meta_bad_birth_year', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(123), 'display_name', 'TooOld', 'birth_year', 1800,
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(jsonb_array_length(pg_temp.resp('meta_bad_birth_year') -> 'rejected'), 1,
  'U1: a birth_year outside 1900-2200 is rejected by the CHECK constraint');
select is((select count(*) from public.profiles where id = tests.ulid(123)), 0::bigint,
  'U1: the out-of-range birth_year row does not land');

insert into r select 'meta_transferred_at', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(120), 'display_name', 'Meta2', 'birth_year', 2011, 'relationship', 'daughter',
    'updated_at', pg_temp.ts_txt('t2'), 'transferred_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('meta_transferred_at') -> 'rejected', '[]'::jsonb,
  'U1: a push carrying transferred_at is accepted (tolerated key)');
select is((select transferred_at from public.profiles where id = tests.ulid(120)), null,
  'U1: transferred_at is never written by sync_push, regardless of the pushed value');

insert into r select 'meta_transferred_to', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(120), 'display_name', 'Meta3', 'birth_year', 2011, 'relationship', 'daughter',
    'updated_at', pg_temp.ts_txt('t3'),
    'transferred_to_user_id', tests.get_supabase_uid('user_b'))),
  '[]'::jsonb);
select is(pg_temp.resp('meta_transferred_to') -> 'rejected', '[]'::jsonb,
  '#296: a push carrying transferred_to_user_id is accepted (tolerated key)');
select is((select transferred_to_user_id from public.profiles where id = tests.ulid(120)), null,
  '#296: transferred_to_user_id is never written by sync_push, regardless of the pushed value');

select throws_ok(
  format($$update public.profiles set transferred_to_user_id = %L where id = tests.ulid(120)$$,
    tests.get_supabase_uid('user_b')),
  '42501', null,
  '#296: authenticated has no column grant to write transferred_to_user_id directly'
);

-- Review item #3 (P1) regression: a client built before U1 never sends
-- birth_year/relationship at all - the key is absent, not present-with-null.
-- The stored value must survive an otherwise-unrelated metadata edit.
insert into r select 'meta_old_client_seed', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(124), 'display_name', 'OldClient', 'birth_year', 2012, 'relationship', 'son',
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('meta_old_client_seed') -> 'rejected', '[]'::jsonb,
  'Review item #3 regression: seeding the old-client profile is not rejected');

insert into r select 'meta_old_client_update', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(124), 'display_name', 'OldClient Renamed',
    'updated_at', pg_temp.ts_txt('t2'))),
  '[]'::jsonb);
select is(pg_temp.resp('meta_old_client_update') -> 'rejected', '[]'::jsonb,
  'Review item #3 regression: an old-client push omitting birth_year/relationship is not rejected');
select is((select display_name from public.profiles where id = tests.ulid(124)), 'OldClient Renamed',
  'Review item #3 regression: the omitted-key push still applies the field it did send');
select is((select birth_year from public.profiles where id = tests.ulid(124)), 2012::smallint,
  'Review item #3: an old client omitting birth_year does not null out the already-stored value');
select is((select relationship from public.profiles where id = tests.ulid(124)), 'son',
  'Review item #3: an old client omitting relationship does not null out the already-stored value');

select throws_ok(
  $$update public.profiles set transferred_at = now() where id = tests.ulid(120)$$,
  '42501', null,
  'U1: authenticated has no column grant to write transferred_at directly'
);

update public.profiles set birth_year = 2010 where id = tests.ulid(120);
select is((select birth_year from public.profiles where id = tests.ulid(120)), 2010::smallint,
  'U1: authenticated can write birth_year directly on an owned profile');

-- ---------------------------------------------------------------------------
-- #131: care modes (profiles.mode) — round-trip, default, rejection,
-- old-client omission, direct grant write, and permission invariance.
-- Mirrors the U1 birth_year/relationship pattern directly above.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');

insert into r select 'mode_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(125), 'display_name', 'Modes', 'mode', 'teen',
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('mode_insert') -> 'rejected', '[]'::jsonb,
  '#131: a push carrying mode is not rejected');
select is((select mode from public.profiles where id = tests.ulid(125)), 'teen',
  '#131: mode round-trips through sync_push');

insert into r select 'mode_default', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(126), 'display_name', 'NoMode',
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is((select mode from public.profiles where id = tests.ulid(126)), 'standard',
  '#131: a push omitting mode lands as the standard default');

insert into r select 'mode_bad', public.sync_push(
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(127), 'display_name', 'Future', 'mode', 'future_mode',
      'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(128), 'display_name', 'Valid', 'mode', 'irregular',
      'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(jsonb_array_length(pg_temp.resp('mode_bad') -> 'rejected'), 1,
  '#131: an out-of-set mode is rejected without aborting the batch');
select is((select count(*) from public.profiles where id = tests.ulid(127)), 0::bigint,
  '#131: the out-of-set mode row does not land');
select is((select mode from public.profiles where id = tests.ulid(128)), 'irregular',
  '#131: the valid mode row in the same batch still lands');

-- A newer push updates the stored mode, then a pre-#131 client's push
-- (no 'mode' key at all) renames the profile without disturbing it - the
-- PR #108 review item #3 containment pattern, applied to mode.
insert into r select 'mode_update', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(125), 'display_name', 'Modes Renamed', 'mode', 'caregiver',
    'updated_at', pg_temp.ts_txt('t2'))),
  '[]'::jsonb);
select is((select mode from public.profiles where id = tests.ulid(125)), 'caregiver',
  '#131: a newer push updates the stored mode');

insert into r select 'mode_old_client', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(125), 'display_name', 'Old Client Rename',
    'updated_at', pg_temp.ts_txt('t3'))),
  '[]'::jsonb);
select is((select display_name from public.profiles where id = tests.ulid(125)), 'Old Client Rename',
  '#131: the old-client push still applies the field it did send');
select is((select mode from public.profiles where id = tests.ulid(125)), 'caregiver',
  '#131: an old client omitting mode does not reset the stored mode');

update public.profiles set mode = 'irregular' where id = tests.ulid(125);
select is((select mode from public.profiles where id = tests.ulid(125)), 'irregular',
  '#131: authenticated can write mode directly on an owned profile');

-- Permission invariance (Issue #131 hard constraint: mode is presentation,
-- never permission): a caregiver-role guardian's push that tries to edit
-- profile metadata (mode included) is still rejected by the unchanged role
-- check, and a caregiver still writes day entries on the mode-carrying
-- profile - mode neither grants nor restricts anything.
select tests.clear_authentication();
insert into public.profile_guardians (profile_id, user_id, role, status)
values (tests.ulid(125), tests.get_supabase_uid('user_b'), 'caregiver', 'accepted');

select tests.authenticate_as('user_b');
insert into r select 'mode_caregiver_edit', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(125), 'display_name', 'Nanny Rename', 'mode', 'teen',
    'updated_at', pg_temp.ts_txt('t3'))),
  '[]'::jsonb);
select is(jsonb_array_length(pg_temp.resp('mode_caregiver_edit') -> 'rejected'), 1,
  '#131: a caregiver-role push cannot edit profile mode (roles unchanged by mode)');
select is((select mode from public.profiles where id = tests.ulid(125)), 'irregular',
  '#131: the rejected caregiver mode edit does not land');

insert into r select 'mode_entry', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(129), 'profile_id', tests.ulid(125), 'local_date', '2026-09-30',
    'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('mode_entry') -> 'rejected', '[]'::jsonb,
  '#131: a caregiver still writes day entries on a profile with any mode');


-- ---------------------------------------------------------------------------
-- #218: onboarding cycle facts (last_period_start,
-- typical_cycle_length_days, typical_period_length_days) -- round-trip,
-- CHECK rejection, old-client omission, direct grant write. Mirrors the
-- U1 birth_year/relationship and #131 mode patterns directly above.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');

insert into r select 'facts_insert', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(134), 'display_name', 'Facts',
    'last_period_start', '2026-09-01',
    'typical_cycle_length_days', 28, 'typical_period_length_days', 5,
    'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('facts_insert') -> 'rejected', '[]'::jsonb,
  '#218: a push carrying the cycle facts is not rejected');
select is((select last_period_start::text from public.profiles where id = tests.ulid(134)), '2026-09-01',
  '#218: last_period_start round-trips through sync_push');
select is((select typical_cycle_length_days from public.profiles where id = tests.ulid(134)), 28::smallint,
  '#218: typical_cycle_length_days round-trips through sync_push');
select is((select typical_period_length_days from public.profiles where id = tests.ulid(134)), 5::smallint,
  '#218: typical_period_length_days round-trips through sync_push');

insert into r select 'facts_bad_cycle', public.sync_push(
  jsonb_build_array(
    jsonb_build_object('id', tests.ulid(135), 'display_name', 'Huge', 'typical_cycle_length_days', 400,
      'updated_at', pg_temp.ts_txt('t1')),
    jsonb_build_object('id', tests.ulid(136), 'display_name', 'Fine', 'typical_cycle_length_days', 90,
      'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(jsonb_array_length(pg_temp.resp('facts_bad_cycle') -> 'rejected'), 1,
  '#218: a typical_cycle_length_days outside 1-365 is rejected by the CHECK constraint');
select is((select count(*) from public.profiles where id = tests.ulid(135)), 0::bigint,
  '#218: the out-of-range cycle-facts row does not land');
select is((select typical_cycle_length_days from public.profiles where id = tests.ulid(136)), 90::smallint,
  '#218: the wide-but-valid answer (90) still lands -- storage is honest-wide, seeding is a client gate');

-- Old-client regression (the PR #108 item #3 / #218 containment guard): a
-- client built before #218 never sends these keys; its ordinary profile
-- edit must not null the stored facts.
insert into r select 'facts_old_client', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(134), 'display_name', 'Facts Renamed',
    'updated_at', pg_temp.ts_txt('t2'))),
  '[]'::jsonb);
select is(pg_temp.resp('facts_old_client') -> 'rejected', '[]'::jsonb,
  '#218: an old-client push omitting the fact keys is not rejected');
select is((select display_name from public.profiles where id = tests.ulid(134)), 'Facts Renamed',
  '#218: the old-client push still applies the field it did send');
select is((select last_period_start::text from public.profiles where id = tests.ulid(134)), '2026-09-01',
  '#218: an old client omitting last_period_start does not null the stored value');
select is((select typical_cycle_length_days from public.profiles where id = tests.ulid(134)), 28::smallint,
  '#218: an old client omitting typical_cycle_length_days does not null the stored value');

update public.profiles set typical_period_length_days = 6 where id = tests.ulid(134);
select is((select typical_period_length_days from public.profiles where id = tests.ulid(134)), 6::smallint,
  '#218: authenticated can write the fact columns directly on an owned profile');

-- ---------------------------------------------------------------------------
-- Issue #159: day_entries provenance (source/source_id/import_id)
-- ---------------------------------------------------------------------------
select tests.authenticate_as('user_a');

-- Issue #167 gave import_id a real `references import_jobs(id)` FK (this
-- column was an unconstrained placeholder before that migration), so the
-- id used below must be a real import_jobs row, not an arbitrary literal
-- uuid -- a fixed id inserted directly, since nothing else in this file
-- needs to look it back up.
insert into public.import_jobs (id, profile_id, source, status, total_rows, created_by)
values ('11111111-1111-1111-1111-111111111111'::uuid, tests.ulid(1), 'clue_import', 'pending', 1,
        tests.get_supabase_uid('user_a'));

-- Round trip: a brand-new entry pushed with all three keys stores them
-- verbatim.
insert into r select 'provenance_insert', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(300), 'profile_id', tests.ulid(1), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'none', 'source', 'clue_import', 'source_id', 'clue-abc',
    'import_id', '11111111-1111-1111-1111-111111111111',
    'updated_at', pg_temp.ts_txt('t1'))));
select is(pg_temp.resp('provenance_insert') -> 'rejected', '[]'::jsonb,
  '#159: a valid source/source_id/import_id day_entries push is accepted');
select is((select source from public.day_entries where id = tests.ulid(300)), 'clue_import',
  '#159: source round-trips');
select is((select source_id from public.day_entries where id = tests.ulid(300)), 'clue-abc',
  '#159: source_id round-trips');
select is((select import_id::text from public.day_entries where id = tests.ulid(300)),
  '11111111-1111-1111-1111-111111111111',
  '#159: import_id round-trips');

-- Default: an entry pushed without a source key at all defaults to manual.
insert into r select 'provenance_default', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(301), 'profile_id', tests.ulid(1), 'local_date', '2026-10-02',
    'tz', 'UTC', 'flow', 'none', 'updated_at', pg_temp.ts_txt('t1'))));
select is((select source from public.day_entries where id = tests.ulid(301)), 'manual',
  '#159: an absent source key defaults to manual on insert');
select is((select source_id from public.day_entries where id = tests.ulid(301)), null,
  '#159: source_id defaults to null on insert');

-- Rejection: a source value outside the closed set is rejected by the
-- CHECK, caught as a per-row rejection, not a batch failure.
insert into r select 'provenance_bad_source', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(302), 'profile_id', tests.ulid(1), 'local_date', '2026-10-03',
    'tz', 'UTC', 'flow', 'none', 'source', 'not_a_real_source',
    'updated_at', pg_temp.ts_txt('t1'))));
select is(jsonb_array_length(pg_temp.resp('provenance_bad_source') -> 'rejected'), 1,
  '#159: an out-of-set day_entries.source value is rejected');
select is((select count(*) from public.day_entries where id = tests.ulid(302)), 0::bigint,
  '#159: the rejected row does not land');

-- Rejection: a malformed import_id (not a UUID) is rejected the same way.
insert into r select 'provenance_bad_import_id', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(303), 'profile_id', tests.ulid(1), 'local_date', '2026-10-04',
    'tz', 'UTC', 'flow', 'none', 'import_id', 'not-a-uuid',
    'updated_at', pg_temp.ts_txt('t1'))));
select is(jsonb_array_length(pg_temp.resp('provenance_bad_import_id') -> 'rejected'), 1,
  '#159: a malformed import_id is rejected rather than crashing the batch');

-- source_id length bound (day_entries_source_id_length_check, 128 chars).
insert into r select 'provenance_long_source_id', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(304), 'profile_id', tests.ulid(1), 'local_date', '2026-10-05',
    'tz', 'UTC', 'flow', 'none', 'source_id', repeat('x', 129),
    'updated_at', pg_temp.ts_txt('t1'))));
select is(jsonb_array_length(pg_temp.resp('provenance_long_source_id') -> 'rejected'), 1,
  '#159: a 129-character source_id is rejected (day_entries_source_id_length_check)');

-- Containment guard (acceptance criteria: "server does not silently null
-- them on later same-row updates"): an update that omits source/source_id/
-- import_id entirely preserves the stored values.
insert into r select 'provenance_old_client_update', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(300), 'profile_id', tests.ulid(1), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'medium', 'updated_at', pg_temp.ts_txt('t2'))));
select is((select flow from public.day_entries where id = tests.ulid(300)), 'medium',
  '#159: the old-client push still applies the field it did send');
select is((select source from public.day_entries where id = tests.ulid(300)), 'clue_import',
  '#159: an old client omitting source does not reset the stored value');
select is((select source_id from public.day_entries where id = tests.ulid(300)), 'clue-abc',
  '#159: an old client omitting source_id does not reset the stored value');
select is((select import_id::text from public.day_entries where id = tests.ulid(300)),
  '11111111-1111-1111-1111-111111111111',
  '#159: an old client omitting import_id does not reset the stored value');

-- Contrast: an explicit key present with a null value DOES clear it - this
-- is what distinguishes "omitted" from "explicitly cleared" (the same
-- jsonb `?` containment semantics U1 established for
-- birth_year/relationship).
insert into r select 'provenance_explicit_clear', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(300), 'profile_id', tests.ulid(1), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'medium', 'source_id', null, 'import_id', null,
    'updated_at', pg_temp.ts_txt('t3'))));
select is((select source_id from public.day_entries where id = tests.ulid(300)), null,
  '#159: an explicit null source_id (key present) clears the stored value');
select is((select import_id from public.day_entries where id = tests.ulid(300)), null,
  '#159: an explicit null import_id (key present) clears the stored value');
select is((select source from public.day_entries where id = tests.ulid(300)), 'clue_import',
  '#159: source itself is untouched by clearing source_id/import_id (independent columns)');

-- Provenance survives a tombstone (this migration's judgement call): a
-- direct client soft-delete keeps whatever source/source_id/import_id the
-- row already carried.
insert into r select 'provenance_tombstone', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(300), 'profile_id', tests.ulid(1), 'local_date', '2026-10-01',
    'tz', 'UTC', 'flow', 'none', 'source', 'clue_import', 'source_id', 'clue-abc-2',
    'updated_at', pg_temp.ts_txt('t4'), 'deleted_at', pg_temp.ts_txt('t4'))));
select isnt((select deleted_at from public.day_entries where id = tests.ulid(300)), null,
  '#159: the row is tombstoned');
select is((select source from public.day_entries where id = tests.ulid(300)), 'clue_import',
  '#159: source survives the tombstone');
select is((select source_id from public.day_entries where id = tests.ulid(300)), 'clue-abc-2',
  '#159: source_id survives the tombstone (day_entries never clears provenance, unlike flow/tags/note)');

select * from finish();
rollback;
