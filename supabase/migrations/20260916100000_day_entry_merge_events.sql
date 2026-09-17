-- Migration: 20260916100000_day_entry_merge_events.sql
--
-- Issue #130 (P2, epics: sharing + tracking-model): "tell guardians when a
-- same-date merge discarded a value". The same-date resolver merges two
-- independently-logged rows for one date -- tags as a set union, but `flow`
-- and `note` last-writer-wins (KTD4) -- and the losing values vanished
-- silently. Both guardians see nothing; the losing author loses their text
-- with no explanation and no recovery. #124 already renders a
-- DEVICE-LOCAL activity-feed row (merge_events under app_settings), which
-- never reaches the other guardian's device and retains no text.
--
-- This migration adds the synced disclosure substrate:
--
--   1. `public.day_entry_merge_events`: one row per same-date merge that
--      actually discarded a `flow` or `note` value -- the merge's date,
--      winning/losing row ids, which field lost, the losing value's text
--      (bounded to the same 2000-char bound as day_entries.note), and
--      losing/winning authorship (uuid display attribution only). Tags-only
--      merges emit NOTHING (a set union loses nothing -- AC); the same-id
--      convergence path never runs the resolver, so it emits nothing
--      either (KTD5 -- union is deliberately wrong there -- AC).
--
--   2. `sync_push`: both same-date resolver branches insert the row(s) in
--      the same transaction as the merge, via the new
--      `public.record_day_entry_merge_discard()` helper; and a new eighth
--      defaulted payload parameter `p_merge_events` accepts
--      client-resolver-authored rows (the #240/#188/#128 defaulted-param
--      pattern), so `LunarLogStorage._resolveSameDateConflicts`'s local
--      emission reaches the server through the normal push path. THE MERGE
--      RULE ITSELF IS UNCHANGED -- this is disclosure, not resolution.
--
--   3. Dedupe by natural key: `unique (profile_id, losing_row_id, field)`.
--      The same discard can be witnessed by two devices (the loser's
--      device resolves the collision locally when the winner's row is
--      pulled; the server resolves it when both rows arrive by push), so
--      both resolvers may race to record it -- first writer wins, ON
--      CONFLICT DO NOTHING, and the loser row's id can never repeat a
--      discard it already recorded. A losing day_entries row is
--      tombstoned by the very merge being disclosed, so (losing_row_id,
--      field) identifies exactly one discard.
--
--   4. Retention: `enforce_retention()` purges rows older than 30 days
--      (the recovery window -- long enough for a guardian to see the
--      notice and re-enter their text, short enough that retained health
--      text about a minor stays bounded). No sync-correctness constraint
--      attaches to this window (a client's local copies age out of the day
--      sheet's own 30-day display window in lockstep; nothing keys a
--      cursor or a resurrection guard on this table).
--
--   5. `reconcile_realtime_publication()`: the table joins the
--      must-never-publish list (it carries the losing note text). A
--      `touch_sync_signal()` trigger still gives co-guardians' devices a
--      content-free realtime wake, exactly like care_notes.
--
--   6. `tombstone_profile_content()`: hard-deletes the profile's merge
--      events. Both callers (delete_profile_data / delete_account_data)
--      tombstone rather than hard-delete the profile itself, so the
--      profiles FK cascade never fires for them -- this explicit delete is
--      the only removal path on a content wipe, and it keeps a wiped
--      profile's discarded note texts from lingering after the content
--      they describe is gone. Scoped to the whole wiped profile (sibling
--      R7 shape: a shared profile's disclosures are the owning family's).
--      The counts surface in tombstone_profile_content()'s returned jsonb;
--      delete_account_data()/delete_profile_data() are NOT re-emitted --
--      the load-bearing deletion happens here, in the one helper both
--      already call.
--
--   7. `sync_pull(p_cursors)`: a ninth per-profile key,
--      'day_entry_merge_events', same tenant scoping and page contract as
--      every content table (the client's primePullCycle would otherwise
--      see a missing key and silently drop its whole cache).
--
-- Design decisions worth naming:
--
--   * NO tombstone column (deviating from the day_entries shape this table
--     otherwise mirrors): nothing ever soft-deletes a merge event --
--     dismissal is device-local by design (one guardian dismissing must
--     not erase the other guardian's notice -- AC), and the only removals
--     are the retention purge and the profile wipe, both hard DELETEs.
--     profile_modes is the established no-tombstone precedent.
--   * The losing value text is retained server-side under the SAME
--     protection posture as day_entries.note: RLS to accepted guardians
--     only, never published to Realtime, length-bounded by CHECK, never
--     in a notification payload (no outbox trigger fires from this
--     table), and the client keeps it out of crash reports (the
--     sentryDenyListedKeys posture day_entries.note already uses).
--   * `export_account_data()` is deliberately untouched, on the #188/#128
--     precedent (client-synced tables are the local JSON export's
--     responsibility). The LOCAL export DOES carry them (export schema
--     v11, `profiles[].mergeEvents`): that is where every synced client
--     table exports, and the user's own discarded writing is exactly the
--     data a "Export my data" right-of-access exists for. The bounded-
--     retention posture survives in two scoping rules: only events still
--     inside the 30-day window are exported (the file never extends the
--     retention the server enforces -- the read filters on the same
--     kDayEntryMergeEventRetention window the day sheet does), and the
--     #140 importer does NOT restore them (machine-written records of
--     merges that already happened, not user state a backup needs to
--     replay as fresh notices; the import parser reads known keys only,
--     so a v11 file round-trips harmlessly).
--
-- Coverage: supabase/tests/day_entry_merge_events_test.sql.

