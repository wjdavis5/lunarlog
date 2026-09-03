-- sync_push RPC proof (plan U2: AE3, LWW guard, resolver, tombstones,
-- idempotency, payload user_id, opaque rejections, batch limits, anon).
begin;
select plan(82);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

-- handy timestamps
create temp table ts (k text primary key, t timestamptz);
insert into ts values
  ('t0', '2026-09-01T09:00:00Z'),
  ('t1', '2026-09-01T10:00:00Z'),
  ('t2', '2026-09-01T11:00:00Z'),
  ('t3', '2026-09-01T12:00:00Z');
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
create temp table sv105 as select server_version from public.day_entries where id = tests.ulid(105);
insert into r select 'eq_b2', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(106), 'profile_id', tests.ulid(1), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'heavy', 'note', 'incoming-larger', 'tags', '["x"]'::jsonb,
    'updated_at', pg_temp.ts_txt('t1'))));
select is((select deleted_at from public.day_entries where id = tests.ulid(105)), null,
  'equal ts: the smaller stored ULID stays live');
select is((select server_version from public.day_entries where id = tests.ulid(105)),
  (select server_version from sv105), 'equal ts: the stored winner is not rewritten');
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
select is(pg_temp.resp('bad_rows') -> 'rejected' -> 0, jsonb_build_object('id', 'not-a-ulid', 'rejected', true),
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

-- B pushing A's profile id as an own row (AE12 through the RPC)
insert into r select 'b_reuse', public.sync_push(
  jsonb_build_array(jsonb_build_object('id', tests.ulid(1), 'display_name', 'Bob two', 'updated_at', pg_temp.ts_txt('t1'))),
  '[]'::jsonb);
select is(pg_temp.resp('b_reuse') -> 'rejected', '[]'::jsonb, 'reusing A''s profile ULID through the RPC is not an error');

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
  'Alice', 'B''s reuse of A''s ULID did not touch A''s row');

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
select ok(has_function_privilege('authenticated', 'public.sync_push(jsonb, jsonb)', 'execute'),
  'authenticated can execute sync_push');
select is((select prosecdef from pg_proc where proname = 'sync_push' and pronamespace = 'public'::regnamespace),
  false, 'sync_push is security invoker');

select * from finish();
rollback;
