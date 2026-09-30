import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  DaySaveError,
  fetchDayView,
  resetPullCursorsForTests,
  saveDay,
} from '../src/lib/day/day-data';
import { DayPermissionError, type DayEdit, type LoadedDayView } from '../src/lib/day/payloads';
import type { AppSupabaseClient } from '../src/lib/supabase';
import type { DayEntryRow, GuardianMembershipRow, ProfileRow } from '../src/lib/schemas';

/**
 * The day editor's data module against a fake Supabase client (issue
 * #1254): the live-stack behaviour — payload acceptance, merge handbacks,
 * opaque rejections — is the round-trip integration test's job
 * (webapp/test/day-round-trip.local.test.ts, wired into CI's db-tests
 * job). What only these unit tests can pin is the mapping: which field a
 * rejected row id lights up, which server answer is a decline rather than
 * a failure, and how the masked sync_pull walk pages and caches cursors.
 */

const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const ENTRY_ID = '01M2FWKNG0ZMH2ANCH7R2CM2Y2';
const NOW = '2026-09-30T08:00:00.000Z';

const baseProfile: ProfileRow = {
  id: PROFILE_ID,
  display_name: 'Maya',
  is_minor: false,
  mode: 'standard',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  bbt_unit: 'celsius',
  weight_unit: 'kg',
  tracking_preferences: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
};

const membership: GuardianMembershipRow = {
  profile_id: PROFILE_ID,
  role: 'primary_guardian',
  status: 'accepted',
  is_subject: true,
};

const storedEntry: DayEntryRow = {
  id: ENTRY_ID,
  profile_id: PROFILE_ID,
  local_date: '2026-09-29',
  tz: 'UTC',
  flow: 'none',
  tags: [],
  note: null,
  note_private: false,
  pms: false,
  source: 'manual',
  source_id: null,
  updated_at: '2026-09-29T08:00:00.000Z',
  deleted_at: null,
};

const baseView: LoadedDayView = {
  profile: baseProfile,
  entry: storedEntry,
  observations: [],
  membership,
  mode: null,
  cycleOverride: null,
};

const baseEdit: DayEdit = {
  flow: 'light',
  flowExplicitlySet: true,
  spotting: false,
  pms: false,
  tags: ['cramps'],
  note: 'hello',
  notePrivate: false,
  bbt: null,
  weight: null,
  mode: null,
  manualCycleStart: false,
  excludeCycleFromAverage: false,
};

/** A chainable, thenable query stub: select().eq().maybeSingle() all resolve
 * to the same configured result. */
function queryChain(result: { data: unknown; error: { message: string } | null }) {
  const chain: Record<string, unknown> = {};
  const resolved = Promise.resolve(result);
  for (const method of ['select', 'eq', 'is', 'order', 'limit']) {
    chain[method] = vi.fn().mockReturnValue(chain);
  }
  chain.maybeSingle = vi.fn().mockReturnValue(resolved);
  chain.then = resolved.then.bind(resolved);
  chain.catch = resolved.catch.bind(resolved);
  return chain;
}

/** The sync_pull page: every synced table answers on every call. */
function pullPage(rows: {
  profiles?: Record<string, unknown>[];
  day_entries?: Record<string, unknown>[];
  observations?: Record<string, unknown>[];
  profile_modes?: Record<string, unknown>[];
  cycle_overrides?: Record<string, unknown>[];
  profile_tag_registry?: Record<string, unknown>[];
}) {
  return {
    profiles: rows.profiles ?? [{ ...baseProfile, server_version: 3 }],
    day_entries: rows.day_entries ?? [],
    observations: rows.observations ?? [],
    profile_modes: rows.profile_modes ?? [],
    cycle_overrides: rows.cycle_overrides ?? [],
    profile_tag_registry: rows.profile_tag_registry ?? [],
  };
}

const pulledEntry = { ...storedEntry, server_version: 7 };

/** A fake client: sync_pull answers with `page`, the membership select with
 * `membership`, and every other rpc with `rpcResult`. With `fullPageOnce`,
 * the first sync_pull returns a full 500-row day_entries page and every
 * later one returns an empty page — the drain-then-stop walk. */
