-- Coverage for 20260917000000_profile_tag_registry.sql (Issue #257): the
-- table posture (RLS + no client write grant), the p_tag_registry push
-- path (round trip, created_by server-stamping, the write ladder, the
-- case-insensitive live-code dedupe, the 100-live-rows-per-profile cap,
-- retirement via hidden_at, tombstones and their payload-clearing CHECK,
-- the containment guards), reads for accepted guardians vs an outsider,
-- the sync_pull key, the Realtime never-publish posture + sync_signals
-- wake, and tombstone_profile_content()'s registry tombstone step.
begin;
select plan(41);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doctor');
select tests.create_supabase_user('eve');

-- ---------------------------------------------------------------------------
-- Table posture.
-- ---------------------------------------------------------------------------
select tests.rls_enabled('public', 'profile_tag_registry');
select tests.rls_forced('public', 'profile_tag_registry');

-- ---------------------------------------------------------------------------
-- Setup: Mom's profile P1, shared with Dad (co_parent) and Doctor
-- (viewer); Eve is an outsider with no relationship to the profile.
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
-- Group A: the push round trip, created_by server-stamping, and the
-- containment guards.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'a_create', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'code', 'back_cracking',
    'display_name', 'Back cracking', 'category', 'custom',
    'intensity_enabled', true, 'sort_order', 1,
    'updated_at', '2026-09-10T10:00:00Z')));

select is(
  (select count(*) from public.profile_tag_registry where id = tests.ulid(910)),
  1::bigint,
  'an accepted guardian can push a registry row'
);
select is(
  (select (created_by, display_name, intensity_enabled) = (tests.get_supabase_uid('mom'), 'Back cracking', true)
     from public.profile_tag_registry where id = tests.ulid(910)),
  true,
  'the pushed row round-trips its payload, with created_by stamped from the caller'
);

-- created_by is never accepted per-row: a row carrying it is an unknown key.
insert into r select 'a_forged', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(911), 'profile_id', tests.ulid(901), 'code', 'forged',
    'display_name', 'Forged', 'category', 'custom',
    'created_by', tests.get_supabase_uid('dad'),
    'updated_at', '2026-09-10T10:00:00Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(911), 'rejected', true))
     from r where name = 'a_forged'),
  true,
  'a row carrying created_by is rejected as an unknown key (server stamps it)'
);

-- A rename (display_name change) at a newer updated_at lands; omitting the
-- optional intensity_enabled key preserves the stored value (containment
-- guard).
insert into r select 'a_rename', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'code', 'back_cracking',
    'display_name', 'Back cracking (upper)', 'category', 'custom',
    'updated_at', '2026-09-10T11:00:00Z')));

select is(
  (select (display_name, intensity_enabled) = ('Back cracking (upper)', true)
     from public.profile_tag_registry where id = tests.ulid(910)),
  true,
  'a newer rename lands, and an omitted optional key preserves the stored value'
);

-- An equal-timestamp re-push of a live row is declined with the server
-- copy handed back (idempotence).
insert into r select 'a_equal', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(901), 'code', 'back_cracking',
    'display_name', 'Back cracking (stale)', 'category', 'custom',
    'updated_at', '2026-09-10T11:00:00Z')));

select is(
  (select (r.v -> 'resolved') @> jsonb_build_array(jsonb_build_object('table', 'profile_tag_registry')
     || jsonb_build_object('id', tests.ulid(910)))
     from r where name = 'a_equal'),
  true,
  'an equal-timestamp live re-push is declined with the server copy handed back'
);
select is(
  (select display_name from public.profile_tag_registry where id = tests.ulid(910)),
  'Back cracking (upper)',
  'the declined equal-timestamp push did not overwrite the stored label'
);

-- ---------------------------------------------------------------------------
-- Group B: the write ladder -- a co_parent writes, a caregiver writes, a
-- viewer and an outsider do not.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
insert into r select 'b_dad', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'code', 'vulva_pain',
    'display_name', 'Vulva pain?!', 'category', 'custom',
    'updated_at', '2026-09-10T12:00:00Z')));

select is(
  (select count(*) from public.profile_tag_registry where id = tests.ulid(912)),
  1::bigint,
  'a co_parent can push a registry row (the day_entries ladder)'
);

select tests.authenticate_as('doctor');
insert into r select 'b_doctor', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(913), 'profile_id', tests.ulid(901), 'code', 'viewer_tag',
    'display_name', 'Viewer tag', 'category', 'custom',
    'updated_at', '2026-09-10T12:00:00Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(913), 'rejected', true))
     from r where name = 'b_doctor'),
  true,
  'a viewer''s registry push is rejected (viewer read-only)'
);

