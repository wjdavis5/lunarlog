-- Coverage for 20260916100000_day_entry_merge_events.sql (Issue #130): the
-- same-date resolver's merge-disclosure emission (both directions), the
-- tags-only and same-id silence guarantees, the p_merge_events push path
-- (natural-key dedupe, write ladder, length bound), RLS, the sync_pull key,
-- the Realtime never-publish posture + sync_signals wake, the 30-day
-- retention purge, and tombstone_profile_content()'s hard delete.
begin;
select plan(31);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('eve');

-- ---------------------------------------------------------------------------
-- Table posture.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'day_entry_merge_events');
select tests.rls_forced('public', 'day_entry_merge_events');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile P1, shared with Dad (co_parent) and Doctor (viewer).
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
-- Group A: incoming-wins merge discards BOTH a note and a flow value --
-- exactly one row per discarded field, carrying the losing text, both row
-- ids, and both authors.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'a_mom', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'medium', 'tags', '["cramps"]'::jsonb, 'note', 'mom''s note',
    'updated_at', '2026-09-05T10:00:00Z')));

select tests.authenticate_as('dad');
insert into r select 'a_dad', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '["heavy_flow"]'::jsonb, 'note', 'dad''s note',
    'updated_at', '2026-09-05T11:00:00Z')));

select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05'),
  2::bigint,
  'incoming-wins merge discarding note+flow emits exactly two events'
);
select is(
  (select losing_value_text from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05' and field = 'note'),
  'mom''s note',
  'the note event retains the LOSING note text for author recovery'
);
select is(
  (select (winning_row_id, losing_row_id) = (tests.ulid(911), tests.ulid(910))
     from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05' and field = 'note'),
  true,
  'the note event names the winning and losing row ids'
);
select is(
  (select (losing_author_user_id, winning_author_user_id)
     = (tests.get_supabase_uid('mom'), tests.get_supabase_uid('dad'))
     from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05' and field = 'note'),
  true,
  'the note event attributes the discard to mom and the survivor to dad'
);
select is(
  (select losing_value_text from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05' and field = 'flow'),
  'medium',
  'the flow event retains the losing flow level wire string'
);
-- Both guardians see the disclosure (the notice must reach the winner too).
select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05'),
  2::bigint,
  'the winning guardian (dad, authenticated) reads the merge events'
);
select tests.authenticate_as('mom');
select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-05'),
  2::bigint,
  'the losing guardian (mom, authenticated) reads the same merge events'
);

-- ---------------------------------------------------------------------------
-- Group B: incoming-loses merge (the older row arrives second) -- the
-- incoming row is the loser, so ITS note and flow are the retained values.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'b_dad', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(921), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'light', 'tags', '[]'::jsonb, 'note', 'dad kept this',
    'updated_at', '2026-09-06T12:00:00Z')));

select tests.authenticate_as('mom');
insert into r select 'b_mom', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'profile_id', tests.ulid(901), 'local_date', '2026-09-06',
    'tz', 'UTC', 'flow', 'heavy', 'tags', '[]'::jsonb, 'note', 'mom''s lost text',
    'updated_at', '2026-09-06T09:00:00Z')));

select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-06'),
  2::bigint,
  'incoming-loses merge discarding note+flow emits exactly two events'
);
select is(
  (select (losing_value_text, losing_row_id, winning_row_id)
     = ('mom''s lost text', tests.ulid(920), tests.ulid(921))
     from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-06' and field = 'note'),
  true,
  'the losing direction retains the incoming row''s text and row ids'
);
select is(
  (select (losing_author_user_id, winning_author_user_id)
     = (tests.get_supabase_uid('mom'), tests.get_supabase_uid('dad'))
     from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-06' and field = 'note'),
  true,
  'the losing direction attributes the loser (the pusher) and the pre-update winner'
);

-- ---------------------------------------------------------------------------
-- Group C: tags-only merge -- a set union loses nothing, so NO event.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'c_mom', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(930), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["a"]'::jsonb, 'note', 'shared wording',
    'updated_at', '2026-09-07T08:00:00Z')));

