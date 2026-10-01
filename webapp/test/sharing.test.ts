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
  mapTransferFailure,
  sha256Hex,
  SharingError,
  type GuardianRow,
  type PendingInviteRow,
} from '../src/lib/sharing';
import type { AppSupabaseClient } from '../src/lib/supabase';

// The digest seam defaults to the platform's WebCrypto; in tests it is the
// same primitive from node:crypto so the vectors hold either way.
const digest = webcrypto.subtle.digest.bind(webcrypto.subtle);

type PageResult = { data: unknown; error: { message: string; code?: string } | null };

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
      data: { resolved: [], rejected: [], server_now: new Date(deviceNow + 10 * 60_000).toISOString() },
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
