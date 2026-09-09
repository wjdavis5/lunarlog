-- Migration: 20260908200000_flow_model.sql
-- Issue #247 (P1, epic: tracking-model): flow model -- superHeavy, spotting
-- split out into its own observations category, explicit not-bleeding.
--
-- Scope (see the issue's acceptance criteria and this run's binding design
-- decisions):
--   1. `day_entries_flow_check` is re-emitted (drop + add, same pattern
--      `20260903170000_tags_string_array_check.sql` used for
--      `day_entries_tags_check`) with two new values: `super_heavy` (Clue's
--      `very_heavy` -- a fourth, heaviest bleed level) and `not_bleeding`
--      (an explicit "not bleeding today" assertion, distinct from a day
--      with no flow entry at all -- `flow` stays `not null`, defaulting to
--      `'none'`, exactly as before; `not_bleeding` is a new, separate
--      value, never a rename of `none`). Existing rows are unaffected: no
--      UPDATE touches `flow`, and every value the old CHECK accepted is
--      still accepted.
--   2. `sync_push` (`public.sync_push(jsonb, jsonb, jsonb)`) is
--      `create or replace`d with the SAME 3-arg signature, body copied
--      VERBATIM from `20260908180000_timezone_contract.sql` (the latest
--      version on `main` as of this migration's dispatch) with exactly one
--      substantive change: the `v_flow not in (...)` allow-list gains
--      `'super_heavy'` and `'not_bleeding'`. Every comment, every other
--      line, is untouched -- diff the two files' `sync_push` bodies to
--      confirm. `revoke`/`grant` are re-issued, matching every prior
--      `sync_push` redefinition's own pattern.
--   3. Spotting backfill: every **live** `day_entries` row whose `flow` is
--      still the deprecated `'spotting'` value (Issue #247: `FlowLevel
--      .spotting` is kept only as a client-side read alias -- this
--      migration does not touch `day_entries.flow` itself, so old clients
--      that still write `'spotting'` keep working) gets a matching
--      `observations` row inserted (`category: 'spotting', code:
--      'spotting'`), so the UI can read spotting from the observations
--      layer per design decision 3 (mappers.dart's `flowToDomain` maps a
--      stored `spotting` row to the domain `notBleeding` value; the
--      accompanying observation is what actually surfaces "spotting" to
--      the user). Idempotent via a deterministic id
--      (`substr(upper(md5(day_entry_id || ':flow:spotting')), 1, 26)`,
--      namespaced with a `flow:` segment so it can never collide with the
--      tag backfill's own `md5(day_entry_id || ':' || tag)` keyspace) and
--      `on conflict (id) do nothing` -- re-running this migration (a local
--      `db reset` replaying every migration from scratch) never
--      duplicates a row. Trigger-storm-safe: `observations_after_change
--      _signal` is disabled for the single backfill INSERT and replaced
--      with one explicit `sync_signals` touch per affected profile
--      afterwards, exactly mirroring `20260908160000_observations.sql`'s
--      own tag-backfill (its header explains the review finding this
--      pattern fixes). `day_entries.flow` itself is left untouched by
--      this backfill -- the deprecated alias keeps old clients working,
--      per the issue's global assumption #7 (existing codes/values are
--      never renamed, only extended).
--   4. Issue #303 (SQL `flow_level` domain, deferred): NOT done here.
--      #303 would collapse this migration's `day_entries_flow_check` list
--      and `sync_push`'s inline `v_flow not in (...)` list into one
--      `create domain public.flow_level` referenced from both places
--      (finding D-10: a three-place hand-kept list). That is a real
--      refactor -- migrating the column's type, updating every reference,
--      re-proving RLS/grants against a domain-typed column -- not a
--      one-line addition, so it is out of scope for this migration
--      (which only adds two values to the existing three-place list) and
--      is left to #303, which already tracks it and blocks on nothing
--      this migration does.
--   5. Review follow-up (PR #335): `public.enqueue_caregiver_alerts()` is
--      re-emitted from its LATEST body (`20260908190000_bulk_import.sql`,
--      which carries the `lunarlog.bulk_import` GUC early-return) --
--      before this fix its `v_is_bleed`/prior-bleed-window/
--      `v_is_high_severity` checks used `flow <> 'none'` / `flow =
--      'heavy'`, which (a) treated the deprecated `spotting` value and
--      the new `not_bleeding` value as a bleed, wrongly firing
--      `cycle_start`/`logged` alerts for both, and (b) never recognised
--      `super_heavy` as high severity. Now: `v_is_bleed`/the prior-bleed
--      window both use `flow in ('light', 'medium', 'heavy',
--      'super_heavy')` (dropping `spotting` from the bleed set), and
--      `v_is_high_severity` uses `flow in ('heavy', 'super_heavy')`.
--      Every comment and every other line is untouched -- diff the two
--      files' `enqueue_caregiver_alerts()` bodies to confirm the only
--      changes are these three flow literals. `revoke` is re-issued.
--   6. Review follow-up (PR #335): `public.bulk_import_entries(uuid,
--      jsonb)` is re-emitted VERBATIM from `20260908190000_bulk_import
--      .sql`'s body (every comment untouched) with only the flow
--      allow-list updated from `('none', 'spotting', 'light', 'medium',
--      'heavy')` to `('none', 'spotting', 'light', 'medium', 'heavy',
--      'super_heavy', 'not_bleeding')`, so an imported row carrying
--      either new value is no longer rejected as `flow is not a known
--      level`. The tombstone-forced `'none'` branch is unchanged.
--      `revoke`/`grant` are re-issued.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. day_entries_flow_check: re-emitted with super_heavy/not_bleeding.
-- ---------------------------------------------------------------------------

alter table public.day_entries
  drop constraint if exists day_entries_flow_check,
  add constraint day_entries_flow_check
    check (flow in ('none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy'));

-- ---------------------------------------------------------------------------
-- 2. Spotting backfill: one observations row per live spotting day_entries
--    row. See this migration's header, item 3.
-- ---------------------------------------------------------------------------

alter table public.observations disable trigger observations_after_change_signal;

insert into public.observations (
  id, day_entry_id, profile_id, local_date, tz, category, code, source,
  excluded, logged_by_user_id, last_modified_by_user_id, created_at, updated_at
)
select
  substr(upper(md5(de.id || ':flow:spotting')), 1, 26),
  de.id,
  de.profile_id,
  de.local_date,
  de.tz,
  'spotting',
  'spotting',
  'manual',
  false,
  de.logged_by_user_id,
  de.last_modified_by_user_id,
  de.updated_at,
  de.updated_at
from public.day_entries de
where de.deleted_at is null
  and de.flow = 'spotting'
on conflict (id) do nothing;

alter table public.observations enable trigger observations_after_change_signal;

-- One explicit sync_signals touch per profile actually touched by the
-- backfill above -- mirrors 20260908160000_observations.sql's own
-- tag-backfill precedent exactly (see that migration's header for why:
-- a content-free wake signal, harmless to re-touch on a no-op re-run).
insert into public.sync_signals (profile_id, updated_at)
select distinct de.profile_id, now()
  from public.day_entries de
 where de.deleted_at is null
   and de.flow = 'spotting'
on conflict (profile_id) do update set updated_at = excluded.updated_at;

-- ---------------------------------------------------------------------------
-- 3. sync_push: create or replace, same 3-arg signature, body copied
--    verbatim from 20260908180000_timezone_contract.sql except for the
--    flow allow-list (see this migration's header, item 2). Diff the two
--    files' sync_push bodies to confirm.
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
      -- Issue #247: super_heavy/not_bleeding added to the allow-list --
      -- the only substantive change to this function's body versus
      -- 20260908180000_timezone_contract.sql (see this migration's
      -- header, item 2).
      if v_flow not in ('none', 'spotting', 'not_bleeding', 'light', 'medium', 'heavy', 'super_heavy') then
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
  'Batch upsert of profiles, day entries, then observations under guardian role permissions with authoritative attribution stamping. U1: profiles carries birth_year/relationship through this path; transferred_at is tolerated-but-never-read. #131: profiles carries mode through this path. Same-date day_entries collisions union tags onto the surviving row (R7, issue #3 gap-closure plan U4) while flow/note stay last-writer-wins - except that a tombstoned row always has flow forced to none, same as note/tags (issue #224). Observations: a brand-new row colliding with an already-live sibling on (profile_id, local_date, category, code) resolves head-to-head (newer updated_at wins, ulid tiebreak) with the loser becoming a payload-free tombstone - the child-table analogue of the day_entries tag union, since there is no array to union here (see 20260908160000_observations.sql''s header). A per-day (profile_id, local_date) cap of 200 live observations is enforced in this RPC, not a CHECK. p_observations defaults to an empty array so a pre-#240 2-argument call keeps working unchanged. Issue #159: day_entries now carries source/source_id/import_id (client-authored provenance, closed-set source check, partial-unique (profile_id, source, source_id) index for import dedup) through this path exactly like every other day_entries column, with a v_row ? ''key'' containment guard on all three so an old client omitting them never nulls an already-stored value (the U1/#131 pattern); observations gains import_id with the same containment guard, and source_id now gets it too (closing a pre-existing #240 gap); source itself now gets the same guard as day_entries.source (review finding: an omitted key coalescing to ''manual'' is not distinguishable from an explicit ''manual'' without one). Provenance is never cleared on a tombstone on either table (source_id/import_id survive a day_entries or observations delete, reversing #240''s original source_id-clearing on an observations tombstone) so a deleted row stays recognisable to a future re-import. Issue #180 review fix: v_local_date is now derived from observed_at/tz (when observed_at is present) immediately after v_tz is resolved, ahead of the stored-row lookup, the same-date (category, code) collision dedup, and the per-day cap, so those checks -- and v_obs_check_collision''s own date-move detection -- always run against the same local_date the observations_derive_local_date trigger will independently recompute; previously they ran against the stale client-supplied local_date key, letting a push (or an observed_at-only update) land on a different day than what was checked. Issue #247: v_flow''s allow-list gains super_heavy/not_bleeding -- the only substantive change from 20260908180000_timezone_contract.sql''s body.';

revoke execute on function public.sync_push(jsonb, jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. enqueue_caregiver_alerts(): review follow-up (PR #335, item 1 above).
--    Re-emitted from its latest body verbatim except the three flow
--    literals -- see this migration's header, item 5.
-- ---------------------------------------------------------------------------

create or replace function public.enqueue_caregiver_alerts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_writer_id uuid;
  v_is_bleed boolean;
  v_prev_bleed boolean;
  v_is_cycle_start boolean;
  v_is_high_severity boolean;
  v_kind text;
  v_pref record;
  v_cadence text;
  v_pushes_today bigint;
begin
  -- Issue #167: see touch_sync_signal()'s identical guard above -- a bulk
  -- import must not fan out into one notification_outbox row per eligible
  -- guardian per imported row.
  if coalesce(current_setting('lunarlog.bulk_import', true), '') = 'on' then
    return null;
  end if;

  -- A tombstoned write carries no meaningful "someone logged an entry"
  -- event.
  if new.deleted_at is not null then
    return null;
  end if;

  -- sync_push stamps last_modified_by_user_id from the caller's own
  -- auth.uid() (see 20260904010000_multi_guardian_schema.sql); a legacy or
  -- direct-insert row with it null falls back to user_id. This is the
  -- self-authored-event suppression the issue asks to verify and pin
  -- (AC3): a guardian's own edit synced from their second device carries
  -- their own id here and never pages them.
  v_writer_id := coalesce(new.last_modified_by_user_id, new.user_id);

  v_is_bleed := new.flow in ('light', 'medium', 'heavy', 'super_heavy');

  -- #6 (review): lib/domain/episodes/episodes.dart's deriveEpisodes() merges
  -- bleed dates at most 2 days apart into the same episode (a one-day
  -- non-bleed gap does not split it) -- probing only local_date - 1 missed
  -- that merge and flagged the day after a one-day gap as a false
  -- cycle_start. Checking the full [local_date - 2, local_date - 1] window
  -- for any prior bleed day matches deriveEpisodes' own rule exactly.
  select exists (
    select 1 from public.day_entries
     where profile_id = new.profile_id
       and local_date >= new.local_date - 2
       and local_date < new.local_date
       and deleted_at is null
       and flow in ('light', 'medium', 'heavy', 'super_heavy')
  ) into v_prev_bleed;

  -- R7: a cycle start is a bleed day with no bleed day in the merge window
  -- (or nothing at all -- v_prev_bleed is false either way).
  v_is_cycle_start := v_is_bleed and not v_prev_bleed;

  -- Q1: no severity marker exists in the tag taxonomy; heavy flow alone
  -- stands in for "high severity" (see 20260906220000's header).
  v_is_high_severity := new.flow in ('heavy', 'super_heavy');

  v_kind := case
    when v_is_cycle_start then 'cycle_start'
    when v_is_high_severity then 'high_severity'
    else 'logged'
  end;

  for v_pref in
    select g.user_id as guardian_user_id,
           p.quiet_hours_start, p.quiet_hours_end, p.time_zone,
           p.log_cadence, p.cycle_start_cadence, p.high_severity_cadence
      from public.notification_preferences p
      join public.profile_guardians g
        on g.profile_id = p.profile_id
       and g.user_id = p.user_id
     where p.profile_id = new.profile_id
       and g.status = 'accepted'
       and g.user_id is distinct from v_writer_id
       and p.alert_on_log
       -- R7: several narrowings enabled at once still yield at most one
       -- row per entry write -- this is a single boolean expression, not
       -- one insert per narrowing.
       and (not p.alert_on_cycle_start_only or v_is_cycle_start)
       and (not p.alert_on_high_severity or v_is_high_severity)
  loop
    -- Issue #125: the cadence column governing this event's kind decides
    -- delivery. 'off' is the per-kind kill switch the issue scopes; the
    -- kind-level default ('immediate') keeps pre-#125 behaviour for every
    -- existing row.
    v_cadence := case v_kind
      when 'cycle_start' then v_pref.cycle_start_cadence
      when 'high_severity' then v_pref.high_severity_cadence
      else v_pref.log_cadence
    end;

    if v_cadence = 'off' then
      continue;
    end if;

    if v_cadence = 'daily_digest' then
      -- Held for the digest sweep: deliver_after = 'infinity' keeps the
      -- row out of push-dispatch's `deliver_after <= now()` claim
      -- predicate until sweep_alert_digests() collapses the group at the
      -- guardian's chosen digest time.
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 3: the daily ceiling first, so the
    -- overflow rolls into the next digest rather than being coalesced
    -- away or dropped. Counts every non-held, non-missed_entry row for
    -- this (guardian, profile) created since the guardian's local
    -- midnight -- sent or not, each is one push made today.
    select count(*) into v_pushes_today
      from public.notification_outbox o
     where o.recipient_user_id = v_pref.guardian_user_id
       and o.profile_id = new.profile_id
       and o.kind <> 'missed_entry'
       and o.deliver_after < 'infinity'::timestamptz
       and o.created_at >= public.local_day_start(now(), v_pref.time_zone);

    if v_pushes_today >= public.alert_daily_push_ceiling() then
      insert into public.notification_outbox
        (profile_id, recipient_user_id, kind, deliver_after)
      values (
        new.profile_id,
        v_pref.guardian_user_id,
        v_kind,
        'infinity'::timestamptz
      );
      continue;
    end if;

    -- Immediate path, issue #125 step 2: the coalescing window. Skip when
    -- a row of the same (recipient, profile, kind) already exists inside
    -- the window -- regardless of sent_at, because under a healthy
    -- webhook every row is sent within milliseconds and an unsent-only
    -- guard would never suppress anything.
    if exists (
      select 1 from public.notification_outbox o
       where o.recipient_user_id = v_pref.guardian_user_id
         and o.profile_id = new.profile_id
         and o.kind = v_kind
         and o.created_at > now() - public.alert_coalesce_window()
    ) then
      continue;
    end if;

    insert into public.notification_outbox
      (profile_id, recipient_user_id, kind, deliver_after)
    values (
      new.profile_id,
      v_pref.guardian_user_id,
      v_kind,
      public.resolve_deliver_after(
        now(), v_pref.quiet_hours_start, v_pref.quiet_hours_end, v_pref.time_zone
      )
    );
  end loop;

  return null; -- AFTER trigger; return value is ignored.
end;
$$;

-- Carries the comment forward, extended for the new guard.
comment on function public.enqueue_caregiver_alerts() is
  'AFTER INSERT and AFTER UPDATE trigger function on day_entries (Issue #5, '
  'KTD4; two separate triggers as of the #7 review fix, since a single '
  'combined trigger cannot WHEN-filter both events with one expression): '
  'fans a live write out into one public.notification_outbox row per '
  'eligible, non-writer guardian. The UPDATE trigger''s WHEN clause skips '
  'ownership-only updates and no-op resaves (#7). Runs independently of '
  'public.touch_sync_signal()''s sync_signals trigger -- the two write to '
  'different tables and neither depends on the other''s firing order. '
  'As of Issue #125 each guardian''s per-kind cadence column decides '
  'delivery: off skips, daily_digest holds the row for '
  'sweep_alert_digests(), and immediate rows are subject to the '
  'per-guardian daily push ceiling (overflow rolls into the next digest) '
  'and the alert_coalesce_window() coalescing guard. Issue #167: no-ops '
  'entirely while lunarlog.bulk_import = ''on'' -- a bulk import is not a '
  '"someone logged an entry" event and must not page anyone.';

revoke execute on function public.enqueue_caregiver_alerts() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. bulk_import_entries(): review follow-up (PR #335, item 2 above).
--    Re-emitted verbatim except the flow allow-list -- see this
--    migration's header, item 6.
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
          when p.flow not in ('none', 'spotting', 'light', 'medium', 'heavy', 'super_heavy', 'not_bleeding') then 'flow is not a known level'
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
  'note length, source_id length, updated_at). A tombstone row (deleted_at '
  'present) has its flow/tags/note forced to the empty payload rather than '
  'validated or rejected, mirroring sync_push. Two independent '
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
