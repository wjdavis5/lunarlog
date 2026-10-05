import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  CURSOR_LOOKBACK,
  emptySyncedData,
  fetchGuardianNotes,
  fetchSettings,
  getSyncedDataCache,
  learnClockOffset,
  learnedClockOffsetMs,
  mergeSyncedData,
  MEMBERSHIP_RECONCILE_INTERVAL_MS,
  newCareNotePayload,
  newDayEntryPayload,
  newGuardianNotePayload,
  newProfileModePayload,
  editedProfilePayload,
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
    const { client, calls } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        // A generous watermark clamps nothing — the default for these
        // structural tests; the clamp itself has its own describe below.
        return { data: 1_000_000, error: null };
      }
      return {
        data: { profiles: [profileRow({ server_version: 100 })], day_entries: [] },
        error: null,
      };
    });
    const { data, cursors } = await pullSyncedData(client);
    // The commit-safe watermark is probed once per pull, before the pages.
    expect(calls.map((call) => call.name)).toEqual(['sync_watermark', 'sync_pull']);
    expect(data.profiles).toHaveLength(1);
    expect(data.profiles[0]?.display_name).toBe('Maya');
    expect(cursors.profiles).toBe(100);
  });

  it('pages past the 500-row cap: a full page triggers another round with the advanced cursor', async () => {
    const fullPage = Array.from({ length: 500 }, (_, i) =>
      profileRow({ id: ULID_A, server_version: i + 1 }),
    );
    let round = 0;
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      round += 1;
      if (round === 1) {
        expect(params.p_cursors).toEqual({});
        return { data: { profiles: fullPage }, error: null };
      }
      expect(params.p_cursors).toEqual({ profiles: 500 });
      return { data: { profiles: [profileRow({ server_version: 501 })] }, error: null };
    });
    const { data, cursors } = await pullSyncedData(client);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
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
    // Runs on an injected budget instead of the production 1,000-round
    // cap: a real full page means 1,000 rounds of genuine row parsing to
    // reach the throw — seconds of pure worst-case CPU that put the CI
    // runner past the 5s default test timeout (issue #1348). Three rounds
    // assert the same property deterministically: an always-full page
    // stops the loop at the cap and fails closed with the count in the
    // message, rather than spinning.
    const fullPage = Array.from({ length: 500 }, (_, i) =>
      profileRow({ server_version: i + 1 }),
    );
    let pulls = 0;
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: null, error: null };
      }
      pulls += 1;
      return { data: { profiles: fullPage }, error: null };
    });
    await expect(pullSyncedData(client, { maxRounds: 3 })).rejects.toThrow(
      'sync_pull did not exhaust within 3 rounds',
    );
    expect(pulls).toBe(3);
  });

  it('a budget the pages fit inside returns normally', async () => {
    const { client, calls } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      return {
        data: { profiles: [profileRow({ server_version: 1 })] },
        error: null,
      };
    });
    const { cursors } = await pullSyncedData(client, { maxRounds: 3 });
    expect(cursors.profiles).toBe(1);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(1);
  });
});

