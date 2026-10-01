import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  emptySyncedData,
  fetchGuardianNotes,
  fetchSettings,
  getSyncedDataCache,
  learnClockOffset,
  learnedClockOffsetMs,
  mergeSyncedData,
  newCareNotePayload,
  newDayEntryPayload,
  newGuardianNotePayload,
  newProfileModePayload,
  newProfilePayload,
  nowSyncStamp,
  pullSyncedData,
  pushSyncBatch,
  resetClockOffset,
  resetWebDataForSignOut,
  serverAdjustedNow,
  subscribeSyncSignals,
  SyncedDataCache,
  tombstonePayload,
} from '../src/lib/domain';
import type { ProfileRow } from '../src/lib/schemas';
import type { AppSupabaseClient } from '../src/lib/supabase';

// The learned clock offset is page-global module state (issue #1283): the
// push tests below teach one from their fakes' server_now, so every test
// starts uncorrected — the same isolation the shared cache's resets give
// the row state.
beforeEach(() => resetClockOffset());

// ---------------------------------------------------------------------------
// Fake client seams. supabase-js's real types are structural; the fakes
// implement exactly the chain the data layer awaits (the mirror style of
// test/queries.test.ts in #1249).
// ---------------------------------------------------------------------------

type RpcHandler = (
  name: string,
  params: Record<string, unknown>,
) => Promise<{ data: unknown; error: { message: string } | null }>;

interface RangeCall {
  table: string;
  eqColumn?: string;
  eqValue?: string;
  from: number;
  to: number;
}

function fakeSelectClient(
  pages: Map<string, { data: unknown[]; error: { message: string } | null }[]>,
) {
  const ranges: RangeCall[] = [];
  const from = vi.fn().mockImplementation((table: string) => {
    const builder = {
      select: vi.fn().mockReturnThis(),
      order: vi.fn().mockReturnThis(),
      eq: vi.fn().mockImplementation((column: string, value: string) => {
        builder.lastEq = { column, value };
        return builder;
      }),
      range: vi.fn().mockImplementation((from: number, to: number) => {
        const queue = pages.get(table) ?? [];
        const page = queue.shift() ?? { data: [], error: null };
        ranges.push({
          table,
          eqColumn: builder.lastEq?.column,
          eqValue: builder.lastEq?.value,
          from,
          to,
        });
        return page;
      }),
      lastEq: undefined as { column: string; value: string } | undefined,
    };
    return builder;
  });
  return { client: { from } as unknown as AppSupabaseClient, from, ranges };
}

function fakeRpcClient(handler: RpcHandler) {
  const calls: { name: string; params: Record<string, unknown> }[] = [];
  const rpc = vi
    .fn()
    .mockImplementation(async (name: string, params: Record<string, unknown>) => {
      calls.push({ name, params });
      return handler(name, params);
    });
  return { client: { rpc } as unknown as AppSupabaseClient, calls };
}

class FakeChannel {
  name = '';
  readonly onCalls: { type: string; opts: Record<string, unknown> }[] = [];
  readonly callbacks: ((payload: { new: unknown }) => void)[] = [];
  subscribed = false;

  on(
    type: string,
    opts: Record<string, unknown>,
    cb: (payload: { new: unknown }) => void,
  ): this {
    this.onCalls.push({ type, opts });
    this.callbacks.push(cb);
    return this;
  }

  subscribe(): this {
    this.subscribed = true;
    return this;
  }
}

function fakeRealtimeClient() {
  const channels: FakeChannel[] = [];
  const removed: FakeChannel[] = [];
  const channel = vi.fn().mockImplementation((name: string) => {
    const ch = new FakeChannel();
    ch.name = name;
    channels.push(ch);
    return ch;
  });
  const removeChannel = vi.fn().mockImplementation(async (ch: FakeChannel) => {
    removed.push(ch);
  });
  const client = { channel, removeChannel } as unknown as AppSupabaseClient;
  return { client, channels, removed };
}

