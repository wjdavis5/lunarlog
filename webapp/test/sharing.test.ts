import { webcrypto } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';

import { learnedClockOffsetMs, resetClockOffset } from '../src/lib/domain';
import {
  encodeCareNote,
  encodeGuardianNote,
  fetchActiveTransfer,
  fetchCareNotes,
  fetchGuardians,
  fetchPendingInvites,
  generateInviteToken,
  createGuardianInvitation,
  createOwnershipTransfer,
  acceptGuardianInvitation,
  previewGuardianInvitation,
  pushGuardianNotes,
  revokeGuardianInvitation,
  updateGuardianRole,
  mapSharingFailure,
  createInviteFailureMessageId,
  guardiansLoadFailureMessageId,
  mapTransferFailure,
  revokeFailureMessageId,
  roleChangeFailureMessageId,
  sha256Hex,
  sharingFailureMessageId,
  transferFailureMessageId,
  SharingError,
  type GuardianRow,
  type PendingInviteRow,
  type SharingFailureKind,
} from '../src/lib/sharing';
import type { AppSupabaseClient } from '../src/lib/supabase';

// The digest seam defaults to the platform's WebCrypto; in tests it is the
// same primitive from node:crypto so the vectors hold either way.
const digest = webcrypto.subtle.digest.bind(webcrypto.subtle);

/**
 * What a supabase-js call resolves to. `status` is the HTTP status it
 * reports beside the error (0 when the request never completed); the fakes
 * that leave it out stand for a response whose status the test does not
 * care about.
 */
type PageResult = {
  data: unknown;
  error: {
    message: string;
    code?: string;
    details?: string | null;
    hint?: string | null;
  } | null;
  status?: number;
};

interface FakeChain {
  client: AppSupabaseClient;
  calls: Array<{ table: string; method: string; args: unknown[] }>;
}

/**
 * A from()-chain fake that records every builder call. Terminal calls
 * (`order`, `range`, `maybeSingle`) resolve to the given page(s) — `pages`
 * hands one result per terminal call, so pagination tests feed a full page
 * then a short one.
 */
function fakeFrom(pageOrPages: PageResult | PageResult[]): FakeChain {
  const pages = Array.isArray(pageOrPages) ? pageOrPages : [pageOrPages];
  const calls: FakeChain['calls'] = [];
  let terminalIndex = 0;
  const resolve = () => pages[Math.min(terminalIndex++, pages.length - 1)];
  const builder = {
    select: (...args: unknown[]) => {
      calls.push({ table: '', method: 'select', args });
      return builder;
    },
    eq: (...args: unknown[]) => {
      calls.push({ table: '', method: 'eq', args });
      return builder;
    },
    is: (...args: unknown[]) => {
      calls.push({ table: '', method: 'is', args });
      return builder;
    },
    gt: (...args: unknown[]) => {
      calls.push({ table: '', method: 'gt', args });
      return builder;
    },
    limit: (...args: unknown[]) => {
      calls.push({ table: '', method: 'limit', args });
      return builder;
    },
    order: (...args: unknown[]) => {
      calls.push({ table: '', method: 'order', args });
      return terminal();
    },
    range: (...args: unknown[]) => {
      calls.push({ table: '', method: 'range', args });
      return terminal();
    },
    maybeSingle: () => {
      calls.push({ table: '', method: 'maybeSingle', args: [] });
      return Promise.resolve(resolve());
    },
  };
  // A thenable that still carries the builder methods, so a chain may end at
  // `order` (awaited) or continue through `range` (pagination).
  function terminal() {
    // The page is resolved at await time, not when the terminal link is
    // built — the paginated reads chain `.order(...).range(...)` and only
    // the awaited link's page counts.
    return {
      select: builder.select,
      eq: builder.eq,
      is: builder.is,
      gt: builder.gt,
      limit: builder.limit,
      order: builder.order,
      range: builder.range,
      maybeSingle: builder.maybeSingle,
      then: (onFulfilled: (v: PageResult) => unknown, onRejected: (e: unknown) => unknown) =>
        Promise.resolve(resolve()).then(onFulfilled, onRejected),
      catch: (onRejected: (e: unknown) => unknown) =>
        Promise.resolve(resolve()).catch(onRejected),
    };
  }
  const client = {
    from: (table: string) => {
      calls.push({ table, method: 'from', args: [] });
      return builder;
    },
    auth: {
      getSession: async () => ({ data: { session: { user: { id: 'user-1' } } } }),
    },
  } as unknown as AppSupabaseClient;
  return { client, calls };
}

function fakeRpc(
  result: PageResult,
  signedIn = true,
): { client: AppSupabaseClient; calls: Array<[string, Record<string, unknown>]> } {
  const calls: Array<[string, Record<string, unknown>]> = [];
  const client = {
    rpc: (name: string, params: Record<string, unknown>) => {
      calls.push([name, params]);
      return Promise.resolve(result);
    },
    auth: {
      getSession: async () => ({
        data: { session: signedIn ? { user: { id: 'user-1' } } : null },
      }),
    },
  } as unknown as AppSupabaseClient;
  return { client, calls };
}

const ULID = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const ULID2 = '01ARZ3NDEKTSV4RRFFQ69G5FAW';

