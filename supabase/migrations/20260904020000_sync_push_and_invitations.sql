-- Migration: 20260904020000_sync_push_and_invitations.sql
-- Implements Issue #8 (Unit U2):
-- 1. sync_push RPC guardian authorization and authoritative attribution stamping.
-- 2. create_guardian_invitation RPC.
-- 3. accept_guardian_invitation RPC.
-- 4. revoke_guardian RPC.

-- ---------------------------------------------------------------------------
-- 1. Updated sync_push RPC
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
    -- tolerated but never read
    'user_id', 'server_version'];
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
          (id, display_name, is_minor, sort_order, archived_at, created_at, updated_at, deleted_at)
        values
          (v_id, v_display_name, v_is_minor, v_sort_order, v_archived_at, v_created_at, v_updated_at, v_deleted_at);
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
                 deleted_at = v_deleted_at
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
            update public.day_entries
               set deleted_at = v_updated_at,
                   updated_at = v_updated_at,
                   note = null,
                   tags = '[]'::jsonb,
                   last_modified_by_user_id = v_uid
             where id = v_other.id
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
  'Batch upsert of profiles then day entries under guardian role permissions with authoritative attribution stamping.';

revoke execute on function public.sync_push(jsonb, jsonb) from public, anon;
grant execute on function public.sync_push(jsonb, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. create_guardian_invitation RPC
-- ---------------------------------------------------------------------------

create or replace function public.create_guardian_invitation(
  p_profile_id text,
  p_role text,
  p_recipient_label text,
  p_token_hash text,
  p_ttl_hours int default 48
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invitation_id uuid;
  v_expires_at timestamptz;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian', 'co_parent']) then
    raise exception 'caller lacks permission to invite guardians for this profile'
      using errcode = 'insufficient_privilege';
  end if;

  if p_role not in ('co_parent', 'caregiver', 'viewer') then
    raise exception 'invalid role: %', p_role using errcode = 'invalid_parameter_value';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  v_expires_at := now() + (coalesce(p_ttl_hours, 48) || ' hours')::interval;

  insert into public.guardian_invitations
    (profile_id, invited_by, token_hash, role, recipient_label, expires_at)
  values
    (p_profile_id, v_uid, p_token_hash, p_role, p_recipient_label, v_expires_at)
  returning id into v_invitation_id;

  return jsonb_build_object(
    'id', v_invitation_id,
    'profile_id', p_profile_id,
    'role', p_role,
    'expires_at', v_expires_at
  );
end;
$$;

revoke all on function public.create_guardian_invitation(text, text, text, text, int) from public, anon;
grant execute on function public.create_guardian_invitation(text, text, text, text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. accept_guardian_invitation RPC
-- ---------------------------------------------------------------------------

create or replace function public.accept_guardian_invitation(
  p_token_hash text,
  p_guardian_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invite public.guardian_invitations%rowtype;
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  select * into v_invite
    from public.guardian_invitations
   where token_hash = p_token_hash
   for update;

  if not found then
    raise exception 'invitation not found' using errcode = 'no_data_found';
  end if;

  if v_invite.accepted_at is not null then
    raise exception 'invitation already accepted' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_invite.revoked_at is not null then
    raise exception 'invitation was revoked' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_invite.expires_at <= now() then
    raise exception 'invitation has expired' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Cannot accept an invitation if already an active guardian
  if exists (
    select 1 from public.profile_guardians
     where profile_id = v_invite.profile_id
       and user_id = v_uid
       and status = 'accepted'
  ) then
    raise exception 'user is already an active guardian of this profile'
      using errcode = 'unique_violation';
  end if;

  -- Add or revive membership in profile_guardians
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, invited_by, updated_at)
  values
    (v_invite.profile_id, v_uid, v_invite.role, 'accepted', p_guardian_display_name, v_invite.invited_by, now())
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = now();

  -- Mark invitation as accepted
  update public.guardian_invitations
     set accepted_at = now(),
         accepted_by = v_uid
   where id = v_invite.id;

  select * into v_profile
    from public.profiles
   where id = v_invite.profile_id;

  return jsonb_build_object(
    'profile_id', v_profile.id,
    'profile_name', v_profile.display_name,
    'role', v_invite.role
  );
end;
$$;

revoke all on function public.accept_guardian_invitation(text, text) from public, anon;
grant execute on function public.accept_guardian_invitation(text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. revoke_guardian RPC
-- ---------------------------------------------------------------------------

create or replace function public.revoke_guardian(
  p_profile_id text,
  p_target_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target_role text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select role into v_caller_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = v_uid
     and status = 'accepted';

  if v_caller_role is null then
    raise exception 'caller is not a guardian of this profile'
      using errcode = 'insufficient_privilege';
  end if;

  select role into v_target_role
    from public.profile_guardians
   where profile_id = p_profile_id
     and user_id = p_target_user_id
     and status = 'accepted';

  if v_target_role is null then
    -- Already not an active guardian
    return true;
  end if;

  -- Self-leave is always allowed unless caller is the sole primary_guardian
  if v_uid = p_target_user_id then
    if v_caller_role = 'primary_guardian' and (
      select count(*) from public.profile_guardians
       where profile_id = p_profile_id and role = 'primary_guardian' and status = 'accepted'
    ) <= 1 then
      raise exception 'the sole primary guardian cannot leave the profile'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  else
    -- Revoking another user:
    -- primary_guardian can revoke anyone
    -- co_parent can revoke caregiver and viewer only
    if v_caller_role = 'primary_guardian' then
      null;
    elsif v_caller_role = 'co_parent' and v_target_role in ('caregiver', 'viewer') then
      null;
    else
      raise exception 'insufficient permission to revoke this guardian'
        using errcode = 'insufficient_privilege';
    end if;
  end if;

  update public.profile_guardians
     set status = 'revoked',
         updated_at = now()
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  return true;
end;
$$;

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;
