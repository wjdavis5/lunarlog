-- Migration: 20260913019000_prediction_minor_gate_durable.sql
--
-- Issue #518 (P1): the "minor profiles are never shared" gate
-- (PRIVACY.md section 5) is not durable, and misses birth_year-derived age.
--
-- Two compounding defects, both closed here (the third - the `v_row ?
-- 'is_minor'` containment guard in sync_push - landed in
-- 20260913016000_sync_push_hardening.sql, since it required re-emitting
-- that function's full body):
--
--   1. The is_minor gate (issue #373, 20260909220000_prediction_connections_minor_gate.sql)
--      runs only at create_prediction_connection and
--      accept_prediction_connection time. Neither upsert_prediction_projection
--      (the sharer's periodic publish) nor get_prediction_projection (the
--      recipient's every read) re-checks it, so a guardian who ticks "this
--      is a minor" on an ALREADY-SHARED profile gets no protection - the
--      outside recipient keeps receiving the child's derived phase dates
--      indefinitely, through both the existing publish and every future
--      read, until someone manually revokes the connection.
--
--   2. Every gate keys ONLY on the is_minor checkbox; birth_year is never
--      consulted, even though the health-sync gate already derives age
--      from it (health_sync_binding.dart:217-222,
--      `now.year - birthYear <= 18`, deliberately `<=` not `<` - see that
--      file's own comment for the year-only-field, fail-closed reasoning
--      issue #296 established). A 12-year-old profile with the box
--      unchecked could be shared under the pre-existing gates.
--
-- Fix:
--   - public.profile_counts_as_minor(is_minor, birth_year): the shared
--     predicate every gate below uses - `is_minor` OR a birth_year-implied
--     age <= 18, mirroring health_sync_binding.dart's own formula exactly
--     (same fail-closed direction, same coarse year-only comparison - a
--     year-only column cannot see the actual birthday, so the whole
--     calendar year an age-18 birthday falls in is treated as still-minor).
--   - create_prediction_connection / accept_prediction_connection
--     (re-emitted from their only prior versions) now call this predicate
--     instead of checking is_minor alone.
--   - upsert_prediction_projection re-checks it: a minor profile deletes
--     any stored projection and returns (mirrors the existing "no active
--     connection" branch's own privacy posture - derived data does not
--     sit on the server unjustified).
--   - get_prediction_projection re-checks it: a minor profile returns null
--     (indistinguishable from "unauthorized" or "unshared", per its
--     existing enumeration-safety posture).
--   - A new BEFORE UPDATE trigger on profiles, enforce_minor_prediction_revocation():
--     when is_minor flips false -> true, revokes every live
--     prediction_connections row for the profile and deletes any stored
--     prediction_projections row, in the SAME statement that made the
--     profile a minor - so the window between "guardian marks minor" and
--     "sharing actually stops" is zero, not "until the next periodic
--     publish/read gate happens to run". A birth_year-implied minority
--     crossing (the calendar-year rollover, with is_minor never touched)
--     is NOT caught by this trigger - no row changes when nothing is
--     written - but is still enforced live by the upsert/get gates above,
--     which re-derive age from birth_year on every call regardless of
--     whether any write ever happens.
--
-- Coverage: supabase/tests/prediction_connection_test.sql (extended).

-- ---------------------------------------------------------------------------
-- 1. Shared minor predicate.
-- ---------------------------------------------------------------------------

create or replace function public.profile_counts_as_minor(
  p_is_minor boolean,
  p_birth_year smallint
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(p_is_minor, false)
    or (p_birth_year is not null
        and extract(year from clock_timestamp())::int - p_birth_year <= 18);
$$;

comment on function public.profile_counts_as_minor(boolean, smallint) is
  'Issue #518: the shared "is this profile a minor" predicate every '
  'prediction-sharing gate uses - is_minor OR a birth_year-implied age <= '
  '18 (mirroring lib/domain/health/health_sync_binding.dart''s '
  '_isMinorNow exactly: <=, not <, since a year-only birth_year cannot see '
  'the actual birthday, so the whole calendar year an 18th birthday falls '
  'in stays treated as minor - the safe, fail-closed direction).';

revoke all on function public.profile_counts_as_minor(boolean, smallint) from public, anon;
grant execute on function public.profile_counts_as_minor(boolean, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. create_prediction_connection (20260909220000 body, gate widened)
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

  -- Issue #518: widened from is_minor alone to also treat a
  -- birth_year-implied age <= 18 as minor.
  if public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

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
  'refused for a minor''s profile - Issue #373/#518: is_minor OR a '
  'birth_year-implied age <= 18, via public.profile_counts_as_minor() - '
  'and in Pregnancy mode, capped at one live (pending or active) '
  'connection per profile by prediction_connections_one_live_uq with this '
  'function as the friendly error path. The caller supplies a client-side '
  'SHA-256 token hash; the plaintext never reaches the server.';

revoke all on function public.create_prediction_connection(text, text, text, int)
  from public, anon;
grant execute on function public.create_prediction_connection(text, text, text, int)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. accept_prediction_connection (20260909220000 body, gate widened)
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

  select * into v_conn
    from public.prediction_connections
   where token_hash = p_token_hash
   for update;
  if not found then
    raise exception 'prediction connection not found' using errcode = 'no_data_found';
  end if;

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

  -- Issue #518: widened from is_minor alone (re-checked at redemption:
  -- the flag, and now the derived age, can both change between arming and
  -- redemption).
  if public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if not public.is_guardian_with_roles(
       v_conn.profile_id, v_conn.owner_user_id, array['primary_guardian']) then
    raise exception 'the sharer is no longer the primary guardian of this profile; the code is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select mode into v_mode
    from public.profile_modes
   where profile_id = v_conn.profile_id;
  if v_mode = 'pregnancy' then
    raise exception 'prediction-only sharing is unavailable while this profile is in Pregnancy mode'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  if public.is_profile_guardian(v_conn.profile_id, v_uid) then
    raise exception 'you are already a guardian of this profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

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
  'minor''s profile (Issue #373/#518: is_minor OR a birth_year-implied age '
  '<= 18, re-checked at accept), for Pregnancy mode (re-checked at '
  'accept), and for a reciprocal share-with-the-same-person pair. The '
  'recipient gains exactly one thing: read access to '
  'get_prediction_projection() for this profile.';

revoke all on function public.accept_prediction_connection(text) from public, anon;
grant execute on function public.accept_prediction_connection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. upsert_prediction_projection: add the minor gate (Issue #518 - this
--    RPC never had one before). Re-emitted from its only prior definition
--    (20260909200000_prediction_connections.sql).
-- ---------------------------------------------------------------------------

create or replace function public.upsert_prediction_projection(
  p_profile_id text,
  p_projection jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if not public.is_guardian_with_roles(
       p_profile_id, v_uid,
       array['primary_guardian', 'co_parent', 'caregiver']) then
    raise exception 'only an accepted guardian of this profile can publish its prediction projection'
      using errcode = 'insufficient_privilege';
  end if;

  if p_projection is null then
    raise exception 'p_projection is required' using errcode = 'invalid_parameter_value';
  end if;

  -- Issue #518: a minor's profile (is_minor, or a birth_year-implied age
  -- <= 18) never gets a stored projection, mirroring the "no active
  -- connection" branch below exactly - any stale row is deleted and the
  -- call is a no-op. This is what makes the durability gap the issue
  -- reports moot: a guardian ticking "this is a minor" now stops the NEXT
  -- publish from ever refreshing a stored snapshot, on top of the
  -- profiles-trigger below that clears any snapshot already stored.
  select * into v_profile from public.profiles where id = p_profile_id;
  if found and public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    delete from public.prediction_projections
     where profile_id = p_profile_id;
    return;
  end if;

  if not exists (
    select 1 from public.prediction_connections
     where profile_id = p_profile_id
       and accepted_at is not null
       and revoked_at is null
  ) then
    delete from public.prediction_projections
     where profile_id = p_profile_id;
    return;
  end if;

  insert into public.prediction_projections
    (profile_id, projection, published_at, published_by)
  values
    (p_profile_id, p_projection, clock_timestamp(), v_uid)
  on conflict (profile_id) do update
    set projection = excluded.projection,
        published_at = excluded.published_at,
        published_by = excluded.published_by;
end;
$$;

comment on function public.upsert_prediction_projection(text, jsonb) is
  'Publishes one profile''s derived-phase snapshot (Issue #151). Issue '
  '#518: refused for a minor''s profile (is_minor OR a birth_year-implied '
  'age <= 18) - any stored snapshot is deleted and the call is a no-op, '
  'the same posture as having no active connection. The payload is '
  'validated by prediction_projections'' trigger and CHECK constraint '
  'against the derived-only allowlist. Allowed only while an active '
  'prediction connection exists; with none, any stored snapshot is '
  'deleted and the call is a no-op, so derived data never sits on the '
  'server unjustified.';

revoke all on function public.upsert_prediction_projection(text, jsonb)
  from public, anon;
grant execute on function public.upsert_prediction_projection(text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. get_prediction_projection: add the minor gate (Issue #518 - this RPC
--    never had one before). Re-emitted from its only prior definition
--    (20260909200000_prediction_connections.sql).
-- ---------------------------------------------------------------------------

create or replace function public.get_prediction_projection(
  p_profile_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.profiles%rowtype;
  v_projection jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if not exists (
    select 1 from public.prediction_connections
     where profile_id = p_profile_id
       and recipient_user_id = v_uid
       and accepted_at is not null
       and revoked_at is null
  ) and not public.is_profile_guardian(p_profile_id, v_uid) then
    return null;
  end if;

  -- Issue #518: a minor's profile (is_minor, or a birth_year-implied age
  -- <= 18) returns null unconditionally - indistinguishable from
  -- "unauthorized" or "unshared", the same enumeration-safety posture the
  -- eligibility check above already has. This is the live-read half of
  -- closing the durability gap: even if a stale projection row somehow
  -- still exists (e.g. a race with the revocation trigger below), no
  -- recipient can ever read it once the profile counts as a minor.
  select * into v_profile from public.profiles where id = p_profile_id;
  if not found or public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    return null;
  end if;

  select projection into v_projection
    from public.prediction_projections
   where profile_id = p_profile_id;

  return v_projection;
end;
$$;

comment on function public.get_prediction_projection(text) is
  'The recipient''s ONLY read path for a shared profile (Issue #151): '
  'returns the published derived-phase snapshot (dates only) to the '
  'active recipient or the profile''s own guardians, and null to everyone '
  'else - an unauthorized caller, an unshared profile, and (Issue #518) a '
  'minor''s profile (is_minor OR a birth_year-implied age <= 18) are all '
  'indistinguishable. The payload''s shape is constrained at write time to '
  'derived phase fields; no raw row can ever reach this function''s return '
  'value.';

revoke all on function public.get_prediction_projection(text) from public, anon;
grant execute on function public.get_prediction_projection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. BEFORE UPDATE trigger on profiles: is_minor flipping false -> true
--    revokes every live prediction_connections row and deletes any stored
--    projection, in the SAME statement.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_minor_prediction_revocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.is_minor and not old.is_minor then
    update public.prediction_connections
       set revoked_at = clock_timestamp()
     where profile_id = new.id
       and revoked_at is null;

    delete from public.prediction_projections
     where profile_id = new.id;
  end if;

  return new;
end;
$$;

comment on function public.enforce_minor_prediction_revocation() is
  'Issue #518: BEFORE UPDATE guard on profiles - when is_minor flips false '
  '-> true (via sync_push or a raw PATCH), every live prediction_connections '
  'row for the profile is revoked and any stored prediction_projections '
  'row is deleted, in the SAME statement that made the profile a minor - '
  'zero window between the flag being set and sharing actually stopping. '
  'A birth_year-implied minority crossing (the calendar-year rollover, '
  'with is_minor never touched) is not caught here - nothing UPDATEs when '
  'no write happens - but is still enforced live by '
  'upsert_prediction_projection()/get_prediction_projection(), which '
  're-derive age from birth_year on every call regardless.';

create trigger profiles_minor_prediction_revocation_guard
  before update on public.profiles
  for each row execute function public.enforce_minor_prediction_revocation();

revoke execute on function public.enforce_minor_prediction_revocation() from public, anon;
