-- Migration: 20260908180000_timezone_contract.sql
-- Issue #180 (P1, epic: health-sync): day-boundary and time-zone contract
-- for `observed_at` vs `local_date` on `public.observations` (added by
-- #240, `20260908160000_observations.sql`, already live on `main` with
-- `observed_at timestamptz null`, `local_date date not null`, and
-- `tz text not null`).
--
-- Timestamp note: this migration sorts after `20260908170000_
-- import_provenance.sql` (issue #159), which is now merged to `main`
-- (1d28b78) and carries the current `sync_push` body -- this migration's
-- item 4 below `create or replace`s that same 3-arg `sync_push`, copying
-- #159's body verbatim except for the `local_date` derivation fix.
--
-- REVIEW FIX (post-merge, applied in this same migration file rather than
-- a follow-up, since it changes this migration's own trigger's contract):
-- `sync_push` was originally left unedited on the theory that the
-- `observations_derive_local_date` BEFORE trigger (item 3) would
-- transparently correct `local_date` for every write regardless of which
-- role or RPC produced it. That is true for the *stored* value, but
-- `sync_push` evaluates the per-day cap and the same-date `(category,
-- code)` dedup *before* the trigger ever runs, against the
-- client-supplied `local_date` key -- so a push whose `observed_at` fell
-- on a different local day than the client-supplied `local_date` bypassed
-- both invariants, and an UPDATE that changed only `observed_at` moved a
-- row across days without ever tripping `v_obs_check_collision` (which
-- was comparing the stored row's `local_date` against that same stale
-- client-supplied value). Item 4 below fixes this by deriving
-- `v_local_date` from `observed_at`/`tz` inside `sync_push` itself,
-- immediately after `v_tz` is resolved and ahead of every downstream
-- check -- the trigger is now a pure backstop that recomputes the exact
-- same value `sync_push` already checked against, never the sole source
-- of truth for it.
--
-- Scope for this migration (see issue #180's acceptance criteria, plus
-- the review fix above):
--   1. `public.is_valid_timezone(text)`: a cheap IMMUTABLE predicate that
--      rejects any string `now() at time zone tz` cannot evaluate --
--      the issue's sketch, with two review refinements: it is now
--      `strict` (`returns null on null input`), so `is_valid_timezone(null)`
--      is `null` rather than `false` -- both CHECK constraints below
--      already pass on a null `tz` under three-valued logic (a `null`
--      CHECK result is not a violation), which cannot occur today since
--      both `tz` columns are `not null`, but `strict` makes that
--      no-crash-on-null behaviour a property of the function itself
--      rather than an accident of how the CHECK happens to be written.
--      The bare `exception when others` is intentionally NOT narrowed to
--      `when invalid_parameter_value`: `'Mars/Olympus'` and `''` were
--      verified in pgTAP (`timezone_contract_test.sql`) to both still
--      return `false` under the bare handler, and Postgres does not
--      document `invalid_parameter_value` as the exclusive errcode every
--      unresolvable zone string raises through `at time zone` (some
--      malformed inputs can raise other classes, e.g. a syntax-shaped
--      POSIX spec) -- narrowing risks a garbage string escaping as an
--      uncaught exception instead of a clean `false`, which is worse for
--      a predicate whose entire job is "never raise, just say no".
--      IMPORTANT (header sentence added by review): this CHECK is
--      deliberately LOOSER than the client's own `isValidIanaTimeZone`
--      (`lib/domain/util/timezone.dart`) -- Postgres' `at time zone`
--      also accepts POSIX-style specs and many non-IANA abbreviations
--      (e.g. `'EST'`, `'PST8PDT'`) that the client's IANA-only validator
--      rejects. `is_valid_timezone` is a garbage filter (rejects strings
--      that are not a zone of any kind to Postgres), not a guarantee that
--      every value it accepts is one the client would also accept or
--      handle correctly -- client-side validation is still the real gate
--      for what a user can enter.
--   2. A CHECK constraint using it on both tables that carry a `tz`
--      column today: `observations_tz_valid` on `public.observations`,
--      `day_entries_tz_valid` on `public.day_entries`. Both added
--      `not valid` then `validate constraint`ed in the same migration
--      (see section 2 below for why that pattern was chosen over a
--      pre-check that raises a custom message).
--
--      OPERATOR PRE-FLIGHT (run against `dleexnnevuuddcgcpztq` before
--      `supabase db push` deploys this migration -- `validate constraint`
--      aborts the migration and rolls back the whole transaction on the
--      FIRST invalid stored value it finds, so this query is how an
--      operator finds every offending row up front instead of discovering
--      them one deploy attempt at a time):
--
--        select 'observations' as table_name, id, tz
--          from public.observations
--         where tz is not null
--           and tz not in (select name from pg_timezone_names)
--           and tz not in (select abbrev from pg_timezone_abbrevs)
--        union all
--        select 'day_entries' as table_name, id, tz
--          from public.day_entries
--         where tz is not null
--           and tz not in (select name from pg_timezone_names)
--           and tz not in (select abbrev from pg_timezone_abbrevs);
--
--      A non-empty result means `validate constraint` WILL fail and the
--      migration transaction WILL roll back (no partial application --
--      `is_valid_timezone`, the CHECKs, the trigger, and the `sync_push`
--      redefinition all either land together or not at all); fix or
--      tombstone the offending row(s) first, per the "Judgement calls"
--      note on `validate constraint` below.
--   3. A `before insert or update` trigger on `public.observations`,
--      `observations_derive_local_date`, that sets
--      `local_date := (observed_at at time zone tz)::date` whenever the
--      incoming `observed_at` is not null, and otherwise leaves
--      `local_date` exactly as supplied (a date-only Clue import, or any
--      other write that never had a real instant, is an honest write, not
--      a value to backfill -- issue #180's acceptance criteria says so
--      explicitly).
--   4. `sync_push` (`public.sync_push(jsonb, jsonb, jsonb)`) IS edited
--      here -- see the REVIEW FIX note above. This `create or replace`
--      copies #159's `20260908170000_import_provenance.sql` body
--      verbatim, including every rationale comment, with exactly two
--      substantive changes in the `p_observations` loop: (a) `v_observed_at`
--      is now parsed immediately after `v_tz` is resolved (instead of
--      inside the tombstone/live if-else below it), and `v_local_date` is
--      immediately re-derived from it when not null, so every downstream
--      check -- the stored-row lookup, the per-day cap, and the same-date
--      `(category, code)` collision dedup -- runs against the corrected
--      value; (b) the now-redundant re-parse of `v_observed_at` inside
--      the live branch is removed (a comment marks where it used to be).
--      `v_obs_check_collision`'s existing condition
--      (`v_stored_obs.local_date is distinct from v_local_date`) needed
--      no code change to satisfy "true when the derived date differs from
--      the stored date" -- it already compared against `v_local_date`,
--      which is now the derived value; only its comment was expanded to
--      say so explicitly. No `sync_push` column list, key allow-list, or
--      resolver logic otherwise changes; the day_entries loop above the
--      observations loop is untouched. `revoke execute ... from public,
--      anon` / `grant execute ... to authenticated` are re-issued on the
--      redefinition, matching #159's own pattern.
--   5. RLS, grants, and `resolve_deliver_after`'s own ad hoc zone-validity
--      defense (`20260906220000_notification_outbox.sql`) are untouched
--      here, per the issue's acceptance criteria: "existing defensive
--      code may be simplified/removed as a follow-up, not required here."
--
-- Judgement calls (mirrored in the PR's Assumptions section):
--   * `is_valid_timezone` is IMMUTABLE despite calling `now()` internally.
--     This is safe ONLY because the function's return value never depends
--     on the actual value `now()` produces -- it depends solely on
--     whether `<any timestamptz> at time zone tz` raises for the given
--     `tz` string, which is a property of `tz` alone (Postgres validates
--     the zone name/abbreviation against the tzdata catalog before doing
--     any arithmetic with the timestamp value). Marking it IMMUTABLE lets
--     it be used in an index or a CHECK constraint's planner-time proof
--     without Postgres objecting to a STABLE/VOLATILE function there; if
--     this function's body ever changes to return something that *does*
--     vary with the current instant (e.g. the actual offset), the
--     IMMUTABLE marking would become incorrect and must be revisited.
--   * No `revoke execute ... from public, anon` on `is_valid_timezone`:
--     it is a pure predicate with no table access and no SECURITY
--     DEFINER, the same category `rls_isolation_test.sql`'s catalog guard
--     already documents an allow-list for (`is_valid_tags_array`,
--     `merge_tag_arrays`, `is_allowed_device_info`) -- the guard is
--     extended to include it rather than adding a redundant revoke that
--     would just have to be un-done the next time this predicate is
--     called from an unauthenticated context. An explicit
--     `grant execute ... to authenticated` is still added, matching the
--     documented pattern, even though it is redundant with the default
--     PUBLIC grant -- explicit is better than implicit for a function two
--     table CHECK constraints now depend on.
--   * CHECK-constraint validation: `not valid` + `validate constraint`
--     (Postgres' standard low-risk pattern for adding a CHECK to a
--     populated table) rather than a hand-written pre-check that raises a
--     custom message. `validate constraint` performs the same full-table
--     scan a pre-check would, and Postgres' own error on a real
--     violation already names the constraint and the table
--     (`check constraint "day_entries_tz_valid" of relation "day_entries"
--     is violated by some row`), which is a clear enough message for an
--     operator to locate and fix the offending row(s) before re-running
--     the deploy -- a hand-rolled pre-check would only duplicate that
--     work for no clearer outcome. If this migration's `validate
--     constraint` step ever fails on the live project, that is the
--     signal to fix (or tombstone) the offending row(s) first, not to
--     weaken the CHECK.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. public.is_valid_timezone(text) -- the issue's sketch, plus `strict`
--    (review fix: `is_valid_timezone(null)` returns `null`, not `false` --
--    see this migration's header, item 1).
-- ---------------------------------------------------------------------------

create or replace function public.is_valid_timezone(tz text)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
begin
  perform now() at time zone tz;
  return true;
exception when others then
  return false;
end;
$$;

comment on function public.is_valid_timezone(text) is
  'Issue #180: cheap IMMUTABLE predicate backing observations_tz_valid/day_entries_tz_valid. Returns false for any string `now() at time zone tz` cannot evaluate (unknown zone name/abbreviation, empty string, etc.) instead of raising -- see this migration''s header for why IMMUTABLE is safe here despite calling now(). `strict`: returns null (not false) on a null tz -- a CHECK sees a null result as "not violated", same as false would never be reached for a null tz today since both tz columns are not null, but this makes the no-crash-on-null behaviour a property of the function, not an accident of the CHECK. The bare `exception when others` is deliberate, not narrowed to a single errcode -- see this migration''s header, item 1, for why (verified in pgTAP against ''Mars/Olympus'' and ''''). This CHECK is looser than the client''s isValidIanaTimeZone (lib/domain/util/timezone.dart) -- it also accepts POSIX-style specs and non-IANA abbreviations the client rejects -- and is a garbage filter, not a guarantee that every value it accepts is one the client can also parse.';

grant execute on function public.is_valid_timezone(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. CHECK constraints on both tables that carry `tz` today.
--    `not valid` + `validate constraint`: see this migration's header,
--    "Judgement calls", for why this pattern was chosen.
-- ---------------------------------------------------------------------------

alter table public.observations
  add constraint observations_tz_valid
  check (public.is_valid_timezone(tz)) not valid;

alter table public.observations
  validate constraint observations_tz_valid;

alter table public.day_entries
  add constraint day_entries_tz_valid
  check (public.is_valid_timezone(tz)) not valid;

alter table public.day_entries
  validate constraint day_entries_tz_valid;

-- ---------------------------------------------------------------------------
-- 3. observations_derive_local_date: before insert or update, sets
--    local_date from observed_at/tz whenever observed_at is not null;
--    leaves local_date exactly as supplied when observed_at is null
--    (date-only historical/Clue import -- issue #180 acceptance criteria).
--
--    Trigger firing order note: Postgres fires same-timing triggers on a
--    table in trigger-name alphabetical order. This table's existing
--    BEFORE triggers are `observations_attribution_insert_guard` /
--    `observations_attribution_update_guard` (20260908160000_observations.sql)
--    and `observations_set_server_version`. Alphabetically:
--    attribution_insert_guard/attribution_update_guard, then
--    derive_local_date, then set_server_version -- so the attribution
--    guard's own-column checks run first (and can still abort the write
--    before this trigger ever sees the row), this trigger runs second and
--    only ever touches `local_date`, and `set_server_version` runs last
--    exactly as before. None of the three read or write a column another
--    one owns, so the order has no correctness dependency today; it is
--    documented here only so a future trigger addition on this table
--    knows to check this comment before assuming a different order.
-- ---------------------------------------------------------------------------

create or replace function public.derive_observation_local_date()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.observed_at is not null then
    new.local_date := (new.observed_at at time zone new.tz)::date;
  end if;
  return new;
end;
$$;

comment on function public.derive_observation_local_date() is
  'Issue #180: derives observations.local_date from observed_at/tz on every insert/update when observed_at is present; leaves local_date untouched when observed_at is null (date-only import). Fires for sync_push''s inserts/updates too -- a BEFORE ROW trigger runs regardless of which role/RPC performed the write -- but is a pure backstop for the *stored* value only: sync_push now derives this same local_date itself, ahead of its own per-day cap and same-date dedup checks, since those run before this trigger ever fires (review fix -- see this migration''s header, item 4, and section 4 below).';

create trigger observations_derive_local_date
  before insert or update on public.observations
  for each row execute function public.derive_observation_local_date();

-- Trigger functions in this schema are never callable directly (they read
-- new/old, meaningless outside a trigger context) and always get an
-- explicit revoke, matching set_server_version()
-- (20260903014208_initial_sync_schema.sql), touch_sync_signal()
-- (20260905100000_realtime_publication.sql), and
-- enforce_observation_attribution() (20260908160000_observations.sql) --
-- unlike is_valid_timezone above, this is NOT a pure predicate exempted
-- from the rls_isolation_test.sql catalog guard.
revoke execute on function public.derive_observation_local_date() from public, anon;

-- ---------------------------------------------------------------------------
-- 4. sync_push: create or replace, same 3-arg signature, body copied verbatim
--    from 20260908170000_import_provenance.sql except for the local_date
--    derivation fix described in this migration's header, item 4. Diff the
--    two files' sync_push bodies to confirm the derivation lines (and their
--    comments) are the only difference.
-- ---------------------------------------------------------------------------

create or replace function public.sync_push(
  p_profiles jsonb,
  p_day_entries jsonb,
  p_observations jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c_max_rows constant integer := 500;
  c_max_observations_per_day constant integer := 200;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  c_profile_keys constant text[] := array[
    'id', 'display_name', 'is_minor', 'sort_order', 'archived_at',
    'created_at', 'updated_at', 'deleted_at',
    -- U1: profile subject metadata, syncable like any other profile column
    'birth_year', 'relationship',
    -- #131: care mode, syncable like any other profile column
    'mode',
    -- tolerated but never read
    'user_id', 'server_version', 'transferred_at'];
  c_day_entry_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
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
    'import_id', 'raw', 'updated_at', 'deleted_at',
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
  v_profile_id text;
  v_local_date date;
  v_tz text;
  v_flow text;
  v_tags jsonb;
  v_note text;

  v_stored_profile public.profiles%rowtype;
  v_stored public.day_entries%rowtype;
  v_other public.day_entries%rowtype;
  v_accept boolean;
  v_incoming_wins boolean;
  v_caller_role text;

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
  v_raw jsonb;
  v_day_entry_profile_id text;
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
begin
  if v_uid is null then
    raise exception 'sync_push requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

  -- Serialise pushes per-user so server_version commits monotonically per user (Issue #14).
  perform pg_advisory_xact_lock(hashtext(v_uid::text));

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

  -- -------------------------------------------------------------------------
  -- profiles
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_profiles) loop
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
           birth_year, relationship, mode)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at,
           v_birth_year, v_relationship, v_mode);
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
                 is_minor = v_is_minor,
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
                 mode = case when v_row ? 'mode' then v_mode else v_stored_profile.mode end
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

  -- -------------------------------------------------------------------------
  -- day entries
  -- -------------------------------------------------------------------------
  for v_row in select value from jsonb_array_elements(p_day_entries) loop
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
      if v_flow not in ('none', 'spotting', 'light', 'medium', 'heavy') then
        raise exception 'flow is not a known level';
      end if;
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;
      if v_deleted_at is not null then
        -- tombstones carry no payload (issue #224: flow joins tags/note -
        -- it was the one field this branch left the incoming value in,
        -- the most sensitive single column on the row)
        v_tags := '[]'::jsonb;
        v_note := null;
        v_flow := 'none';
      else
        v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);
        if jsonb_typeof(v_tags) <> 'array' then
          raise exception 'tags is not an array';
        end if;
        v_note := v_row ->> 'note';
      end if;

      -- Verify caller has write permissions for profile (primary_guardian, co_parent, or caregiver)
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

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
            update public.day_entries
               set deleted_at = v_updated_at,
                   updated_at = v_updated_at,
                   flow = 'none',
                   note = null,
                   tags = '[]'::jsonb,
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
          end if;
        end if;
      end if;

      if v_stored.id is null then
        insert into public.day_entries
          (id, profile_id, local_date, tz, flow, tags, note,
           source, source_id, import_id,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note,
           v_source, v_source_id, v_import_id,
           v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored;
      else
        update public.day_entries
           set profile_id = v_profile_id,
               local_date = v_local_date,
               tz = v_tz,
               flow = v_flow,
               tags = v_tags,
               note = v_note,
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
  for v_row in select value from jsonb_array_elements(p_observations) loop
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
      -- category's required-unless-tombstoned check moves below, once
      -- v_deleted_at is known (review finding: a tombstone push must not
      -- be forced to carry a category just to satisfy this validation --
      -- see observations_category_required_unless_tombstoned_check).
      v_category := v_row ->> 'category';
      v_updated_at := (v_row ->> 'updated_at')::timestamptz;
      if v_updated_at is null then
        raise exception 'updated_at is required';
      end if;
      v_deleted_at := (v_row ->> 'deleted_at')::timestamptz;

      -- The day entry this observation is attached to must exist and must
      -- belong to the same profile the caller is pushing under - a
      -- mismatched pair would smuggle an observation onto another
      -- profile's day entry past the role check below (mirrors the
      -- day_entries "cannot move between profiles" guard's intent, applied
      -- up front here since day_entry_id/profile_id are a pair on this
      -- table rather than a single reassignable column).
      select profile_id into v_day_entry_profile_id
        from public.day_entries
       where id = v_day_entry_id;
      if v_day_entry_profile_id is null then
        raise exception 'day_entry_id does not exist';
      end if;
      if v_day_entry_profile_id is distinct from v_profile_id then
        raise exception 'day_entry_id does not belong to profile_id'
          using errcode = 'insufficient_privilege';
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
      select role into v_caller_role
        from public.profile_guardians
       where profile_id = v_profile_id
         and user_id = v_uid
         and status = 'accepted';

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
             and deleted_at is null
             and id <> v_id
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
           value_num, value_text, unit, intensity, excluded, source, source_id, import_id, raw,
           updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_day_entry_id, v_profile_id, v_local_date, v_observed_at, v_tz, v_category, v_code,
           v_value_num, v_value_text, v_unit, v_intensity, v_excluded, v_source, v_source_id, v_import_id, v_raw,
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

  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$$;

comment on function public.sync_push(jsonb, jsonb, jsonb) is
  'Batch upsert of profiles, day entries, then observations under guardian role permissions with authoritative attribution stamping. U1: profiles carries birth_year/relationship through this path; transferred_at is tolerated-but-never-read. #131: profiles carries mode through this path. Same-date day_entries collisions union tags onto the surviving row (R7, issue #3 gap-closure plan U4) while flow/note stay last-writer-wins - except that a tombstoned row always has flow forced to none, same as note/tags (issue #224). Observations: a brand-new row colliding with an already-live sibling on (profile_id, local_date, category, code) resolves head-to-head (newer updated_at wins, ulid tiebreak) with the loser becoming a payload-free tombstone - the child-table analogue of the day_entries tag union, since there is no array to union here (see 20260908160000_observations.sql''s header). A per-day (profile_id, local_date) cap of 200 live observations is enforced in this RPC, not a CHECK. p_observations defaults to an empty array so a pre-#240 2-argument call keeps working unchanged. Issue #159: day_entries now carries source/source_id/import_id (client-authored provenance, closed-set source check, partial-unique (profile_id, source, source_id) index for import dedup) through this path exactly like every other day_entries column, with a v_row ? ''key'' containment guard on all three so an old client omitting them never nulls an already-stored value (the U1/#131 pattern); observations gains import_id with the same containment guard, and source_id now gets it too (closing a pre-existing #240 gap); source itself now gets the same guard as day_entries.source (review finding: an omitted key coalescing to ''manual'' is not distinguishable from an explicit ''manual'' without one). Provenance is never cleared on a tombstone on either table (source_id/import_id survive a day_entries or observations delete, reversing #240''s original source_id-clearing on an observations tombstone) so a deleted row stays recognisable to a future re-import. Issue #180 review fix: v_local_date is now derived from observed_at/tz (when observed_at is present) immediately after v_tz is resolved, ahead of the stored-row lookup, the same-date (category, code) collision dedup, and the per-day cap, so those checks -- and v_obs_check_collision''s own date-move detection -- always run against the same local_date the observations_derive_local_date trigger will independently recompute; previously they ran against the stale client-supplied local_date key, letting a push (or an observed_at-only update) land on a different day than what was checked.';

revoke execute on function public.sync_push(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb) to authenticated;