const ULID_A = '01ARZ3NDEKTSV4RRFFQ69G5FAV';
const ULID_B = '01ARZ3NDEKTSV4RRFFQ69G5FAW';

function profileRow(overrides: Partial<ProfileRow> = {}): ProfileRow {
  return {
    id: ULID_A,
    user_id: '00000000-0000-0000-0000-000000000001',
    display_name: 'Maya',
    is_minor: false,
    sort_order: 0,
    archived_at: null,
    created_at: '2026-09-01T00:00:00Z',
    updated_at: '2026-09-01T00:00:00Z',
    deleted_at: null,
    server_version: 1,
    mode: 'standard',
    birth_year: 1988,
    relationship: 'self',
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// pullSyncedData
// ---------------------------------------------------------------------------

describe('pullSyncedData (issue #1252)', () => {
  it('pulls one short page and advances cursors to the max server_version', async () => {
    const { client, calls } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow()], day_entries: [] },
      error: null,
    }));
    const { data, cursors } = await pullSyncedData(client);
    expect(calls).toHaveLength(1);
    expect(calls[0]?.name).toBe('sync_pull');
    expect(data.profiles).toHaveLength(1);
    expect(data.profiles[0]?.display_name).toBe('Maya');
    expect(cursors.profiles).toBe(1);
  });

  it('pages past the 500-row cap: a full page triggers another round with the advanced cursor', async () => {
    const fullPage = Array.from({ length: 500 }, (_, i) =>
      profileRow({ id: ULID_A, server_version: i + 1 }),
    );
    let round = 0;
    const { client, calls } = fakeRpcClient(async (_name, params) => {
      round += 1;
      if (round === 1) {
        expect(params.p_cursors).toEqual({});
        return { data: { profiles: fullPage }, error: null };
      }
      expect(params.p_cursors).toEqual({ profiles: 500 });
      return { data: { profiles: [profileRow({ server_version: 501 })] }, error: null };
    });
    const { data, cursors } = await pullSyncedData(client);
    expect(calls).toHaveLength(2);
    expect(data.profiles).toHaveLength(501);
    expect(cursors.profiles).toBe(501);
  });

  it('surfaces an RPC failure', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: null,
      error: { message: 'sync_pull requires an authenticated user' },
    }));
    await expect(pullSyncedData(client)).rejects.toThrow('authenticated');
  });

  it('fails closed on a row that fails boundary validation', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow({ id: 'not-a-ulid' })] },
      error: null,
    }));
    await expect(pullSyncedData(client)).rejects.toThrow();
  });

  it('guards against paging that never exhausts', async () => {
    const fullPage = Array.from({ length: 500 }, (_, i) =>
      profileRow({ server_version: i + 1 }),
    );
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: fullPage },
      error: null,
    }));
    await expect(pullSyncedData(client)).rejects.toThrow('did not exhaust');
  });
});

// ---------------------------------------------------------------------------
// pushSyncBatch + payload builders
// ---------------------------------------------------------------------------

describe('pushSyncBatch (issue #1252)', () => {
  it('sends all ten arrays, defaulting to empty', async () => {
    const { client, calls } = fakeRpcClient(async () => ({
      data: { resolved: [], rejected: [], server_now: '2026-09-30T00:00:00Z' },
      error: null,
    }));
    await pushSyncBatch(client, {});
    expect(calls[0]?.name).toBe('sync_push');
    expect(calls[0]?.params).toEqual({
      p_profiles: [],
      p_day_entries: [],
      p_observations: [],
      p_profile_modes: [],
      p_cycle_overrides: [],
      p_care_notes: [],
      p_visit_prep_items: [],
      p_merge_events: [],
      p_tag_registry: [],
      p_guardian_notes: [],
    });
  });

  it('decodes the result and maps rejections back to payload ids', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: {
        resolved: [{ id: ULID_A, table: 'profiles' }],
        rejected: [{ id: ULID_B, rejected: true }],
        server_now: '2026-09-30T00:00:00Z',
      },
      error: null,
    }));
    const outcome = await pushSyncBatch(client, {});
    expect(outcome.resolved).toHaveLength(1);
    expect(outcome.rejected).toEqual([{ id: ULID_B }]);
    expect(outcome.serverNow).toBe('2026-09-30T00:00:00Z');
  });

  it('surfaces an RPC failure (a whole-call rejection, e.g. unauthenticated)', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: null,
      error: { message: 'sync_push requires an authenticated user' },
    }));
    await expect(pushSyncBatch(client, {})).rejects.toThrow('sync_push failed');
  });
});

