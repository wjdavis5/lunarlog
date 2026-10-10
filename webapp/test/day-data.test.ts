import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  DaySaveError,
  dayViewFromSyncedData,
  fetchDayView,
  saveDay,
} from '../src/lib/day/day-data';
import { DayPermissionError, type DayEdit, type LoadedDayView } from '../src/lib/day/payloads';
import { getSyncedDataCache, resetClockOffset, type SyncedData } from '../src/lib/domain';
import type { AppSupabaseClient } from '../src/lib/supabase';
import type { DayEntryRow, ProfileGuardianRow, ProfileRow } from '../src/lib/schemas';

/**
 * The day editor's data module against a fake Supabase client (issue
 * #1254). Reads compose the #1252 data layer's shared synced-data cache —
 * the walk itself is pinned by that layer's own suite and by the live
 * integration test (test/integration/, CI's db-tests job) — so what only
 * these unit tests can pin is the derivation (which rows make up one
 * profile's one day, membership included) and the save mapping (which
 * field a rejected row id lights up, which server answer is a decline
 * rather than a failure, and the post-save cache refresh).
 */

const PROFILE_ID = '01M2FWKNG0ZMH2ANCH7R2CM2XZ';
const ENTRY_ID = '01M2FWKNG0ZMH2ANCH7R2CM2Y2';
const NOW = '2026-09-30T08:00:00.000Z';
const UID = '00000000-0000-0000-0000-00000000user';

const baseProfile: ProfileRow = {
  id: PROFILE_ID,
  user_id: UID,
  display_name: 'Maya',
  is_minor: false,
  mode: 'standard',
  relationship: 'self',
  birth_year: 1990,
  sort_order: 0,
  archived_at: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  deleted_at: null,
  server_version: 1,
  bbt_unit: 'celsius',
  weight_unit: 'kg',
  tracking_preferences: null,
};

const membership: ProfileGuardianRow = {
  id: '00000000-0000-4000-8000-0000000000ea',
  profile_id: PROFILE_ID,
  user_id: UID,
  role: 'primary_guardian',
  status: 'accepted',
  is_subject: true,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-01-01T00:00:00Z',
  server_version: 2,
};

