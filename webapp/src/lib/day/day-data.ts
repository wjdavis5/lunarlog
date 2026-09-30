import type { AppSupabaseClient } from '../supabase';
import {
  customTagSchema,
  cycleOverrideSchema,
  dayEntrySchema,
  guardianMembershipSchema,
  observationSchema,
  profileModeSchema,
  profileSchema,
  type CustomTagRow,
  type CycleOverrideRow,
  type DayEntryRow,
  type GuardianMembershipRow,
  type ObservationRow,
  type ProfileModeRow,
  type ProfileRow,
} from '../schemas';
import {
  buildSavePlan,
  type SavePlanField,
  type DayEdit,
  type LoadedDayView,
  type JsonRow,
} from './payloads';

/**
 * The day editor's data module (issue #1254): reads the day through the
 * same masked pull the app uses, writes through the same `sync_push` RPC
 * the phones use — no new server path, no local queue, no browser
 * persistence. A failed save stays in the page (the mutation keeps its
 * error) and the caller retries; nothing is silently dropped.
 *
 * **Reads go through `sync_pull`, not raw selects, for one deliberate
 * reason:** issue #849 masks a private day note to NULL for every
 * non-subject guardian *inside sync_pull* — a raw `day_entries` PostgREST
 * select hands the raw row to any guardian RLS lets through, so the
 * browser would receive text it must not even hold. sync_pull pages every
 * synced table by `server_version` cursors (500 rows per page, no
 * cursors in the response — the client tracks the max it saw). This
 * module walks those pages behind an in-memory per-session cursor store:
 * the first day view walks the household's history once, every later view
 * is an increment. The cursors live in page memory and die with the tab —
 * the same nothing-stored rule as the query cache.
 *
 * This module is the #1252 data-layer slice the day editor needs. When
 * #1252's general data module lands, these functions move behind it; the
 * payload contract they speak is the contract #1252's acceptance pins.
 */

/** Thrown when a call itself fails (auth, network, whole-batch
 * rejection). The page renders this in the retry banner. */
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
  customTags: CustomTagRow[];
}

/**
 * The per-table page size sync_pull applies (`c_page_size` in the SQL). A
 * page this long means more rows may follow; the walk continues until
 * every table returns a short page.
 */
const PULL_PAGE_SIZE = 500;

/** Safety valve for the walk: 1000 full pages per table is far past any
 * real household's history; past it, fail loudly instead of looping. */
const MAX_PULL_ROUNDS = 1000;

export type PullCursorStore = Map<string, number>;

const PULLED_TABLES = [
  'profiles',
  'day_entries',
  'observations',
  'profile_modes',
  'cycle_overrides',
  'profile_tag_registry',
] as const;

/** The per-uid session pull cache: per-table cursors PLUS the accumulated
 * rows. Module memory only — nothing at rest, nothing survives a reload.
 * **Keyed by the signed-in user**: sync_pull masks a private day note for
 * the caller it runs as, so a cache shared across users would hand a later
 * signed-in user (or a re-used tab) the previous user's unmasked rows. The
 * uid comes from the caller's own session. */
interface SessionPullCache {
  cursors: PullCursorStore;
  rows: Record<(typeof PULLED_TABLES)[number], Record<string, unknown>[]>;
}

interface PullAccumulator {
  profiles: ProfileRow[];
  dayEntries: DayEntryRow[];
  observations: ObservationRow[];
  profileModes: ProfileModeRow[];
  cycleOverrides: CycleOverrideRow[];
  customTags: CustomTagRow[];
}

const sessionCaches = new Map<string, SessionPullCache>();

function cacheFor(uid: string): SessionPullCache {
  const existing = sessionCaches.get(uid);
  if (existing !== undefined) return existing;
  const fresh: SessionPullCache = {
    cursors: new Map<string, number>(),
    rows: {
      profiles: [],
      day_entries: [],
      observations: [],
      profile_modes: [],
      cycle_overrides: [],
      profile_tag_registry: [],
    },
  };
  sessionCaches.set(uid, fresh);
  return fresh;
}

/** The in-flight walk per uid, so concurrent callers share one sync_pull
 * loop instead of racing duplicate requests. */