describe('pullSyncedData cursor clamp (issue #1282)', () => {
  // The commit-order race (issue #521): a row's `server_version` is
  // assigned pre-commit, so the highest *pulled* version is not necessarily
  // the highest *settled* one — advancing the cursor to it unclamped would
  // strand the late commit below the cursor forever (`server_version >
  // cursor` is a strict pull).
  it('clamps the returned cursors to the server watermark when it sits below the pulled maximum', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 4800, error: null };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client);
    expect(cursors.profiles).toBe(4800);
  });

  it('accepts a quoted numeric string watermark (a bigint wire shape)', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: '4800', error: null };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client);
    expect(cursors.profiles).toBe(4800);
  });

  it('falls back to CURSOR_LOOKBACK below the maximum when the watermark RPC fails', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        // A server predating the watermark migration (or any transient
        // failure): the pull must still succeed, cursor held short of the
        // page max instead.
        return { data: null, error: { message: 'function not found in schema cache' } };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client);
    expect(cursors.profiles).toBe(5000 - CURSOR_LOOKBACK);
  });

  it('never regresses a cursor below where the pull started (a stale watermark holds, not moves back)', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 100, error: null };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client, { cursors: { profiles: 4000 } });
    expect(cursors.profiles).toBe(4000);
  });

  it('the lookback fallback never regresses a cursor either', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: null, error: { message: 'unavailable' } };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client, { cursors: { profiles: 4999 } });
    // max − 50 would land below the start cursor; the start cursor wins.
    expect(cursors.profiles).toBe(4999);
  });

  it('a watermark above the pulled maximum clamps nothing', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 900_000, error: null };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client);
    expect(cursors.profiles).toBe(5000);
  });

  it('tables with no rows this pull keep their start cursor under a stale watermark', async () => {
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 100, error: null };
      }
      return { data: { profiles: [profileRow({ server_version: 5000 })] }, error: null };
    });
    const { cursors } = await pullSyncedData(client, {
      cursors: { profiles: 0, day_entries: 400 },
    });
    expect(cursors.profiles).toBe(100);
    expect(cursors.day_entries).toBe(400);
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

  it('a new profile payload carries the full seed shape, created now and un-archived', () => {
    const clock = (): Date => new Date('2026-09-14T12:00:00.000Z');
    const payload = newProfilePayload(
      {
        display_name: 'Maya',
        is_minor: false,
        sort_order: 0,
        birth_year: 1988,
        relationship: 'self',
        mode: 'standard',
        last_period_start: '2026-08-29',
        typical_cycle_length_days: 28,
        typical_period_length_days: 5,
        bbt_unit: 'celsius',
        weight_unit: 'kg',
      },
      clock,
    );
    expect(payload.created_at).toBe('2026-09-14T12:00:00.000Z');
    expect(payload.updated_at).toBe('2026-09-14T12:00:00.000Z');
    expect(payload.archived_at).toBeNull();
    expect(payload.typical_cycle_length_days).toBe(28);
  });

  // Issue #1388: sync_push's profiles UPDATE writes display_name,
  // sort_order, archived_at and created_at from the payload unconditionally,
  // so an edit that omits one clears it for every guardian's device.
  describe('editedProfilePayload', () => {
    const stored = {
      id: ULID_A,
      created_at: '2026-08-01T09:30:00.123456+00:00',
      display_name: 'Maya',
      sort_order: 3,
      archived_at: '2026-09-01T00:00:00+00:00',
    };
    const clock = (): Date => new Date('2026-09-14T12:00:00.000Z');

    it('carries every full-row column forward when the change names none of them', () => {
      const payload = editedProfilePayload(stored, { birth_year: 1990 }, clock);
      expect(payload).toEqual({
        ...stored,
        birth_year: 1990,
        updated_at: '2026-09-14T12:00:00.000Z',
      });
    });

    it('applies a named change and keeps the rest of the stored row', () => {
      const renamed = editedProfilePayload(stored, { display_name: 'Maya B' }, clock);
      expect(renamed.display_name).toBe('Maya B');
      expect(renamed.sort_order).toBe(3);
      expect(renamed.archived_at).toBe(stored.archived_at);
      expect(renamed.created_at).toBe(stored.created_at);

      const unarchived = editedProfilePayload(stored, { archived_at: null }, clock);
      expect(unarchived.archived_at).toBeNull();
      expect(unarchived.display_name).toBe('Maya');
    });

    it('never serialises a partial row, even for an explicitly undefined change', () => {
      const payload = editedProfilePayload(
        stored,
        { display_name: undefined, sort_order: undefined, archived_at: undefined },
        clock,
      );
      const wire = JSON.parse(JSON.stringify(payload)) as Record<string, unknown>;
      expect(wire).toMatchObject(stored);
    });

    it('leaves guarded columns off the wire unless changed (the server preserves those)', () => {
      const payload = editedProfilePayload(stored, {}, clock);
      expect(Object.keys(payload).sort()).toEqual(
        ['archived_at', 'created_at', 'display_name', 'id', 'sort_order', 'updated_at'].sort(),
      );
    });
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
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
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
    const first = await cache.refresh(client, () => null);
    expect(first.profiles).toHaveLength(1);
    const second = await cache.refresh(client, () => null);
    expect(second.profiles).toHaveLength(1);
    expect(second.profiles[0]?.display_name).toBe('Newer');
    expect(second.profiles[0]?.server_version).toBe(8);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
  });

  it('reset forgets cursors and rows (the sign-out path)', async () => {
    const cache = new SyncedDataCache();
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow({ server_version: 7 })] },
      error: null,
    }));
    await cache.refresh(client, () => null);
    cache.reset();
    expect(cache.current()).toEqual(emptySyncedData());
  });

  it('the shared cache resets through resetWebDataForSignOut and clears the query cache', async () => {
    const { client } = fakeRpcClient(async () => ({
      data: { profiles: [profileRow({ server_version: 7 })] },
      error: null,
    }));
    await getSyncedDataCache().refresh(client, () => null);
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
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
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

    const inFlight = cache.refresh(client, () => null); // A's pull, still awaiting the network
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
    const fresh = await cache.refresh(client, () => null);
    expect(fresh.profiles.map((row) => row.server_version)).toEqual([9]);
  });
});

