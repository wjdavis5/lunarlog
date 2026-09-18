-- ===========================================================================
-- 20260918150000_guardian_notes.sql
-- Issue #801 (P1, feat(sharing)): per-guardian dated notes on a child's day.
--
-- The owner's stated core of the product: "parents being able to help their
-- daughters ... with the ability to add their own notes / observations for
-- the children." `DayEntry.note` is a single shared String? per day with no
-- author, so a parent writing about her daughter's day writes into the
-- daughter's note and two writers collide (the #130 merge-disclosure
-- machinery exists to let the losing author recover discarded text -- a
-- disclosure of the collision, not a fix). Nothing in the app is BOTH
-- date-bound AND author-scoped. This table is.
--
-- Shape (mirrors public.care_notes closely; see
-- 20260909141503_care_notes_visit_prep.sql):
--   * one row per (author, profile, date); distinct ULIDs, so two guardians
--     writing offline on the same day both survive;
--   * per-id last-writer-wins by updated_at, with tombstones;
--   * no cross-author merge, ever -- this is not a chat feature.
--
-- Visibility (issue #800, decided): open and transparent. Every accepted
-- guardian -- the child included -- reads every guardian note. There is no
-- per-note visibility column and no hidden-note mechanism. The client is
-- required to state that audience at the point of writing (issue #801's
-- disclosure-copy acceptance criterion); the server enforces the read ladder.
--
-- THIS MIGRATION CONTAINS ONE NEW TABLE AND ONE FUNCTION RE-EMISSION. DDL
-- summary for the deploy approver:
--   1. create table public.guardian_notes (... primary key (id), FK
--      profile_id -> public.profiles(id) on delete cascade, ULID/body-length/
--      tz/date/tombstone CHECKs) -- additive only, no existing table altered.
--   2. create index guardian_notes_profile_id_idx, guardian_notes_local_date_idx,
--      guardian_notes_server_version_idx -- additive.
--   3. create trigger guardian_notes_set_server_version (reuses the existing
--      public.set_server_version()) and guardian_notes_after_change_signal
--      (reuses the existing public.touch_sync_signal()) -- additive.
--   4. alter table public.guardian_notes enable/force row level security;
--      three policies (select for any accepted guardian, insert/update for
--      primary_guardian/co_parent/caregiver) -- replicates the care_notes
--      ladder exactly, via the existing public.is_profile_guardian() /
--      public.is_guardian_with_roles() helpers. No role logic is duplicated.
--   5. revoke all + grant select, insert + column-list update -- the
--      care_notes grant shape.
--   6. two attribution trigger bindings to the existing generic
--      public.enforce_care_note_attribution() -- no new guard function.
--   7. drop function public.sync_push(9x jsonb); create or replace
--      public.sync_push(10x jsonb) from the current definition
--      (20260918100000) with one new parameter p_guardian_notes jsonb
--      default '[]' and one new per-id LWW loop. The ten allowlists are
--      re-derived through public.sync_push_payload_keys(t) at CREATE time
--      (the #181 DO-block recipe; AGENTS.md Migration Flow item 9), so the
--      new table's columns join the accepted-key set automatically.
--   8. grant execute on the new 10-arg sync_push to authenticated; revoke
--      from public, anon.
-- No existing table/column is altered, no RLS is weakened, and
-- sync_pull/delete_*/enforce_retention are deliberately untouched (see the
-- PR body's "Not done").
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. public.guardian_notes
-- ---------------------------------------------------------------------------

create table public.guardian_notes (
  id text not null
    constraint guardian_notes_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  -- The calendar day the note is about (the date-bound half of the model;
  -- care_notes has no date, day_entries.note has no author).
  local_date date not null,
  -- The zone the author's day was measured in, length-bounded and
  -- validity-checked exactly like day_entries.tz / observations.tz.
  tz text not null
    constraint guardian_notes_tz_length_check
    check (char_length(tz) <= 64),
  -- Free text (health content about a minor). Not null with an '' tombstone
  -- sentinel (see the tombstone CHECK), length-bounded by 2000
  -- (kMaxCareNoteLength / day_entries.note posture) -- rejected, never
  -- truncated. Scrubbed from crash reports; never in a notification.
  body text not null default ''
    constraint guardian_notes_body_length_check
    check (char_length(body) <= 2000),
  -- The original author. Author-inmutable: enforce_care_note_attribution()
  -- (reused below) rejects any change on UPDATE, and sync_push refuses an
  -- edit or tombstone whose stored author is not the caller -- so a
  -- guardian can only ever edit or remove her own note.
  logged_by_user_id uuid references auth.users (id) on delete set null,
  last_modified_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null,
  deleted_at timestamptz,
  server_version bigint not null default 0,
  primary key (id),
  -- Structural backstop (issue #224 precedent): a tombstone carries the ''
  -- body sentinel and nothing else.
  constraint guardian_notes_tombstone_payload_check
    check (
      deleted_at is null
      or (body = '')
    )
);

alter table public.guardian_notes
  add constraint guardian_notes_tz_valid
  check (public.is_valid_timezone(tz));

comment on table public.guardian_notes is
  'Issue #801: one dated, author-scoped guardian note per row on a profile -- the mirror gap to care_notes: date-bound AND attributed, never merged with another author''s note for the same day. Distinct ULIDs and per-id last-writer-wins by updated_at (see the migration header). Tombstones (deleted_at not null) carry the '''' body sentinel and nothing else (guardian_notes_tombstone_payload_check). Length-bounded by guardian_notes_body_length_check (2000, mirroring day_entries.note / care_notes.body). Every accepted guardian reads every row (issue #800: open and transparent, the child included); primary_guardian/co_parent/caregiver write; viewer rejected. logged_by_user_id is author-immutable and is what sync_push checks before allowing an edit or tombstone.';

create index guardian_notes_profile_id_idx
  on public.guardian_notes (profile_id);
-- The day-sheet read is per profile + date; the calendar marker also scans
-- by profile + date.
create index guardian_notes_profile_local_date_idx
  on public.guardian_notes (profile_id, local_date);
create index guardian_notes_server_version_idx
  on public.guardian_notes (server_version);

create trigger guardian_notes_set_server_version
  before insert or update on public.guardian_notes
  for each row execute function public.set_server_version();

-- Realtime: no new publication membership. guardian_notes reuses the
-- existing content-free public.sync_signals wake-signal exactly like
-- care_notes (touch_sync_signal() branches on new.profile_id/old.profile_id
-- for anything that is not literally the profiles table), so only this
-- trigger wiring is needed.
create trigger guardian_notes_after_change_signal
  after insert or update or delete on public.guardian_notes
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- 2. Attribution guards -- the existing generic guard, reused (not a
--    duplicated function). It pins logged_by_user_id on UPDATE and refuses
--    a caller-spoofed attribution on INSERT; the author-ownership rule (only
--    the original author may edit/tombstone) is enforced in sync_push below.
-- ---------------------------------------------------------------------------

create trigger guardian_notes_attribution_insert_guard
  before insert on public.guardian_notes
  for each row execute function public.enforce_care_note_attribution();

create trigger guardian_notes_attribution_update_guard
  before update on public.guardian_notes
  for each row execute function public.enforce_care_note_attribution();

-- ---------------------------------------------------------------------------
-- 3. Row-Level Security -- the care_notes/day_entries write ladder exactly
--    (any accepted guardian reads; primary_guardian/co_parent/caregiver
--    writes; viewer rejected), reusing the existing role-derivation helpers.
--    No client DELETE anywhere (tombstone-only, like every synced table).
-- ---------------------------------------------------------------------------

alter table public.guardian_notes enable row level security;
alter table public.guardian_notes force row level security;

create policy "guardian_notes_select_guardians" on public.guardian_notes
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

create policy "guardian_notes_insert_guardians" on public.guardian_notes
  for insert to authenticated
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

create policy "guardian_notes_update_guardians" on public.guardian_notes
  for update to authenticated
  using (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  )
  with check (
    public.is_guardian_with_roles(profile_id, (select auth.uid()), array['primary_guardian', 'co_parent', 'caregiver'])
  );

-- ---------------------------------------------------------------------------
-- 4. Privileges (the care_notes shape: column-list grants, no DELETE).
--    profile_id is granted so a client row can round-trip it, but sync_push
--    refuses a move between profiles; logged_by_user_id is never granted for
--    update (author-immutable).
-- ---------------------------------------------------------------------------

revoke all on table public.guardian_notes from public, anon, authenticated;

grant select, insert on table public.guardian_notes to authenticated;
grant update (
  profile_id, local_date, tz, body, updated_at, deleted_at
) on table public.guardian_notes to authenticated;
grant update (last_modified_by_user_id) on table public.guardian_notes to authenticated;

-- ---------------------------------------------------------------------------
-- 5. sync_push is re-emitted from 20260918100000 with one new parameter
--    (p_guardian_notes) and one new per-id loop. Adding a parameter changes
--    the signature, so the 9-argument overload is dropped first (the exact
--    trap documented in 20260909141503's header: an un-dropped older
--    overload silently forks the function in two).
-- ---------------------------------------------------------------------------

drop function if exists public.sync_push(
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb);

do $derive$
declare
  v_tables constant text[] := array[
    'profiles', 'day_entries', 'observations', 'profile_modes',
    'cycle_overrides', 'care_notes', 'visit_prep_items',
    'day_entry_merge_events', 'profile_tag_registry', 'guardian_notes'];
  v_t text;
  v_derived text[];
  v_src text;
  v_body text;
begin
  -- Sanity-check every derived set before it is embedded (the same checks
  -- 20260917120000's DO block ran; no hand-written prior baseline is
  -- restated here because no allowlist changes -- the pgTAP suite's
  -- re-derivation against the live body remains the drift catch).
  for v_t in select unnest(v_tables) loop
    v_derived := public.sync_push_payload_keys(v_t);
    if v_derived is null or cardinality(v_derived) = 0 then
      raise exception 'derived allowlist for % is empty -- is the table name right?', v_t
        using errcode = 'object_not_in_prerequisite_state';
    end if;
    if exists (select 1 from unnest(v_derived) k where k !~ '^[a-z_][a-z0-9_]*$') then
      raise exception 'derived allowlist for % has a non-identifier element: %',
        v_t, (select string_agg(k, ', ') from unnest(v_derived) k where k !~ '^[a-z_][a-z0-9_]*$')
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end loop;

  -- The 20260918000000 statement verbatim except the nine array
  -- declarations (placeholder tokens) and the Issue #192 profile_modes
  -- estimated_due_date edits (declare/parse/insert/update).
  v_body := $ddl$
create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb,
  p_profile_modes jsonb default '[]'::jsonb,
  p_cycle_overrides jsonb default '[]'::jsonb,
  p_care_notes jsonb default '[]'::jsonb,
  p_visit_prep_items jsonb default '[]'::jsonb,
  p_merge_events jsonb default '[]'::jsonb,
  p_tag_registry jsonb default '[]'::jsonb,
  p_guardian_notes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  c_max_rows constant integer := 500;
  c_max_observations_per_day constant integer := 200;
  -- Issue #564: total-row cap across all payload arrays combined.
  -- 3500 (= 7 * c_max_rows) was a no-op cap when seven arrays existed;
  -- Issue #130 grew it to 4000 for the eighth (p_merge_events); Issue
  -- #257 grew it to 4500 for the ninth (p_tag_registry); Issue #801 grows
  -- it to 5000 (= 10 * c_max_rows) for the tenth (p_guardian_notes) --
  -- still exactly one full batch per array, still a no-op rather than a
  -- real tightening (the Dart sync engine legitimately fills every table to
  -- 500 rows each on a first sync or a post-Clue-import push; a lower cap
  -- would reject that call outright and the client would retry it forever).
  -- A stricter combined cap needs a client-side batch-size change first.
  c_max_total_rows constant integer := 5000;
  -- Issue #257: the per-profile custom-tag registry's live-row ceiling.
  -- Enforced here rather than by a CHECK for the same reason
  -- c_max_observations_per_day lives here: a CHECK cannot count sibling
  -- rows.
  c_max_tags_per_profile constant integer := 100;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  -- Issue #181: the ten per-table key allowlists below are DERIVED, not
  -- hand-restated. Each is the set of columns information_schema reports
  -- for its table, minus that table's server-stamped columns (never
  -- accepted from a payload because the RPC stamps them from the caller)
  -- plus that table's legacy tolerated keys (accepted but never read).
  -- The derivation lives in public.sync_push_payload_keys(text) and was
  -- materialized into this body at CREATE time by 20260917120000's DO
  -- block -- a per-call information_schema read on the sync hot path was
  -- deliberately rejected, and so was call-time derivation generally:
  -- this is a SECURITY DEFINER function, and letting a later grant change
  -- silently widen the accepted-key set with zero code review is exactly
  -- the drift the issue exists to close. Per-table shape (pinned by
  -- supabase/tests/sync_push_derived_allowlists_test.sql):
  --   profiles / observations / profile_modes / cycle_overrides /
  --     care_notes: every column of the table, nothing ignored
  --   day_entries / day_entry_merge_events: minus created_at (stamped)
  --   profile_tag_registry: minus created_by, created_at (stamped)
  --   visit_prep_items: minus checked_by_user_id, checked_at (stamped)
  --   observations / care_notes / visit_prep_items: plus the legacy
  --     'user_id' key (tolerated but never read; not a column any of
  --     these tables has ever had, kept so an old client echoing one is
  --     not rejected)
  -- Tolerated-but-never-read members that ARE real columns (user_id,
  -- server_version, logged_by_user_id, last_modified_by_user_id,
  -- created_at where listed above, transferred_at,
  -- transferred_to_user_id) are ordinary members of these arrays exactly
  -- as before: the per-row key check admits them, the parse/INSERT/UPDATE
  -- paths ignore or stamp them.
  c_profile_keys constant text[] := __SYNC_PUSH_PROFILE_KEYS__;
  c_day_entry_keys constant text[] := __SYNC_PUSH_DAY_ENTRY_KEYS__;
  c_observation_keys constant text[] := __SYNC_PUSH_OBSERVATION_KEYS__;
  c_profile_mode_keys constant text[] := __SYNC_PUSH_PROFILE_MODE_KEYS__;
  c_cycle_override_keys constant text[] := __SYNC_PUSH_CYCLE_OVERRIDE_KEYS__;
  c_care_note_keys constant text[] := __SYNC_PUSH_CARE_NOTE_KEYS__;
  c_visit_prep_item_keys constant text[] := __SYNC_PUSH_VISIT_PREP_ITEM_KEYS__;
  c_merge_event_keys constant text[] := __SYNC_PUSH_MERGE_EVENT_KEYS__;
  c_tag_registry_keys constant text[] := __SYNC_PUSH_TAG_REGISTRY_KEYS__;
  c_guardian_note_keys constant text[] := __SYNC_PUSH_GUARDIAN_NOTE_KEYS__;

  v_uid uuid := (select auth.uid());
  v_row jsonb;
  v_resolved jsonb := '[]'::jsonb;
  v_rejected jsonb := '[]'::jsonb;

  -- parsed incoming row
  v_id text;
  v_updated_at timestamptz;
  v_deleted_at timestamptz;
  v_created_at timestamptz;
  v_archived_at timestamptz;
  v_display_name text;
  v_is_minor boolean;
  v_sort_order integer;
  v_birth_year smallint;
  v_relationship text;
  -- #131: care mode; absent key parses to the column default
  v_mode text;
  -- #218: onboarding cycle facts
  v_last_period_start date;
  v_typical_cycle_length_days smallint;
  v_typical_period_length_days smallint;
  -- #255: numeric-measurement display-unit preferences; absent keys parse
  -- to the column defaults
  v_bbt_unit text;
  v_weight_unit text;
  -- #259: the tracking-preferences document (jsonb, null when absent or
  -- explicitly null in the payload)
  v_tracking_preferences jsonb;
  v_profile_id text;
  v_local_date date;
  v_tz text;
  v_flow text;
  v_tags jsonb;
  v_note text;
  -- Issue #220: the first-class PMS marker.
  v_pms boolean;

  v_stored_profile public.profiles%rowtype;
  v_stored public.day_entries%rowtype;
  v_other public.day_entries%rowtype;
  v_accept boolean;
  v_incoming_wins boolean;
  -- Issue #170: merged_discard fields whose LOSING row is the incoming
  -- one -- collected in the resolver's incoming-loses branch and emitted
  -- only after that row is stored, because the day_entry_history row's
  -- entry_id FK requires the loser to exist in day_entries first (a
  -- brand-new incoming loser is inserted at the END of this iteration).
  -- Reset per row at the top of the day_entries loop.
  v_pending_discard_fields text[];
  v_caller_role text;
  -- Issue #564: profile_id -> role, computed once (not per row) for the
  -- six loops below that need it (day_entries, observations, profile_modes,
  -- cycle_overrides, care_notes, visit_prep_items).
  v_role_map jsonb;

  -- Issue #240: observations parsing/resolution state.
  v_day_entry_id text;
  v_observed_at timestamptz;
  v_category text;
  v_code text;
  v_value_num numeric;
  v_value_text text;
  v_unit text;
  v_intensity smallint;
  v_excluded boolean;
  v_source text;
  v_source_id text;
  -- Issue #159: shared by the day_entries loop and the observations loop
  -- below, exactly like v_profile_id/v_local_date/v_tz already are --
  -- the two loops run sequentially, never concurrently.
  v_import_id uuid;
  -- Issue #186: the round-trip-write marker, same provenance class as
  -- v_import_id (parsed unconditionally, never cleared on a tombstone).
  v_exported_to_platform_at timestamptz;
  v_raw jsonb;
  v_day_entry_profile_id text;
  -- Issue #524: the day entry's own tombstone state, fetched alongside its
  -- profile_id, so a live observation can be rejected when its parent day
  -- entry is already tombstoned.
  v_day_entry_deleted_at timestamptz;
  v_stored_obs public.observations%rowtype;
  v_other_obs public.observations%rowtype;
  v_obs_incoming_wins boolean;
  v_obs_count integer;
  -- Review finding (item 4): true whenever this push will land the row
  -- live under a (profile_id, local_date) that isn't already guaranteed
  -- to have counted it -- a brand-new row, a tombstone being revived
  -- (deleted_at: null on an already-tombstoned id), or a live row's
  -- local_date moving to a different day. The per-day cap and the
  -- same-date (category, code) dedup below both key off this, not just
  -- "brand new", so a revive or a date-move cannot bypass either.
  v_obs_check_collision boolean;
  -- Issue #188: profile_modes parsing state.
  v_mode_started_on date;
  v_estimated_due_date date;
  v_birth_control_method text;
  v_birth_control_started_on date;
  v_birth_control_stopped_on date;
  v_health_sync_consent boolean;
  v_stored_mode public.profile_modes%rowtype;
  -- Issue #188: cycle_overrides parsing state.
  v_cycle_start_date date;
  v_excluded_from_average boolean;
  v_manual_start boolean;
  v_note_id text;
  v_stored_override public.cycle_overrides%rowtype;
  -- Issue #128: care_notes parsing state.
  v_body text;
  v_stored_note public.care_notes%rowtype;
  -- Issue #128: visit_prep_items parsing state.
  v_is_checked boolean;
  v_checked_by_user_id uuid;
  v_checked_at timestamptz;
  v_stored_prep_item public.visit_prep_items%rowtype;
  -- Issue #130: day_entry_merge_events parsing state.
  v_merge_winning_row_id text;
  v_merge_losing_row_id text;
  v_merge_field text;
  v_merge_losing_value text;
  v_merge_losing_author uuid;
  v_merge_winning_author uuid;
  -- Issue #257: profile_tag_registry parsing state.
  v_registry_code text;
  v_registry_display_name text;
  v_registry_category text;
  v_registry_intensity_enabled boolean;
  v_registry_hidden_at timestamptz;
  v_registry_sort_order integer;
  v_registry_count integer;
  v_stored_registry_row public.profile_tag_registry%rowtype;
  -- Issue #801: guardian_notes parsing state. local_date/tz reuse the
  -- day_entries loop's v_local_date/v_tz (the loops run sequentially);
  -- v_body is likewise shared with the care_notes loop.
  v_stored_guardian_note public.guardian_notes%rowtype;
begin
  if v_uid is null then
    raise exception 'sync_push requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  -- Serialise pushes per-user so server_version commits monotonically per user (Issue #14).
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  if p_profiles is null or jsonb_typeof(p_profiles) <> 'array' then
    raise exception 'p_profiles must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_day_entries is null or jsonb_typeof(p_day_entries) <> 'array' then
    raise exception 'p_day_entries must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_observations is null or jsonb_typeof(p_observations) <> 'array' then
    raise exception 'p_observations must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_profile_modes is null or jsonb_typeof(p_profile_modes) <> 'array' then
    raise exception 'p_profile_modes must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_cycle_overrides is null or jsonb_typeof(p_cycle_overrides) <> 'array' then
    raise exception 'p_cycle_overrides must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_care_notes is null or jsonb_typeof(p_care_notes) <> 'array' then
    raise exception 'p_care_notes must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_visit_prep_items is null or jsonb_typeof(p_visit_prep_items) <> 'array' then
    raise exception 'p_visit_prep_items must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_merge_events is null or jsonb_typeof(p_merge_events) <> 'array' then
    raise exception 'p_merge_events must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_tag_registry is null or jsonb_typeof(p_tag_registry) <> 'array' then
    raise exception 'p_tag_registry must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if p_guardian_notes is null or jsonb_typeof(p_guardian_notes) <> 'array' then
    raise exception 'p_guardian_notes must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_profiles) > c_max_rows then
    raise exception 'p_profiles exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_day_entries) > c_max_rows then
    raise exception 'p_day_entries exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_observations) > c_max_rows then
    raise exception 'p_observations exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_profile_modes) > c_max_rows then
    raise exception 'p_profile_modes exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_cycle_overrides) > c_max_rows then
    raise exception 'p_cycle_overrides exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_care_notes) > c_max_rows then
    raise exception 'p_care_notes exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_visit_prep_items) > c_max_rows then
    raise exception 'p_visit_prep_items exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_merge_events) > c_max_rows then
    raise exception 'p_merge_events exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_tag_registry) > c_max_rows then
    raise exception 'p_tag_registry exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_guardian_notes) > c_max_rows then
    raise exception 'p_guardian_notes exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;

  -- Issue #564: with seven arrays each individually capped at c_max_rows
  -- (500), a single call could still open up to 3500 per-row
  -- subtransactions (one per exception-handling block below), pushing this
  -- session's top-level transaction past Postgres' 64-subxid in-memory
  -- limit and forcing pg_subtrans lookups for every OTHER session on the
  -- instance for the duration. This caps the combined total instead of
  -- restructuring to a set-based write (deliberately out of scope - see
  -- 20260913016000_sync_push_hardening.sql's header).
  if jsonb_array_length(p_profiles) + jsonb_array_length(p_day_entries)
     + jsonb_array_length(p_observations) + jsonb_array_length(p_profile_modes)
     + jsonb_array_length(p_cycle_overrides) + jsonb_array_length(p_care_notes)
     + jsonb_array_length(p_visit_prep_items)
     + jsonb_array_length(p_merge_events)
     + jsonb_array_length(p_tag_registry)
     + jsonb_array_length(p_guardian_notes) > c_max_total_rows then
    raise exception 'sync_push payload exceeds % total rows across all tables', c_max_total_rows
      using errcode = 'invalid_parameter_value';
  end if;

  -- -------------------------------------------------------------------------
  -- profiles
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_profiles) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_profile_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      v_created_at := coalesce((v_row ->> 'created_at')::timestamptz, v_updated_at);
      v_archived_at := (v_row ->> 'archived_at')::timestamptz;
      v_is_minor := coalesce((v_row ->> 'is_minor')::boolean, false);
      v_sort_order := coalesce((v_row ->> 'sort_order')::integer, 0);
      -- U1: birth_year/relationship are ordinary optional profile metadata,
      -- validated by the table's own CHECK constraints (an invalid value
      -- lands this row in `rejected` via the exception handler below, same
      -- as an over-length display_name). These two parsed values feed the
      -- INSERT path unconditionally (a brand-new row has nothing to
      -- preserve) and the UPDATE path guarded by a jsonb `?` containment
      -- check below (review item #3) so an old client that omits these keys
      -- entirely does not silently null out an already-stored value.
      v_birth_year := (v_row ->> 'birth_year')::smallint;
      v_relationship := v_row ->> 'relationship';
      -- #131: mode gets the same treatment except that the column is not
      -- null with a default - an absent key parses to 'standard' (which the
      -- INSERT path needs), and an out-of-set value is rejected by
      -- profiles_mode_check into `rejected` like any other CHECK failure.
      -- The UPDATE path applies the same `?` containment guard so a
      -- pre-#131 client's push never touches a stored mode.
      v_mode := coalesce(v_row ->> 'mode', 'standard');
      -- #218: cycle facts parse like birth_year/relationship -- optional
      -- metadata validated by the table's own CHECK constraints; a bad
      -- value lands the row in `rejected` via the exception handler.
      v_last_period_start := (v_row ->> 'last_period_start')::date;
      v_typical_cycle_length_days := (v_row ->> 'typical_cycle_length_days')::smallint;
      v_typical_period_length_days := (v_row ->> 'typical_period_length_days')::smallint;
      -- #255: display-unit preferences parse like mode -- the columns are
      -- not null with defaults, so an absent key parses to the default;
      -- an out-of-set value is rejected by the column CHECK into
      -- `rejected` like any other CHECK failure. The UPDATE path applies
      -- the same `?` containment guard so a pre-#255 client's push never
      -- touches a stored preference.
      v_bbt_unit := coalesce(v_row ->> 'bbt_unit', 'celsius');
      v_weight_unit := coalesce(v_row ->> 'weight_unit', 'kg');
      -- #259: the document parses as-is (shape validated by
      -- profiles_tracking_preferences_check -- a bad value lands the row
      -- in `rejected` like any other CHECK failure). `nullif` collapses
      -- an explicit JSON `null` to SQL NULL (the observations.raw
      -- lesson: `-> 'key'` on a JSON null yields the jsonb null literal,
      -- not SQL NULL); an absent key already yields SQL NULL. The UPDATE
      -- path below applies the `?` containment guard, so a pre-#259
      -- client that omits the key entirely never clobbers a stored
      -- document -- and a client that simply has not pulled yet sends no
      -- key either (the codec emits it only when locally non-null), so a
      -- co-guardian's curated document survives every unrelated edit.
      v_tracking_preferences := nullif(v_row -> 'tracking_preferences', 'null'::jsonb);
      if v_deleted_at is not null then
        -- tombstones carry no payload
        v_display_name := '';
      else
        v_display_name := coalesce(v_row ->> 'display_name', '');
      end if;

      -- Check if profile already exists
      select * into v_stored_profile
        from public.profiles
       where id = v_id
       for update;

      if not found then
        -- New profile insertion: creator becomes primary_guardian via trigger
        insert into public.profiles
          (id, display_name, is_minor, sort_order, archived_at, created_at, updated_at, deleted_at,
           birth_year, relationship, mode,
           last_period_start, typical_cycle_length_days, typical_period_length_days,
           bbt_unit, weight_unit,
           tracking_preferences)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at,
           v_birth_year, v_relationship, v_mode,
           v_last_period_start, v_typical_cycle_length_days, v_typical_period_length_days,
           v_bbt_unit, v_weight_unit,
           v_tracking_preferences);
      else
        -- Profile exists: check guardian role of caller
        select role into v_caller_role
          from public.profile_guardians
         where profile_id = v_id
           and user_id = v_uid
           and status = 'accepted';

        if v_caller_role is null then
          raise exception 'caller is not an accepted guardian of profile'
            using errcode = 'insufficient_privilege';
        end if;

        -- Only primary_guardian or co_parent can edit profiles
        if v_caller_role not in ('primary_guardian', 'co_parent') then
          raise exception 'role % cannot edit profile metadata', v_caller_role
            using errcode = 'insufficient_privilege';
        end if;

        -- Only primary_guardian can delete/archive profiles
        if (v_deleted_at is not null or v_archived_at is not null) and v_caller_role <> 'primary_guardian' then
          raise exception 'only primary_guardian can delete or archive profile'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored_profile.updated_at
          or (v_updated_at = v_stored_profile.updated_at
              and v_deleted_at is not null
              and v_stored_profile.deleted_at is null);
        if v_accept then
          update public.profiles
             set display_name = v_display_name,
                 -- Issue #518: is_minor gets the same v_row ? 'key'
                 -- containment guard as birth_year/relationship/mode below -
                 -- an old client (or any partial-row writer) that omits the
                 -- key must not silently un-mark a minor's profile.
                 is_minor = case when v_row ? 'is_minor' then v_is_minor else v_stored_profile.is_minor end,
                 sort_order = v_sort_order,
                 archived_at = v_archived_at,
                 created_at = v_created_at,
                 updated_at = v_updated_at,
                 deleted_at = v_deleted_at,
                 -- Review item #3 (P1): an old client that predates U1 omits
                 -- birth_year/relationship from its payload entirely, rather
                 -- than sending them as null - v_row ->> 'key' cannot tell
                 -- "omitted" from "explicitly cleared" apart, and both parse
                 -- to the same null in v_birth_year/v_relationship above. The
                 -- jsonb `?` containment operator can tell them apart: only
                 -- overwrite the stored value when the incoming row actually
                 -- carries the key, so an old client's push preserves
                 -- whatever birth_year/relationship the profile already has
                 -- instead of silently nulling it on every metadata edit.
                 -- #131: mode gets the identical guard, so a pre-#131
                 -- client's push never clobbers a stored mode.
                 birth_year = case when v_row ? 'birth_year' then v_birth_year else v_stored_profile.birth_year end,
                 relationship = case when v_row ? 'relationship' then v_relationship else v_stored_profile.relationship end,
                 mode = case when v_row ? 'mode' then v_mode else v_stored_profile.mode end,
                 -- #218: same containment guard as birth_year/relationship
                 -- above -- a pre-#218 client never sends these keys, and
                 -- its ordinary metadata edits must not null a stored fact.
                 last_period_start = case when v_row ? 'last_period_start' then v_last_period_start else v_stored_profile.last_period_start end,
                 typical_cycle_length_days = case when v_row ? 'typical_cycle_length_days' then v_typical_cycle_length_days else v_stored_profile.typical_cycle_length_days end,
                 typical_period_length_days = case when v_row ? 'typical_period_length_days' then v_typical_period_length_days else v_stored_profile.typical_period_length_days end,
                 -- #255: same containment guard as mode/#218 above -- a
                 -- pre-#255 client never sends these keys, and its ordinary
                 -- metadata edits must not clobber a stored preference.
                 bbt_unit = case when v_row ? 'bbt_unit' then v_bbt_unit else v_stored_profile.bbt_unit end,
                 weight_unit = case when v_row ? 'weight_unit' then v_weight_unit else v_stored_profile.weight_unit end,
                 -- #259: same containment guard as every optional profile
                 -- column above. An explicit JSON null in the payload
                 -- (cleared back to defaults) still lands: nullif turned
                 -- it into SQL NULL, and the key IS present, so the case
                 -- writes null over the stored document. Only a key that
                 -- is absent altogether preserves it.
                 tracking_preferences = case when v_row ? 'tracking_preferences' then v_tracking_preferences else v_stored_profile.tracking_preferences end
           where id = v_id;
        elsif v_updated_at = v_stored_profile.updated_at
              and v_deleted_at is not null
              and v_stored_profile.deleted_at is not null then
          -- identical tombstone already stored: no-op, nothing to converge
          null;
        else
          -- declined (older, or equal-and-live): hand back the server copy
          v_resolved := v_resolved
            || (to_jsonb(v_stored_profile) || jsonb_build_object('table', 'profiles'));
        end if;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- Issue #564: the role lookup every one of the six loops below used to
  -- repeat per row is hoisted to this single pre-computed map (profile_id
  -- -> role), built from ONE query against the union of distinct
  -- profile_ids across all six arrays. Computed HERE - after the profiles
  -- loop above, not before it - deliberately: a sync_push call routinely
  -- creates a brand-new profile and that profile's first day_entries (or
  -- other child-table rows) in the SAME call, and the profiles loop's own
  -- on_profile_created_add_guardian trigger is what inserts the caller's
  -- primary_guardian profile_guardians row for a new profile. Computing
  -- this map before the profiles loop ran would see no such row yet for
  -- any profile created in this very call, and every one of the six loops
  -- below would then reject its rows as "caller is not authorized" even
  -- for the profile's own creator. A malformed row (not an object, or
  -- missing profile_id) contributes NULL to the union harmlessly - `->>`
  -- on a non-object jsonb value returns NULL rather than erroring, and
  -- that row's own validation still runs (and still rejects it) inside its
  -- loop's per-row exception block exactly as before. Note: this still
  -- takes one consistent snapshot for the rest of the call, rather than a
  -- fresh per-row read in each of the six loops - a role change committed
  -- by another session mid-batch no longer affects a later row in the SAME
  -- call (previously it could, under ordinary read-committed per-statement
  -- snapshots); this is an accepted, and arguably more consistent,
  -- trade-off of the hoist.
  select coalesce(jsonb_object_agg(pg.profile_id, pg.role), '{}'::jsonb) into v_role_map
    from public.profile_guardians pg
   where pg.user_id = v_uid
     and pg.status = 'accepted'
     and pg.profile_id = any(
       array(
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_day_entries) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_observations) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_profile_modes) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_cycle_overrides) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_care_notes) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_visit_prep_items) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_merge_events) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_tag_registry) x
         union
         select distinct x.value ->> 'profile_id' from jsonb_array_elements(p_guardian_notes) x
        )
     );

  -- -------------------------------------------------------------------------
  -- day entries
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_day_entries) order by value ->> 'id' loop
    -- per-row state the branches below test for
    v_stored := null;
    v_other := null;
    v_incoming_wins := null;
    v_pending_discard_fields := '{}'::text[];
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_day_entry_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'local_date') is null
         or (v_row ->> 'local_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date is not an ISO calendar date';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      v_tz := coalesce(v_row ->> 'tz', 'UTC');
      -- Issue #159: parsed unconditionally, ahead of the tombstone
      -- if/else below (like tz) -- provenance is not health content and
      -- survives a tombstone by design (see the migration header's
      -- "tombstone payload" decision), so it is never cleared on delete.
      v_source := coalesce(v_row ->> 'source', 'manual');
      v_source_id := v_row ->> 'source_id';
      v_import_id := (v_row ->> 'import_id')::uuid;
      v_flow := coalesce(v_row ->> 'flow', 'none');
      -- Issue #303: validated against the single source-of-truth
      -- public.is_valid_flow_level() -- the same predicate the flow_level
      -- domain's own CHECK calls (see this migration's header) -- instead
      -- of a third hand-kept copy of the allow-list.
      if not public.is_valid_flow_level(v_flow) then
        raise exception 'flow is not a known level';
      end if;
      -- Issue #220: the first-class PMS marker, parsed like any other
      -- day-level content field. An absent key parses to false so the
      -- INSERT path always has a value; the UPDATE path below guards with
      -- v_row ? 'pms' so an old client omitting the key never clears an
      -- already-stored marker.
      v_pms := coalesce((v_row ->> 'pms')::boolean, false);
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224: flow joins tags/note -
        -- it was the one field this branch left the incoming value in,
        -- the most sensitive single column on the row). Issue #220: pms
        -- is health content exactly like flow/tags/note and clears here
        -- too (day_entries_tombstone_pms_check is the structural
        -- backstop).
        v_tags := '[]'::jsonb;
        v_note := null;
        v_flow := 'none';
        v_pms := false;
      else
        v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);
        if jsonb_typeof(v_tags) <> 'array' then
          raise exception 'tags is not an array';
        end if;
        -- Issue #96: restore the is_valid_tags_array RPC-level validation
        -- the 20260904020000 rewrite silently dropped (Issue #40's
        -- contract). The day_entries_tags_check table CHECK backstops the
        -- same predicate, so this is defence in depth, not a behavior
        -- change; the per-row handler turns the 22023 raise into a
        -- rejected entry exactly like the 23514 CHECK violation did.
        if not public.is_valid_tags_array(v_tags) then
          raise exception 'tags is not a valid array of strings'
            using errcode = '22023';
        end if;
        v_note := v_row ->> 'note';
      end if;

      -- Verify caller has write permissions for profile (primary_guardian, co_parent, or caregiver)
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write day entries for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored
        from public.day_entries
       where id = v_id
       for update;

      if found then
        -- An entry never legitimately changes profiles: the role check
        -- above ran against v_profile_id only, so a re-pointed row would
        -- smuggle another profile's entry past that check.
        if v_stored.profile_id is distinct from v_profile_id then
          raise exception 'day entry cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored.updated_at
          or (v_updated_at = v_stored.updated_at
              and v_deleted_at is not null
              and v_stored.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored.updated_at
                  and v_deleted_at is not null
                  and v_stored.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
          end if;
          continue;
        end if;
      else
        -- Coordinator review (PR #705, #263/#189): no stored row exists for
        -- this id. That is ordinarily just "a brand-new entry" -- but
        -- 20260915200000_nightly_retention_job.sql's enforce_retention()
        -- hard-deletes a day_entries tombstone once its deleted_at is more
        -- than 180 days old, so "no stored row" is now ALSO the exact state
        -- left behind by a purged tombstone. A client offline for the
        -- entire 180+ days never learned of that deletion and would
        -- otherwise resurrect it here via the ordinary INSERT path below.
        -- Reject (this row alone, via the per-row exception handler) any
        -- unknown id whose updated_at already predates that same 180-day
        -- window -- it can never be distinguished, server-side, from a
        -- resurrection attempt, so it is treated as one. This 180-day
        -- figure MUST stay equal to enforce_retention()'s own day_entries
        -- tombstone window -- see that function's migration header for the
        -- full sync-safety reasoning (kSyncFullPullInterval). A stored row
        -- that still exists (the `if found` branch above) is completely
        -- unaffected: this guard only ever fires on the "no stored row"
        -- branch, never on an ordinary LWW update of a still-live or
        -- still-tombstoned-but-not-yet-purged row.
        if v_updated_at < now() - interval '180 days' then
          raise exception 'day entry is too old to accept as new (past the tombstone retention window)'
            using errcode = 'invalid_parameter_value';
        end if;
      end if;

      -- Same-date resolver: runs on every write that would leave a live row.
      if v_deleted_at is null then
        select * into v_other
          from public.day_entries
         where profile_id = v_profile_id
           and local_date = v_local_date
           and deleted_at is null
           and id <> v_id
         order by id
         for update;

        if found then
          v_incoming_wins := v_updated_at > v_other.updated_at
            or (v_updated_at = v_other.updated_at
                and (v_id collate "C") < (v_other.id collate "C"));
          if v_incoming_wins then
            -- R7: union the loser's tags onto the incoming (surviving) row
            -- before tombstoning it - the loser's tags would otherwise be
            -- destroyed outright. flow/note stay last-writer-wins (KTD4)
            -- for the surviving row; the *loser* being tombstoned here
            -- clears its own flow to 'none' alongside note/tags (issue
            -- #224 - this direct UPDATE previously left the loser's old
            -- flow value in place forever).
            v_tags := public.merge_tag_arrays(v_tags, v_other.tags);
            -- Issue #130: disclosure, not resolution. flow/note stay
            -- last-writer-wins (KTD4, unchanged) -- but the loser's actual
            -- value is now recorded in day_entry_merge_events in the SAME
            -- transaction as the merge, so both guardians' devices can show
            -- a quiet notice and the losing author can recover their text.
            -- Recorded while v_other still holds its PRE-tombstone payload
            -- (the UPDATE further down overwrites it via RETURNING).
            -- Emission itself must never abort the merge: the helper
            -- truncates the retained text to the CHECK bound and resolves
            -- natural-key duplicates with ON CONFLICT DO NOTHING. A
            -- tags-only merge (note and flow equal) emits nothing.
            if v_other.note is distinct from v_note then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_id, v_other.id, 'note',
                v_other.note,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id),
                v_uid);
              -- Issue #170: the same discard's content-free feed row --
              -- losing row id + field NAME only (day_entry_merge_events
              -- above carries the recoverable text; see this migration's
              -- header item 5 for the two tables' interplay).
              perform public.record_day_entry_merge_history(
                v_profile_id, v_other.id, 'note', v_uid);
            end if;
            if v_other.flow is distinct from v_flow then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_id, v_other.id, 'flow',
                v_other.flow,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id),
                v_uid);
              -- Issue #170: the same discard's content-free feed row.
              perform public.record_day_entry_merge_history(
                v_profile_id, v_other.id, 'flow', v_uid);
            end if;
            -- Issue #639 LLA-036 (incoming-wins direction): reparent the
            -- losing entry's live observations onto the surviving (winning)
            -- day entry BEFORE the cascade below tombstones the loser --
            -- otherwise the losing day's structured severity/measurements
            -- are cascade-wiped and lost even though the loser's tags
            -- survive the union above.
            --
            -- The reparent's FK needs the winner row to exist, but the
            -- winner cannot be inserted live while the loser is still live
            -- (day_entries_live_profile_date_uq). Insert it as a TOMBSTONE
            -- instead: that satisfies the FK, is invisible to the live
            -- unique index, and the end-of-loop store below flips it back
            -- to live once the loser is tombstoned. When the incoming
            -- winner already exists (v_stored.id not null) it is already
            -- present, so no insert runs. Every live loser observation
            -- moves, without exception: any (category, code) it shares
            -- with the winner's own observations is resolved by the
            -- observations loop's own same-date dedup later in this same
            -- call (which runs after the day_entries loop, so the winner's
            -- pending observations are invisible to a `not exists` guard
            -- here anyway), backed by the
            -- observations_live_profile_date_category_code_uq partial
            -- unique index. Reparenting cannot itself violate that index:
            -- it only rewrites day_entry_id, which is not part of it.
            -- last_modified_by_user_id is stamped to the caller because
            -- enforce_observation_attribution requires it on every update
            -- while auth.uid() is set.
            if v_stored.id is null then
              insert into public.day_entries
                (id, profile_id, local_date, tz, flow, tags, note, pms,
                 source, source_id, import_id,
                 updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
              values
                (v_id, v_profile_id, v_local_date, v_tz, 'none', '[]'::jsonb, null, false,
                 v_source, v_source_id, v_import_id,
                 v_updated_at, v_updated_at, v_uid, v_uid)
              returning * into v_stored;
            end if;
            update public.observations o
               set day_entry_id = v_id,
                   last_modified_by_user_id = v_uid
              where o.day_entry_id = v_other.id
                and o.deleted_at is null;

            update public.day_entries
               set deleted_at = v_updated_at,
                   updated_at = v_updated_at,
                   flow = 'none',
                   note = null,
                   tags = '[]'::jsonb,
                   -- Issue #220: the losing row's tombstone carries no
                   -- payload, the marker included.
                   pms = false,
                   last_modified_by_user_id = v_uid
             where id = v_other.id
             returning * into v_other;
            v_resolved := v_resolved
              || (to_jsonb(v_other) || jsonb_build_object('table', 'day_entries'));
          else
            -- Issue #130: disclosure for the losing direction, recorded
            -- BEFORE the UPDATE below (which re-stamps v_other's
            -- last_modified_by_user_id to the caller and overwrites the
            -- row variable via RETURNING). The incoming row's author is the
            -- caller: the server stamps logged_by/last_modified from v_uid
            -- on the store below, so the discard's losing author is v_uid
            -- and the winner's author is v_other's pre-update attribution.
            if v_note is distinct from v_other.note then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_other.id, v_id, 'note',
                v_note,
                v_uid,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id));
              -- Issue #170: the same discard's content-free feed row --
              -- DEFERRED: the incoming row (v_id) is the loser and does
              -- not exist in day_entries yet, and the history row's
              -- entry_id FK requires it to; collected here, emitted after
              -- this iteration's store below.
              v_pending_discard_fields := v_pending_discard_fields || array['note'];
            end if;
            if v_flow is distinct from v_other.flow then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_other.id, v_id, 'flow',
                v_flow,
                v_uid,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id));
              -- Issue #170: the same discard's content-free feed row --
              -- deferred like the note discard above (FK ordering).
              v_pending_discard_fields := v_pending_discard_fields || array['flow'];
            end if;
            -- The incoming row loses: it is stored as a tombstone at the
            -- winner's time (unchanged). R7/R11: the union of both rows'
            -- tags is written onto the surviving v_other row in the same
            -- statement that already touches it, leaving v_other.updated_at
            -- alone so the merge does not disturb the winner's timestamp.
            -- last_modified_by_user_id must still be stamped to the caller
            -- here (enforce_day_entry_attribution requires it on every
            -- update while auth.uid() is set) even though this row's
            -- content otherwise belongs to whoever logged it.
            update public.day_entries
               set tags = public.merge_tag_arrays(v_other.tags, v_tags),
                   last_modified_by_user_id = v_uid
             where id = v_other.id
             returning * into v_other;
            v_deleted_at := v_other.updated_at;
            v_updated_at := v_other.updated_at;
            v_tags := '[]'::jsonb;
            v_note := null;
            -- issue #224: the incoming row is the one becoming a tombstone
            -- here (stored via the insert/update below) - it must carry no
            -- payload either, same as every other tombstone.
            v_flow := 'none';
            -- Issue #220: same clearing on the losing incoming row.
            v_pms := false;
            -- Issue #639 LLA-036 (incoming-loses direction): the incoming
            -- row is about to be stored as a tombstone below. If it was an
            -- already-stored live row, its observations must be reparented
            -- onto the surviving v_other BEFORE that tombstone's cascade
            -- wipes them (all of them -- collisions are resolved by the
            -- observations loop's own same-date dedup, as in the wins
            -- direction). Brand-new incoming rows have no stored
            -- observations yet (v_stored.id is null), so the guard is
            -- cheap.
            if v_stored.id is not null then
              update public.observations o
                 set day_entry_id = v_other.id,
                     last_modified_by_user_id = v_uid
                where o.day_entry_id = v_id
                  and o.deleted_at is null;
            end if;
          end if;
        end if;
      end if;

      if v_stored.id is null then
        insert into public.day_entries
          (id, profile_id, local_date, tz, flow, tags, note, pms,
           source, source_id, import_id,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note, v_pms,
           v_source, v_source_id, v_import_id,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored;
      else
        -- Issue #562: profile_id is no longer in this SET clause (and no
        -- longer needs to be - the immutability check above already
        -- proved it equals the stored value, so re-assigning it here was
        -- always a no-op). authenticated no longer holds an UPDATE grant
        -- on this column at all (20260913017000_day_entries_column_grants.sql).
        -- Issue #201: sync_push is now SECURITY DEFINER, so this omission
        -- is no longer load-bearing the way it was under SECURITY INVOKER
        -- (a DEFINER function runs as its owner, which bypasses column
        -- grants entirely) - it stays omitted anyway since re-adding a
        -- provably-no-op assignment would serve no purpose.
        update public.day_entries
           set local_date = v_local_date,
               tz = v_tz,
               flow = v_flow,
               tags = v_tags,
               note = v_note,
               -- Issue #220: the PMS marker gets the same v_row ? 'key'
               -- containment guard as source/source_id/import_id below --
               -- an old client (pre-#220) omits the key entirely, and
               -- must never silently clear an already-stored marker.
               -- A tombstone always clears it first, though: the guard
               -- protects the marker from an old client's *live* edit,
               -- never from a delete (day_entries_tombstone_pms_check
               -- would otherwise reject the whole row into `rejected`).
               pms = case
                      when v_deleted_at is not null then false
                      when v_row ? 'pms' then v_pms
                      else v_stored.pms
                    end,
               -- Issue #159 (acceptance criteria): an old client that omits
               -- source/source_id/import_id entirely must not silently null
               -- an already-stored value on a later edit -- the same
               -- v_row ? 'key' containment guard U1 established for
               -- profiles.birth_year/relationship (20260906160000, PR #108
               -- review item #3) and #131 established for profiles.mode.
               source = case when v_row ? 'source' then v_source else v_stored.source end,
               source_id = case when v_row ? 'source_id' then v_source_id else v_stored.source_id end,
               import_id = case when v_row ? 'import_id' then v_import_id else v_stored.import_id end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
         returning * into v_stored;
      end if;

      -- Issue #170: emit the deferred merged_discard rows now that the
      -- losing INCOMING row has been stored (the incoming-wins branch
      -- above emits directly, since its loser -- v_other -- was already a
      -- stored row). Still inside this same per-row exception block, so a
      -- failing emission lands the whole push in `rejected` atomically.
      if cardinality(v_pending_discard_fields) > 0 then
        perform public.record_day_entry_merge_history(
          v_profile_id, v_id, f, v_uid)
          from unnest(v_pending_discard_fields) f;
      end if;

      if v_incoming_wins is false then
        -- the incoming row was tombstoned by resolution: return its server copy
        v_resolved := v_resolved
          || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- observations (Issue #240)
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_observations) order by value ->> 'id' loop
    v_stored_obs := null;
    v_other_obs := null;
    v_obs_incoming_wins := null;
    v_obs_check_collision := false;
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_observation_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_day_entry_id := v_row ->> 'day_entry_id';
      if v_day_entry_id is null or v_day_entry_id !~ c_ulid then
        raise exception 'day_entry_id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'local_date') is null
         or (v_row ->> 'local_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date is not an ISO calendar date';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      v_tz := coalesce(v_row ->> 'tz', 'UTC');
      -- Issue #180 review fix: derive v_local_date from observed_at/tz
      -- right here, ahead of every check below (the stored-row lookup,
      -- the same-date (category, code) collision dedup, and the per-day
      -- cap), so the value this RPC checks against and the value
      -- observations_derive_local_date's BEFORE trigger will
      -- independently recompute on the same row are identical -- the
      -- trigger becomes a pure backstop, never the sole source of truth
      -- for a value this RPC already used to make an accept/reject
      -- decision. Without this fix, a push whose observed_at derived to
      -- a different local day than the client-supplied local_date key
      -- evaded both the per-day cap and the same-date dedup below (they
      -- ran against the stale client-supplied local_date, not the day
      -- the row actually lands on once the trigger fires), and an
      -- UPDATE that changed only observed_at moved a row across days
      -- without ever tripping v_obs_check_collision, since
      -- v_stored_obs.local_date was being compared against that same
      -- stale value. Parsed unconditionally here, ahead of the tombstone
      -- if/else below, since every downstream check needs the corrected
      -- value regardless of tombstone status; the tombstone branch below
      -- still nulls v_observed_at itself (tombstones carry no payload --
      -- issue #224 precedent), it just no longer gets a second say over
      -- v_local_date, which is already derived here.
      v_observed_at := (v_row ->> 'observed_at')::timestamptz;
      if v_observed_at is not null then
        v_local_date := (v_observed_at at time zone v_tz)::date;
      end if;
      -- Issue #159: parsed unconditionally, ahead of the tombstone
      -- if/else below -- import_id is provenance, not health content, and
      -- survives a tombstone by design (see this migration's header).
      v_import_id := (v_row ->> 'import_id')::uuid;
      -- Issue #186: same unconditional provenance parse -- the export
      -- marker survives a tombstone (a deleted row must stay recognisable
      -- as already-written to a health store, so a future re-import dedupe
      -- never re-writes it).
      v_exported_to_platform_at := (v_row ->> 'exported_to_platform_at')::timestamptz;
      -- category's required-unless-tombstoned check moves below, once
      -- v_deleted_at is known (review finding: a tombstone push must not
      -- be forced to carry a category just to satisfy this validation --
      -- see observations_category_required_unless_tombstoned_check).
      v_category := v_row ->> 'category';
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      -- The day entry this observation is attached to must exist and must
      -- belong to the same profile the caller is pushing under - a
      -- mismatched pair would smuggle an observation onto another
      -- profile's day entry past the role check below (mirrors the
      -- day_entries "cannot move between profiles" guard's intent, applied
      -- up front here since day_entry_id/profile_id are a pair on this
      -- table rather than a single reassignable column).
      select profile_id, deleted_at into v_day_entry_profile_id, v_day_entry_deleted_at
        from public.day_entries
       where id = v_day_entry_id;
      if v_day_entry_profile_id is null then
        raise exception 'day_entry_id does not exist';
      end if;
      if v_day_entry_profile_id is distinct from v_profile_id then
        raise exception 'day_entry_id does not belong to profile_id'
          using errcode = 'insufficient_privilege';
      end if;
      -- Issue #524: a live observation may never point at a tombstoned day
      -- entry - closes the second half of the cascade LWW-rewind fix
      -- (20260913012000_cascade_tombstone_lww_guard.sql's greatest() guard
      -- closes the first half, the cascade itself rewinding a child's
      -- clock backward). Without this, a push that races the cascade -
      -- carrying a live payload for an observation whose day_entry another
      -- guardian just tombstoned - would otherwise be accepted purely on
      -- LWW timing and resurrect a live row under a deleted day.
      if v_day_entry_deleted_at is not null and v_deleted_at is null then
        raise exception 'day_entry_id is tombstoned; observation cannot be live'
          using errcode = 'invalid_parameter_value';
      end if;

      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224 precedent) except
        -- local_date/tz/day_entry_id/profile_id -- category is cleared
        -- too (review finding; see this migration's header "Judgement
        -- calls" and observations_tombstone_payload_check).
        v_category := null;
        v_code := null;
        v_value_num := null;
        v_value_text := null;
        v_unit := null;
        v_intensity := null;
        v_excluded := false;
        v_source := coalesce(v_row ->> 'source', 'manual');
        -- Issue #159 (review decision, this migration's header): unlike
        -- every other value column, source_id now SURVIVES a tombstone --
        -- a deleted row must stay recognisable to a future re-import so it
        -- can be skipped rather than resurrected as a duplicate. Reverses
        -- #240's original "v_source_id := null" here.
        v_source_id := v_row ->> 'source_id';
        v_raw := null;
        v_observed_at := null;
      else
        if v_category is null or char_length(v_category) < 1 then
          raise exception 'category is required';
        end if;
        v_code := v_row ->> 'code';
        v_value_num := (v_row ->> 'value_num')::numeric;
        v_value_text := v_row ->> 'value_text';
        v_unit := v_row ->> 'unit';
        v_intensity := (v_row ->> 'intensity')::smallint;
        v_excluded := coalesce((v_row ->> 'excluded')::boolean, false);
        v_source := coalesce(v_row ->> 'source', 'manual');
        v_source_id := v_row ->> 'source_id';
        -- Review finding: `->` on a `"raw": null` key yields the *jsonb*
        -- literal `null` (`jsonb_typeof = 'null'`), not a SQL NULL -- left
        -- as-is this would store a real (non-NULL) jsonb `null` value,
        -- which is distinct from the column actually being NULL (and would
        -- fail `observations_tombstone_payload_check`'s `raw is null` arm
        -- on a tombstone push that explicitly sent `"raw": null`). `nullif`
        -- collapses the jsonb `null` literal to a genuine SQL NULL; a
        -- missing `raw` key already parses to SQL NULL via `->`'s own
        -- semantics, so this is a no-op for that case.
        v_raw := nullif(v_row -> 'raw', 'null'::jsonb);
        -- v_observed_at already parsed above, ahead of this if/else (see
        -- the Issue #180 review-fix comment by the v_tz assignment).
      end if;

      -- Verify caller has write permissions for the profile (primary_guardian,
      -- co_parent, or caregiver) - identical role ladder to day_entries.
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write observations for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_obs
        from public.observations
       where id = v_id
       for update;

      if found then
        -- Immutable once created (mirrors day_entries' profile-move guard).
        if v_stored_obs.day_entry_id is distinct from v_day_entry_id
           or v_stored_obs.profile_id is distinct from v_profile_id then
          raise exception 'observation cannot move between day entries or profiles'
            using errcode = 'insufficient_privilege';
        end if;

        v_accept := v_updated_at > v_stored_obs.updated_at
          or (v_updated_at = v_stored_obs.updated_at
              and v_deleted_at is not null
              and v_stored_obs.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_obs.updated_at
                  and v_deleted_at is not null
                  and v_stored_obs.deleted_at is not null) then
            v_resolved := v_resolved
              || (to_jsonb(v_stored_obs) || jsonb_build_object('table', 'observations'));
          end if;
          continue;
        end if;

        -- Review finding (item 4): a revive (tombstone -> live) or a
        -- local_date move on an already-live row must run through the
        -- same per-day cap / same-date dedup as a brand-new row -
        -- otherwise either is a way to land a 201st observation on a day,
        -- or a second live (category, code) sibling, without ever going
        -- through the "brand new" branch below.
        -- Issue #180 review fix: v_local_date is now the *derived*
        -- value (from observed_at/tz, above), so an UPDATE that changes
        -- only observed_at -- moving the row to a different local day
        -- while leaving the client-supplied local_date key untouched --
        -- is correctly detected here too: v_stored_obs.local_date
        -- (the day the row currently lives on) is distinct from the
        -- freshly-derived v_local_date (the day it is moving to), so
        -- this still evaluates true and the move goes through the same
        -- cap/dedup gate as any other collision.
        v_obs_check_collision := v_deleted_at is null
          and (
            v_stored_obs.deleted_at is not null
            or v_stored_obs.local_date is distinct from v_local_date
          );
      else
        -- Brand-new row (never stored under this id before): always
        -- subject to the same-date collision dedup / per-day cap below.
        v_obs_check_collision := v_deleted_at is null;
      end if;

      if v_obs_check_collision then
        if v_code is not null then
          select * into v_other_obs
            from public.observations
           where profile_id = v_profile_id
             and local_date = v_local_date
             and category = v_category
             and code = v_code
             -- Issue #255 (A1-42 source discipline): the collision dedup
             -- is source-scoped. A wearable-sourced temperature or weight
             -- value and a manually-entered BBT/weight value on the same
             -- date are different facts and must coexist, so neither ever
             -- overwrites or tombstones the other. The anti-duplicate-race
             -- property the dedup was built for is untouched: the "same
             -- tap on two phones" case is always manual-vs-manual (or
             -- same-source), and those rows still collapse exactly as
             -- before.
             and source = v_source
             and deleted_at is null
             and id <> v_id
           order by id
           for update;

          if found then
            v_obs_incoming_wins := v_updated_at > v_other_obs.updated_at
              or (v_updated_at = v_other_obs.updated_at
                  and (v_id collate "C") < (v_other_obs.id collate "C"));
            if v_obs_incoming_wins then
              -- The incoming row survives in the other's place; the
              -- previously-live sibling becomes a payload-free tombstone.
              -- Issue #159: source_id (and import_id, never touched by
              -- this statement) survive this tombstoning -- only
              -- category/code/value/etc are cleared, matching the
              -- tombstone-parse branch's decision above.
              update public.observations
                 set deleted_at = v_updated_at,
                     updated_at = v_updated_at,
                     category = null,
                     code = null,
                     value_num = null,
                     value_text = null,
                     unit = null,
                     intensity = null,
                     excluded = false,
                     raw = null,
                     observed_at = null,
                     last_modified_by_user_id = v_uid
               where id = v_other_obs.id
               returning * into v_other_obs;
              v_resolved := v_resolved
                || (to_jsonb(v_other_obs) || jsonb_build_object('table', 'observations'));
            else
              -- The incoming row loses: it is stored as a payload-free
              -- tombstone at the winner's (already-live) timestamp,
              -- exactly like day_entries' "incoming loses" branch.
              v_deleted_at := v_other_obs.updated_at;
              v_updated_at := v_other_obs.updated_at;
              v_category := null;
              v_code := null;
              v_value_num := null;
              v_value_text := null;
              v_unit := null;
              v_intensity := null;
              v_excluded := false;
              -- Issue #159: v_source_id (and v_import_id, never cleared
              -- here) are left as originally parsed -- the incoming row
              -- keeps its own provenance even as it becomes a tombstone.
              v_raw := null;
              v_observed_at := null;
            end if;
          end if;
        end if;

        -- Per-day cap (issue #240 acceptance criteria: enforced in the RPC,
        -- not a CHECK, since a CHECK cannot count sibling rows). Only
        -- counted when this row will actually land as a new *live* row --
        -- a tombstone, or a row that just lost the collision dedup above
        -- and became a tombstone itself, adds nothing to the day's live
        -- count. Runs for a brand-new row, a revive (v_obs_check_collision
        -- above), and a local_date move (same) -- not just inserts --
        -- since the stored copy is either not-yet-live (revive: still a
        -- tombstone in the database) or live at a *different* local_date
        -- (a move) at this point, so this SELECT never double-counts the
        -- row against itself without needing an explicit `id <>` filter.
        -- Counting inside the same transaction as every other row already
        -- inserted earlier in this same loop iteration/batch (all visible
        -- to this SELECT, since nothing has committed yet) bounds a single
        -- oversized batch too, not just the already-stored total.
        if v_deleted_at is null and v_obs_incoming_wins is not false then
          select count(*) into v_obs_count
            from public.observations
           where profile_id = v_profile_id
             and local_date = v_local_date
             and deleted_at is null;
          if v_obs_count >= c_max_observations_per_day then
            raise exception 'profile % already has % observations for %, at the % cap',
              v_profile_id, v_obs_count, v_local_date, c_max_observations_per_day
              using errcode = 'invalid_parameter_value';
          end if;
        end if;
      end if;

      if v_stored_obs.id is null then
        insert into public.observations
          (id, day_entry_id, profile_id, local_date, observed_at, tz, category, code,
           value_num, value_text, unit, intensity, excluded, source, source_id, import_id,
           exported_to_platform_at, raw,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_day_entry_id, v_profile_id, v_local_date, v_observed_at, v_tz, v_category, v_code,
           v_value_num, v_value_text, v_unit, v_intensity, v_excluded, v_source, v_source_id, v_import_id,
           v_exported_to_platform_at, v_raw,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_obs;
      else
        update public.observations
           set local_date = v_local_date,
               observed_at = v_observed_at,
               tz = v_tz,
               category = v_category,
               code = v_code,
               value_num = v_value_num,
               value_text = v_value_text,
               unit = v_unit,
               intensity = v_intensity,
               excluded = v_excluded,
               -- Issue #159 review finding: the original header rationale
               -- ("source always has a value via the coalesce, so there is
               -- no null-vs-omitted ambiguity") was wrong -- the coalesce
               -- resolves an *omitted* key to 'manual' just as surely as an
               -- explicit null would, so an old client, or a tombstone push
               -- that omits `source` entirely, silently reset an
               -- already-stored non-manual source back to 'manual' on
               -- update. `source` now gets the same v_row ? 'key'
               -- containment guard as day_entries.source
               -- (:~657 in this file) and observations.source_id/import_id
               -- below.
               source = case when v_row ? 'source' then v_source else v_stored_obs.source end,
               -- source_id and import_id get the identical containment
               -- guard (an old client, or a tombstone push that omits the
               -- key, must not null an already-stored value) -- required
               -- for "provenance survives a tombstone" to actually hold
               -- when a tombstone push carries only identity fields, not
               -- the full payload. This closes the one piece of #240's
               -- original source_id handling that was a pre-existing gap
               -- (no containment guard at all).
               source_id = case when v_row ? 'source_id' then v_source_id else v_stored_obs.source_id end,
               import_id = case when v_row ? 'import_id' then v_import_id else v_stored_obs.import_id end,
               -- Issue #186: the export marker gets the identical `v_row ?
               -- 'exported_to_platform_at'` containment guard (an old
               -- client, or a tombstone push that omits the key, must not
               -- null an already-stored value -- the provenance-survives-a-
               -- tombstone rule applied to the round-trip marker).
               exported_to_platform_at = case when v_row ? 'exported_to_platform_at'
                 then v_exported_to_platform_at else v_stored_obs.exported_to_platform_at end,
               raw = v_raw,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
         returning * into v_stored_obs;
      end if;

      if v_obs_incoming_wins is false then
        v_resolved := v_resolved
          || (to_jsonb(v_stored_obs) || jsonb_build_object('table', 'observations'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;


  -- -------------------------------------------------------------------------
  -- profile_modes (Issue #188): one row per profile, no tombstone -- a
  -- newer write replaces the older under strict LWW; an equal-timestamp
  -- push is declined with the server copy handed back (a retry of an
  -- already-applied write converges instead of duplicating).
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_profile_modes) order by value ->> 'profile_id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_profile_mode_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      -- Issue #188: the life-stage mode; an absent key parses to the
      -- column default 'tracking' (which the INSERT path needs), and an
      -- out-of-set value is rejected by profile_modes_mode_check into
      -- `rejected` like any other CHECK failure. The UPDATE path applies
      -- the `?` containment guard so a pre-#188-aware client's push never
      -- clobbers a stored mode (the #131 profiles.mode pattern).
      v_mode := coalesce(v_row ->> 'mode', 'tracking');
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      -- Optional dates/method/consent: parsed with the column defaults an
      -- INSERT needs; the UPDATE path below only overwrites a stored
      -- value when the incoming row actually carries the key, so an older
      -- client that omits birth_control_* or health_sync_consent never
      -- silently nulls/reset them (the U1/#108 containment pattern).
      if (v_row ->> 'mode_started_on') is not null
         and (v_row ->> 'mode_started_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'mode_started_on is not an ISO calendar date';
      end if;
      v_mode_started_on := (v_row ->> 'mode_started_on')::date;
      -- Issue #192: the Pregnancy-mode estimated due date, same
      -- shape/guard as its siblings.
      if (v_row ->> 'estimated_due_date') is not null
         and (v_row ->> 'estimated_due_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'estimated_due_date is not an ISO calendar date';
      end if;
      v_estimated_due_date := (v_row ->> 'estimated_due_date')::date;
      v_birth_control_method := v_row ->> 'birth_control_method';
      if (v_row ->> 'birth_control_started_on') is not null
         and (v_row ->> 'birth_control_started_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'birth_control_started_on is not an ISO calendar date';
      end if;
      v_birth_control_started_on := (v_row ->> 'birth_control_started_on')::date;
      if (v_row ->> 'birth_control_stopped_on') is not null
         and (v_row ->> 'birth_control_stopped_on') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'birth_control_stopped_on is not an ISO calendar date';
      end if;
      v_birth_control_stopped_on := (v_row ->> 'birth_control_stopped_on')::date;
      v_health_sync_consent := coalesce((v_row ->> 'health_sync_consent')::boolean, false);

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection -- and enumeration-parity with the day_entries path:
      -- a nonexistent profile and a foreign profile both reject).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #188's write ladder: accepted guardian required, and only
      -- primary_guardian or co_parent may edit profile metadata (mode,
      -- birth-control state) -- the same ladder as a profile edit, and
      -- deliberately stricter than day_entries/observations.
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role not in ('primary_guardian', 'co_parent') then
        raise exception 'caller is not authorized to write profile mode for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_mode
        from public.profile_modes
       where profile_id = v_profile_id
       for update;

      if not found then
        insert into public.profile_modes
          (profile_id, mode, mode_started_on, estimated_due_date,
           birth_control_method,
           birth_control_started_on, birth_control_stopped_on,
           health_sync_consent, updated_at)
        values
          (v_profile_id, v_mode, v_mode_started_on, v_estimated_due_date,
           v_birth_control_method,
           v_birth_control_started_on, v_birth_control_stopped_on,
           v_health_sync_consent, v_updated_at);
      elsif v_updated_at > v_stored_mode.updated_at then
        update public.profile_modes
           set mode = case when v_row ? 'mode' then v_mode else v_stored_mode.mode end,
               mode_started_on = case when v_row ? 'mode_started_on' then v_mode_started_on else v_stored_mode.mode_started_on end,
               estimated_due_date = case when v_row ? 'estimated_due_date' then v_estimated_due_date else v_stored_mode.estimated_due_date end,
               birth_control_method = case when v_row ? 'birth_control_method' then v_birth_control_method else v_stored_mode.birth_control_method end,
               birth_control_started_on = case when v_row ? 'birth_control_started_on' then v_birth_control_started_on else v_stored_mode.birth_control_started_on end,
               birth_control_stopped_on = case when v_row ? 'birth_control_stopped_on' then v_birth_control_stopped_on else v_stored_mode.birth_control_stopped_on end,
               health_sync_consent = case when v_row ? 'health_sync_consent' then v_health_sync_consent else v_stored_mode.health_sync_consent end,
               updated_at = v_updated_at
         where profile_id = v_profile_id;
      else
        -- declined (older or equal): hand back the server copy so the
        -- caller converges; an equal-timestamp retry is a no-op, which is
        -- what makes a mode switch idempotent from a client's point of
        -- view (the row is never duplicated or half-updated).
        v_resolved := v_resolved
          || (to_jsonb(v_stored_mode) || jsonb_build_object('table', 'profile_modes'));
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'profile_id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- cycle_overrides (Issue #188): per-id LWW with tombstones, mirroring
  -- the day_entries accept/decline shape minus the same-date resolver
  -- (see the migration header's judgement calls). Keyed by the full
  -- composite (id, profile_id), so a row can never move between profiles.
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_cycle_overrides) order by value ->> 'profile_id', value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_cycle_override_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'cycle_start_date') is null
         or (v_row ->> 'cycle_start_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'cycle_start_date is not an ISO calendar date';
      end if;
      v_cycle_start_date := (v_row ->> 'cycle_start_date')::date;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (issue #224 precedent): the flags
        -- reset and note_id clears UNCONDITIONALLY here -- no containment
        -- guard on this branch, because a tombstone push carrying only
        -- identity fields must still reach the cleared state
        -- cycle_overrides_tombstone_payload_check demands.
        v_excluded_from_average := false;
        v_manual_start := false;
        v_note_id := null;
      else
        v_excluded_from_average := coalesce((v_row ->> 'excluded_from_average')::boolean, false);
        v_manual_start := coalesce((v_row ->> 'manual_start')::boolean, false);
        v_note_id := v_row ->> 'note_id';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection; same enumeration-parity as profile_modes above).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #188's write ladder: identical to profile_modes (profile
      -- metadata -- a manual cycle correction reshapes the averages).
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role not in ('primary_guardian', 'co_parent') then
        raise exception 'caller is not authorized to write cycle overrides for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_override
        from public.cycle_overrides
       where id = v_id
         and profile_id = v_profile_id
       for update;

      if found then
        v_accept := v_updated_at > v_stored_override.updated_at
          or (v_updated_at = v_stored_override.updated_at
              and v_deleted_at is not null
              and v_stored_override.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_override.updated_at
                  and v_deleted_at is not null
                  and v_stored_override.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_override) || jsonb_build_object('table', 'cycle_overrides'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_override.id is null then
        insert into public.cycle_overrides
          (id, profile_id, cycle_start_date, excluded_from_average,
           manual_start, note_id, updated_at, deleted_at)
        values
          (v_id, v_profile_id, v_cycle_start_date, v_excluded_from_average,
           v_manual_start, v_note_id, v_updated_at, v_deleted_at);
      else
        update public.cycle_overrides
           set cycle_start_date = v_cycle_start_date,
               -- Containment guards on the optional payload columns for a
               -- LIVE write (the U1/#131/#159 pattern): a client that omits
               -- a key never silently resets an already-stored value. A
               -- TOMBSTONE write must bypass the guards and clear
               -- unconditionally -- a tombstone push carries only identity
               -- fields, so guarding it would preserve the stored payload
               -- onto a row the structural CHECK requires payload-free
               -- (rejected wholesale, and the tombstone never landed).
               -- The tombstone parse branch above already set the cleared
               -- values, so the `v_deleted_at is not null` arms simply
               -- write them through.
               excluded_from_average = case
                 when v_deleted_at is not null then false
                 when v_row ? 'excluded_from_average' then v_excluded_from_average
                 else v_stored_override.excluded_from_average end,
               manual_start = case
                 when v_deleted_at is not null then false
                 when v_row ? 'manual_start' then v_manual_start
                 else v_stored_override.manual_start end,
               note_id = case
                 when v_deleted_at is not null then null
                 when v_row ? 'note_id' then v_note_id
                 else v_stored_override.note_id end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at
         where id = v_id
           and profile_id = v_profile_id;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- care_notes (Issue #128): per-id LWW with tombstones, mirroring the
  -- cycle_overrides accept/decline shape (see this migration's header for
  -- the stated resolution rule). Keyed by id alone (the table's primary
  -- key); like day_entries, a row can never move between profiles.
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_care_notes) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_care_note_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      v_body := v_row ->> 'body';
      if v_body is null then
        raise exception 'body is required';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (issue #224 precedent): body clears
        -- UNCONDITIONALLY here, so a tombstone push carrying a stale
        -- non-empty body still lands payload-free, as
        -- care_notes_tombstone_payload_check demands. Over-length bodies
        -- are rejected by that CHECK into `rejected`, never truncated.
        v_body := '';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection -- and enumeration-parity with the day_entries path:
      -- a nonexistent profile and a foreign profile both reject).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #128's write ladder: the day_entries ladder (any accepted
      -- guardian except a viewer may log), NOT the stricter #188
      -- profile-metadata ladder -- a care note is logging, like a day
      -- entry.
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write care notes for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_note
        from public.care_notes
       where id = v_id
       for update;

      if found then
        -- A note never legitimately changes profiles: the role check above
        -- ran against v_profile_id only, so a re-pointed row would smuggle
        -- another profile's note past that check (the day_entries
        -- cannot-move-between-profiles pattern).
        if v_stored_note.profile_id is distinct from v_profile_id then
          raise exception 'care note cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_note.updated_at
          or (v_updated_at = v_stored_note.updated_at
              and v_deleted_at is not null
              and v_stored_note.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_note.updated_at
                  and v_deleted_at is not null
                  and v_stored_note.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_note) || jsonb_build_object('table', 'care_notes'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_note.id is null then
        insert into public.care_notes
          (id, profile_id, body, updated_at, deleted_at,
           logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_body, v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_note;
      else
        update public.care_notes
           set body = v_body,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
        returning * into v_stored_note;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- visit_prep_items (Issue #128): per-id LWW with tombstones, mirroring
  -- the care_notes loop above (same resolution rule: the checklist
  -- converges as a set; a check-off races only against another write to
  -- the same item id). checked_by_user_id/checked_at are derived from the
  -- caller here -- never accepted per-row (absent from
  -- c_visit_prep_item_keys, so a row carrying them is rejected as
  -- unknown-key rather than silently accepted).
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_visit_prep_items) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_visit_prep_item_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      v_body := v_row ->> 'body';
      if v_body is null then
        raise exception 'body is required';
      end if;
      v_is_checked := coalesce((v_row ->> 'is_checked')::boolean, false);
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (not the whole batch - this row alone, via the
      -- per-row exception handler below) an updated_at more than five
      -- minutes ahead of the server's own clock. A client whose clock is
      -- badly fast would otherwise win every future LWW race against every
      -- other guardian indefinitely.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload and no check state (the
        -- visit_prep_items_tombstone_payload_check mirror): body clears
        -- and the item lands unchecked with no stamp, UNCONDITIONALLY.
        v_body := '';
        v_is_checked := false;
        v_checked_by_user_id := null;
        v_checked_at := null;
      elsif v_is_checked then
        -- A check names the acting user (AC3); the stamp time is the
        -- write's own time.
        v_checked_by_user_id := v_uid;
        v_checked_at := v_updated_at;
      else
        v_checked_by_user_id := null;
        v_checked_at := null;
      end if;

      -- The profile must exist (same FK-backstop rejection as care_notes).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #128's write ladder: identical to care_notes (logging, not
      -- profile metadata).
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write visit prep items for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_prep_item
        from public.visit_prep_items
       where id = v_id
       for update;

      if found then
        -- An item never legitimately changes profiles (the care_notes
        -- cannot-move-between-profiles pattern).
        if v_stored_prep_item.profile_id is distinct from v_profile_id then
          raise exception 'visit prep item cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_prep_item.updated_at
          or (v_updated_at = v_stored_prep_item.updated_at
              and v_deleted_at is not null
              and v_stored_prep_item.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_prep_item.updated_at
                  and v_deleted_at is not null
                  and v_stored_prep_item.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_prep_item) || jsonb_build_object('table', 'visit_prep_items'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_prep_item.id is null then
        insert into public.visit_prep_items
          (id, profile_id, body, is_checked, checked_by_user_id, checked_at,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_body, v_is_checked, v_checked_by_user_id, v_checked_at,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored_prep_item;
      else
        update public.visit_prep_items
           set body = v_body,
               is_checked = v_is_checked,
               -- A text edit that leaves the check state unchanged keeps
               -- the stored stamp (editing a co-guardian's checked item
               -- must not silently re-stamp who checked it); only a real
               -- check/uncheck transition -- or a tombstone -- rewrites
               -- it. A tombstone always clears (the
               -- visit_prep_items_tombstone_payload_check mirror).
               checked_by_user_id = case
                 when v_deleted_at is not null then null
                 when v_is_checked is distinct from v_stored_prep_item.is_checked
                   then v_checked_by_user_id
                 else v_stored_prep_item.checked_by_user_id end,
               checked_at = case
                 when v_deleted_at is not null then null
                 when v_is_checked is distinct from v_stored_prep_item.is_checked
                   then v_checked_at
                 else v_stored_prep_item.checked_at end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
        returning * into v_stored_prep_item;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;
  -- -------------------------------------------------------------------------
  -- day_entry_merge_events (Issue #130): client-resolver-authored merge
  -- disclosures. Rows are machine-written by whichever device's
  -- _resolveSameDateConflicts computed the merge, and ride the normal push
  -- path like any synced table. The write ladder is the day_entries ladder
  -- (any accepted non-viewer guardian) -- these are logging-path rows, not
  -- profile metadata. Rows are IMMUTABLE here: the unique natural key
  -- (profile_id, losing_row_id, field) dedupes a second device's record of
  -- the same discard (the server's own emission and a client's can race;
  -- first writer wins, and both describe the same event), so there is no
  -- update path at all -- a re-push of the same natural key is a no-op,
  -- never a rejection.
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_merge_events) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_merge_event_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      if (v_row ->> 'local_date') is null
         or (v_row ->> 'local_date') !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'local_date is not an ISO calendar date';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      v_merge_winning_row_id := v_row ->> 'winning_row_id';
      if v_merge_winning_row_id is null or v_merge_winning_row_id !~ c_ulid then
        raise exception 'winning_row_id is not a ULID';
      end if;
      v_merge_losing_row_id := v_row ->> 'losing_row_id';
      if v_merge_losing_row_id is null or v_merge_losing_row_id !~ c_ulid then
        raise exception 'losing_row_id is not a ULID';
      end if;
      v_merge_field := v_row ->> 'field';
      if v_merge_field not in ('flow', 'note') then
        raise exception 'field must be flow or note';
      end if;
      -- Retained health text (the discarded note, or a flow level string):
      -- bounded by the same CHECK as the table, rejected -- never
      -- truncated -- on this client-authoring path.
      v_merge_losing_value := v_row ->> 'losing_value_text';
      if v_merge_losing_value is null or char_length(v_merge_losing_value) > 2000 then
        raise exception 'losing_value_text is required and bounded to 2000 characters';
      end if;
      v_merge_losing_author := (v_row ->> 'losing_author_user_id')::uuid;
      v_merge_winning_author := (v_row ->> 'winning_author_user_id')::uuid;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject an updated_at more than five minutes ahead of
      -- the server's own clock (same rationale as every table above).
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection; same enumeration-parity as care_notes above).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #130's write ladder: the day_entries ladder.
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write merge events for profile'
          using errcode = 'insufficient_privilege';
      end if;

      insert into public.day_entry_merge_events
        (id, profile_id, local_date, winning_row_id, losing_row_id, field,
         losing_value_text, losing_author_user_id, winning_author_user_id,
         created_at, updated_at)
      values
        (v_id, v_profile_id, v_local_date, v_merge_winning_row_id,
         v_merge_losing_row_id, v_merge_field, v_merge_losing_value,
         v_merge_losing_author, v_merge_winning_author,
         v_updated_at, v_updated_at)
      on conflict (profile_id, losing_row_id, field) do nothing;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- profile_tag_registry (Issue #257): per-id LWW with tombstones,
  -- mirroring the care_notes accept/decline shape (see this migration's
  -- header). Retirement (hidden_at) is an ordinary payload column on this
  -- path -- the write that removes a code from the picker, never anything
  -- stronger. The per-profile live-row cap runs only when this row will
  -- actually land live (a tombstone, or an update to an already-live row,
  -- adds nothing to the count). created_by is stamped from the caller on
  -- INSERT and preserved on UPDATE -- never accepted per-row.
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_tag_registry) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_tag_registry_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      v_registry_code := v_row ->> 'code';
      if v_registry_code is null or char_length(v_registry_code) < 1
         or char_length(v_registry_code) > 64 then
        raise exception 'code is required and bounded to 64 characters';
      end if;
      v_registry_display_name := v_row ->> 'display_name';
      if v_registry_display_name is null or char_length(v_registry_display_name) > 40 then
        raise exception 'display_name is required and bounded to 40 characters';
      end if;
      v_registry_category := v_row ->> 'category';
      if v_registry_category is null or char_length(v_registry_category) < 1
         or char_length(v_registry_category) > 64 then
        raise exception 'category is required and bounded to 64 characters';
      end if;
      -- Optional payload columns: parsed with the defaults an INSERT
      -- needs; the UPDATE path below only overwrites a stored value when
      -- the incoming row actually carries the key (the U1/#108/#131
      -- containment pattern -- a partial-row writer never clobbers).
      v_registry_intensity_enabled :=
        coalesce((v_row ->> 'intensity_enabled')::boolean, false);
      v_registry_hidden_at := (v_row ->> 'hidden_at')::timestamptz;
      v_registry_sort_order := (v_row ->> 'sort_order')::integer;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566: reject (this row alone, via the per-row exception
      -- handler below) an updated_at more than five minutes ahead of the
      -- server's own clock, exactly like every table above.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (the #224 house pattern): the
        -- label, category, retirement stamp and sort position clear
        -- UNCONDITIONALLY here -- a tombstone push carrying a stale
        -- payload still lands payload-free, as
        -- profile_tag_registry_tombstone_payload_check demands. `code`
        -- survives (the #159 provenance precedent -- see this
        -- migration's header).
        v_registry_display_name := '';
        v_registry_category := '';
        v_registry_intensity_enabled := false;
        v_registry_hidden_at := null;
        v_registry_sort_order := null;
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection; same enumeration-parity as care_notes above).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #257's write ladder: the day_entries ladder (any accepted
      -- non-viewer guardian), NOT the stricter #188 profile-metadata
      -- ladder -- a custom tag is logging vocabulary, like a care note.
      v_caller_role := v_role_map ->> v_profile_id;

      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write profile tag registry for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_registry_row
        from public.profile_tag_registry
       where id = v_id
       for update;

      if found then
        -- A registry row never legitimately changes profiles: the role
        -- check above ran against v_profile_id only, so a re-pointed row
        -- would smuggle another profile's tag past that check (the
        -- day_entries cannot-move-between-profiles pattern).
        if v_stored_registry_row.profile_id is distinct from v_profile_id then
          raise exception 'profile tag registry entry cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_registry_row.updated_at
          or (v_updated_at = v_stored_registry_row.updated_at
              and v_deleted_at is not null
              and v_stored_registry_row.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_registry_row.updated_at
                  and v_deleted_at is not null
                  and v_stored_registry_row.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_registry_row) || jsonb_build_object('table', 'profile_tag_registry'));
          end if;
          continue;
        end if;
      end if;

      -- Per-profile live-row cap (Issue #257's acceptance criteria:
      -- enforced in the write RPC, not a CHECK, since a CHECK cannot
      -- count sibling rows). Counted only when this row will actually
      -- land as a NEW live row -- a tombstone, an update to an
      -- already-live row, or a row that just lost LWW above adds nothing
      -- to the day's live count. Counting inside the same transaction as
      -- every row already inserted earlier in this same loop iteration
      -- bounds a single oversized batch too.
      if v_deleted_at is null
         and (v_stored_registry_row.id is null or v_stored_registry_row.deleted_at is not null) then
        select count(*) into v_registry_count
          from public.profile_tag_registry
         where profile_id = v_profile_id
           and deleted_at is null;
        if v_registry_count >= c_max_tags_per_profile then
          raise exception 'profile % already has % live custom tags, at the % cap',
            v_profile_id, v_registry_count, c_max_tags_per_profile
            using errcode = 'invalid_parameter_value';
        end if;
      end if;

      if v_stored_registry_row.id is null then
        insert into public.profile_tag_registry
          (id, profile_id, code, display_name, category, intensity_enabled,
           hidden_at, sort_order, created_by, created_at, updated_at, deleted_at)
        values
          (v_id, v_profile_id, v_registry_code, v_registry_display_name,
           v_registry_category, v_registry_intensity_enabled,
           v_registry_hidden_at, v_registry_sort_order, v_uid, now(),
           v_updated_at, v_deleted_at);
      else
        update public.profile_tag_registry
           set -- Containment guards on the optional payload columns for a
               -- LIVE write (the U1/#131/#159 pattern): a partial-row
               -- writer that omits a key never silently resets an
               -- already-stored value. A TOMBSTONE write bypasses the
               -- guards and clears unconditionally -- the tombstone parse
               -- branch above already set the cleared values, so the
               -- `v_deleted_at is not null` arms simply write them
               -- through.
               display_name = case
                 when v_deleted_at is not null then ''
                 when v_row ? 'display_name' then v_registry_display_name
                 else v_stored_registry_row.display_name end,
               category = case
                 when v_deleted_at is not null then ''
                 when v_row ? 'category' then v_registry_category
                 else v_stored_registry_row.category end,
               intensity_enabled = case
                 when v_deleted_at is not null then false
                 when v_row ? 'intensity_enabled' then v_registry_intensity_enabled
                 else v_stored_registry_row.intensity_enabled end,
               hidden_at = case
                 when v_deleted_at is not null then null
                 when v_row ? 'hidden_at' then v_registry_hidden_at
                 else v_stored_registry_row.hidden_at end,
               sort_order = case
                 when v_deleted_at is not null then null
                 when v_row ? 'sort_order' then v_registry_sort_order
                 else v_stored_registry_row.sort_order end,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at
         where id = v_id;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  -- -------------------------------------------------------------------------
  -- guardian_notes (Issue #801): one dated, author-scoped note per row.
  -- Per-id LWW with tombstones, exactly like the care_notes loop above --
  -- but with an author-ownership gate: a stored row may be edited or
  -- tombstoned only by its original author (logged_by_user_id). A
  -- non-viewer guardian may always INSERT a new note (the RPC stamps it as
  -- its own). No cross-author merge, ever -- two authors on the same day
  -- are two distinct ULIDs, both live.
  -- -------------------------------------------------------------------------
  -- Issue #95: deterministic lock order - iterate the payload in key
  -- order so concurrent guardians lock the same rows in the same sequence.
  for v_row in select value from jsonb_array_elements(p_guardian_notes) order by value ->> 'id' loop
    begin
      if jsonb_typeof(v_row) <> 'object' then
        raise exception 'row is not an object';
      end if;
      if exists (select 1 from jsonb_object_keys(v_row) k where k <> all (c_guardian_note_keys)) then
        raise exception 'row carries an unknown key';
      end if;

      v_id := v_row ->> 'id';
      if v_id is null or v_id !~ c_ulid then
        raise exception 'id is not a ULID';
      end if;
      v_profile_id := v_row ->> 'profile_id';
      if v_profile_id is null or v_profile_id !~ c_ulid then
        raise exception 'profile_id is not a ULID';
      end if;
      v_local_date := (v_row ->> 'local_date')::date;
      if v_local_date is null then
        raise exception 'local_date is required';
      end if;
      v_tz := v_row ->> 'tz';
      if v_tz is null then
        raise exception 'tz is required';
      end if;
      v_body := v_row ->> 'body';
      if v_body is null then
        raise exception 'body is required';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      -- Issue #566 house rule, same as every table above: a clock badly
      -- ahead of the server must not win every future LWW race.
      if v_updated_at > now() + interval '5 minutes' then
        raise exception 'updated_at is in the future'
          using errcode = 'invalid_parameter_value';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      if v_deleted_at is not null then
        -- Tombstones carry no payload (the #224 house pattern):
        -- guardian_notes_tombstone_payload_check demands the '' sentinel.
        v_body := '';
      end if;

      -- The profile must exist (FK backstop turned into a typed, opaque
      -- rejection, same enumeration-parity as every sibling loop).
      if not exists (select 1 from public.profiles p where p.id = v_profile_id) then
        raise exception 'profile does not exist';
      end if;

      -- Issue #801's write ladder: identical to care_notes (logging, not
      -- profile metadata) -- any accepted guardian except a viewer writes.
      v_caller_role := v_role_map ->> v_profile_id;
      if v_caller_role is null or v_caller_role = 'viewer' then
        raise exception 'caller is not authorized to write guardian notes for profile'
          using errcode = 'insufficient_privilege';
      end if;

      select * into v_stored_guardian_note
        from public.guardian_notes
       where id = v_id
       for update;

      if found then
        -- A note never legitimately changes profiles (the day_entries
        -- cannot-move-between-profiles pattern).
        if v_stored_guardian_note.profile_id is distinct from v_profile_id then
          raise exception 'guardian note cannot move between profiles'
            using errcode = 'insufficient_privilege';
        end if;
        -- Author-ownership: only the original author may edit or tombstone.
        -- logged_by_user_id is never accepted from the payload (stamped on
        -- insert) and is author-immutable by the attribution trigger, so
        -- this cannot be bypassed by re-attributing the row.
        if v_stored_guardian_note.logged_by_user_id is distinct from v_uid then
          raise exception 'only the author may modify a guardian note'
            using errcode = 'insufficient_privilege';
        end if;
        v_accept := v_updated_at > v_stored_guardian_note.updated_at
          or (v_updated_at = v_stored_guardian_note.updated_at
              and v_deleted_at is not null
              and v_stored_guardian_note.deleted_at is null);
        if not v_accept then
          if not (v_updated_at = v_stored_guardian_note.updated_at
                  and v_deleted_at is not null
                  and v_stored_guardian_note.deleted_at is not null) then
            -- declined (older, or equal-and-live): hand back the server copy
            v_resolved := v_resolved
              || (to_jsonb(v_stored_guardian_note)
                  || jsonb_build_object('table', 'guardian_notes'));
          end if;
          continue;
        end if;
      end if;

      if v_stored_guardian_note.id is null then
        insert into public.guardian_notes
          (id, profile_id, local_date, tz, body, updated_at, deleted_at,
           logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_body, v_updated_at,
           v_deleted_at, v_uid, v_uid)
        returning * into v_stored_guardian_note;
      else
        update public.guardian_notes
           set local_date = v_local_date,
               tz = v_tz,
               body = v_body,
               updated_at = v_updated_at,
               deleted_at = v_deleted_at,
               last_modified_by_user_id = v_uid
         where id = v_id
        returning * into v_stored_guardian_note;
      end if;
    exception
      when sqlstate '40P01' or sqlstate '40001' or sqlstate '55P03' then
        raise;
      when others then
        v_rejected := v_rejected || jsonb_build_object('id', v_row -> 'id', 'rejected', true);
    end;
  end loop;

  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$fn$;
$ddl$;

  v_body := replace(v_body, '__SYNC_PUSH_PROFILE_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('profiles'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_DAY_ENTRY_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('day_entries'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_OBSERVATION_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('observations'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_PROFILE_MODE_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('profile_modes'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_CYCLE_OVERRIDE_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('cycle_overrides'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_CARE_NOTE_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('care_notes'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_VISIT_PREP_ITEM_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('visit_prep_items'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_MERGE_EVENT_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('day_entry_merge_events'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_TAG_REGISTRY_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('profile_tag_registry'), ',') || '}'));
  v_body := replace(v_body, '__SYNC_PUSH_GUARDIAN_NOTE_KEYS__',
    quote_literal('{' || array_to_string(public.sync_push_payload_keys('guardian_notes'), ',') || '}'));

  if v_body like '%__SYNC_PUSH_%' then
    raise exception 'unsubstituted allowlist placeholder remains in the sync_push template'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  execute v_body;

  select p.prosrc into v_src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'sync_push';

  if v_src is null then
    raise exception 'public.sync_push not found after materialization'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_src ~ '__SYNC_PUSH_' or v_src !~ 'c_profile_keys[[:space:]]+constant[[:space:]]+text\[\][[:space:]]*:=[[:space:]]*''\{' then
    raise exception 'embedded allowlist declarations not found in canonical form after materialization'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
end
$derive$;

-- ---------------------------------------------------------------------------
-- 6. Privileges on the re-emitted 10-argument sync_push. Adding a parameter
--    created a new function identity, so the old grants do not carry over.
-- ---------------------------------------------------------------------------

revoke execute on function public.sync_push(
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon;
grant execute on function public.sync_push(
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. The function comment is re-stated for the new identity (the old
--    overload's comment died with its DROP). It carries the
--    tombstone-resurrection-guard text the pgTAP suite pins
--    (sync_push_tombstone_resurrection_guard_test.sql) plus Issue #801's
--    guardian-notes addition.
-- ---------------------------------------------------------------------------

comment on function public.sync_push(
  jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, observations, profile_modes, '
  'cycle_overrides, care_notes, visit_prep_items, day_entry_merge_events, '
  'profile_tag_registry, and (Issue #801) guardian_notes under guardian '
  'role permissions with authoritative attribution stamping. See prior '
  'migrations'' function comments (20260906200000 onward) for the full '
  'per-table history. Issue #201: SECURITY DEFINER, sole write path for '
  'day_entries -- `authenticated` holds no insert/update on that table at '
  'all. Coordinator review of PR #705 (#263/#189): the day_entries loop''s '
  '"no stored row" branch rejects (does not insert) an incoming id whose '
  'updated_at predates enforce_retention()''s own 180-day day_entries '
  'tombstone-purge window (20260915200000_nightly_retention_job.sql) -- '
  'without this, a client offline the entire 180+ days could resurrect a '
  'row whose tombstone was already hard-deleted. Issue #801 adds the tenth '
  'payload array, p_guardian_notes: one dated, author-scoped note per row, '
  'per-id LWW with tombstones like care_notes, BUT gated by author '
  'ownership -- only the stored logged_by_user_id (the original author) may '
  'edit or tombstone that row, so no guardian can alter another''s note. '
  'The ten per-table key allowlists stay DERIVED (issue #181) and are '
  'materialized at CREATE time by this migration''s DO block.';