select tests.authenticate_as('dad');
insert into r select 'c_dad', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(931), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["b"]'::jsonb, 'note', 'shared wording',
    'updated_at', '2026-09-07T09:00:00Z')));

select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-07'),
  0::bigint,
  'a tags-only merge (equal note and flow) emits nothing (AC)'
);

-- ---------------------------------------------------------------------------
-- Group D: same-id convergence -- an ordinary edit of one row never runs
-- the same-date resolver, so it emits nothing even though the note changes.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'd_dad', public.sync_push('[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(931), 'profile_id', tests.ulid(901), 'local_date', '2026-09-07',
    'tz', 'UTC', 'flow', 'light', 'tags', '["b"]'::jsonb, 'note', 'a plain later edit',
    'updated_at', '2026-09-07T10:00:00Z')));

select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and local_date = '2026-09-07'),
  0::bigint,
  'a same-id convergence (ordinary edit of the surviving row) emits nothing (AC)'
);

-- ---------------------------------------------------------------------------
-- Group E: the p_merge_events push path (client-resolver-authored rows).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'e_mom', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(950), 'profile_id', tests.ulid(901), 'local_date', '2026-09-08',
    'winning_row_id', tests.ulid(911), 'losing_row_id', tests.ulid(945),
    'field', 'note', 'losing_value_text', 'a client-resolver-authored discard',
    'losing_author_user_id', tests.get_supabase_uid('mom'),
    'winning_author_user_id', tests.get_supabase_uid('dad'),
    'updated_at', '2026-09-08T11:00:01Z')));

select is(
  (select count(*) from public.day_entry_merge_events where id = tests.ulid(950)),
  1::bigint,
  'an accepted guardian can push a client-resolver-authored merge event'
);

-- Same natural key, different id: deduplicated, not rejected.
insert into r select 'e_mom2', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(951), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'winning_row_id', tests.ulid(911), 'losing_row_id', tests.ulid(910),
    'field', 'note', 'losing_value_text', 'mom''s note',
    'updated_at', '2026-09-05T11:00:02Z')));

select is(
  (select count(*) from public.day_entry_merge_events
    where profile_id = tests.ulid(901) and losing_row_id = tests.ulid(910) and field = 'note'),
  1::bigint,
  'a re-push of the same natural key (second device''s record of the same discard) is deduplicated'
);
select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(951), 'rejected', true))
     from r where name = 'e_mom2'),
  false,
  'the deduplicated re-push is accepted, not rejected'
);

-- Over-length retained text: rejected (never truncated) on the client path.
insert into r select 'e_mom3', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(952), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'winning_row_id', tests.ulid(911), 'losing_row_id', tests.ulid(930),
    'field', 'note', 'losing_value_text', repeat('x', 2001),
    'updated_at', '2026-09-05T11:00:03Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(952), 'rejected', true))
     from r where name = 'e_mom3'),
  true,
  'an over-length losing_value_text is rejected, never truncated (client path)'
);

-- Write ladder: a non-guardian and a viewer cannot push merge events.
select tests.authenticate_as('eve');
insert into r select 'e_eve', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(953), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'winning_row_id', tests.ulid(911), 'losing_row_id', tests.ulid(930),
    'field', 'flow', 'losing_value_text', 'light',
    'updated_at', '2026-09-05T11:00:04Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(953), 'rejected', true))
     from r where name = 'e_eve'),
  true,
  'a non-guardian''s merge-event push is rejected (write ladder)'
);

select tests.authenticate_as('doctor');
insert into r select 'e_doctor', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(954), 'profile_id', tests.ulid(901), 'local_date', '2026-09-05',
    'winning_row_id', tests.ulid(911), 'losing_row_id', tests.ulid(930),
    'field', 'flow', 'losing_value_text', 'light',
    'updated_at', '2026-09-05T11:00:05Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(954), 'rejected', true))
     from r where name = 'e_doctor'),
  true,
  'a viewer''s merge-event push is rejected (write ladder)'
);