const walksInFlight = new Map<string, Promise<void>>();

/**
 * Brings the caller's session cache current (walking sync_pull until every
 * table returns a short page) and returns the CUMULATIVE rows: the first
 * walk drains the household's history once, every later walk appends only
 * the increment, and every caller sees the whole set.
 */
export async function pullSyncedTables(
  client: AppSupabaseClient,
  uid: string,
): Promise<PullAccumulator> {
  const inFlight = walksInFlight.get(uid);
  if (inFlight !== undefined) {
    await inFlight;
    return cachedAccumulator(cacheFor(uid));
  }
  const walk = walkIntoCache(client, cacheFor(uid));
  walksInFlight.set(uid, walk);
  try {
    await walk;
  } finally {
    walksInFlight.delete(uid);
  }
  return cachedAccumulator(cacheFor(uid));
}

function cachedAccumulator(cache: SessionPullCache): PullAccumulator {
  return {
    profiles: cache.rows.profiles as ProfileRow[],
    dayEntries: cache.rows.day_entries as DayEntryRow[],
    observations: cache.rows.observations as ObservationRow[],
    profileModes: cache.rows.profile_modes as ProfileModeRow[],
    cycleOverrides: cache.rows.cycle_overrides as CycleOverrideRow[],
    customTags: cache.rows.profile_tag_registry as CustomTagRow[],
  };
}

async function walkIntoCache(
  client: AppSupabaseClient,
  cache: SessionPullCache,
): Promise<void> {
  const live = cache.cursors;
  const rows = cache.rows;
  for (let round = 0; round < MAX_PULL_ROUNDS; round++) {
    const pCursors: Record<string, number> = {};
    for (const table of PULLED_TABLES) {
      const value = live.get(table);
      if (value !== undefined) pCursors[table] = value;
    }
    const { data, error } = await client.rpc('sync_pull', { p_cursors: pCursors });
    if (error !== null) {
      throw new DaySaveError(`sync_pull failed: ${error.message}`, error);
    }
    const response = data as unknown as Record<string, Record<string, unknown>[] | undefined>;
    let anyFullPage = false;
    for (const table of PULLED_TABLES) {
      const pulled = response[table] ?? [];
      rows[table].push(...pulled);
      if (pulled.length > 0) {
        // server_version is a monotonic Postgres bigint; the values a real
        // account sees stay far inside Number's exact range.
        const maxVersion = Math.max(...pulled.map((row) => Number(row['server_version'] ?? 0)));
        if (maxVersion > (live.get(table) ?? 0)) {
          live.set(table, maxVersion);
        }
        if (pulled.length >= PULL_PAGE_SIZE) anyFullPage = true;
      }
    }
    if (!anyFullPage) return;
  }
  throw new DaySaveError('sync_pull did not drain within the page budget');
}

/** Test seam: forget every per-uid session cache so a test walks from
 * scratch. */
export function resetPullCursorsForTests(): void {
  sessionCaches.clear();
  walksInFlight.clear();
}

interface FetchDayArgs {
  profileId: string;
  dateIso: string;
}

/** Reads one profile's one day, plus the caller's role. The synced tables
 * come from the masked sync_pull walk; the caller's membership is the one
 * read RLS serves directly (profile_guardians is not a synced table). */
