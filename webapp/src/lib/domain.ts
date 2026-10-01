import {
  careNoteListSchema,
  cycleOverrideListSchema,
  dayEntryListSchema,
  guardianNoteListSchema,
  observationListSchema,
  profileGuardianListSchema,
  profileListSchema,
  profileModeListSchema,
  profileTagRegistryListSchema,
  settingListSchema,
  syncPushResultSchema,
  syncSignalSchema,
  visitPrepItemListSchema,
  type CareNoteRow,
  type CycleOverrideRow,
  type DayEntryRow,
  type GuardianNoteRow,
  type ObservationRow,
  type ProfileGuardianRow,
  type ProfileRow,
  type ProfileModeRow,
  type ProfileTagRegistryRow,
  type SettingRow,
  type SyncPushResult,
  type VisitPrepItemRow,
} from './schemas';
import { type AppSupabaseClient } from './supabase';
import { newUlid } from './ulid';

/**
 * The web data layer (issue #1252): one module every web screen uses to
 * read and write account data directly against Supabase, with nothing
 * persisted in the browser.
 *
 * **Reads go through `sync_pull`.** One approach, chosen deliberately:
 *
 * - `sync_pull` is the app's authoritative read path — the same
 *   guardian-tenant-scoped, `server_version`-cursor RPC the phones parse
 *   (its per-table page cap is 500, well under PostgREST's 1,000-row
 *   response cap, and this module pages to exhaustion, so a profile's full
 *   cycle history loads no matter its size). The cursors a pull hands back
 *   are clamped to the server's commit-safe `sync_watermark()` — or, when
 *   that RPC is unavailable, to `CURSOR_LOOKBACK` below each table's
 *   pulled maximum — so an out-of-commit-order row can never be skipped
 *   past (issue #1282, the web mirror of issue #521's engine fix).
 *   Membership changes (invite accept, transfer claim, leave, revoke)
 *   reshapes what the RPC returns without bumping `server_version`s, so
 *   `SyncedDataCache.repullAll` re-pulls from zero into a fresh,
 *   membership-filtered snapshot after them.
 * - Private-note masking lives *only* on the RPC paths: a non-subject
 *   guardian receives a masked `day_entries.note = null` from `sync_pull`
 *   (mask_day_entry_note, 20260921130000). A raw `select` on
 *   `day_entries` passes the guardian RLS policy but returns an unmasked
 *   private note — so the RLS-scoped select is not a safe substitute for
 *   that table.
 * - Two synced tables are not in `sync_pull`'s response and keep the
 *   app's own direct RLS-scoped select, paged past PostgREST's cap:
 *   `guardian_notes` (the phones pull it the same way) and `settings`
 *   (per-user rows; `settings_select_own` RLS).
 *
 * **Writes go exactly where the app's writes go:** `sync_push` for every
 * synced row — the sole write path since 20260915160000 revoked
 * `day_entries`' direct INSERT/UPDATE grants (a column-scoped
 * `note_private` grant exists but nothing in the app uses it directly).
 * The client generates each row's ULID id and `updated_at`, so the
 * server's last-writer-wins and same-date rules behave as they do for
 * phones; per-row rejections (date bounds, key allowlist, viewer role)
 * come back in `rejected` and are surfaced mapped to the offending payload
 * row. Guardian-membership changes ride the sharing RPCs
 * (`create_guardian_invitation`, `accept_guardian_invitation`,
 * `update_guardian_role`, `revoke_guardian`, …) — this module adds no
 * server path, and no migration ships with it. `updated_at` is stamped
 * from the device clock corrected by the offset learned from each push's
 * `server_now` (issue #1283) — the web mirror of the phones' issue-#566
 * clock discipline, so a browser clock more than five minutes fast stops
 * tripping `sync_push`'s future check and a slow one stops losing
 * last-writer-wins.
 *
 * **Live updates:** `public.sync_signals` is the only table the Realtime
 * publication carries (20260905100000) — a content-free
 * (profile_id, updated_at) wake row per profile. Subscribe for the open
 * profiles and refetch on a signal; the signal payload is never trusted
 * as data.
 *
 * **Cache:** everything here lives in page memory — cursors, the merged
 * row snapshot, and the TanStack Query cache (no persister, issue #1249).
 * `resetWebDataForSignOut` clears all three; the auth layer calls it at
 * every identity boundary (issue #1281) — on sign-out, on session
 * adoption, and whenever the signed-in user id changes.
 */

/** `sync_pull`'s per-table page cap (c_page_size in the RPC body). */
export const SYNC_PULL_PAGE_SIZE = 500;

/**
 * PostgREST's default per-response row cap — the limit the direct-select
 * reads page past with `.range()`.
 */
export const POSTGREST_PAGE_SIZE = 1_000;

/** Safety cap on pull rounds; unreachable in practice, a guard against a
 * paging bug spinning forever. */
const MAX_PULL_ROUNDS = 1_000;

