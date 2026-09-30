/**
 * The day editor's write path (issue #1254): pure functions that turn the
 * editor's state plus the currently-loaded day view into `sync_push`
 * payload rows, shaped exactly like the app's own codec emits them
 * (`lib/data/sync/row_codec.dart`) — the same client-generated ULID ids and
 * client-minted `updated_at` instants, so the server's last-writer-wins and
 * same-date merge rules treat the web as just another device.
 *
 * Nothing here talks to the network. `day-data.ts` executes the plan the
 * builder returns; the split is what makes every rule here unit-testable
 * and what lets the round-trip integration test drive the exact payload
 * shapes against a live local stack.
 */

import type {
  CycleOverrideRow,
  DayEntryRow,
  ObservationRow,
  ProfileGuardianRow,
  ProfileRow,
  ProfileModeRow,
} from '../schemas';
import { isValidUlid, newUlid } from '../ulid';
import type {
  CycleOverridePayload,
  DayEntryPayload,
  ObservationPayload,
  ProfileModePayload,
} from '../domain';
import { isIsoLocalDate, validateDayDate } from './day-entry-policy';
import { isValidBbt, isValidWeight, type BbtUnit, type WeightUnit } from './measurements';

/** The seven flow levels the server's `is_valid_flow_level` accepts. */
export const FLOW_LEVELS = [
  'none',
  'spotting',
  'not_bleeding',
  'light',
  'medium',
  'heavy',
  'super_heavy',
] as const;
export type FlowLevel = (typeof FLOW_LEVELS)[number];

/** The levels the flow chip row offers — the deprecated `spotting` alias is
 * not offered (spotting is the separate toggle + observation row, exactly
 * like the app's day sheet). */
export const SELECTABLE_FLOW_LEVELS: FlowLevel[] = [
  'none',
  'not_bleeding',
  'light',
  'medium',
  'heavy',
  'super_heavy',
];

/** The caller roles that may write day content (day_entries/observations). */
export type DayWriterRole = 'primary_guardian' | 'co_parent' | 'caregiver';
/** The roles that may additionally edit profile metadata (modes/overrides). */
const PROFILE_METADATA_ROLES = ['primary_guardian', 'co_parent'];

export type CallerRole = DayWriterRole | 'viewer';

/** Resolves the editor's role from the caller's membership row. */
export function resolveCallerRole(membership: ProfileGuardianRow | null): CallerRole {
  if (membership === null || membership.status !== 'accepted') return 'viewer';
  if (
    membership.role === 'primary_guardian' ||
    membership.role === 'co_parent' ||
    membership.role === 'caregiver'
  ) {
    return membership.role;
  }
  return 'viewer';
}

export function canWriteDayContent(role: CallerRole): boolean {
  return role !== 'viewer';
}

export function canEditProfileMetadata(role: CallerRole): boolean {
  return PROFILE_METADATA_ROLES.includes(role);
}

// ---------------------------------------------------------------------------
// Editor state
// ---------------------------------------------------------------------------

/** The lifecycle-mode values the server's `profile_modes_mode_check` accepts. */
export const LIFECYCLE_MODES = [
  'tracking',
  'conceive',
  'pregnancy',
  'perimenopause',
  'postpartum',
] as const;

/** What the day editor's controls hold. */
export interface DayEdit {
  flow: FlowLevel;
  flowExplicitlySet: boolean;
  spotting: boolean;
  pms: boolean;
  tags: string[];
  note: string | null;
  notePrivate: boolean;
  bbt: number | null;
  weight: number | null;
  /** `null` leaves the profile's life-stage mode untouched. */
  mode: (typeof LIFECYCLE_MODES)[number] | null;
  /** Cycle-correction flags for the edited date (`cycle_overrides`). */
  manualCycleStart: boolean;
  excludeCycleFromAverage: boolean;
}

/** The effective flow value a save persists (#247's rule, ported from
 * `resolveEffectiveFlow`): a spotting-only day asserts `not_bleeding`; a
 * day that loaded with spotting and an un-set flow reverts to `none` when
 * spotting is removed. */
export function resolveEffectiveFlow(edit: DayEdit, hadSpottingOnLoad: boolean): FlowLevel {
  if (edit.spotting && edit.flow === 'none') return 'not_bleeding';
  const revertToNone =
    hadSpottingOnLoad &&
    !edit.spotting &&
    !edit.flowExplicitlySet &&
    edit.flow === 'not_bleeding';
  return revertToNone ? 'none' : edit.flow;
}