function fakeClient(options?: {
  page?: ReturnType<typeof pullPage>;
  fullPageOnce?: boolean;
  membership?: { data: unknown; error: { message: string } | null };
  rpcResult?: { data: unknown; error: { message: string } | null };
  pullError?: { message: string } | null;
}) {
  let pullCalls = 0;
  const rpc = vi.fn().mockImplementation((name: string) => {
    if (name === 'sync_pull') {
      pullCalls += 1;
      const data = options?.pullError
        ? null
        : options?.fullPageOnce === true
          ? pullCalls === 1
            ? pullPage({
                day_entries: Array.from({ length: 500 }, (_, i) => ({
                  ...storedEntry,
                  id: `ROW${String(i).padStart(21, '0')}`,
                  local_date: '2026-01-01', // a different day, so the view ignores it
                  server_version: i + 1,
                })),
              })
            : pullPage({ day_entries: [{ ...pulledEntry, server_version: 501 }] })
          : (options?.page ?? pullPage({ day_entries: [pulledEntry] }));
      return Promise.resolve({ data, error: options?.pullError ?? null });
    }
    return Promise.resolve(options?.rpcResult ?? { data: {}, error: null });
  });
  const from = vi.fn().mockImplementation((table: string) => {
    if (table !== 'profile_guardians') {
      throw new Error(`fakeClient: unexpected table '${table}'`);
    }
    return queryChain(options?.membership ?? { data: membership, error: null });
  });
  return {
    client: {
      from,
      rpc,
      auth: { getSession: async () => ({ data: { session: { user: { id: 'uid-1' } } } }) },
    } as unknown as AppSupabaseClient,
    from,
    rpc,
  };
}

describe('fetchDayView (issue #1254)', () => {
  beforeEach(() => {
    resetPullCursorsForTests();
  });

  it('reads the day through the masked sync_pull walk and resolves the caller role', async () => {
    const { client } = fakeClient({ page: pullPage({ day_entries: [pulledEntry] }) });
    const view = await fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' });
    expect(view.profile.display_name).toBe('Maya');
    expect(view.entry?.id).toBe(ENTRY_ID);
    expect(view.membership?.role).toBe('primary_guardian');
    expect(view.customTags).toEqual([]);
  });

  it('advances the session cursors so the next read is an increment', async () => {
    const { client, rpc } = fakeClient();
    await fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' });
    await fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' });
    const calls = rpc.mock.calls.filter(([name]) => name === 'sync_pull');
    expect(calls).toHaveLength(2);
    const cursors = (calls[1] as unknown as [string, { p_cursors: Record<string, number> }])[1];
    expect(cursors.p_cursors['day_entries']).toBe(7);
    expect(cursors.p_cursors['profiles']).toBe(3);
  });

  it('keeps walking while a table returns a full page', async () => {
    const { client, rpc } = fakeClient({ fullPageOnce: true });
    const view = await fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' });
    // Two rounds: the full page, then the short page — the cursor moved
    // past 500 so the walk stopped.
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(view.entry?.id).toBe(ENTRY_ID);
  });

  it('throws a typed error when the profile is not in the pulled set', async () => {
    const { client } = fakeClient({ page: pullPage({ profiles: [] }) });
    await expect(
      fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' }),
    ).rejects.toThrowError(/not visible/);
  });

  it('propagates a sync_pull failure as a typed error', async () => {
    const { client } = fakeClient({
      pullError: { message: 'sync_pull requires an authenticated user' },
    });
    await expect(
      fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' }),
    ).rejects.toThrow('sync_pull requires an authenticated user');
  });

  it('propagates a membership select failure as a typed error', async () => {
    const { client } = fakeClient({
      membership: { data: null, error: { message: 'permission denied' } },
    });
    await expect(
      fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' }),
    ).rejects.toThrow('permission denied');
  });
});