select tests.authenticate_as('eve');
insert into r select 'b_eve', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(914), 'profile_id', tests.ulid(901), 'code', 'outsider_tag',
    'display_name', 'Outsider tag', 'category', 'custom',
    'updated_at', '2026-09-10T12:00:00Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(914), 'rejected', true))
     from r where name = 'b_eve'),
  true,
  'a non-guardian''s registry push is rejected (the day_entries ladder)'
);

-- A registry row cannot move between profiles (the immutability guard).
-- Profile P2 is created through sync_push (not a direct INSERT) so the
-- on_profile_created_add_guardian trigger makes Mom its primary guardian
-- -- otherwise her later pushes against P2 would fail the role check
-- before the move guard could ever run.
select tests.authenticate_as('mom');
insert into r select 'b_p2', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(902), 'display_name', 'Sam',
    'updated_at', '2026-09-10T12:30:00Z')),
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb);
insert into r select 'b_move', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(910), 'profile_id', tests.ulid(902), 'code', 'back_cracking',
    'display_name', 'Moved', 'category', 'custom',
    'updated_at', '2026-09-10T13:00:00Z')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(910), 'rejected', true))
     from r where name = 'b_move'),
  true,
  'a registry row cannot move between profiles'
);

-- ---------------------------------------------------------------------------
-- Group C: the case-insensitive live-code collision resolution (Issue #825).
-- ---------------------------------------------------------------------------
-- Incoming wins: 915 is newer than stored 910, so 915 becomes live and 910
-- becomes a payload-free tombstone returned in resolved (0 rejections).
insert into r select 'c_case', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(915), 'profile_id', tests.ulid(901), 'code', 'BACK_CRACKING',
    'display_name', 'Duplicate', 'category', 'custom',
    'updated_at', '2026-09-10T14:00:00Z')));

select is(
  (select coalesce(r.v -> 'rejected', '[]'::jsonb) from r where name = 'c_case'),
  '[]'::jsonb,
  'a colliding code in different case is resolved via LWW, not rejected'
);
select is(
  (select (deleted_at is not null and display_name = '') from public.profile_tag_registry where id = tests.ulid(910)),
  true,
  'the older stored sibling becomes a payload-free tombstone'
);
select is(
  (select (deleted_at is null and display_name = 'Duplicate') from public.profile_tag_registry where id = tests.ulid(915)),
  true,
  'the newer incoming row is stored as live'
);
select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and lower(code) = 'back_cracking' and deleted_at is null),
  1::bigint,
  'exactly one live row survives incoming-wins same-code collision'
);

-- Incoming loses: 918 is older than stored 915 (13:00 < 14:00), so 918 is
-- stored as a payload-free tombstone, 915 stays live, and both are returned
-- in resolved (0 rejections).
insert into r select 'c_case_loses', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(918), 'profile_id', tests.ulid(901), 'code', 'back_cracking',
    'display_name', 'Older duplicate', 'category', 'custom',
    'updated_at', '2026-09-10T13:00:00Z')));

select is(
  (select coalesce(r.v -> 'rejected', '[]'::jsonb) from r where name = 'c_case_loses'),
  '[]'::jsonb,
  'an older colliding code is not rejected (incoming-loses collision)'
);
select is(
  (select (deleted_at is not null and display_name = '') from public.profile_tag_registry where id = tests.ulid(918)),
  true,
  'the older incoming row is stored as a payload-free tombstone'
);
select is(
  (select deleted_at is null from public.profile_tag_registry where id = tests.ulid(915)),
  true,
  'the newer stored row remains live'
);
select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and lower(code) = 'back_cracking' and deleted_at is null),
  1::bigint,
  'exactly one live row survives incoming-loses same-code collision'
);

-- The same code under a DIFFERENT profile is fine (the dedupe is per-profile).
insert into r select 'c_other_profile', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(916), 'profile_id', tests.ulid(902), 'code', 'back_cracking',
    'display_name', 'Sam''s own', 'category', 'custom',
    'updated_at', '2026-09-10T14:00:00Z')));

select is(
  (select count(*) from public.profile_tag_registry where id = tests.ulid(916)),
  1::bigint,
  'the same code under another profile is accepted (per-profile dedupe)'
);

-- ---------------------------------------------------------------------------
-- Group D: retirement (hidden_at) -- the picker-removal write that never
-- deletes, and its reversal.
-- ---------------------------------------------------------------------------
insert into r select 'd_retire', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'code', 'vulva_pain',
    'display_name', 'Vulva pain?!', 'category', 'custom',
    'hidden_at', '2026-09-11T09:00:00Z',
    'updated_at', '2026-09-11T09:00:00Z')));

