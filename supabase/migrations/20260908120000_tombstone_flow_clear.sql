-- Migration: 20260908120000_tombstone_flow_clear.sql
-- Fixes issue #224 (P1, epic: Privacy & Compliance): a tombstoned (soft-
-- deleted) day_entries row kept its `flow` value on the server forever,
-- even though both the schema comment on public.day_entries
-- ("tombstones keep the id but carry no payload",
-- 20260903014208_initial_sync_schema.sql) and the client's own doc comment
-- (lib/data/db/storage.dart) say a tombstone should carry no payload.
-- `flow` is the most sensitive single column on the row, and there is no
-- purge job that ever removes tombstones (tracked separately, and this fix
-- is the safety precondition that retention job's design assumes).
--
-- Per "do not edit a merged migration in place", this create-or-replaces
-- sync_push from its latest body (20260906200000_same_date_tag_merge.sql)
-- with three tombstone-producing sites touched - every place that can
-- leave a day_entries row with deleted_at not null needs the same fix, not
-- only the direct client soft-delete path the issue called out by line
-- number:
--   1. The direct tombstone branch (client pushes deleted_at not null):
--      alongside the existing v_tags := '[]' / v_note := null clearing,
--      now also sets v_flow := 'none' before the insert/update below it.
--   2. The same-date resolver's "incoming wins" branch: the losing
--      *existing* row is tombstoned by a direct UPDATE that already
--      cleared tags/note but left flow untouched - now also sets
--      flow = 'none' in that same statement.
--   3. The same-date resolver's "incoming loses" branch: the *incoming*
--      row itself becomes the tombstone (stored via the same insert/update
--      as case 1) - now also sets v_flow := 'none' alongside the existing
--      v_tags/v_note reset, so the row written for it carries no payload
--      either.
-- Nothing else changes: winner/loser selection, tombstone stamps, role
-- checks, attribution stamping, the advisory lock, row-count caps, and key
-- allow-lists are all untouched, matching every other create-or-replace of
-- this function.
--
-- The one-off backfill below cleans up every tombstone already sitting on
-- the server (a payload leak that has existed since the schema shipped),
-- and the new day_entries_tombstone_flow_check CHECK constraint is the
-- structural guard (issue #224 AC5): a table-level constraint, mirroring
-- the enforcement precedent set for tags (day_entries_tags_check is the
-- real backstop over the in-RPC tag validation per AGENTS.md), so *any*
-- future write path - a different RPC, a raw admin fix, a migration that
-- forgets this history - fails loudly instead of silently reintroducing
-- payload on a tombstone.

-- ---------------------------------------------------------------------------
-- 1. sync_push - tombstone branches now clear flow to 'none' too.
-- ---------------------------------------------------------------------------

create or replace function public.sync_push(p_profiles jsonb, p_day_entries jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  c_max_rows constant integer := 500;
  c_ulid constant text := '^[0-9A-HJKMNP-TV-Z]{26}$';
  c_profile_keys constant text[] := array[
    'id', 'display_name', 'is_minor', 'sort_order', 'archived_at',
    'created_at', 'updated_at', 'deleted_at',
    -- U1: profile subject metadata, syncable like any other profile column
    'birth_year', 'relationship',
    -- tolerated but never read
    'user_id', 'server_version', 'transferred_at'];
  c_day_entry_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version', 'logged_by_user_id', 'last_modified_by_user_id'];

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
  if jsonb_array_length(p_profiles) > c_max_rows then
    raise exception 'p_profiles exceeds % rows', c_max_rows
      using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_array_length(p_day_entries) > c_max_rows then
    raise exception 'p_day_entries exceeds % rows', c_max_rows
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
           birth_year, relationship)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at,
           v_birth_year, v_relationship);
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
                 birth_year = case when v_row ? 'birth_year' then v_birth_year else v_stored_profile.birth_year end,
                 relationship = case when v_row ? 'relationship' then v_relationship else v_stored_profile.relationship end
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
          (id, profile_id, local_date, tz, flow, tags, note, updated_at, deleted_at, logged_by_user_id, last_modified_by_user_id)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note, v_updated_at, v_deleted_at, v_uid, v_uid)
        returning * into v_stored;
      else
        update public.day_entries
           set profile_id = v_profile_id,
               local_date = v_local_date,
               tz = v_tz,
               flow = v_flow,
               tags = v_tags,
               note = v_note,
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

  return jsonb_build_object(
    'resolved', v_resolved,
    'rejected', v_rejected,
    'server_now', now());
end;
$$;

comment on function public.sync_push(jsonb, jsonb) is
  'Batch upsert of profiles then day entries under guardian role permissions with authoritative attribution stamping. U1: profiles carries birth_year/relationship through this path; transferred_at is tolerated-but-never-read (ownership state, written only by accept_ownership_transfer). Same-date collisions union tags onto the surviving row (R7, issue #3 gap-closure plan U4) while flow/note stay last-writer-wins - except that a row this resolver or the client itself tombstones always has flow forced to none, same as note/tags (issue #224).';

revoke execute on function public.sync_push(jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. One-off backfill: every tombstone already on the server predates this
--    fix and may still carry its pre-deletion flow value.
-- ---------------------------------------------------------------------------

update public.day_entries
   set flow = 'none'
 where deleted_at is not null
   and flow <> 'none';

-- ---------------------------------------------------------------------------
-- 3. Structural guard (issue #224 AC5): a table CHECK constraint, not just
--    an RPC-level fix, so a *future* write path - a different RPC, a raw
--    admin fix, a migration that forgets this history - cannot silently
--    reintroduce payload on a tombstoned row. Mirrors the precedent
--    day_entries_tags_check already sets (AGENTS.md: "the table CHECK is
--    the whole enforcement mechanism", since the in-RPC validation it backs
--    up was itself silently dropped by an earlier create-or-replace).
--    Safe to add as a validating constraint (not NOT VALID) because the
--    backfill above has already cleared every existing violation.
-- ---------------------------------------------------------------------------

alter table public.day_entries
  add constraint day_entries_tombstone_flow_check
  check (deleted_at is null or flow = 'none');

comment on constraint day_entries_tombstone_flow_check on public.day_entries is
  'A tombstoned row (deleted_at is not null) always carries flow = none - the structural backstop for issue #224, independent of which code path wrote the row.';
