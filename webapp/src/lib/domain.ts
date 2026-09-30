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
 *   cycle history loads no matter its size).
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
 * server's last-writer-wins and same-date merge rules behave as they do
 * for phones; per-row rejections (date bounds, key allowlist, viewer
 * role) come back in `rejected` and are surfaced mapped to the offending
 * payload row. Guardian-membership changes ride the sharing RPCs
 * (`create_guardian_invitation`, `accept_guardian_invitation`,
 * `update_guardian_role`, `revoke_guardian`, …) — this module adds no
 * server path, and no migration ships with it.
 *
 * **Live updates:** `public.sync_signals` is the only table the Realtime
 * publication carries (20260905100000) — a content-free
 * (profile_id, updated_at) wake row per profile. Subscribe for the open
 * profiles and refetch on a signal; the signal payload is never trusted
 * as data.
 *
 * **Cache:** everything here lives in page memory — cursors, the merged
 * row snapshot, and the TanStack Query cache (no persister, issue #1249).
 * `resetWebDataForSignOut` clears all three; the auth flow calls it on
 * sign-out.
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
 * Pulls every synced table forward from `cursors` (all the way from zero
 * for a first load — a profile's full cycle history arrives, not just the
 * recent window), paging until no table returns a full page, and returns
 * the merged rows plus the advanced cursors.
 */
export async function pullSyncedData(
  client: AppSupabaseClient,
  opts: { cursors?: SyncPullCursors } = {},
): Promise<{ data: SyncedData; cursors: SyncPullCursors }> {
  const cursors: SyncPullCursors = { ...emptyCursors(), ...opts.cursors };
  const merged = emptySyncedData();

  for (let round = 0; round < MAX_PULL_ROUNDS; round += 1) {
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
      return { data: merged, cursors };
    }
  }
  throw new Error(`sync_pull did not exhaust within ${MAX_PULL_ROUNDS} rounds`);
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
  serverNow: string;
}

/**
 * Pushes one batch through the same RPC the phones use. The server's
 * constraints are unchanged: last-writer-wins on `updated_at`, same-date
 * merge with disclosure rows, the 500-rows-per-array / 5000-total caps.
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
  const { data, error } = await client.rpc('sync_push', params as never);
  if (error !== null) {
    throw new Error(`sync_push failed: ${error.message}`);
  }
  const parsed = syncPushResultSchema.parse(data);
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

/** The current time as the ISO-8601 UTC instant the server expects. */
export function nowSyncStamp(clock: () => Date = () => new Date()): string {
  return clock().toISOString();
}

/** A new client-generated row id + updated_at stamp pair. */
export function newSyncStamps(clock: () => Date = () => new Date()): {
  id: string;
  updated_at: string;
} {
  return { id: newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a create-or-edit `profiles` payload (ULID id, live unless told otherwise). */
export function newProfilePayload(
  fields: Omit<ProfilePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): ProfilePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `day_entries` payload; tombstones carry only id + deleted_at. */
export function newDayEntryPayload(
  fields: Omit<DayEntryPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): DayEntryPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds an `observations` payload. */
export function newObservationPayload(
  fields: Omit<ObservationPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): ObservationPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `profile_modes` payload (keyed by profile, no id). */
export function newProfileModePayload(
  fields: Omit<ProfileModePayload, 'updated_at'>,
  clock: () => Date = () => new Date(),
): ProfileModePayload {
  return { ...fields, updated_at: nowSyncStamp(clock) };
}

/** Builds a `cycle_overrides` payload. */
export function newCycleOverridePayload(
  fields: Omit<CycleOverridePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): CycleOverridePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `care_notes` payload. */
export function newCareNotePayload(
  fields: Omit<CareNotePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): CareNotePayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `visit_prep_items` payload. */
export function newVisitPrepItemPayload(
  fields: Omit<VisitPrepItemPayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
): VisitPrepItemPayload {
  return { ...fields, id: fields.id ?? newUlid(), updated_at: nowSyncStamp(clock) };
}

/** Builds a `guardian_notes` payload. */
export function newGuardianNotePayload(
  fields: Omit<GuardianNotePayload, 'id' | 'updated_at'> & { id?: string },
  clock: () => Date = () => new Date(),
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
  clock: () => Date = () => new Date(),
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
 */
export class SyncedDataCache {
  private cursors: SyncPullCursors = emptyCursors();
  private snapshot: SyncedData = emptySyncedData();

  /** Pulls forward from the session's cursors and merges into the snapshot. */
  async refresh(client: AppSupabaseClient): Promise<SyncedData> {
    const result = await pullSyncedData(client, { cursors: this.cursors });
    this.cursors = result.cursors;
    this.snapshot = mergeSyncedData(this.snapshot, result.data);
    return this.snapshot;
  }

  /** The current merged snapshot, or the empty one before the first pull. */
  current(): SyncedData {
    return this.snapshot;
  }

  /** Sign-out: forget every cursor and row. Nothing was ever persisted. */
  reset(): void {
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

/** The page's one synced-data cache. */
const sharedCache = new SyncedDataCache();

/** The shared cache, for hooks and screens. */
export function getSyncedDataCache(): SyncedDataCache {
  return sharedCache;
}

/**
 * Sign-out: resets the synced-data snapshot/cursors and clears the TanStack
 * Query cache. The auth layer (issue #1250's flow) calls this on
 * `SIGNED_OUT` — after it, nothing of the session remains in memory.
 */
export function resetWebDataForSignOut(queryClient: { clear: () => void }): void {
  sharedCache.reset();
  queryClient.clear();
}

/** Convenience re-export so callers need only this module for push results. */
export type { SyncPushResult };