describe('payload builders (issue #1252)', () => {
  it('day-entry payloads carry exactly the seed-fixture keys and no server-stamped column', () => {
    const payload = newDayEntryPayload({
      profile_id: ULID_A,
      local_date: '2026-09-14',
      tz: 'America/New_York',
      flow: 'light',
      tags: ['sad', 'irritable'],
      note: 'Mild cramps.',
      pms: true,
    });
    expect(Object.keys(payload).sort()).toEqual(
      [
        'flow',
        'id',
        'local_date',
        'note',
        'pms',
        'profile_id',
        'tags',
        'tz',
        'updated_at',
      ].sort(),
    );
    expect('created_at' in payload).toBe(false);
    expect(payload.id).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{26}$/);
    expect(Number.isFinite(Date.parse(payload.updated_at))).toBe(true);
  });

  it('profile payloads can carry the full seed shape including created_at and cycle facts', () => {
    const payload = newProfilePayload({
      display_name: 'Maya',
      is_minor: false,
      sort_order: 0,
      created_at: '2026-09-14T12:00:00.000Z',
      birth_year: 1988,
      relationship: 'self',
      mode: 'standard',
      last_period_start: '2026-08-29',
      typical_cycle_length_days: 28,
      typical_period_length_days: 5,
      bbt_unit: 'celsius',
      weight_unit: 'kg',
    });
    expect(payload.created_at).toBe('2026-09-14T12:00:00.000Z');
    expect(payload.typical_cycle_length_days).toBe(28);
  });

  it('tombstones carry id, updated_at, deleted_at and nothing else', () => {
    const tombstone = tombstonePayload(ULID_A, () => new Date('2026-09-30T00:00:00Z'));
    expect(Object.keys(tombstone).sort()).toEqual(['deleted_at', 'id', 'updated_at']);
  });

  it('profile-mode payloads are keyed by profile with no id', () => {
    const payload = newProfileModePayload(
      { profile_id: ULID_A, mode: 'tracking', mode_started_on: '2026-07-15' },
      () => new Date('2026-09-30T00:00:00Z'),
    );
    expect('id' in payload).toBe(false);
    expect(payload.updated_at).toBe('2026-09-30T00:00:00.000Z');
  });

  it('guardian-note payloads mirror the dated, author-scoped shape', () => {
    const payload = newGuardianNotePayload({
      profile_id: ULID_A,
      local_date: '2026-09-14',
      tz: 'UTC',
      body: 'Check-in note.',
    });
    expect(Object.keys(payload).sort()).toEqual(
      ['body', 'id', 'local_date', 'profile_id', 'tz', 'updated_at'].sort(),
    );
  });

  it('care-note payloads ride sync_push like every other synced row', () => {
    const payload = newCareNotePayload({ profile_id: ULID_A, body: 'Heat pad helps.' });
    expect(payload.body).toBe('Heat pad helps.');
    expect(payload.id).not.toBe(payload.profile_id);
  });
});

// ---------------------------------------------------------------------------
// The learned server-clock offset (issue #1283)
// ---------------------------------------------------------------------------