describe('saveDay (issue #1254)', () => {
  beforeEach(() => {
    resetPullCursorsForTests();
  });

  const saveArgs = {
    profileId: PROFILE_ID,
    dateIso: '2026-09-29',
    todayIso: '2026-09-30',
    tz: 'UTC',
    edit: baseEdit,
    view: baseView,
    nowIso: NOW,
  };

  it('pushes one sync_push call carrying the plan arrays', async () => {
    const { client, rpc } = fakeClient({
      rpcResult: { data: { resolved: [], rejected: [], server_now: NOW }, error: null },
    });
    const result = await saveDay(client, saveArgs);
    expect(rpc).toHaveBeenCalledWith(
      'sync_push',
      expect.objectContaining({
        p_profiles: [],
        p_day_entries: [expect.objectContaining({ id: ENTRY_ID, note: 'hello' })],
      }),
    );
    expect(result.rejectedFields).toEqual([]);
    expect(result.ourEntryDeclined).toBe(false);
    expect(result.mergedLoserCount).toBe(0);
    expect(result.serverNow).toBe(NOW);
  });

  it('maps an opaque row rejection back to the field that owns the id', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [],
          rejected: [{ id: ENTRY_ID, rejected: true }],
          server_now: NOW,
        },
        error: null,
      },
    });
    const result = await saveDay(client, saveArgs);
    expect(result.rejectedFields).toContain('entry');
  });

  it('maps an observation rejection to its category (bbt)', async () => {
    const view: LoadedDayView = {
      ...baseView,
      observations: [
        {
          id: '01ARZ3NDEK0000000000000BBT',
          day_entry_id: ENTRY_ID,
          profile_id: PROFILE_ID,
          local_date: '2026-09-29',
          observed_at: null,
          tz: 'UTC',
          category: 'bbt',
          code: null,
          value_num: 36.4,
          value_text: null,
          unit: 'celsius',
          intensity: null,
          excluded: false,
          source: 'manual',
          source_id: null,
          updated_at: '2026-09-29T08:00:00.000Z',
          deleted_at: null,
        },
      ],
    };
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [],
          rejected: [{ id: '01ARZ3NDEK0000000000000BBT', rejected: true }],
          server_now: NOW,
        },
        error: null,
      },
    });
    const result = await saveDay(client, {
      ...saveArgs,
      edit: { ...baseEdit, bbt: 36.6 },
      view,
    });
    expect(result.rejectedFields).toContain('bbt');
  });

  it('recognises the decline handback (our id, server copy) as lost LWW', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [
            {
              id: ENTRY_ID,
              table: 'day_entries',
              deleted_at: null,
              updated_at: '2026-09-29T23:00:00.000Z',
            },
          ],
          rejected: [],
          server_now: NOW,
        },
        error: null,
      },
    });
    const result = await saveDay(client, saveArgs);
    expect(result.ourEntryDeclined).toBe(true);
    expect(result.mergedLoserCount).toBe(0);
  });

  it('counts tombstoned same-date losers as merges, not declines', async () => {
    const { client } = fakeClient({
      rpcResult: {
        data: {
          resolved: [
            { id: '01ARZ3NDEK0000000000000001', table: 'day_entries', deleted_at: NOW },
          ],
          rejected: [],
          server_now: NOW,
        },
        error: null,
      },
    });
    const result = await saveDay(client, saveArgs);
    expect(result.ourEntryDeclined).toBe(false);
    expect(result.mergedLoserCount).toBe(1);
  });

  it('surfaces an RPC failure as a DaySaveError the page renders for retry', async () => {
    const { client } = fakeClient({
      rpcResult: { data: null, error: { message: 'p_day_entries must be a JSON array' } },
    });
    await expect(saveDay(client, saveArgs)).rejects.toThrowError(DaySaveError);
  });

  it('refuses to build a plan for a viewer before any call is made', async () => {
    const { client, rpc } = fakeClient();
    const viewerView: LoadedDayView = {
      ...baseView,
      membership: { ...membership, role: 'viewer' },
    };
    await expect(saveDay(client, { ...saveArgs, view: viewerView })).rejects.toThrowError(
      DayPermissionError,
    );
    expect(rpc).not.toHaveBeenCalledWith('sync_push', expect.anything());
  });
});
