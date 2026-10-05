/**
 * The web client's family-sharing data layer (issue #1255).
 *
 * Thin, typed wrappers over the exact RPCs and tables the Flutter client
 * uses — no new server surface (epic #831 decision D4):
 *
 * - `create_guardian_invitation` / `preview_guardian_invitation` /
 *   `accept_guardian_invitation` / `update_guardian_role` / `revoke_guardian`
 *   / `revoke_guardian_invitation` (`20260904020000`,
 *   `20260906190000`, `20260909140004`, `20260915060000`,
 *   `20260920120000`)
 * - `create_ownership_transfer` / `cancel_ownership_transfer` /
 *   `accept_ownership_transfer` (`20260906180000`)
 * - `record_minimum_age_acknowledgement` (`20260921100000`, the #845/#957
 *   consent record)
 * - `sync_push` for guardian-note and care-note writes (the same sole write
 *   path the phones use; `day_entries`-style direct writes are not granted
 *   and are not attempted)
 *
 * Invitation and transfer tokens mirror `SupabaseSharingService`: 32 random
 * bytes, base64url without padding, redeemed by the SHA-256 hex hash — the
 * raw token never leaves the URL it arrived in, and only the hash reaches
 * the server.
 */

import { z } from './zod';

import type { Json } from '../../../supabase/database.types';
import { webAuth } from './auth';
import { learnClockOffset } from './domain';
import type { AppSupabaseClient } from './supabase';
import { ulidSchema } from './schemas';
import { isValidUlid, UlidGenerator } from './ulid';
import type { GuardianRole } from './roles';

// ---------------------------------------------------------------------------
// Typed failures — the client-side mirror of SupabaseSharingService's
// SharingFailure / TransferFailure mapping.
// ---------------------------------------------------------------------------

export type SharingFailureKind =
  | 'network'
  | 'notFound'
  | 'expired'
  | 'revoked'
  | 'alreadyAccepted'
  | 'alreadyGuardian'
  | 'unauthorized'
  | 'notSignedIn'
  | 'invalidToken'
  | 'cancelled'
  | 'selfTransfer'
  | 'staleOwner'
  | 'alreadyArmed'
  | 'other';

/**
 * The catalogue keys each failure kind reads its copy from — the web mirror
 * of `sharing_failure_copy.dart` / `transfer_failure_copy.dart`. Kept next to
 * the mapping so a new kind cannot land without its copy decision.
 */
export function sharingFailureMessageId(kind: SharingFailureKind) {
  switch (kind) {
    case 'network':
      return 'commonNetworkError' as const;
    case 'notFound':
      return 'sharingFailureNotFound' as const;
    case 'expired':
      return 'sharingFailureExpired' as const;
    case 'revoked':
      return 'sharingFailureRevoked' as const;
    case 'alreadyAccepted':
      return 'sharingFailureAlreadyAccepted' as const;
    case 'alreadyGuardian':
      return 'sharingFailureAlreadyGuardian' as const;
    case 'unauthorized':
      return 'commonUnauthorized' as const;
    case 'notSignedIn':
      return 'sharingFailureNotSignedIn' as const;
    case 'invalidToken':
      return 'sharingFailureInvalidToken' as const;
    case 'cancelled':
      return 'transferFailureCancelled' as const;
    case 'selfTransfer':
      return 'transferFailureSelfTransfer' as const;
    case 'staleOwner':
      return 'transferFailureStaleOwner' as const;
    case 'alreadyArmed':
      return 'transferFailureAlreadyArmed' as const;
    case 'other':
      return 'sharingFailureOther' as const;
  }
}

/**
 * The line for a removal (or a leave) that failed, the app's
 * `_revokeErrorMessage` (lib/ui/sharing/manage_guardians_screen.dart).
 *
 * `selfPrimaryLeave` is a primary guardian leaving. The one thing the
 * server refuses her for, apart from permission, is being the only primary
 * guardian left, which another device can make true between the tap and
 * the call. That is inferred from who was leaving, so it is read only
 * after the two answers that say nothing about it: a refusal for lack of
 * permission, and a request that never arrived.
 */
export function revokeFailureMessageId(kind: SharingFailureKind, selfPrimaryLeave: boolean) {
  if (kind === 'unauthorized') return 'commonUnauthorized' as const;
  if (kind === 'network') return 'sharingManageGuardiansRemoveFailed' as const;
  if (selfPrimaryLeave) return 'sharingManageGuardiansSolePrimaryLeave' as const;
  return 'sharingManageGuardiansRemoveFailed' as const;
}

/**
 * The line for an invitation that could not be created, the app's
 * `inviteCreateFailureCopy`. `sharingFailureMessageId` is written for the
 * person accepting one, so only the three answers that mean the same for
 * any action are shared with it.
 */
export function createInviteFailureMessageId(kind: SharingFailureKind) {
  switch (kind) {
    case 'network':
      return 'commonNetworkError' as const;
    case 'unauthorized':
      return 'commonUnauthorized' as const;
    case 'notSignedIn':
      return 'sharingFailureNotSignedIn' as const;
    default:
      return 'commonSomethingWentWrong' as const;
  }
}