-- ---------------------------------------------------------------------------
-- 1. public.day_entry_merge_events
-- ---------------------------------------------------------------------------

create table public.day_entry_merge_events (
  id text not null
    constraint day_entry_merge_events_id_ulid_check
    check (id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  local_date date not null,
  -- The surviving row's id and the tombstoned row's id at merge time.
  winning_row_id text not null
    constraint day_entry_merge_events_winning_row_id_ulid_check
    check (winning_row_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  losing_row_id text not null
    constraint day_entry_merge_events_losing_row_id_ulid_check
    check (losing_row_id ~ '^[0-9A-HJKMNP-TV-Z]{26}$'),
  -- Which value kind was discarded. The closed set IS the table's purpose:
  -- tags are unioned, never discarded, so no row may claim them.
  field text not null
    constraint day_entry_merge_events_field_check
    check (field in ('flow', 'note')),
  -- The discarded value itself: the losing note's text, or the losing flow
  -- level's wire string ('heavy' etc.). Health content about a minor --
  -- same protection posture as day_entries.note, same 2000-char bound.
  -- Not null with an '' sentinel when the discarded value was an empty
  -- string, so null-vs-cleared is never ambiguous.
  losing_value_text text not null default ''
    constraint day_entry_merge_events_losing_value_length_check
    check (char_length(losing_value_text) <= 2000),
  -- Display attribution only (never a permission input): whose value was
  -- discarded, and whose survived. Read like
  -- caregiver_attribution_badge.dart reads logged_by/last_modified.
  losing_author_user_id uuid references auth.users (id) on delete set null,
  winning_author_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  server_version bigint not null default 0,
  primary key (id),
  -- The natural key of one discard: a losing day_entries row is tombstoned
  -- by the very merge being disclosed, so it can lose at most one value per
  -- field. Deduplicates the server resolver's emission against a client
  -- resolver's push of the same event (first writer wins).
  constraint day_entry_merge_events_discard_uq
    unique (profile_id, losing_row_id, field)
);

comment on table public.day_entry_merge_events is
  'Issue #130: one row per same-date day-entry merge that discarded a flow or note value (tags-only merges emit nothing). Carries the losing value''s text for author recovery, bounded to 2000 characters, purged after 30 days by enforce_retention(). No tombstone: dismissal is device-local; removals are the retention purge and the profile wipe (tombstone_profile_content). Rows are machine-written by the sync_push resolver or pushed by the client resolver that witnessed the merge -- never user-composed content.';

create index day_entry_merge_events_profile_date_idx
  on public.day_entry_merge_events (profile_id, local_date);
create index day_entry_merge_events_server_version_idx
  on public.day_entry_merge_events (server_version);
-- Retention scan support (the 30-day purge predicate), matching
-- notification_outbox_sent_at_idx's role in the same job.
create index day_entry_merge_events_created_at_idx
  on public.day_entry_merge_events (created_at);

create trigger day_entry_merge_events_set_server_version
  before insert or update on public.day_entry_merge_events
  for each row execute function public.set_server_version();

-- Realtime: no publication membership (see reconcile_realtime_publication
-- below). The wake signal is content-free, exactly like every content
-- table's -- touch_sync_signal() branches on new.profile_id for anything
-- that is not literally the profiles table.
create trigger day_entry_merge_events_after_change_signal
  after insert or update or delete on public.day_entry_merge_events
  for each row execute function public.touch_sync_signal();

-- ---------------------------------------------------------------------------
-- 2. Row-Level Security: reads mirror day_entries' guardian predicate;
--    writes have NO policy and NO grant at all -- sync_push (SECURITY
--    DEFINER, the sole write path since 20260915160000) is the only
--    writer, the exact posture day_entries itself carries on main.
-- ---------------------------------------------------------------------------

alter table public.day_entry_merge_events enable row level security;
alter table public.day_entry_merge_events force row level security;

create policy "day_entry_merge_events_select_guardians" on public.day_entry_merge_events
  for select to authenticated
  using (
    public.is_profile_guardian(profile_id, (select auth.uid()))
  );

revoke all on table public.day_entry_merge_events from public, anon, authenticated;
grant select on table public.day_entry_merge_events to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The emission helper sync_push's resolver branches call. SECURITY
--    INVOKER (it only ever runs inside sync_push's own SECURITY DEFINER
--    context, as the function owner), fully qualified, EXECUTE revoked
--    from every client-facing role. Truncates the retained text to the
--    CHECK bound itself -- an emission must never abort the merge it is
--    disclosing (a per-row exception in sync_push's day_entries loop
--    would reject the whole merged row).
--
--    The id is 26 hex characters taken from a random uuid (core
--    gen_random_uuid(), always visible under a pinned search_path --
--    unlike gen_random_bytes, which lives in the extensions schema here):
--    every hex digit is inside the Crockford base32 set the table's ULID
--    CHECK accepts. Random identity is fine -- rows are keyed by the
--    natural key, never ordered by id.
-- ---------------------------------------------------------------------------

create or replace function public.record_day_entry_merge_discard(
  p_profile_id text,
  p_local_date date,
  p_winning_row_id text,
  p_losing_row_id text,
  p_field text,
  p_losing_value text,
  p_losing_author uuid,
  p_winning_author uuid
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into public.day_entry_merge_events
    (id, profile_id, local_date, winning_row_id, losing_row_id, field,
     losing_value_text, losing_author_user_id, winning_author_user_id,
     created_at, updated_at)
  values
    (upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 26)),
     p_profile_id, p_local_date,
     p_winning_row_id, p_losing_row_id, p_field,
     left(coalesce(p_losing_value, ''), 2000),
     p_losing_author, p_winning_author,
     now(), now())
  on conflict (profile_id, losing_row_id, field) do nothing;
end;
$$;

comment on function public.record_day_entry_merge_discard(text, date, text, text, text, text, uuid, uuid) is
  'Issue #130: records one same-date merge discard (flow or note) into day_entry_merge_events, deduplicated by (profile_id, losing_row_id, field). Called only from sync_push''s same-date resolver branches; truncates the retained text to the 2000-character CHECK bound so an emission can never abort the merge it discloses.';

revoke execute on function public.record_day_entry_merge_discard(text, date, text, text, text, text, uuid, uuid) from public, anon, authenticated;

  
-- ---------------------------------------------------------------------------
-- 4. sync_push: re-emitted verbatim from its immediate predecessor
--    (20260915200001_sync_push_tombstone_resurrection_guard.sql, still the
--    latest definition on main at dispatch time) with exactly the Issue
--    #130 changes its own comment names -- the two resolver-branch
--    emissions, the eighth defaulted payload parameter + its loop, and
--    the c_max_total_rows 3500 -> 4000 no-op-cap growth. Everything else
--    (the 20260915200001 tombstone-resurrection guard included) carries
--    forward unchanged.
-- ---------------------------------------------------------------------------

-- Postgres identifies a function by name + parameter TYPE LIST: adding
-- a parameter does not replace the existing 7-argument sync_push in
-- place -- it would sit alongside it as a second, distinct overload
-- (the exact-arity match winning over a default-substituted one),
-- silently forking the function in two. Drop the 7-arg overload first
-- so exactly one sync_push exists afterwards and a 2- through
-- 7-argument call resolves to THIS body with p_merge_events taking its
-- '[]'::jsonb default (the #240/#128 technique).
drop function if exists public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb);

create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb,
  p_profile_modes jsonb default '[]'::jsonb,
  p_cycle_overrides jsonb default '[]'::jsonb,
  p_care_notes jsonb default '[]'::jsonb,
  p_visit_prep_items jsonb default '[]'::jsonb,
  p_merge_events jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_rows constant integer := 500;
  c_max_observations_per_day constant integer := 200;
  -- Issue #564: total-row cap across all payload arrays combined.
  -- 3500 (= 7 * c_max_rows) was a no-op cap when seven arrays existed;
  -- Issue #130 adds the eighth (p_merge_events), so the cap grows with it
  -- to 4000 (= 8 * c_max_rows) -- still exactly one full batch per array,
  -- still a no-op rather than a real tightening (the Dart sync engine
  -- legitimately fills every table to 500 rows each on a first sync or a
  -- post-Clue-import push; a lower cap would reject that call outright and
  -- the client would retry it forever). A stricter combined cap needs a
  -- client-side batch-size change first.
  c_max_total_rows constant integer := 4000;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  c_profile_keys constant text[] := array[
    'id', 'display_name', 'is_minor', 'sort_order', 'archived_at',
    'created_at', 'updated_at', 'deleted_at',
    -- U1: profile subject metadata, syncable like any other profile column
    'birth_year', 'relationship',
    -- #131: care mode, syncable like any other profile column
    'mode',
    -- #218: onboarding cycle facts, syncable like any other profile column
    'last_period_start', 'typical_cycle_length_days', 'typical_period_length_days',
    -- #255: numeric-measurement display-unit preferences, syncable like
    -- any other profile column
    'bbt_unit', 'weight_unit',
    -- #259: the curated tracking-categories document, syncable like any
    -- other profile column (category keys inside the document stay free
    -- text -- the taxonomy is client-owned and grows)
    'tracking_preferences',
    -- tolerated but never read
    'user_id', 'server_version', 'transferred_at',
    -- #296: same treatment as transferred_at - ownership state written
    -- only by accept_ownership_transfer, admitted only so a client that
    -- pulls the column back down and echoes it is not rejected for
    -- carrying an "unknown key".
    'transferred_to_user_id'];
  c_day_entry_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    -- Issue #220: the first-class PMS marker.
    'pms',
    -- Issue #159: import-dedup provenance columns.
    'source', 'source_id', 'import_id',
    'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id'];
  -- Issue #240: observations' allowed keys.
  c_observation_keys constant text[] := array[
    'id', 'day_entry_id', 'profile_id', 'local_date', 'observed_at', 'tz',
    'category', 'code', 'value_num', 'value_text', 'unit', 'intensity',
    'excluded', 'source', 'source_id',
  -- Issue #159: import-dedup provenance column (day_entries gets the
  -- same three columns; observations already had source/source_id from
  -- #240 -- this adds only import_id here).
  'import_id',
  -- Issue #186: the round-trip-write marker, same provenance class.
  'exported_to_platform_at', 'raw', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];
  -- Issue #188: profile_modes' allowed keys.
  c_profile_mode_keys constant text[] := array[
    'profile_id', 'mode', 'mode_started_on', 'birth_control_method',
    'birth_control_started_on', 'birth_control_stopped_on',
    'health_sync_consent', 'updated_at',
    -- tolerated but never read
    'server_version'];
  -- Issue #188: cycle_overrides' allowed keys.
  c_cycle_override_keys constant text[] := array[
    'id', 'profile_id', 'cycle_start_date', 'excluded_from_average',
    'manual_start', 'note_id', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'server_version'];
  -- Issue #128: care_notes' allowed keys. checked_by_user_id/checked_at
  -- are deliberately absent -- the server stamps them from the caller and
  -- never accepts them per-row (see this migration's header).
  c_care_note_keys constant text[] := array[
    'id', 'profile_id', 'body', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];
  -- Issue #128: visit_prep_items' allowed keys (same checked_by/checked_at
  -- exclusion as care_notes above).
  c_visit_prep_item_keys constant text[] := array[
    'id', 'profile_id', 'body', 'is_checked', 'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id',
    'created_at'];
  -- Issue #130: day_entry_merge_events' allowed keys. losing_author_user_id/
  -- winning_author_user_id are accepted as sent (display-only attribution of
  -- a discard the client resolver witnessed) and created_at is never written
  -- from a payload -- the server stamps it.
  c_merge_event_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'winning_row_id', 'losing_row_id',
    'field', 'losing_value_text', 'losing_author_user_id',
    'winning_author_user_id', 'updated_at',
    -- tolerated but never read
    'server_version'];

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
     + jsonb_array_length(p_merge_events) > c_max_total_rows then
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
            end if;
            if v_other.flow is distinct from v_flow then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_id, v_other.id, 'flow',
                v_other.flow,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id),
                v_uid);
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
            end if;
            if v_flow is distinct from v_other.flow then
              perform public.record_day_entry_merge_discard(
                v_profile_id, v_local_date, v_other.id, v_id, 'flow',
                v_flow,
                v_uid,
                coalesce(v_other.last_modified_by_user_id, v_other.logged_by_user_id));
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
          (profile_id, mode, mode_started_on, birth_control_method,
           birth_control_started_on, birth_control_stopped_on,
           health_sync_consent, updated_at)
        values
          (v_profile_id, v_mode, v_mode_started_on, v_birth_control_method,
           v_birth_control_started_on, v_birth_control_stopped_on,
           v_health_sync_consent, v_updated_at);
      elsif v_updated_at > v_stored_mode.updated_at then
        update public.profile_modes
           set mode = case when v_row ? 'mode' then v_mode else v_stored_mode.mode end,
               mode_started_on = case when v_row ? 'mode_started_on' then v_mode_started_on else v_stored_mode.mode_started_on end,
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

  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$$;