select is(
  (select (hidden_at is not null and deleted_at is null and display_name = 'Vulva pain?!')
     from public.profile_tag_registry where id = tests.ulid(912)),
  true,
  'retiring sets hidden_at and removes nothing else (retirement, not deletion)'
);

-- Un-retire: a newer write with an explicit null hidden_at clears it.
insert into r select 'd_unretire', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'code', 'vulva_pain',
    'display_name', 'Vulva pain?!', 'category', 'custom',
    'hidden_at', null,
    'updated_at', '2026-09-11T10:00:00Z')));

select is(
  (select hidden_at is null from public.profile_tag_registry where id = tests.ulid(912)),
  true,
  'an explicit null hidden_at at a newer updated_at un-retires the tag'
);

-- Retirement state survives a pull round trip: the day_entries tags
-- referencing the code are untouched (the registry never gates writes).
insert into r select 'd_entry', public.sync_push(
  '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(940), 'profile_id', tests.ulid(901), 'local_date', '2026-09-11',
    'tz', 'UTC', 'flow', 'none', 'tags', '["vulva_pain","not_a_registry_code"]'::jsonb,
    'updated_at', '2026-09-11T11:00:00Z')));

select is(
  (select (r.v -> 'rejected')::text
     from r where name = 'd_entry'),
  '[]',
  'a day entry whose tags include a retired registry code AND an unknown code is accepted unchanged (the registry is never an allowlist)'
);

-- ---------------------------------------------------------------------------
-- Group E: tombstones -- payload cleared per the structural CHECK, code
-- surviving, LWW decline of an older live re-push, and re-creation of the
-- same code after the tombstone.
-- ---------------------------------------------------------------------------
insert into r select 'e_tombstone', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'code', 'vulva_pain',
    'display_name', 'Vulva pain?!', 'category', 'custom',
    'updated_at', '2026-09-12T09:00:00Z', 'deleted_at', '2026-09-12T09:00:00Z')));

select is(
  (select (deleted_at is not null and code = 'vulva_pain' and display_name = ''
           and category = '' and hidden_at is null and intensity_enabled = false)
     from public.profile_tag_registry where id = tests.ulid(912)),
  true,
  'a tombstone lands payload-free per the CHECK, with code surviving'
);

-- An older live push cannot resurrect the tombstoned row.
insert into r select 'e_resurrect', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(912), 'profile_id', tests.ulid(901), 'code', 'vulva_pain',
    'display_name', 'Zombie', 'category', 'custom',
    'updated_at', '2026-09-11T10:00:00Z')));

select is(
  (select display_name from public.profile_tag_registry where id = tests.ulid(912)),
  '',
  'an older live push is declined against the tombstone (no resurrection)'
);

-- The tombstone frees the code: a NEW live row with the same code is
-- accepted (the partial unique index).
insert into r select 'e_recreate', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(917), 'profile_id', tests.ulid(901), 'code', 'Vulva_Pain',
    'display_name', 'Vulva pain (new)', 'category', 'custom',
    'updated_at', '2026-09-12T10:00:00Z')));

select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and lower(code) = 'vulva_pain' and deleted_at is null),
  1::bigint,
  'a tombstoned code can be re-created live (partial unique index)'
);

-- ---------------------------------------------------------------------------
-- Group F: the 100-live-rows-per-profile cap, enforced in the RPC.
-- ---------------------------------------------------------------------------
insert into r select 'f_bulk', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  (select jsonb_agg(jsonb_build_object(
      'id', tests.ulid(2000 + g), 'profile_id', tests.ulid(901),
      'code', 'bulk_' || g, 'display_name', 'Bulk ' || g, 'category', 'custom',
      'updated_at', now() - interval '1 hour'))
     from generate_series(1, 97) g));

select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and deleted_at is null and code like 'bulk_%'),
  97::bigint,
  'a bulk push of 97 rows lands (P1 currently holds 99 live rows: 97 bulk + back_cracking + vulva_pain (new))'
);

-- The 100th live row is fine; the 101st is rejected.
insert into r select 'f_100th', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2100), 'profile_id', tests.ulid(901), 'code', 'hundredth',
    'display_name', 'Hundredth', 'category', 'custom',
    'updated_at', now() - interval '1 hour')));

select is(
  (select count(*) from public.profile_tag_registry where id = tests.ulid(2100)),
  1::bigint,
  'the 100th live registry row is accepted (cap is inclusive)'
);

