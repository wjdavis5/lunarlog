-- sync_push: the single hardened push RPC (plan 2026-09-02-001, KTD3/KTD5).
--
-- Contract
--   sync_push(p_profiles jsonb, p_day_entries jsonb) returns jsonb
--
--   Both arguments must be JSON arrays of at most 500 rows, otherwise the
--   whole call raises (invalid_parameter_value). Rows are processed profiles
--   first, then day entries, each inside its own exception block: any failure
--   (unknown key, malformed id, bad flow, unparseable date, CHECK or FK
--   violation, RLS violation) rejects only that row with the opaque entry
--   {"id": <payload id>, "rejected": true} and the rest of the batch commits.
--   The function is therefore not an existence oracle. Any user_id or
--   server_version in a payload row is never read: user_id comes from the
--   column default (auth.uid()) and server_version from the trigger.
--
--   Per-id last-writer-wins guard: a stored row is overwritten only when the
--   incoming updated_at is greater, or equal and the incoming row is a
--   tombstone (delete wins the tie). A declined incoming row (older, or
--   equal-and-live) is answered with the server's stored copy in `resolved`.
--
--   Same-date resolver (KTD5): on every write that leaves a live day entry
--   (insert, overwrite, or revival of a tombstone) the other live row for
--   (user_id, profile_id, local_date), if any, competes: greater updated_at
--   wins, tie -> lexicographically smaller id (byte order). The loser is
--   tombstoned with deleted_at = updated_at = winner.updated_at, note = null,
--   tags = '[]'; the loser's server copy is returned in `resolved` (whether
--   it was the stored row or the incoming one).
--
--   Tombstones written by this function never carry payload: day entries
--   store note = null and tags = '[]'; profiles store display_name = ''.
--
--   Response: {"resolved": [<server row + "table">...],
--              "rejected": [{"id": ..., "rejected": true}...],
--              "server_now": <timestamptz>}
--   Every `resolved` element is to_jsonb(row) of the server's current copy
--   plus a "table" key ("profiles" | "day_entries").

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
    -- tolerated but never read
    'user_id', 'server_version'];
  c_day_entry_keys constant text[] := array[
    'id', 'profile_id', 'local_date', 'tz', 'flow', 'tags', 'note',
    'updated_at', 'deleted_at',
    -- tolerated but never read
    'user_id', 'server_version'];

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
begin
  if v_uid is null then
    raise exception 'sync_push requires an authenticated user'
      using errcode = 'insufficient_privilege';
  end if;

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
      if v_deleted_at is not null then
        -- tombstones carry no payload
        v_display_name := '';
      else
        v_display_name := coalesce(v_row ->> 'display_name', '');
      end if;

      select * into v_stored_profile
        from public.profiles
       where id = v_id and user_id = v_uid
       for update;

      if not found then
        insert into public.profiles
          (id, display_name, is_minor, sort_order, archived_at, created_at, updated_at, deleted_at)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at);
      else
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
                 deleted_at = v_deleted_at
           where id = v_id and user_id = v_uid;
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
    exception when others then
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
        -- tombstones carry no payload
        v_tags := '[]'::jsonb;
        v_note := null;
      else
        v_tags := coalesce(v_row -> 'tags', '[]'::jsonb);
        if jsonb_typeof(v_tags) <> 'array' then
          raise exception 'tags is not an array';
        end if;
        v_note := v_row ->> 'note';
      end if;

      select * into v_stored
        from public.day_entries
       where id = v_id and user_id = v_uid
       for update;

      if found then
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
         where user_id = v_uid
           and profile_id = v_profile_id
           and local_date = v_local_date
           and deleted_at is null
           and id <> v_id
         for update;

        if found then
          v_incoming_wins := v_updated_at > v_other.updated_at
            or (v_updated_at = v_other.updated_at
                and (v_id collate "C") < (v_other.id collate "C"));
          if v_incoming_wins then
            update public.day_entries
               set deleted_at = v_updated_at,
                   updated_at = v_updated_at,
                   note = null,
                   tags = '[]'::jsonb
             where id = v_other.id and user_id = v_uid
             returning * into v_other;
            v_resolved := v_resolved
              || (to_jsonb(v_other) || jsonb_build_object('table', 'day_entries'));
          else
            -- the incoming row loses: store it as a tombstone at the winner's time
            v_deleted_at := v_other.updated_at;
            v_updated_at := v_other.updated_at;
            v_tags := '[]'::jsonb;
            v_note := null;
          end if;
        end if;
      end if;

      if v_stored.id is null then
        insert into public.day_entries
          (id, profile_id, local_date, tz, flow, tags, note, updated_at, deleted_at)
        values
          (v_id, v_profile_id, v_local_date, v_tz, v_flow, v_tags, v_note, v_updated_at, v_deleted_at)
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
               deleted_at = v_deleted_at
         where id = v_id and user_id = v_uid
         returning * into v_stored;
      end if;

      if v_incoming_wins is false then
        -- the incoming row was tombstoned by resolution: return its server copy
        v_resolved := v_resolved
          || (to_jsonb(v_stored) || jsonb_build_object('table', 'day_entries'));
      end if;
    exception when others then
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
  'Batch upsert of profiles then day entries under RLS with per-row rejection, LWW guard, and the same-date resolver (KTD3/KTD5).';

revoke execute on function public.sync_push(jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb) to authenticated;