// The learned clock offset is page-global module state (issue #1283) and
// the notes pushes below teach it from their fakes' server_now — every
// test starts uncorrected.
beforeEach(() => resetClockOffset());
// Sharing-table row ids are `uuid primary key default gen_random_uuid()`
// (20260904010000, 20260906170000) — the fixtures carry real UUIDs, which is
// exactly what the pre-#1284 z.ulid() schemas rejected.
const UUID = '0f0f0f0f-0f0f-4f0f-8f0f-0f0f0f0f0f0f';
const UUID2 = '1f1f1f1f-1f1f-4f1f-8f1f-1f1f1f1f1f1f';

describe('token generation (the SupabaseSharingService wire format)', () => {
  it('emits 32 bytes of base64url without padding', async () => {
    const bytes = new Uint8Array(32).fill(0xab);
    const { rawToken, tokenHash } = generateInviteToken(() => bytes, digest);
    expect(rawToken).toHaveLength(43);
    expect(rawToken).not.toContain('=');
    expect(rawToken).not.toContain('+');
    expect(rawToken).not.toContain('/');
    await expect(tokenHash).resolves.toBe(await sha256Hex(rawToken, digest));
  });

  it('sha256Hex matches the known test vector', async () => {
    await expect(sha256Hex('abc', digest)).resolves.toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });
});

describe('createGuardianInvitation', () => {
  it('sends the hash, never the raw token, with the app defaults', async () => {
    const { client, calls } = fakeRpc({
      data: {
        id: UUID,
        profile_id: ULID,
        role: 'caregiver',
        expires_at: '2026-10-02T00:00:00Z',
      },
      error: null,
    });
    const { invitation, rawToken } = await createGuardianInvitation(client, {
      profileId: ULID,
      role: 'caregiver',
      recipientLabel: null,
      subject: false,
    });
    expect(rawToken).toHaveLength(43);
    expect(invitation.id).toBe(UUID);
    const [name, params] = calls[0] ?? ['', {}];
    expect(name).toBe('create_guardian_invitation');
    expect(params['p_profile_id']).toBe(ULID);
    expect(params['p_role']).toBe('caregiver');
    expect(params['p_recipient_label']).toBeNull();
    expect(params['p_ttl_hours']).toBe(48);
    expect(params['p_subject']).toBe(false);
    // Both sides use the platform subtle here; the vector test below pins
    // the digest itself against node:crypto.
    expect(params['p_token_hash']).toBe(await sha256Hex(rawToken));
  });

  it('keeps the raw token when the committed result fails to parse (issue #1284)', async () => {
    // The row is committed server-side by the time the response arrives;
    // the raw token exists only here. A shape mismatch must degrade the
    // parsed invitation, never throw the token away.
    const { client } = fakeRpc({
      data: { id: 'not-a-uuid', profile_id: ULID, role: 'caregiver' },
      error: null,
    });
    const { invitation, rawToken } = await createGuardianInvitation(client, {
      profileId: ULID,
      role: 'caregiver',
      recipientLabel: null,
      subject: false,
    });
    expect(rawToken).toHaveLength(43);
    // The degraded result echoes the raw payload's string fields (missing
    // ones collapse to '') instead of throwing — the token is the piece
    // that must survive.
    expect(invitation.id).toBe('not-a-uuid');
    expect(invitation.profile_id).toBe(ULID);
    expect(invitation.role).toBe('caregiver');
    expect(invitation.expires_at).toBe('');
  });

  it('maps server rejections to typed failures', async () => {
    const { client } = fakeRpc({
      data: null,
      error: { message: 'invitation already accepted', code: 'P0001' },
    });
    await expect(
      createGuardianInvitation(client, {
        profileId: ULID,
        role: 'viewer',
        recipientLabel: null,
        subject: false,
      }),
    ).rejects.toMatchObject({ kind: 'alreadyAccepted' });
  });
});

describe('the error ladders (mirroring the two Dart mappers)', () => {
  it('an unauthenticated caller reads as not-signed-in, a signed-in one as unauthorized', () => {
    const error = { message: 'permission denied', code: '42501' };
    expect(mapSharingFailure(error, false)).toMatchObject({ kind: 'notSignedIn' });
    expect(mapSharingFailure(error, true)).toMatchObject({ kind: 'unauthorized' });
  });

  it('invitation failures: not found, expired, already guardian, invalid token', () => {
    expect(mapSharingFailure({ message: 'invitation not found', code: 'P0002' })).toMatchObject(
      { kind: 'notFound' },
    );
    expect(
      mapSharingFailure({ message: 'invitation has expired', code: 'P0001' }),
    ).toMatchObject({ kind: 'expired' });
    expect(
      mapSharingFailure({ message: 'already an active guardian', code: '23505' }),
    ).toMatchObject({
      kind: 'alreadyGuardian',
    });
    expect(
      mapSharingFailure({
        message: 'token_hash must be a 64-character hex string',
        code: '22023',
      }),
    ).toMatchObject({
      kind: 'invalidToken',
    });
  });

  it('a subject invitation refused because the profile already has a subject is the generic failure', () => {
    // The exact error the server's guardian_invitations trigger raises
    // (issue 1499; pinned in supabase/tests/self_profile_subject_test.sql):
    // P0001, and wording none of the specific mappings match.
    expect(
      mapSharingFailure(
        {
          message:
            'this profile already has a subject; a subject invitation cannot be created for it',
          code: 'P0001',
        },
        true,
      ),
    ).toMatchObject({ kind: 'other' });
  });

  it('transfer failures read 23505 as already-armed, never already-guardian', () => {
    expect(mapTransferFailure({ message: 'duplicate', code: '23505' })).toMatchObject({
      kind: 'alreadyArmed',
    });
    expect(
      mapTransferFailure({ message: 'transfer was cancelled', code: 'P0001' }),
    ).toMatchObject({
      kind: 'cancelled',
    });
    expect(
      mapTransferFailure({ message: 'cannot accept their own transfer', code: 'P0001' }),
    ).toMatchObject({
      kind: 'selfTransfer',
    });
    expect(
      mapTransferFailure({
        message: 'the arming parent no longer owns this profile; the link is stale',
        code: 'P0001',
      }),
    ).toMatchObject({ kind: 'staleOwner' });
    expect(
      mapTransferFailure({
        message:
          'the arming parent is no longer the primary guardian of this profile; the link is stale',
        code: 'P0001',
      }),
    ).toMatchObject({ kind: 'staleOwner' });
    expect(
      mapTransferFailure({ message: 'transfer has expired', code: 'P0001' }),
    ).toMatchObject({ kind: 'expired' });
    expect(
      mapTransferFailure({ message: 'invalid parent_post_transfer_role: x', code: '22023' }),
    ).toMatchObject({
      kind: 'other',
    });
  });

  it('wraps unknown errors as other', () => {
    expect(mapSharingFailure(new Error('boom'))).toMatchObject({ kind: 'other' });
    expect(mapSharingFailure(new SharingError('network'))).toMatchObject({ kind: 'network' });
  });
});

