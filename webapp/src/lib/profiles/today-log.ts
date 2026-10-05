import {
  todayLog,
  type DomainModule,
  type TodayLogCustomTagJson,
  type TodayLogObservationJson,
  type TodayLogRequest,
} from '../../domain/client';
import type { TodayLog, TodayLogFlow } from '../../domain/schemas';
import { LABEL_COLON, LIST_SEPARATOR } from '../../i18n/punctuation';
import type { TFunction } from '../../i18n/t';
import { bbtUnitSymbol, formatMeasurementValue, weightUnitSymbol } from '../day/measurements';
import type { SyncedData } from '../domain';
import type { DayEntryRow } from '../schemas';
import { liveEntryToDomainJson, type GuardianLens } from './profile-views';

/**
 * What is logged today for one profile, for the home's "Logged today" card
 * and its Log today / Edit today button (the browser version of issue
 * 1489's Today log card).
 *
 * Nothing here decides what the card says. This file picks today's rows
 * out of the synced snapshot the page already holds and hands them to the
 * compiled domain module, whose `todayLog` answers with the app's own
 * rules (lib/domain/logging/today_log.dart): whether anything is logged,
 * the flow line, which tags are named and which are only counted, and the
 * readings. No request is made and nothing is kept: it is a pure function
 * of the snapshot and the day.
 */

/**
 * The profile's live entry dated `todayIso`, or null. The last one wins if
 * the snapshot ever holds two, the same choice the home's calendar makes
 * for the same day.
 */
export function liveEntryOn(
  synced: SyncedData,
  profileId: string,
  todayIso: string,
): DayEntryRow | null {
  let found: DayEntryRow | null = null;
  for (const row of synced.day_entries) {
    if (row.profile_id !== profileId || row.deleted_at !== null) continue;
    if (row.local_date === todayIso) found = row;
  }
  return found;
}

/**
 * The `todayLog` request for one profile's day: the entry, the live
 * observations attached to it (spotting and the temperature and weight
 * readings are observations, not entry columns), the profile's own tag
 * names, and its display units.
 *
 * The entry carries its note, because whether a note exists is the
 * domain's question. This request is the only place the note is put, and
 * it goes nowhere but into the call ([readTodayLog]).
 */
export function todayLogRequest(
  synced: SyncedData,
  profileId: string,
  todayIso: string,
): TodayLogRequest {
  const entry = liveEntryOn(synced, profileId, todayIso);
  if (entry === null) return { entry: null };

  const observations: TodayLogObservationJson[] = [];
  for (const row of synced.observations) {
    if (row.day_entry_id !== entry.id || row.deleted_at !== null) continue;
    observations.push({
      dayEntryId: row.day_entry_id,
      category: row.category,
      valueNum: row.value_num,
      unit: row.unit,
      source: row.source,
    });
  }

  const customTags: TodayLogCustomTagJson[] = [];
  for (const row of synced.profile_tag_registry) {
    if (row.profile_id !== profileId || row.deleted_at !== null) continue;
    customTags.push({ code: row.code, displayName: row.display_name });
  }

  const profile = synced.profiles.find((row) => row.id === profileId);
  const request: TodayLogRequest = {
    entry: liveEntryToDomainJson(entry),
    observations,
    customTags,
  };
  if (profile?.bbt_unit !== undefined) request.bbtUnit = profile.bbt_unit;
  if (profile?.weight_unit !== undefined) request.weightUnit = profile.weight_unit;
  return request;
}

/**
 * Asks the domain module what is logged today for `profileId`. Throws what
 * the module throws (a missing module, a refused request); the page turns
 * that into "no card" rather than a wrong one.
 */
export function readTodayLog(
  module: DomainModule,
  synced: SyncedData,
  profileId: string,
  todayIso: string,
): TodayLog {
  return todayLog(module, todayLogRequest(synced, profileId, todayIso));
}

/** What the home shows of today's log to the person looking, if anything. */
export type TodayLogCardView =
  { kind: 'none' } | { kind: 'empty' } | { kind: 'logged'; log: TodayLog; canEdit: boolean };