/** What a fetch found for the day — the builder's read-side input. */
export interface LoadedDayView {
  profile: ProfileRow;
  entry: DayEntryRow | null;
  observations: ObservationRow[];
  mode: ProfileModeRow | null;
  cycleOverride: CycleOverrideRow | null;
  /** The caller's membership, or null when the caller has none. */
  membership: ProfileGuardianRow | null;
}

// ---------------------------------------------------------------------------
// Payload rows (the sync_push wire shapes)
// ---------------------------------------------------------------------------

/** One outgoing payload row: the data layer's push-batch shapes. */
export type JsonRow = Record<string, unknown>;

export interface SavePlan {
  dayEntries: DayEntryPayload[];
  observations: ObservationPayload[];
  profileModes: ProfileModePayload[];
  cycleOverrides: CycleOverridePayload[];
}

export type SavePlanField =
  'date' | 'entry' | 'flow' | 'tags' | 'note' | 'bbt' | 'weight' | 'mode' | 'cycleOverride';

/** A client-side validation failure, attributed to the field that owns it. */
export class DayValidationError extends Error {
  readonly field: SavePlanField;
  constructor(field: SavePlanField, message: string) {
    super(message);
    this.name = 'DayValidationError';
    this.field = field;
  }
}

/** A structural guard — a caller tried to build a plan it may not build. */
export class DayPermissionError extends Error {
  readonly field: SavePlanField;
  constructor(field: SavePlanField, message: string) {
    super(message);
    this.name = 'DayPermissionError';
    this.field = field;
  }
}

export interface BuildSavePlanArgs {
  profileId: string;
  dateIso: string;
  /** The caller's civil today (`yyyy-MM-dd`), read at the boundary — the
   * date-bounds policy never reads a clock itself. */
  todayIso: string;
  tz: string;
  edit: DayEdit;
  view: LoadedDayView;
  /** The save instant, ISO-8601 UTC — the LWW timestamp. */
  nowIso: string;
  /** ULID draws, injectable for deterministic tests; defaults to `generateUlid`. */
  newId?: () => string;
}

/** Server bounds (`is_valid_tags_array`): at most 32 strings, each ≤ 64 chars. */
export const MAX_TAGS_PER_DAY = 32;
export const MAX_TAG_LENGTH = 64;

/** Server bound (`day_entries_note_length_check`): 2000 characters. */
export const MAX_NOTE_LENGTH = 2000;

const BBT_CATEGORY = 'bbt';
const WEIGHT_CATEGORY = 'weight';
const SPOTTING_CATEGORY = 'spotting';

function allLiveObservations(view: LoadedDayView, category: string): ObservationRow[] {
  return view.observations.filter((o) => o.deleted_at === null && o.category === category);
}

/** The note-private flag a save may legitimately write (#849's rules):
 * chosen while the stored note is still empty, never cleared, never set
 * onto an already-shared note. Non-subjects echo whatever they loaded, so
 * a masked private note is never silently cleared by a guardian's save
 * (the server's mask-preserving guard stays the real backstop). */
function resolveNotePrivate(edit: DayEdit, view: LoadedDayView): boolean {
  const isSubject = view.membership?.is_subject === true;
  if (!isSubject && view.entry !== null) {
    return view.entry.note_private;
  }
  const storedNote = view.entry?.note ?? null;
  const storedPrivate = view.entry?.note_private ?? false;
  if (storedPrivate) return true; // never clearable
  if (storedNote !== null && storedNote !== '') return storedPrivate; // shared stays shared
  return edit.notePrivate;
}

/**
 * Builds the `sync_push` payload rows for one save. The plan carries only
 * the rows that actually changed; empty arrays are the common case and the
 * RPC's defaulted `[]` parameters accept them untouched.
 */