describe('SyncedDataCache identity tag (issue #1338)', () => {
  it('discards a pull that ran under an account the snapshot was not built for', async () => {
    const cache = new SyncedDataCache();
    let account: string | null = 'user-a';
    const readIdentity = () => account;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      // Captured before pullSyncedData advances the cursors object this
      // params entry aliases (the #1315 test's note applies here too).
      cursorsSeen.push(structuredClone(params.p_cursors));
      if (cursorsSeen.length === 1) {
        return { data: { profiles: [profileRow({ server_version: 7 })] }, error: null };
      }
      return {
        data: {
          profiles: [profileRow({ id: ULID_B, display_name: 'B-only', server_version: 9 })],
        },
        error: null,
      };
    });

    // Built under A: the pull merges and the cache tags itself with A.
    const underA = await cache.refresh(client, readIdentity);
    expect(underA.profiles.map((row) => row.display_name)).toEqual(['Maya']);

    // The refresh cookie flips to B; the next pull runs entirely under B
    // with no reset in between — the generation never moves, so only the
    // tag catches it. B's row never merges onto A's snapshot.
    account = 'user-b';
    const pulledUnderB = await cache.refresh(client, readIdentity);
    expect(pulledUnderB.profiles.map((row) => row.display_name)).toEqual(['Maya']);
    expect(cache.current().profiles.map((row) => row.id)).toEqual([ULID_A]);

    // The watcher's reset re-bases the cache on B: zero cursors, B's rows
    // merge, and the tag moves to B.
    cache.reset();
    const underB = await cache.refresh(client, readIdentity);
    expect(underB.profiles.map((row) => row.display_name)).toEqual(['B-only']);
    expect(cursorsSeen).toEqual([{}, { profiles: 7 }, {}]);
  });

  it('discards a pull that re-identifies itself mid-flight (a renewal adopted the replaced cookie)', async () => {
    const cache = new SyncedDataCache();
    let account: string | null = 'user-a';
    const readIdentity = () => account;
    let releasePull!: (value: { data: unknown; error: { message: string } | null }) => void;
    const heldPull = new Promise<{ data: unknown; error: { message: string } | null }>(
      (resolve) => {
        releasePull = resolve;
      },
    );
    // Both RPCs the pull now makes (the watermark probe and sync_pull) wait
    // on the same held response: the probe reads its object payload as "no
    // watermark", the pull parses its row.
    const { client } = fakeRpcClient(async () => heldPull);

    const inFlight = cache.refresh(client, readIdentity); // A's pull, awaiting the network
    // The pull's bearer renewal runs mid-pull and adopts whatever account
    // the shared refresh cookie now holds — the same request stream is now
    // B's — before the pull resolves.
    account = 'user-b';
    releasePull({
      data: {
        profiles: [profileRow({ id: ULID_B, display_name: 'B-only', server_version: 7 })],
      },
      error: null,
    });

    // B's rows never merge and the cursors never advance: the id read at
    // resolution no longer matches the one the pull started under.
    const discarded = await inFlight;
    expect(discarded).toEqual(emptySyncedData());
    expect(cache.current()).toEqual(emptySyncedData());
  });

  it('keeps merging while the account stays the same', async () => {
    const cache = new SyncedDataCache();
    let round = 0;
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      round += 1;
      if (round === 1) {
        expect(params.p_cursors).toEqual({});
        return { data: { profiles: [profileRow({ server_version: 7 })] }, error: null };
      }
      expect(params.p_cursors).toEqual({ profiles: 7 });
      return {
        data: { profiles: [profileRow({ server_version: 8, display_name: 'Newer' })] },
        error: null,
      };
    });
    const readIdentity = () => 'user-a';
    const first = await cache.refresh(client, readIdentity);
    expect(first.profiles).toHaveLength(1);
    // Same account at resolution: the incremental pull merges as usual —
    // the tag never discards a pull that re-resolves to its own account.
    const second = await cache.refresh(client, readIdentity);
    expect(second.profiles[0]?.server_version).toBe(8);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
  });
});