describe('the learned server-clock offset (issue #1283)', () => {
  it("stamps raw before anything is learned — the phones' zero-offset start", () => {
    expect(learnedClockOffsetMs()).toBeNull();
    const fixed = () => new Date('2026-09-30T00:00:00Z');
    expect(nowSyncStamp(fixed)).toBe('2026-09-30T00:00:00.000Z');
    expect(serverAdjustedNow(fixed).toISOString()).toBe('2026-09-30T00:00:00.000Z');
  });

  it('folds samples through the same EMA the phones smooth with (the first as-is)', () => {
    const device = Date.parse('2026-10-01T00:00:00.000Z');
    // First sample (+10 min): nothing to smooth against — taken as-is.
    expect(learnClockOffset('2026-10-01T00:10:00.000Z', device)).toBe(600_000);
    // Second (+4 min): 600000 + 0.2 * (240000 - 600000) = 528000.
    expect(learnClockOffset('2026-10-01T00:04:00.000Z', device)).toBe(528_000);
    // Third (back to +10 min): 528000 + 0.2 * (600000 - 528000) = 542400.
    expect(learnClockOffset('2026-10-01T00:10:00.000Z', device)).toBe(542_400);
  });

  it("a browser clock ten minutes fast stops tripping sync_push's future check", async () => {
    const deviceNow = Date.now();
    // The server sits ten minutes behind this browser — the raw stamp
    // (`now + 10 min`) is past `now() + interval '5 minutes'` and every
    // row would land in `rejected` (20260921130000). The push's own
    // response teaches the offset even so: the rejection is per-row, and
    // `server_now` rides every result.
    const { client } = fakeRpcClient(async () => ({
      data: {
        resolved: [],
        rejected: [{ id: ULID_A, rejected: true }],
        server_now: new Date(deviceNow - 10 * 60_000).toISOString(),
      },
      error: null,
    }));
    await pushSyncBatch(client, {});
    expect(learnedClockOffsetMs()).not.toBeNull();
    const stamp = Date.parse(nowSyncStamp());
    // ≈ server time (device − 10 min), and never inside the server's
    // future-rejection window again.
    expect(stamp).toBeLessThan(deviceNow + 4 * 60_000);
    expect(Math.abs(stamp - (deviceNow - 10 * 60_000))).toBeLessThan(30_000);
  });

  it('a browser clock ten minutes slow stops losing last-writer-wins', async () => {
    const deviceNow = Date.now();
    // The phones just wrote at true server time; this browser is ten
    // minutes behind, so its raw stamp would read as older and the server
    // would decline the write (LWW). The learned offset lifts the stamp
    // back onto server time.
    const { client } = fakeRpcClient(async () => ({
      data: {
        resolved: [],
        rejected: [],
        server_now: new Date(deviceNow + 10 * 60_000).toISOString(),
      },
      error: null,
    }));
    await pushSyncBatch(client, {});
    const stamp = Date.parse(nowSyncStamp());
    expect(stamp).toBeGreaterThan(deviceNow + 4 * 60_000);
    expect(Math.abs(stamp - (deviceNow + 10 * 60_000))).toBeLessThan(30_000);
  });

  it('a whole-call failure teaches nothing', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: null,
      error: { message: 'sync_push requires an authenticated user' },
    }));
    await expect(pushSyncBatch(client, {})).rejects.toThrow('sync_push failed');
    expect(learnedClockOffsetMs()).toBeNull();
  });

  it('an unparseable server_now teaches nothing rather than poisoning the EMA', () => {
    expect(learnClockOffset('not-a-timestamp', Date.now())).toBe(0);
    expect(learnedClockOffsetMs()).toBeNull();
    // A good sample still seeds cleanly afterwards.
    expect(
      learnClockOffset('2026-10-01T00:10:00.000Z', Date.parse('2026-10-01T00:00:00.000Z')),
    ).toBe(600_000);
  });

  it('the identity reset keeps the offset: device-vs-server is not account data', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: {
        resolved: [],
        rejected: [],
        server_now: new Date(Date.now() + 60_000).toISOString(),
      },
      error: null,
    }));
    await pushSyncBatch(client, {});
    expect(learnedClockOffsetMs()).not.toBeNull();
    const clear = vi.fn();
    resetWebDataForSignOut({ clear });
    expect(clear).toHaveBeenCalledTimes(1);
    // Deliberately still learned: the next account's first write is
    // stamped corrected without waiting on a fresh push to re-teach it.
    expect(learnedClockOffsetMs()).not.toBeNull();
  });

  it('payload builders default to the corrected clock once an offset is learned', () => {
    learnClockOffset('2026-10-01T00:10:00.000Z', Date.parse('2026-10-01T00:00:00.000Z'));
    const payload = newDayEntryPayload({ profile_id: ULID_A, local_date: '2026-09-30' });
    // ≈ the raw device clock + the learned +10 min — server time on a
    // browser whose clock reads ten minutes slow.
    const stamp = Date.parse(payload.updated_at);
    expect(Math.abs(stamp - (Date.now() + 10 * 60_000))).toBeLessThan(30_000);
  });
});