/**
 * Issue #1282: how far below a table's highest pulled `server_version` the
 * cursor may advance when the server's commit-safe watermark is unavailable
 * — the web mirror of the engine's `kCursorLookback` (issue #521,
 * `lib/data/sync/supabase_sync_engine.dart`). `server_version` comes from a
 * sequence assigned *before* commit, so a lower-versioned row can become
 * visible after a higher one has already been pulled; a strict
 * `server_version > cursor` pull that pinned the cursor to the page maximum
 * would never re-fetch it. Keeping the cursor this many versions short of
 * the maximum re-pulls a small band of already-seen rows on the next pull —
 * mergeSyncedData is idempotent (last-writer-wins by updated_at), so the
 * duplicate work costs nothing but correctness.
 */
export const CURSOR_LOOKBACK = 50;

// ---------------------------------------------------------------------------
// The learned server-clock offset (issue #1283)
// ---------------------------------------------------------------------------

/**
 * The weight a fresh clock-offset sample carries against the previously
 * smoothed value — the web mirror of the phones' `kClockOffsetSmoothingAlpha`
 * (`lib/data/sync/supabase_sync_engine.dart`, issue #566): a simple
 * exponential moving average, `next = previous + alpha * (sample - previous)`.
 * `server_now - device_now` is measured once per push batch, and a single
 * sample can be noisy — a slow or congested request inflates the apparent
 * one-way trip, and `server_now` is the transaction-start instant of a batch
 * that may still be writing rows when it stamps that instant. `0.2` reacts
 * within a handful of pushes (a real clock skew shows up quickly) while
 * damping any one sample's noise rather than snapping every stamp to it.
 * `1.0` would disable smoothing entirely (every sample replaces the previous
 * one outright).
 */
export const CLOCK_OFFSET_SMOOTHING_ALPHA = 0.2;

/**
 * The smoothed `server_now - device_now` offset learned from push responses,
 * in milliseconds, or `null` before the first one lands. Purely in-memory
 * page state — like everything else in this module, nothing is persisted
 * (issue #1249) — so a fresh page starts uncorrected and learns from its
 * first push, exactly as a phone restart does (the engine re-seeds from its
 * first sample too; its persisted value is a Flutter-side affordance the
 * no-storage web client does not have).
 */
let smoothedClockOffsetMs: number | null = null;

/** The offset learned so far (`null` before the first push response). */
export function learnedClockOffsetMs(): number | null {
  return smoothedClockOffsetMs;
}

/**
 * Folds one push response's clock sample — `server_now` (the RPC's
 * transaction-start instant) minus the device clock reading taken
 * immediately before the call — into the smoothed offset and returns the
 * new value in milliseconds. The very first sample is taken as-is (there is
 * nothing to smooth against yet), the same rule as the engine's
 * `_smoothOffset`. An unparseable `server_now` leaves the state untouched:
 * a boundary that cannot be read must never poison the offset with `NaN`.
 */
export function learnClockOffset(serverNow: string, sentAtMs: number): number {
  const sampleMs = Date.parse(serverNow) - sentAtMs;
  if (Number.isNaN(sampleMs)) {
    return smoothedClockOffsetMs ?? 0;
  }
  const previous = smoothedClockOffsetMs;
  smoothedClockOffsetMs =
    previous === null
      ? sampleMs
      : Math.round(previous + CLOCK_OFFSET_SMOOTHING_ALPHA * (sampleMs - previous));
  return smoothedClockOffsetMs;
}

/** Forgets the learned offset (tests; the offset deliberately survives the
 * identity resets — see `resetWebDataForSignOut`). */
export function resetClockOffset(): void {
  smoothedClockOffsetMs = null;
}

/**
 * The device clock corrected by the learned offset — the instant a local
 * write should carry. Before the first push response this is simply the raw
 * device clock (the phones' posture too: `StorageClock` starts at a zero
 * offset and the first batch is stamped uncorrected). This is the default
 * clock of `nowSyncStamp` and every payload builder below, so every web
 * write lands on server time once the offset has been learned: a browser
 * clock more than five minutes fast stops tripping `sync_push`'s
 * `updated_at > now() + interval '5 minutes'` per-row rejection
 * (20260921130000), and a slow browser stops losing last-writer-wins
 * against the phones. An explicitly injected clock bypasses the correction
 * — that is the tests' determinism seam.
 */
export function serverAdjustedNow(clock: () => Date = () => new Date()): Date {
  return new Date(clock().getTime() + (smoothedClockOffsetMs ?? 0));
}

// ---------------------------------------------------------------------------
// Pull (sync_pull, cursor-paginated)
// ---------------------------------------------------------------------------

/**
 * The `sync_pull` tables this client tracks cursors for. `day_entry_merge_events`
 * and `day_entry_history` ride the same RPC response but are not part of
 * the web data layer's typed surface yet (the issue scopes reads to the
 * content tables, guardians, and notes); their response keys are ignored.
 */
export type SyncCursorTable =
  | 'profiles'
  | 'day_entries'
  | 'observations'
  | 'profile_modes'
  | 'cycle_overrides'
  | 'care_notes'
  | 'visit_prep_items'
  | 'profile_tag_registry'
  | 'profile_guardians';

export type SyncPullCursors = Partial<Record<SyncCursorTable, number>>;

export function emptyCursors(): SyncPullCursors {
  return {};
}