/**
 * The line for a guardian list that could not be loaded. Again not
 * `sharingFailureMessageId`: its generic line is "Failed to accept
 * invitation", which is what this page used to show for a failed load.
 */
export function guardiansLoadFailureMessageId(kind: SharingFailureKind) {
  switch (kind) {
    case 'network':
      return 'commonNetworkError' as const;
    case 'unauthorized':
      return 'commonUnauthorized' as const;
    case 'notSignedIn':
      return 'sharingFailureNotSignedIn' as const;
    default:
      return 'webGuardiansLoadFailed' as const;
  }
}

/** The line for a role change that failed, the app's `_roleChangeErrorMessage`. */
export function roleChangeFailureMessageId(kind: SharingFailureKind) {
  return kind === 'unauthorized'
    ? ('commonUnauthorized' as const)
    : ('sharingManageGuardiansRoleUpdateFailed' as const);
}

/**
 * The transfer-surface variant: the transfer failures carry their own
 * reviewed copy (`transfer_failure_copy.dart`), so the claim form reads from
 * this map, not the invitation one.
 */
export function transferFailureMessageId(kind: SharingFailureKind) {
  switch (kind) {
    case 'network':
      return 'commonNetworkError' as const;
    case 'notFound':
      return 'transferFailureNotFound' as const;
    case 'expired':
      return 'transferFailureExpired' as const;
    case 'alreadyAccepted':
      return 'transferFailureAlreadyAccepted' as const;
    case 'unauthorized':
      return 'commonUnauthorized' as const;
    case 'notSignedIn':
      return 'sharingFailureNotSignedIn' as const;
    case 'invalidToken':
      return 'transferFailureInvalidToken' as const;
    case 'cancelled':
      return 'transferFailureCancelled' as const;
    case 'selfTransfer':
      return 'transferFailureSelfTransfer' as const;
    case 'staleOwner':
      return 'transferFailureStaleOwner' as const;
    case 'alreadyArmed':
      return 'transferFailureAlreadyArmed' as const;
    // The invitation ladder's own kinds: the transfer ladder never returns
    // them (a claimant whose access was removed reads as `staleOwner`).
    case 'alreadyGuardian':
    case 'revoked':
    case 'other':
      return 'commonSomethingWentWrong' as const;
  }
}

/** The error every wrapper throws: a typed kind, never a raw message. */
export class SharingError extends Error {
  readonly kind: SharingFailureKind;
  constructor(kind: SharingFailureKind) {
    super(kind);
    this.name = 'SharingError';
    this.kind = kind;
  }
}

/** Shape of supabase-js's PostgrestError, restated for the mappers. */
export interface PostgrestErrorLike {
  message: string;
  code?: string | null;
}

/**
 * Maps one supabase-js error to a typed invitation/role failure, mirroring
 * `SupabaseSharingService._mapError`'s ladder in order. `status` is the
 * HTTP status supabase-js reports beside the error (see `isServerFailure`).
 */
export function mapSharingFailure(
  error: unknown,
  signedIn: boolean = false,
  status?: number,
): SharingError {
  return mapFailure(error, signedIn, mapInvitationBusiness, status);
}

/**
 * Maps one supabase-js error to a typed ownership-transfer failure,
 * mirroring `SupabaseOwnershipTransferService._mapError`'s ladder in order —
 * in particular 23505 reads as "a transfer is already armed" here, never as
 * the invitation mapper's "already guardian".
 */
export function mapTransferFailure(
  error: unknown,
  signedIn: boolean = false,
  status?: number,
): SharingError {
  return mapFailure(error, signedIn, mapTransferBusiness, status);
}

function mapFailure(
  error: unknown,
  signedIn: boolean,
  business: (code: string, msg: string) => SharingFailureKind | null,
  status: number | undefined,
): SharingError {
  if (error instanceof SharingError) return error;
  const postgrest = error as Partial<PostgrestErrorLike> | null;
  if (
    postgrest !== null &&
    typeof postgrest === 'object' &&
    typeof postgrest.message === 'string'
  ) {
    return new SharingError(
      mapPostgrest(postgrest.code ?? '', postgrest.message, signedIn, business, status),
    );
  }
  return new SharingError('other');
}

function mapPostgrest(
  code: string,
  message: string,
  signedIn: boolean,
  business: (code: string, msg: string) => SharingFailureKind | null,
  status: number | undefined,
): SharingFailureKind {
  // Decided first (issue #1504): what answered was not PostgREST, so the
  // message is a gateway's page or the browser's own fetch error. It is not
  // a refusal, and its text is not read for one.
  if (isServerFailure(code, status)) return 'network';
  const msg = message.toLowerCase();
  if (isUnauthorized(code, msg)) {
    // The server refuses an unauthenticated caller the same way it refuses
    // an under-privileged one (42501), but with no session the honest copy
    // is "sign in" (issue #885's posture).
    return signedIn ? 'unauthorized' : 'notSignedIn';
  }
  return business(code, msg) ?? 'other';
}

