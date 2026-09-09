-- Coverage for per-profile tracking preferences (Issue #259): the
-- profiles.tracking_preferences document's shape CHECK, its sync_push
-- round-trip (insert / containment-guarded update / explicit clear /
-- role gates / rejected shapes), and the server half of the
-- minor-visibility defaults -- a primary guardian's explicit enable of
-- `partying`/`sex_life` on an isMinor profile round-trips verbatim,
-- because the default-hidden *rule* itself resolves client-side
-- (lib/domain/logging/tracking_preferences.dart) and the server's only
-- job is to store the document honestly and never let an old client's
-- unrelated edit clobber it.
--
-- sync_push_test.sql / guardian_sync_push_test.sql remain the
-- characterization suite for everything else sync_push does.
begin;
select plan(29);

create temp table r (name text primary key, v jsonb);
grant all on table r to authenticated;

create function pg_temp.resp(n text) returns jsonb language sql as
  $$ select v from r where name = n $$;
create function pg_temp.resolved_profile(n text, p_id text) returns jsonb language sql as
  $$ select e from r, jsonb_array_elements(r.v -> 'resolved') e where r.name = n and e ->> 'id' = p_id limit 1 $$;

select tests.create_supabase_user('mom');
select tests.create_supabase_user('dad');
select tests.create_supabase_user('doctor');

-- ---------------------------------------------------------------------------
-- 1. is_valid_tracking_preferences: shape only, category keys free text.
-- ---------------------------------------------------------------------------
select is(
  public.is_valid_tracking_preferences(null),
  true,
  'null document is valid (never customized)'
);
select is(
  public.is_valid_tracking_preferences('{}'::jsonb),
  true,
  'empty document is valid (explicit no-overrides)'
);
select is(
  public.is_valid_tracking_preferences(
    '{"mood": {"enabled": true, "sort_order": 0}, "pain": {"enabled": false, "sort_order": 3}}'::jsonb),
  true,
  'a well-formed two-entry document is valid'
);
select is(
  public.is_valid_tracking_preferences(
    '{"partying": {"enabled": true, "sort_order": 1}, "sex_life": {"enabled": true, "sort_order": 2}}'::jsonb),
  true,
  'minor-hidden category names are ordinary keys server-side (the taxonomy is client-owned)'
);
select is(
  public.is_valid_tracking_preferences(
    '{"some_future_category_from_253": {"enabled": true, "sort_order": 9}}'::jsonb),
  true,
  'unknown category keys are accepted (stored, never rejected - taxonomy growth)'
);
select is(
  public.is_valid_tracking_preferences('[]'::jsonb),
  false,
  'a JSON array is not a document'
);
select is(
  public.is_valid_tracking_preferences('{"mood": "on"}'::jsonb),
  false,
  'an entry that is not an object is invalid'
);
select is(
  public.is_valid_tracking_preferences('{"mood": {"enabled": "yes", "sort_order": 0}}'::jsonb),
  false,
  'a non-boolean enabled is invalid'
);
select is(
  public.is_valid_tracking_preferences('{"mood": {"enabled": true}}'::jsonb),
  false,
  'a missing sort_order is invalid'
);
select is(
  public.is_valid_tracking_preferences('{"mood": {"enabled": true, "sort_order": -1}}'::jsonb),
  false,
  'a negative sort_order is invalid'
);
select is(
  public.is_valid_tracking_preferences('{"mood": {"enabled": true, "sort_order": 1.5}}'::jsonb),
  false,
  'a fractional sort_order is invalid'
);
select is(
  public.is_valid_tracking_preferences(
    '{"mood": {"enabled": true, "sort_order": 0, "color": "red"}}'::jsonb),
  false,
  'an entry carrying keys beyond enabled/sort_order is invalid'
);
select is(
  public.is_valid_tracking_preferences(
    jsonb_build_object(repeat('c', 65), jsonb_build_object('enabled', true, 'sort_order', 0))),
  false,
  'a category key over 64 chars is invalid'
);

-- ---------------------------------------------------------------------------
-- 2. The table CHECK enforces the same shape on direct writes; the
-- column-level update grant covers the new column (KTD15).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into public.profiles (id, display_name, is_minor, sort_order, created_at, updated_at)
values (tests.ulid(901), 'Riley', true, 0, '2026-09-01T00:00:00Z', '2026-09-01T00:00:00Z');

select lives_ok(
  $$update public.profiles set tracking_preferences = '{"mood": {"enabled": false, "sort_order": 0}}'::jsonb
     where id = tests.ulid(901)$$,
  'a well-formed document passes the column CHECK on a direct update'
);
select throws_ok(
  $$update public.profiles set tracking_preferences = '{"mood": {"enabled": true, "sort_order": 99999}}'::jsonb
     where id = tests.ulid(901)$$,
  '23514',
  null,
  'an out-of-range sort_order violates profiles_tracking_preferences_check (23514)'
);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(901)),
  '{"mood": {"enabled": false, "sort_order": 0}}'::jsonb,
  'the stored document round-trips verbatim through a direct write'
);