/**
 * Who sees the card, and which one (the app's `_todayLogCard` and its lens
 * choice in lib/ui/overview/overview_panel.dart):
 *
 * - a guardian sees no card: a guardian's front page says what is needed
 *   of them, never what was logged (issue 850);
 * - someone who cannot log sees the summary without Edit, and no card at
 *   all when nothing is logged, since "Nothing logged today yet" points at
 *   a button they are not offered;
 * - everyone else sees the summary with Edit, or the quiet empty line.
 *
 * `log` is null when the module could not answer; that is no card.
 */
export function todayLogCardView(options: {
  log: TodayLog | null;
  lens: GuardianLens;
  canLog: boolean;
}): TodayLogCardView {
  const { log } = options;
  if (log === null || options.lens === 'guardian') return { kind: 'none' };
  if (log.hasContent) return { kind: 'logged', log, canEdit: options.canLog };
  return options.canLog ? { kind: 'empty' } : { kind: 'none' };
}

// ---------------------------------------------------------------------------
// The card's words
// ---------------------------------------------------------------------------

/**
 * The flow line in the reader's words, as the app's card says it: a bleed
 * level reads "{level} flow" (the calendar's own phrase), spotting reads
 * "Spotting", and an explicit not-bleeding reads "Not bleeding". Which of
 * them the day is was the domain's decision; this only names it.
 */
export function todayLogFlowLine(flow: TodayLogFlow, t: TFunction): string {
  switch (flow) {
    case 'light':
      return t('calendarCellFlowState', { level: t('flowLevelLight') });
    case 'medium':
      return t('calendarCellFlowState', { level: t('flowLevelMedium') });
    case 'heavy':
      return t('calendarCellFlowState', { level: t('flowLevelHeavy') });
    case 'super_heavy':
      return t('calendarCellFlowState', { level: t('flowLevelSuperHeavy') });
    case 'spotting':
      return t('flowLevelSpotting');
    case 'not_bleeding':
      return t('flowLevelNotBleeding');
  }
}

/**
 * The tags line: the labels the domain chose to name, then "and N more"
 * for the ones it only counted. A day whose tags are all counted reads
 * "1 other entry". The labels and the count arrive ready; nothing here
 * knows a tag code.
 */
function todayLogTagsLine(log: TodayLog, t: TFunction): string {
  if (log.tags.length === 0) return t('todayLogOtherEntries', { count: log.moreTagCount });
  const shown = log.tags.join(LIST_SEPARATOR);
  return log.moreTagCount > 0
    ? `${shown} ${t('todayLogMoreTags', { count: log.moreTagCount })}`
    : shown;
}

/** A reading under the day editor's field label: "BBT (°C): 36.7". */
function readingLine(label: string, value: number): string {
  return `${label}${LABEL_COLON}${formatMeasurementValue(value)}`;
}

/**
 * The card's lines for a day with something logged, top to bottom, in the
 * app's order (`todayLogSummaryOf` and `todayLogLines`,
 * lib/ui/components/today_log_card.dart): the flow, the tags, the PMS
 * marker, the temperature and the weight, then "Note added".
 *
 * The note is one fixed line. `TodayLog` has no field that could hold its
 * text.
 */
export function todayLogLines(log: TodayLog, t: TFunction): string[] {
  const lines: string[] = [];
  if (log.flow !== null) lines.push(todayLogFlowLine(log.flow, t));
  if (log.tags.length > 0 || log.moreTagCount > 0) lines.push(todayLogTagsLine(log, t));
  if (log.pms) lines.push(t('daySheetPmsChip'));
  if (log.bbt !== null) {
    lines.push(
      readingLine(
        t('daySheetBbtFieldLabel', { unit: bbtUnitSymbol(log.bbt.unit) }),
        log.bbt.value,
      ),
    );
  }
  if (log.weight !== null) {
    lines.push(
      readingLine(
        t('daySheetWeightFieldLabel', { unit: weightUnitSymbol(log.weight.unit) }),
        log.weight.value,
      ),
    );
  }
  if (log.hasNote) lines.push(t('todayLogNoteAdded'));
  return lines;
}
