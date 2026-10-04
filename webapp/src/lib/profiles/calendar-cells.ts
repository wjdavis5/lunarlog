import { taxonomy } from '../day/categories';
import type { DayEntryRow } from '../schemas';
import type { ForecastDayCell } from '../../domain/schemas';

/**
 * The web month calendar's pure cell math (issue #1253) — the same grid
 * rules the app's `month_calendar.dart` applies, ported as data-in/data-out
 * functions so the React component only paints. The forecast decoration
 * itself is never computed here: it arrives from the domain facade's
 * `calendarForecast` (the app's own `forecastDayCells` output), and this
 * module only merges it with the logged rows per rendered day.
 */

/** Weeks start on Sunday, the app's `kFirstDayOfWeek` default (issue #160). */
export const FIRST_DAY_OF_WEEK_SUNDAY = 0;

/**
 * Forward month navigation may move at most this far past the current
 * month — the app's `kForwardMonthLimit = kForecastHorizonMonths` (12,
 * lib/domain/prediction/forecast.dart). Backward navigation is unbounded,
 * exactly like the app's epoch-indexed pages.
 */
export const FORWARD_MONTH_LIMIT = 12;

/**
 * At most this many symptom layers may be active at once — the app's
 * `kMaxSymptomLayers` (lib/domain/symptoms/symptom_layers.dart).
 */
export const MAX_SYMPTOM_LAYERS = 3;