comment on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, observations, profile_modes, '
  'cycle_overrides, care_notes, visit_prep_items, and day_entry_merge_events '
  'under guardian role permissions with authoritative attribution stamping. '
  'See prior migrations'' function comments (20260906200000 onward) for the '
  'full per-table history; this comment covers only what '
  '20260916100000_day_entry_merge_events.sql changed on top of '
  '20260915200001_sync_push_tombstone_resurrection_guard.sql. Issue #201 '
  '(carried forward unchanged): SECURITY DEFINER, sole write path for '
  'day_entries -- `authenticated` holds no insert/update on that table at '
  'all. Coordinator review of PR #705 (#263/#189), carried forward: the '
  'day_entries loop''s "no stored row" branch rejects (does not insert) an '
  'incoming id whose updated_at predates enforce_retention()''s own 180-day '
  'day_entries tombstone-purge window (20260915200000_nightly_retention_job.sql) '
  '-- without this, a client offline the entire 180+ days could resurrect a '
  'row whose tombstone was already hard-deleted. Issue #130: (a) both '
  'same-date resolver branches now insert '
  'day_entry_merge_events rows (one per discarded flow/note value, none for '
  'a tags-only merge) in the same transaction as the merge, via '
  'public.record_day_entry_merge_discard(); (b) a new eighth defaulted '
  'payload parameter p_merge_events accepts client-resolver-authored '
  'disclosure rows under the day_entries write ladder, deduplicated by the '
  '(profile_id, losing_row_id, field) natural key with ON CONFLICT DO '
  'NOTHING (immutable rows, no update path); (c) c_max_total_rows grows '
  'from 3500 to 4000 to keep the combined cap a no-op for eight arrays. '
  'The merge rule itself is unchanged. No other behavior change.';