insert into r select 'f_101st', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2101), 'profile_id', tests.ulid(901), 'code', 'onehundredfirst',
    'display_name', 'One hundred first', 'category', 'custom',
    'updated_at', now() - interval '1 hour')));

select is(
  (select (r.v -> 'rejected') @> jsonb_build_array(jsonb_build_object('id', tests.ulid(2101), 'rejected', true))
     from r where name = 'f_101st'),
  true,
  'the 101st live registry row is rejected at the per-profile cap'
);

-- An UPDATE to an already-live row at the cap is NOT blocked (it adds
-- nothing to the live count).
insert into r select 'f_update_at_cap', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2100), 'profile_id', tests.ulid(901), 'code', 'hundredth',
    'display_name', 'Hundredth (edited)', 'category', 'custom',
    'updated_at', now())));

select is(
  (select display_name from public.profile_tag_registry where id = tests.ulid(2100)),
  'Hundredth (edited)',
  'an update to an already-live row at the cap is accepted (no double count)'
);

-- A TOMBSTONE for a new id is not blocked by the cap either (it never
-- lands live) -- and it then frees a slot.
insert into r select 'f_tombstone_new', public.sync_push(
  '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb, '[]'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(2102), 'profile_id', tests.ulid(901), 'code', 'dead_on_arrival',
    'display_name', 'Dead on arrival', 'category', 'custom',
    'updated_at', now(), 'deleted_at', now())));

select is(
  (select (r.v -> 'rejected')::text
     from r where name = 'f_tombstone_new'),
  '[]',
  'a tombstone push is not blocked by the live-row cap'
);

-- ---------------------------------------------------------------------------
-- Group G: RLS -- reads for accepted guardians (a viewer included), never
-- for an outsider; and no direct client write path at all.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doctor');
select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and deleted_at is null),
  100::bigint,
  'a viewer guardian still reads the registry (reads mirror day_entries)'
);
select tests.authenticate_as('eve');
select is(
  (select count(*) from public.profile_tag_registry where profile_id = tests.ulid(901)),
  0::bigint,
  'an outsider reads no registry rows (RLS)'
);
select throws_ok(
  $$insert into public.profile_tag_registry
     (id, profile_id, code, display_name, category, updated_at)
   values (tests.ulid(2199), tests.ulid(901), 'forged', 'Forged', 'custom', now())$$,
  '42501', null,
  'no direct client INSERT path exists (sync_push is the sole writer)'
);

-- ---------------------------------------------------------------------------
-- Group H: the sync_pull key, the Realtime posture, and the sync_signals
-- wake.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('dad');
select is(
  (select jsonb_array_length(v -> 'profile_tag_registry')::bigint
     from (select public.sync_pull('{}'::jsonb) as v) s),
  (select count(*) from public.profile_tag_registry
     where profile_id = any(array(
       select profile_id from public.profile_guardians
        where user_id = tests.get_supabase_uid('dad') and status = 'accepted'))),
  'sync_pull returns profile_tag_registry pages under the guardian tenant predicate'
);
select tests.clear_authentication();
select ok(
  not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'profile_tag_registry'
  ),
  'profile_tag_registry is never published to Realtime (it carries user-authored health vocabulary)'
);
select is(
  (select count(*) from public.sync_signals where profile_id = tests.ulid(901)),
  1::bigint,
  'a registry write fires the content-free sync_signals wake for the profile'
);

-- ---------------------------------------------------------------------------
-- Group I: tombstone_profile_content() tombstones the profile's registry
-- rows (propagating the wipe to co-guardian devices via the ordinary
-- pull), rather than hard-deleting them.
-- ---------------------------------------------------------------------------
create temp table pre_count (c bigint);
insert into pre_count
  select count(*) from public.profile_tag_registry
   where profile_id = tests.ulid(901) and deleted_at is null;
create temp table wipe_result (r jsonb);
insert into wipe_result
  select public.tombstone_profile_content(tests.ulid(901), now());

select is(
  (select c from pre_count),
  (select (r ->> 'profile_tag_registry')::bigint from wipe_result),
  'tombstone_profile_content reports the registry rows it tombstoned'
);
select is(
  (select count(*) from public.profile_tag_registry
    where profile_id = tests.ulid(901) and deleted_at is null),
  0::bigint,
  'a profile content wipe tombstones every live registry row'
);
select is(
  (select bool_and(code <> '' and display_name = '')
     from public.profile_tag_registry where profile_id = tests.ulid(901)),
  true,
  'the wiped registry rows keep their codes (re-import recognition) with payload cleared'
);

select * from finish();
rollback;
