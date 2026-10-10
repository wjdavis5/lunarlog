/**
 * The typed client for the compiled Dart domain module (issue #1251).
 *
 * The module is `webapp/public/domain/lunarlog_domain.js` — dart2js output
 * from `tool/web_domain/main.dart`, loaded by a static `<script>` tag in
 * `index.html` (parser-inserted same-origin script: clean under the
 * #1249 CSP's `script-src 'self'`, and no Trusted Types sink). It installs
 * `window.lunarlogDomain` with a JSON-in/JSON-out `invoke` surface.
 *
 * Every response passes through two gates before a caller sees it: the
 * envelope is unwrapped here (a `{"ok": false}` envelope becomes a thrown
 * `DomainCallError`), and the data is validated with the Zod schemas in
 * `./schemas`. The parity suite keeps these schemas pinned to the Dart
 * side through committed fixtures.
 *
 * The domain module holds no state between calls: `today` and the IANA
 * zone are passed in on every request, so the browser's own clock and
 * `Intl.DateTimeFormat().resolvedOptions().timeZone` are the only time
 * inputs — the same seam the Flutter app's services use.
 */

import {
  bbtChartSchema,
  calendarForecastSchema,
  cycleRecapResponseSchema,
  cycleHistoryViewSchema,
  dateValidationSchema,
  domainErrorSchema,
  domainSuccessSchema,
  exportDocumentSchema,
  insightsReportSchema,
  inviteLinkSchema,
  predictionSchema,
  todayLogSchema,
  type BbtChart,
  type CalendarForecast,
  type CycleRecap,
  type CycleHistoryView,
  type ExportDocument,
  type InsightsReport,
  type InviteLink,
  type Prediction,
  type TodayLog,
} from './schemas';
import type { z } from 'zod';

/** The surface `tool/web_domain/main.dart` installs on the global. */
export interface DomainModule {
  readonly version: string;
  invoke(method: string, requestJson: string): string;
}

declare global {
  interface Window {
    lunarlogDomain?: DomainModule;
  }
}

/** The global is absent — the module was not built or not loaded. */
export class DomainModuleMissingError extends Error {
  constructor() {
    super(
      'window.lunarlogDomain is not loaded. Build the domain module first: ' +
        'dart compile js -O2 tool/web_domain/main.dart ' +
        '-o webapp/public/domain/lunarlog_domain.js (see webapp/README.md).',
    );
    this.name = 'DomainModuleMissingError';
  }
}

/** The Dart side answered `{"ok": false, "error": ...}`. */
export class DomainCallError extends Error {
  constructor(
    readonly method: string,
    message: string,
  ) {
    super(`domain call "${method}" failed: ${message}`);
    this.name = 'DomainCallError';
  }
}

/** Reads the module the script tag installed. */
export function getDomainModule(win: Window = window): DomainModule {
  const module = win.lunarlogDomain;
  if (!module || typeof module.invoke !== 'function') {
    throw new DomainModuleMissingError();
  }
  return module;
}

/**
 * Runs one facade call: JSON in, Zod-validated typed data out. The only
 * function in this file that talks to the module — every per-method helper
 * below routes through it, so the envelope unwrap and validation gates
 * apply everywhere.
 */
export function callDomain<T>(
  module: DomainModule,
  method: string,
  request: unknown,
  schema: z.ZodType<T>,
): T {
  const response: unknown = JSON.parse(module.invoke(method, JSON.stringify(request)));
  const errorResult = domainErrorSchema.safeParse(response);
  if (errorResult.success) {
    throw new DomainCallError(method, errorResult.data.error);
  }
  const success = domainSuccessSchema.parse(response);
  return schema.parse(success.data);
}

// ---------------------------------------------------------------------------
// Request shapes (the facade's documented inputs; export-shaped rows)
// ---------------------------------------------------------------------------

/** One day entry in the app's export-row shape (`tool/web_domain/facade.dart`). */
export interface DayEntryJson {
  id: string;
  /** Injected per request context; the export row itself omits it. */
  profileId?: string;
  localDate: string;
  tz: string;
  flow: string;
  tags: string[];
  note: string | null;
  notePrivate: boolean;
  pms: boolean;
  source: string;
  sourceId: string | null;
  importId: string | null;
  updatedAt: string;
  /** Facade extension: the export format excludes tombstones; we hold them. */
  deletedAt?: string | null;
}

/** Onboarding-supplied cycle facts (`CycleFacts` on the Dart side). */
export interface CycleFactsJson {
  lastPeriodStart: string | null;
  typicalCycleLengthDays: number | null;
  typicalPeriodLengthDays: number | null;
}

/** Raw `profile_modes` birth-control columns (`BirthControlState` in Dart). */
export interface BirthControlStateJson {
  method: string | null;
  startedOn: string | null;
  stoppedOn: string | null;
}

/** The shared prediction-input shape (also `insights`' input). */
export interface PredictRequest {
  today: string;
  /** The browser's IANA zone, e.g. `Intl.DateTimeFormat().resolvedOptions().timeZone`. */
  tz: string;
  entries: DayEntryJson[];
  profileId?: string;
  omittedCycleStarts?: string[];
  facts?: CycleFactsJson;
  birthControl?: BirthControlStateJson;
  lifecycleMode?: string;
  predictionsEnabled?: boolean;
}

export function predict(module: DomainModule, request: PredictRequest): Prediction {
  return callDomain(module, 'predict', request, predictionSchema);
}