// ---------------------------------------------------------------------------
// Direct RLS-scoped selects (settings, guardian_notes)
// ---------------------------------------------------------------------------

describe('fetchSettings (issue #1252)', () => {
  it('pages past PostgREST’s 1,000-row cap', async () => {
    const fullPage = Array.from({ length: 1_000 }, (_, i) => ({
      user_id: 'u',
      key: `k${String(i).padStart(4, '0')}`,
      value: 'v',
      updated_at: '2026-09-01T00:00:00Z',
      server_version: i,
    }));
    const tail = [
      {
        user_id: 'u',
        key: 'zzz',
        value: 'v',
        updated_at: '2026-09-01T00:00:00Z',
        server_version: 1,
      },
    ];
    const { client, ranges } = fakeSelectClient(
      new Map([
        [
          'settings',
          [
            { data: fullPage, error: null },
            { data: tail, error: null },
          ],
        ],
      ]),
    );
    const rows = await fetchSettings(client);
    expect(rows).toHaveLength(1_001);
    expect(ranges).toEqual([
      { table: 'settings', from: 0, to: 999 },
      { table: 'settings', from: 1_000, to: 1_999 },
    ]);
  });

  it('surfaces a PostgREST error', async () => {
    const { client } = fakeSelectClient(
      new Map([['settings', [{ data: [], error: { message: 'permission denied' } }]]]),
    );
    await expect(fetchSettings(client)).rejects.toThrow('permission denied');
  });
});

describe('fetchGuardianNotes (issue #1252)', () => {
  it('selects guardian_notes scoped to a profile when one is given', async () => {
    const { client, ranges } = fakeSelectClient(
      new Map([['guardian_notes', [{ data: [], error: null }]]]),
    );
    await fetchGuardianNotes(client, { profileId: ULID_A });
    expect(ranges[0]?.table).toBe('guardian_notes');
    expect(ranges[0]?.eqColumn).toBe('profile_id');
    expect(ranges[0]?.eqValue).toBe(ULID_A);
  });

  it('pages when a profile’s notes exceed the cap', async () => {
    const fullPage = Array.from({ length: 1_000 }, (_, i) => ({
      id: `${ULID_A}`,
      user_id: 'u',
      profile_id: ULID_A,
      local_date: '2026-09-14',
      tz: 'UTC',
      body: `note ${i}`,
      created_at: '2026-09-01T00:00:00Z',
      updated_at: '2026-09-01T00:00:00Z',
      deleted_at: null,
      server_version: i,
    }));
    const { client, ranges } = fakeSelectClient(
      new Map([
        [
          'guardian_notes',
          [
            { data: fullPage, error: null },
            { data: [], error: null },
          ],
        ],
      ]),
    );
    const rows = await fetchGuardianNotes(client);
    expect(rows).toHaveLength(1_000);
    expect(ranges).toHaveLength(2);
  });
});

// ---------------------------------------------------------------------------
// sync_signals subscription
// ---------------------------------------------------------------------------