export async function fetchDayView(
  client: AppSupabaseClient,
  args: FetchDayArgs,
): Promise<DayView> {
  const { profileId, dateIso } = args;
  const uid = (await client.auth.getSession()).data.session?.user.id ?? null;
  if (uid === null) {
    throw new DaySaveError('not signed in');
  }

  const [pulled, membershipRes] = await Promise.all([
    pullSyncedTables(client, uid),
    client
      .from('profile_guardians')
      .select('profile_id, role, status, is_subject')
      .eq('profile_id', profileId)
      .eq('user_id', uid)
      .maybeSingle(),
  ]);
  if (membershipRes.error !== null) {
    throw new DaySaveError(
      `profile_guardians select failed: ${membershipRes.error.message}`,
      membershipRes.error,
    );
  }

  const profile = pulled.profiles.find((row) => row.id === profileId);
  if (profile === undefined) {
    throw new DaySaveError('profile not found (or not visible to you)');
  }
  const entry =
    pulled.dayEntries.find(
      (row) =>
        row.profile_id === profileId && row.local_date === dateIso && row.deleted_at === null,
    ) ?? null;
  const observations = pulled.observations.filter(
    (row) =>
      row.profile_id === profileId && row.local_date === dateIso && row.deleted_at === null,
  );
  const mode = pulled.profileModes.find((row) => row.profile_id === profileId) ?? null;
  const cycleOverride =
    pulled.cycleOverrides.find(
      (row) =>
        row.profile_id === profileId &&
        row.cycle_start_date === dateIso &&
        row.deleted_at === null,
    ) ?? null;
  const customTags = pulled.customTags.filter(
    (row) => row.profile_id === profileId && row.hidden_at === null,
  );

  return {
    profile: profileSchema.parse(profile),
    entry: entry === null ? null : (dayEntrySchema.parse(entry) as DayEntryRow),
    observations: observations.map((row) => observationSchema.parse(row) as ObservationRow),
    mode: mode === null ? null : (profileModeSchema.parse(mode) as ProfileModeRow),
    cycleOverride:
      cycleOverride === null
        ? null
        : (cycleOverrideSchema.parse(cycleOverride) as CycleOverrideRow),
    membership:
      membershipRes.data === null
        ? null
        : (guardianMembershipSchema.parse(membershipRes.data) as GuardianMembershipRow),
    customTags: customTags.map((row) => customTagSchema.parse(row) as CustomTagRow),
  };
}

/** The `sync_push` response envelope. */
interface SyncPushResponse {
  resolved: JsonRow[];
  rejected: { id: unknown; rejected: boolean }[];
  server_now: string;
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
 * `sync_push` in a single call (the day-entry lands before its observations,
 * the same order the server processes the arrays), and summarises the
 * server's answer. Opaque per-row rejections map back to the field that owns
 * the rejected row id; the caller shows them inline and offers retry.
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
    const category = row['category'];
    const id = row['id'];
    if (typeof id !== 'string') continue;
    if (category === 'bbt') fieldByRowId.set(id, 'bbt');
    else if (category === 'weight') fieldByRowId.set(id, 'weight');
    else fieldByRowId.set(id, 'flow'); // spotting rides the flow group
  }
  for (const row of plan.profileModes) {
    const id = row['profile_id'];
    if (typeof id === 'string') fieldByRowId.set(id, 'mode');
  }
  for (const row of plan.cycleOverrides) {
    const id = row['id'];
    if (typeof id === 'string') fieldByRowId.set(id, 'cycleOverride');
  }

  let response: SyncPushResponse;
  try {
    // The generated Database types type the rpc args as `Json`; the plan
    // rows are `Record<string, unknown>` by construction — the same shapes
    // the server's per-table key allowlists admit, pinned by the payload
    // tests.
    const { data, error } = await client.rpc('sync_push', {
      p_profiles: [],
      p_day_entries: plan.dayEntries,
      p_observations: plan.observations,
      p_profile_modes: plan.profileModes,
      p_cycle_overrides: plan.cycleOverrides,
    } as never);
    if (error !== null) {
      throw new DaySaveError(error.message, error);
    }
    response = data as unknown as SyncPushResponse;
  } catch (error) {
    if (error instanceof DaySaveError) throw error;
    throw new DaySaveError(error instanceof Error ? error.message : 'sync_push failed', error);
  }

  const rejectedFields: SavePlanField[] = [];
  for (const rejection of response.rejected ?? []) {
    const field =
      typeof rejection?.id === 'string' ? fieldByRowId.get(rejection.id) : undefined;
    if (field !== undefined && !rejectedFields.includes(field)) {
      rejectedFields.push(field);
    }
  }

  const resolved = response.resolved ?? [];
  let ourEntryDeclined = false;
  let mergedLoserCount = 0;
  for (const row of resolved) {
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

  return {
    serverNow: response.server_now,
    rejectedFields,
    ourEntryDeclined,
    mergedLoserCount,
  };
}
