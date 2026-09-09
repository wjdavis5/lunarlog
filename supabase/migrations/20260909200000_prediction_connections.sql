-- Migration: 20260909200000_prediction_connections.sql
-- Issue #151: the prediction-only connection (Clue Connect equivalent).
--
-- A fifth, NON-guardian relationship: a profile's accepted primary guardian
-- shares *derived cycle phases only* (period days, fertile days, ovulation,
-- PMS window) with one recipient. This is deliberately NOT a fifth
-- GuardianRole value: every existing row-level RLS predicate keys off
-- membership in profile_guardians, so a role would inherit day-entry read
-- access by construction. The connection lives in its own table
-- (public.prediction_connections) whose grants never touch
-- profile_guardians, so a future widening of guardian-role permissions
-- cannot widen this relationship by accident.
--
-- Design, mirroring the proven shapes already in this schema:
--   * Tokens: SHA-256 hex token_hash unique, plaintext never stored,
--     server-computed expires_at, accepted_at/revoked_at markers in place
--     of a status column (guardian_invitations / ownership_transfers).
--   * One-connection cap (R: "at most one active prediction-only
--     connection outstanding"): prediction_connections_one_live_uq, a
--     partial unique index allowing at most one non-revoked row per
--     profile -- pending or active, never two. An expired-but-unrevoked
--     pending row blocks a re-invite until create_prediction_connection
--     cancels it (the ownership_transfers cancel-then-create precedent).
--   * The projection payload (R: "server-side projection returning only
--     derived phases and dates") is CLIENT-PUBLISHED. The prediction
--     engine (lib/domain/prediction/prediction.dart) has exactly one
--     implementation and the server never recomputes it -- the same KTD4
--     decision 20260906230000_reminder_windows_and_cron.sql made for
--     reminder windows. The sharer's device computes the phases it already
--     computes for its own calendar and publishes them via
--     upsert_prediction_projection(); the server validates the payload
--     against a strict derived-only allowlist (no note/tags/flow key can
--     ever ride along) and serves it to the recipient through
--     get_prediction_projection(). The recipient's client can therefore
--     never receive a day_entries/observations row for the shared profile:
--     no sync table grants anything to the recipient, and the only derived
--     read path is this RPC's allowlisted shape.
--   * prediction_projections rows exist ONLY while an active (accepted,
--     unrevoked) connection exists -- enforced structurally by the
--     prediction_connections_projection_gc trigger and by the RPCs
--     themselves, so revocation (or the recipient's account deletion)
--     leaves no residual server-side copy and the next fetch returns null.
--   * Pregnancy mode (R: "unavailable in Pregnancy mode"; the life-stage
--     axis from 20260909000000_profile_modes_and_cycle_overrides.sql, not
--     #131's care mode): both create and accept refuse while
--     profile_modes.mode = 'pregnancy'.
--   * Minor profiles (PRIVACY.md: "Minor profiles ... are never shared or
--     analyzed"): both create and accept refuse when profiles.is_minor is
--     true, mirroring the Pregnancy-mode gate exactly (same rationale for
--     checking at both call sites -- is_minor is just as mutable a column
--     as profile_modes.mode).
--   * One-directional (R: "a recipient of a prediction-only share cannot
--     simultaneously be a source of one back"): accept refuses when the
--     accepting user already holds an active connection back to the
--     sharer's account (pair-level, per the issue's "one back" wording).
--   * Realtime: neither table is added to the supabase_realtime
--     publication. prediction_connections carries token hashes and
--     prediction_projections carries the derived payload -- neither may
--     ever cross the websocket. Both are named in
--     reconcile_realtime_publication()'s never-publish list below (the
--     #240/#188 review-finding pattern: name every table explicitly
--     rather than relying on it never being added). sync_signals --
--     the only published table -- and its column list are untouched.
--   * Account deletion: both tables' user FKs cascade from auth.users and
--     the profile FK cascades from public.profiles, so
--     delete_account_data() / the delete-account Edge Function's
--     auth.users deletion already removes every row without this migration
--     touching that function (its returned per-table counts stay exactly
--     as its own pgTAP suite asserts them).
--   * Guardian revocation closes this door too: revoke_guardian (below,
--     create-or-replace per the "don't edit a merged migration" rule) now
--     revokes every live prediction connection for the profile alongside
--     its ownership_transfers/guardian_invitations cleanup (#81 precedent).

-- ---------------------------------------------------------------------------
-- 1. prediction_connections table
-- ---------------------------------------------------------------------------

create table public.prediction_connections (
  id uuid primary key default gen_random_uuid(),
  profile_id text not null
    references public.profiles (id) on delete cascade,
  -- The sharer: the accepted primary_guardian who created the connection.
  owner_user_id uuid not null
    references auth.users (id) on delete cascade,
  -- The recipient: null until the invite is redeemed.
  recipient_user_id uuid
    references auth.users (id) on delete cascade,
  token_hash text not null unique
    constraint prediction_connections_token_hash_check
    check (token_hash ~ '^[0-9a-f]{64}$'),
  recipient_label text
    constraint prediction_connections_recipient_label_check
    check (recipient_label is null or char_length(recipient_label) <= 80),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  -- A redeemed row always names its recipient; a pending row never does.
  constraint prediction_connections_recipient_presence_check
    check ((accepted_at is null) = (recipient_user_id is null))
);

comment on table public.prediction_connections is
  'Prediction-only connections (Issue #151): a primary guardian shares '
  'derived cycle phases only with one recipient. Deliberately outside '
  'profile_guardians -- this relationship must never inherit day-entry '
  'read access, and every guardian RLS predicate keys off that table. '
  'Every mutation goes through the SECURITY DEFINER RPCs of this '
  'migration; authenticated holds SELECT on a narrow policy and no '
  'INSERT/UPDATE/DELETE grant at all.';

create index prediction_connections_profile_id_idx on public.prediction_connections (profile_id);
create index prediction_connections_token_hash_idx on public.prediction_connections (token_hash);
create index prediction_connections_recipient_idx on public.prediction_connections (recipient_user_id);

-- The one-connection cap (Issue #151: "at most one active prediction-only
-- connection outstanding"), structural: at most one non-revoked row per
-- profile, whether pending or active. now() is not immutable so expiry
-- cannot join the predicate -- create_prediction_connection cancels the
-- caller's own outstanding-but-expired row before inserting (the
-- ownership_transfers cancel-then-create precedent).
create unique index prediction_connections_one_live_uq
  on public.prediction_connections (profile_id)
  where revoked_at is null;

-- ---------------------------------------------------------------------------
-- 2. prediction_connections RLS: select-only, narrow
-- ---------------------------------------------------------------------------

alter table public.prediction_connections enable row level security;
alter table public.prediction_connections force row level security;

-- Select only. The sharer sees their own rows (any state); the profile's
-- accepted primary guardian sees them too (so the seat survives an
-- ownership handover -- the new primary guardian can revoke, mirroring
-- revoke_prediction_connection's authority); an accepted recipient sees
-- only their own still-live connection. Nobody else -- in particular a
-- pending invite is invisible to the (unknown) recipient, exactly like
-- guardian_invitations. There is deliberately NO INSERT, UPDATE, or
-- DELETE policy: every mutation runs through this migration's SECURITY
-- DEFINER RPCs, which enforce the primary-guardian gate, the pregnancy
-- gate, the one-connection cap, and terminal-revocation semantics that a
-- with check clause could not express.
create policy "prediction_connections_select" on public.prediction_connections
  for select to authenticated
  using (
    owner_user_id = (select auth.uid())
    or public.is_guardian_with_roles(
         profile_id, (select auth.uid()), array['primary_guardian'])
    or (
      recipient_user_id = (select auth.uid())
      and accepted_at is not null
      and revoked_at is null
    )
  );

revoke all on table public.prediction_connections from public, anon, authenticated;

-- Column-scoped SELECT (the issue #114/#242 hardening applied from day
-- one, not patched in later): the stored token_hash IS the credential --
-- accept_prediction_connection compares a client-supplied hash directly,
-- so an account admitted by the policy above must never be able to read
-- (or even filter on) the hash of someone else's still-pending invite.
-- Referencing a column anywhere in a query requires SELECT on it, so a
-- full-row `select *` fails closed with 42501; the SECURITY DEFINER RPCs
-- and policies are unaffected (policy quals are not subject to the
-- caller's column grants).
grant select (
  id,
  profile_id,
  owner_user_id,
  recipient_user_id,
  recipient_label,
  expires_at,
  accepted_at,
  revoked_at,
  created_at
) on table public.prediction_connections to authenticated;

-- ---------------------------------------------------------------------------
-- 3. prediction_projections: the published derived-phase snapshot
-- ---------------------------------------------------------------------------

create table public.prediction_projections (
  profile_id text primary key
    references public.profiles (id) on delete cascade,
  projection jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid not null
    references auth.users (id) on delete cascade,
  -- Structural key allowlist (issue #151: "verified by inspecting the
  -- RPC's return shape (derived fields only)"). CHECK constraints cannot
  -- carry subqueries, but jsonb `-` with a text[] operand is a pure
  -- expression: removing every allowed key must leave nothing. This
  -- backstop survives any future writer (including a migration bug);
  -- the per-value validation lives in enforce_prediction_projection_payload()
  -- below, wired as a BEFORE trigger.
  constraint prediction_projections_payload_keys_check
    check (
      (projection - array[
        'generated_at', 'period_days', 'fertile_days',
        'ovulation_days', 'pms_days'
      ]) = '{}'::jsonb
    ),
  constraint prediction_projections_generated_at_check
    check (projection ? 'generated_at')
);

comment on table public.prediction_projections is
  'Client-published snapshot of derived cycle phases (Issue #151): period '
  'days, fertile days, ovulation days, PMS window -- dates only, never '
  'note/tags/flow, never a raw day_entries/observations row. One row per '
  'profile, and only while an active prediction connection exists '
  '(prediction_connections_projection_gc keeps that invariant). The '
  'prediction algorithm itself is never recomputed server-side -- the '
  'sharer''s device publishes what lib/domain/prediction already computes. '
  'NO policies and no grants: clients reach this through '
  'get_prediction_projection() only, which serves the allowlisted payload '
  'to the active recipient and to the profile''s own guardians (who '
  'already hold full raw access and gain nothing new here).';

alter table public.prediction_projections enable row level security;
alter table public.prediction_projections force row level security;

-- No policies at all (the notification_outbox posture): nothing a client
-- can do against this table directly. The SECURITY DEFINER RPCs below
-- bypass RLS deliberately and re-impose the access checks in their bodies.
revoke all on table public.prediction_projections from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. Payload validation trigger
-- ---------------------------------------------------------------------------

create or replace function public.enforce_prediction_projection_payload()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_array jsonb;
  v_item jsonb;
begin
  -- generated_at: required, an ISO yyyy-mm-dd civil date string.
  if jsonb_typeof(new.projection -> 'generated_at')
       is distinct from 'string'
     or (new.projection ->> 'generated_at')
       !~ '^\d{4}-\d{2}-\d{2}$' then
    raise exception 'projection.generated_at must be an ISO yyyy-mm-dd date string'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Every other key must be an array of at most 100 ISO date strings.
  -- The CHECK constraint already bounds the key set; this re-checks it so
  -- the error names the offending key, and bounds every value's shape.
  for v_key in
    select k from jsonb_object_keys(new.projection) as t(k)
  loop
    if v_key = 'generated_at' then
      continue;
    end if;
    if v_key not in ('period_days', 'fertile_days', 'ovulation_days', 'pms_days') then
      raise exception 'projection key % is not a derived-phase field', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    v_array := new.projection -> v_key;
    if jsonb_typeof(v_array) is distinct from 'array' then
      raise exception 'projection.% must be an array of date strings', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    if jsonb_array_length(v_array) > 100 then
      raise exception 'projection.% may hold at most 100 dates', v_key
        using errcode = 'invalid_parameter_value';
    end if;
    for v_item in select * from jsonb_array_elements(v_array)
    loop
      if jsonb_typeof(v_item) is distinct from 'string'
         or v_item #>> '{}' !~ '^\d{4}-\d{2}-\d{2}$' then
        raise exception 'projection.% must hold only ISO yyyy-mm-dd date strings', v_key
          using errcode = 'invalid_parameter_value';
      end if;
    end loop;
  end loop;

  return new;
end;
$$;

comment on function public.enforce_prediction_projection_payload() is
  'BEFORE INSERT/UPDATE guard on prediction_projections: the payload may '
  'carry only derived-phase keys (generated_at plus period_days / '
  'fertile_days / ovulation_days / pms_days), each an array of at most '
  '100 ISO date strings. No free-text key can ever be stored, so the '
  'recipient-facing RPC cannot leak note/tags/flow even by server bug -- '
  'the data is not there.';

create trigger prediction_projections_payload_guard
  before insert or update on public.prediction_projections
  for each row execute function public.enforce_prediction_projection_payload();

revoke execute on function public.enforce_prediction_projection_payload()
  from public, anon;

-- ---------------------------------------------------------------------------
-- 5. Projection garbage collection: rows exist only while a connection is
--    active. An AFTER trigger on prediction_connections re-checks the
--    invariant on every connection mutation (revoke, recipient account
--    deletion cascade, owner account deletion cascade, profile deletion
--    cascade) so no code path can leave a residual snapshot behind.
-- ---------------------------------------------------------------------------

create or replace function public.prediction_connections_projection_gc()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.prediction_projections pp
   where pp.profile_id = coalesce(new.profile_id, old.profile_id)
     and not exists (
       select 1
         from public.prediction_connections pc
        where pc.profile_id = coalesce(new.profile_id, old.profile_id)
          and pc.accepted_at is not null
          and pc.revoked_at is null
     );
  return null;
end;
$$;

comment on function public.prediction_connections_projection_gc() is
  'AFTER INSERT/UPDATE/DELETE on prediction_connections: drops the '
  'profile''s prediction_projections row the moment no active (accepted, '
  'unrevoked) connection remains, so derived-phase data never outlives '
  'the connection that justifies it -- including cascade paths (account '
  'deletion, profile deletion) no RPC explicitly handles.';

create trigger prediction_connections_projection_gc_trg
  after insert or update or delete on public.prediction_connections
  for each row execute function public.prediction_connections_projection_gc();

revoke execute on function public.prediction_connections_projection_gc()
  from public, anon;

-- ---------------------------------------------------------------------------
-- 6. create_prediction_connection
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

  -- Minor gate (issue #151; PRIVACY.md: minor profiles "are never shared
  -- or analyzed"). Mirrors the Pregnancy gate immediately above -- same
  -- errcode, same "checked at create AND accept" reasoning, because
  -- is_minor is just as mutable as profile_modes.mode (both are plain
  -- owner-writable columns synced through the normal push path), so the
  -- same race between arming a code and its redemption applies here too.
  if v_profile.is_minor then
    raise exception 'prediction-only sharing is unavailable for minor profiles'
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
  'refused in Pregnancy mode and for minor profiles (PRIVACY.md: minor '
  'data is never shared or analyzed), capped at one live (pending or '
  'active) connection per profile by prediction_connections_one_live_uq '
  'with this function as the friendly error path. The caller supplies a '
  'client-side SHA-256 token hash; the plaintext never reaches the '
  'server.';

revoke all on function public.create_prediction_connection(text, text, text, int)
  from public, anon;
grant execute on function public.create_prediction_connection(text, text, text, int)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 7. accept_prediction_connection
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

  -- Minor gate, re-checked at redemption -- same reasoning as the
  -- Pregnancy gate immediately above: is_minor is a plain owner-writable
  -- column (synced through the normal push path) just like
  -- profile_modes.mode, so it can change between arming a code and its
  -- redemption.
  if v_profile.is_minor then
    raise exception 'prediction-only sharing is unavailable for minor profiles'
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
  'guardian, for a profile whose sharer lost the primary seat, for '
  'Pregnancy mode and for a minor profile (both re-checked at accept -- '
  'either can change between arming a code and its redemption), and for '
  'a reciprocal share-with-the-same-person pair. The recipient gains '
  'exactly one thing: read access to get_prediction_projection() for '
  'this profile.';

revoke all on function public.accept_prediction_connection(text) from public, anon;
grant execute on function public.accept_prediction_connection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. revoke_prediction_connection
-- ---------------------------------------------------------------------------

create or replace function public.revoke_prediction_connection(
  p_connection_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_conn public.prediction_connections%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  select * into v_conn
    from public.prediction_connections
   where id = p_connection_id
   for update;
  if not found then
    raise exception 'prediction connection not found' using errcode = 'no_data_found';
  end if;

  -- The sharer who created it, or the profile's current accepted primary
  -- guardian (the seat survives an ownership handover -- the new primary
  -- can revoke what the old one armed, mirroring the SELECT policy).
  if v_conn.owner_user_id <> v_uid
     and not public.is_guardian_with_roles(
       v_conn.profile_id, v_uid, array['primary_guardian']) then
    raise exception 'only the sharer or the current primary guardian can revoke this connection'
      using errcode = 'insufficient_privilege';
  end if;

  -- Idempotent: an already-revoked connection reports success without a
  -- further write (the revoke_guardian_invitation terminal-state
  -- pattern). Revocation is terminal -- there is no un-revoke.
  if v_conn.revoked_at is null then
    update public.prediction_connections
       set revoked_at = clock_timestamp()
     where id = v_conn.id;
  end if;

  -- The projection GC trigger fires on the UPDATE above and deletes the
  -- profile's snapshot in this same transaction, so the recipient's very
  -- next fetch already returns null ("no residual access").
  return true;
end;
$$;

comment on function public.revoke_prediction_connection(uuid) is
  'Revokes a prediction-only connection (Issue #151): the sharer or the '
  'profile''s current primary guardian, idempotent, terminal. The '
  'projection_gc trigger deletes the published snapshot in the same '
  'transaction, so the recipient''s next fetch returns null.';

revoke all on function public.revoke_prediction_connection(uuid) from public, anon;
grant execute on function public.revoke_prediction_connection(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. upsert_prediction_projection (the sharer's publish path)
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
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Same write ladder as upsert_reminder_window: any accepted guardian
  -- with a logging seat may publish the snapshot their own device
  -- computed (primary_guardian, co_parent, caregiver -- not viewer).
  if not public.is_guardian_with_roles(
       p_profile_id, v_uid,
       array['primary_guardian', 'co_parent', 'caregiver']) then
    raise exception 'only an accepted guardian of this profile can publish its prediction projection'
      using errcode = 'insufficient_privilege';
  end if;

  if p_projection is null then
    raise exception 'p_projection is required' using errcode = 'invalid_parameter_value';
  end if;

  -- Privacy posture: derived-phase data exists server-side only while an
  -- active connection justifies it. With none, delete any stale row (the
  -- GC trigger may not have run for a caller that never touched
  -- prediction_connections) and return instead of erroring -- a revoked
  -- connection racing this publish is benign and must not surface as a
  -- failure on the sharer's device.
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
  'Publishes one profile''s derived-phase snapshot (Issue #151). The '
  'payload is validated by prediction_projections'' trigger and CHECK '
  'constraint against the derived-only allowlist. Allowed only while an '
  'active prediction connection exists; with none, any stored snapshot is '
  'deleted and the call is a no-op, so derived data never sits on the '
  'server unjustified.';

revoke all on function public.upsert_prediction_projection(text, jsonb)
  from public, anon;
grant execute on function public.upsert_prediction_projection(text, jsonb)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 10. get_prediction_projection (the recipient's only read path)
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
  v_projection jsonb;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  -- Eligibility: the profile's ACTIVE recipient (the connection itself
  -- -- never is_profile_guardian, which would let guardian-role changes
  -- widen this relationship; issue #151's "no RLS grant reachable through
  -- is_profile_guardian"), or one of the profile's own guardians, who
  -- already hold full raw access and gain nothing derived they cannot
  -- compute locally. An unauthorized caller and an unshared profile both
  -- return null: no enumeration signal.
  if not exists (
    select 1 from public.prediction_connections
     where profile_id = p_profile_id
       and recipient_user_id = v_uid
       and accepted_at is not null
       and revoked_at is null
  ) and not public.is_profile_guardian(p_profile_id, v_uid) then
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
  'else -- an unauthorized caller and an unshared profile are '
  'indistinguishable. The payload''s shape is constrained at write time '
  'to derived phase fields; no raw row can ever reach this function''s '
  'return value.';

revoke all on function public.get_prediction_projection(text) from public, anon;
grant execute on function public.get_prediction_projection(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 11. revoke_guardian: revoking a guardian now also revokes the profile's
--     live prediction connections (#81 precedent -- close every door)
-- ---------------------------------------------------------------------------
--
-- Fix-forward per the "do not edit a merged migration in place" rule: this
-- function was last defined in 20260906240000_account_deletion_notifications
-- .sql, which predates this feature and is already merged -- so this is a
-- `create or replace`, not an edit to that file. The body is carried
-- forward verbatim (including Issue #5 U4's notification_preferences /
-- notification_outbox / missed_entry_alert_state cleanup and the Issue #4
-- review-item-#1 ownership_transfers cancellation) except for the one new
-- block called out inline.
--
-- A prediction connection armed by a guardian who is then revoked must not
-- outlive the revocation: the sharer's primary-guardian seat was the
-- connection's justification, and the projection snapshot would keep
-- flowing to the recipient under an access level that no longer holds.
-- Like guardian_invitations and ownership_transfers, a pending invite
-- carries no invitee identity, so the safe default is to revoke every
-- live prediction connection for the profile whenever any revocation
-- happens on it; the GC trigger (section 5) deletes the profile's
-- published snapshot in this same transaction, so the recipient's next
-- fetch returns null.
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
  v_now timestamptz;
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

  v_now := clock_timestamp();

  -- Issue #4, U3, review item #1 (P0): close the ownership-transfer bypass.
  -- This update runs first, ahead of the updates below, so the lock order
  -- here - ownership_transfers, then guardian_invitations, then
  -- prediction_connections (Issue #151's addition, last-in), then
  -- profile_guardians - matches accept_ownership_transfer's own order for
  -- the tables it shares and the RPCs cannot deadlock against each other.
  update public.ownership_transfers
     set cancelled_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and cancelled_at is null;

  -- #81: revocation must close every door, not just the one the revoked
  -- user already walked through. guardian_invitations binds to a token
  -- (see 20260904010000_multi_guardian_schema.sql) rather than a recipient
  -- identity - there is no invitee column, only accepted_by, which stays
  -- null until redemption - so a live, unaccepted invitation cannot be
  -- reliably tied to p_target_user_id before it is redeemed. The safe
  -- default is to cancel every still-live invitation for the profile
  -- whenever any revocation happens on it, not just one provably addressed
  -- to the revoked user; the cost is that an unrelated pending invitation
  -- (e.g. to a caregiver the target never touched) also gets canceled and
  -- must be re-sent, which is an acceptable trade for closing the bypass.
  update public.guardian_invitations
     set revoked_at = v_now
   where profile_id = p_profile_id
     and accepted_at is null
     and revoked_at is null;

  -- Issue #151: a guardian revocation also revokes every live prediction
  -- connection for the profile -- pending or active. The projection_gc
  -- trigger fires per revoked row and deletes the profile's published
  -- snapshot in this same transaction, so the prediction-only recipient's
  -- next fetch returns null. Placed before the profile_guardians update,
  -- keeping the established table order.
  update public.prediction_connections
     set revoked_at = v_now
   where profile_id = p_profile_id
     and revoked_at is null;

  update public.profile_guardians
     set status = 'revoked',
         updated_at = v_now,
         revoked_at = v_now
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  -- Issue #5, U4 (R5): stop the revoked guardian's alerts for this profile
  -- immediately. The preference row's RLS read already closed the moment
  -- status flipped above, but deleting it (rather than leaving it orphaned)
  -- is what R5 means by "immediately" - and any of their pending, unsent
  -- alerts for this profile are removed too, so nothing already enqueued
  -- reaches them after this call returns. A already-sent alert cannot be
  -- recalled (sent_at is not null), which is unavoidable and out of scope.
  delete from public.notification_preferences
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  delete from public.notification_outbox
   where profile_id = p_profile_id
     and recipient_user_id = p_target_user_id
     and sent_at is null;

  -- Round-2 review #8: also drop the revoked guardian's missed-entry dedupe
  -- marker for this profile. Without this, a guardian who is revoked and
  -- later re-invited -- with the same estimated_next_start still published
  -- on profile_reminder_windows -- is silently skipped by the scan's
  -- `last_enqueued_for is distinct from estimated_next_start` gate,
  -- re-creating exactly the co-guardian suppression bug review #8 was filed
  -- to remove. It is also residual data about a minor's profile retained
  -- for someone whose access was just revoked (R5).
  delete from public.missed_entry_alert_state
   where profile_id = p_profile_id
     and user_id = p_target_user_id;

  return true;
end;
$$;

comment on function public.revoke_guardian(text, uuid) is
  'Revokes p_target_user_id''s guardianship of p_profile_id (see prior '
  'migrations for the #81/#82 fixes and Issue #5 U4''s alert cleanup) and, '
  'as of Issue #151, also revokes every live prediction_connections row '
  'for the profile -- whose projection_gc trigger deletes the published '
  'derived-phase snapshot in the same transaction, so a prediction-only '
  'recipient loses access at their next fetch the moment any guardian '
  'revocation happens.';

revoke all on function public.revoke_guardian(text, uuid) from public, anon;
grant execute on function public.revoke_guardian(text, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 12. Realtime: name the new tables in reconcile_realtime_publication()'s
--     never-publish list.
-- ---------------------------------------------------------------------------
--
-- Fix-forward per the "don't edit a merged migration in place" rule: the
-- function is create-or-replaced from its latest definition
-- (20260909141503_care_notes_visit_prep.sql), copied verbatim except for
-- the two new drop blocks called out inline and the widened FOR ALL TABLES
-- message. sync_signals -- the only published table -- and its column list
-- are untouched, so the coordinator's subscription shape is unchanged;
-- what grows is the list of tables this function actively REVERTS if a
-- Studio "Enable Realtime" toggle ever adds them (the #240/#188/#128
-- review-finding pattern: name every sensitive table explicitly rather
-- than relying on it never being added). prediction_connections carries
-- token hashes and prediction_projections the derived payload -- neither
-- may ever cross the websocket.
create or replace function public.reconcile_realtime_publication()
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_signals_col_list name[] := array['profile_id', 'updated_at']::name[];
  v_current_cols name[];
  v_all_tables boolean;
begin
  if not exists (
    select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime'
  ) then
    raise exception
      'supabase_realtime publication does not exist -- expected to already '
      'exist, created by the Supabase platform''s own base migrations';
  end if;

  -- Never let day_entries or profiles be published, in any form. Checks
  -- *and corrects* rather than only checking membership, so a whole-row
  -- publication left behind by Supabase Studio's "Enable Realtime" toggle
  -- (or a future edit that widens this migration) is actively reverted
  -- instead of being treated as already-correct and skipped.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'day_entries'
  ) then
    alter publication supabase_realtime drop table public.day_entries;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profiles'
  ) then
    alter publication supabase_realtime drop table public.profiles;
  end if;

  -- Issue #240 review finding: observations joins day_entries/profiles on
  -- this must-never-be-published list -- it carries the same category of
  -- sensitive per-entry content (symptom/option detail) that day_entries
  -- was excluded for, and nothing about this table was ever meant to reach
  -- the client any way other than the existing sync_signals wake-signal +
  -- an authenticated sync_push/read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'observations'
  ) then
    alter publication supabase_realtime drop table public.observations;
  end if;

  -- Issue #167: import_jobs joins this must-never-be-published list --
  -- no health content, but a per-user tracking table with no reason to
  -- reach the client any way other than an authenticated read.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'import_jobs'
  ) then
    alter publication supabase_realtime drop table public.import_jobs;
  end if;

  -- Issue #188: profile_modes and cycle_overrides join this
  -- must-never-be-published list -- a profile's reproductive-life-stage
  -- state and cycle corrections are exactly the category of sensitive
  -- content day_entries/profiles/observations were excluded for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'profile_modes'
  ) then
    alter publication supabase_realtime drop table public.profile_modes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'cycle_overrides'
  ) then
    alter publication supabase_realtime drop table public.cycle_overrides;
  end if;

  -- Issue #128: care_notes and visit_prep_items join this
  -- must-never-be-published list -- standing care notes and visit-prep
  -- checklists are exactly the category of sensitive health content
  -- about a minor that day_entries/profiles/observations were excluded
  -- for.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'care_notes'
  ) then
    alter publication supabase_realtime drop table public.care_notes;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'visit_prep_items'
  ) then
    alter publication supabase_realtime drop table public.visit_prep_items;
  end if;

  -- Issue #151: the prediction tables join the never-publish list --
  -- token hashes (prediction_connections) and the derived payload
  -- (prediction_projections) must never cross the websocket.
  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_connections'
  ) then
    alter publication supabase_realtime drop table public.prediction_connections;
  end if;

  if exists (
    select 1
      from pg_catalog.pg_publication_rel pr
      join pg_catalog.pg_class pc on pc.oid = pr.prrelid
      join pg_catalog.pg_namespace pn on pn.oid = pc.relnamespace
      join pg_catalog.pg_publication pp on pp.oid = pr.prpubid
     where pp.pubname = 'supabase_realtime'
       and pn.nspname = 'public'
       and pc.relname = 'prediction_projections'
  ) then
    alter publication supabase_realtime drop table public.prediction_projections;
  end if;

  -- If `supabase_realtime` was ever switched to FOR ALL TABLES (which would
  -- silently republish day_entries/profiles/observations/import_jobs
  -- whole-row regardless of the per-table checks above), that is a
  -- platform-level misconfiguration this function cannot safely undo (it
  -- would also drop unrelated tables this repo does not own). Fail loudly
  -- instead of pretending the guard above was sufficient.
  select puballtables into v_all_tables
    from pg_catalog.pg_publication
   where pubname = 'supabase_realtime';

  if v_all_tables then
    raise exception
      'supabase_realtime is FOR ALL TABLES -- this publishes public.profiles, '
      'public.day_entries, public.observations, public.import_jobs, '
      'public.profile_modes, public.cycle_overrides, public.care_notes, public.visit_prep_items, '
      'public.prediction_connections, and public.prediction_projections whole-row and must be '
      'fixed manually before this migration can proceed (see the migration '
      'header comment)';
  end if;

  -- public.sync_signals: the only table this app publishes to Realtime.
  -- Correct both membership and the published column list -- not just
  -- membership -- so a Studio toggle (which would publish every column) is
  -- detected and repaired rather than skipped as "already there".
  select attnames
    into v_current_cols
    from pg_catalog.pg_publication_tables
   where pubname = 'supabase_realtime'
     and schemaname = 'public'
     and tablename = 'sync_signals';

  if v_current_cols is null then
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  elsif (select array_agg(c order by c) from unnest(v_current_cols) as c)
        is distinct from (
          select array_agg(c order by c) from unnest(v_signals_col_list) as c
        ) then
    -- Column set drifted from what this function intends (e.g. a Studio
    -- toggle re-added the table whole-row) -- correct it rather than skip.
    alter publication supabase_realtime drop table public.sync_signals;
    alter publication supabase_realtime
      add table public.sync_signals (profile_id, updated_at);
  end if;
end;
$$;

comment on function public.reconcile_realtime_publication() is
  'Ensures supabase_realtime publishes only public.sync_signals (with '
  'exactly profile_id, updated_at) and never public.profiles/day_entries/'
  'observations/profile_modes/cycle_overrides/care_notes/visit_prep_items/'
  'prediction_connections/prediction_projections (Issue #240 added '
  'observations to this list; Issue #188 added the two mode tables; Issue '
  '#128 added care_notes/visit_prep_items; Issue #151 added the two '
  'prediction tables), drift (e.g. a Studio "Enable Realtime" toggle) '
  'rather than skipping an already-published table (Issue #77 P1 fix). '
  'Not an API function -- runs only from migrations and from pgTAP (as an '
  'unrestricted role); execute is revoked from every app role below.';

revoke execute on function public.reconcile_realtime_publication()
  from public, anon, authenticated;

select public.reconcile_realtime_publication();
