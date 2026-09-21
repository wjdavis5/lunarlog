-- Migration: 20260920120000_profile_subject_membership.sql
-- Implements Issue #802: "her own profile" — the subject of a profile can
-- hold a first-class membership on it, without a fifth role and without a
-- second permission model (#131's "mode is presentation, not permission"
-- constraint; family-sharing plan KTD8).
--
-- 1. public.profile_guardians.is_subject (nullable boolean): a durable,
--    server-visible membership fact — "this member is the person the
--    profile is about". Durability is the point (#518's lesson: a
--    client-side or derived flag is not a fact the server can see or the
--    sync can carry): the column is stored on the membership row, pulled
--    to every device by sync_pull's existing `select *` over
--    profile_guardians, and writable ONLY by the SECURITY DEFINER RPCs
--    below. There is deliberately no column grant: the table's existing
--    authenticated update grant covers (display_name, updated_at) only,
--    so no client can set, clear, or forge the marker through PostgREST.
-- 2. public.guardian_invitations.is_subject (boolean not null default
--    false): the invitation records the preset itself, so the marker
--    travels with the invite and accept_guardian_invitation can stamp it
--    onto the membership without a second source of truth.
-- 3. create_guardian_invitation gains p_subject (default false). A
--    subject invitation must grant `caregiver` — the issue's recommended
--    default, and the only role consistent with "a minor must not be able
--    to remove her parent from the profile before a transfer": a
--    caregiver cannot edit profile metadata, manage guardians, or delete
--    the profile (sync_push's own role checks enforce all three
--    server-side). The marker is identity/labelling, NOT permission — the
--    role ladder and every RLS policy are untouched.
-- 4. accept_guardian_invitation copies the invitation's is_subject onto
--    the upserted membership row. A plain (non-subject) re-invitation of
--    a former subject therefore clears the marker deliberately — the
--    latest invitation is the truth about how this member was invited.
-- 5. preview_guardian_invitation returns is_subject alongside its
--    existing three fields, so the accept sheet can say "This is your
--    profile…" (issue #800's plain-language decision) before the
--    recipient commits. It remains enumeration-free: the marker describes
--    the invite being presented, nothing about other guardians.
-- 6. accept_ownership_transfer stamps is_subject = true on the accepting
--    child's row (they are now unambiguously the subject AND the owner)
--    and is_subject = false on the demoted parent's row — transfer
--    remains the separate, later decision (#4); this migration does not
--    move it.
--
-- Orthogonality notes (binding):
-- * vs #295 (isMinor as a guardian-editable checkbox): is_subject is
--   about MEMBERSHIP identity (which member the profile is about);
--   profiles.is_minor / profiles.birth_year are about the PROFILE's
--   subject. They answer different questions and never derive from each
--   other — nothing here computes, gates, or schedules anything from
--   either (#802's non-goal: no age computation; birth year "never
--   gates, forces, or auto-schedules").
-- * vs the role ladder (#8): role stays the only capability model.
--   is_subject changes no policy, no grant, and no CHECK constraint.
-- * revoke_guardian and update_guardian_role deliberately do NOT touch
--   the marker: revocation is terminal for access (status = 'revoked'
--   already gates everything) and a role change is orthogonal to
--   identity — a subject whose role is later moved stays the subject.
--
-- Client compatibility: the new profile_guardians column is nullable and
-- never validated against a closed set, so an older client's pull
-- (to_jsonb of the row now carrying the key) and a newer client pulling
-- from a pre-#802 server (key absent) both degrade cleanly; the client
-- decodes a missing/null is_subject as false.

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------

alter table public.profile_guardians
  add column is_subject boolean;

comment on column public.profile_guardians.is_subject is
  'Issue #802: this member is the person the profile is about (the subject), distinct from role. Nullable — null and false mean the same thing (a helper membership); nullable keeps the backfill a catalog-only change. Writable only through the SECURITY DEFINER RPCs (subject invitation accept, accept_ownership_transfer): no authenticated column grant exists, so a client cannot set or clear it. Server-visible and synced (sync_pull selects the whole row), unlike a client-side flag (#518''s lesson). Orthogonal to profiles.is_minor/birth_year (#295): membership identity vs profile fact.';

alter table public.guardian_invitations
  add column is_subject boolean not null default false;

comment on column public.guardian_invitations.is_subject is
  'Issue #802: this invitation was created with the "her own profile" preset — accepting it stamps the subject marker onto the upserted profile_guardians row. Default false keeps every pre-#802 invitation a plain helper invite.';

-- #114 made guardian_invitations SELECT column-granted (every column but
-- token_hash), and a column-level grant does not cover a column added
-- later — so the new column must join the list explicitly, or the
-- client's pending-invitations read (which selects is_subject) would
-- fail closed with 42501. token_hash stays ungranted exactly as before.
grant select (is_subject) on table public.guardian_invitations to authenticated;

-- ---------------------------------------------------------------------------
-- 2. create_guardian_invitation — p_subject param
-- ---------------------------------------------------------------------------
-- Signature change (new trailing parameter with a default): the old
-- function is dropped and recreated, so the grant is re-issued against
-- the new signature. Body carried verbatim from
-- 20260905090000_close_guardian_revocation_bypass.sql except: the
-- subject/role validation block, the is_subject insert column, and the
-- is_subject result key.

drop function public.create_guardian_invitation(text, text, text, text, int);

create or replace function public.create_guardian_invitation(
  p_profile_id text,
  p_role text,
  p_recipient_label text,
  p_token_hash text,
  p_ttl_hours int default 48,
  p_subject boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_invitation_id uuid;
  v_now timestamptz;
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

  -- R3: only the primary guardian may create co-parent invitations; a
  -- co-parent can invite caregivers and viewers only.
  if p_role = 'co_parent'
     and not public.is_guardian_with_roles(p_profile_id, v_uid, array['primary_guardian']) then
    raise exception 'only the primary guardian can invite a co-parent'
      using errcode = 'insufficient_privilege';
  end if;

  -- Issue #802: the "her own profile" preset exists only on the
  -- caregiver role. A subject marker riding a co_parent or viewer
  -- invitation would contradict the preset's own rationale (a minor must
  -- not be able to manage guardians on her own profile) or label a
  -- read-only helper as the subject. Same authority ladder as every
  -- other invitation — nothing about who may invite changes.
  if coalesce(p_subject, false) and p_role <> 'caregiver' then
    raise exception 'a subject invitation must grant the caregiver role'
      using errcode = 'invalid_parameter_value';
  end if;

  -- R7: the TTL is server-bounded so an authorized inviter cannot mint a
  -- multi-century (or negative) invitation.
  if coalesce(p_ttl_hours, 48) < 1 or coalesce(p_ttl_hours, 48) > 168 then
    raise exception 'p_ttl_hours must be between 1 and 168'
      using errcode = 'invalid_parameter_value';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- clock_timestamp() rather than now(): see this function's history in
  -- 20260905090000. This row's created_at is compared against a
  -- profile_guardians.revoked_at in accept_guardian_invitation (#82), and
  -- now()/transaction_timestamp() is frozen for the whole transaction.
  v_now := clock_timestamp();
  v_expires_at := v_now + (coalesce(p_ttl_hours, 48) || ' hours')::interval;

  insert into public.guardian_invitations
    (profile_id, invited_by, token_hash, role, recipient_label, expires_at, created_at, is_subject)
  values
    (p_profile_id, v_uid, p_token_hash, p_role, p_recipient_label, v_expires_at, v_now, coalesce(p_subject, false))
  returning id into v_invitation_id;

  return jsonb_build_object(
    'id', v_invitation_id,
    'profile_id', p_profile_id,
    'role', p_role,
    'expires_at', v_expires_at,
    'is_subject', coalesce(p_subject, false)
  );
end;
$$;

revoke all on function public.create_guardian_invitation(text, text, text, text, int, boolean) from public, anon;
grant execute on function public.create_guardian_invitation(text, text, text, text, int, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. accept_guardian_invitation — stamps the invitation's marker
-- ---------------------------------------------------------------------------
-- Body carried verbatim from 20260905090000_close_guardian_revocation_
-- bypass.sql except: is_subject in the membership upsert (insert values
-- and the DO UPDATE) and in the returned object.

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
  v_existing public.profile_guardians%rowtype;
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

  -- Lock any existing membership row for this (profile, user) up front, so
  -- the revoked-terminal check below and the upsert further down decide
  -- against the same snapshot. This also fixes the lock order to match
  -- revoke_guardian's own order (guardian_invitations row(s), then this
  -- profile_guardians row) - see that function - so the two RPCs cannot
  -- deadlock against each other under concurrent calls.
  select * into v_existing
    from public.profile_guardians
   where profile_id = v_invite.profile_id
     and user_id = v_uid
   for update;

  if found then
    if v_existing.status = 'accepted' then
      raise exception 'user is already an active guardian of this profile'
        using errcode = 'unique_violation';
    end if;

    if v_existing.status = 'revoked' then
      -- #82: revoked is terminal for a token that predates the revocation.
      -- A deliberate re-invitation issued *after* the revocation must still
      -- work (a primary guardian can always re-add someone they previously
      -- removed) - the distinguishing fact is whether this invitation's
      -- created_at is after the membership row's revoked_at. Both are
      -- stamped with clock_timestamp(), not now() (see
      -- create_guardian_invitation and revoke_guardian), so the comparison
      -- holds even across two RPC calls made inside one transaction.
      --
      -- v_existing.revoked_at is null only for a row revoked before this
      -- migration's column existed (best-effort backfilled from updated_at
      -- - see the migration header); if it is still null here there is
      -- nothing reliable to compare against, so the safer default is to
      -- refuse rather than guess.
      if v_existing.revoked_at is null or v_invite.created_at <= v_existing.revoked_at then
        raise exception 'guardian access to this profile was revoked; a new invitation is required'
          using errcode = 'object_not_in_prerequisite_state';
      end if;
      -- else: this invitation was created after the revocation - a genuine
      -- re-invitation. Fall through to the upsert below, which clears
      -- revoked_at and re-derives role from this (fresh) invitation.
    end if;
  end if;

  -- Add or revive membership in profile_guardians. The check above has
  -- already run for any existing row, so this can only reach a revoked row
  -- here via a provably fresh invitation. Issue #802: is_subject comes
  -- from THIS invitation (excluded) on both branches - a fresh subject
  -- invitation stamps the marker, a fresh plain invitation of a former
  -- subject deliberately clears it. The marker is membership state, so it
  -- is written by this SECURITY DEFINER path only, exactly like role and
  -- status.
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, invited_by, updated_at, revoked_at, is_subject)
  values
    (v_invite.profile_id, v_uid, v_invite.role, 'accepted', p_guardian_display_name, v_invite.invited_by, now(), null, v_invite.is_subject)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null,
        is_subject = excluded.is_subject;

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
    'role', v_invite.role,
    'is_subject', v_invite.is_subject
  );