-- Explicit and idempotent, matching public.sync_pull(jsonb)'s (20260913014000)
-- own DEFINER-RPC grant pattern -- the authenticated grant already existed
-- from 20260904020000 onward (CREATE OR REPLACE does not touch existing
-- grants), this just makes both grant and revoke sides explicit here too.
revoke all on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. sync_pull(p_cursors): re-emitted from 20260913014000 (unchanged
--    since) with the ninth per-profile key (see header item 7).
-- ---------------------------------------------------------------------------

create or replace function public.sync_pull(p_cursors jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_page_size constant integer := 500;
  v_uid uuid := (select auth.uid());
  v_profile_ids text[];
  v_result jsonb := '{}'::jsonb;
  v_cursor bigint;
begin
  if v_uid is null then
    raise exception 'sync_pull requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  if p_cursors is null or jsonb_typeof(p_cursors) <> 'object' then
    raise exception 'p_cursors must be a JSON object'
      using errcode = 'invalid_parameter_value';
  end if;

  -- The tenant predicate, computed ONCE up front - every page below reuses
  -- this same array rather than invoking a per-row guardian-membership
  -- check (Issue #525, compounding problem 3).
  select coalesce(array_agg(profile_id), '{}') into v_profile_ids
    from public.profile_guardians
   where user_id = v_uid
     and status = 'accepted';

  v_cursor := coalesce((p_cursors ->> 'profiles')::bigint, 0);
  v_result := v_result || jsonb_build_object('profiles', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profiles
       where id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'day_entries')::bigint, 0);
  v_result := v_result || jsonb_build_object('day_entries', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.day_entries
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'observations')::bigint, 0);
  v_result := v_result || jsonb_build_object('observations', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.observations
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'profile_modes')::bigint, 0);
  v_result := v_result || jsonb_build_object('profile_modes', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profile_modes
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'cycle_overrides')::bigint, 0);
  v_result := v_result || jsonb_build_object('cycle_overrides', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.cycle_overrides
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'care_notes')::bigint, 0);
  v_result := v_result || jsonb_build_object('care_notes', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.care_notes
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  v_cursor := coalesce((p_cursors ->> 'visit_prep_items')::bigint, 0);
  v_result := v_result || jsonb_build_object('visit_prep_items', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.visit_prep_items
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  -- Issue #130: day_entry_merge_events rides the same per-profile
  -- scoping as every content table above (reads are RLS-guarded to
  -- accepted guardians; this SECURITY DEFINER page computes the same
  -- tenant set itself).
  v_cursor := coalesce((p_cursors ->> 'day_entry_merge_events')::bigint, 0);
  v_result := v_result || jsonb_build_object('day_entry_merge_events', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.day_entry_merge_events
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  -- profile_guardians: every membership row on every profile in the
  -- tenant set (not just the caller's own row) - see this migration's
  -- header contract note.
  v_cursor := coalesce((p_cursors ->> 'profile_guardians')::bigint, 0);
  v_result := v_result || jsonb_build_object('profile_guardians', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from (
      select * from public.profile_guardians
       where profile_id = any(v_profile_ids)
         and server_version > v_cursor
       order by server_version
       limit c_page_size
    ) t
  ));

  return v_result;
end;
$$;

comment on function public.sync_pull(jsonb) is
  'Issue #525: SECURITY DEFINER incremental-pull RPC returning one page '
  '(<= 500 rows, ordered by server_version) per synced table -- profiles, '
  'day_entries, observations, profile_modes, cycle_overrides, care_notes, '
  'visit_prep_items, day_entry_merge_events, profile_guardians -- filtered '
  'to the caller''s '
  'ACCEPTED profile_guardians membership set BEFORE the server_version '
  'cursor, computed once up front rather than per row. Not yet called by '
  'the client (the seven-table pull in supabase_sync_engine.dart is '
  'unchanged) -- this is the contract a future client-side change adopts. '
  'See 20260913014000_sync_server_version_indexes_and_pull.sql''s header '
  'for the full per-key contract.';

revoke all on function public.sync_pull(jsonb) from public, anon;
grant execute on function public.sync_pull(jsonb) to authenticated;


-- ---------------------------------------------------------------------------
-- 6. tombstone_profile_content(): re-emitted from its current definition
--    (20260913013000_deleted_profiles_tombstone_purge.sql, unchanged since)
--    with the merge-events hard delete + count (see this migration's
--    header item 6 for why the explicit delete is load-bearing).
-- ---------------------------------------------------------------------------

create or replace function public.tombstone_profile_content(
  p_profile_id text,
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_day_entries bigint := 0;
  v_observations bigint := 0;
  v_care_notes bigint := 0;
  v_visit_prep_items bigint := 0;
  v_cycle_overrides bigint := 0;
  v_day_entry_merge_events bigint := 0;
begin
  -- last_modified_by_user_id is set explicitly on every UPDATE below (the
  -- enforce_day_entry_attribution / enforce_observation_attribution /
  -- enforce_care_note_attribution / enforce_prep_item_attribution guards
  -- each raise, on an UPDATE, unless `new.last_modified_by_user_id` equals
  -- the calling auth.uid() exactly - the same requirement sync_push's own
  -- UPDATE branches satisfy on every row they touch). coalesce() falls
  -- back to the row's existing stamp only for a null-auth.uid() caller
  -- (migrations/service role - the attribution guards return early in that
  -- case and do not check this column at all, but the coalesce keeps the
  -- column itself sane either way). cycle_overrides carries no attribution
  -- columns and needs no such guard.
  --
  -- Counted BEFORE the day_entries update below, not via that update's own
  -- explicit UPDATE row_count: day_entries_after_tombstone_cascade_observations
  -- (20260913012000_cascade_tombstone_lww_guard.sql, greatest()-guarded)
  -- tombstones every live child observation as a side effect of the
  -- day_entries UPDATE's own AFTER trigger, BEFORE the explicit
  -- `update public.observations ... where deleted_at is null` below ever
  -- runs - so by the time that statement executes, the cascade has already
  -- excluded every row it touched from matching `deleted_at is null`, and
  -- its own row_count would undercount (report 0 even though every
  -- observation was, correctly, tombstoned - just via the cascade, not
  -- this statement). Every live observation on the profile is guaranteed
  -- to end up tombstoned by the end of this function (via the cascade, or
  -- the explicit catch-all below for the belt-and-suspenders case the
  -- cascade doesn't cover), so the pre-count here is the correct total
  -- regardless of which path actually did the write.
  select count(*) into v_observations
    from public.observations
   where profile_id = p_profile_id
     and deleted_at is null;

  update public.day_entries
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         flow = 'none',
         note = null,
         tags = '[]'::jsonb,
         pms = false,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_day_entries = row_count;

  -- Belt-and-suspenders catch-all (see the comment above): every live
  -- observation has a day_entry_id, so in practice this touches zero rows
  -- - the cascade above already got all of them - but it is not relied
  -- upon for the returned count.
  update public.observations
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         category = null,
         code = null,
         value_num = null,
         value_text = null,
         unit = null,
         intensity = null,
         excluded = false,
         raw = null,
         observed_at = null,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;

  update public.care_notes
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         body = '',
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_care_notes = row_count;

  update public.visit_prep_items
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         body = '',
         is_checked = false,
         checked_by_user_id = null,
         checked_at = null,
         last_modified_by_user_id = coalesce(v_uid, last_modified_by_user_id)
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_visit_prep_items = row_count;

  update public.cycle_overrides
     set deleted_at = p_now,
         updated_at = greatest(updated_at, p_now),
         excluded_from_average = false,
         manual_start = false,
         note_id = null
   where profile_id = p_profile_id
     and deleted_at is null;
  get diagnostics v_cycle_overrides = row_count;

  -- Issue #130: the profile's merge-disclosure rows are HARD-deleted (the
  -- one table here without a tombstone): a disclosed discard's retained
  -- note text is health content with no meaning once the profile content it
  -- describes is wiped, and both callers (delete_profile_data and
  -- delete_account_data, via tombstone_profile_content) tombstone rather
  -- than hard-delete the profile itself -- so the profiles FK cascade
  -- never fires here and this explicit delete is the ONLY removal path.
  -- Scoped to the whole profile, exactly like every sibling step: this
  -- function is only ever called for a profile the caller is authorized to
  -- wipe (owned-profile account deletion, or the profile's own purge).
  delete from public.day_entry_merge_events
   where profile_id = p_profile_id;
  get diagnostics v_day_entry_merge_events = row_count;

  return jsonb_build_object(
    'day_entries', v_day_entries,
    'observations', v_observations,
    'care_notes', v_care_notes,
    'visit_prep_items', v_visit_prep_items,
    'cycle_overrides', v_cycle_overrides,
    'day_entry_merge_events', v_day_entry_merge_events
  );
end;
$$;

comment on function public.tombstone_profile_content(text, timestamptz) is
  'Issue #522: tombstones (deleted_at set, payload cleared to each table''s '
  'own CHECK-required shape) every live day_entries/observations/care_notes/ '
  'visit_prep_items/cycle_overrides row for one profile, bumping '
  'server_version so the tombstone propagates via the ordinary incremental '
  'pull - shared by delete_profile_data() and delete_account_data() so both '
  'purge paths tombstone content identically. Takes no caller-authority '
  'check of its own; callable only from a SECURITY DEFINER function that '
  'has already authorized p_profile_id (no EXECUTE grant to any client-facing '
  'role - see this migration''s footer).';

revoke all on function public.tombstone_profile_content(text, timestamptz) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 7. enforce_retention(): re-emitted from 20260915200000_nightly_retention_job.sql
--    (unchanged since) with the 30-day day_entry_merge_events purge step,
--    its counter, its returned-count key, and the scan index above
--    (header item 4).
-- ---------------------------------------------------------------------------

create or replace function public.enforce_retention() returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Per-statement row cap and per-table iteration cap (see this migration's
  -- header): bounds a single run to at most 25,000 deleted rows per table,
  -- so a large backlog is worked off over several nightly runs instead of
  -- one run holding a table lock for an unbounded scan.
  v_batch_size constant integer := 500;
  v_max_iterations constant integer := 50;
  v_iterations integer;
  v_rows bigint;
  v_notification_outbox_deleted bigint := 0;
  v_day_entries_deleted bigint := 0;
  v_day_entry_history_deleted bigint := 0;
  v_feedback_tickets_deleted bigint := 0;
  v_day_entry_merge_events_deleted bigint := 0;
  -- Coordinator review of PR #705, blocking finding 3: a table's purge
  -- failing every night used to be invisible (a NOTICE server logs
  -- typically discard). Every exception handler below now also raises a
  -- WARNING (surfaces in cron job run history/logs) and records the
  -- failure here, keyed by table -- surfaced in the returned jsonb only
  -- when at least one table actually failed (see the `return` statement),
  -- so a healthy run's result carries no `errors` key at all.
  v_errors jsonb := '{}'::jsonb;
begin
  -- notification_outbox: sent_at older than 30 days (see header -- no
  -- sync-pull contract at all, this table is never read by any client).
  begin
    v_iterations := 0;
    loop
      delete from public.notification_outbox
       where id in (
         select id from public.notification_outbox
          where sent_at is not null
            and sent_at < now() - interval '30 days'
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_notification_outbox_deleted := v_notification_outbox_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: notification_outbox purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('notification_outbox', sqlerrm);
  end;

  -- day_entries tombstones: deleted_at older than 180 days (see header --
  -- tied to kSyncFullPullInterval, a wide multiple of the 24h full-reconcile
  -- cadence so no realistically-offline client can miss the deletion).
  begin
    v_iterations := 0;
    loop
      delete from public.day_entries
       where id in (
         select id from public.day_entries
          where deleted_at is not null
            and deleted_at < now() - interval '180 days'
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_day_entries_deleted := v_day_entries_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: day_entries tombstone purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('day_entries_tombstones', sqlerrm);
  end;

  -- day_entry_history: changed_at older than 90 days, per Issue #170's own
  -- proposal -- guarded because #170 has not landed as of this migration
  -- (no public.day_entry_history table exists yet). Silently no-ops until
  -- that table exists, then enforces automatically with no further
  -- migration (see header).
  begin
    if to_regclass('public.day_entry_history') is not null then
      v_iterations := 0;
      loop
        execute format(
          'delete from public.day_entry_history where id in ('
          || 'select id from public.day_entry_history'
          || ' where changed_at < now() - interval ''90 days'''
          || ' limit %s)',
          v_batch_size
        );
        get diagnostics v_rows = row_count;
        v_day_entry_history_deleted := v_day_entry_history_deleted + v_rows;
        v_iterations := v_iterations + 1;
        exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
      end loop;
    end if;
  exception
    when others then
      raise warning 'enforce_retention: day_entry_history purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('day_entry_history', sqlerrm);
  end;

  -- feedback_tickets: resolved, updated_at older than 1 year, AND no
  -- attachments (Coordinator review of PR #705, blocking finding 2 -- see
  -- this migration's header: SQL cannot remove the Storage objects
  -- attachment_paths point at, so a ticket that still references one is
  -- left untouched rather than orphaning that object forever).
  -- feedback_replies cascades from feedback_tickets (on delete cascade).
  begin
    v_iterations := 0;
    loop
      delete from public.feedback_tickets
       where id in (
         select id from public.feedback_tickets
          where status = 'resolved'
            and updated_at < now() - interval '1 year'
            and cardinality(attachment_paths) = 0
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_feedback_tickets_deleted := v_feedback_tickets_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: feedback_tickets purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('feedback_tickets', sqlerrm);
  end;

  -- day_entry_merge_events: created_at older than 30 days (Issue #130's
  -- recovery window -- see this function's updated comment and the table's
  -- own migration header). The purge is a hard DELETE: these rows carry no
  -- sync-deletion contract a client depends on (a client's local copies
  -- age out of the day sheet's own 30-day display window in lockstep), and
  -- the discarded note text they retain is exactly the category of bounded
  -- health content that must not outlive its documented window. Each
  -- exception-isolated like every sibling step above.
  begin
    v_iterations := 0;
    loop
      delete from public.day_entry_merge_events
       where id in (
         select id from public.day_entry_merge_events
          where created_at < now() - interval '30 days'
          limit v_batch_size
       );
      get diagnostics v_rows = row_count;
      v_day_entry_merge_events_deleted := v_day_entry_merge_events_deleted + v_rows;
      v_iterations := v_iterations + 1;
      exit when v_rows < v_batch_size or v_iterations >= v_max_iterations;
    end loop;
  exception
    when others then
      raise warning 'enforce_retention: day_entry_merge_events purge failed: %', sqlerrm;
      v_errors := v_errors || jsonb_build_object('day_entry_merge_events', sqlerrm);
  end;

  -- Coordinator review of PR #705, blocking finding 3: `errors` is included
  -- only when v_errors actually holds at least one entry, so a healthy
  -- run's result carries no `errors` key at all (pinned by a pgTAP
  -- assertion) and cron job history still shows the WARNING either way.
  return jsonb_build_object(
    'notification_outbox', v_notification_outbox_deleted,
    'day_entries_tombstones', v_day_entries_deleted,
    'day_entry_history', v_day_entry_history_deleted,
    'feedback_tickets', v_feedback_tickets_deleted,
    'day_entry_merge_events', v_day_entry_merge_events_deleted
  ) || case when v_errors = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('errors', v_errors) end;
end;
$$;

comment on function public.enforce_retention() is
  'Issue #263: nightly retention purge for notification_outbox (sent_at > '
  '30 days), day_entries tombstones (deleted_at > 180 days -- tied to '
  'kSyncFullPullInterval, see this migration''s header), day_entry_history '
  '(changed_at > 90 days, guarded no-op until Issue #170 lands), and '
  'resolved feedback_tickets with no attachments (updated_at > 1 year and '
  'cardinality(attachment_paths) = 0 -- Coordinator review of PR #705: a '
  'ticket still referencing a Storage object is left alone, since SQL '
  'cannot remove that object and a hard delete here would orphan it '
  'forever). Each table purges in its own exception-isolated sub-block, in '
  'bounded batches (500 rows/statement, up to 50 iterations), so one '
  'table''s failure or an oversized backlog can never block the others or '
  'hold a lock indefinitely. A failed sub-block raises a WARNING (not a '
  'NOTICE) and is recorded in the returned jsonb under an `errors` key '
  '(table -> sqlerrm), present only when at least one table actually '
  'failed, so a failing purge is visible in cron job history instead of '
  'silent. SECURITY DEFINER; callable only by cron or service_role.';

revoke all on function public.enforce_retention() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 8. reconcile_realtime_publication(): re-emitted from
--    20260909200000_prediction_connections.sql (unchanged since) with
--    day_entry_merge_events on the must-never-publish list (header item 5).
-- ---------------------------------------------------------------------------

create or replace function public.reconcile_realtime_publication()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signals_col_list name[] := array['profile_id', 'updated_at']::name[];
  v_current_cols name[];
  v_all_tables boolean;
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception
      'supabase_realtime publication does not exist -- expected to already '
      'exist, created by the Supabase platform''s own base migrations';
  end if;

  -- Never let day_entries or profiles be published, in any form. Checks
  -- *and corrects* rather than only checking membership, so a whole-row
  -- publication left behind by Supabase Studio's "Enable Realtime" toggle
  -- (or a future edit that widens this migration) is actively reverted
  -- instead of being treated as already-correct and skipped.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entries'
  ) then
    alter publication supabase_realtime drop table public.day_entries;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profiles'
  ) then
    alter publication supabase_realtime drop table public.profiles;
  end if;

  -- Issue #240 review finding: observations joins day_entries/profiles on
  -- this must-never-be-published list -- it carries the same category of
  -- sensitive per-entry content (symptom/option detail) that day_entries
  -- was excluded for, and nothing about this table was ever meant to reach
  -- the client any way other than the existing sync_signals wake-signal +
  -- an authenticated sync_push/read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'observations'
  ) then
    alter publication supabase_realtime drop table public.observations;
  end if;

  -- Issue #167: import_jobs joins this must-never-be-published list --
  -- no health content, but a per-user tracking table with no reason to
  -- reach the client any way other than an authenticated read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'import_jobs'
  ) then
    alter publication supabase_realtime drop table public.import_jobs;
  end if;

  -- Issue #188: profile_modes and cycle_overrides join this
  -- must-never-be-published list -- a profile's reproductive-life-stage
  -- state and cycle corrections are exactly the category of sensitive
  -- content day_entries/profiles/observations were excluded for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profile_modes'
  ) then
    alter publication supabase_realtime drop table public.profile_modes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'cycle_overrides'
  ) then
    alter publication supabase_realtime drop table public.cycle_overrides;
  end if;

  -- Issue #128: care_notes and visit_prep_items join this
  -- must-never-be-published list -- standing care notes and visit-prep
  -- checklists are exactly the category of sensitive health content
  -- about a minor that day_entries/profiles/observations were excluded
  -- for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'care_notes'
  ) then
    alter publication supabase_realtime drop table public.care_notes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'visit_prep_items'
  ) then
    alter publication supabase_realtime drop table public.visit_prep_items;
  end if;

  -- Issue #151: the prediction tables join the never-publish list --
  -- token hashes (prediction_connections) and the derived payload
  -- (prediction_projections) must never cross the websocket.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_connections'
  ) then
    alter publication supabase_realtime drop table public.prediction_connections;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_projections'
  ) then
    alter publication supabase_realtime drop table public.prediction_projections;
  end if;

  -- Issue #130: day_entry_merge_events joins the never-publish list -- a
  -- merge-disclosure row retains the LOSING guardian's discarded note text
  -- (health content about a minor), exactly the category of payload that
  -- must never cross the websocket. Co-guardians still learn a merge
  -- happened promptly via the table's touch_sync_signal() trigger (a
  -- content-free sync_signals wake), and re-read through the RLS-checked
  -- pull -- the same posture every content table here already uses.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entry_merge_events'
  ) then
    alter publication supabase_realtime drop table public.day_entry_merge_events;
  end if;

  -- If `supabase_realtime` was ever switched to FOR ALL TABLES (which would
  -- silently republish day_entries/profiles/observations/import_jobs
  -- whole-row regardless of the per-table checks above), that is a
  -- platform-level misconfiguration this function cannot safely undo (it
  -- would also drop unrelated tables this repo does not own). Fail loudly
  -- instead of pretending the guard above was sufficient.
  select puballtables into v_all_tables
    from pg_catalog.pg_publication
   where pubname = 'supabase_realtime';

  if v_all_tables then
    raise exception
      'supabase_realtime is FOR ALL TABLES -- this publishes public.profiles, '
      'public.day_entries, public.observations, public.import_jobs, '
      'public.profile_modes, public.cycle_overrides, public.care_notes, public.visit_prep_items, '
      'public.prediction_connections, public.prediction_projections, and '
      'public.day_entry_merge_events whole-row and must be '
      'fixed manually before this migration can proceed (see the migration '
      'header comment)';
  end if;

  -- public.sync_signals: the only table this app publishes to Realtime.
  -- Correct both membership and the published column list -- not just
  -- membership -- so a Studio toggle (which would publish every column) is
  -- detected and repaired rather than skipped as "already there".
  select attnames
    into v_current_cols
    from pg_catalog.pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'sync_signals';

  if v_current_cols is null then
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  elsif (select array_agg(c order by c) from unnest(v_current_cols) as c)
        is distinct from (
          select array_agg(c order by c) from unnest(v_signals_col_list) as c
        ) then
    -- Column set drifted from what this function intends (e.g. a Studio
    -- toggle re-added the table whole-row) -- correct it rather than skip.
    alter publication supabase_realtime drop table public.sync_signals;
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  end if;
end;
$$;

comment on function public.reconcile_realtime_publication() is
  'Ensures supabase_realtime publishes only public.sync_signals (with '
  'exactly profile_id, updated_at) and never public.profiles/day_entries/'
  'observations/profile_modes/cycle_overrides/care_notes/visit_prep_items/'
  'prediction_connections/prediction_projections/day_entry_merge_events '
  '(Issue #240 added observations to this list; Issue #188 added the two '
  'mode tables; Issue #128 added care_notes/visit_prep_items; Issue #151 '
  'added the two prediction tables; Issue #130 added '
  'day_entry_merge_events), drift (e.g. a Studio "Enable Realtime" toggle) '
  'rather than skipping an already-published table (Issue #77 P1 fix). '
  'Not an API function -- runs only from migrations and from pgTAP (as an '
  'unrestricted role); execute is revoked from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;select public.reconcile_realtime_publication();