describe('subscribeSyncSignals (issue #1252)', () => {
  it('creates no channel for an empty profile set', () => {
    const { client, channels } = fakeRealtimeClient();
    const subscription = subscribeSyncSignals(client, [], () => undefined);
    subscription.unsubscribe();
    expect(channels).toHaveLength(0);
  });

  it('subscribes to public.sync_signals filtered to the given profiles', () => {
    const { client, channels } = fakeRealtimeClient();
    const subscription = subscribeSyncSignals(client, [ULID_B, ULID_A], () => undefined);
    expect(channels).toHaveLength(1);
    const channel = channels[0] as FakeChannel;
    expect(channel.subscribed).toBe(true);
    expect(channel.onCalls[0]?.type).toBe('postgres_changes');
    expect(channel.onCalls[0]?.opts).toMatchObject({
      event: '*',
      schema: 'public',
      table: 'sync_signals',
      filter: `profile_id=in.(${ULID_A},${ULID_B})`,
    });
    subscription.unsubscribe();
  });

  it('fires the callback with a parsed payload and fires on a content-free event too', () => {
    const { client, channels } = fakeRealtimeClient();
    const signals: unknown[] = [];
    const subscription = subscribeSyncSignals(client, [ULID_A], (signal) =>
      signals.push(signal),
    );
    const channel = channels[0] as FakeChannel;
    channel.callbacks[0]?.({ new: { profile_id: ULID_A, updated_at: '2026-09-30T00:00:00Z' } });
    channel.callbacks[0]?.({ new: {} }); // a DELETE event carries no row
    expect(signals).toEqual([
      { profile_id: ULID_A, updated_at: '2026-09-30T00:00:00Z' },
      { profile_id: null, updated_at: null },
    ]);
    subscription.unsubscribe();
  });

  it('unsubscribe removes the channel', async () => {
    const { client, channels, removed } = fakeRealtimeClient();
    const subscription = subscribeSyncSignals(client, [ULID_A], () => undefined);
    subscription.unsubscribe();
    await Promise.resolve();
    expect(removed).toEqual(channels);
  });
});

// ---------------------------------------------------------------------------
// The in-memory session cache + merge semantics
// ---------------------------------------------------------------------------

describe('SyncedDataCache (issue #1252)', () => {
  it('refreshes from zero cursors, then incrementally from the advanced ones', async () => {
    const cache = new SyncedDataCache();
    let round = 0;
    const { client, calls } = fakeRpcClient(async (_name, params) => {
      round += 1;
      if (round === 1) {
        expect(params.p_cursors).toEqual({});
        return {
          data: { profiles: [profileRow({ server_version: 7 })] },
          error: null,
        };
      }
      expect(params.p_cursors).toEqual({ profiles: 7 });
      return {
        data: {
          profiles: [profileRow({ server_version: 8, display_name: 'Newer' })],
        },
        error: null,
      };
    });
    const first = await cache.refresh(client);
    expect(first.profiles).toHaveLength(1);
    const second = await cache.refresh(client);
    expect(second.profiles).toHaveLength(1);
    expect(second.profiles[0]?.display_name).toBe('Newer');
    expect(second.profiles[0]?.server_version).toBe(8);
    expect(calls).toHaveLength(2);
  });

  it('reset forgets cursors and rows (the sign-out path)', async () => {
    const cache = new SyncedDataCache();
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow({ server_version: 7 })] },
      error: null,
    }));
    await cache.refresh(client);
    cache.reset();
    expect(cache.current()).toEqual(emptySyncedData());
  });

  it('the shared cache resets through resetWebDataForSignOut and clears the query cache', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow({ server_version: 7 })] },
      error: null,
    }));
    await getSyncedDataCache().refresh(client);
    const clear = vi.fn();
    resetWebDataForSignOut({ clear });
    expect(clear).toHaveBeenCalledTimes(1);
    expect(getSyncedDataCache().current()).toEqual(emptySyncedData());
  });
});