/**
 * Whether the call got no answer from PostgREST at all — the request never
 * completed, or something in front of PostgREST answered 5xx — rather than
 * a refusal the server chose (issue #1504).
 *
 * The two arrive in different places. `error.code` is the server's own
 * code: a five-character SQLSTATE (`55000`, `P0001`, `42501`) or one of
 * PostgREST's (`PGRST301`). It is never an HTTP status, and its digits say
 * nothing about one: "invitation was revoked" is `55000`, which the old
 * test (any all-digit code of 500 or more) read as a server failure.
 * PostgREST also answers every class-55 refusal with HTTP 500, so the
 * status of a response that carries a code says nothing either.
 *
 * The HTTP status is the response's `status`, beside the error. supabase-js
 * sets it to 0 and the code to `''` when the request never completed, and
 * leaves the code out when the body was not PostgREST's (a gateway's 5xx
 * page). A three-digit `code` is read as a status as well: that is where
 * the app's client puts it (`SupabaseSharingService._isServerFailure`), and
 * the two mappers stay the same.
 */
function isServerFailure(code: string, status: number | undefined): boolean {
  const reported = /^\d{3}$/.test(code)
    ? Number.parseInt(code, 10)
    : code === ''
      ? status
      : undefined;
  return reported !== undefined && (reported === 0 || reported >= 500);
}

function isUnauthorized(code: string, msg: string): boolean {
  return (
    code === 'PGRST301' ||
    code === '42501' ||
    msg.includes('permission') ||
    msg.includes('unauthorized')
  );
}

function mapInvitationBusiness(code: string, msg: string): SharingFailureKind | null {
  if (code === 'P0002' || msg.includes('not found')) return 'notFound';
  if (msg.includes('already accepted')) return 'alreadyAccepted';
  if (msg.includes('expired')) return 'expired';
  // Issue #1504: "invitation was revoked" (whoever sent it cancelled it) and
  // "guardian access to this profile was revoked; a new invitation is
  // required" (the invitee was removed after it was sent). Both are 55000,
  // and for both the way forward is a new invitation.
  if (msg.includes('revoked')) return 'revoked';
  if (code === '23505' || msg.includes('already an active guardian')) return 'alreadyGuardian';
  if (code === '22023' || msg.includes('invalid') || msg.includes('token_hash'))
    return 'invalidToken';
  return null;
}

function mapTransferBusiness(code: string, msg: string): SharingFailureKind | null {
  if (code === 'P0002') return 'notFound';
  // 23505 on create means a live transfer already exists for this profile —
  // the caller's signal to offer cancelling it, not a dead end (review #2).
  if (code === '23505') return 'alreadyArmed';
  if (code === '22023') return msg.includes('token') ? 'invalidToken' : 'other';
  // Ordered substring ladder — first match wins (`_messageFailures`).
  if (msg.includes('not found')) return 'notFound';
  if (msg.includes('already accepted')) return 'alreadyAccepted';
  if (msg.includes('cancelled')) return 'cancelled';
  if (msg.includes('expired')) return 'expired';
  if (msg.includes('cannot accept their own transfer')) return 'selfTransfer';
  // The third (issue #1504) is the claimant's own side of the same thing:
  // "guardian access to this profile was revoked; a new transfer link is
  // required". Her role on the profile changed after the link was made,
  // which is what the stale-link copy says.
  if (
    msg.includes('no longer owns this profile') ||
    msg.includes('no longer the primary guardian') ||
    msg.includes('a new transfer link is required')
  ) {
    return 'staleOwner';
  }
  return null;
}

/**
 * Maps with the caller's own auth state deciding notSignedIn vs
 * unauthorized. `status` is the response's HTTP status, which every wrapper
 * passes along with the error: it is what tells a request that never
 * completed, or a gateway's 5xx, from a refusal (`isServerFailure`).
 */
async function failureFor(
  client: AppSupabaseClient,
  error: unknown,
  transfer: boolean,
  status: number | undefined,
): Promise<SharingError> {
  const signedIn = await isSignedIn(client);
  return transfer
    ? mapTransferFailure(error, signedIn, status)
    : mapSharingFailure(error, signedIn, status);
}

/**
 * Whether the caller has a session (see `sessionUserId` for the two client
 * kinds and why the storage read can throw on the app client).
 */
export async function isSignedIn(client: AppSupabaseClient): Promise<boolean> {
  return (await sessionUserId(client)) !== null;
}

// ---------------------------------------------------------------------------
// Token generation — mirrors SupabaseSharingService.createInvite steps 1-2.
// ---------------------------------------------------------------------------

const subtle = (): SubtleCrypto => {
  const c = globalThis.crypto;
  if (c === undefined || c.subtle === undefined) {
    throw new SharingError('other');
  }
  return c.subtle;
};

/** SHA-256 of `input` as lowercase hex (the wire form of `p_token_hash`). */
export async function sha256Hex(
  input: string,
  digest: SubtleCrypto['digest'] = subtle().digest.bind(subtle()),
): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const hash = await digest('SHA-256', bytes);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * Generates a 256-bit invitation/transfer token: base64url without padding,
 * exactly `base64UrlEncode(bytes).replaceAll('=', '')` in Dart. Returns the
 * redeemable raw token (URL-only, never logged or stored) and a promise for
 * its server-side hash.
 */
