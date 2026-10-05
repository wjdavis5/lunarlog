import type {
  BirthControlStateJson,
  CycleFactsJson,
  DayEntryJson,
  PredictRequest,
} from '../../domain/client';
import type { CycleConfidence, Prediction } from '../../domain/schemas';
import type { SyncedData } from '../domain';
import type { ProfileRow } from '../schemas';
import { guardianRoleFromDbOrViewer, roleCanEditProfile, type GuardianRole } from '../roles';

/**
 * The profile screens' pure derivations (issue #1253) — everything the
 * profiles page and the profile home render, computed from the #1252
 * synced-data snapshot and the #1251 domain outputs. No client, no
 * network, no clock: `todayIso` and the signed-in user id always arrive
 * from the caller, the same seam discipline `lib/day/day-data.ts` applies,
 * so every function here is unit-testable without a Supabase client.
 */

/** The operator's profiles grouped the way the app's picker groups them. */
export interface ProfileLists {
  /** Profiles this account created (`profiles.user_id` is the caller). */
  mine: ProfileRow[];
  /** Profiles shared with me by another guardian. */
  shared: ProfileRow[];
  /** Archived profiles (both mine and shared), archive instant descending. */
  archived: ProfileRow[];
}

/**
 * Splits the synced snapshot's live profiles into mine / shared-with-me /
 * archived. Live means not deleted and not archived — the same predicate
 * `useLiveProfiles` applies — so a tombstoned profile never renders
 * anywhere; an archived one renders only under the archived header.
 */
export function profileListsFromSyncedData(
  synced: SyncedData,
  uid: string | null,
): ProfileLists {
  const mine: ProfileRow[] = [];
  const shared: ProfileRow[] = [];
  const archived: ProfileRow[] = [];
  for (const profile of synced.profiles) {
    if (profile.deleted_at !== null) continue;
    const list =
      profile.archived_at !== null
        ? archived
        : uid !== null && profile.user_id === uid
          ? mine
          : shared;
    list.push(profile);
  }
  const bySortOrder = (a: ProfileRow, b: ProfileRow): number =>
    a.sort_order - b.sort_order || (a.id < b.id ? -1 : 1);
  const byArchived = (a: ProfileRow, b: ProfileRow): number =>
    (b.archived_at ?? '').localeCompare(a.archived_at ?? '') || bySortOrder(a, b);
  mine.sort(bySortOrder);
  shared.sort(bySortOrder);
  archived.sort(byArchived);
  return { mine, shared, archived };
}

/**
 * The caller's effective role on `profileId`, fails-closed to viewer for
 * an unknown role value and null when there is no live membership row
 * (revoked memberships keep `revoked_at` set — not a role).
 */
export function callerRoleFor(
  synced: SyncedData,
  profileId: string,
  uid: string | null,
): GuardianRole | null {
  if (uid === null) return null;
  const membership = synced.profile_guardians.find(
    (row) =>
      row.profile_id === profileId &&
      row.user_id === uid &&
      (row.revoked_at ?? null) === null &&
      row.status === 'accepted',
  );
  if (membership === undefined) return null;
  return guardianRoleFromDbOrViewer(membership.role);
}

/** Whether the caller may write this profile's metadata (the server re-checks). */
export function canEditProfile(role: GuardianRole | null): boolean {
  return role !== null && roleCanEditProfile(role);
}

// ---------------------------------------------------------------------------
// The domain module's inputs, built from the synced snapshot
// ---------------------------------------------------------------------------

/**
 * Maps one profile's live day entries onto the export-row shape the
 * domain facade decodes (`DayEntryJson`). Tombstoned rows are dropped
 * here rather than shipped: the facade drops them too (issue #1274), so
 * sending them is pure noise. `notePrivate` rides along — the engine only
 * reads flow/tags/pms/dates, never note content.
 */