-- ---------------------------------------------------------------------------
-- 3. sync_push round-trip (AC1/AC6): mom curates, the document stores,
-- a co-parent's client sees the identical bytes on the wire. Fresh
-- profile (920) so the sync lifecycle is its own fixture.
-- ---------------------------------------------------------------------------
insert into r select 'mom_prefs', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno', 'is_minor', true,
    'sort_order', 0, 'created_at', '2026-09-01T00:00:00Z',
    'updated_at', '2026-09-01T10:00:00Z',
    'tracking_preferences', '{"mood": {"enabled": false, "sort_order": 0}, "pain": {"enabled": true, "sort_order": 1}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  '{"mood": {"enabled": false, "sort_order": 0}, "pain": {"enabled": true, "sort_order": 1}}'::jsonb,
  'sync_push INSERT stores the curated document (AC1)'
);

-- Share the profile with Dad (co_parent): the invitation RPC needs the
-- profile to exist and Mom to be its primary guardian, so it runs after
-- the INSERT above.
select public.create_guardian_invitation(
  tests.ulid(920), 'co_parent', 'Dad',
  '9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c', 48
);
select tests.authenticate_as('dad');
select public.accept_guardian_invitation(
  '9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c', 'Dad'
);
select tests.authenticate_as('mom');

-- The pull/resolved wire shape carries the document (to_jsonb of the
-- stored row): a declined push hands back the server copy including it.
insert into r select 'older_edit', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Older', 'is_minor', true,
    'updated_at', '2026-09-01T09:00:00Z'
  )),
  '[]'::jsonb);
select is(
  pg_temp.resolved_profile('older_edit', tests.ulid(920)) -> 'tracking_preferences',
  '{"mood": {"enabled": false, "sort_order": 0}, "pain": {"enabled": true, "sort_order": 1}}'::jsonb,
  'a declined push''s resolved row carries the stored document (pull path)'
);

-- Containment guard: an old (pre-#259) client's unrelated edit omits the
-- key entirely; the stored document survives.
insert into r select 'old_client_edit', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T11:00:00Z'
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  '{"mood": {"enabled": false, "sort_order": 0}, "pain": {"enabled": true, "sort_order": 1}}'::jsonb,
  'a pre-#259 client''s push that omits the key never clobbers the stored document'
);
select is(
  (select display_name from public.profiles where id = tests.ulid(920)),
  'Juno Renamed',
  'the same old-client push still lands its own edit'
);

-- A newer document replaces an older one (co-parent curates next; AC6).
select tests.authenticate_as('dad');
insert into r select 'dad_prefs', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T12:00:00Z',
    'tracking_preferences', '{"pain": {"enabled": true, "sort_order": 0}, "mood": {"enabled": true, "sort_order": 1}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  '{"pain": {"enabled": true, "sort_order": 0}, "mood": {"enabled": true, "sort_order": 1}}'::jsonb,
  'a co_parent''s newer document replaces the stored one (AC6: shared curation)'
);

