-- Issue #373 (bug 3 of the #369 review follow-ups): minor profiles are
-- never shared -- PRIVACY.md section 5 has said so since the first
-- version of the policy, but 20260909200000_prediction_connections.sql
-- shipped `create_prediction_connection` without an `is_minor` gate, even
-- though it already fetches the `profiles` row (for the Pregnancy-mode
-- check right after it) and that row carries `is_minor`.
--
-- This migration replaces both RPCs with the SAME bodies as
-- 20260909200000 plus one guard each, placed immediately after the
-- profile fetch and before any mutating statement:
--
--   * `create_prediction_connection` refuses to arm an invite for a
--     profile with `is_minor = true`.
--   * `accept_prediction_connection` re-checks it at redemption. The flag
--     is mutable between arming and redemption -- `sync_push` upserts
--     `is_minor` from the client row on every push, and `authenticated`
--     holds a direct column UPDATE grant on it (20260903014208) -- so it is
--     the `profile_modes.mode` situation exactly, and gets the same
--     create-AND-accept treatment.
--
-- Same errcode convention as the Pregnancy gate
-- (`object_not_in_prerequisite_state`, SQLSTATE 55000) so the client's
-- existing PostgREST error mapping needs only a message match. Nothing
-- else changes: no table, policy, grant, trigger, or index is touched;
-- the grants are restated verbatim for explicitness (`create or replace`
-- preserves them regardless).
--
-- Coverage: supabase/tests/prediction_connection_test.sql section 7b.

-- ---------------------------------------------------------------------------
-- 1. create_prediction_connection (20260909200000 body + is_minor gate)
-- ---------------------------------------------------------------------------