export function entriesToDomainJson(rows: {
  profileId: string;
  entries: SyncedData['day_entries'];
}): DayEntryJson[] {
  const out: DayEntryJson[] = [];
  for (const row of rows.entries) {
    if (row.profile_id !== rows.profileId || row.deleted_at !== null) continue;
    out.push({
      id: row.id,
      profileId: row.profile_id,
      localDate: row.local_date,
      tz: row.tz,
      flow: row.flow,
      tags: row.tags,
      note: row.note,
      notePrivate: row.note_private,
      pms: row.pms,
      source: row.source,
      sourceId: row.source_id ?? null,
      importId: row.import_id ?? null,
      updatedAt: row.updated_at,
      deletedAt: null,
    });
  }
  return out;
}

/** The domain request inputs shared by predict / cycleHistory / calendarForecast. */
export interface ProfileDomainInputs {
  entries: DayEntryJson[];
  omittedCycleStarts: string[];
  facts?: CycleFactsJson;
  birthControl?: BirthControlStateJson;
  lifecycleMode?: string;
  predictionsEnabled: true;
}

/**
 * Builds the prediction inputs for one profile from the synced snapshot:
 * live entries, the omitted-cycle starts (live `cycle_overrides` rows with
 * `excluded_from_average`), the onboarding facts stored on the profile,
 * and the profile_modes row's birth-control state. `lifecycleMode` is
 * absent for the default `tracking` (the facade treats absent as
 * tracking); `predictionsEnabled` is always true — the phones' off toggle
 * is a device-local setting (`predictionsEnabledSettingKey`,
 * lib/domain/prediction/cycle_history.dart) the web client has no
 * settings surface for yet, so the web never disables.
 */
export function profileDomainInputs(
  synced: SyncedData,
  profileId: string,
): ProfileDomainInputs {
  const profile = synced.profiles.find((row) => row.id === profileId);
  const mode = synced.profile_modes.find((row) => row.profile_id === profileId);
  const inputs: ProfileDomainInputs = {
    entries: entriesToDomainJson({ profileId, entries: synced.day_entries }),
    omittedCycleStarts: synced.cycle_overrides
      .filter(
        (row) =>
          row.profile_id === profileId && row.deleted_at === null && row.excluded_from_average,
      )
      .map((row) => row.cycle_start_date),
    predictionsEnabled: true,
  };
  if (
    profile?.last_period_start != null ||
    profile?.typical_cycle_length_days != null ||
    profile?.typical_period_length_days != null
  ) {
    inputs.facts = {
      lastPeriodStart: profile.last_period_start ?? null,
      typicalCycleLengthDays: profile.typical_cycle_length_days ?? null,
      typicalPeriodLengthDays: profile.typical_period_length_days ?? null,
    };
  }
  if (mode !== undefined) {
    if (mode.mode !== 'tracking' && mode.mode !== '') {
      inputs.lifecycleMode = mode.mode;
    }
    const method = mode.birth_control_method ?? null;
    if (method !== null && method !== '' && method !== 'none') {
      inputs.birthControl = {
        method,
        startedOn: mode.birth_control_started_on ?? null,
        stoppedOn: mode.birth_control_stopped_on ?? null,
      };
    }
  }
  return inputs;
}

/** Adds the per-request clock inputs (`today` + the browser's IANA zone). */
export function withClockInputs(
  inputs: ProfileDomainInputs,
  todayIso: string,
  tz: string,
): PredictRequest {
  return { ...inputs, today: todayIso, tz };
}

// ---------------------------------------------------------------------------
// Home presentation (care_modes.dart's composition, mirrored)
// ---------------------------------------------------------------------------

/**
 * The profile's care mode (`ProfileMode.fromDb`): the stored wire value,
 * with the retired `caregiver` folded into `standard` and anything
 * unrecognised degrading to `standard` — the app's own read rule
 * (lib/domain/models/profile_mode.dart).
 */
export type WebProfileMode = 'standard' | 'teen' | 'irregular';

export function profileModeFromDb(value: string | null | undefined): WebProfileMode {
  if (value === 'teen' || value === 'irregular') return value;
  return 'standard';
}

/**
 * The effective irregular-cycles framing (issue #853), a direct port of
 * `irregularFramingInEffect` (lib/domain/care_modes.dart): an explicitly
 * stored value wins; the engine default is ON for a teen profile until
 * the estimate reaches `high` confidence (null tier reads ON), OFF for
 * every other mode; the retired `irregular` wire mode is always ON.
 */