// Issue #1504. The server raised several ordinary refusals with SQLSTATE
// 55000, and the mapper read any all-digit code of 500 or more as a network
// failure before it looked at the message. A SQLSTATE is five characters and
// lives in the error's `code`; the HTTP status is the response's `status`,
// beside the error, and PostgREST answers a class-55 refusal with HTTP 500.
describe('every refusal the sharing RPCs raise (issue #1504)', () => {
  type Refusal = [
    fn: string,
    sqlstate: string,
    status: number,
    message: string,
    kind: SharingFailureKind,
  ];

  /** The error and status a PostgREST `raise exception` arrives as. */
  const raised = (sqlstate: string, message: string) => ({
    code: sqlstate,
    details: null,
    hint: null,
    message,
  });

  // Function, SQLSTATE, the HTTP status PostgREST gives that SQLSTATE, the
  // message, and what it reads as. Taken from the newest definition of each
  // function in supabase/migrations: 20260920120000 (create, accept and
  // preview_guardian_invitation), 20260906190000 (revoke_guardian_invitation),
  // 20260918160000 (revoke_guardian), 20260915010000 (update_guardian_role),
  // and the 20261005143105 trigger on a second subject invitation. The app's
  // test/data/sharing/supabase_sharing_service_test.dart holds the same rows
  // with the same kinds. Each is read as a signed-in caller.
  const invitationRefusals: Refusal[] = [
    [
      'create_guardian_invitation',
      '42501',
      403,
      'caller lacks permission to invite guardians for this profile',
      'unauthorized',
    ],
    ['create_guardian_invitation', '22023', 400, 'invalid role: owner', 'invalidToken'],
    [
      'create_guardian_invitation',
      '42501',
      403,
      'only the primary guardian can invite a co-parent',
      'unauthorized',
    ],
    [
      'create_guardian_invitation',
      '22023',
      400,
      'a subject invitation must grant the caregiver role',
      'invalidToken',
    ],
    [
      'create_guardian_invitation',
      '22023',
      400,
      'p_ttl_hours must be between 1 and 168',
      'invalidToken',
    ],
    [
      'create_guardian_invitation',
      '22023',
      400,
      'token_hash must be a 64-character hex string',
      'invalidToken',
    ],
    [
      'create_guardian_invitation',
      'P0001',
      400,
      'this profile already has a subject; a subject invitation cannot be created for it',
      'other',
    ],
    [
      'accept_guardian_invitation',
      '22023',
      400,
      'token_hash must be a 64-character hex string',
      'invalidToken',
    ],
    ['accept_guardian_invitation', 'P0002', 500, 'invitation not found', 'notFound'],
    [
      'accept_guardian_invitation',
      '55000',
      500,
      'invitation already accepted',
      'alreadyAccepted',
    ],
    // Was the network failure.
    ['accept_guardian_invitation', '55000', 500, 'invitation was revoked', 'revoked'],
    ['accept_guardian_invitation', '55000', 500, 'invitation has expired', 'expired'],
    [
      'accept_guardian_invitation',
      '23505',
      409,
      'user is already an active guardian of this profile',
      'alreadyGuardian',
    ],
    // Was the network failure.
    [
      'accept_guardian_invitation',
      '55000',
      500,
      'guardian access to this profile was revoked; a new invitation is required',
      'revoked',
    ],
    [
      'preview_guardian_invitation',
      '22023',
      400,
      'token_hash must be a 64-character hex string',
      'invalidToken',
    ],
    // Was the network failure. Neither client shows a preview's kind (both
    // say the preview could not be loaded), so it needs no copy of its own.
    [
      'preview_guardian_invitation',
      '55000',
      500,
      'too many preview attempts; wait a moment and try again',
      'other',
    ],
    [
      'revoke_guardian_invitation',
      '42501',
      403,
      'caller lacks permission to cancel this invitation',
      'unauthorized',
    ],
    [
      'revoke_guardian',
      '42501',
      403,
      'caller is not a guardian of this profile',
      'unauthorized',
    ],
    // Was the network failure. Manage guardians shows its own line for a
    // failed removal, whatever the kind.
    [
      'revoke_guardian',
      '55000',
      500,
      'the sole primary guardian cannot leave the profile',
      'other',
    ],
    [
      'revoke_guardian',
      '42501',
      403,
      'insufficient permission to revoke this guardian',
      'unauthorized',
    ],
    [
      'update_guardian_role',
      '42501',
      403,
      'primary_guardian cannot be granted through update_guardian_role',
      'unauthorized',
    ],
    ['update_guardian_role', '22023', 400, 'invalid role: owner', 'invalidToken'],
    ['update_guardian_role', '42501', 403, 'cannot change your own role', 'unauthorized'],
    [
      'update_guardian_role',
      '42501',
      403,
      'caller is not a guardian of this profile',
      'unauthorized',
    ],
    [
      'update_guardian_role',
      'P0002',
      500,
      'target is not an active guardian of this profile',
      'notFound',
    ],
    [
      'update_guardian_role',
      '42501',
      403,
      "insufficient permission to change this guardian's role",
      'unauthorized',
    ],
  ];

  it.each(invitationRefusals)(
    '%s: %s (HTTP %i) "%s" is %s',
    (_fn, sqlstate, status, message, kind) => {
      expect(mapSharingFailure(raised(sqlstate, message), true, status)).toMatchObject({
        kind,
      });
    },
  );

  // Every one of the six opens with the same check. It can only be raised
  // when there is no session, which reads as "sign in" (issue #885).
  it('"authentication required" (42501, HTTP 401) is the sign-in failure, with no session', () => {
    expect(
      mapSharingFailure(raised('42501', 'authentication required'), false, 401),
    ).toMatchObject({ kind: 'notSignedIn' });
  });

  // The transfer RPCs, from 20260915010000 (create_ownership_transfer, plus
  // the one-live-transfer unique index of 20260906170000), 20260906180000
  // (cancel_ownership_transfer) and 20260920120000
  // (accept_ownership_transfer). The app's
  // test/data/sharing/supabase_ownership_transfer_service_test.dart holds
  // the same rows with the same kinds.
  const transferRefusals: Refusal[] = [
    ['create_ownership_transfer', '42501', 401, 'authentication required', 'unauthorized'],
    [
      'create_ownership_transfer',
      '42501',
      403,
      'only the accepted primary guardian can transfer ownership of this profile',
      'unauthorized',
    ],
    [
      'create_ownership_transfer',
      '22023',
      400,
      'invalid parent_post_transfer_role: owner',
      'other',
    ],
    [
      'create_ownership_transfer',
      '22023',
      400,
      'p_ttl_hours must be between 1 and 168',
      'other',
    ],
    [
      'create_ownership_transfer',
      '22023',
      400,
      'token_hash must be a 64-character hex string',
      'invalidToken',
    ],
    [
      'create_ownership_transfer',
      '22023',
      400,
      'recipient_label must be at most 80 characters',
      'other',
    ],
    [
      'create_ownership_transfer',
      '23505',
      409,
      'duplicate key value violates unique constraint "ownership_transfers_one_live_uq"',
      'alreadyArmed',
    ],
    ['cancel_ownership_transfer', '42501', 401, 'authentication required', 'unauthorized'],
    ['cancel_ownership_transfer', 'P0002', 500, 'transfer not found', 'notFound'],
    [
      'cancel_ownership_transfer',
      '42501',
      403,
      'only the arming parent can cancel this transfer',
      'unauthorized',
    ],
    ['accept_ownership_transfer', '42501', 401, 'authentication required', 'unauthorized'],
    [
      'accept_ownership_transfer',
      '22023',
      400,
      'token_hash must be a 64-character hex string',
      'invalidToken',
    ],
    ['accept_ownership_transfer', 'P0002', 500, 'transfer not found', 'notFound'],
    [
      'accept_ownership_transfer',
      '55000',
      500,
      'transfer was already accepted',
      'alreadyAccepted',
    ],
    ['accept_ownership_transfer', '55000', 500, 'transfer was cancelled', 'cancelled'],
    ['accept_ownership_transfer', '55000', 500, 'transfer has expired', 'expired'],
    [
      'accept_ownership_transfer',
      '55000',
      500,
      'the arming parent cannot accept their own transfer',
      'selfTransfer',
    ],
    ['accept_ownership_transfer', 'P0002', 500, 'profile not found', 'notFound'],
    [
      'accept_ownership_transfer',
      '55000',
      500,
      'the arming parent no longer owns this profile; the link is stale',
      'staleOwner',
    ],
    [
      'accept_ownership_transfer',
      '55000',
      500,
      'the arming parent is no longer the primary guardian of this profile; the link is stale',
      'staleOwner',
    ],
    // Was the network failure. The claimant's own role on the profile
    // changed after the link was made, which is what this copy says.
    [
      'accept_ownership_transfer',
      '55000',
      500,
      'guardian access to this profile was revoked; a new transfer link is required',
      'staleOwner',
    ],
  ];

  it.each(transferRefusals)(
    '%s: %s (HTTP %i) "%s" is %s',
    (_fn, sqlstate, status, message, kind) => {
      expect(mapTransferFailure(raised(sqlstate, message), true, status)).toMatchObject({
        kind,
      });
    },
  );

  it('a SQLSTATE no refusal matches is the generic failure, never the network one, whatever its digits', () => {
    const unknown: [string, number, string][] = [
      ['55000', 500, 'a refusal this build has not heard of'],
      ['57014', 500, 'canceling statement due to statement timeout'],
      ['23514', 400, 'new row violates check constraint'],
    ];
    for (const [sqlstate, status, message] of unknown) {
      expect(mapSharingFailure(raised(sqlstate, message), true, status)).toMatchObject({
        kind: 'other',
      });
      expect(mapTransferFailure(raised(sqlstate, message), true, status)).toMatchObject({
        kind: 'other',
      });
    }
  });

  it('the copy for a revoked invitation is its own, not the network line', () => {
    expect(sharingFailureMessageId('revoked')).toBe('sharingFailureRevoked');
    expect(sharingFailureMessageId('revoked')).not.toBe(sharingFailureMessageId('network'));
    // The transfer ladder never returns it; its page has a line all the same.
    expect(transferFailureMessageId('revoked')).toBe('commonSomethingWentWrong');
  });

  it('a failed removal names what the server said, and the sole-primary line only when the server answered', () => {
    // Someone else's row.
    expect(revokeFailureMessageId('unauthorized', false)).toBe('commonUnauthorized');
    expect(revokeFailureMessageId('network', false)).toBe('sharingManageGuardiansRemoveFailed');
    expect(revokeFailureMessageId('other', false)).toBe('sharingManageGuardiansRemoveFailed');
    // A primary guardian leaving: the only thing the server refuses her
    // for, apart from permission, is being the last one.
    expect(revokeFailureMessageId('other', true)).toBe(
      'sharingManageGuardiansSolePrimaryLeave',
    );
    // Neither of these says anything about who the primary guardians are.
    expect(revokeFailureMessageId('network', true)).toBe('sharingManageGuardiansRemoveFailed');
    expect(revokeFailureMessageId('unauthorized', true)).toBe('commonUnauthorized');
    // Nor does having no session (issue #1527): a tab left open past its
    // sign-in told a primary guardian she was the only one.
    expect(revokeFailureMessageId('notSignedIn', true)).toBe('sharingFailureNotSignedIn');
    expect(revokeFailureMessageId('notSignedIn', false)).toBe('sharingFailureNotSignedIn');
  });

  // `sharingFailureMessageId` is written for the person accepting an
  // invitation. These two actions used it, or one generic line, instead.
  const ACCEPT_ONLY: SharingFailureKind[] = [
    'notFound',
    'expired',
    'revoked',
    'alreadyAccepted',
    'alreadyGuardian',
    'invalidToken',
    'other',
  ];

  it('a failed invitation create never reads as a failed accept', () => {
    expect(createInviteFailureMessageId('network')).toBe('commonNetworkError');
    expect(createInviteFailureMessageId('unauthorized')).toBe('commonUnauthorized');
    expect(createInviteFailureMessageId('notSignedIn')).toBe('sharingFailureNotSignedIn');
    for (const kind of ACCEPT_ONLY) {
      expect(createInviteFailureMessageId(kind)).toBe('commonSomethingWentWrong');
    }
  });

  it('a guardian list that fails to load says so, not "failed to accept invitation"', () => {
    expect(guardiansLoadFailureMessageId('network')).toBe('commonNetworkError');
    expect(guardiansLoadFailureMessageId('unauthorized')).toBe('commonUnauthorized');
    expect(guardiansLoadFailureMessageId('notSignedIn')).toBe('sharingFailureNotSignedIn');
    for (const kind of ACCEPT_ONLY) {
      expect(guardiansLoadFailureMessageId(kind)).toBe('webGuardiansLoadFailed');
    }
  });

  it('a failed role change names a refusal for lack of permission, and a missing session', () => {
    expect(roleChangeFailureMessageId('unauthorized')).toBe('commonUnauthorized');
    // Issue #1527: with no session the thing to do is sign in.
    expect(roleChangeFailureMessageId('notSignedIn')).toBe('sharingFailureNotSignedIn');
    expect(roleChangeFailureMessageId('network')).toBe(
      'sharingManageGuardiansRoleUpdateFailed',
    );
    expect(roleChangeFailureMessageId('notFound')).toBe(
      'sharingManageGuardiansRoleUpdateFailed',
    );
  });

  it('a refused accept reaches the page as its own kind through the wrapper', async () => {
    const { client } = fakeRpc({
      data: null,
      error: raised('55000', 'invitation was revoked'),
      status: 500,
    });
    await expect(acceptGuardianInvitation(client, 'raw-token', null)).rejects.toMatchObject({
      kind: 'revoked',
    });
  });
});