describe('SyncedDataCache identity race (issue #1315)', () => {
  it('discards a pull that resolves after the reset: rows and cursors stay empty', async () => {
    const cache = new SyncedDataCache();
    let releaseStalePull!: (value: {
      data: unknown;
      error: { message: string } | null;
    }) => void;
    const stalePull = new Promise<{ data: unknown; error: { message: string } | null }>(
      (resolve) => {
        releaseStalePull = resolve;
      },
    );
    let round = 0;
    const { client } = fakeRpcClient(async (_name, params) => {
      round += 1;
      if (round === 1) {
        // Account A's pull, held in flight across the reset.
        return stalePull;
      }
      // Account B's first pull starts from zero cursors — server_version is
      // one global sequence, so A's cursors would have made B skip every
      // lower-version row. Asserted here, before pullSyncedData advances
      // the cursors object this params entry aliases.
      expect(params.p_cursors).toEqual({});
      return { data: { profiles: [profileRow({ server_version: 9 })] }, error: null };
    });

    const inFlight = cache.refresh(client); // A's pull, still awaiting the network
    cache.reset(); // the identity boundary lands mid-pull (resetWebDataForSignOut)
    releaseStalePull({
      data: { profiles: [profileRow({ server_version: 7 })] },
      error: null,
    });

    // A's rows never merge and A's cursors never land: the stale resolution
    // returns the post-reset snapshot and touches nothing.
    const stale = await inFlight;
    expect(stale).toEqual(emptySyncedData());
    expect(cache.current()).toEqual(emptySyncedData());

    // B's own pull starts from zero cursors (asserted in the handler) and
    // B's rows merge onto the still-empty snapshot.
    const fresh = await cache.refresh(client);
    expect(fresh.profiles.map((row) => row.server_version)).toEqual([9]);
  });
});

describe('mergeSyncedData (issue #1252)', () => {
  it('replaces a stored row when the pulled copy is newer, keeps it when older', () => {
    const base = emptySyncedData();
    base.day_entries = [
      {
        id: ULID_A,
        user_id: 'u',
        profile_id: ULID_B,
        local_date: '2026-09-14',
        tz: 'UTC',
        flow: 'light',
        tags: [],
        note: null,
        note_private: false,
        pms: false,
        source: 'manual',
        created_at: '2026-09-14T00:00:00Z',
        updated_at: '2026-09-14T10:00:00Z',
        deleted_at: null,
        server_version: 5,
      },
    ];
    const newer = structuredClone(base);
    newer.day_entries = [
      { ...base.day_entries[0], updated_at: '2026-09-14T11:00:00Z', flow: 'heavy' },
    ];
    const merged = mergeSyncedData(base, newer);
    expect(merged.day_entries[0]?.flow).toBe('heavy');

    const older = structuredClone(base);
    older.day_entries = [
      { ...base.day_entries[0], updated_at: '2026-09-14T09:00:00Z', flow: 'heavy' },
    ];
    expect(mergeSyncedData(base, older).day_entries[0]?.flow).toBe('light');
  });

  it('merges profile_modes by their natural key (profile_id, no id)', () => {
    const base = emptySyncedData();
    base.profile_modes = [
      {
        profile_id: ULID_A,
        mode: 'tracking',
        mode_started_on: '2026-07-15',
        health_sync_consent: false,
        updated_at: '2026-09-01T00:00:00Z',
        server_version: 3,
      },
    ];
    const incoming = emptySyncedData();
    incoming.profile_modes = [
      {
        profile_id: ULID_A,
        mode: 'pregnancy',
        mode_started_on: '2026-09-01',
        health_sync_consent: false,
        updated_at: '2026-09-15T00:00:00Z',
        server_version: 9,
      },
    ];
    const merged = mergeSyncedData(base, incoming);
    expect(merged.profile_modes).toHaveLength(1);
    expect(merged.profile_modes[0]?.mode).toBe('pregnancy');
  });

  it('keeps tombstones (deleted_at rows) — screens filter, the snapshot preserves', () => {
    const base = emptySyncedData();
    const incoming = emptySyncedData();
    incoming.profiles = [profileRow({ deleted_at: '2026-09-20T00:00:00Z' })];
    const merged = mergeSyncedData(base, incoming);
    expect(merged.profiles[0]?.deleted_at).not.toBeNull();
  });
});
