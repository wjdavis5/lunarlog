-- Migration: 20260915160000_sync_push_sole_write_path.sql
--
-- Issue #201 (P3): day_entries was the one client-writable table in this
-- schema still directly reachable via PostgREST -- `initial_sync_schema.sql`
-- grants `select, insert` and a column-scoped `update` on it to
-- `authenticated`, and the guardian RLS policies (`multi_guardian_schema.sql`)
-- let any accepted guardian use that grant. Every invariant sync_push
-- enforces beyond the table's own CHECK constraints and triggers -- the
-- same-date tag union, the 500-row batch cap, the "an entry cannot move
-- between profiles" guard, the per-user advisory lock -- lived only in the
-- RPC, so a raw PostgREST write could bypass all of them. No guardian could
-- write data they could not otherwise write (every column CHECK, the unique
-- live index, the attribution trigger and the server_version trigger still
-- applied regardless of write path), so this was an untested correctness
-- surface, not a security hole -- but every other client-writable table in
-- this schema (`profile_guardians`, `guardian_invitations`,
-- `ownership_transfers`, `notification_outbox`) already has NO client write
-- grant at all; day_entries was the one exception.
--
-- Decision (D-31 recommended this, option (a) of the issue's two-option
-- tradeoff): REVOKE the direct grants and make `sync_push` the sole write
-- path, rather than option (b) (duplicate the RPC's invariants into BEFORE
-- triggers so a direct write stays safe too). (a) is chosen because it
-- matches the posture every other client-writable-adjacent table in this
-- schema already has, and because sync_push already performs every one of
-- its own role/authorization checks by deriving the caller from
-- `auth.uid()` (never from RLS) -- verified below, not just assumed --
-- which is exactly what SECURITY DEFINER needs to stay safe once RLS no
-- longer applies to its writes. (b) would have meant re-deriving the
-- same-date union, the profile-move guard and a row-count-style cap a
-- second time in trigger form, permanently maintained in two places instead
-- of one, for a correctness surface (`observations`, tracked separately
-- under the Tracking Model epic) that is only going to grow more such
-- invariants.
--
-- What this migration does:
--   1. `revoke insert, update on table public.day_entries from
--      authenticated` -- the table's `select` grant is untouched (the
--      client still reads its own rows directly, e.g. for the pull path
--      and local queries); no `delete` grant existed to revoke.
--   2. Re-emits `sync_push` (CREATE OR REPLACE takes the whole body, so
--      this is the current body verbatim -- from
--      20260915130000_data_consistency_bundle.sql, the latest predecessor
--      on `main` at dispatch time -- with exactly two changes):
--      `security invoker` becomes `security definer`, and the one inline
--      comment whose justification depended on invoker mode is corrected
--      (search for "Issue #201" in the body below). `set search_path = ''`
--      was already pinned and every reference in the body was already
--      fully schema-qualified (`public.day_entries`, `public.profiles`,
--      `auth.uid()`, ...), so DEFINER introduces no unqualified-name
--      hijack risk.
--   3. Verifies (this migration adds no new checks -- every one of the
--      following was already present in the body carried over from
--      20260915130000, confirmed by inspection before writing this
--      migration, not assumed) that DEFINER is safe: every one of
--      sync_push's seven per-table loops derives the caller from
--      `v_uid := (select auth.uid())` (never from `current_user`/`session_user`,
--      which DEFINER would change to the function owner), and enforces
--      guardian role + accepted profile membership before any write --
--      profiles' edit/delete branch via a direct `profile_guardians`
--      lookup (the `select role into v_caller_role from
--      public.profile_guardians ...` block just after the "Profile
--      exists" branch), and every one of the other six loops
--      (day_entries, observations, profile_modes, cycle_overrides,
--      care_notes, visit_prep_items) via `v_role_map`, itself built as
--      `... from public.profile_guardians pg where pg.user_id = v_uid and
--      pg.status = 'accepted' and pg.profile_id = any(...)` -- so a
--      non-member's `v_caller_role` is null and every loop's `if
--      v_caller_role is null or ...` guard rejects the row. A brand-new
--      profile's own INSERT branch has no such check by design (there is
--      no existing owner yet to check against; the `on_profile_created_add_guardian`
--      trigger is what grants the creator `primary_guardian` immediately
--      after), unchanged by this migration.
--   4. `revoke all on function public.sync_push(...) from public, anon;
--      grant execute on function public.sync_push(...) to authenticated;`
--      -- explicit and idempotent, matching the pattern
--      `public.sync_pull(jsonb)` (20260913014000) already established for
--      a DEFINER RPC in this schema, even though the `authenticated` grant
--      already existed from 20260904020000 onward (CREATE OR REPLACE does
--      not touch existing grants).
--
-- Other writers checked (issue's own instruction) -- grepped every
-- `insert into public.day_entries` / `update public.day_entries` across
-- every migration and confirmed the CURRENT (latest, as of this migration)
-- definition of each: `bulk_import_entries` (re-emitted most recently by
-- 20260915130000_data_consistency_bundle.sql), `rehome_stray_day_entries`
-- (20260906120000), `accept_ownership_transfer` (most recently
-- 20260915010000_db_integrity_bundle.sql), `tombstone_profile_content`
-- (20260913013000), `delete_profile_data` (most recently
-- 20260915090000_deletion_tombstones_bundle.sql), and `delete_account_data`
-- (most recently 20260914103000_account_deletion_cross_guardian_and_identity_fixes.sql)
-- are every OTHER function that writes day_entries, and all six are
-- already `security definer` -- they run as their owner regardless of the
-- `authenticated` grant, so this revoke changes nothing about them.
-- `sync_push` was the only `security invoker` function writing day_entries
-- anywhere in this schema's history (every prior `sync_push` re-emission
-- back to 20260903014211 was also invoker). The BEFORE/AFTER triggers on
-- day_entries (attribution,
-- server_version, tombstone cascades) are unaffected either way -- a
-- trigger fires for any successful write regardless of the writing role;
-- only reaching that write in the first place is what this migration gates.
-- The Dart client (`lib/data/sync/supabase_sync_transport.dart`) never
-- issues a PostgREST insert/update against `day_entries` directly -- its
-- only non-select call there is `.select()` inside `pullPage`; every write
-- goes through the `sync_push` RPC.
--
-- pgTAP coverage added by this migration: supabase/tests/sync_push_sole_write_path_test.sql
-- (direct insert/update by an accepted guardian now fails 42501; sync_push
-- itself still succeeds for that same guardian and is still refused for a
-- non-member). A large share of the REST of the pgTAP suite used a raw
-- `insert`/`update` on day_entries as `authenticated` purely as fixture
-- setup (never as the thing under test) -- those call sites now run as
-- `service_role` instead (already an established pattern in this suite,
-- e.g. bulk_import_test.sql, missed_entry_scan_test.sql), which still
-- carries the table's un-revoked default grants and leaves `auth.uid()`
-- untouched (it reads `request.jwt.claims`, a separate session GUC from
-- `role`), so attribution and every other row-content assertion in those
-- tests is unaffected by the role switch.

revoke insert, update on table public.day_entries from authenticated;

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
security definer
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
  '20260915160000_sync_push_sole_write_path.sql changed. Issue #201: now '
  'SECURITY DEFINER, so it is the sole write path for day_entries -- '
  '`authenticated` no longer holds insert/update on that table at all. '
  'Every one of its seven per-table loops already derived the caller from '
  'auth.uid() and enforced guardian role + accepted profile_guardians '
  'membership before writing (RLS was never what carried that weight), so '
  'no new checks were needed for DEFINER to stay safe -- see this '
  'migration''s header for the full verification.';

-- Explicit and idempotent, matching public.sync_pull(jsonb)'s (20260913014000)
-- own DEFINER-RPC grant pattern -- the authenticated grant already existed
-- from 20260904020000 onward (CREATE OR REPLACE does not touch existing
-- grants), this just makes both grant and revoke sides explicit here too.
revoke all on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb, jsonb, jsonb, jsonb, jsonb) to authenticated;