export function irregularFramingInEffect(options: {
  mode: WebProfileMode;
  stored: boolean | null | undefined;
  tier: CycleConfidence | null | undefined;
}): boolean {
  if (options.stored !== null && options.stored !== undefined) return options.stored;
  if (options.mode === 'irregular') return true;
  if (options.mode !== 'teen') return false;
  return options.tier === null || options.tier === undefined || options.tier !== 'high';
}

/**
 * Whether the fertile-window estimate renders at all — the port of the
 * month calendar's `_showsFertileWindow` (lib/ui/logging/month_calendar.dart):
 * the care mode's copy hides it for the retired `irregular` mode (#143) and
 * whenever the irregular-cycles framing is in effect (#853 — which, for a
 * teen with no stored choice, is until the estimate reaches `high`), and
 * the Perimenopause life stage hides it on top (#196). A precise-looking
 * ovulation window is false precision for all three.
 */
export function showsFertileWindow(options: {
  profileMode: WebProfileMode;
  storedIrregularFraming: boolean | null | undefined;
  tier: CycleConfidence | null | undefined;
  lifecycleMode: string | null | undefined;
}): boolean {
  if (options.lifecycleMode === 'perimenopause') return false;
  // The legacy wire mode is its own full copy: a stored `false` framing
  // never turns its fertile window back on (careModeCopyFor).
  if (options.profileMode === 'irregular') return false;
  return !irregularFramingInEffect({
    mode: options.profileMode,
    stored: options.storedIrregularFraming,
    tier: options.tier,
  });
}

/**
 * The estimate's date presentation (`estimateDateText`,
 * lib/ui/overview/estimate_copy.dart): `high` confidence shows the exact
 * date; any other tier shows the `estimatedNextStart ± round(spreadDays)`
 * range — except a degenerate spread that rounds to zero, which falls
 * back to the plain date so "June 18 – June 18" never renders.
 */
export function estimateDateText(options: {
  estimatedNextStart: string;
  spreadDays: number;
  tier: CycleConfidence;
}): { kind: 'date'; iso: string } | { kind: 'range'; startIso: string; endIso: string } {
  if (options.tier === 'high') return { kind: 'date', iso: options.estimatedNextStart };
  const days = Math.round(options.spreadDays);
  if (days === 0) return { kind: 'date', iso: options.estimatedNextStart };
  return {
    kind: 'range',
    startIso: shiftIsoDate(options.estimatedNextStart, -days),
    endIso: shiftIsoDate(options.estimatedNextStart, days),
  };
}

/**
 * Whether [iso] is a real civil date written `yyyy-MM-dd`: four-digit year,
 * and a day that exists (no 31 February).
 *
 * A date field hands over more than that. Chrome's year box takes up to six
 * digits, so one extra keystroke yields `20261-10-05`, which is not a date
 * anything here can format, store or look up.
 */
export function isCivilDate(iso: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
  const time = Date.parse(`${iso}T00:00:00Z`);
  return !Number.isNaN(time) && new Date(time).toISOString().slice(0, 10) === iso;
}

/**
 * A formatter for civil dates (`yyyy-MM-dd`: no time, no zone). The date is
 * read as UTC midnight, so it must be written in UTC too — in the browser's
 * own zone anyone west of UTC would read the day before (issue #1389).
 *
 * It never throws. A value that is not a civil date comes back as it was
 * given: `Intl.DateTimeFormat` throws on an invalid date, and these
 * formatters run while a page renders, where a throw takes the whole page
 * down (issue #1473).
 */
export function isoDateFormatter(
  locale: string,
  options: Omit<Intl.DateTimeFormatOptions, 'timeZone'>,
): (iso: string) => string {
  const format = new Intl.DateTimeFormat(locale, { ...options, timeZone: 'UTC' });
  return (iso) => (isCivilDate(iso) ? format.format(new Date(`${iso}T00:00:00Z`)) : iso);
}

/** Civil-date arithmetic on `yyyy-MM-dd` strings (no time zones involved). */
export function shiftIsoDate(iso: string, days: number): string {
  const [y, m, d] = iso.split('-').map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}

