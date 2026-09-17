-- Coverage for 20260918000000_day_entry_history.sql (Issue #170): one
-- content-free audit row per day_entries change (logged/updated/
-- tombstoned), the same-date resolver's merged_discard emission (and its
-- interplay with day_entry_merge_events -- both tables written by one
-- discard, different payloads), the content-free guarantee as a real scan
-- (every changed_fields element is a known day_entries COLUMN NAME, never
-- a value from flow/tags/note) plus the CHECK that enforces it, RLS
-- (co-parent reads, non-guardian cannot), the sync_pull key, the 90-day
-- retention purge (enforce_retention's pre-armed guarded step, live for
-- the first time), tombstone_profile_content()'s wipe, and the Realtime
-- never-publish posture.
begin;
select plan(29);

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('eve');

-- ---------------------------------------------------------------------------
-- Table posture: RLS, guardian-only select, trigger-only writes.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'day_entry_history');
select tests.rls_forced('public', 'day_entry_history');
select is(
  (select count(*)::integer from pg_policies
    where tablename = 'day_entry_history' and schemaname = 'public'
      and cmd <> 'SELECT'),
  0,
  'no INSERT/UPDATE/DELETE policy exists -- writes are trigger/resolver-only'
);
select ok(
  has_table_privilege('authenticated', 'public.day_entry_history', 'select'),
  'authenticated can SELECT day_entry_history'
);
select ok(
  not has_table_privilege('authenticated', 'public.day_entry_history', 'insert')
    and not has_table_privilege('authenticated', 'public.day_entry_history', 'update')
    and not has_table_privilege('authenticated', 'public.day_entry_history', 'delete'),
  'authenticated holds no write grant on day_entry_history (the outbox posture)'
);

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile P1, shared with Dad (co_parent). Eve is an outsider.
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
-- Group A: insert, update, and tombstone each produce EXACTLY one history
-- row, with the acting user attributed from sync_push's stamps.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom private note text',
    'updated_at', '2026-09-05T10:00:00Z')));

select is(
  (select count(*) from public.day_entry_history where entry_id = tests.ulid(910)),
  1::bigint,
  'a logged entry produces exactly one history row'
);
select is(
  (select change_kind from public.day_entry_history where entry_id = tests.ulid(910)),
  'logged',
  'the insert row is change_kind logged'
);
select is(
  (select (changed_by_user_id, changed_fields)
     = (tests.get_supabase_uid('mom'),
        array['local_date', 'flow', 'tags', 'note'])
     from public.day_entry_history where entry_id = tests.ulid(910)),
  true,
  'the logged row names the content columns set at insert and attributes mom'
);

select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom edited note',
    'updated_at', '2026-09-05T11:00:00Z')));

select is(
  (select count(*) from public.day_entry_history where entry_id = tests.ulid(910)),
  2::bigint,
  'an edit produces exactly one more history row (two total)'
);
select is(
  (select (change_kind, changed_fields) = ('updated', array['note'])
     from public.day_entry_history
    where entry_id = tests.ulid(910)
    order by changed_at desc limit 1),
  true,
  'the edit row is change_kind updated naming exactly the changed column'
);

select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'updated_at', '2026-09-05T12:00:00Z', 'deleted_at', '2026-09-05T12:00:00Z')));

select is(
  (select count(*) from public.day_entry_history where entry_id = tests.ulid(910)),
  3::bigint,
  'a tombstone produces exactly one more history row (three total)'
);
select is(
  (select (change_kind, changed_fields)
     = ('tombstoned', array['deleted_at', 'flow', 'tags', 'note'])
     from public.day_entry_history
    where entry_id = tests.ulid(910)
    order by changed_at desc limit 1),
  true,
  'the tombstone row is change_kind tombstoned naming deleted_at plus the cleared payload columns'
);

-- ---------------------------------------------------------------------------
-- Group B: the content-free guarantee. A REAL scan: every element of every
-- changed_fields array is a known day_entries COLUMN NAME; none is a value
-- from flow/tags/note that any fixture ever carried; and the table's own
-- CHECK rejects a value-shaped array outright.
-- ---------------------------------------------------------------------------
select ok(
  not exists(
    select 1
      from public.day_entry_history h,
           unnest(h.changed_fields) f
     where f <> all (array[
       'local_date', 'tz', 'flow', 'tags', 'note', 'pms',
       'source', 'source_id', 'import_id', 'deleted_at'])
  ),
  'content-free scan: every changed_fields element is a known column NAME'
);
select ok(
  not exists(
    select 1
      from public.day_entry_history h,
           unnest(h.changed_fields) f
     where f = any (array[
       'medium', 'heavy', 'light', 'none',
       'mom private note text', 'mom edited note', 'dad winning note',
       'cramps', 'secret_tag_code'])
  ),
  'content-free scan: no changed_fields element is a value from flow/tags/note'
);
-- As the table owner (not authenticated): the point is the CHECK, and an
-- authenticated caller would be denied by the missing INSERT grant before
-- the CHECK ever ran.
select tests.clear_authentication();
select throws_ok(
  $sql$insert into public.day_entry_history
    (id, entry_id, profile_id, changed_by_user_id, change_kind, changed_fields)
  values
    (upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 26)),
     tests.ulid(910), tests.ulid(901), tests.get_supabase_uid('mom'),
     'updated', array['heavy'])$sql$,
  '23514', null,
  'the structural CHECK rejects a changed_fields element that is a value, not a column name'
);

-- ---------------------------------------------------------------------------
-- Group C: the same-date resolver's discard branch writes merged_discard
-- rows naming the discarded field(s) -- next to (not instead of) the
-- day_entry_merge_events rows that retain the losing text.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'light', 'tags', '[]'::jsonb, 'note', 'mom keeps this',
    'updated_at', '2026-09-06T09:00:00Z')));

