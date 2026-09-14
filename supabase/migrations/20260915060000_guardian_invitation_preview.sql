-- Migration: 20260915060000_guardian_invitation_preview.sql
-- Implements Issue #594: a pre-accept preview RPC so the accept sheet isn't
-- blind consent. #580 fixed the hardcoded "a child profile" wording and the
-- signed-out latch, but the accept sheet still could not show *whose*
-- profile or *which* role before the recipient committed - no server RPC
-- returned that for an un-redeemed token (see accept_invite_sheet.dart's
-- own header, written for #535 (a), for the prior state of the world).
--
-- preview_guardian_invitation(p_token_hash) returns
-- {profile_display_name, role, expires_at} for a live, unexpired,
-- un-accepted, un-revoked invitation whose token_hash the caller presents -
-- the same
-- hash create_guardian_invitation/accept_guardian_invitation already use
-- (SHA-256 hex of the raw token, computed client-side; the raw token itself
-- is never stored server-side - see 20260908000000_guardian_invitations_
-- token_hash_unreadable.sql's header). Presenting the correct hash is the
-- only way to reach a row at all; this RPC changes nothing about who can
-- redeem what, only what a caller who already holds the token can see
-- *before* redeeming.
--
-- Security posture (R6/enumeration):
-- - SECURITY DEFINER, search_path pinned to '' (matches every other
--   guardian_invitations RPC in this schema), owned by the table owner so
--   the authenticated-scoped column grants on guardian_invitations
--   (token_hash unreadable - see the migration above) never apply to it.
-- - authenticated only, not anon: the existing client flow already
--   requires a session before the accept sheet (and so this preview) is
--   ever shown - lib/app.dart's _maybePresentInvite latches a signed-out
--   recipient's code and shows a "Sign in to accept your invite" banner
--   instead of presenting AcceptInviteSheet; accept_guardian_invitation
--   itself has required auth.uid() since it was written. Granting this to
--   anon as well would only add exposure with no product need it serves
--   today - if a genuinely signed-out preview becomes a requirement, that
--   is a deliberate, separate product decision, not a default.
-- - Every non-live state (wrong token_hash, expired, revoked, or already
--   accepted) returns the same SQL null, not a distinguishable error or
--   row - collapsing "no such token" and "token existed but is now dead"
--   into one outcome, so this can never be used as an oracle for which
--   state applies. A soft-deleted profile also returns null through the
--   same path - the invitation may still be technically live, but there
--   is nothing safe to preview.
-- - The returned object carries exactly three fields: profile_display_name,
--   role, and expires_at. No profile id, no invited_by, no other
--   guardians, no accepted/revoked timestamps, nothing that could seed a
--   follow-up enumeration query the way a raw profile id could
--   (profile_guardians is queryable by profile_id for any accepted
--   guardian).
-- - No membership change: this function only ever reads guardian_
--   invitations and profiles; it never touches profile_guardians or the
--   invitation row itself. accept_guardian_invitation remains the only
--   RPC that commits anything.
-- - Rate-limited per caller: an authenticated caller has an auth.uid() to
--   key on (unlike an anon caller, which is exactly why this stays
--   authenticated-only above), so a small attempts log lets this refuse a
--   21st preview call within a trailing minute from the same caller - not
--   a defense against a determined distributed attacker, but it bounds
--   how fast a single account can grind through guesses via this RPC
--   specifically, and 20/minute is generous enough that no legitimate
--   retry loop (a flaky network, a mistyped/re-pasted deep link) should
--   ever hit it. Bounded growth (round-1 review): every call deletes this
--   same caller's own rows outside the trailing window before counting,
--   so the table never holds more than each caller's own live window
--   (never unbounded growth from `auth.users` cascade alone), and the
--   work stays proportional to the calling user, not the whole table.

-- ---------------------------------------------------------------------------
-- 1. guardian_invitation_preview_attempts - write-only rate-limit bookkeeping
-- ---------------------------------------------------------------------------

create table public.guardian_invitation_preview_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null
    references auth.users (id) on delete cascade,
  attempted_at timestamptz not null default clock_timestamp()
);

comment on table public.guardian_invitation_preview_attempts is
  'Issue #594: per-caller attempt log backing preview_guardian_invitation''s rate limit. Write-only bookkeeping, touched only by that SECURITY DEFINER function - never selected, inserted, or deleted by a client directly (no grants to authenticated/anon below), so its own presence carries no information a client can read.';

create index guardian_invitation_preview_attempts_user_id_attempted_at_idx
  on public.guardian_invitation_preview_attempts (user_id, attempted_at);

alter table public.guardian_invitation_preview_attempts enable row level security;
-- Deliberately no policies and no grants to authenticated/anon: only the
-- SECURITY DEFINER function below (running as the table owner) ever
-- reads or writes this table. RLS with zero policies denies every
-- non-owner statement outright, belt-and-braces alongside the revoke.
revoke all on table public.guardian_invitation_preview_attempts from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. preview_guardian_invitation
-- ---------------------------------------------------------------------------

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
    'expires_at', v_invite.expires_at
  );
end;
$$;

comment on function public.preview_guardian_invitation(text) is
  'Issue #594: read-only pre-accept preview for a live, unexpired, un-accepted, un-revoked invitation - returns {profile_display_name, role, expires_at}, or SQL null for every other state (uniform, never distinguishing why). Never mutates guardian_invitations or profile_guardians; see this migration''s header for the full security posture.';

revoke all on function public.preview_guardian_invitation(text) from public, anon;
grant execute on function public.preview_guardian_invitation(text) to authenticated;