export function cycleHistory(
  module: DomainModule,
  request: Pick<
    PredictRequest,
    'today' | 'tz' | 'entries' | 'profileId' | 'omittedCycleStarts'
  >,
): CycleHistoryView {
  return callDomain(module, 'cycleHistory', request, cycleHistoryViewSchema);
}

/**
 * The month calendar's per-date forecast cells (issue #1253) — the same
 * `forecastDayCells` lookup the app's grid paints, resolved through the
 * service-equivalent prediction order. Callers gate on `predict` first
 * (kind `active`) and treat `staleHistory` as no-forecast, exactly like
 * the app's calendar.
 */
export function calendarForecast(
  module: DomainModule,
  request: PredictRequest,
): CalendarForecast {
  return callDomain(module, 'calendarForecast', request, calendarForecastSchema);
}

export function insights(module: DomainModule, request: PredictRequest): InsightsReport {
  return callDomain(module, 'insights', request, insightsReportSchema);
}

/** One measurement row the BBT chart resolves onto its own day. */
export interface BbtObservationJson {
  dayEntryId: string;
  category: string;
  valueNum: number | null;
  unit: string | null;
  source?: string;
  excluded?: boolean;
  deletedAt?: string | null;
}

/**
 * The BBT chart's input: the same entries `predict` takes, plus the
 * profile's measurement rows. Callers map their synced `observations` rows
 * onto `BbtObservationJson` (the row's `dayEntryId`, category, value, unit,
 * source, exclusion flag, and tombstone); the facade resolves each row onto
 * its day and drops what the chart does not plot.
 */
export interface BbtChartRequest {
  entries: DayEntryJson[];
  observations: BbtObservationJson[];
}

/**
 * The BBT chart's drawable series (issue #1796): the app's own
 * `BbtChartData` in the form its painter consumes - per-point x/y fractions,
 * per-series overlay opacity, and the Celsius range for the caption - so the
 * web draws exactly what the phone draws without recomputing any geometry.
 */
export function bbtChart(module: DomainModule, request: BbtChartRequest): BbtChart {
  return callDomain(module, 'bbtChart', request, bbtChartSchema);
}

/**
 * The cycle-end recap (issue #1796): the facts the app's recap card reads,
 * or null when no cycle has completed yet. The web keeps no previous-
 * snapshot state, so the change facts arrive as the no-snapshot case.
 */
export function cycleRecap(module: DomainModule, request: PredictRequest): CycleRecap | null {
  return callDomain(module, 'cycleRecap', request, cycleRecapResponseSchema).recap;
}

export function validateDayEntryDate(
  module: DomainModule,
  request: { date: string; today: string; birthYear?: number },
): z.infer<typeof dateValidationSchema> {
  return callDomain(module, 'validateDayEntryDate', request, dateValidationSchema);
}

/** Export-shaped profile, with its day entries nested (the export layout). */
export interface ExportProfileJson {
  id: string;
  displayName: string;
  isMinor: boolean;
  mode?: string;
  irregularFraming?: boolean | null;
  sortOrder?: number;
  archivedAt?: string | null;
  createdAt: string;
  updatedAt: string;
  birthYear?: number | null;
  relationship?: string | null;
  lastPeriodStart?: string | null;
  typicalCycleLengthDays?: number | null;
  typicalPeriodLengthDays?: number | null;
  trackingPreferences?: Record<string, unknown> | null;
  dayEntries: DayEntryJson[];
  profileMode?: Record<string, unknown> | null;
}

export function buildExport(
  module: DomainModule,
  request: {
    exportedAt: string;
    appVersion: string;
    appName?: string;
    profiles: ExportProfileJson[];
  },
): ExportDocument {
  return callDomain(module, 'buildExport', request, exportDocumentSchema);
}

export function parseInviteLink(
  module: DomainModule,
  request: { url: string; linkDomain?: string },
): InviteLink | null {
  return callDomain(module, 'parseInviteLink', request, inviteLinkSchema.nullable());
}

/** One observation of the day's entry, as much of it as the Today log reads. */
export interface TodayLogObservationJson {
  dayEntryId: string;
  category: string | null;
  valueNum: number | null;
  unit: string | null;
  source: string;
  deletedAt?: string | null;
}

/** One row of the profile's own tag registry: the code and what it is called. */
export interface TodayLogCustomTagJson {
  code: string;
  displayName: string;
  deletedAt?: string | null;
}

/** The `todayLog` request (`todayLogFromJson`, tool/web_domain/facade.dart). */
export interface TodayLogRequest {
  /** The day's entry, or null when the day has none. */
  entry: DayEntryJson | null;
  /** The observations attached to that entry. */
  observations?: TodayLogObservationJson[];
  /** The profile's own tag registry. */
  customTags?: TodayLogCustomTagJson[];
  /** The profile's display units; a reading is answered in them. */
  bbtUnit?: string;
  weightUnit?: string;
}

/**
 * What is logged for one day, as the app's Today log card says it: the
 * app's own rules (lib/domain/logging/today_log.dart), not a TypeScript
 * copy of them.
 *
 * The entry goes in whole, its note included, because "is there a note"
 * is the domain's question to answer. Nothing of the note comes back: the
 * response carries `hasNote` and no text, and the schema strips any key it
 * does not name.
 */
export function todayLog(module: DomainModule, request: TodayLogRequest): TodayLog {
  return callDomain(module, 'todayLog', request, todayLogSchema);
}