end;
$$;

-- Signature unchanged: the existing grant from
-- 20260905090000_close_guardian_revocation_bypass.sql still applies.

-- ---------------------------------------------------------------------------
-- 4. preview_guardian_invitation — is_subject in the preview
-- ---------------------------------------------------------------------------
-- Body carried verbatim from 20260915060000_guardian_invitation_preview.sql
-- except the is_subject result key. The returned object now carries
-- exactly four fields; the enumeration posture is unchanged (the marker
-- describes only the invitation whose hash the caller already holds).

create or replace function public.preview_guardian_invitation(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_recent_count integer;
  v_invite public.guardian_invitations%rowtype;
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- Bound the table's growth (round-1 review): delete this caller's own
  -- rows outside the trailing window before counting, rather than only
  -- ever relying on the auth.users cascade. Scoped to user_id so this
  -- stays a per-caller operation, not a table-wide sweep. If the rate
  -- limit below raises, this delete rolls back with the rest of the
  -- transaction along with the insert further down - fine, since a
  -- rejected call leaving its own window untouched doesn't defeat the
  -- limit.
  delete from public.guardian_invitation_preview_attempts
   where user_id = v_uid
     and attempted_at <= clock_timestamp() - interval '1 minute';

  select count(*) into v_recent_count
    from public.guardian_invitation_preview_attempts
   where user_id = v_uid
     and attempted_at > clock_timestamp() - interval '1 minute';

  if v_recent_count >= 20 then
    raise exception 'too many preview attempts; wait a moment and try again'
      using errcode = '55000';
  end if;

  insert into public.guardian_invitation_preview_attempts (user_id)
  values (v_uid);

  select * into v_invite
    from public.guardian_invitations
   where token_hash = p_token_hash;

  if not found
     or v_invite.accepted_at is not null
     or v_invite.revoked_at is not null
     or v_invite.expires_at <= now() then
    -- Uniform "not available": wrong token, already accepted, revoked, or
    -- expired are all indistinguishable from here on out.
    return null;
  end if;

  select * into v_profile
    from public.profiles
   where id = v_invite.profile_id;

  if not found or v_profile.deleted_at is not null then
    return null;
  end if;

  return jsonb_build_object(
    'profile_display_name', v_profile.display_name,
    'role', v_invite.role,
    'expires_at', v_invite.expires_at,
    'is_subject', v_invite.is_subject
  );
end;
$$;

comment on function public.preview_guardian_invitation(text) is
  'Issue #594: read-only pre-accept preview for a live, unexpired, un-accepted, un-revoked invitation - returns {profile_display_name, role, expires_at, is_subject}, or SQL null for every other state (uniform, never distinguishing why). Never mutates guardian_invitations or profile_guardians; see this migration''s header for the full security posture. Issue #802 added is_subject (the subject preset) so the accept sheet can promise "this is your profile" before the recipient commits.';

-- Signature and grant unchanged (revoke/grant from
-- 20260915060000_guardian_invitation_preview.sql still apply).

-- ---------------------------------------------------------------------------
-- 5. accept_ownership_transfer — the subject marker follows ownership
-- ---------------------------------------------------------------------------
-- Body carried verbatim from 20260915010000_db_integrity_bundle.sql except
-- the two membership upserts: the demoted parent's row is explicitly
-- is_subject = false (the acceptor is now the subject, whatever either
-- row was before), and the promoted child's row is is_subject = true.

create or replace function public.accept_ownership_transfer(
  p_token_hash text,
  p_child_display_name text default null,
  p_parent_display_name text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_transfer public.ownership_transfers%rowtype;
  v_profile public.profiles%rowtype;
  v_initiator public.profile_guardians%rowtype;
  v_existing public.profile_guardians%rowtype;
  v_day_entries_rehomed bigint := 0;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = 'insufficient_privilege';
  end if;

  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'token_hash must be a 64-character hex string' using errcode = 'invalid_parameter_value';
  end if;

  -- Lock order: ownership_transfers, then profiles, then profile_guardians -
  -- matches accept_guardian_invitation / revoke_guardian's own order, so
  -- the two RPC families cannot deadlock against each other.
  select * into v_transfer
    from public.ownership_transfers
   where token_hash = p_token_hash
   for update;

  if not found then
    raise exception 'transfer not found' using errcode = 'no_data_found';
  end if;

  -- R20: each terminal state gets a distinguishable reason.
  if v_transfer.accepted_at is not null then
    raise exception 'transfer was already accepted' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_transfer.cancelled_at is not null then
    raise exception 'transfer was cancelled' using errcode = 'object_not_in_prerequisite_state';
  end if;

  if v_transfer.expires_at <= clock_timestamp() then
    raise exception 'transfer has expired' using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- R11: the arming parent cannot accept their own transfer. Guarantees
  -- v_transfer.initiated_by <> v_uid below, so the two profile_guardians
  -- locks that follow are always on two distinct rows.
  if v_uid = v_transfer.initiated_by then
    raise exception 'the arming parent cannot accept their own transfer'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  select * into v_profile
    from public.profiles
   where id = v_transfer.profile_id
   for update;

  if not found then
    raise exception 'profile not found' using errcode = 'no_data_found';
  end if;

  -- Stale-link guard (1 of 2): the armer must still own the profile.
  if v_profile.user_id is distinct from v_transfer.initiated_by then
    raise exception 'the arming parent no longer owns this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- LLA-054/LLA-056: lock the initiator's and the acceptor's own
  -- profile_guardians rows before checking either's authority, in
  -- ascending user_id order - this migration's binding convention, so
  -- this can never deadlock against update_guardian_role or
  -- revoke_guardian locking the same pair of rows. Previously the
  -- initiator's role was read via
  -- is_guardian_with_roles(v_transfer.profile_id, v_transfer.initiated_by,
  -- array['primary_guardian']) - an UNLOCKED read of someone else's
  -- membership row (LLA-054's TOCTOU) through a helper that LLA-056 (Part
  -- 1 above) now refuses to answer for any p_user_id other than the
  -- caller's own auth.uid() anyway (LLA-056). Querying profile_guardians
  -- directly, inline, under a lock, fixes both at once.
  if v_transfer.initiated_by < v_uid then
    select * into v_initiator
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_transfer.initiated_by
       and status = 'accepted'
     for update;
    select * into v_existing
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_uid
     for update;
  else
    select * into v_existing
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_uid
     for update;
    select * into v_initiator
      from public.profile_guardians
     where profile_id = v_transfer.profile_id
       and user_id = v_transfer.initiated_by
       and status = 'accepted'
     for update;
  end if;

  -- Stale-link guard (2 of 2): the armer must still be the accepted
  -- primary_guardian. v_initiator.role reads null (distinct from
  -- 'primary_guardian') both when no row exists at all and when one exists
  -- but is not status = 'accepted' (the WHERE clause above already
  -- excludes it), matching is_guardian_with_roles()'s original semantics
  -- exactly.
  if v_initiator.role is distinct from 'primary_guardian' then
    raise exception 'the arming parent is no longer the primary guardian of this profile; the link is stale'
      using errcode = 'object_not_in_prerequisite_state';
  end if;

  -- Review item #1 (P0), acceptor-freshness check: the mirror of
  -- accept_guardian_invitation's #82 guard, applied to the acceptor rather
  -- than the arming parent. v_existing.user_id is not null stands in for
  -- the old `found` (unreliable here, since which SELECT ran last differs
  -- by branch above).
  if v_existing.user_id is not null and v_existing.status = 'revoked' then
    if v_existing.revoked_at is null or v_transfer.created_at <= v_existing.revoked_at then
      raise exception 'guardian access to this profile was revoked; a new transfer link is required'
        using errcode = 'object_not_in_prerequisite_state';
    end if;
  end if;

  -- KTD4: arm the transaction-local bypass so the re-home below can move
  -- day_entries.user_id (and, per Issue #616/LLA-059 below, profiles.
  -- transferred_at/transferred_to_user_id) without tripping either
  -- attribution/authoritative-field guard.
  perform set_config('lunarlog.ownership_transfer', 'on', true);

  -- R12: profiles.user_id moves to the accepting user; transferred_at is
  -- stamped. Issue #296: transferred_to_user_id is stamped with the same
  -- accepting uid, in the same statement.
  update public.profiles
     set user_id = v_uid,
         transferred_at = clock_timestamp(),
         transferred_to_user_id = v_uid,
         updated_at = greatest(updated_at, clock_timestamp())
   where id = v_transfer.profile_id;

  -- R15/R16/R17: re-point the cascade anchor for EVERY entry on the
  -- profile, not only the ones currently anchored to the arming parent.
  update public.day_entries
     set user_id = v_uid
   where profile_id = v_transfer.profile_id;
  get diagnostics v_day_entries_rehomed = row_count;

  -- R14: demote the parent to their chosen role BEFORE promoting the child,
  -- so profile_guardians_one_primary_uq (R22) is never transiently violated.
  -- Issue #802: is_subject = false explicitly - the accepting child is now
  -- the profile's subject; the ex-parent is a helper by definition.
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, updated_at, revoked_at, is_subject)
  values
    (v_transfer.profile_id, v_transfer.initiated_by, v_transfer.parent_post_transfer_role, 'accepted',
     p_parent_display_name, clock_timestamp(), null, false)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null,
        is_subject = false;

  -- R13: promote the child to the profile's sole primary_guardian.
  -- Issue #802: is_subject = true - accepting ownership of the profile
  -- makes the acceptor its subject outright, whether or not they held a
  -- subject membership before (a plain invitee can be transferred to
  -- directly).
  insert into public.profile_guardians
    (profile_id, user_id, role, status, display_name, invited_by, updated_at, revoked_at, is_subject)
  values
    (v_transfer.profile_id, v_uid, 'primary_guardian', 'accepted', p_child_display_name,
     v_transfer.initiated_by, clock_timestamp(), null, true)
  on conflict (profile_id, user_id) do update
    set role = excluded.role,
        status = 'accepted',
        display_name = coalesce(excluded.display_name, profile_guardians.display_name),
        updated_at = excluded.updated_at,
        revoked_at = null,
        is_subject = true;

  -- R18: single-use.
  update public.ownership_transfers
     set accepted_at = clock_timestamp(),
         accepted_by = v_uid
   where id = v_transfer.id;

  -- Any other still-live transfer for this profile is now moot.
  update public.ownership_transfers
     set cancelled_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and id <> v_transfer.id
     and accepted_at is null
     and cancelled_at is null;

  -- Review item #4 (P1): the ex-parent's own still-live guardian invitations
  -- for this profile are decisions made under an ownership that no longer
  -- holds.
  update public.guardian_invitations
     set revoked_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and accepted_at is null
     and revoked_at is null;

  -- Issue #496: the ex-parent's live prediction connections for this
  -- profile must be revoked upon transfer.
  update public.prediction_connections
     set revoked_at = clock_timestamp()
   where profile_id = v_transfer.profile_id
     and revoked_at is null;

  return jsonb_build_object(
    'profile_id', v_transfer.profile_id,
    'profile_name', v_profile.display_name,
    'parent_role', v_transfer.parent_post_transfer_role,
    'day_entries_rehomed', v_day_entries_rehomed
  );
end;
$$;

-- Signature unchanged: the existing grant from
-- 20260915010000_db_integrity_bundle.sql still applies.