describe('a transport or server failure is still the network kind (issue #1504)', () => {
  // What supabase-js resolves to when the request never completed: status
  // 0, an empty code, and the browser's own fetch error as the message.
  const neverCompleted = {
    message: 'TypeError: Failed to fetch',
    details: 'TypeError: Failed to fetch\n    at fetch',
    hint: '',
    code: '',
  };

  it('a request that never completes', () => {
    expect(mapSharingFailure(neverCompleted, true, 0)).toMatchObject({ kind: 'network' });
    expect(mapTransferFailure(neverCompleted, true, 0)).toMatchObject({ kind: 'network' });
    // Signed out as well: nothing was refused, so it is not "sign in".
    expect(mapSharingFailure(neverCompleted, false, 0)).toMatchObject({ kind: 'network' });
  });

  it('an HTTP 503 whose body carries no code of its own', () => {
    const bodies = [
      // A page that is not JSON: supabase-js hands it over as the message.
      { message: '<html><body><h1>503 Service Temporarily Unavailable</h1></body></html>' },
      // A gateway's own JSON, parsed as the error, with no code in it.
      { message: 'name resolution failed' },
    ];
    for (const body of bodies) {
      expect(mapSharingFailure(body, true, 503)).toMatchObject({ kind: 'network' });
      expect(mapTransferFailure(body, true, 503)).toMatchObject({ kind: 'network' });
    }
  });

  it('a three-digit code is a status too: where the app client carries it', () => {
    expect(mapSharingFailure({ message: 'Service Unavailable', code: '503' })).toMatchObject({
      kind: 'network',
    });
    expect(mapTransferFailure({ message: 'Service Unavailable', code: '503' })).toMatchObject({
      kind: 'network',
    });
    // A 4xx status is not a server failure.
    expect(mapSharingFailure({ message: 'Too Many Requests', code: '429' })).toMatchObject({
      kind: 'other',
    });
  });

  it('a gateway page is not read for a refusal, whatever it says', () => {
    // Each of these used to be matched on its wording: an invalid-link, a
    // not-found and an expired failure.
    const pages: [number, string][] = [
      [526, '<html><head><title>Invalid SSL certificate</title></head></html>'],
      [502, '<html><body>The origin server was not found</body></html>'],
      [504, '<html><body>The gateway timed out; the request expired</body></html>'],
    ];
    for (const [status, message] of pages) {
      expect(mapSharingFailure({ message }, true, status)).toMatchObject({ kind: 'network' });
      expect(mapTransferFailure({ message }, true, status)).toMatchObject({ kind: 'network' });
    }
  });

  it('an HTTP 500 that carries a SQLSTATE is the refusal it names, not a server failure', () => {
    expect(
      mapSharingFailure(
        { code: '55000', message: 'invitation has expired', details: null, hint: null },
        true,
        500,
      ),
    ).toMatchObject({ kind: 'expired' });
  });

  it('the wrappers pass the status on: a failed fetch and a 503 reach the page as network', async () => {
    const offline = fakeRpc({ data: null, error: neverCompleted, status: 0 });
    await expect(
      acceptGuardianInvitation(offline.client, 'raw-token', null),
    ).rejects.toMatchObject({ kind: 'network' });

    const down = fakeRpc({
      data: null,
      error: { message: '<html><body>503 Service Temporarily Unavailable</body></html>' },
      status: 503,
    });
    await expect(previewGuardianInvitation(down.client, 'raw-token')).rejects.toMatchObject({
      kind: 'network',
    });

    const read = fakeFrom({ data: null, error: neverCompleted, status: 0 });
    await expect(fetchGuardians(read.client, ULID)).rejects.toMatchObject({ kind: 'network' });
  });
});