export function buildSavePlan(args: BuildSavePlanArgs): SavePlan {
  const { profileId, dateIso, todayIso, tz, edit, view, nowIso } = args;
  const nextId = args.newId ?? newUlid;
  if (!isValidUlid(profileId)) {
    throw new DayValidationError('date', 'profile id must be a ULID');
  }
  if (!isIsoLocalDate(dateIso)) {
    throw new DayValidationError('date', 'local_date must be yyyy-MM-dd');
  }
  // Date bounds are the caller's first gate (#1251's interim): the policy
  // module owns the rule, the builder refuses to emit an out-of-bounds row.
  const bounds = validateDayDate(dateIso, todayIso, view.profile.birth_year);
  if (!bounds.valid) {
    throw new DayValidationError(
      'date',
      bounds.violation === 'futureDate'
        ? 'day is more than one day in the future'
        : 'day is before the profile birth year',
    );
  }

  // The day-entry row: updated when one exists (same id — LWW), created
  // with a fresh ULID when it does not (the server's same-date resolver
  // handles the collision case where a phone created one first).
  const role = resolveCallerRole(view.membership);
  if (!canWriteDayContent(role)) {
    throw new DayPermissionError('date', 'a viewer cannot write day content');
  }
  const entryId = view.entry?.id ?? nextId();
  const effectiveFlow = resolveEffectiveFlow(edit, hadSpottingOnLoad(view));
  // Tags: the server's `is_valid_tags_array` rejects a payload row past
  // these bounds, so they are validated here, before anything is emitted.
  if (edit.tags.length > MAX_TAGS_PER_DAY) {
    throw new DayValidationError('tags', `more than ${MAX_TAGS_PER_DAY} tags`);
  }
  for (const tag of edit.tags) {
    if (tag.length > MAX_TAG_LENGTH) {
      throw new DayValidationError('tags', 'a tag is longer than 64 characters');
    }
  }
  // Note: the server's `day_entries_note_length_check` rejects past 2000.
  const note = edit.note === '' ? null : edit.note;
  if (note !== null && note.length > MAX_NOTE_LENGTH) {
    throw new DayValidationError('note', `note longer than ${MAX_NOTE_LENGTH} characters`);
  }
  const dayEntry: DayEntryPayload = {
    id: entryId,
    profile_id: profileId,
    local_date: dateIso,
    tz,
    flow: effectiveFlow,
    tags: [...edit.tags],
    note,
    note_private: resolveNotePrivate(edit, view),
    pms: edit.pms,
    source: view.entry?.source ?? 'manual',
    ...(view.entry?.source_id !== null && view.entry?.source_id !== undefined
      ? { source_id: view.entry.source_id }
      : {}),
    updated_at: nowIso,
  };

  if (FLOW_LEVELS.includes(effectiveFlow) === false) {
    throw new DayValidationError('flow', 'unknown flow level');
  }

  const observations: ObservationPayload[] = [];
  const observationIds = observationIdsFor(nextId);

  // Spotting (#247): a `category: 'spotting'` observation row exists
  // exactly when the toggle is on — created when missing, every existing
  // row tombstoned when off.
  const existingSpotting = allLiveObservations(view, SPOTTING_CATEGORY);
  if (edit.spotting && existingSpotting.length === 0) {
    observations.push(
      liveObservation({
        id: observationIds.next(),
        dayEntryId: entryId,
        profileId,
        dateIso,
        tz,
        category: SPOTTING_CATEGORY,
        code: 'spotting',
        nowIso,
      }),
    );
  } else if (!edit.spotting) {
    for (const row of existingSpotting) {
      observations.push(tombstoneObservation(row, nowIso));
    }
  }

  // BBT / weight (#457): one manual measurement row per category — updated
  // in place when the value changes, tombstoned when cleared.
  const bbtUnit = view.profile.bbt_unit as BbtUnit;
  const weightUnit = view.profile.weight_unit as WeightUnit;
  if (edit.bbt !== null) {
    if (!isValidBbt(edit.bbt, bbtUnit)) {
      throw new DayValidationError('bbt', 'BBT outside the sanity range');
    }
    observations.push(
      ...upsertMeasurement(
        view,
        BBT_CATEGORY,
        entryId,
        profileId,
        dateIso,
        tz,
        edit.bbt,
        bbtUnit,
        nowIso,
        observationIds.next,
      ),
    );
  } else {
    for (const row of manualRows(view, BBT_CATEGORY)) {
      observations.push(tombstoneObservation(row, nowIso));
    }
  }
  if (edit.weight !== null) {
    if (!isValidWeight(edit.weight, weightUnit)) {
      throw new DayValidationError('weight', 'weight outside the sanity range');
    }
    observations.push(
      ...upsertMeasurement(
        view,
        WEIGHT_CATEGORY,
        entryId,
        profileId,
        dateIso,
        tz,
        edit.weight,
        weightUnit,
        nowIso,
        observationIds.next,
      ),
    );
  } else {
    for (const row of manualRows(view, WEIGHT_CATEGORY)) {
      observations.push(tombstoneObservation(row, nowIso));
    }
  }

  // Life-stage mode (#188): profile metadata — primary_guardian/co_parent
  // only, exactly like the server's own ladder. Emitted only when changed;
  // the server's per-key containment guards preserve every field this
  // payload omits.
  const profileModes: ProfileModePayload[] = [];
  if (edit.mode !== null && edit.mode !== view.mode?.mode) {
    if (!canEditProfileMetadata(role)) {
      throw new DayPermissionError('mode', `${role} cannot edit the life-stage mode`);
    }
    profileModes.push({
      profile_id: profileId,
      mode: edit.mode,
      mode_started_on: dateIso,
      updated_at: nowIso,
    });
  }

  // Cycle correction (#188): the override row keyed on the edited date.
  const cycleOverrides: CycleOverridePayload[] = [];
  const wantsOverride = edit.manualCycleStart || edit.excludeCycleFromAverage;
  const existing = view.cycleOverride;
  const overrideUnchanged =
    existing !== null &&
    existing.manual_start === edit.manualCycleStart &&
    existing.excluded_from_average === edit.excludeCycleFromAverage;
  if (!overrideUnchanged) {
    if (wantsOverride) {
      if (!canEditProfileMetadata(role)) {
        throw new DayPermissionError('cycleOverride', `${role} cannot edit cycle corrections`);
      }
      cycleOverrides.push({
        id: existing?.id ?? nextId(),
        profile_id: profileId,
        cycle_start_date: dateIso,
        excluded_from_average: edit.excludeCycleFromAverage,
        manual_start: edit.manualCycleStart,
        updated_at: nowIso,
      });
    } else if (existing !== null && existing.deleted_at === null) {
      if (!canEditProfileMetadata(role)) {
        throw new DayPermissionError('cycleOverride', `${role} cannot edit cycle corrections`);
      }
      // Tombstones carry no payload; the server clears the flags.
      cycleOverrides.push({
        id: existing.id,
        profile_id: profileId,
        cycle_start_date: dateIso,
        updated_at: nowIso,
        deleted_at: nowIso,
      });
    }
  }

  return {
    dayEntries: [dayEntry],
    observations: observations as ObservationPayload[],
    profileModes: profileModes as ProfileModePayload[],
    cycleOverrides: cycleOverrides as CycleOverridePayload[],
  };
}