select tests.authenticate_as('dad');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '[]'::jsonb, 'note', 'dad winning note',
    'updated_at', '2026-09-06T10:00:00Z')));

select is(
  (select count(*) from public.day_entry_history
    where entry_id = tests.ulid(920) and change_kind = 'merged_discard'),
  2::bigint,
  'an incoming-wins merge discarding note+flow writes exactly two merged_discard rows on the LOSING row'
);
select is(
  (select array_agg(f order by f) from (
     select unnest(changed_fields) f from public.day_entry_history
      where entry_id = tests.ulid(920) and change_kind = 'merged_discard') s),
  array['flow', 'note'],
  'the merged_discard rows name the discarded field(s) -- field names only'
);
select is(
  (select changed_by_user_id from public.day_entry_history
    where entry_id = tests.ulid(920) and change_kind = 'merged_discard' limit 1),
  tests.get_supabase_uid('dad'),
  'the merged_discard rows attribute the acting caller (dad, who pushed the winner)'
);
select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-06'),
  2::bigint,
  'interplay: the SAME discard also wrote two day_entry_merge_events rows (the recoverable text) -- both tables, one discard, different purposes'
);

-- A tags-only merge discards nothing: no merged_discard row.
select tests.authenticate_as('mom');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(930), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["a"]'::jsonb,
    'updated_at', '2026-09-07T09:00:00Z')));
select tests.authenticate_as('dad');
select public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(931), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["b"]'::jsonb,
    'updated_at', '2026-09-07T10:00:00Z')));

select is(
  (select count(*) from public.day_entry_history
    where change_kind = 'merged_discard'
      and entry_id in (tests.ulid(930), tests.ulid(931))),
  0::bigint,
  'a tags-only merge discards nothing and writes no merged_discard row'
);

-- ---------------------------------------------------------------------------
-- Group D: RLS -- a co-parent reads another guardian's history rows; a
-- non-guardian cannot read anything.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select ok(
  (select count(*) from public.day_entry_history
    where profile_id = tests.ulid(901)) > 0::bigint,
  'the co-parent (dad, authenticated) reads mom''s history rows'
);
select tests.authenticate_as('eve');
select is(
  (select count(*) from public.day_entry_history
    where profile_id = tests.ulid(901)),
  0::bigint,
  'a non-guardian reads no history rows'
);

-- ---------------------------------------------------------------------------
-- Group E: the sync_pull key -- pull-only transport, same tenant scoping.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select ok(
  jsonb_array_length(
    public.sync_pull('{"day_entry_history": 0}'::jsonb) -> 'day_entry_history') > 0,
  'sync_pull returns day_entry_history rows for the co-parent'
);
select tests.authenticate_as('eve');
select is(
  (select public.sync_pull('{"day_entry_history": 0}'::jsonb) -> 'day_entry_history'),
  '[]'::jsonb,
  'sync_pull returns no day_entry_history rows for a non-guardian'
);

-- ---------------------------------------------------------------------------
-- Group F: Realtime never-publish posture.
-- ---------------------------------------------------------------------------
select ok(
  not exists(
    select 1 from pg_catalog.pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'day_entry_history'
  ),
  'public.day_entry_history is NOT published to supabase_realtime'
);

-- ---------------------------------------------------------------------------
-- Group G: the 90-day retention purge -- enforce_retention()'s guarded
-- step, armed by 20260915200000 and live since this migration created the
-- table. Boundary: 91 days old is purged, 89 days old survives. Runs as
-- the table owner (superuser): the direct inserts below are fixture rows
-- (RLS does not apply, and the set_server_version/signal triggers fire
-- exactly as for trigger-written rows), and enforce_retention itself is
-- EXECUTE-revoked from every client-facing role.
-- ---------------------------------------------------------------------------
select tests.clear_authentication();
select is(
  (select count(*) from public.day_entry_history
    where profile_id = tests.ulid(901) and changed_at < now() - interval '90 days'),
  0::bigint,
  'no history row is older than the retention window yet (the purge''s precondition)'
);
insert into public.day_entry_history
  (id, entry_id, profile_id, changed_by_user_id, changed_at, change_kind, changed_fields)
values
  (upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 26)),
   tests.ulid(910), tests.ulid(901), tests.get_supabase_uid('mom'),
   now() - interval '91 days', 'updated', array['note']),
  (upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 26)),
   tests.ulid(910), tests.ulid(901), tests.get_supabase_uid('mom'),
   now() - interval '89 days', 'updated', array['note']);

select is(
  (select (public.enforce_retention()) ->> 'day_entry_history'),
  '1',
  'the nightly retention job purges exactly the 91-day-old row'
);
select is(
  (select count(*) from public.day_entry_history
    where profile_id = tests.ulid(901)
      and changed_at >= now() - interval '90 days'
      and changed_at < now() - interval '88 days'),
  1::bigint,
  'the 89-day-old row survives the 90-day purge boundary'
);

-- ---------------------------------------------------------------------------
-- Group H: a profile wipe removes the profile's history rows entirely.
-- (Runs last: the wipe tombstones every entry, which fires the history
-- trigger again -- the explicit delete inside tombstone_profile_content
-- runs after those updates, so the final count is zero.)
-- ---------------------------------------------------------------------------
select public.tombstone_profile_content(tests.ulid(901), '2026-09-08T00:00:00Z');
select is(
  (select count(*) from public.day_entry_history
    where profile_id = tests.ulid(901)),
  0::bigint,
  'tombstone_profile_content hard-deletes every history row for the wiped profile'
);

select finish();
rollback;