describe('reads', () => {
  it('fetchGuardians parses RLS-scoped membership rows', async () => {
    const { client, calls } = fakeFrom({
      data: [
        {
          id: UUID,
          profile_id: ULID,
          user_id: UUID,
          role: 'primary_guardian',
          status: 'accepted',
          display_name: 'Mom',
          invited_by: null,
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z',
        },
      ],
      error: null,
    });
    const rows: GuardianRow[] = await fetchGuardians(client, ULID);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.role).toBe('primary_guardian');
    expect(calls[0]).toMatchObject({ table: 'profile_guardians' });
  });

  it('a pre-#802 guardian row (null is_subject) parses as false instead of failing the list (issue #1284)', async () => {
    const { client } = fakeFrom({
      data: [
        {
          id: UUID,
          profile_id: ULID,
          user_id: UUID,
          role: 'caregiver',
          status: 'accepted',
          display_name: null,
          invited_by: UUID2,
          // Nullable with no backfill (20260920120000): real rows carry null.
          is_subject: null,
          created_at: '2026-01-01T00:00:00Z',
          updated_at: '2026-01-01T00:00:00Z',
        },
      ],
      error: null,
    });
    const rows: GuardianRow[] = await fetchGuardians(client, ULID);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.is_subject).toBe(false);
  });

  it('fetchPendingInvites selects the safe columns and the seven-day cutoff', async () => {
    const now = new Date('2026-09-30T12:00:00Z');
    const { client, calls } = fakeFrom({ data: [], error: null });
    const rows: PendingInviteRow[] = await fetchPendingInvites(client, ULID, now);
    expect(rows).toEqual([]);
    const select = calls.find((call) => call.method === 'select');
    const columns = String(select?.args[0]);
    expect(columns).toContain('id');
    expect(columns).toContain('invited_by');
    expect(columns).not.toContain('token_hash');
    const cutoff = calls.find((call) => call.method === 'gt');
    expect(new Date(String(cutoff?.args[1])).getTime()).toBe(
      now.getTime() - 7 * 24 * 60 * 60 * 1000,
    );
  });

  it('fetchPendingInvites parses real invitation rows (uuid id, null is_subject)', async () => {
    const { client } = fakeFrom({
      data: [
        {
          id: UUID2,
          profile_id: ULID,
          role: 'viewer',
          // Read since issue #1285 for the cancel ladder (a co-parent may
          // not cancel a co_parent invitation someone else created).
          invited_by: UUID,
          recipient_label: 'Nurse',
          created_at: '2026-09-01T00:00:00Z',
          expires_at: '2026-09-30T00:00:00Z',
          is_subject: null,
        },
      ],
      error: null,
    });
    const rows: PendingInviteRow[] = await fetchPendingInvites(client, ULID);
    expect(rows).toHaveLength(1);
    expect(rows[0]?.id).toBe(UUID2);
    expect(rows[0]?.invited_by).toBe(UUID);
    expect(rows[0]?.is_subject).toBe(false);
  });

  it('fetchActiveTransfer parses the live transfer row (uuid id)', async () => {
    const { client } = fakeFrom({
      data: {
        id: UUID,
        profile_id: ULID,
        parent_post_transfer_role: 'co_parent',
        recipient_label: null,
        expires_at: '2026-10-03T00:00:00Z',
      },
      error: null,
    });
    const row = await fetchActiveTransfer(client, ULID);
    expect(row?.id).toBe(UUID);
    expect(row?.parent_post_transfer_role).toBe('co_parent');
  });

  it('fetchActiveTransfer returns null without a live row', async () => {
    const { client } = fakeFrom({ data: null, error: null });
    await expect(fetchActiveTransfer(client, ULID)).resolves.toBeNull();
  });

  it('fetchCareNotes paginates until a short page', async () => {
    const row = {
      id: ULID,
      profile_id: ULID,
      body: 'note',
      logged_by_user_id: UUID,
      last_modified_by_user_id: null,
      updated_at: '2026-01-01T00:00:00Z',
    };
    const crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    const suffix = (n: number) => {
      let out = '';
      for (let i = 0; i < 2; i++) {
        out = crockford[n % 32] + out;
        n = Math.floor(n / 32);
      }
      return out;
    };
    const fullPage = Array.from({ length: 500 }, (_, i) => ({
      ...row,
      id: `01ARZ3NDEKTSV4RRFFQ69G5F${suffix(i)}`,
    }));
    const { client, calls } = fakeFrom([
      { data: fullPage, error: null },
      { data: [row], error: null },
    ]);
    const rows = await fetchCareNotes(client, ULID);
    expect(rows).toHaveLength(501);
    const ranges = calls.filter((call) => call.method === 'range');
    expect(ranges).toHaveLength(2);
    expect(ranges[0]?.args).toEqual([0, 499]);
    expect(ranges[1]?.args).toEqual([500, 999]);
  });

  it('surfaces a PostgREST error as a typed failure', async () => {
    const { client } = fakeFrom({
      data: null,
      error: { message: 'permission denied', code: '42501' },
    });
    await expect(fetchGuardians(client, ULID)).rejects.toMatchObject({ kind: 'unauthorized' });
  });
});