/** Days from `startIso` to `endIso` (inclusive-exclusive, civil dates). */
export function isoDaysBetween(startIso: string, endIso: string): number {
  const a = Date.UTC(
    Number(startIso.slice(0, 4)),
    Number(startIso.slice(5, 7)) - 1,
    Number(startIso.slice(8, 10)),
  );
  const b = Date.UTC(
    Number(endIso.slice(0, 4)),
    Number(endIso.slice(5, 7)) - 1,
    Number(endIso.slice(8, 10)),
  );
  return Math.round((b - a) / 86_400_000);
}

/** What the home card renders for one prediction, before catalogue lookup. */
export type HomeEstimateView =
  | { kind: 'disabled' }
  | {
      kind: 'suppressed';
      /** The suppression reason's parameters, exactly one of the two set. */
      methodDb: string | null;
      lifecycleModeDb: string | null;
    }
  | {
      kind: 'notEnoughHistory';
      teen: boolean;
      completedCycles: number;
      neededCycles: number;
    }
  | {
      kind: 'active';
      mode: WebProfileMode;
      composed: boolean;
      cycleDay: number;
      duringEpisode: boolean;
      episodeDay: number;
      estimate:
        { kind: 'date'; iso: string } | { kind: 'range'; startIso: string; endIso: string };
      tier: CycleConfidence;
      /** The overdue line's parameters, or null when not overdue. */
      overdue: { daysLate: number | null } | null;
      unusuallyLongCycle: boolean;
      staleHistory: boolean;
      todayIso: string;
    };

const kNeededCompletedCycles = 3;

/**
 * Composes the home estimate view from the domain prediction and the
 * profile's framing — the service/UI order the app applies
 * (care_modes.dart + overview_panel.dart): mode framing decides labels
 * and the overdue voice; the tier decides date vs range; a teen is never
 * "late". Pure.
 */
export function homeEstimateView(options: {
  prediction: Prediction;
  profileMode: WebProfileMode;
  storedIrregularFraming: boolean | null | undefined;
  todayIso: string;
}): HomeEstimateView {
  const { prediction } = options;
  switch (prediction.kind) {
    case 'disabled':
      return { kind: 'disabled' };
    case 'suppressed':
      return {
        kind: 'suppressed',
        methodDb: prediction.method,
        lifecycleModeDb: prediction.lifecycleMode,
      };
    case 'notEnoughHistory': {
      const mode = options.profileMode;
      return {
        kind: 'notEnoughHistory',
        teen: mode === 'teen',
        completedCycles: prediction.completedCycleCount,
        neededCycles: kNeededCompletedCycles,
      };
    }
    case 'active': {
      const mode = options.profileMode === 'irregular' ? 'standard' : options.profileMode;
      // The composed axis only ever composes onto standard/teen; the
      // legacy `irregular` wire mode is already its own full copy
      // (care_modes.dart's careModeCopyFor).
      const stored =
        options.profileMode === 'irregular' ? true : options.storedIrregularFraming;
      const composed = irregularFramingInEffect({
        mode,
        stored,
        tier: prediction.tier,
      });
      const overdue =
        prediction.daysLate !== null && prediction.daysLate > 0
          ? { daysLate: prediction.daysLate }
          : null;
      return {
        kind: 'active',
        mode,
        composed,
        cycleDay: prediction.cycleDay,
        duringEpisode: prediction.duringEpisode,
        episodeDay: isoDaysBetween(prediction.lastEpisodeStart, options.todayIso) + 1,
        estimate: estimateDateText({
          estimatedNextStart: prediction.estimatedNextStart,
          spreadDays: prediction.spreadDays,
          tier: prediction.tier,
        }),
        tier: prediction.tier,
        overdue,
        unusuallyLongCycle: prediction.unusuallyLongCycle,
        staleHistory: prediction.staleHistory,
        todayIso: options.todayIso,
      };
    }
  }
}

/**
 * The address of one profile's home. The home reads `?profile=` and falls
 * back to the first live profile without it, so a link that means "back to
 * this profile" has to name the profile.
 */
export function profileHomePath(profileId: string): string {
  return profileId === '' ? '/' : `/?profile=${encodeURIComponent(profileId)}`;
}