function hadSpottingOnLoad(view: LoadedDayView): boolean {
  return (
    view.entry !== null &&
    (allLiveObservations(view, SPOTTING_CATEGORY).length > 0 ||
      // A spotting-flagged legacy row (flow = 'spotting') also counts as
      // loaded-with-spotting, matching the app's `hadSpottingOnLoad` seed.
      view.entry.flow === 'spotting')
  );
}

function manualRows(view: LoadedDayView, category: string): ObservationRow[] {
  return view.observations.filter(
    (o) => o.deleted_at === null && o.category === category && o.source === 'manual',
  );
}

function upsertMeasurement(
  view: LoadedDayView,
  category: string,
  entryId: string,
  profileId: string,
  dateIso: string,
  tz: string,
  value: number,
  unit: string,
  nowIso: string,
  nextId: () => string,
): ObservationPayload[] {
  const existing = manualRows(view, category);
  if (existing.length > 0) {
    const row = existing[0];
    if (row.value_num === value && row.unit === unit) return [];
    return [
      {
        id: row.id,
        day_entry_id: entryId,
        profile_id: profileId,
        local_date: dateIso,
        tz,
        category,
        value_num: value,
        unit,
        source: row.source,
        updated_at: nowIso,
      },
    ];
  }
  return [
    liveObservation({
      id: nextId(),
      dayEntryId: entryId,
      profileId,
      dateIso,
      tz,
      category,
      valueNum: value,
      unit,
      nowIso,
    }),
  ];
}

interface LiveObservationArgs {
  id: string;
  dayEntryId: string;
  profileId: string;
  dateIso: string;
  tz: string;
  category: string;
  code?: string;
  valueNum?: number;
  unit?: string;
  nowIso: string;
}

function liveObservation(args: LiveObservationArgs): ObservationPayload {
  return {
    id: args.id,
    day_entry_id: args.dayEntryId,
    profile_id: args.profileId,
    local_date: args.dateIso,
    tz: args.tz,
    category: args.category,
    ...(args.code !== undefined ? { code: args.code } : {}),
    ...(args.valueNum !== undefined ? { value_num: args.valueNum } : {}),
    ...(args.unit !== undefined ? { unit: args.unit } : {}),
    source: 'manual',
    updated_at: args.nowIso,
  };
}

function tombstoneObservation(row: ObservationRow, nowIso: string): ObservationPayload {
  return {
    id: row.id,
    day_entry_id: row.day_entry_id,
    profile_id: row.profile_id,
    local_date: row.local_date,
    tz: row.tz,
    source: row.source,
    updated_at: nowIso,
    deleted_at: nowIso,
  };
}

/** Deterministic id draws per plan (tests assert exact payloads). */
function observationIdsFor(nextId: () => string): { next: () => string } {
  let drawn = 0;
  return {
    next: () => {
      drawn++;
      if (drawn > 16) throw new Error('too many observation ids drawn for one save');
      return nextId();
    },
  };
}
