import type { AppSupabaseClient } from '../supabase';
import {
  profileSchema,
  type CycleOverrideRow,
  type DayEntryRow,
  type ObservationRow,
  type ProfileGuardianRow,
  type ProfileModeRow,
  type ProfileTagRegistryRow,
} from '../schemas';
import { getSyncedDataCache, pushSyncBatch, type SyncedData } from '../domain';
import { webAuth } from '../auth';
import { sessionUserId } from '../sharing';
import {
  buildSavePlan,
  type SavePlanField,
  type DayEdit,
  type LoadedDayView,
} from './payloads';

/**
 * The day editor's data module (issue #1254), composed on the #1252 data
 * layer: reads come from the shared synced-data cache — the masked
 * `sync_pull` walk (`src/lib/domain.ts`), the only read path that applies
 * the #849 private-note mask, so a non-subject guardian's browser never
 * even receives note text it must not hold — and writes go through
 * `pushSyncBatch`, the same `sync_push` RPC the phones use, with
 * client-generated ULID ids and client-minted `updated_at`. No new server
 * path, no local queue, no browser persistence. A failed save stays in the
 * page (the mutation keeps its error) and the caller retries; nothing is
 * silently dropped.
 */

/** Thrown when a call itself fails (auth, network, whole-batch
 * rejection), or when the requested day is not visible to the caller. */
export class DaySaveError extends Error {
  constructor(
    message: string,
    readonly cause?: unknown,
  ) {
    super(message);
    this.name = 'DaySaveError';
  }
}

/** Everything a save needs to know about what the server answered. */
export interface SaveDayResult {
  serverNow: string;
  /** Fields the server rejected (opaque rejections: id + true, no reason). */
  rejectedFields: SavePlanField[];
  /** True when the server handed our entry row back — an older LWW write
   * the server declined, i.e. another device saved newer content. */
  ourEntryDeclined: boolean;
  /** How many same-date loser rows the server tombstoned into our entry
   * (the tags union / merge disclosure path). */
  mergedLoserCount: number;
}

/** The day view: everything the editor renders for one profile's one day. */
export interface DayView extends LoadedDayView {
  customTags: ProfileTagRegistryRow[];
}

/**
 * Derives one profile's one day from the synced snapshot — pure, so the
 * derivation is unit-testable without any client and reusable as a React
 * Query `select`. A private note arrives masked (note = null) for every
 * non-subject guardian because masking happened server-side, in
 * `sync_pull`; the client schema just carries the nullable field.
 */
export function dayViewFromSyncedData(
  synced: SyncedData,
  profileId: string,
  dateIso: string,
  uid: string,
): DayView {
  const profile = synced.profiles.find((row) => row.id === profileId);
  if (profile === undefined) {
    throw new DaySaveError('profile not found (or not visible to you)');
  }
  const entry =
    synced.day_entries.find(
      (row) =>
        row.profile_id === profileId && row.local_date === dateIso && row.deleted_at === null,
    ) ?? null;
  const observations = synced.observations.filter(
    (row) =>
      row.profile_id === profileId && row.local_date === dateIso && row.deleted_at === null,
  );
  const mode = synced.profile_modes.find((row) => row.profile_id === profileId) ?? null;
  const cycleOverride =
    synced.cycle_overrides.find(
      (row) =>
        row.profile_id === profileId &&
        row.cycle_start_date === dateIso &&
        row.deleted_at === null,
    ) ?? null;
  const membership =
    synced.profile_guardians.find(
      (row) =>
        row.profile_id === profileId &&
        row.user_id === uid &&
        (row.revoked_at ?? null) === null,
    ) ?? null;
  const customTags = synced.profile_tag_registry.filter(
    (row) => row.profile_id === profileId && row.hidden_at === null,
  );

  return {
    profile: profileSchema.parse(profile),
    entry: (entry ?? null) as DayEntryRow | null,
    observations: observations as ObservationRow[],
    mode: (mode ?? null) as ProfileModeRow | null,
    cycleOverride: (cycleOverride ?? null) as CycleOverrideRow | null,
    membership: (membership ?? null) as ProfileGuardianRow | null,
    customTags: customTags as ProfileTagRegistryRow[],
  };
}

interface FetchDayArgs {
  profileId: string;
  dateIso: string;
}

/** Reads one profile's one day for the signed-in caller: brings the shared
 * synced-data cache current (an incremental `sync_pull` walk) and derives
 * the view. The caller's membership comes from the pulled
 * `profile_guardians` rows — the role the read-only / writable split keys
 * on. */