const storedEntry: DayEntryRow = {
  id: ENTRY_ID,
  user_id: UID,
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
  created_at: '2026-09-29T08:00:00.000Z',
  updated_at: '2026-09-29T08:00:00.000Z',
  deleted_at: null,
  server_version: 3,
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

function syncedData(rows: Partial<SyncedData>): SyncedData {
  return {
    profiles: rows.profiles ?? [baseProfile],
    day_entries: rows.day_entries ?? [],
    observations: rows.observations ?? [],
    profile_modes: rows.profile_modes ?? [],
    cycle_overrides: rows.cycle_overrides ?? [],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians: rows.profile_guardians ?? [],
  };
}

describe('dayViewFromSyncedData (issue #1254)', () => {
  it('derives the day: live entry, the day observations, mode, override, membership', () => {
    const otherDay: DayEntryRow = {
      ...storedEntry,
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
      local_date: '2026-09-28',
    };
    const view = dayViewFromSyncedData(
      syncedData({
        day_entries: [otherDay, storedEntry],
        profile_guardians: [membership],
      }),
      PROFILE_ID,
      '2026-09-29',
      UID,
    );
    expect(view.profile.display_name).toBe('Maya');
    expect(view.entry?.id).toBe(ENTRY_ID);
    expect(view.observations).toEqual([]);
    expect(view.mode).toBeNull();
    expect(view.cycleOverride).toBeNull();
    expect(view.membership?.role).toBe('primary_guardian');
    expect(view.customTags).toEqual([]);
  });

  it('skips tombstoned rows when picking the live entry and override', () => {
    const view = dayViewFromSyncedData(
      syncedData({
        day_entries: [{ ...storedEntry, deleted_at: NOW }],
        cycle_overrides: [
          {
            id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
            profile_id: PROFILE_ID,
            cycle_start_date: '2026-09-29',
            excluded_from_average: true,
            manual_start: false,
            updated_at: '2026-09-29T08:00:00.000Z',
            deleted_at: NOW,
            server_version: 4,
          },
        ],
      }),
      PROFILE_ID,
      '2026-09-29',
      UID,
    );
    expect(view.entry).toBeNull();
    expect(view.cycleOverride).toBeNull();
  });

  it('matches the membership to the caller (role and uid), not to any guardian row', () => {
    const otherGuardian: ProfileGuardianRow = {
      ...membership,
      user_id: '00000000-0000-4000-8000-0000000000eb',
      role: 'viewer',
    };
    const view = dayViewFromSyncedData(
      syncedData({ profile_guardians: [otherGuardian, membership] }),
      PROFILE_ID,
      '2026-09-29',
      UID,
    );
    expect(view.membership?.role).toBe('primary_guardian');
  });

  it('throws the typed error when the profile is not in the snapshot', () => {
    expect(() =>
      dayViewFromSyncedData(syncedData({ profiles: [] }), PROFILE_ID, '2026-09-29', UID),
    ).toThrowError(/not visible/);
  });
});

/** A fake client: sync_pull answers with `page` and sync_push with
 * `rpcResult` — enough for the shared cache and the save path. */
function fakeClient(options?: {
  page?: Partial<SyncedData>;
  rpcResult?: { data: unknown; error: { message: string } | null };
  pullError?: { message: string } | null;
}) {
  // Record cloned args: sync_pull's cursors object is mutated by the
  // pull loop after the call, and the spy stores the reference.
  const rpcCalls: [string, unknown][] = [];
  const rpc = vi.fn().mockImplementation((name: string, args: unknown) => {
    rpcCalls.push([name, structuredClone(args)]);
    if (name === 'sync_pull') {
      return Promise.resolve({
        data: options?.pullError
          ? null
          : {
              profiles: options?.page?.profiles ?? [],
              day_entries: options?.page?.day_entries ?? [],
              observations: options?.page?.observations ?? [],
              profile_modes: options?.page?.profile_modes ?? [],
              cycle_overrides: options?.page?.cycle_overrides ?? [],
              care_notes: [],
              visit_prep_items: [],
              profile_tag_registry: [],
              profile_guardians: options?.page?.profile_guardians ?? [],
              day_entry_history: [],
            },
        error: options?.pullError ?? null,
      });
    }
    return Promise.resolve(options?.rpcResult ?? { data: {}, error: null });
  });
  return {
    client: {
      rpc,
      auth: { getSession: async () => ({ data: { session: { user: { id: UID } } } }) },
    } as unknown as AppSupabaseClient,
    rpc,
    rpcCalls,
  };
}

describe('fetchDayView (issue #1254, on the shared synced-data cache)', () => {
  beforeEach(() => {
    getSyncedDataCache().reset();
  });

  it('pulls through the cache and derives the view', async () => {
    const { client, rpcCalls } = fakeClient({
      page: {
        profiles: [baseProfile],
        day_entries: [storedEntry],
        profile_guardians: [membership],
      },
    });
    const view = await fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' });
    expect(view.profile.display_name).toBe('Maya');
    expect(view.entry?.id).toBe(ENTRY_ID);
    expect(view.membership?.role).toBe('primary_guardian');
    // The first pull starts from empty cursors (cloned at call time — the
    // pull loop mutates its cursors object after the call returns). The
    // commit-safe watermark probe (issue #1282) precedes it; filtered out
    // here so the assertion keeps pinning the sync_pull call itself.
    expect(rpcCalls.filter(([name]) => name === 'sync_pull')).toEqual([
      ['sync_pull', { p_cursors: {} }],
    ]);
  });

  it('propagates a sync_pull failure as a typed error', async () => {
    const { client } = fakeClient({
      pullError: { message: 'sync_pull requires an authenticated user' },
    });
    await expect(
      fetchDayView(client, { profileId: PROFILE_ID, dateIso: '2026-09-29' }),
    ).rejects.toThrow('sync_pull requires an authenticated user');
  });
});

describe('saveDay (issue #1254)', () => {
  beforeEach(() => {
    getSyncedDataCache().reset();
  });

  const view: LoadedDayView = {
    profile: baseProfile,
    entry: storedEntry,
    observations: [],
    membership,
    mode: null,
    cycleOverride: null,
  };

  const saveArgs = {
    profileId: PROFILE_ID,
    dateIso: '2026-09-29',
    todayIso: '2026-09-30',
    tz: 'UTC',
    edit: baseEdit,
    view,
    nowIso: NOW,
  };

  it('pushes one sync_push batch carrying the plan arrays', async () => {
    const { client, rpc } = fakeClient({
      rpcResult: {
        data: { resolved: [], rejected: [], server_now: NOW },
        error: null,
      },
    });
    const result = await saveDay(client, saveArgs);
    expect(rpc).toHaveBeenCalledWith(
      'sync_push',
      expect.objectContaining({
        p_day_entries: [expect.objectContaining({ id: ENTRY_ID, note: 'hello' })],
      }),
    );
    expect(result.rejectedFields).toEqual([]);
    expect(result.ourEntryDeclined).toBe(false);
    expect(result.mergedLoserCount).toBe(0);
    expect(result.serverNow).toBe(NOW);
    // A clean save is the only kind that refreshes the cache: the pull
    // after the push is exactly what the rejected/declined saves below
    // must skip (issue #1290) — with its watermark probe (issue #1282)
    // ahead of it, since the probe lives inside the pull.
    expect(rpc.mock.calls.map(([name]) => name)).toEqual([
      'sync_push',
      'sync_watermark',
      'sync_pull',
    ]);
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

  it('resolves a partly-rejected push and skips the post-save cache refresh', async () => {
    const { client, rpc } = fakeClient({
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
    // The push itself succeeded, so the outcome resolves — the page's
    // onSuccess runs and must read it as not-accepted rather than saved.
    // Nothing was accepted, so nothing pulls: the server kept its stored
    // state (issue #1290).
    expect(result.rejectedFields).toEqual(['entry']);
    expect(result.ourEntryDeclined).toBe(false);
    expect(rpc.mock.calls.map(([name]) => name)).toEqual(['sync_push']);
  });

  it('maps an observation rejection to its category (bbt)', async () => {
    const measurement = {
      id: '01ARZ3NDEK0000000000000BBT',
      day_entry_id: ENTRY_ID,
      profile_id: PROFILE_ID,
      local_date: '2026-09-29',
      tz: 'UTC',
      observed_at: null,
      category: 'bbt',
      code: null,
      value_num: 36.4,
      value_text: null,
      unit: 'celsius',
      intensity: null,
      excluded: false,
      source: 'manual',
      source_id: null,
      created_at: '2026-09-29T08:00:00.000Z',
      updated_at: '2026-09-29T08:00:00.000Z',
      deleted_at: null,
      server_version: 5,
    };
    const dayView: LoadedDayView = { ...view, observations: [measurement] };
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
      view: dayView,
    });
    expect(result.rejectedFields).toContain('bbt');
  });

  it('recognises the decline handback (our id, server copy) as lost LWW', async () => {
    const { client, rpc } = fakeClient({
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
    // The decline resolves too (issue #1290) and nothing was accepted, so
    // the cache is not refreshed.
    expect(rpc.mock.calls.map(([name]) => name)).toEqual(['sync_push']);
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
      ...view,
      membership: { ...membership, role: 'viewer' },
    };
    await expect(saveDay(client, { ...saveArgs, view: viewerView })).rejects.toThrowError(
      DayPermissionError,
    );
    expect(rpc).not.toHaveBeenCalledWith('sync_push', expect.anything());
  });
});

describe('saveDay stamps the corrected clock (issue #1283)', () => {
  beforeEach(() => {
    getSyncedDataCache().reset();
    resetClockOffset();
  });

  // saveArgs/view live inside the #1254 describe above; this describe
  // builds its own from the same file-scope fixtures.
  const correctedView: LoadedDayView = {
    profile: baseProfile,
    entry: storedEntry,
    observations: [],
    membership,
    mode: null,
    cycleOverride: null,
  };
  const correctedArgs = {
    profileId: PROFILE_ID,
    dateIso: '2026-09-29',
    todayIso: '2026-09-30',
    tz: 'UTC',
    edit: baseEdit,
    view: correctedView,
    nowIso: NOW,
  };

  it('after a skew-teaching push, a save without an explicit nowIso stamps server time', async () => {
    const deviceNow = Date.now();
    // The phones write at true server time; this browser runs ten minutes
    // slow, so a raw-clock stamp would read as older and lose LWW. The
    // first save (explicit nowIso, raw stamp) is what teaches the offset
    // from the response's server_now.
    const serverNow = new Date(deviceNow + 10 * 60_000).toISOString();
    const rpcResult = {
      data: { resolved: [], rejected: [], server_now: serverNow },
      error: null,
    };
    const seeding = fakeClient({ rpcResult });
    await saveDay(seeding.client, correctedArgs);

    // The second save omits nowIso: the default instant now comes from the
    // learned offset — every plan row stamps corrected.
    const corrected = fakeClient({ rpcResult });
    const { nowIso: _explicit, ...defaultedArgs } = correctedArgs;
    await saveDay(corrected.client, defaultedArgs);
    const pushCall = corrected.rpcCalls.find(([name]) => name === 'sync_push');
    expect(pushCall).toBeDefined();
    const payload = pushCall?.[1] as { p_day_entries: { updated_at: string }[] };
    const stamp = Date.parse(payload.p_day_entries[0]?.updated_at ?? '');
    // Wins LWW against a phone's true-now write, and reads as ≈ server
    // time — without the fix this stamp would be the raw, ten-minutes-slow
    // browser clock and land ~10 minutes in the server's past.
    expect(stamp).toBeGreaterThan(deviceNow + 4 * 60_000);
    expect(Math.abs(stamp - (deviceNow + 10 * 60_000))).toBeLessThan(30_000);
  });

  it('before any push has taught the offset, the default instant stays the raw clock', async () => {
    const { client, rpcCalls } = fakeClient({
      rpcResult: { data: { resolved: [], rejected: [], server_now: NOW }, error: null },
    });
    const { nowIso: _explicit, ...defaultedArgs } = correctedArgs;
    await saveDay(client, defaultedArgs);
    const pushCall = rpcCalls.find(([name]) => name === 'sync_push');
    const payload = pushCall?.[1] as { p_day_entries: { updated_at: string }[] };
    // Uncorrected (the phones' zero-offset start): ≈ the raw device clock.
    const stamp = Date.parse(payload.p_day_entries[0]?.updated_at ?? '');
    expect(Math.abs(stamp - Date.now())).toBeLessThan(30_000);
  });
});