describe('createOwnershipTransfer', () => {
  it('parses the committed transfer row (uuid id) and returns the raw token', async () => {
    const { client, calls } = fakeRpc({
      data: { id: UUID, expires_at: '2026-10-03T00:00:00Z' },
      error: null,
    });
    const { transfer, rawToken } = await createOwnershipTransfer(client, {
      profileId: ULID,
      parentPostTransferRole: 'co_parent',
      recipientLabel: null,
    });
    expect(rawToken).toHaveLength(43);
    expect(transfer.id).toBe(UUID);
    const [name, params] = calls[0] ?? ['', {}];
    expect(name).toBe('create_ownership_transfer');
    expect(params['p_profile_id']).toBe(ULID);
    expect(params['p_parent_post_transfer_role']).toBe('co_parent');
    expect(params['p_ttl_hours']).toBe(72);
  });

  it('keeps the raw token when the committed result fails to parse (issue #1284)', async () => {
    const { client } = fakeRpc({ data: { id: ULID }, error: null });
    const { transfer, rawToken } = await createOwnershipTransfer(client, {
      profileId: ULID,
      parentPostTransferRole: 'viewer',
      recipientLabel: null,
    });
    // The transfer is armed server-side; the token must survive the parse,
    // with whatever raw fields the payload carried.
    expect(rawToken).toHaveLength(43);
    expect(transfer.id).toBe(ULID);
    expect(transfer.expires_at).toBe('');
  });
});