/** `yyyy-MM-dd` for a JS local date triple. */
function isoOf(year: number, month1: number, day: number): string {
  return `${String(year).padStart(4, '0')}-${String(month1).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}

/**
 * Leading blank cells before day 1 of the month — the port of
 * `leadingBlanksFor` (lib/ui/logging/month_calendar.dart, issue #160), for
 * a Sunday-first grid. Layout filler with no meaning: the component never
 * renders interactive content for them, exactly like the app's
 * `ExcludeSemantics` blanks.
 */
export function leadingBlanksFor(year: number, month1: number): number {
  // JS getDay() is 0=Sunday..6=Saturday — already the Sunday-first offset.
  return new Date(year, month1 - 1, 1).getDay();
}

/** How many days `year`/`month1` has. */
export function daysInMonth(year: number, month1: number): number {
  return new Date(year, month1, 0).getDate();
}

/** The month's day cells as ISO dates, day 1 first. */
export function monthDayIsos(year: number, month1: number): string[] {
  return Array.from({ length: daysInMonth(year, month1) }, (_, i) =>
    isoOf(year, month1, i + 1),
  );
}

/**
 * The weekday header's single-letter initials, Sunday-first — the port of
 * `weekdayHeaderLabels` (locale-derived narrow initials, the same
 * Sunday-first identity ordering).
 */
export function weekdayInitials(locale: string = 'en'): string[] {
  const fmt = new Intl.DateTimeFormat(locale, { weekday: 'narrow', timeZone: 'UTC' });
  // 2023-10-01 is a Sunday; +i days walks the week from there.
  const sunday = Date.UTC(2023, 9, 1);
  return Array.from({ length: 7 }, (_, i) => fmt.format(new Date(sunday + i * 86_400_000)));
}

/**
 * Whether `year`/`month1` is within the forward navigation limit from
 * `today`'s month — the app's forwardmost-page rule
 * (`maxPageIndex = monthIndex(today) + kForwardMonthLimit`, so exactly
 * +12 months is still allowed). Backward navigation is unbounded.
 */
export function canNavigateForward(year: number, month1: number, today: Date): boolean {
  const target = year * 12 + (month1 - 1);
  const current = today.getFullYear() * 12 + today.getMonth();
  return target <= current + FORWARD_MONTH_LIMIT;
}

/** Month arithmetic for the nav buttons. */
export function shiftMonth(
  year: number,
  month1: number,
  delta: number,
): { year: number; month: number } {
  const zero = year * 12 + (month1 - 1) + delta;
  return { year: Math.floor(zero / 12), month: (((zero % 12) + 12) % 12) + 1 };
}

// ---------------------------------------------------------------------------
// Flow marks (the logged half of a day cell)
// ---------------------------------------------------------------------------

/**
 * How many flow marks a logged flow level draws — the port of
 * `_flowLevelMarkCount` (lib/ui/logging/month_calendar.dart): 1 for
 * spotting/none/not-bleeding, climbing to 5 for super heavy (which shares
 * heavy's ramp token, so the mark count is the distinguishing signal).
 */
export function flowMarkCount(flow: string): number {
  switch (flow) {
    case 'light':
      return 2;
    case 'medium':
      return 3;
    case 'heavy':
      return 4;
    case 'super_heavy':
      return 5;
    default:
      // none / spotting / not_bleeding / anything unrecognised.
      return 1;
  }
}

/** Whether a flow level renders as the single spotting-style ring. */
export function flowIsSpottingStyle(flow: string): boolean {
  return flow === 'none' || flow === 'spotting' || flow === 'not_bleeding';
}

// ---------------------------------------------------------------------------
// Symptom layers (the app's rankTagUsage / defaultLayerTags port)
// ---------------------------------------------------------------------------

/** One tag's usage count across a profile's entries. */
export interface TagUsage {
  code: string;
  count: number;
}

/**
 * Ranks tag usage across entries, most-used first, ties broken in
 * taxonomy order — the port of `rankTagUsage`
 * (lib/domain/symptoms/symptom_layers.dart). Tombstoned entries are
 * skipped, and positive "none today" assertions never rank (they are not
 * symptoms).
 */
export function rankTagUsage(entries: Pick<DayEntryRow, 'tags' | 'deleted_at'>[]): TagUsage[] {
  const counts = new Map<string, number>();
  for (const entry of entries) {
    if (entry.deleted_at !== null) continue;
    for (const tag of entry.tags) {
      if (taxonomy.positiveAssertionCodes.includes(tag)) continue;
      counts.set(tag, (counts.get(tag) ?? 0) + 1);
    }
  }
  const taxonomyOrder = new Map(taxonomy.tags.map((tag, i) => [tag.code, i]));
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || rankOf(taxonomyOrder, a[0]) - rankOf(taxonomyOrder, b[0]))
    .map(([code, count]) => ({ code, count }));
}

function rankOf(order: Map<string, number>, code: string): number {
  return order.get(code) ?? order.size;
}

/**
 * The default active layer set: the profile's most-used tags, at most
 * [max] — the port of `defaultLayerTags`. Recomputed until the operator
 * first toggles a layer; the selection itself is page memory only.
 */
export function defaultLayerTags(
  entries: Pick<DayEntryRow, 'tags' | 'deleted_at'>[],
  max: number = MAX_SYMPTOM_LAYERS,
): string[] {
  return rankTagUsage(entries)
    .slice(0, max)
    .map((usage) => usage.code);
}

/** Applies one layer toggle with the cap — the port of `_toggleLayer`'s rule. */
export function toggledLayers(current: string[], code: string): string[] | null {
  const selected = current.includes(code);
  if (!selected && current.length >= MAX_SYMPTOM_LAYERS) return null; // rejected
  return selected ? current.filter((c) => c !== code) : [...current, code];
}

// ---------------------------------------------------------------------------
// Per-day view
// ---------------------------------------------------------------------------

/** Everything a day cell paints, before catalogue lookup. */
export interface DayCellView {
  iso: string;
  dayNumber: number;
  isToday: boolean;
  /** The logged entry (live only) or null. */
  entry: DayEntryRow | null;
  flowMarkCount: number;
  spottingStyle: boolean;
  /** The active symptom layers this day's tags hit, in palette order. */
  layerHits: string[];
  /** The domain facade's forecast decoration for dates after today. */
  forecast: ForecastDayCell | null;
}

/**
 * Merges the logged row and the facade forecast cell for one rendered day.
 * A logged day suppresses its forecast decoration (the app's rule: the
 * past stays factual, and a logged "future" day shows what was logged).
 */
export function dayCellView(options: {
  iso: string;
  todayIso: string;
  entryByIso: Map<string, DayEntryRow>;
  forecastByIso: Map<string, ForecastDayCell>;
  activeLayers: string[];
}): DayCellView {
  const entry = options.entryByIso.get(options.iso) ?? null;
  const forecast =
    entry === null && options.iso > options.todayIso
      ? (options.forecastByIso.get(options.iso) ?? null)
      : null;
  const layerHits = options.activeLayers.filter(
    (code) => entry !== null && entry.deleted_at === null && entry.tags.includes(code),
  );
  return {
    iso: options.iso,
    dayNumber: Number(options.iso.slice(8, 10)),
    isToday: options.iso === options.todayIso,
    entry,
    flowMarkCount: entry !== null ? flowMarkCount(entry.flow) : 0,
    spottingStyle: entry !== null && flowIsSpottingStyle(entry.flow),
    layerHits,
    forecast,
  };
}

/**
 * The screen-reader label for one day cell — the port of
 * `dayCellSemanticLabel`'s composition: the date, the logged flow, and
 * the estimated-day fragment. Dates render via `Intl` by the component;
 * this returns the structural parts.
 */
export function dayCellSemantics(cell: DayCellView): {
  estimated: boolean;
  cycleDayNumber: number | null;
  pms: boolean;
  cramps: boolean;
  fertile: boolean;
} {
  return {
    estimated: cell.forecast !== null,
    cycleDayNumber: cell.forecast?.cycleDayNumber ?? null,
    pms: cell.forecast?.pmsBadge ?? false,
    cramps: cell.forecast?.crampsBadge ?? false,
    fertile: cell.forecast?.fertileWindow ?? false,
  };
}