-- ---------------------------------------------------------------------------
-- Group F: RLS -- reads for accepted guardians (a viewer included), never
-- for an outsider; and no direct client write path at all.
-- ---------------------------------------------------------------------------
select is(
  (select count(*) from public.day_entry_merge_events where profile_id = tests.ulid(901)),
  5::bigint,
  'a viewer guardian still reads the merge events (reads mirror day_entries)'
);
select tests.authenticate_as('eve');
select is(
  (select count(*) from public.day_entry_merge_events where profile_id = tests.ulid(901)),
  0::bigint,
  'an outsider reads no merge events (RLS)'
);
select throws_ok(
  $$insert into public.day_entry_merge_events
     (id, profile_id, local_date, winning_row_id, losing_row_id, field,
      losing_value_text, updated_at)
   values (tests.ulid(960), tests.ulid(901), '2026-09-05', tests.ulid(911), tests.ulid(910),
     'note', 'forged', now())$$,
  '42501', null,
  'no direct client INSERT path exists (sync_push is the sole writer)'
);

-- ---------------------------------------------------------------------------
-- Group G: sync_pull key, Realtime posture, and the sync_signals wake.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select is(
  (select jsonb_array_length(v -> 'day_entry_merge_events')
     from (select public.sync_pull('{}'::jsonb) as v) s),
  5,
  'sync_pull returns day_entry_merge_events pages under the guardian tenant predicate'
);
select tests.clear_authentication();
select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'day_entry_merge_events'
  ),
  'day_entry_merge_events is never published to Realtime (it carries the losing note text)'
);
select is(
  (select count(*) from public.sync_signals where profile_id = tests.ulid(901)),
  1::bigint,
  'a merge-event write fires the content-free sync_signals wake for the profile'
);

-- ---------------------------------------------------------------------------
-- Group H: the 30-day retention purge.
-- ---------------------------------------------------------------------------
insert into public.day_entry_merge_events
  (id, profile_id, local_date, winning_row_id, losing_row_id, field,
   losing_value_text, created_at, updated_at)
values
  (tests.ulid(970), tests.ulid(901), '2026-08-01', tests.ulid(911), tests.ulid(940),
   'note', 'purged - 31 days', now() - interval '31 days', now() - interval '31 days'),
  (tests.ulid(971), tests.ulid(901), '2026-08-02', tests.ulid(911), tests.ulid(941),
   'note', 'purged - 40 days', now() - interval '40 days', now() - interval '40 days'),
  (tests.ulid(972), tests.ulid(901), '2026-09-13', tests.ulid(911), tests.ulid(942),
   'note', 'kept - fresh', now() - interval '2 days', now() - interval '2 days');

select is(
  (select (public.enforce_retention() ->> 'day_entry_merge_events')::bigint),
  2::bigint,
  'enforce_retention purges merge events older than 30 days and reports the count'
);
select is(
  (select count(*) from public.day_entry_merge_events
    where id in (tests.ulid(970), tests.ulid(971))),
  0::bigint,
  'the 30-day-plus merge events are gone'
);
select is(
  (select count(*) from public.day_entry_merge_events where id = tests.ulid(972)),
  1::bigint,
  'a fresh merge event survives the purge (the recovery window)'
);

-- ---------------------------------------------------------------------------
-- Group I: tombstone_profile_content() hard-deletes the profile's merge
-- events (the only removal path on a content wipe -- the callers tombstone
-- rather than hard-delete the profile, so the FK cascade never fires).
-- ---------------------------------------------------------------------------
create temp table pre_count (c bigint);
insert into pre_count
  select count(*) from public.day_entry_merge_events where profile_id = tests.ulid(901);
create temp table wipe_result (r jsonb);
insert into wipe_result
  select public.tombstone_profile_content(tests.ulid(901), now());

select is(
  (select c from pre_count),
  (select (r ->> 'day_entry_merge_events')::bigint from wipe_result),
  'tombstone_profile_content reports the merge events it removed'
);
select is(
  (select count(*) from public.day_entry_merge_events where profile_id = tests.ulid(901)),
  0::bigint,
  'a profile content wipe removes every merge event for the profile'
);

select * from finish();
rollback;