export async function fetchDayView(
  client: AppSupabaseClient,
  args: FetchDayArgs,
): Promise<DayView> {
  const uid = await sessionUserId(client);
  if (uid === null) {
    throw new DaySaveError('not signed in');
  }
  // The pull is tagged with the account it runs under (issue #1338) — the
  // live id, re-read inside refresh, never the `uid` resolved above (that
  // snapshot is exactly what a mid-pull renewal may invalidate).
  const synced = await getSyncedDataCache().refresh(
    client,
    () => webAuth.getUser()?.id ?? null,
  );
  return dayViewFromSyncedData(synced, args.profileId, args.dateIso, uid);
}

export interface SaveDayArgs {
  profileId: string;
  dateIso: string;
  todayIso: string;
  tz: string;
  edit: DayEdit;
  view: LoadedDayView;
  /** The save instant; defaults to now. Injectable for tests. */
  nowIso?: string;
}

/**
 * Validates and saves one day: builds the payload rows, pushes them through
 * `sync_push` in a single call via the data layer's `pushSyncBatch` (the
 * day-entry lands before its observations — the same order the server
 * processes the arrays), brings the synced-data cache current so the very
 * next view reflects the server's stored state, and summarises the answer.
 * Opaque per-row rejections map back to the field that owns the rejected
 * row id; the caller shows them inline and offers retry.
 */
export async function saveDay(
  client: AppSupabaseClient,
  args: SaveDayArgs,
): Promise<SaveDayResult> {
  const plan = buildSavePlan({
    profileId: args.profileId,
    dateIso: args.dateIso,
    todayIso: args.todayIso,
    tz: args.tz,
    edit: args.edit,
    view: args.view,
    nowIso: args.nowIso ?? new Date().toISOString(),
  });

  const fieldByRowId = new Map<string, SavePlanField>();
  const entryId = plan.dayEntries[0]?.id;
  if (typeof entryId === 'string') fieldByRowId.set(entryId, 'entry');
  // Observation rejections map to the category the row belongs to; the
  // builder emitted them, so the mapping is recoverable by category key.
  for (const row of plan.observations) {
    if (typeof row.id !== 'string') continue;
    if (row.category === 'bbt') fieldByRowId.set(row.id, 'bbt');
    else if (row.category === 'weight') fieldByRowId.set(row.id, 'weight');
    else fieldByRowId.set(row.id, 'flow'); // spotting rides the flow group
  }
  for (const row of plan.profileModes) {
    fieldByRowId.set(row.profile_id, 'mode');
  }
  for (const row of plan.cycleOverrides) {
    fieldByRowId.set(row.id, 'cycleOverride');
  }

  let outcome;
  try {
    outcome = await pushSyncBatch(client, {
      day_entries: plan.dayEntries,
      observations: plan.observations,
      profile_modes: plan.profileModes,
      cycle_overrides: plan.cycleOverrides,
    });
  } catch (error) {
    throw new DaySaveError(error instanceof Error ? error.message : 'sync_push failed', error);
  }

  const rejectedFields: SavePlanField[] = [];
  for (const rejection of outcome.rejected) {
    const field = rejection.id !== null ? fieldByRowId.get(rejection.id) : undefined;
    if (field !== undefined && !rejectedFields.includes(field)) {
      rejectedFields.push(field);
    }
  }

  let ourEntryDeclined = false;
  let mergedLoserCount = 0;
  for (const row of outcome.resolved) {
    if (row['table'] !== 'day_entries') continue;
    if (row['id'] === entryId) {
      // The server handed our own row back: its stored copy is newer or
      // equal-and-live — our write was declined, nothing was saved.
      ourEntryDeclined = true;
    } else if (row['deleted_at'] !== null && row['deleted_at'] !== undefined) {
      // A different day-entry row came back tombstoned: the same-date
      // resolver merged it into ours (tags unioned, flow/note LWW).
      mergedLoserCount++;
    }
  }

  // A successful push changed server state; pull the increment now so the
  // next view — this tab or a remount — reads the stored truth (merge
  // results included) without waiting for the query invalidation.
  if (rejectedFields.length === 0 && !ourEntryDeclined) {
    try {
      // Tagged with the account it runs under, same as every pull (issue
      // #1338).
      await getSyncedDataCache().refresh(client, () => webAuth.getUser()?.id ?? null);
    } catch {
      // The invalidation retry covers a failed refresh; never mask a
      // successful save behind it.
    }
  }

  return {
    serverNow: outcome.serverNow,
    rejectedFields,
    ourEntryDeclined,
    mergedLoserCount,
  };
}