describe('preview/accept/revoke/role wrappers', () => {
  it('preview passes the hash and passes null through', async () => {
    const { client, calls } = fakeRpc({ data: null, error: null });
    const rawToken = 'token';
    await expect(previewGuardianInvitation(client, rawToken)).resolves.toBeNull();
    const [, params] = calls[0] ?? ['', {}];
    // Both sides use the platform subtle here; the vector test below pins
    // the digest itself against node:crypto.
    expect(params['p_token_hash']).toBe(await sha256Hex(rawToken));
  });

  it('preview reads a missing is_subject as false (a server predating #802)', async () => {
    const { client } = fakeRpc({
      data: {
        profile_display_name: 'Maya',
        role: 'caregiver',
        expires_at: '2026-10-02T00:00:00Z',
      },
      error: null,
    });
    await expect(previewGuardianInvitation(client, 'token')).resolves.toMatchObject({
      is_subject: false,
    });
  });

  it('accept returns the parsed result', async () => {
    const { client } = fakeRpc({
      data: { profile_id: ULID, profile_name: 'Maya', role: 'caregiver', is_subject: true },
      error: null,
    });
    const result = await acceptGuardianInvitation(client, 'token', 'Dad');
    expect(result).toMatchObject({ profile_id: ULID, profile_name: 'Maya', is_subject: true });
  });

  it('accept reads a null is_subject as false (issue #1284)', async () => {
    const { client } = fakeRpc({
      data: { profile_id: ULID, profile_name: 'Maya', role: 'viewer', is_subject: null },
      error: null,
    });
    await expect(acceptGuardianInvitation(client, 'token', null)).resolves.toMatchObject({
      is_subject: false,
    });
  });

  it('revoke returns the outcome enum', async () => {
    const { client } = fakeRpc({ data: { outcome: 'already_accepted' }, error: null });
    await expect(revokeGuardianInvitation(client, ULID)).resolves.toBe('already_accepted');
  });

  it('role updates send the wire spelling', async () => {
    const { client, calls } = fakeRpc({ data: null, error: null });
    await updateGuardianRole(client, ULID, UUID, 'caregiver');
    const [, params] = calls[0] ?? ['', {}];
    expect(params).toEqual({
      p_profile_id: ULID,
      p_target_user_id: UUID,
      p_new_role: 'caregiver',
    });
  });
});

