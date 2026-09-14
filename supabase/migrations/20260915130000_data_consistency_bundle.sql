-- Migration: 20260915130000_data_consistency_bundle.sql
-- Bundle of three data-consistency fixes:
--
--   1. Issue #303 (P2, epic: backend-data): `flow`'s allowed values were
--      hand-kept in three places -- the `day_entries_flow_check` table
--      CHECK, `sync_push`'s inline `v_flow not in (...)` allow-list, and
--      the Dart `FlowLevel` enum -- with nothing that failed if a future
--      addition (like #247's `super_heavy`/`not_bleeding`) missed one of
--      them (finding D-10, called out but deliberately deferred by
--      `20260908200000_flow_model.sql`'s own header). This migration
--      collapses the two SQL copies into one: a new IMMUTABLE
--      `public.is_valid_flow_level(text)` function is the single literal
--      allow-list, called by both a new `public.flow_level` domain's own
--      CHECK and (replacing the hand-kept list) `sync_push`'s validation
--      and `bulk_import_entries`'s set-based rejection CASE.
--      `day_entries.flow` is retyped from `text` to the domain, and the
--      now-redundant `day_entries_flow_check` table CHECK is dropped --
--      the domain is the single place the allow-list is declared in SQL.
--      The Dart enum stays the client mirror (issue's own proposal); its
--      own guard test lives in `test/domain/models/flow_level_test.dart`,
--      pinned against the identical literal list this migration's
--      `is_valid_flow_level()` uses, and `supabase/tests/
--      flow_level_domain_test.sql` pins the SQL side of the same list --
--      together they are the "can't drift apart silently" guard the
--      issue asks for (neither is derived from the other, but a future
--      edit to either literal list without the other breaks one suite or
--      the other).
--
--      PRODUCTION SAFETY (day_entries is a live table): retyping a column
--      from `text` to a domain whose base type is also `text` is
--      binary-coercible -- Postgres does not rewrite the table's heap for
--      this ALTER (no `USING` clause is given, and none is needed: every
--      value assignable to `text` is assignable to a text-based domain,
--      subject to the domain's own CHECK). It does still take an
--      ACCESS EXCLUSIVE lock and scan every existing row once to verify
--      the new domain's CHECK against it, exactly as adding a new table
--      CHECK constraint would. That scan cannot fail here: the domain's
--      `is_valid_flow_level()` allow-list is a strict superset containing
--      every value `day_entries_flow_check` already accepted (the exact
--      same seven-value list `20260908200000_flow_model.sql` last
--      widened it to), so no existing row -- however old -- can violate
--      it. The old table CHECK is dropped first (same statement window),
--      so at no point are both constraints validated redundantly.
--
--   2. Issue #292 (P3, epic: privacy-compliance): `public.settings` (a
--      per-user key/value table, provisioned but not yet written by the
--      app today per issue #101) was in neither the server-side
--      right-of-access export (`export_account_data()`) nor the local
--      JSON export -- a gap that is empty in practice today but becomes a
--      real right-of-access gap the moment the app starts writing to the
--      table. `export_account_data()` is `create or replace`d (carrying
--      its `20260915070000_export_account_data_tracking_preferences.sql`
--      body verbatim, per Migration Flow item 7/8, other than the one new
--      `settings` section below) to add a `settings` top-level key: every
--      row where `user_id = auth.uid()`, `key`/`value`/`updated_at` only
--      (never `server_version` -- sync bookkeeping stays out of the
--      export document, matching every other table's own projection
--      here). `schema_version` stays 1: an additive top-level key, not a
--      breaking change to an existing one (the `20260908190000_
--      bulk_import.sql` `import_jobs` precedent). The local JSON export
--      (`lib/domain/export/account_export.dart`) needs no code change of
--      its own to pick this up -- `mergeAccountExport` already nests
--      the server's whole document verbatim under `server`, so the new
--      `settings` key reaches the exported file the moment the server
--      side carries it; that file's own doc comment is updated to say so
--      explicitly. `supabase/tests/export_account_data_test.sql` gains
--      settings fixtures/assertions (including a same-key-different-user
--      case: A and B both write a `theme` setting with different values,
--      proving the per-user scoping distinguishes them even though the
--      key collides), and a new guard test enumerates every
--      `information_schema.columns` row with `column_name = 'user_id'`
--      under `public` against a hardcoded exported/excluded-with-reason
--      list, so a future user-keyed table cannot silently land outside
--      this document -- the test itself fails the moment a new one
--      appears until it is triaged into one bucket or the other.
--
-- Neither fix touches RLS, grants, or any authorization path.

-- ---------------------------------------------------------------------------
-- Issue #303, part 1: the single source-of-truth allow-list and domain.
-- ---------------------------------------------------------------------------

create function public.is_valid_flow_level(p_flow text)
returns boolean
language sql
immutable
as $$
  select p_flow in ('none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy');
$$;

comment on function public.is_valid_flow_level(text) is
  'Issue #303: the single SQL source of truth for flow''s allowed values -- '
  'called by the flow_level domain''s own CHECK below, by sync_push''s '
  'per-row validation, and by bulk_import_entries''s set-based rejection '
  'CASE, so the seven-value list (Issue #247''s super_heavy/not_bleeding '
  'included) is declared exactly once in SQL. A plain boolean predicate, '
  'never a domain cast, so bulk_import_entries''s set-based CASE can keep '
  'rejecting one bad row instead of aborting the whole batch on a '
  'check_violation.';

create domain public.flow_level as text
  check (public.is_valid_flow_level(value));

comment on domain public.flow_level is
  'Issue #303: the day_entries.flow allow-list as a SQL domain, backed by '
  'public.is_valid_flow_level() -- collapses the table CHECK and '
  'sync_push''s inline allow-list into one declaration. The Dart '
  '`FlowLevel` enum (lib/domain/models/flow_level.dart) stays the client '
  'mirror; test/domain/models/flow_level_test.dart and supabase/tests/'
  'flow_level_domain_test.sql each pin the identical literal list so the '
  'two sides cannot drift apart silently.';

-- Retype the live column (see this migration's header for the production
-- safety argument: binary-coercible, no rewrite, and the domain's
-- allow-list is a superset of every value the old CHECK ever accepted, so
-- the mandatory revalidation scan cannot fail on existing data). The old
-- table CHECK is dropped first so the column carries the allow-list in
-- exactly one place once this statement completes.
alter table public.day_entries
  drop constraint day_entries_flow_check;

-- Postgres refuses ALTER COLUMN ... TYPE outright when a trigger's own WHEN
-- clause (not merely its function body -- that's fine) references the
-- column being retyped ("cannot alter type of a column used in a trigger
-- definition"): day_entries_after_update_enqueue_alerts
-- (20260906220000_notification_outbox.sql) has `new.flow is distinct from
-- old.flow` in its WHEN clause. Drop and recreate it, identically, around
-- the retype -- no other trigger, index, or view depends on this column's
-- type (every other flow reference lives inside a function body, which
-- Postgres does not need to re-bind).
drop trigger day_entries_after_update_enqueue_alerts on public.day_entries;

alter table public.day_entries
  alter column flow type public.flow_level;

create trigger day_entries_after_update_enqueue_alerts
  after update on public.day_entries
  for each row
  when (
    new.local_date is distinct from old.local_date
    or new.flow is distinct from old.flow
    or new.tags is distinct from old.tags
    or new.note is distinct from old.note
    or new.deleted_at is distinct from old.deleted_at
  )
  execute function public.enqueue_caregiver_alerts();

-- ---------------------------------------------------------------------------
-- Issue #303, part 2: sync_push re-emitted from
-- 20260915000000_profile_tracking_preferences.sql's body (main's current
-- definition), unchanged except the flow validation now calls
-- is_valid_flow_level() instead of a hand-kept allow-list. Same 7-argument
-- signature, so a plain create-or-replace applies (no overload fork).
-- ---------------------------------------------------------------------------

create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb,
  p_profile_modes jsonb default '[]'::jsonb,
  p_cycle_overrides jsonb default '[]'::jsonb,
  p_care_notes jsonb default '[]'::jsonb,
  p_visit_prep_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c_max_rows constant integer := 500;
  c_max_observations_per_day constant integer := 200;
  -- Issue #564: total-row cap across all seven payload arrays combined.
  -- 3500 (= 7 * c_max_rows) is a no-op today, not a real tightening yet -
  -- see this migration's header for why (the Dart sync engine legitimately
  -- fills all seven tables to 500 rows each on a first sync or a
  -- post-Clue-import push; a lower cap would reject that call outright and
  -- the client would retry it forever). A stricter combined cap needs a
  -- client-side batch-size change first.
  c_max_total_rows constant integer := 3500;
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
     + jsonb_array_length(p_visit_prep_items) > c_max_total_rows then
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
        -- on this column at all (20260913017000_day_entries_column_grants.sql),
        -- so leaving this assignment in would make this statement fail
        -- outright for every caller (sync_push is security invoker).
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
  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$$;

comment on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, observations, profile_modes, '
  'cycle_overrides, care_notes, and visit_prep_items under guardian role '
  'permissions with authoritative attribution stamping. See prior '
  'migrations'' function comments (20260906200000 onward) for the full '
  'per-table history; this comment covers only what '
  '20260913016000_sync_push_hardening.sql changed, plus Issue #303 below. '
  'Issue #518: is_minor on '
  'the profiles UPDATE path now carries the same v_row ? ''key'' '
  'containment guard as birth_year/relationship/mode, so an old client or '
  'partial-row writer omitting the key never un-marks a minor''s profile. '
  'Issue #521: the per-user advisory lock uses hashtextextended(uid::text, '
  '0) (int8) instead of hashtext(uid::text) (int4, collision-prone). Issue '
  '#524: a live observation push is rejected outright when its day_entry_id '
  'is already tombstoned (v_deleted_at is null but the parent day entry''s '
  'deleted_at is not) - the companion to the cascade trigger''s own '
  'greatest() LWW guard. Issue #562: the day_entries UPDATE no longer '
  'assigns profile_id (always a no-op - the immutability check above it '
  'already proved equality), matching the revoked column grant. Issue '
  '#564: a combined 3500-row cap (a no-op today - see the migration '
  'header) applies across all seven payload arrays (on top of, not '
  'instead of, each array''s own 500-row cap), and the '
  'profile_guardians role lookup for day_entries/observations/'
  'profile_modes/cycle_overrides/care_notes/visit_prep_items is computed '
  'ONCE up front via a jsonb_object_agg map keyed by profile_id, rather '
  'than once per row. Issue #566: every one of the seven loops rejects (as '
  'a per-row rejection, not a batch failure) any row whose updated_at is '
  'more than five minutes ahead of the server''s now(). Issue #303: '
  'v_flow''s validation now calls public.is_valid_flow_level() (the same '
  'predicate the new flow_level domain''s own CHECK calls) instead of a '
  'hand-kept allow-list, so the seven-value set is declared exactly once '
  'in SQL -- day_entries.flow is now typed as that domain too.';

revoke execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Issue #303, part 3: bulk_import_entries re-emitted from
-- 20260915020000_bulk_import_pms_tombstone.sql's body (main's current
-- definition), unchanged except its set-based rejection CASE now calls
-- is_valid_flow_level() instead of a hand-kept allow-list. A plain boolean
-- predicate (never a domain cast), so a bad row is still rejected
-- individually rather than aborting the whole batch on a check_violation
-- (see this migration's header). Same 2-argument signature.
-- ---------------------------------------------------------------------------

create or replace function public.bulk_import_entries(
  p_import_id uuid,
  p_rows jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  c_max_rows constant integer := 2000;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  -- Issue #167: source/import_id are deliberately NOT in this allowlist --
  -- they come from the job record, never the payload (see this
  -- migration's header).
  c_row_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'source_id', 'updated_at', 'deleted_at'];

  v_uid uuid := (select auth.uid());
  v_job public.import_jobs%rowtype;
  v_inserted integer := 0;
  v_updated integer := 0;
  v_revived integer := 0;
  v_rejected jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'bulk_import_entries requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'p_rows must be a JSON array'
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) > c_max_rows then
    raise exception 'p_rows exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;

  select * into v_job from public.import_jobs where id = p_import_id for update;
  if not found then
    raise exception 'import job % does not exist', p_import_id
      using errcode = 'invalid_parameter_value';
  end if;

  -- Guardian check: the caller must be an accepted guardian of the job's
  -- profile with a *writing* role -- mirrors sync_push's day_entries check
  -- (v_caller_role is null or = 'viewer' => reject) via the same
  -- is_guardian_with_roles() helper the ownership-transfer RPCs use.
  -- Review fix: this must run BEFORE the status check below -- an
  -- unauthorised caller must learn nothing about a job's status (or, via
  -- the exception message shape, its existence beyond "some row with this
  -- id exists"), so a non-guardian probing a real job id gets the same
  -- 42501 regardless of whether that job is pending or already
  -- completed/failed.
  if not public.is_guardian_with_roles(
    v_job.profile_id, v_uid, array['primary_guardian', 'co_parent', 'caregiver']
  ) then
    raise exception 'caller is not authorized to import entries for profile %', v_job.profile_id
      using errcode = 'insufficient_privilege';
  end if;

  if v_job.status in ('completed', 'failed') then
    raise exception 'import job % is already %', p_import_id, v_job.status
      using errcode = 'invalid_parameter_value';
  end if;

  if jsonb_array_length(p_rows) = 0 then
    return jsonb_build_object('inserted', 0, 'updated', 0, 'revived', 0, 'rejected', '[]'::jsonb);
  end if;

  -- Issue #167: skip touch_sync_signal()/enqueue_caregiver_alerts()'s
  -- per-row work for the duration of the write below (this RPC touches
  -- sync_signals itself, once, at the end; a bulk import never pages a
  -- guardian) -- transaction-local, per the same transaction-local-GUC
  -- pattern the ownership-transfer RPC set in
  -- 20260906180000_ownership_transfer_rpcs.sql uses.
  --
  -- Review fix: this function does NOT (and cannot) raise its own
  -- statement_timeout. `set local statement_timeout = '60s'` used to sit
  -- here, but `statement_timeout` is sampled once when a statement starts
  -- and a mid-statement `set local` on it is a documented Postgres no-op --
  -- it has no effect on the currently-executing statement, and there is no
  -- second statement in this call for it to apply to before the
  -- transaction (and the GUC's `local` scope) ends. So this call has
  -- always run under whatever statement_timeout the caller's role already
  -- had -- the platform's ordinary 8s timeout for `authenticated` -- not a
  -- 60s allowance. Every claim of a 60s bound in this migration's comments
  -- was wrong; see the pgTAP 2000-row latency case, which now measures
  -- against that real 8s ceiling instead.
  perform set_config('lunarlog.bulk_import', 'on', true);

  begin
    with parsed as (
      -- One SQL expression over the whole batch, not a per-row plpgsql
      -- loop (see this migration's header) -- ordinality gives each row
      -- its 0-based position for the `rejected` summary.
      select
        ord.idx - 1 as row_index,
        ord.value as raw,
        ord.value ->> 'id' as id,
        ord.value ->> 'profile_id' as row_profile_id,
        ord.value ->> 'local_date' as local_date_text,
        coalesce(ord.value ->> 'tz', 'UTC') as tz,
        ord.value ->> 'source_id' as source_id,
        ord.value ->> 'updated_at' as updated_at_text,
        ord.value ->> 'deleted_at' as deleted_at_text,
        -- Review fix: a tombstone row carries no payload, mirroring
        -- sync_push's identical day_entries branch
        -- (20260908180000_timezone_contract.sql) -- forced here
        -- unconditionally rather than validating whatever flow/tags/note
        -- keys a tombstone row happens to carry, so a client that sends a
        -- tombstone with a stale (non-empty) payload is not rejected for
        -- it; the payload is simply discarded, same as a live row's would
        -- be validated.
        case when (ord.value ->> 'deleted_at') is not null then 'none'
          else coalesce(ord.value ->> 'flow', 'none') end as flow,
        case when (ord.value ->> 'deleted_at') is not null then '[]'::jsonb
          else coalesce(ord.value -> 'tags', '[]'::jsonb) end as tags,
        case when (ord.value ->> 'deleted_at') is not null then null
          else ord.value ->> 'note' end as note
      from jsonb_array_elements(p_rows) with ordinality as ord(value, idx)
    ),
    validated as (
      select
        p.*,
        public.bulk_import_safe_date(p.local_date_text) as parsed_local_date,
        public.bulk_import_safe_timestamptz(p.updated_at_text) as parsed_updated_at,
        public.bulk_import_safe_timestamptz(p.deleted_at_text) as parsed_deleted_at,
        case
          when jsonb_typeof(p.raw) <> 'object' then 'row is not an object'
          when exists (select 1 from jsonb_object_keys(p.raw) k where k <> all (c_row_keys))
            then 'row carries an unknown key'
          when p.id is null or p.id !~ c_ulid then 'id is not a ULID'
          when p.row_profile_id is null or p.row_profile_id !~ c_ulid then 'profile_id is not a ULID'
          when p.row_profile_id is distinct from v_job.profile_id then 'profile_id does not match import job'
          when public.bulk_import_safe_date(p.local_date_text) is null then 'local_date is not an ISO calendar date'
          when char_length(p.tz) > 64 then 'tz exceeds 64 characters'
          -- Review fix: a syntactically-plausible but unrecognized zone
          -- (e.g. 'Mars/Cydonia') previously passed straight through to
          -- the day_entries CHECK constraint added by
          -- 20260908180000_timezone_contract.sql, which would abort the
          -- whole batch's write statement (caught only by the
          -- unique_violation backstop's cousin, a check_violation, not
          -- handled at all) instead of rejecting just this row.
          when not public.is_valid_timezone(p.tz) then 'tz is not a known time zone'
          -- Issue #303: routed through the same public.is_valid_flow_level()
          -- the flow_level domain's own CHECK and sync_push's validation
          -- now share, instead of a third hand-kept copy of the
          -- allow-list. Still a plain boolean predicate (never a domain
          -- cast), so this set-based CASE keeps rejecting one bad row
          -- instead of aborting the whole batch on a check_violation --
          -- see this migration's header.
          when not public.is_valid_flow_level(p.flow) then 'flow is not a known level'
          when not public.is_valid_tags_array(p.tags) then 'tags failed validation'
          when p.note is not null and char_length(p.note) > 2000 then 'note exceeds 2000 characters'
          when p.source_id is not null and char_length(p.source_id) > 128 then 'source_id exceeds 128 characters'
          when p.updated_at_text is null then 'updated_at is required'
          when public.bulk_import_safe_timestamptz(p.updated_at_text) is null then 'updated_at is not a valid timestamp'
          when p.deleted_at_text is not null and public.bulk_import_safe_timestamptz(p.deleted_at_text) is null
            then 'deleted_at is not a valid timestamp'
          else null
        end as reason
      from parsed p
    ),
    by_id as (
      -- Review fix: resolve every still-valid row against an existing
      -- day_entries id FIRST, regardless of provenance -- mirrors
      -- sync_push's own id-first resolution and is what makes a retry of
      -- an already-landed chunk idempotent: a row whose id already exists
      -- (from a prior successful chunk of this same job, or any other
      -- write) is updated in place below rather than re-attempting an
      -- insert that would collide on the primary key.
      select
        v.*,
        d.id as existing_by_id_id,
        d.profile_id as existing_by_id_profile_id,
        d.updated_at as existing_by_id_updated_at,
        d.deleted_at as existing_by_id_deleted_at
      from validated v
      left join public.day_entries d on d.id = v.id
      where v.reason is null
    ),
    collision_checked as (
      -- Review fix (decision: no in-RPC resolver in this PR -- the client
      -- surfaces the conflict): a row that would land LIVE is rejected
      -- outright if (profile_id, local_date) already belongs to a
      -- different LIVE row under different provenance (e.g. a manual
      -- entry, or a different import's row) -- sync_push's own same-date
      -- merge algorithm is deliberately not reimplemented here. Exempt:
      -- only a tombstone (nothing is landing live). An update-by-id row
      -- is NOT exempt -- day_entries_live_profile_date_uq
      -- (20260904010000_multi_guardian_schema.sql) is a real partial
      -- unique index on (profile_id, local_date) where deleted_at is
      -- null, so an update that moves an existing row onto an
      -- already-occupied live date would otherwise raise a genuine
      -- unique_violation (23505) from the UPDATE statement itself and
      -- abort the whole chunk via the backstop below -- exactly the
      -- per-row-not-per-chunk failure this migration exists to prevent.
      -- `d.id <> b.id` correctly excludes the row's own currently-stored
      -- self when its date is not actually changing.
      --
      -- Review fix (blocking): compare only (source, source_id), never
      -- import_id. import_id is a job-scoped surrogate, not part of a
      -- row's provenance identity -- re-importing the same source_id under
      -- a brand-new import_jobs row (a legitimate resume/retry with a
      -- fresh job id) previously compared as "different provenance" purely
      -- because the two jobs' ids differed, rejecting every row of an
      -- otherwise-idempotent re-import. (source, source_id) alone is what
      -- actually identifies "the same imported thing" -- see
      -- import_provenance_test.sql's partial unique index on exactly that
      -- pair.
      select
        b.*,
        case
          when b.parsed_deleted_at is not null then null
          when exists (
            select 1 from public.day_entries d
             where d.profile_id = b.row_profile_id
               and d.local_date = b.parsed_local_date
               and d.deleted_at is null
               and d.id <> b.id
               and (d.source, d.source_id)
                   is distinct from (v_job.source, b.source_id)
          ) then 'date already has a live entry'
          else null
        end as collision_reason
      from by_id b
    ),
    reasoned as (
      select
        c.*,
        coalesce(
          c.collision_reason,
          -- Review fix (blocking): a row whose id already exists in
          -- day_entries but on a DIFFERENT profile is rejected outright,
          -- not silently dropped. Previously by_id's `d.id = v.id` join
          -- ignores profile_id, so a cross-profile id match still set
          -- existing_by_id_id and the row was routed into update_rows --
          -- but the actual UPDATE statement's `d.profile_id =
          -- u.row_profile_id` guard (day entries never move between
          -- profiles, mirroring sync_push) then matched zero rows,
          -- discarding the row without writing it, counting it as
          -- inserted/updated/revived, or rejecting it. It never reaches
          -- insert_rows either (existing_by_id_id is not null), so it
          -- vanished from the response entirely.
          case
            when c.existing_by_id_id is not null
              and c.existing_by_id_profile_id is distinct from c.row_profile_id
              then 'id belongs to another profile'
            else null
          end,
          -- Review fix: a row not already resolved by id needs a
          -- source_id to reach an idempotent write path at all -- the
          -- `on conflict (profile_id, source, source_id)` arbiter below
          -- is the only other route to one, and it requires source_id is
          -- not null. Without this, a brand-new row with no source_id
          -- would insert successfully once and then hit the day_entries
          -- primary key on every subsequent retry of the same chunk,
          -- aborting the whole batch -- the idempotency bug this
          -- restructuring exists to close. Documented as a hard
          -- requirement in BulkImportRow (lib/domain/import/bulk_importer.dart).
          case
            when c.existing_by_id_id is null and c.source_id is null
              then 'source_id is required for idempotent import'
            else null
          end
        ) as combined_reason
      from collision_checked c
    ),
    source_ranked as (
      -- Within-batch duplicate resolution (this migration's header): two
      -- rows sharing (profile_id, source, source_id) cannot both be
      -- affected by one ON CONFLICT DO UPDATE (21000), and would collide
      -- with each other's write regardless of which path either takes --
      -- the later row (by position) wins, the earlier is rejected as
      -- superseded. A null source_id gets its own singleton partition
      -- (never superseded here -- see the source_id-required rejection
      -- above, which already removes every row that would otherwise need
      -- one).
      select
        r.*,
        row_number() over (
          partition by coalesce(r.source_id, 'row:' || r.row_index::text)
          order by r.row_index desc
        ) as source_dupe_rank
      from reasoned r
      where r.combined_reason is null
    ),
    date_ranked as (
      -- Review fix: two rows in the same batch sharing (profile_id,
      -- local_date) under different source_id both landing live is a
      -- second, independent within-batch conflict (decision: no in-RPC
      -- resolver, same as the live-row collision check above) -- the
      -- earlier row (by position) wins, the later is rejected. Tombstones
      -- never contest a date (nothing is landing live), so they always
      -- pass through with rank 1.
      --
      -- Review fix (blocking): the row_number() window is partitioned by
      -- (profile_id, local_date, is-a-tombstone) rather than just
      -- (profile_id, local_date) -- a window function still evaluates over
      -- every row in its partition even when the CASE above discards a
      -- tombstone's computed value and hardcodes 1 instead, so a tombstone
      -- sharing a live row's date previously occupied rank 1 in the
      -- shared partition and pushed the live row (or an earlier live row)
      -- to rank 2+, rejecting it as a spurious "duplicate date" even
      -- though a tombstone never actually contests the date. Splitting
      -- tombstones into their own partition bucket means a live row's
      -- rank depends only on other live rows sharing its date, exactly as
      -- intended -- a tombstone for date D and a live row for date D in
      -- one batch now both proceed.
      select
        s.*,
        case
          when s.parsed_deleted_at is not null then 1
          else row_number() over (
            partition by s.row_profile_id, s.parsed_local_date, (s.parsed_deleted_at is not null)
            order by s.row_index asc
          )
        end as date_dupe_rank
      from source_ranked s
      where s.source_dupe_rank = 1
    ),
    to_write as (
      select d.* from date_ranked d where d.date_dupe_rank = 1
    ),
    -- -----------------------------------------------------------------
    -- Two disjoint, set-based write paths from here (review fix -- see
    -- the migration header's restructuring note):
    --   (a) update_rows: the row's id already exists in day_entries (any
    --       provenance) -- updated in place, last-writer-wins on
    --       updated_at, mirroring sync_push's own resolution. A row that
    --       loses last-writer-wins is silently skipped (not written, not
    --       counted, not rejected) -- exactly sync_push's own "declined"
    --       behaviour for a stale push.
    --   (b) insert_rows: no existing id -- source_id is guaranteed not
    --       null here (every row that would otherwise need one and lacks
    --       it was already rejected above) -- goes through the
    --       pre-existing `on conflict (profile_id, source, source_id)`
    --       upsert, which is how a tombstoned imported row gets revived.
    -- -----------------------------------------------------------------
    update_rows as (
      select
        tw.*,
        (tw.parsed_updated_at > tw.existing_by_id_updated_at
          or (tw.parsed_updated_at = tw.existing_by_id_updated_at
              and tw.parsed_deleted_at is not null
              and tw.existing_by_id_deleted_at is null)) as lww_accept
      from to_write tw
      where tw.existing_by_id_id is not null
    ),
    updated as (
      -- Review fix: apply sync_push's own `v_row ? 'key'` containment
      -- guard (20260908170000_import_provenance.sql /
      -- 20260908180000_timezone_contract.sql) to source_id/import_id here
      -- too -- `source_id` is an ordinary optional payload key (see
      -- c_row_keys above), so an update-by-id row that omits it (editing
      -- flow/tags/note only, say) must not null out the row's already-
      -- stored idempotency key. import_id is guarded by the same
      -- condition rather than its own -- it is never a payload key (it
      -- comes from p_import_id, not the row), so its only sensible update
      -- rule is "moves together with source_id": a row that isn't
      -- (re)stamping source_id has no new provenance to record either.
      update public.day_entries d set
        local_date = u.parsed_local_date,
        tz = u.tz,
        flow = u.flow,
        tags = u.tags,
        note = u.note,
        -- Issue #140 review, LLA-060: pms is not a bulk-import-carried
        -- field (it stays outside c_row_keys -- Clue and similar bulk
        -- sources have no PMS concept to import), so there is never an
        -- incoming value to apply here, only a stored one to either clear
        -- (the row is becoming a tombstone, mirroring flow's 'none'
        -- treatment above) or leave untouched (an ordinary live update).
        -- Without this, a chunk that tombstones an existing pms = true row
        -- by id violated day_entries_tombstone_pms_check -- a
        -- check_violation this function's unique_violation handler below
        -- does not catch -- aborting the WHOLE CHUNK, not just this row.
        pms = case when u.parsed_deleted_at is not null then false else d.pms end,
        source = v_job.source,
        source_id = case when u.raw ? 'source_id' then u.source_id else d.source_id end,
        import_id = case when u.raw ? 'source_id' then p_import_id else d.import_id end,
        updated_at = u.parsed_updated_at,
        deleted_at = u.parsed_deleted_at,
        last_modified_by_user_id = v_uid
      from update_rows u
      where d.id = u.id
        -- Mirrors sync_push's own "day entry cannot move between
        -- profiles" guard -- every surviving row's profile_id already
        -- equals v_job.profile_id (validated above), so this only ever
        -- excludes the cryptographically-negligible case of a ULID
        -- collision landing on a different profile's row; profile_id
        -- itself is deliberately left out of the SET list above, same as
        -- sync_push never moves it either.
        and d.profile_id = u.row_profile_id
        and u.lww_accept
      returning u.existing_by_id_deleted_at, u.parsed_deleted_at
    ),
    insert_rows as (
      select tw.* from to_write tw where tw.existing_by_id_id is null
    ),
    insert_lookup as (
      -- Pre-classify against the live table before writing, so the
      -- inserted/revived/updated split doesn't need to be
      -- reverse-engineered from RETURNING (which only ever shows the
      -- post-write row).
      select
        ir.*,
        d.id as conflict_id,
        d.deleted_at as conflict_deleted_at
      from insert_rows ir
      left join public.day_entries d
        on d.profile_id = ir.row_profile_id
       and d.source = v_job.source
       and d.source_id = ir.source_id
       and ir.source_id is not null
    ),
    upserted as (
      insert into public.day_entries (
        id, profile_id, local_date, tz, flow, tags, note,
        source, source_id, import_id,
        updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id
      )
      select
        il.id, il.row_profile_id, il.parsed_local_date, il.tz, il.flow, il.tags, il.note,
        v_job.source, il.source_id, p_import_id,
        il.parsed_updated_at, il.parsed_deleted_at, v_uid, v_uid
      from insert_lookup il
      on conflict (profile_id, source, source_id) where source_id is not null
      do update set
        local_date = excluded.local_date,
        tz = excluded.tz,
        flow = excluded.flow,
        tags = excluded.tags,
        note = excluded.note,
        -- Issue #140 review, LLA-060: same rule as the by-id UPDATE above
        -- -- pms is never an incoming value on this path either (a fresh
        -- INSERT gets the column's own `not null default false`, since
        -- pms is deliberately absent from the column list above), so a
        -- conflict that revives/updates an EXISTING row only ever clears
        -- it (becoming a tombstone) or keeps it (an ordinary live update);
        -- `public.day_entries.pms` reads the pre-update stored value, same
        -- as `excluded.<col>` reads the proposed INSERT's. Without this,
        -- the source-conflict path had the identical
        -- day_entries_tombstone_pms_check failure the by-id path did.
        pms = case when excluded.deleted_at is not null then false else public.day_entries.pms end,
        import_id = excluded.import_id,
        updated_at = excluded.updated_at,
        -- Revives a tombstoned row that a re-import's rows carry live
        -- (deleted_at is null in the incoming row): the ordinary
        -- deleted_at-clearing path, exactly as the on_conflict shape
        -- import_provenance_test.sql already pins.
        deleted_at = excluded.deleted_at,
        last_modified_by_user_id = excluded.last_modified_by_user_id
      -- xmax = 0 identifies a row this command actually inserted (as
      -- opposed to one it found and updated via the arbiter) -- the
      -- standard Postgres INSERT ... ON CONFLICT idiom for telling the
      -- two branches apart from RETURNING alone. source_id is unique
      -- within insert_lookup (source_ranked's dedup above already
      -- guarantees it), so joining back to insert_lookup on it below is
      -- exact, not approximate.
      returning source_id, (xmax = 0) as was_insert
    )
    select
      (select count(*) from upserted where was_insert),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and il.conflict_deleted_at is not null and il.parsed_deleted_at is null)
        + (select count(*) from updated
            where existing_by_id_deleted_at is not null and parsed_deleted_at is null),
      (select count(*) from upserted u
         join insert_lookup il on il.source_id = u.source_id
        where not u.was_insert
          and not (il.conflict_deleted_at is not null and il.parsed_deleted_at is null))
        + (select count(*) from updated
            where not (existing_by_id_deleted_at is not null and parsed_deleted_at is null)),
      (select coalesce(jsonb_agg(jsonb_build_object('row_index', x.row_index, 'reason', x.reason) order by x.row_index), '[]'::jsonb)
         from (
           select row_index, reason from validated where reason is not null
           union all
           select row_index, combined_reason as reason from reasoned where combined_reason is not null
           union all
           select row_index, 'superseded by a later row in the same batch with the same (profile_id, source, source_id)'
             from source_ranked where source_dupe_rank > 1
           union all
           select row_index, 'duplicate date in batch'
             from date_ranked where date_dupe_rank > 1
         ) x)
    into v_inserted, v_revived, v_updated, v_rejected;
  exception
    when unique_violation then
      raise exception 'a row in this batch collides with an existing day_entries row under a different identity (its id resolves to one row, its (profile_id, source, source_id) to another) -- the client must ensure a row''s id and source_id always resolve to the same existing row before retrying'
        using errcode = 'invalid_parameter_value';
  end;

  -- Issue #167: touch sync_signals exactly once for the job's profile,
  -- rather than once per row (touch_sync_signal() no-op'd above) -- only
  -- if something actually changed. now() (transaction start time), not
  -- clock_timestamp() -- consistent with touch_sync_signal() itself and
  -- every other sync_signals writer in this schema, none of which have a
  -- same-transaction reason to need statement-time precision.
  if (v_inserted + v_updated + v_revived) > 0 then
    insert into public.sync_signals (profile_id, updated_at)
    values (v_job.profile_id, now())
    on conflict (profile_id) do update set updated_at = excluded.updated_at;
  end if;

  return jsonb_build_object(
    'inserted', v_inserted,
    'updated', v_updated,
    'revived', v_revived,
    'rejected', v_rejected
  );
end;
$$;

comment on function public.bulk_import_entries(uuid, jsonb) is
  'Issue #167: set-based bulk upsert of day_entries for large imports (up '
  'to 2000 rows/call), bypassing sync_push entirely -- SECURITY DEFINER, '
  'guardian-write-role checked against the p_import_id job''s profile '
  '(before the job-status check below it, so an unauthorised caller learns '
  'nothing about a job''s status), every row''s profile_id must equal the '
  'job''s. source/import_id come from the import_jobs row, never the '
  'payload. Two disjoint set-based write paths: a row whose id already '
  'exists in day_entries (any provenance) is UPDATEd in place with '
  'last-writer-wins on updated_at, mirroring sync_push''s own resolution '
  '(a stale update is silently skipped, not rejected); every other row '
  'requires a non-null source_id (rejected otherwise -- '
  '`source_id is required for idempotent import`, documented on '
  'BulkImportRow) and goes through '
  '`insert ... select ... on conflict (profile_id, source, source_id) '
  'where source_id is not null do update` -- the same raw shape '
  'import_provenance_test.sql pins as the way to revive a tombstoned '
  'imported row, which sync_push cannot do (it resolves strictly by id; '
  'see this migration''s header and AGENTS.md Migration Flow item 8). This '
  'two-path split is what makes a retry of an already-landed chunk '
  'idempotent instead of aborting on a primary-key collision. Validation '
  'is fully set-based (jsonb_array_elements ... with ordinality plus two '
  'safe-cast helpers and public.is_valid_timezone()), not a per-row loop, '
  'so a malformed individual row is rejected (row_index, reason) rather '
  'than aborting the batch -- covering every day_entries CHECK the row '
  'shape can violate (id/profile_id ULID, local_date, tz, flow, tags, '
  'note length, source_id length, updated_at). Issue #303: the flow check '
  'now calls public.is_valid_flow_level() (the same predicate the '
  'flow_level domain''s own CHECK and sync_push''s validation both use) '
  'instead of a third hand-kept copy of the allow-list -- still a plain '
  'boolean predicate, never a domain cast, so this set-based CASE keeps '
  'rejecting one bad row instead of aborting the whole batch. A tombstone '
  'row (deleted_at '
  'present) has its flow/tags/note/pms forced to the empty payload rather '
  'than validated or rejected, mirroring sync_push (Issue #140 review, '
  'LLA-060: pms joined this treatment after predating #220 entirely -- see '
  'this migration''s own header). Two independent '
  'within-batch duplicate rules: two rows sharing (profile_id, source, '
  'source_id) resolve to the later row (by position) winning; two rows '
  'sharing (profile_id, local_date) with different source_id resolve to '
  'the earlier row winning (`duplicate date in batch`) -- no in-RPC '
  'resolver for either kind of ambiguity. A row landing live on a date a '
  'different, differently-provenanced LIVE row already occupies is '
  'likewise rejected (`date already has a live entry`) rather than merged '
  '-- decision: no in-RPC resolver in this PR; the client surfaces the '
  'conflict. Sets lunarlog.bulk_import = ''on'' (transaction-local) for '
  'the duration of the write so touch_sync_signal()/'
  'enqueue_caregiver_alerts() no-op per row -- this function touches '
  'sync_signals itself, once, at the end, and never enqueues a caregiver '
  'alert for an imported row. Must complete within the caller''s ordinary '
  '8s role statement_timeout, like any other RPC -- an earlier draft''s '
  '`set local statement_timeout = ''60s''` was removed as a documented '
  'no-op (that GUC is sampled once at statement start; a mid-statement '
  '`set local` cannot retroactively widen it). Returns '
  '{inserted, updated, revived, rejected: [{row_index, reason}]}. Scoped '
  'to day_entries only (issue''s Proposed change is day_entries-first) -- '
  'an observations-shaped row is rejected as carrying unknown keys. The '
  'unique_violation backstop below is not purely theoretical: this '
  'function takes no day_entries row locks, so it can still fire on a '
  'genuine concurrent race with sync_push writing the same row(s) '
  '(unlike sync_push, which serialises per-user via '
  'pg_advisory_xact_lock), as well as on the id/source_id split '
  'resolution its own message describes -- either way, the client should '
  'retry the whole chunk.';

revoke all on function public.bulk_import_entries(uuid, jsonb) from public, anon;
grant execute on function public.bulk_import_entries(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- Issue #292: export_account_data() re-emitted from
-- 20260915070000_export_account_data_tracking_preferences.sql's body
-- (main's current definition), unchanged except one new `settings` section
-- (see this migration's header). Same 0-argument signature.
-- ---------------------------------------------------------------------------

create or replace function public.export_account_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profiles jsonb;
  v_profile_guardians jsonb;
  v_guardian_invitations jsonb;
  v_ownership_transfers jsonb;
  v_notification_preferences jsonb;
  v_push_devices jsonb;
  v_missed_entry_alert_state jsonb;
  v_feedback_tickets jsonb;
  v_profile_reminder_windows jsonb;
  v_import_jobs jsonb;
  -- Issue #292: the caller's own public.settings rows.
  v_settings jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- ---------------------------------------------------------------------
  -- profiles + nested day_entries. Owned profiles carry every live entry;
  -- shared profiles (the caller is an accepted guardian but not the
  -- owner) carry only entries the caller authored.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pr.id,
        'display_name', pr.display_name,
        'is_minor', pr.is_minor,
        'mode', pr.mode,
        'sort_order', pr.sort_order,
        'archived_at', pr.archived_at,
        'created_at', pr.created_at,
        'updated_at', pr.updated_at,
        'birth_year', pr.birth_year,
        'relationship', pr.relationship,
        -- Issue #255: the numeric-measurement display-unit preferences.
        'bbt_unit', pr.bbt_unit,
        'weight_unit', pr.weight_unit,
        -- Issue #648: the #259 per-profile tracking-preferences document --
        -- already jsonb, selected as-is like every other profiles column.
        'tracking_preferences', pr.tracking_preferences,
        'transferred_at', pr.transferred_at,
        'owned', (pr.user_id = v_uid),
        'day_entries', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', de.id,
              'local_date', de.local_date,
              'tz', de.tz,
              'flow', de.flow,
              'tags', de.tags,
              'note', de.note,
              'created_at', de.created_at,
              'updated_at', de.updated_at,
              'logged_by_user_id', de.logged_by_user_id,
              'last_modified_by_user_id', de.last_modified_by_user_id
            )
            order by de.local_date, de.id
          )
          from public.day_entries de
          where de.profile_id = pr.id
            and de.deleted_at is null
            and (pr.user_id = v_uid or de.logged_by_user_id = v_uid)
        ), '[]'::jsonb)
      )
      order by pr.id
    ), '[]'::jsonb
  )
  into v_profiles
  from public.profiles pr
  where pr.deleted_at is null
    and (
      pr.user_id = v_uid
      or exists (
        select 1 from public.profile_guardians g
         where g.profile_id = pr.id
           and g.user_id = v_uid
           and g.status = 'accepted'
      )
    );

  -- ---------------------------------------------------------------------
  -- profile_guardians: every membership on a profile the caller owns,
  -- plus the caller's own membership row on any profile (owned or
  -- shared) -- never a co-guardian's row on a shared profile.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', g.id,
        'profile_id', g.profile_id,
        'user_id', g.user_id,
        'role', g.role,
        'status', g.status,
        'display_name', g.display_name,
        -- Never another user's id on a shared (non-owned) profile: the
        -- caller's own row there is the only one returned, and its
        -- invited_by names whoever invited them (often the owner) --
        -- another user's identity, out of scope per this migration's
        -- never-another-user's-data bound. Owned profiles keep it: the
        -- owner already sees every guardian's invited_by via ordinary
        -- profile_guardians_select RLS.
        'invited_by', case
          when g.profile_id in (select id from public.profiles where user_id = v_uid)
            then g.invited_by
          else null
        end,
        'created_at', g.created_at,
        'updated_at', g.updated_at,
        'revoked_at', g.revoked_at
      )
      order by g.profile_id, g.user_id
    ), '[]'::jsonb
  )
  into v_profile_guardians
  from public.profile_guardians g
  where g.profile_id in (select id from public.profiles where user_id = v_uid)
     or g.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- guardian_invitations: every invitation for a profile the caller owns,
  -- plus invitations the caller personally created for any profile (owned
  -- or shared). token_hash is never selected (see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'profile_id', i.profile_id,
        'invited_by', i.invited_by,
        'role', i.role,
        'recipient_label', i.recipient_label,
        'expires_at', i.expires_at,
        'accepted_at', i.accepted_at,
        'accepted_by', i.accepted_by,
        'revoked_at', i.revoked_at,
        'created_at', i.created_at
      )
      order by i.created_at, i.id
    ), '[]'::jsonb
  )
  into v_guardian_invitations
  from public.guardian_invitations i
  where i.profile_id in (select id from public.profiles where user_id = v_uid)
     or i.invited_by = v_uid;

  -- ---------------------------------------------------------------------
  -- ownership_transfers: the caller's own involvement only (initiated or
  -- accepted), on any profile. token_hash is never selected.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'profile_id', t.profile_id,
        'initiated_by', t.initiated_by,
        'parent_post_transfer_role', t.parent_post_transfer_role,
        'recipient_label', t.recipient_label,
        'expires_at', t.expires_at,
        'accepted_at', t.accepted_at,
        'accepted_by', t.accepted_by,
        'cancelled_at', t.cancelled_at,
        'created_at', t.created_at
      )
      order by t.created_at, t.id
    ), '[]'::jsonb
  )
  into v_ownership_transfers
  from public.ownership_transfers t
  where t.initiated_by = v_uid
     or t.accepted_by = v_uid;

  -- ---------------------------------------------------------------------
  -- notification_preferences: the caller's own rows only (never a
  -- co-guardian's, on any profile -- see header note).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', np.profile_id,
        'alert_on_log', np.alert_on_log,
        'alert_on_cycle_start_only', np.alert_on_cycle_start_only,
        'alert_on_high_severity', np.alert_on_high_severity,
        'missed_entry_days', np.missed_entry_days,
        'quiet_hours_start', np.quiet_hours_start,
        'quiet_hours_end', np.quiet_hours_end,
        'time_zone', np.time_zone,
        'log_cadence', np.log_cadence,
        'cycle_start_cadence', np.cycle_start_cadence,
        'high_severity_cadence', np.high_severity_cadence,
        'digest_local_time', np.digest_local_time,
        'updated_at', np.updated_at
      )
      order by np.profile_id
    ), '[]'::jsonb
  )
  into v_notification_preferences
  from public.notification_preferences np
  where np.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- push_devices: the caller's own devices; `token` redacted to its last
  -- 4 characters (see header note) rather than included verbatim.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pd.id,
        'platform', pd.platform,
        'token_last4', right(pd.token, 4),
        'updated_at', pd.updated_at,
        'disabled_at', pd.disabled_at
      )
      order by pd.id
    ), '[]'::jsonb
  )
  into v_push_devices
  from public.push_devices pd
  where pd.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- missed_entry_alert_state: the caller's own dedupe markers only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', s.profile_id,
        'last_enqueued_for', s.last_enqueued_for
      )
      order by s.profile_id
    ), '[]'::jsonb
  )
  into v_missed_entry_alert_state
  from public.missed_entry_alert_state s
  where s.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- feedback_tickets + their full reply thread (the ticket owner can
  -- already read every reply on their own ticket via
  -- feedback_replies_select).
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ft.id,
        'reply_email', ft.reply_email,
        'category', ft.category,
        'message', ft.message,
        'device_info', ft.device_info,
        'attachment_paths', ft.attachment_paths,
        'status', ft.status,
        'created_at', ft.created_at,
        'updated_at', ft.updated_at,
        'replies', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', fr.id,
              'author_type', fr.author_type,
              'message', fr.message,
              'created_at', fr.created_at
            )
            order by fr.created_at, fr.id
          )
          from public.feedback_replies fr
          where fr.ticket_id = ft.id
        ), '[]'::jsonb)
      )
      order by ft.created_at, ft.id
    ), '[]'::jsonb
  )
  into v_feedback_tickets
  from public.feedback_tickets ft
  where ft.user_id = v_uid;

  -- ---------------------------------------------------------------------
  -- profile_reminder_windows: owned profiles only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', w.profile_id,
        'estimated_next_start', w.estimated_next_start,
        'episode_open', w.episode_open,
        'updated_at', w.updated_at
      )
      order by w.profile_id
    ), '[]'::jsonb
  )
  into v_profile_reminder_windows
  from public.profile_reminder_windows w
  where w.profile_id in (select id from public.profiles where user_id = v_uid);

  -- ---------------------------------------------------------------------
  -- Issue #167: import_jobs -- every job on a profile the caller owns,
  -- plus every job the caller personally ran (created_by = v_uid) on any
  -- profile, mirroring guardian_invitations' scoping exactly. Progress
  -- metadata only (source label, counts, status, timestamps) -- no health
  -- content.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', j.id,
        'profile_id', j.profile_id,
        'source', j.source,
        'status', j.status,
        'total_rows', j.total_rows,
        'processed_rows', j.processed_rows,
        'error_kind', j.error_kind,
        'created_by', j.created_by,
        'created_at', j.created_at,
        'completed_at', j.completed_at
      )
      order by j.created_at, j.id
    ), '[]'::jsonb
  )
  into v_import_jobs
  from public.import_jobs j
  where j.profile_id in (select id from public.profiles where user_id = v_uid)
     or j.created_by = v_uid;

  -- ---------------------------------------------------------------------
  -- Issue #292: settings -- the caller's own per-user key/value rows.
  -- server_version stays out (sync bookkeeping, matching every other
  -- table's own projection above); key/value/updated_at only.
  -- ---------------------------------------------------------------------
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'key', st.key,
        'value', st.value,
        'updated_at', st.updated_at
      )
      order by st.key
    ), '[]'::jsonb
  )
  into v_settings
  from public.settings st
  where st.user_id = v_uid;

  -- schema_version stays 1 deliberately: this migration's new
  -- tracking_preferences projection key is purely additive to the existing
  -- `profiles[]` element, not a breaking change to an existing key's shape
  -- -- see 20260908190000_bulk_import.sql's header for the same reasoning
  -- applied to import_jobs. Issue #292's new `settings` top-level key is
  -- additive on the same grounds.
  return jsonb_build_object(
    'schema_version', 1,
    'exported_at', now(),
    'profiles', v_profiles,
    'profile_guardians', v_profile_guardians,
    'guardian_invitations', v_guardian_invitations,
    'ownership_transfers', v_ownership_transfers,
    'notification_preferences', v_notification_preferences,
    'push_devices', v_push_devices,
    'missed_entry_alert_state', v_missed_entry_alert_state,
    'feedback_tickets', v_feedback_tickets,
    'profile_reminder_windows', v_profile_reminder_windows,
    'import_jobs', v_import_jobs,
    'settings', v_settings
  );
end;
$$;

revoke execute on function public.export_account_data() from public, anon;
grant execute on function public.export_account_data() to authenticated;