describe('SyncedDataCache.repullAll (issue #1282)', () => {
  const ME = 'user-a';
  function guardianRow(
    profileId: string,
    overrides: Record<string, unknown> = {},
  ): Record<string, unknown> {
    return {
      id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2f',
      profile_id: profileId,
      user_id: ME,
      role: 'primary_guardian',
      status: 'accepted',
      created_at: '2026-09-01T00:00:00Z',
      updated_at: '2026-09-01T00:00:00Z',
      server_version: 5,
      ...overrides,
    };
  }

  it('re-pulls from zero into a fresh snapshot: a left profile is dropped, not merged over', async () => {
    const cache = new SyncedDataCache();
    const cursorsSeen: unknown[] = [];
    let pull = 0;
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return {
          data: {
            profiles: [profileRow({ id: ULID_A, server_version: 900 })],
            profile_guardians: [guardianRow(ULID_A, { server_version: 901 })],
          },
          error: null,
        };
      }
      // After the leave, sync_pull returns nothing for the profile — the
      // re-pull's response simply lacks it.
      return { data: { profiles: [], profile_guardians: [] }, error: null };
    });
    const readIdentity = () => ME;
    const first = await cache.refresh(client, readIdentity);
    expect(first.profiles.map((row) => row.id)).toEqual([ULID_A]);

    const repulled = await cache.repullAll(client, readIdentity);
    // A fresh snapshot: A is gone entirely (an incremental merge would have
    // kept it — nothing tombstones a profile the RLS no longer returns).
    expect(repulled.profiles).toEqual([]);
    expect(cache.current().profiles).toEqual([]);
    // The re-pull started from zero cursors, not the session's 900s.
    expect(cursorsSeen).toEqual([{}, {}]);
    // And the fresh cursors are the re-pull's (empty here — no rows), so
    // the next refresh starts over from zero too.
    const third = await cache.refresh(client, readIdentity);
    expect(cursorsSeen[2]).toEqual({});
    expect(third.profiles).toEqual([]);
  });

  it('brings a joined profile into the snapshot even though its versions sit below the old cursors', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      pull += 1;
      if (pull === 1) {
        // The long-standing profile the account already guards; its
        // versions put the session cursors far above anything the joined
        // profile (created long ago, accepted just now) will ever carry.
        expect(params.p_cursors).toEqual({});
        return {
          data: {
            profiles: [profileRow({ id: ULID_A, server_version: 900 })],
            profile_guardians: [guardianRow(ULID_A, { server_version: 901 })],
          },
          error: null,
        };
      }
      // The accept inserts no server_version bump on the joined profile's
      // rows — the re-pull is the only way its history arrives.
      expect(params.p_cursors).toEqual({});
      return {
        data: {
          profiles: [
            profileRow({ id: ULID_A, server_version: 900 }),
            profileRow({ id: ULID_B, display_name: 'Joined', server_version: 3 }),
          ],
          day_entries: [
            {
              id: '01ARZ3NDEKTSV4RRFFQ69G5FBV',
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
              updated_at: '2026-09-14T00:00:00Z',
              deleted_at: null,
              server_version: 4,
            },
          ],
          profile_guardians: [
            guardianRow(ULID_A, { server_version: 901 }),
            guardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              server_version: 5,
            }),
          ],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const repulled = await cache.repullAll(client, readIdentity);
    expect(repulled.profiles.map((row) => row.id)).toEqual([ULID_A, ULID_B]);
    expect(repulled.day_entries.map((row) => row.profile_id)).toEqual([ULID_B]);
  });

  it('drops profiles absent from the accepted profile_guardians set, with their dependent rows', async () => {
    const cache = new SyncedDataCache();
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      return {
        data: {
          profiles: [
            profileRow({ id: ULID_A, server_version: 900 }),
            profileRow({ id: ULID_B, display_name: 'Revoked-under-me', server_version: 3 }),
          ],
          day_entries: [
            {
              id: '01ARZ3NDEKTSV4RRFFQ69G5FBV',
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
              updated_at: '2026-09-14T00:00:00Z',
              deleted_at: null,
              server_version: 4,
            },
          ],
          // sync_pull's profile_guardians branch returns every guardian row
          // on the pulled profiles: mine on A (accepted) and on B (the
          // stale revoked row this filter exists for).
          profile_guardians: [
            guardianRow(ULID_A, { server_version: 901 }),
            guardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              status: 'revoked',
              server_version: 5,
            }),
            // Another guardian's accepted row on A — present, but not mine:
            // it must not put B's data back (the set is keyed on MY rows).
            guardianRow(ULID_A, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2d',
              user_id: 'user-other',
              server_version: 6,
            }),
          ],
        },
        error: null,
      };
    });
    const repulled = await cache.repullAll(client, () => ME);
    expect(repulled.profiles.map((row) => row.id)).toEqual([ULID_A]);
    expect(repulled.day_entries).toEqual([]);
    // B's revoked row is gone; both remaining guardian rows sit on A —
    // mine and the other guardian's (whose row never re-admits B: the set
    // is derived from THIS account's own rows only).
    expect(repulled.profile_guardians.map((row) => row.id)).toEqual([
      '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2f',
      '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2d',
    ]);
  });

  it('discards a re-pull that resolves across a reset (the #1315 guard)', async () => {
    const cache = new SyncedDataCache();
    let releasePull!: (value: { data: unknown; error: { message: string } | null }) => void;
    const heldPull = new Promise<{ data: unknown; error: { message: string } | null }>(
      (resolve) => {
        releasePull = resolve;
      },
    );
    let pull = 0;
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      pull += 1;
      return pull === 1
        ? { data: { profiles: [profileRow({ id: ULID_A, server_version: 7 })] }, error: null }
        : heldPull;
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const inFlight = cache.repullAll(client, readIdentity);
    cache.reset(); // the identity boundary lands mid-re-pull
    releasePull({
      data: {
        profiles: [profileRow({ id: ULID_B, display_name: 'Too late', server_version: 9 })],
      },
      error: null,
    });
    const discarded = await inFlight;
    // The re-pull's fresh snapshot never lands: the post-reset (empty)
    // snapshot is handed back and the cache stays empty for the next
    // account.
    expect(discarded).toEqual(emptySyncedData());
    expect(cache.current()).toEqual(emptySyncedData());
  });

  it('discards a re-pull that ran under an account the snapshot was not built for (the #1338 guard)', async () => {
    const cache = new SyncedDataCache();
    let account: string | null = ME;
    let pull = 0;
    const { client } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      pull += 1;
      return pull === 1
        ? { data: { profiles: [profileRow({ id: ULID_A, server_version: 7 })] }, error: null }
        : {
            data: {
              profiles: [profileRow({ id: ULID_B, display_name: 'B-only', server_version: 9 })],
            },
            error: null,
          };
    });
    await cache.refresh(client, () => account);
    account = 'user-b'; // the cookie flipped with no reset in between
    const discarded = await cache.repullAll(client, () => account);
    expect(discarded.profiles.map((row) => row.id)).toEqual([ULID_A]);
    expect(cache.current().profiles.map((row) => row.id)).toEqual([ULID_A]);
  });
});

