-- Migration: 20260920100000_minor_status_birth_year_authoritative.sql
--
-- Issue #945: converge the SERVER to #820's client-side minor-status
-- derivation discipline, so client and server cannot disagree by
-- construction.
--
-- #820 (d9eaa3f6) made lib/domain/models/profile.dart's deriveMinorStatus()
-- treat a PRESENT birth_year as authoritative (minor iff
-- `currentYear - birthYear <= 18`) and fall back to the stored is_minor flag
-- only when no year exists. The server predicate every minor gate shares,
-- public.profile_counts_as_minor (issue #518,
-- 20260913019000_prediction_minor_gate_durable.sql), instead takes the UNION:
-- `is_minor OR birth_year-implied age <= 18`. So for the window before a
-- client's recomputed flag syncs, a profile whose birth year says ADULT
-- while its stored flag still says true shows the prediction-share
-- affordance (client derives adult) and is refused by the server (union
-- sees the stale flag) - exactly the dead-end-affordance pattern #885 was
-- filed for. The one cell of the truth table that changes: (adult-implying
-- birth_year, is_minor = true) goes refused -> allowed. That is the safe
-- direction: the profile IS an adult by the #295 ruling ("age decides"),
-- every minor-implying year still refuses regardless of the flag, and
-- profiles with no birth year keep today's flag-driven behavior exactly.
--
-- What changes:
--   1. public.profile_counts_as_minor: birth-year-authoritative with the
--      flag as null-year fallback - mirroring deriveMinorStatus() exactly
--      (same coarse `<= 18` year-only comparison, issue #296's fail-closed
--      boundary: the whole calendar year an 18th birthday falls in stays
--      minor). Every gate that already calls this predicate converges with
--      it.
--   2. enforce_minor_prediction_revocation() (the profiles BEFORE UPDATE
--      trigger body, #518): previously keyed on the RAW
--      `new.is_minor and not old.is_minor` flag flip. Now fires on the
--      DERIVED transition - profile_counts_as_minor(new) and not
--      profile_counts_as_minor(old) - so:
--        - a flag flip on a no-year profile still revokes exactly as before
--          (the flag is the fallback and the only signal there);
--        - a birth_year EDIT that crosses into minority now revokes in the
--          same statement (new: with the year authoritative, the edit is
--          the primary way a profile becomes a minor, and #518's
--          zero-window guarantee must follow the decision-maker);
--        - a bare flag flip on a profile with an adult-implying year no
--          longer revokes (the flag is not the decision-maker anymore;
--          create/accept/upsert/get all derive adult for that profile, so
--          a lingering live connection was the only place the stale flag
--          still decided anything).
--        The calendar-year rollover still needs no trigger (nothing UPDATEs
--        when no write happens) and is still enforced live by the
--        upsert/get gates, which re-derive on every call - unchanged from
--        #518's documented posture.
--   3. create_prediction_connection / accept_prediction_connection /
--      upsert_prediction_projection / get_prediction_projection:
--      re-emitted from their current definitions (create/upsert/get from
--      20260913019000; accept from 20260915010000_db_integrity_bundle.sql
--      Part 5, keeping its LLA-056 inline profile_guardians check) VERBATIM
--      except the comments that restated the old union rule - they call
--      profile_counts_as_minor() by name, so their behavior changed in
--      step 1 and only their documentation needed to follow.
--
-- Explicitly NOT touched:
--   - public.sync_push: it transports is_minor and birth_year as DATA
--     (both in the derived c_profile_keys allowlist) and never gates on
--     minor status, so no re-emission (and no DO-block allowlist
--     re-derivation) is needed - no synced column changed here.
--   - profiles.is_minor itself: kept, per #820/#945 - it is the documented
--     fallback for the (still-possible, #944) profile with no birth year
--     and the column default; dropping it would reintroduce the
--     reclassification risk #820 was careful to avoid.
--   - create_guardian_invitation / the guardian invitation and transfer
--     RPCs: audited - none of them reads minor status at all (guardian
--     sharing is the family-collaboration path, not the outside-recipient
--     prediction path PRIVACY.md section 5 gates), so there is nothing to
--     converge there. No RLS policy and no Edge Function reads is_minor
--     either; the only server-side consumers of minor status are the five
--     functions above.
--
-- Coverage: supabase/tests/prediction_connection_test.sql (section 6b
-- reworked for the trigger widening, new section 6e for the disagreement
-- matrix).

-- ---------------------------------------------------------------------------
-- 1. Shared minor predicate: birth year authoritative, stored flag the
--    null-year fallback (deriveMinorStatus(), mirrored).
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
  select case
    when p_birth_year is not null
      then extract(year from clock_timestamp())::int - p_birth_year <= 18
    else coalesce(p_is_minor, false)
  end;
$$;

comment on function public.profile_counts_as_minor(boolean, smallint) is
  'Issue #945 (superseding #518''s union): the shared "is this profile a '
  'minor" predicate every prediction-sharing gate uses - a PRESENT '
  'birth_year is authoritative (minor iff current year - birth_year <= 18, '
  'mirroring lib/domain/models/profile.dart''s deriveMinorStatus() exactly: '
  '<=, not <, since a year-only birth_year cannot see the actual birthday, '
  'so the whole calendar year an 18th birthday falls in stays treated as '
  'minor - the safe, fail-closed direction); the stored is_minor flag '
  'decides only when birth_year is null, so client and server cannot '
  'disagree about a profile that has a birth year.';

revoke all on function public.profile_counts_as_minor(boolean, smallint) from public, anon;
grant execute on function public.profile_counts_as_minor(boolean, smallint) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. create_prediction_connection (20260913019000 body verbatim, rule
--    comment updated).
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

  -- Issues #373/#518/#945: a minor's profile is never shared. Minor
  -- status is DERIVED (birth year authoritative, stored flag the null-year
  -- fallback) via the shared predicate, so an adult-implying birth year
  -- wins over a stale is_minor flag exactly like the client's own
  -- deriveMinorStatus().
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
  'refused for a minor''s profile - Issues #373/#518/#945: minor status is '
  'derived via public.profile_counts_as_minor() (a present birth_year is '
  'authoritative, minor iff current year - birth_year <= 18; the stored '
  'is_minor flag decides only when no year exists, mirroring the client''s '
  'deriveMinorStatus() so the two cannot disagree) - and in Pregnancy '
  'mode, capped at one live (pending or active) connection per profile by '
  'prediction_connections_one_live_uq with this function as the friendly '
  'error path. The caller supplies a client-side SHA-256 token hash; the '
  'plaintext never reaches the server.';

revoke all on function public.create_prediction_connection(text, text, text, int)
  from public, anon;
grant execute on function public.create_prediction_connection(text, text, text, int)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. accept_prediction_connection (20260915010000_db_integrity_bundle.sql
--    Part 5 body verbatim, keeping its LLA-056 inline profile_guardians
--    check, rule comment updated).
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

  -- Issues #373/#518/#945: re-checked at redemption (the derived status,
  -- like the old flag, can change between arming and redemption) - minor
  -- status is DERIVED (birth year authoritative, stored flag the null-year
  -- fallback) via the shared predicate.
  if public.profile_counts_as_minor(v_profile.is_minor, v_profile.birth_year) then
    raise exception 'prediction-only sharing is unavailable for a minor''s profile'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Issue #636, LLA-056: was `if not public.is_guardian_with_roles(
  -- v_conn.profile_id, v_conn.owner_user_id, array['primary_guardian'])` -
  -- an unlocked read of someone OTHER than the caller's own membership row
  -- through a helper that now refuses to answer for any p_user_id but
  -- auth.uid(). Queries profile_guardians directly instead, matching the
  -- table's own is_guardian_with_roles() definition exactly (status =
  -- 'accepted' and role = 'primary_guardian').
  if not exists (
    select 1 from public.profile_guardians
     where profile_id = v_conn.profile_id
       and user_id = v_conn.owner_user_id
       and status = 'accepted'
       and role = 'primary_guardian'
  ) then
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
  'minor''s profile (Issues #373/#518/#945: minor status derived via '
  'public.profile_counts_as_minor() - a present birth_year is '
  'authoritative, the stored flag decides only when no year exists - '
  're-checked at accept), for Pregnancy mode (re-checked at accept), and '
  'for a reciprocal share-with-the-same-person pair. Issue #636, LLA-056: '
  'the sharer''s role is read via a direct, inline profile_guardians '
  'query instead of the shared is_guardian_with_roles() helper, which no '
  'longer answers for anyone but the caller. The recipient gains exactly '
  'one thing: read access to get_prediction_projection() for this '
  'profile.';

revoke all on function public.accept_prediction_connection(text) from public, anon;
grant execute on function public.accept_prediction_connection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. upsert_prediction_projection (20260913019000 body verbatim, rule
--    comment updated).
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

  -- Issues #518/#945: a minor's profile (minor status derived via the
  -- shared predicate: birth year authoritative, stored flag the null-year
  -- fallback) never gets a stored projection, mirroring the "no active
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
  '#518/#945: refused for a minor''s profile (minor status derived via '
  'public.profile_counts_as_minor(): a present birth_year is '
  'authoritative, the stored flag decides only when no year exists) - any '
  'stored snapshot is deleted and the call is a no-op, the same posture '
  'as having no active connection. The payload is validated by '
  'prediction_projections'' trigger and CHECK constraint against the '
  'derived-only allowlist. Allowed only while an active prediction '
  'connection exists; with none, any stored snapshot is deleted and the '
  'call is a no-op, so derived data never sits on the server '
  'unjustified.';

revoke all on function public.upsert_prediction_projection(text, jsonb)
  from public, anon;
grant execute on function public.upsert_prediction_projection(text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 5. get_prediction_projection (20260913019000 body verbatim, rule
--    comment updated).
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

  -- Issues #518/#945: a minor's profile (minor status derived via the
  -- shared predicate: birth year authoritative, stored flag the null-year
  -- fallback) returns null unconditionally - indistinguishable from
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
  'else - an unauthorized caller, an unshared profile, and (Issues '
  '#518/#945) a minor''s profile (minor status derived via '
  'public.profile_counts_as_minor(): a present birth_year is '
  'authoritative, the stored flag decides only when no year exists) are '
  'all indistinguishable. The payload''s shape is constrained at write '
  'time to derived phase fields; no raw row can ever reach this '
  'function''s return value.';

revoke all on function public.get_prediction_projection(text) from public, anon;
grant execute on function public.get_prediction_projection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. enforce_minor_prediction_revocation: fire on the DERIVED transition
--    instead of the raw is_minor flag flip. The existing
--    profiles_minor_prediction_revocation_guard trigger keeps its OID and
--    picks the new body up in place - no DROP/CREATE TRIGGER needed.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_minor_prediction_revocation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Issue #945: the decision-maker is the derived status, not the raw
  -- flag. Old and new are derived in the same statement (same clock), so
  -- this fires exactly when this UPDATE is what made the profile count
  -- as a minor - a no-year profile's flag flipping true (#518, as
  -- before) or a birth_year edit crossing into minority (new: the year
  -- is authoritative, so the edit is now the primary path). A bare flag
  -- flip on a profile with an adult-implying year no longer fires - the
  -- flag decides nothing there.
  if public.profile_counts_as_minor(new.is_minor, new.birth_year)
     and not public.profile_counts_as_minor(old.is_minor, old.birth_year) then
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
  'Issues #518/#945: BEFORE UPDATE guard on profiles - when the DERIVED '
  'minor status (public.profile_counts_as_minor(): birth year '
  'authoritative, stored flag the null-year fallback) flips to minor - a '
  'no-year profile''s is_minor flag flipping false -> true (via sync_push '
  'or a raw PATCH, #518, as before) or a birth_year edit crossing into '
  'minority (#945, now the primary path) - every live '
  'prediction_connections row for the profile is revoked and any stored '
  'prediction_projections row is deleted, in the SAME statement that made '
  'the profile a minor: zero window between the profile counting as a '
  'minor and sharing actually stopping. A bare is_minor flip on a profile '
  'with an adult-implying birth_year no longer fires (the flag is not the '
  'decision-maker there, #945), and the calendar-year rollover is still '
  'not caught here - nothing UPDATEs when no write happens - but is still '
  'enforced live by upsert_prediction_projection()/'
  'get_prediction_projection(), which re-derive on every call regardless.';