describe('notes payloads (the sync_push wire shapes)', () => {
  it('a guardian note emits exactly the allowed keys', () => {
    const payload = encodeGuardianNote({
      id: ULID,
      profileId: ULID,
      localDate: '2026-09-30',
      tz: 'America/Chicago',
      body: "Slept over at Dad's.",
      updatedAt: new Date('2026-09-30T18:00:00Z'),
      deleted: false,
    });
    expect(Object.keys(payload).sort()).toEqual([
      'body',
      'deleted_at',
      'id',
      'local_date',
      'profile_id',
      'tz',
      'updated_at',
    ]);
    expect(payload['updated_at']).toBe('2026-09-30T18:00:00.000Z');
    expect(payload['deleted_at']).toBeNull();
  });

  it('a tombstone carries the empty-body sentinel and nothing else', () => {
    const payload = encodeGuardianNote({
      id: ULID,
      profileId: ULID,
      localDate: '2026-09-30',
      tz: 'UTC',
      body: 'text to erase',
      updatedAt: new Date('2026-09-30T18:00:00Z'),
      deleted: true,
    });
    expect(payload['body']).toBe('');
    expect(payload['deleted_at']).toBe('2026-09-30T18:00:00.000Z');
  });

  it('a care note emits exactly the allowed keys', () => {
    const payload = encodeCareNote({
      id: ULID,
      profileId: ULID,
      body: 'Refill heat pad',
      updatedAt: new Date('2026-09-30T18:00:00Z'),
      deleted: false,
    });
    expect(Object.keys(payload).sort()).toEqual([
      'body',
      'deleted_at',
      'id',
      'profile_id',
      'updated_at',
    ]);
    // logged_by_user_id is deliberately absent: the server stamps the author.
    expect(payload).not.toHaveProperty('logged_by_user_id');
  });

  it('pushGuardianNotes rides the empty arrays and reports rejections', async () => {
    const { client, calls } = fakeRpc({
      data: {
        resolved: [],
        rejected: [{ id: ULID2, rejected: true }],
        server_now: '2026-09-30T00:00:00Z',
      },
      error: null,
    });
    const rejections = await pushGuardianNotes(client, [
      {
        id: ULID,
        profileId: ULID,
        localDate: '2026-09-30',
        tz: 'UTC',
        body: 'ok',
        updatedAt: new Date(),
        deleted: false,
      },
      {
        id: ULID2,
        profileId: ULID,
        localDate: '2026-09-30',
        tz: 'UTC',
        body: 'refused',
        updatedAt: new Date(),
        deleted: false,
      },
    ]);
    expect(rejections).toEqual([ULID2]);
    const [name, params] = calls[0] ?? ['', {}];
    expect(name).toBe('sync_push');
    expect(params['p_profiles']).toEqual([]);
    expect(params['p_day_entries']).toEqual([]);
    expect(params['p_guardian_notes']).toHaveLength(2);
    expect(params).not.toHaveProperty('p_observations');
  });

  it('a notes push teaches the clock offset too (issue #1283)', async () => {
    const deviceNow = Date.now();
    // The server sits ten minutes ahead of this browser: the response's
    // server_now is what teaches the offset, so the notes pages' writes —
    // stamped via serverAdjustedNow — land on server time.
    const { client } = fakeRpc({
      data: {
        resolved: [],
        rejected: [],
        server_now: new Date(deviceNow + 10 * 60_000).toISOString(),
      },
      error: null,
    });
    await pushGuardianNotes(client, [
      {
        id: ULID,
        profileId: ULID,
        localDate: '2026-09-30',
        tz: 'UTC',
        body: 'ok',
        updatedAt: new Date(),
        deleted: false,
      },
    ]);
    const offset = learnedClockOffsetMs();
    expect(offset).not.toBeNull();
    expect(Math.abs((offset ?? 0) - 10 * 60_000)).toBeLessThan(30_000);
  });
});

describe('invitePath', () => {
  it('builds the /invite query the universal links carry', async () => {
    const { invitePath } = await import('../src/lib/sharing');
    expect(invitePath('T0KEN', ULID)).toBe('/invite?code=T0KEN&profile=' + ULID);
  });
});

describe('pagination failure', () => {
  it('a rejected page surfaces the typed failure, not raw data', async () => {
    const { client } = fakeFrom({ data: null, error: { message: 'network', code: '' } });
    await expect(fetchCareNotes(client, ULID)).rejects.toBeInstanceOf(SharingError);
  });
});