export function generateInviteToken(
  randomBytes: (length: number) => Uint8Array = defaultRandomBytes,
  digest: SubtleCrypto['digest'] = subtle().digest.bind(subtle()),
): { rawToken: string; tokenHash: Promise<string> } {
  const rawToken = base64UrlNoPad(randomBytes(32));
  return { rawToken, tokenHash: sha256Hex(rawToken, digest) };
}

function defaultRandomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

function base64UrlNoPad(bytes: Uint8Array): string {
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// ---------------------------------------------------------------------------
// Row schemas (Zod at the boundary, like schemas.ts).
// ---------------------------------------------------------------------------

/**
 * The sharing tables' own primary keys are `uuid primary key default
 * gen_random_uuid()` — `profile_guardians`/`guardian_invitations`
 * (20260904010000) and `ownership_transfers` (20260906170000) — the same
 * shape `schemas.ts`'s `profileGuardianSchema` already validates. Issue
 * #1284: these were `z.ulid()`, which no real row passes — every guardian
 * read threw a ZodError before rendering. The profile-scoped ids
 * (`profile_id`, note ids) stay `ulidSchema`: those rows are
 * client-generated ULIDs written through `sync_push`.
 */
const sharingRowId = z.uuid();

/**
 * `profile_guardians.is_subject` is nullable with no backfill
 * (20260920120000), and a server predating that migration omits the key
 * from the RPC results entirely — the migration's own contract is that the
 * client "decodes a missing/null is_subject as false". Zod `.default`
 * replaces only `undefined`, so one pre-#802 null failed the whole list
 * (issue #1284); this accepts null and absent and reads both as false.
 */
const isSubjectSchema = z
  .boolean()
  .nullable()
  .optional()
  .transform((value) => value ?? false);

export const guardianRowSchema = z.object({
  id: sharingRowId,
  profile_id: ulidSchema,
  user_id: z.uuid(),
  // Fail closed to the least-privileged role, matching the app (#540).
  role: z.string().transform((value) => guardianRoleSchemaSafe(value) ?? 'viewer'),
  status: z.string().transform((value) => {
    switch (value) {
      case 'pending':
      case 'accepted':
      case 'revoked':
        return value;
      default:
        // Least privilege: an unrecognised status reads as revoked (#540).
        return 'revoked' as const;
    }
  }),
  display_name: z.string().nullable(),
  invited_by: z.uuid().nullable(),
  is_subject: isSubjectSchema,
  created_at: z.string(),
  updated_at: z.string(),
});

function guardianRoleSchemaSafe(value: string): GuardianRole | null {
  switch (value) {
    case 'primary_guardian':
    case 'co_parent':
    case 'caregiver':
    case 'viewer':
      return value;
    default:
      return null;
  }
}

export type GuardianRow = z.infer<typeof guardianRowSchema>;

/** The pending-invite projection — deliberately never `token_hash` (R6).
 * `invited_by` rides along for the cancel ladder (issue #1285): a co-parent
 * may not cancel a co_parent invitation someone else created. */
export const pendingInviteRowSchema = z.object({
  id: sharingRowId,
  profile_id: ulidSchema,
  // Fail closed to the least-privileged role, matching the app (#540).
  role: z.string().transform((value) => guardianRoleSchemaSafe(value) ?? 'viewer'),
  invited_by: z.uuid().nullable(),
  recipient_label: z.string().nullable(),
  created_at: z.string(),
  expires_at: z.string(),
  is_subject: isSubjectSchema,
});

export type PendingInviteRow = z.infer<typeof pendingInviteRowSchema>;

export const activeTransferRowSchema = z.object({
  id: sharingRowId,
  profile_id: ulidSchema,
  parent_post_transfer_role: z
    .string()
    .refine(
      (value) => value === 'co_parent' || value === 'viewer',
      'unknown post-transfer role',
    ),
  recipient_label: z.string().nullable(),
  expires_at: z.string(),
});

export type ActiveTransferRow = z.infer<typeof activeTransferRowSchema>;

export const invitePreviewSchema = z.object({
  profile_display_name: z.string(),
  role: z.string().transform((value) => guardianRoleSchemaSafe(value) ?? 'viewer'),
  expires_at: z.string(),
  is_subject: isSubjectSchema,
});

export type InvitePreview = z.infer<typeof invitePreviewSchema>;

export const acceptedInviteSchema = z.object({
  profile_id: ulidSchema,
  profile_name: z.string(),
  role: z.string().transform((value) => guardianRoleSchemaSafe(value) ?? 'viewer'),
  is_subject: isSubjectSchema,
});

export type AcceptedInvite = z.infer<typeof acceptedInviteSchema>;

export const createdInvitationSchema = z.object({
  id: sharingRowId,
  profile_id: ulidSchema,
  role: z.string().transform((value) => guardianRoleSchemaSafe(value) ?? 'viewer'),
  expires_at: z.string(),
});

export type CreatedInvitation = z.infer<typeof createdInvitationSchema>;

export const createdTransferSchema = z.object({
  id: sharingRowId,
  expires_at: z.string(),
});

export type CreatedTransfer = z.infer<typeof createdTransferSchema>;

export const claimedTransferSchema = z.object({
  profile_id: ulidSchema,
  profile_name: z.string(),
  parent_role: z.string(),
  day_entries_rehomed: z.number(),
});

export type ClaimedTransfer = z.infer<typeof claimedTransferSchema>;

export const invitationOutcomeSchema = z.object({
  outcome: z.enum(['revoked', 'already_revoked', 'already_accepted', 'expired']),
});

export type InvitationOutcome = z.infer<typeof invitationOutcomeSchema>['outcome'];

export const guardianNoteRowSchema = z.object({
  id: ulidSchema,
  profile_id: ulidSchema,
  local_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date'),
  tz: z.string(),
  body: z.string(),
  logged_by_user_id: z.uuid().nullable(),
  updated_at: z.string(),
});

export type GuardianNoteRow = z.infer<typeof guardianNoteRowSchema>;

export const careNoteRowSchema = z.object({
  id: ulidSchema,
  profile_id: ulidSchema,
  body: z.string(),
  logged_by_user_id: z.uuid().nullable(),
  last_modified_by_user_id: z.uuid().nullable(),
  updated_at: z.string(),
});

export type CareNoteRow = z.infer<typeof careNoteRowSchema>;

// ---------------------------------------------------------------------------
// Reads.
// ---------------------------------------------------------------------------

/** Every membership row the caller may see for `profileId` (RLS-scoped). */
export async function fetchGuardians(
  client: AppSupabaseClient,
  profileId: string,
): Promise<GuardianRow[]> {
  const { data, error, status } = await client
    .from('profile_guardians')
    .select('*')
    .eq('profile_id', profileId)
    .order('created_at');
  if (error !== null) throw await failureFor(client, error, false, status);
  return z.array(guardianRowSchema).parse(data);
}

/**
 * How far back an expired invitation stays visible — the same seven-day
 * window `SupabaseSharingService.recentlyExpiredWindow` uses, so an aged-out
 * invitation is visible as expired rather than vanishing (issue #362).
 */
export const RECENTLY_EXPIRED_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * `profileId`'s outstanding invitations, live plus recently expired ones
 * (issue #362). Explicit column list — never `token_hash`, so a screenshot
 * of the pending list is not redeemable (R6/enumeration, mirrored from the
 * app's identical discipline); `invited_by` is read for the cancel ladder
 * (issue #1285).
 */
export async function fetchPendingInvites(
  client: AppSupabaseClient,
  profileId: string,
  now: Date = new Date(),
): Promise<PendingInviteRow[]> {
  const cutoff = new Date(now.getTime() - RECENTLY_EXPIRED_WINDOW_MS).toISOString();
  const { data, error, status } = await client
    .from('guardian_invitations')
    .select(
      'id, profile_id, role, invited_by, recipient_label, created_at, expires_at, is_subject',
    )
    .eq('profile_id', profileId)
    .is('accepted_at', null)
    .is('revoked_at', null)
    .gt('expires_at', cutoff)
    .order('created_at', { ascending: true });
  if (error !== null) throw await failureFor(client, error, false, status);
  return z.array(pendingInviteRowSchema).parse(data);
}

/**
 * The still-live ownership transfer for `profileId`, if any — read directly
 * off `ownership_transfers` (no RPC), the same recovery read the app's
 * `getActiveTransfer` makes (review #2, P1 of the transfer PR).
 */
export async function fetchActiveTransfer(
  client: AppSupabaseClient,
  profileId: string,
  now: Date = new Date(),
): Promise<ActiveTransferRow | null> {
  const { data, error, status } = await client
    .from('ownership_transfers')
    .select('id, profile_id, parent_post_transfer_role, recipient_label, expires_at')
    .eq('profile_id', profileId)
    .is('accepted_at', null)
    .is('cancelled_at', null)
    .gt('expires_at', now.toISOString())
    .limit(1)
    .maybeSingle();
  if (error !== null) throw await failureFor(client, error, false, status);
  return data === null ? null : activeTransferRowSchema.parse(data);
}

/** PostgREST's default row cap per response — anything past it paginates. */
const PAGE_SIZE = 500;

/**
 * A paginated full read of `guardian_notes` for `profileId` (live rows
 * only). PostgREST caps a response at its max-rows setting, so pages are
 * looped until a short page arrives (issue #1252's pagination rule, applied
 * to the notes this slice reads).
 */
export async function fetchGuardianNotes(
  client: AppSupabaseClient,
  profileId: string,
): Promise<GuardianNoteRow[]> {
  const rows: GuardianNoteRow[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error, status } = await client
      .from('guardian_notes')
      .select('id, profile_id, local_date, tz, body, logged_by_user_id, updated_at')
      .eq('profile_id', profileId)
      .is('deleted_at', null)
      .order('updated_at', { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);
    if (error !== null) throw await failureFor(client, error, false, status);
    const page = z.array(guardianNoteRowSchema).parse(data);
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

/** One local date's live guardian notes for `profileId`, paginated. */
export async function fetchGuardianNotesForDate(
  client: AppSupabaseClient,
  profileId: string,
  localDate: string,
): Promise<GuardianNoteRow[]> {
  const rows: GuardianNoteRow[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error, status } = await client
      .from('guardian_notes')
      .select('id, profile_id, local_date, tz, body, logged_by_user_id, updated_at')
      .eq('profile_id', profileId)
      .eq('local_date', localDate)
      .is('deleted_at', null)
      .order('updated_at', { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);
    if (error !== null) throw await failureFor(client, error, false, status);
    const page = z.array(guardianNoteRowSchema).parse(data);
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

/** The profile's live care notes, paginated. */
export async function fetchCareNotes(
  client: AppSupabaseClient,
  profileId: string,
): Promise<CareNoteRow[]> {
  const rows: CareNoteRow[] = [];
  for (let offset = 0; ; offset += PAGE_SIZE) {
    const { data, error, status } = await client
      .from('care_notes')
      .select('id, profile_id, body, logged_by_user_id, last_modified_by_user_id, updated_at')
      .eq('profile_id', profileId)
      .is('deleted_at', null)
      .order('updated_at', { ascending: true })
      .range(offset, offset + PAGE_SIZE - 1);
    if (error !== null) throw await failureFor(client, error, false, status);
    const page = z.array(careNoteRowSchema).parse(data);
    rows.push(...page);
    if (page.length < PAGE_SIZE) return rows;
  }
}

/**
 * The session user's id, or null when signed out. Two client kinds: a
 * storage-backed client (test fakes, issue #1252's integration clients)
 * answers from its in-memory session; the app client carries supabase-js's
 * `accessToken` option (issue #1250), whose contract makes the `auth`
 * namespace unusable — the call throws — so the id falls back to the auth
 * Worker's session (one single-flighted /auth/session probe, user echoed
 * with the token).
 */
export async function sessionUserId(client: AppSupabaseClient): Promise<string | null> {
  try {
    const { data } = await client.auth.getSession();
    return data.session?.user.id ?? null;
  } catch {
    const token = await webAuth.getToken().catch(() => null);
    return token === null ? null : (webAuth.getUser()?.id ?? null);
  }
}

/**
 * The signed-in account's id, or null when there is no session — the same
 * check `failureFor` makes.
 */
export async function currentUserId(client: AppSupabaseClient): Promise<string | null> {
  return sessionUserId(client);
}

// ---------------------------------------------------------------------------
// Invitation RPCs.
// ---------------------------------------------------------------------------

/** Server-bounded TTL range for invitations (`p_ttl_hours must be between 1 and 168`). */
export const INVITE_TTL_HOURS = 48;
/** Server-bounded TTL for ownership transfers (the app's 72-hour default). */
export const TRANSFER_TTL_HOURS = 72;

/**
 * Parses a create-RPC result whose row the server has already committed.
 * The one-time token exists only in the caller's scope — the server stores
 * just its SHA-256 hash — so a parse failure after the RPC returned would
 * strand an orphaned invitation or an armed transfer nobody can redeem
 * (issue #1284). The strict schema is tried first; a mismatch degrades to
 * the raw payload's usable fields instead of throwing the token away.
 */
function parseCommittedResult<T extends z.ZodType>(
  schema: T,
  data: unknown,
  degraded: (raw: Record<string, unknown>) => z.output<T>,
): z.output<T> {
  const parsed = schema.safeParse(data);
  if (parsed.success) return parsed.data;
  return degraded(
    data !== null && typeof data === 'object' ? (data as Record<string, unknown>) : {},
  );
}

/** `value` when it is a string, `fallback` for anything else. */
function stringOr(value: unknown, fallback: string): string {
  return typeof value === 'string' ? value : fallback;
}

/**
 * Creates a guardian invitation. The token is generated here, only its hash
 * travels; the returned `invitePath` is the browser-side redemption URL
 * (`/invite?code=…&profile=…`, the same query the app's universal links
 * carry).
 */
export async function createGuardianInvitation(
  client: AppSupabaseClient,
  options: {
    profileId: string;
    role: GuardianRole;
    recipientLabel: string | null;
    subject: boolean;
    ttlHours?: number;
  },
): Promise<{ invitation: CreatedInvitation; rawToken: string }> {
  const { rawToken, tokenHash } = generateInviteToken();
  const { data, error, status } = await client.rpc('create_guardian_invitation', {
    p_profile_id: options.profileId,
    p_role: options.role,
    // `p_recipient_label` has no SQL default, so omitting the key would be
    // a PostgREST resolution error; explicit JSON null is what the Dart
    // client sends and what the nullable column stores. The generated Args
    // type has no `| null`, hence the single targeted cast.
    p_recipient_label: (options.recipientLabel ?? null) as string,
    p_token_hash: await tokenHash,
    p_ttl_hours: options.ttlHours ?? INVITE_TTL_HOURS,
    p_subject: options.subject,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
  return {
    invitation: parseCommittedResult(createdInvitationSchema, data, (raw) => ({
      id: stringOr(raw['id'], ''),
      profile_id: stringOr(raw['profile_id'], ''),
      role: guardianRoleSchemaSafe(stringOr(raw['role'], '')) ?? 'viewer',
      expires_at: stringOr(raw['expires_at'], ''),
    })),
    rawToken,
  };
}

/**
 * The pre-accept preview (issue #594). Returns null for every state that
 * isn't a live invitation — wrong token, expired, revoked, already
 * accepted — deliberately indistinguishable (R6/enumeration).
 */
export async function previewGuardianInvitation(
  client: AppSupabaseClient,
  rawToken: string,
): Promise<InvitePreview | null> {
  const { data, error, status } = await client.rpc('preview_guardian_invitation', {
    p_token_hash: await sha256Hex(rawToken),
  });
  if (error !== null) throw await failureFor(client, error, false, status);
  return data === null ? null : invitePreviewSchema.parse(data);
}

/** Redeems the invitation; the accepting operator becomes a guardian. */
export async function acceptGuardianInvitation(
  client: AppSupabaseClient,
  rawToken: string,
  displayName: string | null,
): Promise<AcceptedInvite> {
  const { data, error, status } = await client.rpc('accept_guardian_invitation', {
    p_token_hash: await sha256Hex(rawToken),
    p_guardian_display_name: displayName ?? undefined,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
  return acceptedInviteSchema.parse(data);
}

/** Revokes an active guardian (or the caller themself — leave profile). */
export async function revokeGuardian(
  client: AppSupabaseClient,
  profileId: string,
  targetUserId: string,
): Promise<void> {
  const { error, status } = await client.rpc('revoke_guardian', {
    p_profile_id: profileId,
    p_target_user_id: targetUserId,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
}

/** Cancels one outstanding invitation; idempotent server-side (R5). */
export async function revokeGuardianInvitation(
  client: AppSupabaseClient,
  invitationId: string,
): Promise<InvitationOutcome> {
  const { data, error, status } = await client.rpc('revoke_guardian_invitation', {
    p_invitation_id: invitationId,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
  return invitationOutcomeSchema.parse(data).outcome;
}

/**
 * Changes an accepted guardian's role without revoke-and-reinvite (issue
 * #127). The server enforces the ladder; the UI gates with
 * `roles.ts`'s mirror of it.
 */
export async function updateGuardianRole(
  client: AppSupabaseClient,
  profileId: string,
  targetUserId: string,
  newRole: GuardianRole,
): Promise<void> {
  const { error, status } = await client.rpc('update_guardian_role', {
    p_profile_id: profileId,
    p_target_user_id: targetUserId,
    p_new_role: newRole,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
}

// ---------------------------------------------------------------------------
// Ownership-transfer RPCs.
// ---------------------------------------------------------------------------

/** Arms a child-profile ownership transfer (R6: only the primary guardian). */
export async function createOwnershipTransfer(
  client: AppSupabaseClient,
  options: {
    profileId: string;
    parentPostTransferRole: 'co_parent' | 'viewer';
    recipientLabel: string | null;
    ttlHours?: number;
  },
): Promise<{ transfer: CreatedTransfer; rawToken: string }> {
  const { rawToken, tokenHash } = generateInviteToken();
  const { data, error, status } = await client.rpc('create_ownership_transfer', {
    p_profile_id: options.profileId,
    p_parent_post_transfer_role: options.parentPostTransferRole,
    p_token_hash: await tokenHash,
    p_recipient_label: options.recipientLabel ?? undefined,
    p_ttl_hours: options.ttlHours ?? TRANSFER_TTL_HOURS,
  });
  if (error !== null) throw await failureFor(client, error, true, status);
  return {
    transfer: parseCommittedResult(createdTransferSchema, data, (raw) => ({
      id: stringOr(raw['id'], ''),
      expires_at: stringOr(raw['expires_at'], ''),
    })),
    rawToken,
  };
}

/** Cancels a live transfer (R9: only the arming parent). */
export async function cancelOwnershipTransfer(
  client: AppSupabaseClient,
  transferId: string,
): Promise<void> {
  const { error, status } = await client.rpc('cancel_ownership_transfer', {
    p_transfer_id: transferId,
  });
  if (error !== null) throw await failureFor(client, error, true, status);
}

/** Claims a transfer; the caller becomes the profile's owner (R11). */
export async function acceptOwnershipTransfer(
  client: AppSupabaseClient,
  rawToken: string,
  options: { childDisplayName: string | null; parentDisplayName: string | null },
): Promise<ClaimedTransfer> {
  const { data, error, status } = await client.rpc('accept_ownership_transfer', {
    p_token_hash: await sha256Hex(rawToken),
    p_child_display_name: options.childDisplayName ?? undefined,
    p_parent_display_name: options.parentDisplayName ?? undefined,
  });
  if (error !== null) throw await failureFor(client, error, true, status);
  return claimedTransferSchema.parse(data);
}

// ---------------------------------------------------------------------------
// Minimum-age consent (issues #845/#957).
// ---------------------------------------------------------------------------

/** The policy version the acknowledgement writes — kept in step with `kMinimumAgePolicyVersion`. */
export const MINIMUM_AGE_POLICY_VERSION = '2026-09-21';
/** `consent_via` for a subject invitation's acceptance (the parental-consent record). */
export const CONSENT_VIA_PARENT_INVITE = 'parent_invite';

/**
 * Records the caller's minimum-age acknowledgement. Best-effort by contract:
 * the caller decides how failures surface (the app swallows them — the
 * accepted membership is the durable record either way).
 */
export async function recordMinimumAgeAcknowledgement(
  client: AppSupabaseClient,
  options: { consentVia: string; appVersion: string; policyVersion: string },
): Promise<void> {
  const { error, status } = await client.rpc('record_minimum_age_acknowledgement', {
    p_consent_via: options.consentVia,
    p_app_version: options.appVersion,
    p_policy_version: options.policyVersion,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
}

// ---------------------------------------------------------------------------
// Notes writes — through `sync_push`, the phones' sole write path (D4).
// ---------------------------------------------------------------------------

/**
 * The `p_care_notes` element — exactly the keys `encodeCareNote` emits
 * (`row_codec.dart`): ids are client-generated ULIDs, `logged_by_user_id`
 * is deliberately absent because the server stamps the author.
 */
export function encodeCareNote(row: {
  id: string;
  profileId: string;
  body: string;
  updatedAt: Date;
  deleted: boolean;
}): { [key: string]: Json } {
  assertUlid(row.id);
  assertUlid(row.profileId);
  return {
    id: row.id,
    profile_id: row.profileId,
    body: row.deleted ? '' : row.body,
    updated_at: row.updatedAt.toISOString(),
    deleted_at: row.deleted ? row.updatedAt.toISOString() : null,
  };
}

/**
 * The `p_guardian_notes` element — exactly the keys `encodeGuardianNote`
 * emits: `id`, `profile_id`, `local_date` (the note's calendar day),
 * `tz` (the author's zone), `body`, `updated_at`, `deleted_at`. Tombstones
 * carry the `''` body sentinel and nothing else (the tombstone CHECK).
 */
export function encodeGuardianNote(row: {
  id: string;
  profileId: string;
  localDate: string;
  tz: string;
  body: string;
  updatedAt: Date;
  deleted: boolean;
}): { [key: string]: Json } {
  assertUlid(row.id);
  assertUlid(row.profileId);
  return {
    id: row.id,
    profile_id: row.profileId,
    local_date: row.localDate,
    tz: row.tz,
    body: row.deleted ? '' : row.body,
    updated_at: row.updatedAt.toISOString(),
    deleted_at: row.deleted ? row.updatedAt.toISOString() : null,
  };
}

function assertUlid(value: string): void {
  if (!isValidUlid(value)) {
    throw new SharingError('other');
  }
}

/**
 * The `sync_push` result's per-row rejections (`{id, rejected: true}`), so
 * the UI can tell "the server refused this row" (a bounds or author check)
 * apart from "the network died".
 */
export type SyncPushRejections = string[];

interface SyncPushResultLike {
  resolved?: unknown;
  rejected?: unknown;
  server_now?: unknown;
}

async function pushNotes(
  client: AppSupabaseClient,
  payload: { guardianNotes: { [key: string]: Json }[]; careNotes: { [key: string]: Json }[] },
): Promise<SyncPushRejections> {
  // `p_profiles`/`p_day_entries` have no defaults (they are the function's
  // original two parameters), so an empty array is passed explicitly; every
  // other table rides its server-side `'[]'` default. Ten empty arrays is
  // what a notes-only push looks like.
  const sentAtMs = Date.now();
  const { data, error, status } = await client.rpc('sync_push', {
    p_profiles: [],
    p_day_entries: [],
    p_care_notes: payload.careNotes,
    p_guardian_notes: payload.guardianNotes,
  });
  if (error !== null) throw await failureFor(client, error, false, status);
  const result = data as SyncPushResultLike | null;
  // Issue #1283: this is the notes pages' own sync_push call site (kept off
  // pushSyncBatch to preserve the four-array wire shape the tests pin), so
  // it teaches the clock offset too — same sent-at-before-the-call reading,
  // same EMA — or a save typed on the notes pages would never correct the
  // stamps of the writes it just made.
  if (typeof result?.server_now === 'string') {
    learnClockOffset(result.server_now, sentAtMs);
  }
  const rejected = Array.isArray(result?.rejected) ? result.rejected : [];
  return rejected
    .map((entry) =>
      entry !== null && typeof entry === 'object' ? (entry as { id?: unknown }).id : null,
    )
    .filter((id): id is string => typeof id === 'string');
}

/** Writes guardian-note rows (inserts, edits, and tombstones) via sync_push. */
export function pushGuardianNotes(
  client: AppSupabaseClient,
  rows: Parameters<typeof encodeGuardianNote>[0][],
): Promise<SyncPushRejections> {
  return pushNotes(client, {
    guardianNotes: rows.map((row) => encodeGuardianNote(row)),
    careNotes: [],
  });
}

/** Writes care-note rows (inserts and tombstones) via sync_push. */
export function pushCareNotes(
  client: AppSupabaseClient,
  rows: Parameters<typeof encodeCareNote>[0][],
): Promise<SyncPushRejections> {
  return pushNotes(client, {
    guardianNotes: [],
    careNotes: rows.map((row) => encodeCareNote(row)),
  });
}

/** The ULID generator notes writes use (one per page load, monotonic). */
export const noteIdGenerator = new UlidGenerator();

/** The browser-side path of an invitation created here (same query as the app's universal links). */
export function invitePath(rawToken: string, profileId: string): string {
  const params = new URLSearchParams({ code: rawToken, profile: profileId });
  return `/invite?${params.toString()}`;
}