create or replace function public.create_prediction_connection(
  p_profile_id text,
  p_token_hash text,
  p_recipient_label text default null,
  p_ttl_hours int default 72
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_mode text;
  v_ttl int;
  v_now timestamptz;
  v_expires_at timestamptz;
  v_connection_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Issue #151: "A primary guardian can create a prediction-only
  -- connection" -- only the accepted primary_guardian, never a co_parent
  -- (the sharer's own cycle data is being exposed; the primary's seat is
  -- also the authority that can later revoke).
  if not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian']) then
    raise exception 'only the accepted primary guardian can share predictions for this profile'
      using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile
    from public.profiles
   where id = p_profile_id
   for update;
  if not found then
    raise exception 'profile not found' using errcode = 'no_data_found';
  end if;

  -- Minor gate (issue #373; PRIVACY.md section 5: minor profiles are
  -- never shared). Checked at create AND accept (below): is_minor is
  -- client-writable and can change between arming a code and its
  -- redemption, exactly like the life-stage mode.
  if v_profile.is_minor then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Pregnancy gate (issue #151; the life-stage mode, not #131's care
  -- mode). Checked at create AND accept (below): the mode can change
  -- between arming a code and its redemption.
  select mode into v_mode
    from public.profile_modes
   where profile_id = p_profile_id;
  if v_mode = 'pregnancy' then
    raise exception 'prediction-only sharing is unavailable while this profile is in Pregnancy mode'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  if p_recipient_label is not null and char_length(p_recipient_label) > 80 then
    raise exception 'recipient_label must be at most 80 characters' using errcode = 'invalid_parameter_value';
  end if;

  v_ttl := coalesce(p_ttl_hours, 72);
  if v_ttl < 1 or v_ttl > 168 then
    raise exception 'p_ttl_hours must be between 1 and 168'
      using errcode = 'invalid_parameter_value';
  end if;

  -- One-connection cap (issue #151): refused server-side, not just in the
  -- UI. A live row -- a still-pending invite or the active connection --
  -- blocks a second. An outstanding-but-expired invite of the caller's
  -- own is first cancelled (cancel-then-create, the ownership_transfers
  -- precedent), so a lapsed code never wedges the feature shut.
  update public.prediction_connections
     set revoked_at = clock_timestamp()
   where profile_id = p_profile_id
     and owner_user_id = v_uid
     and accepted_at is null
     and revoked_at is null
     and expires_at <= clock_timestamp();

  if exists (
    select 1 from public.prediction_connections
     where profile_id = p_profile_id
       and revoked_at is null
  ) then
    raise exception 'this profile already has a prediction-only connection or pending invite'
      using errcode = 'unique_violation';
  end if;

  v_now := clock_timestamp();
  v_expires_at := v_now + (v_ttl || ' hours')::interval;

  insert into public.prediction_connections
    (profile_id, owner_user_id, token_hash, recipient_label, expires_at, created_at)
  values
    (p_profile_id, v_uid, p_token_hash, p_recipient_label, v_expires_at, v_now)
  returning id into v_connection_id;

  return jsonb_build_object(
    'id', v_connection_id,
    'profile_id', p_profile_id,
    'expires_at', v_expires_at
  );
end;
$$;

comment on function public.create_prediction_connection(text, text, text, int) is
  'Arms one prediction-only invite (Issue #151): primary-guardian-only, '
  'refused for a minor''s profile (Issue #373, PRIVACY.md section 5) and '
  'in Pregnancy mode, capped at one live (pending or active) connection '
  'per profile by prediction_connections_one_live_uq with this function '
  'as the friendly error path. The caller supplies a client-side SHA-256 '
  'token hash; the plaintext never reaches the server.';

revoke all on function public.create_prediction_connection(text, text, text, int)
  from public, anon;
grant execute on function public.create_prediction_connection(text, text, text, int)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. accept_prediction_connection (20260909200000 body + is_minor gate)
-- ---------------------------------------------------------------------------

create or replace function public.accept_prediction_connection(
  p_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conn public.prediction_connections%rowtype;
  v_profile public.profiles%rowtype;
  v_mode text;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- Enumeration safety: an unknown hash and a mistyped hash report the
  -- identical message (the format guard above already separates only the
  -- "not even a hash shape" case, which leaks nothing).
  select * into v_conn
    from public.prediction_connections
   where token_hash = p_token_hash
   for update;
  if not found then
    raise exception 'prediction connection not found' using errcode = 'no_data_found';
  end if;

  -- Terminal states, each with its own distinguishable reason (the
  -- accept_guardian_invitation pattern).
  if v_conn.accepted_at is not null then
    raise exception 'prediction connection was already accepted'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if v_conn.revoked_at is not null then
    raise exception 'prediction connection was revoked'
      using errcode = 'object_not_in_prerequisite_state';
  end if;
  if v_conn.expires_at <= clock_timestamp() then
    raise exception 'prediction connection has expired'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- The sharer cannot redeem their own code.
  if v_uid = v_conn.owner_user_id then
    raise exception 'the sharer cannot accept their own prediction connection'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into v_profile
    from public.profiles
   where id = v_conn.profile_id
   for update;
  if not found then
    raise exception 'profile not found' using errcode = 'no_data_found';
  end if;

  -- Minor gate, re-checked at redemption (issue #373): the flag can be
  -- set between arming and redemption, so a code armed for a then-adult
  -- profile refuses once the profile is marked a minor.
  if v_profile.is_minor then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Stale-code guard (the accept_ownership_transfer precedent): the
  -- sharer must still be the profile's accepted primary guardian at
  -- accept time -- a revocation, role change, or ownership handover
  -- between arming and redemption refuses the code.
  if not public.is_guardian_with_roles(
       v_conn.profile_id, v_conn.owner_user_id, array['primary_guardian']) then
    raise exception 'the sharer is no longer the primary guardian of this profile; the code is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Pregnancy gate, re-checked at redemption.
  select mode into v_mode
    from public.profile_modes
   where profile_id = v_conn.profile_id;
  if v_mode = 'pregnancy' then
    raise exception 'prediction-only sharing is unavailable while this profile is in Pregnancy mode'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- A guardian of the profile already sees everything; a prediction-only
  -- seat under them would muddy revocation semantics for no gain.
  if public.is_profile_guardian(v_conn.profile_id, v_uid) then
    raise exception 'you are already a guardian of this profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- One-directional (issue #151): "a recipient of a prediction-only share
  -- cannot simultaneously be a source of one back". Refuse when the
  -- accepting user already holds an ACTIVE connection back to the
  -- sharer's account (pair-level, per the issue's "one back" wording).
  if exists (
    select 1 from public.prediction_connections
     where owner_user_id = v_uid
       and recipient_user_id = v_conn.owner_user_id
       and accepted_at is not null
       and revoked_at is null
  ) then
    raise exception 'cannot share and view predictions with the same person at the same time'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- The cap is re-checked implicitly: a second redemption would have to
  -- get past the "already accepted" guard or the one_live_uq index (the
  -- row for this profile is the one being locked, so a concurrent
  -- second-invite insert for the same profile is serialized here).

  update public.prediction_connections
     set accepted_at = clock_timestamp(),
         recipient_user_id = v_uid
   where id = v_conn.id;

  return jsonb_build_object(
    'profile_id', v_conn.profile_id,
    'profile_name', v_profile.display_name,
    'connection_id', v_conn.id
  );
end;
$$;

comment on function public.accept_prediction_connection(text) is
  'Redeems a prediction-only invite (Issue #151): single-use, expiry- and '
  'revocation-checked, refused for the sharer themself, for an existing '
  'guardian, for a profile whose sharer lost the primary seat, for a '
  'minor''s profile (Issue #373, re-checked at accept), for Pregnancy mode '
  '(re-checked at accept), and for a reciprocal share-with-the-same-person '
  'pair. The recipient gains exactly one thing: read access to '
  'get_prediction_projection() for this profile.';

revoke all on function public.accept_prediction_connection(text) from public, anon;
grant execute on function public.accept_prediction_connection(text) to authenticated;