describe('SyncedDataCache membership drift (issue #1370)', () => {
  const ME = 'user-a';

  function myGuardianRow(
    profileId: string,
    overrides: Record<string, unknown> = {},
  ): Record<string, unknown> {
    return {
      id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2f',
      profile_id: profileId,
      user_id: ME,
      role: 'primary_guardian',
      status: 'accepted',
      created_at: '2026-09-01T00:00:00Z',
      updated_at: '2026-09-01T00:00:00Z',
      server_version: 5,
      ...overrides,
    };
  }

  function dayEntryRow(profileId: string, serverVersion: number): Record<string, unknown> {
    return {
      id: '01ARZ3NDEKTSV4RRFFQ69G5FBV',
      user_id: 'u',
      profile_id: profileId,
      local_date: '2026-09-14',
      tz: 'UTC',
      flow: 'light',
      tags: [],
      note: null,
      note_private: false,
      pms: false,
      source: 'manual',
      created_at: '2026-09-14T00:00:00Z',
      updated_at: '2026-09-14T00:00:00Z',
      deleted_at: null,
      server_version: serverVersion,
    };
  }

  // The long-held profile: its rows put the session cursors at ~900, far
  // above anything a profile joined later will ever carry (the accept
  // bumps no server_version).
  const heldState = () => ({
    profiles: [profileRow({ id: ULID_A, server_version: 900 })],
    profile_guardians: [myGuardianRow(ULID_A, { server_version: 901 })],
  });

  it('escalates to a from-zero re-pull when a pulled guardian row names a profile the snapshot lacks (joined on another device)', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      if (pull === 2) {
        // The accept landed on the phone: my guardian row on B is new
        // (above the cursors) but B's own rows predate them and never
        // arrive — the incremental pull cannot converge.
        return {
          data: {
            profile_guardians: [
              myGuardianRow(ULID_B, {
                id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
                server_version: 950,
              }),
            ],
          },
          error: null,
        };
      }
      // The escalation's from-zero pull: B's full history finally arrives.
      return {
        data: {
          profiles: [
            profileRow({ id: ULID_A, server_version: 900 }),
            profileRow({ id: ULID_B, display_name: 'Joined', server_version: 3 }),
          ],
          day_entries: [dayEntryRow(ULID_B, 4)],
          profile_guardians: [
            myGuardianRow(ULID_A, { server_version: 901 }),
            myGuardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              server_version: 5,
            }),
          ],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const converged = await cache.refresh(client, readIdentity);
    expect(converged.profiles.map((row) => row.id)).toEqual([ULID_A, ULID_B]);
    expect(converged.day_entries.map((row) => row.profile_id)).toEqual([ULID_B]);
    // The incremental pull's cursors never landed: the escalation re-pulled
    // from zero and its cursors took over.
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }, {}]);
  });

  it('does not escalate when the pulled guardian row names a profile the same pull delivers', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      // B's profile row happens to sit above the cursors too: the merged
      // view holds it, so there is no drift to repair.
      return {
        data: {
          profiles: [profileRow({ id: ULID_B, display_name: 'Joined', server_version: 905 })],
          profile_guardians: [
            myGuardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              server_version: 950,
            }),
          ],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const second = await cache.refresh(client, readIdentity);
    expect(second.profiles.map((row) => row.id)).toEqual([ULID_A, ULID_B]);
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }]);
  });

  it('does not escalate on another guardian’s row naming an unpulled profile (the check is keyed on my rows)', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      // A co-guardian's accepted row on a profile my snapshot lacks: not my
      // membership, so no drift on my behalf.
      return {
        data: {
          profile_guardians: [
            myGuardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              user_id: 'user-other',
              server_version: 950,
            }),
          ],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const second = await cache.refresh(client, readIdentity);
    // The snapshot keeps its own row and merely merges the co-guardian's
    // in — no re-pull happened.
    expect(second.profile_guardians.map((row) => row.user_id)).toEqual([
      'user-a',
      'user-other',
    ]);
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }]);
  });

  it('does not escalate on my revoked row naming an unpulled profile (only accepted memberships signal a join)', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      return {
        data: {
          profile_guardians: [
            myGuardianRow(ULID_B, {
              id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
              status: 'revoked',
              server_version: 950,
            }),
          ],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    await cache.refresh(client, readIdentity);
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }]);
  });

  it('keeps merging incrementally when there is no drift and the from-zero baseline is fresh', async () => {
    const cache = new SyncedDataCache();
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      return {
        data: {
          profiles: [profileRow({ id: ULID_A, server_version: 902, display_name: 'Newer' })],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    const first = await cache.refresh(client, readIdentity);
    const second = await cache.refresh(client, readIdentity);
    expect(first.profiles[0]?.display_name).toBe('Maya');
    expect(second.profiles[0]?.display_name).toBe('Newer');
    // Exactly the two pulls, the second incremental: the steady state is
    // untouched by the drift machinery.
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }]);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
  });

  it('escalates to a from-zero reconcile once the baseline is stale, dropping a profile revoked elsewhere with no tombstone', async () => {
    let now = 1_000_000;
    const cache = new SyncedDataCache(() => now);
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      // The revoke: A left sync_pull's tenant set, so the incremental pull
      // returns nothing at all — and neither does the from-zero reconcile.
      // No tombstone ever arrives; only the reconcile can drop the row.
      return { data: {}, error: null };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    now += MEMBERSHIP_RECONCILE_INTERVAL_MS + 1;
    const reconciled = await cache.refresh(client, readIdentity);
    expect(reconciled.profiles).toEqual([]);
    expect(cache.current().profiles).toEqual([]);
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }, {}]);
  });

  it('keeps merging incrementally just under the reconcile interval', async () => {
    let now = 1_000_000;
    const cache = new SyncedDataCache(() => now);
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      return {
        data: {
          profiles: [profileRow({ id: ULID_A, server_version: 902, display_name: 'Newer' })],
        },
        error: null,
      };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    now += MEMBERSHIP_RECONCILE_INTERVAL_MS - 1;
    const second = await cache.refresh(client, readIdentity);
    expect(second.profiles[0]?.display_name).toBe('Newer');
    expect(cursorsSeen).toEqual([{}, { profiles: 900, profile_guardians: 901 }]);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
  });

  it('never escalates a pull the identity guard discarded (a reset landed mid-pull)', async () => {
    const cache = new SyncedDataCache();
    let releasePull!: (value: { data: unknown; error: { message: string } | null }) => void;
    const heldPull = new Promise<{ data: unknown; error: { message: string } | null }>(
      (resolve) => {
        releasePull = resolve;
      },
    );
    let pull = 0;
    const { client, calls } = fakeRpcClient(async (name) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      return heldPull;
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    const inFlight = cache.refresh(client, readIdentity);
    cache.reset(); // the identity boundary lands mid-pull
    releasePull({
      // Drift rows, but the pull they rode in on is about to be discarded.
      data: {
        profile_guardians: [
          myGuardianRow(ULID_B, {
            id: '2f2f2f2f-2f2f-4f2f-8f2f-2f2f2f2f2f2e',
            server_version: 950,
          }),
        ],
      },
      error: null,
    });
    const discarded = await inFlight;
    expect(discarded).toEqual(emptySyncedData());
    expect(cache.current()).toEqual(emptySyncedData());
    // No escalation followed the discard: the next account's first pull is
    // its own from-zero baseline.
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(2);
  });

  it('an explicit repullAll re-bases the reconcile baseline (the sharing pages’ own re-pulls count)', async () => {
    let now = 1_000_000;
    const cache = new SyncedDataCache(() => now);
    let pull = 0;
    const cursorsSeen: unknown[] = [];
    const { client, calls } = fakeRpcClient(async (name, params) => {
      if (name === 'sync_watermark') {
        return { data: 1_000_000, error: null };
      }
      cursorsSeen.push(structuredClone(params.p_cursors));
      pull += 1;
      if (pull === 1) {
        return { data: heldState(), error: null };
      }
      if (pull === 2) {
        // The leave's own re-pull (repullMembershipData): A is gone.
        return { data: {}, error: null };
      }
      return { data: {}, error: null };
    });
    const readIdentity = () => ME;
    await cache.refresh(client, readIdentity);
    await cache.repullAll(client, readIdentity);
    now += MEMBERSHIP_RECONCILE_INTERVAL_MS - 1;
    await cache.refresh(client, readIdentity);
    // The refresh after the explicit re-pull stays incremental: the
    // re-pull itself was the reconcile.
    expect(cursorsSeen).toEqual([{}, {}, {}]);
    expect(calls.filter((call) => call.name === 'sync_pull')).toHaveLength(3);
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