/** The rows one full (or incremental) pull leaves behind, per table. */
export interface SyncedData {
  profiles: ProfileRow[];
  day_entries: DayEntryRow[];
  observations: ObservationRow[];
  profile_modes: ProfileModeRow[];
  cycle_overrides: CycleOverrideRow[];
  care_notes: CareNoteRow[];
  visit_prep_items: VisitPrepItemRow[];
  profile_tag_registry: ProfileTagRegistryRow[];
  profile_guardians: ProfileGuardianRow[];
  guardian_notes: GuardianNoteRow[];
}

export function emptySyncedData(): SyncedData {
  return {
    profiles: [],
    day_entries: [],
    observations: [],
    profile_modes: [],
    cycle_overrides: [],
    care_notes: [],
    visit_prep_items: [],
    profile_tag_registry: [],
    profile_guardians: [],
    guardian_notes: [],
  };
}

/** One `sync_pull` round trip, validated at the boundary. */
interface PullPage {
  profiles: ProfileRow[];
  day_entries: DayEntryRow[];
  observations: ObservationRow[];
  profile_modes: ProfileModeRow[];
  cycle_overrides: CycleOverrideRow[];
  care_notes: CareNoteRow[];
  visit_prep_items: VisitPrepItemRow[];
  profile_tag_registry: ProfileTagRegistryRow[];
  profile_guardians: ProfileGuardianRow[];
}

async function pullOnce(
  client: AppSupabaseClient,
  cursors: SyncPullCursors,
): Promise<PullPage> {
  const { data, error } = await client.rpc('sync_pull', {
    p_cursors: cursors as Record<string, number>,
  });
  if (error !== null) {
    throw new Error(`sync_pull failed: ${error.message}`);
  }
  const parsed = data as Record<string, unknown>;
  return {
    profiles: profileListSchema.parse(parsed.profiles ?? []),
    day_entries: dayEntryListSchema.parse(parsed.day_entries ?? []),
    observations: observationListSchema.parse(parsed.observations ?? []),
    profile_modes: profileModeListSchema.parse(parsed.profile_modes ?? []),
    cycle_overrides: cycleOverrideListSchema.parse(parsed.cycle_overrides ?? []),
    care_notes: careNoteListSchema.parse(parsed.care_notes ?? []),
    visit_prep_items: visitPrepItemListSchema.parse(parsed.visit_prep_items ?? []),
    profile_tag_registry: profileTagRegistryListSchema.parse(parsed.profile_tag_registry ?? []),
    profile_guardians: profileGuardianListSchema.parse(parsed.profile_guardians ?? []),
  };
}

/**
 * The server's commit-safe pull-cursor ceiling (`public.sync_watermark()`,
 * 20260913015000): `min(min_version) - 1` over every transaction still
 * holding an uncommitted `server_version`, so advancing a cursor to it can
 * never strand a later-committing, lower-versioned row. `null` — the RPC is
 * missing (a server predating the migration) or the call failed for any
 * reason — degrades the caller to the [CURSOR_LOOKBACK] fallback, exactly
 * like the engine's `SupabaseSyncTransport.fetchWatermark`: the watermark is
 * an optimization the pull cursor can always do without, never a
 * correctness requirement, so a hiccup fetching it must never fail the
 * pull. PostgREST renders a `bigint` as a JSON number in practice but is
 * not guaranteed to (precision past 2^53), so a quoted numeric string is
 * accepted too.
 */