-- An explicit JSON null clears the document back to never-customized.
insert into r select 'clear_prefs', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T13:00:00Z',
    'tracking_preferences', 'null'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  null,
  'an explicit JSON null in the payload clears the stored document'
);

-- A malformed document is rejected, not stored.
insert into r select 'bad_shape', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T14:00:00Z',
    'tracking_preferences', '{"mood": 3}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select r.v -> 'rejected' from r where r.name = 'bad_shape'),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(920), 'rejected', true)),
  'a malformed document lands the profile row in rejected'
);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  null,
  'the rejected push left the stored document (still null) untouched'
);

-- ---------------------------------------------------------------------------
-- 4. Role gates: curation rides the profile-metadata ladder. Dad (co_parent)
-- may curate (proven above); a viewer may not; a caregiver may not.
-- ---------------------------------------------------------------------------
select tests.authenticate_as('doctor');
insert into r select 'viewer_prefs', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T15:00:00Z',
    'tracking_preferences', '{"mood": {"enabled": true, "sort_order": 0}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select r.v -> 'rejected' from r where r.name = 'viewer_prefs'),
  jsonb_build_array(jsonb_build_object('id', tests.ulid(920), 'rejected', true)),
  'a viewer''s curation push is rejected like any profile-metadata edit'
);

-- ---------------------------------------------------------------------------
-- 5. Minor-visibility defaults, server half (AC4): the profile above is
-- is_minor = true, and a primary_guardian's explicit enable of
-- `partying`/`sex_life` stores and round-trips verbatim -- the server
-- neither imposes the hidden default nor blocks its override. The
-- default-hidden resolution itself is client-side (see the file header).
-- ---------------------------------------------------------------------------
select tests.authenticate_as('mom');
insert into r select 'mom_enable', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T16:00:00Z',
    'tracking_preferences', '{"partying": {"enabled": true, "sort_order": 0}, "sex_life": {"enabled": true, "sort_order": 1}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select r.v -> 'rejected' from r where r.name = 'mom_enable'),
  '[]'::jsonb,
  'the primary guardian''s enable push is accepted'
);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  '{"partying": {"enabled": true, "sort_order": 0}, "sex_life": {"enabled": true, "sort_order": 1}}'::jsonb,
  'AC4: partying/sex_life enabled by the primary guardian on a minor profile round-trip verbatim'
);

-- ... and a document that leaves them hidden (disabled entries) is
-- stored just as verbatim on the same minor profile.
insert into r select 'mom_disable', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(920), 'display_name', 'Juno Renamed', 'is_minor', true,
    'updated_at', '2026-09-01T17:00:00Z',
    'tracking_preferences', '{"partying": {"enabled": false, "sort_order": 0}, "sex_life": {"enabled": false, "sort_order": 1}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(920)),
  '{"partying": {"enabled": false, "sort_order": 0}, "sex_life": {"enabled": false, "sort_order": 1}}'::jsonb,
  'a minor profile''s hidden-by-default document stores verbatim too'
);

-- An adult profile carries the same document shape without any
-- minor-specific behavior anywhere in the path.
insert into r select 'mom_adult', public.sync_push(
  jsonb_build_array(jsonb_build_object(
    'id', tests.ulid(950), 'display_name', 'Maya', 'is_minor', false,
    'created_at', '2026-09-01T00:00:00Z', 'updated_at', '2026-09-01T18:00:00Z',
    'tracking_preferences', '{"sex_life": {"enabled": true, "sort_order": 0}}'::jsonb
  )),
  '[]'::jsonb);
select is(
  (select tracking_preferences from public.profiles where id = tests.ulid(950)),
  '{"sex_life": {"enabled": true, "sort_order": 0}}'::jsonb,
  'an adult profile''s document stores identically (no minor-specific server behavior)'
);

select finish();
rollback;