async function fetchWatermark(client: AppSupabaseClient): Promise<number | null> {
  try {
    const { data, error } = await client.rpc('sync_watermark');
    if (error !== null) {
      return null;
    }
    if (typeof data === 'number' && Number.isFinite(data)) {
      return data;
    }
    if (typeof data === 'string') {
      const parsed = Number(data);
      return Number.isFinite(parsed) ? parsed : null;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * The cursors one pull may safely persist: each table's raw pull maximum
 * clamped to at most the commit-safe `watermark` when one was available, or
 * to [CURSOR_LOOKBACK] below the raw maximum when it was not — and never
 * below the cursors the pull started from (a stale or lagging watermark
 * must never move a cursor backward, only fail to advance it as far as the
 * page allows; the engine's `_clampedCursor` carries the same floor).
 *
 * Issue #1282's race, restated: `nextval()` order is not commit order, so a
 * row can become visible *after* a higher version has been pulled; paging
 * runs on the raw maxima (so one pull never re-reads its own band and the
 * exhaustion check stays exact), and the clamp lands on the cursors this
 * pull hands back — the only ones a caller persists.
 */
function clampedPullCursors(
  raw: SyncPullCursors,
  start: SyncPullCursors,
  watermark: number | null,
): SyncPullCursors {
  const clamped: SyncPullCursors = {};
  for (const table of Object.keys(raw) as SyncCursorTable[]) {
    const rawValue = raw[table];
    if (rawValue === undefined) {
      continue;
    }
    const target = watermark ?? rawValue - CURSOR_LOOKBACK;
    clamped[table] = Math.max(start[table] ?? 0, Math.min(target, rawValue));
  }
  return clamped;
}

/**
 * Pulls every synced table forward from `cursors` (all the way from zero
 * for a first load — a profile's full cycle history arrives, not just the
 * recent window), paging until no table returns a full page, and returns
 * the merged rows plus the advanced cursors.
 *
 * The returned cursors are clamped (issue #1282): at most the server's
 * commit-safe `sync_watermark()` when that RPC answers, otherwise
 * [CURSOR_LOOKBACK] below each table's raw maximum — either way never below
 * the cursors the pull started from. See [clampedPullCursors].
 *
 * `maxRounds` overrides the safety cap for the never-exhausts guard's own
 * test: driving the production 1,000-round budget through a real 500-row
 * page of parsed rows is pure worst-case CPU (seconds of it, past the
 * runner's test timeout under CI load — issue #1348) and asserts the same
 * property on a handful of rounds. Callers omit it; the default stays
 * `MAX_PULL_ROUNDS`.
 */
export async function pullSyncedData(
  client: AppSupabaseClient,
  opts: { cursors?: SyncPullCursors; maxRounds?: number } = {},
): Promise<{ data: SyncedData; cursors: SyncPullCursors }> {
  const maxRounds = opts.maxRounds ?? MAX_PULL_ROUNDS;
  const start: SyncPullCursors = { ...emptyCursors(), ...opts.cursors };
  const cursors: SyncPullCursors = { ...start };
  const merged = emptySyncedData();
  const watermark = await fetchWatermark(client);

  for (let round = 0; round < maxRounds; round += 1) {
    const page = await pullOnce(client, cursors);
    let anyFull = false;
    const append = <K extends SyncCursorTable>(
      table: K,
      rows: { server_version: number }[],
    ): void => {
      merged[table] = [...(merged[table] as unknown[]), ...rows] as SyncedData[K];
      if (rows.length > 0) {
        const maxVersion = Math.max(...rows.map((row) => row.server_version));
        cursors[table] = Math.max(cursors[table] ?? 0, maxVersion);
      }
      if (rows.length >= SYNC_PULL_PAGE_SIZE) {
        anyFull = true;
      }
    };
    append('profiles', page.profiles);
    append('day_entries', page.day_entries);
    append('observations', page.observations);
    append('profile_modes', page.profile_modes);
    append('cycle_overrides', page.cycle_overrides);
    append('care_notes', page.care_notes);
    append('visit_prep_items', page.visit_prep_items);
    append('profile_tag_registry', page.profile_tag_registry);
    append('profile_guardians', page.profile_guardians);

    if (!anyFull) {
      return { data: merged, cursors: clampedPullCursors(cursors, start, watermark) };
    }
  }
  throw new Error(`sync_pull did not exhaust within ${maxRounds} rounds`);
}

// ---------------------------------------------------------------------------
// Push (sync_push — the sole write path for synced rows)
// ---------------------------------------------------------------------------

/**
 * Outgoing payload shapes. The keys of each are exactly the columns
 * `sync_push`'s derived allowlist admits for the table (every column minus
 * that table's server-stamped ones — created_at on day_entries, the
 * checked_* pair on visit_prep_items, the created_* pair on
 * profile_tag_registry); unknown keys are rejected server-side per row.
 * Ids are client-generated ULIDs; `updated_at` is client-generated ISO
 * UTC. An absent optional key is a preserve instruction (the server's `?`
 * containment guards never let a partial row clobber a stored value).
 */
export interface ProfilePayload {
  id: string;
  updated_at: string;
  created_at?: string;
  display_name?: string;
  is_minor?: boolean;
  sort_order?: number;
  archived_at?: string | null;
  deleted_at?: string | null;
  birth_year?: number | null;
  relationship?: string | null;
  mode?: string;
  irregular_framing?: boolean | null;
  last_period_start?: string | null;
  typical_cycle_length_days?: number | null;
  typical_period_length_days?: number | null;
  bbt_unit?: string;
  weight_unit?: string;
  tracking_preferences?: Record<string, unknown> | null;
}

export interface DayEntryPayload {
  id: string;
  profile_id: string;
  local_date: string;
  updated_at: string;
  tz?: string;
  flow?: string;
  tags?: string[];
  note?: string | null;
  pms?: boolean;
  note_private?: boolean;
  source?: string;
  source_id?: string | null;
  import_id?: string | null;
  deleted_at?: string | null;
}

export interface ObservationPayload {
  id: string;
  day_entry_id: string;
  profile_id: string;
  local_date: string;
  updated_at: string;
  tz?: string;
  observed_at?: string | null;
  category?: string | null;
  code?: string | null;
  value_num?: number | null;
  value_text?: string | null;
  unit?: string | null;
  intensity?: number | null;
  excluded?: boolean;
  source?: string;
  source_id?: string | null;
  deleted_at?: string | null;
}

export interface ProfileModePayload {
  profile_id: string;
  updated_at: string;
  mode: string;
  mode_started_on?: string | null;
  estimated_due_date?: string | null;
  postpartum_birth_date?: string | null;
  birth_control_method?: string | null;
  birth_control_started_on?: string | null;
  birth_control_stopped_on?: string | null;
  health_sync_consent?: boolean;
}

export interface CycleOverridePayload {
  id: string;
  profile_id: string;
  cycle_start_date: string;
  updated_at: string;
  excluded_from_average?: boolean;
  manual_start?: boolean;
  note_id?: string | null;
  deleted_at?: string | null;
}

export interface CareNotePayload {
  id: string;
  profile_id: string;
  body: string;
  updated_at: string;
  deleted_at?: string | null;
}

export interface VisitPrepItemPayload {
  id: string;
  profile_id: string;
  body: string;
  updated_at: string;
  kind?: string;
  is_checked?: boolean;
  deleted_at?: string | null;
}

export interface GuardianNotePayload {
  id: string;
  profile_id: string;
  local_date: string;
  updated_at: string;
  tz?: string;
  body: string;
  deleted_at?: string | null;
}

export interface SyncPushBatch {
  profiles?: ProfilePayload[];
  day_entries?: DayEntryPayload[];
  observations?: ObservationPayload[];
  profile_modes?: ProfileModePayload[];
  cycle_overrides?: CycleOverridePayload[];
  care_notes?: CareNotePayload[];
  visit_prep_items?: VisitPrepItemPayload[];
  merge_events?: Record<string, unknown>[];
  tag_registry?: Record<string, unknown>[];
  guardian_notes?: GuardianNotePayload[];
}

/** A per-row rejection: the payload row's own `id`, echoed by the server. */
export interface SyncRejection {
  id: string | null;
}

export interface SyncPushOutcome {
  /** The server's stored copy of rows it declined (older updated_at). */
  resolved: Record<string, unknown>[];
  /** Rows the server refused — surface at the field/row that caused it. */
  rejected: SyncRejection[];
  /** The server's transaction-start instant for this push; consumed to
   * learn the clock offset (issue #1283). */
  serverNow: string;
}

/**
 * Pushes one batch through the same RPC the phones use. The server's
 * constraints are unchanged: last-writer-wins on `updated_at`, same-date
 * merge with disclosure rows, the 500-rows-per-array / 5000-total caps.
 *
 * Issue #1283: every response also teaches the clock offset — `server_now`
 * minus a device reading taken immediately before the call (read here, not
 * after the await, so a slow link cannot bias the sample the way issue #566
 * found on the phones), folded through the same EMA the engine smooths
 * with. The response arrives with `server_now` even when rows are rejected
 * (`sync_push`'s per-row handlers answer per row), so the very first save
 * of a badly-skewed browser is what teaches the offset — it may itself be
 * rejected, and every later write is stamped corrected.
 */
export async function pushSyncBatch(
  client: AppSupabaseClient,
  batch: SyncPushBatch,
): Promise<SyncPushOutcome> {
  // supabase-js types each jsonb RPC arg as its `Json` union; the payload
  // interfaces above are exactly that shape at runtime (the integration
  // suite proves the live RPC accepts them) but lack the index signature
  // the union demands, so this boundary cast is deliberate.
  const params = {
    p_profiles: batch.profiles ?? [],
    p_day_entries: batch.day_entries ?? [],
    p_observations: batch.observations ?? [],
    p_profile_modes: batch.profile_modes ?? [],
    p_cycle_overrides: batch.cycle_overrides ?? [],
    p_care_notes: batch.care_notes ?? [],
    p_visit_prep_items: batch.visit_prep_items ?? [],
    p_merge_events: batch.merge_events ?? [],
    p_tag_registry: batch.tag_registry ?? [],
    p_guardian_notes: batch.guardian_notes ?? [],
  };
  const sentAtMs = Date.now();
  const { data, error } = await client.rpc('sync_push', params as never);
  if (error !== null) {
    throw new Error(`sync_push failed: ${error.message}`);
  }
  const parsed = syncPushResultSchema.parse(data);
  learnClockOffset(parsed.server_now, sentAtMs);
  const outcome: SyncPushOutcome = {
    resolved: parsed.resolved,
    rejected: parsed.rejected.map((entry) => ({ id: entry.id })),
    serverNow: parsed.server_now,
  };
  return outcome;
}

// ---------------------------------------------------------------------------
// Payload builders — client-generated ULID ids and updated_at stamps.
// ---------------------------------------------------------------------------
//
// Every stamp comes from `serverAdjustedNow` by default (issue #1283): the
// device clock plus the offset learned from push responses, so a skewed
// browser clock writes server time rather than its own. A test passing an
// explicit clock gets that clock verbatim — the determinism seam.

/** The current time as the ISO-8601 UTC instant the server expects. */
export function nowSyncStamp(clock: () => Date = serverAdjustedNow): string {
  return clock().toISOString();
}

/** A new client-generated row id + updated_at stamp pair. */
export function newSyncStamps(clock: () => Date = serverAdjustedNow): {
  id: string;
  updated_at: string;
} {
  return { id: newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a create-or-edit `profiles` payload (ULID id, live unless told otherwise). */
export function newProfilePayload(
  fields: Omit<ProfilePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): ProfilePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `day_entries` payload; tombstones carry only id + deleted_at. */
export function newDayEntryPayload(
  fields: Omit<DayEntryPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): DayEntryPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds an `observations` payload. */
export function newObservationPayload(
  fields: Omit<ObservationPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): ObservationPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `profile_modes` payload (keyed by profile, no id). */
export function newProfileModePayload(
  fields: Omit<ProfileModePayload, 'updated_at'>,
  clock: () => Date = serverAdjustedNow,
): ProfileModePayload {
  return { ...fields, updated_at: nowSyncStamp(clock) };
}

/** Builds a `cycle_overrides` payload. */
export function newCycleOverridePayload(
  fields: Omit<CycleOverridePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): CycleOverridePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `care_notes` payload. */
export function newCareNotePayload(
  fields: Omit<CareNotePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): CareNotePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `visit_prep_items` payload. */
export function newVisitPrepItemPayload(
  fields: Omit<VisitPrepItemPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): VisitPrepItemPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `guardian_notes` payload. */
export function newGuardianNotePayload(
  fields: Omit<GuardianNotePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = serverAdjustedNow,
): GuardianNotePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/**
 * A tombstone: synced rows are never DELETEd (no grant anywhere), they are
 * soft-deleted by pushing `{ id, updated_at, deleted_at }` — the server
 * strips the payload itself.
 */
export function tombstonePayload(
  id: string,
  clock: () => Date = serverAdjustedNow,
): { id: string; updated_at: string; deleted_at: string } {
  return { id, updated_at: nowSyncStamp(clock), deleted_at: nowSyncStamp(clock) };
}

// ---------------------------------------------------------------------------
// Direct RLS-scoped selects for the tables sync_pull does not carry.
// ---------------------------------------------------------------------------

/**
 * Reads the caller's own `settings` rows — `settings_select_own` RLS
 * scopes the table to the signed-in user — paging past PostgREST's
 * 1,000-row response cap with `.range()`.
 */
export async function fetchSettings(client: AppSupabaseClient): Promise<SettingRow[]> {
  const rows: SettingRow[] = [];
  for (let offset = 0; ; offset += POSTGREST_PAGE_SIZE) {
    const { data, error } = await client
      .from('settings')
      .select('*')
      .order('key')
      .range(offset, offset + POSTGREST_PAGE_SIZE - 1);
    if (error !== null) {
      throw new Error(`settings select failed: ${error.message}`);
    }
    rows.push(...settingListSchema.parse(data));
    if (data.length < POSTGREST_PAGE_SIZE) {
      return rows;
    }
  }
}

/**
 * Reads every `guardian_notes` row on the profiles the caller guards — the
 * table's own guardian-scoped RLS scopes the select, the same path the
 * phones use for this table (it is not in sync_pull's response) — paged
 * past PostgREST's cap with `.range()`.
 */
export async function fetchGuardianNotes(
  client: AppSupabaseClient,
  opts: { profileId?: string } = {},
): Promise<GuardianNoteRow[]> {
  const rows: GuardianNoteRow[] = [];
  for (let offset = 0; ; offset += POSTGREST_PAGE_SIZE) {
    let query = client.from('guardian_notes').select('*').order('id');
    if (opts.profileId !== undefined) {
      query = query.eq('profile_id', opts.profileId);
    }
    const { data, error } = await query.range(offset, offset + POSTGREST_PAGE_SIZE - 1);
    if (error !== null) {
      throw new Error(`guardian_notes select failed: ${error.message}`);
    }
    rows.push(...guardianNoteListSchema.parse(data));
    if (data.length < POSTGREST_PAGE_SIZE) {
      return rows;
    }
  }
}

// ---------------------------------------------------------------------------
// Live updates: public.sync_signals (the Realtime publication's only table)
// ---------------------------------------------------------------------------

/** A parsed wake signal. Carries no health content, by construction. */
export type SyncSignal = {
  profile_id: string | null;
  updated_at: string | null;
};

export interface SyncSignalsSubscription {
  unsubscribe: () => void;
}

/**
 * Subscribes to `public.sync_signals` for the given profiles and invokes
 * `onSignal` on every event. The payload is a wake signal only — the
 * authoritative read stays on `sync_pull` — so every event (insert,
 * update, delete, unparseable) fires the callback; only the subscription
 * wiring itself is typed.
 */
export function subscribeSyncSignals(
  client: AppSupabaseClient,
  profileIds: string[],
  onSignal: (signal: SyncSignal) => void,
): SyncSignalsSubscription {
  if (profileIds.length === 0) {
    return { unsubscribe: () => undefined };
  }
  const channel = client.channel(`sync_signals:${profileIds.slice().sort().join(',')}`);
  channel.on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'sync_signals',
      filter: `profile_id=in.(${profileIds.slice().sort().join(',')})`,
    },
    (payload: { new: unknown }) => {
      const parsed = syncSignalSchema.safeParse(payload.new ?? {});
      onSignal(
        parsed.success
          ? { profile_id: parsed.data.profile_id, updated_at: parsed.data.updated_at }
          : { profile_id: null, updated_at: null },
      );
    },
  );
  channel.subscribe();
  return {
    unsubscribe: () => {
      void client.removeChannel(channel);
    },
  };
}

// ---------------------------------------------------------------------------
// The in-memory session cache: cursors + merged snapshot, reset on sign-out.
// ---------------------------------------------------------------------------

/**
 * The web session's synced-data state: a merged row snapshot plus the pull
 * cursors, both purely in-memory. One instance per page; `reset()` (sign-
 * out) drops it — the same moment the TanStack cache is cleared.
 *
 * Every reset bumps a generation counter, and each `refresh()` captures it
 * before its pull starts (issue #1315): `resetWebDataForSignOut` clears the
 * TanStack cache but cannot abort a `queryFn` already awaiting the network,
 * so a pull started under account A can resolve after account B's reset.
 * Without the guard that stale resolution would write A's cursors back and
 * merge A's rows into B's empty snapshot — B's first pull would then start
 * from A's `server_version` cursors and skip every B row below them (one
 * global sequence). A refresh whose generation moved returns the current
 * snapshot instead and touches nothing.
 *
 * The generation alone cannot see every identity change, though (issue
 * #1338): a pull that runs entirely *before* any reset has an unchanged
 * generation, yet it can still run under a different account — the bearer
 * token comes from the auth client's renewal (GET /auth/session), which
 * adopts whatever account the shared refresh cookie now holds, while the
 * shell's watcher notices an account change only when the session query
 * re-resolves. So each `refresh()` also tags itself with the account it
 * runs under, re-read through the caller-supplied `readIdentity` before the
 * pull and again at resolution: a pull that re-identifies itself mid-flight,
 * or runs under an account the current snapshot was not built for, is
 * discarded the same way — no cursor advance, no merge — until the watcher's
 * reset re-bases the cache on the new account.
 */
export class SyncedDataCache {
  private cursors: SyncPullCursors = emptyCursors();
  private snapshot: SyncedData = emptySyncedData();
  private generation = 0;
  private identity: string | null = null;

  /**
   * Pulls forward from the session's cursors and merges into the snapshot.
   * `readIdentity` is the caller's live read of the signed-in account's id
   * (the auth client stays out of this module's imports — the caller, whose
   * queryFn already holds it, supplies the seam).
   */
  async refresh(
    client: AppSupabaseClient,
    readIdentity: () => string | null,
  ): Promise<SyncedData> {
    const generation = this.generation;
    const identityBefore = readIdentity();
    const result = await pullSyncedData(client, { cursors: this.cursors });
    return this.adoptPull(readIdentity, generation, identityBefore, () => {
      this.cursors = result.cursors;
      this.snapshot = mergeSyncedData(this.snapshot, result.data);
      return this.snapshot;
    });
  }

  /**
   * The full from-zero re-pull (issue #1282): a membership change — invite
   * accept, ownership-transfer claim, leave, revoke — reshapes which rows
   * `sync_pull` returns without bumping the affected rows'
   * `server_version`s, so an incremental pull can never converge. The new
   * profile's history sits below the session's cursors (the global sequence
   * predates the accept), and a left/revoked profile simply stops being
   * returned with no tombstone at all. This pull starts from zero cursors
   * and lands in a **fresh** snapshot — the stale rows are discarded with
   * the snapshot that held them, not merged over — filtered down to the
   * profiles the pulled `profile_guardians` rows still accept for this
   * account (see [filterToAcceptedMemberships]).
   *
   * The same generation + identity guard as [refresh]: a pull that resolves
   * across a sign-out/reset, or under an account the snapshot was not built
   * for, touches nothing.
   */
  async repullAll(
    client: AppSupabaseClient,
    readIdentity: () => string | null,
  ): Promise<SyncedData> {
    const generation = this.generation;
    const identityBefore = readIdentity();
    const result = await pullSyncedData(client, { cursors: emptyCursors() });
    return this.adoptPull(readIdentity, generation, identityBefore, (identity) => {
      this.cursors = result.cursors;
      this.snapshot = filterToAcceptedMemberships(result.data, identity);
      return this.snapshot;
    });
  }

  /**
   * [refresh]/[repullAll]'s shared landing: re-reads the identity and
   * discards the pull when the generation moved (a reset landed mid-pull,
   * issue #1315) or the pull ran under — or re-identified itself into — an
   * account the current snapshot was not built for (issue #1338). Only on a
   * clean landing does `commit` write the cursors and snapshot.
   */
  private async adoptPull(
    readIdentity: () => string | null,
    generation: number,
    identityBefore: string | null,
    commit: (identity: string | null) => SyncedData,
  ): Promise<SyncedData> {
    const identityAfter = readIdentity();
    if (
      generation !== this.generation ||
      identityBefore !== identityAfter ||
      (this.identity !== null && identityAfter !== this.identity)
    ) {
      // The identity reset landed while this pull was in flight (the
      // generation moved), or the pull ran under — or re-identified itself
      // into — an account this snapshot was not built for (issue #1338).
      // The result belongs to another account: discard it — no cursor
      // advance, no merge, no tag — and hand back whatever the current
      // session's snapshot holds until the watcher's reset re-bases the
      // cache.
      return this.snapshot;
    }
    this.identity = identityAfter;
    return commit(identityAfter);
  }

  /** The current merged snapshot, or the empty one before the first pull. */
  current(): SyncedData {
    return this.snapshot;
  }

  /** Sign-out: forget every cursor and row. Nothing was ever persisted. */
  reset(): void {
    this.generation += 1;
    this.identity = null;
    this.cursors = emptyCursors();
    this.snapshot = emptySyncedData();
  }
}

/**
 * Merges a pull page-set into a snapshot: replaces rows by id where the
 * pulled copy is newer (or a tombstone), drops nothing that is still live.
 * Rows without ids (profile_modes) merge by their natural key.
 */
export function mergeSyncedData(base: SyncedData, incoming: SyncedData): SyncedData {
  return {
    profiles: mergeById(base.profiles, incoming.profiles),
    day_entries: mergeById(base.day_entries, incoming.day_entries),
    observations: mergeById(base.observations, incoming.observations),
    profile_modes: mergeByNaturalKey(base.profile_modes, incoming.profile_modes),
    cycle_overrides: mergeById(base.cycle_overrides, incoming.cycle_overrides),
    care_notes: mergeById(base.care_notes, incoming.care_notes),
    visit_prep_items: mergeById(base.visit_prep_items, incoming.visit_prep_items),
    profile_tag_registry: mergeById(base.profile_tag_registry, incoming.profile_tag_registry),
    profile_guardians: mergeById(base.profile_guardians, incoming.profile_guardians),
    guardian_notes: mergeById(base.guardian_notes, incoming.guardian_notes),
  };
}

/** Compares ISO-8601 timestamps as instants (renders differ in offset form). */
function isNotOlder(updatedAt: string, than: string): boolean {
  return Date.parse(updatedAt) <= Date.parse(than);
}

function mergeById<T extends { id: string; updated_at: string }>(
  base: T[],
  incoming: T[],
): T[] {
  if (incoming.length === 0) return base;
  const byId = new Map(base.map((row) => [row.id, row]));
  for (const row of incoming) {
    const stored = byId.get(row.id);
    if (stored === undefined || isNotOlder(stored.updated_at, row.updated_at)) {
      byId.set(row.id, row);
    }
  }
  return [...byId.values()];
}

function mergeByNaturalKey<T extends { profile_id: string; updated_at: string }>(
  base: T[],
  incoming: T[],
): T[] {
  if (incoming.length === 0) return base;
  const byKey = new Map(base.map((row) => [row.profile_id, row]));
  for (const row of incoming) {
    const stored = byKey.get(row.profile_id);
    if (stored === undefined || isNotOlder(stored.updated_at, row.updated_at)) {
      byKey.set(row.profile_id, row);
    }
  }
  return [...byKey.values()];
}

/**
 * Drops every profile this account no longer holds an **accepted**
 * guardianship on, with all of its dependent rows (issue #1282). Runs on a
 * from-zero pull's fresh snapshot only: `sync_pull` scopes every table to
 * the caller's accepted memberships server-side, but an *incremental* pull
 * returns `profile_guardians` rows past the cursor only — deriving the set
 * from one of those would mistake an unchanged (not re-returned) membership
 * for a missing one. A from-zero pull carries every guardian row on every
 * pulled profile, so the derived set is complete.
 *
 * `sync_pull`'s `profile_guardians` branch returns **all** guardian rows on
 * the accepted profiles (every guardian, not just the caller's), so the
 * caller's own rows are picked out by `user_id`. A null identity (no live
 * read — not a state a successful pull reaches, since the RPC requires an
 * authenticated caller) skips the filter: the server-side tenant predicate
 * already scoped the rows.
 */
export function filterToAcceptedMemberships(
  data: SyncedData,
  userId: string | null,
): SyncedData {
  if (userId === null) {
    return data;
  }
  const accepted = new Set(
    data.profile_guardians
      .filter((row) => row.user_id === userId && row.status === 'accepted')
      .map((row) => row.profile_id),
  );
  const onAcceptedProfiles = <T extends { profile_id: string }>(rows: T[]): T[] =>
    rows.filter((row) => accepted.has(row.profile_id));
  return {
    profiles: data.profiles.filter((row) => accepted.has(row.id)),
    day_entries: onAcceptedProfiles(data.day_entries),
    observations: onAcceptedProfiles(data.observations),
    profile_modes: onAcceptedProfiles(data.profile_modes),
    cycle_overrides: onAcceptedProfiles(data.cycle_overrides),
    care_notes: onAcceptedProfiles(data.care_notes),
    visit_prep_items: onAcceptedProfiles(data.visit_prep_items),
    profile_tag_registry: onAcceptedProfiles(data.profile_tag_registry),
    profile_guardians: onAcceptedProfiles(data.profile_guardians),
    guardian_notes: onAcceptedProfiles(data.guardian_notes),
  };
}

/** The page's one synced-data cache. */
const sharedCache = new SyncedDataCache();

/** The shared cache, for hooks and screens. */
export function getSyncedDataCache(): SyncedDataCache {
  return sharedCache;
}

/**
 * Sign-out: resets the synced-data snapshot/cursors and clears the TanStack
 * Query cache. The auth layer's mutations call this at every identity
 * boundary (issue #1281) — after it, nothing of the session remains in
 * memory. The learned clock offset deliberately survives (issue #1283): it
 * is a device-versus-server property, not account data — the same server
 * clock on either side of the boundary — so keeping it means the next
 * account's first write is already stamped corrected instead of waiting on
 * a fresh push to re-teach it.
 */
export function resetWebDataForSignOut(queryClient: { clear: () => void }): void {
  sharedCache.reset();
  queryClient.clear();
}

/** Convenience re-export so callers need only this module for push results. */
export type { SyncPushResult };
