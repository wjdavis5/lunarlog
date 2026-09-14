/// Pure day-sheet reconciliation rules (issue #601, moved out of
/// `lib/ui/logging/day_sheet.dart`'s `_DaySheetState`): the flow/spotting
/// interplay (#247) and the spotting/pain observation-row mutations an
/// autosave commits alongside the entry itself. Pure Dart (R14/R16) — no
/// Flutter, no repository access, no wall-clock read (issue #304's clock
/// seam audit: every timestamp is an explicit [updatedAt] parameter, never
/// `DateTime.now()` read in here).
///
/// [resolveEffectiveFlow] and [computeObservationMutations] are exact,
/// behaviour-preserving extractions of `_resolveEffectiveFlow` and
/// `_computeSpottingMutations`/`_computePainMutations` — every doc comment
/// below that explains a rule carries the same reasoning the widget-private
/// versions did, since the rules themselves did not change, only where they
/// live.
library;

import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../models/observation.dart';

/// The `flow` value an autosave actually writes (#247): selecting
/// "Spotting" on a day with no other flow chosen is still a positive fact
/// about the day, not "unlogged" — it is raised to [FlowLevel.notBleeding].
/// A day already logged at a real bleed level keeps that level; spotting is
/// recorded alongside it as its own observation, never overwriting a
/// chosen flow.
///
/// Review fix (blocking, carried over verbatim): the mirror image —
/// unchecking Spotting on a day whose only signal *was* spotting reverts
/// [flow] back to [FlowLevel.none] rather than leaving the previously
/// -derived [FlowLevel.notBleeding] behind as if it had been asserted on
/// purpose. Guarded to fire only when the user never touched a flow chip
/// this session ([flowExplicitlySet]) — tapping "Not bleeding" (even
/// alongside spotting) is a deliberate, independent assertion that
/// survives unchecking spotting.
///
/// * [spotting] — the standalone Spotting toggle's current value.
/// * [flow] — the flow chip row's current selection.
/// * [hadSpottingOnLoad] — true once the day was found to already carry
///   spotting when the sheet loaded (kept true even after unchecking, so
///   this function can tell "spotting was just removed" apart from
///   "spotting was never on this session").
/// * [flowExplicitlySet] — true once the operator tapped any flow chip this
///   session (including re-tapping the already-selected one).
FlowLevel resolveEffectiveFlow({
  required bool spotting,
  required FlowLevel flow,
  required bool hadSpottingOnLoad,
  required bool flowExplicitlySet,
}) {
  if (spotting && flow == FlowLevel.none) return FlowLevel.notBleeding;
  final revertToNone = hadSpottingOnLoad &&
      !spotting &&
      !flowExplicitlySet &&
      flow == FlowLevel.notBleeding;
  return revertToNone ? FlowLevel.none : flow;
}

/// One category's upserts and deletes, computed against a target day
/// entry's already-persisted observation rows.
class ObservationMutations {
  const ObservationMutations({
    this.toUpsert = const [],
    this.toDelete = const [],
  });

  final List<Observation> toUpsert;
  final List<String> toDelete;

  /// Concatenates [a] and [b]'s upserts/deletes — used to combine the
  /// spotting and pain-intensity mutation sets the same way
  /// `_computeObservationMutations` accumulated into one shared pair of
  /// lists.
  static ObservationMutations merge(
    ObservationMutations a,
    ObservationMutations b,
  ) =>
      ObservationMutations(
        toUpsert: [...a.toUpsert, ...b.toUpsert],
        toDelete: [...a.toDelete, ...b.toDelete],
      );
}

/// The spotting observation row's upsert/delete (issue #247): a
/// `category: 'spotting'` row exists exactly when [spotting] is true —
/// created if missing, removed (every existing spotting row) if unchecked.
/// Never updates an existing spotting row in place (there is nothing on it
/// to change besides its existence).
ObservationMutations computeSpottingMutations({
  required List<Observation> existingObservations,
  required bool spotting,
  required String targetDayEntryId,
  required String profileId,
  required LocalDate date,
  required String tz,
  required DateTime updatedAt,
}) {
  final existingSpotting = [
    for (final o in existingObservations)
      if (o.category == 'spotting') o,
  ];
  if (!spotting) {
    return ObservationMutations(
      toDelete: [for (final o in existingSpotting) o.id],
    );
  }
  if (existingSpotting.isNotEmpty) return const ObservationMutations();
  return ObservationMutations(
    toUpsert: [
      Observation(
        id: '',
        dayEntryId: targetDayEntryId,
        profileId: profileId,
        localDate: date,
        tz: tz,
        category: 'spotting',
        code: 'spotting',
        updatedAt: updatedAt,
      ),
    ],
  );
}

/// The graded pain-intensity observation rows' upserts/deletes (issue
/// #256): one `category: 'pain'` row per taxonomy code carrying an entry in
/// [painIntensity] — created or updated to the chosen grade, or deleted
/// when the entry's value is `null` (the operator explicitly cleared a
/// previously recorded grade; ungraded means "no severity recorded", never
/// "low"). A code absent from [painIntensity] entirely is left untouched.
/// When several already-persisted rows share the same code (possible in
/// imported data), only the first is ever considered for an update; the
/// day sheet's own local writes resolve one row per code so this never
/// diverges for entries this app created.
ObservationMutations computePainMutations({
  required List<Observation> existingObservations,
  required Map<String, int?> painIntensity,
  required String targetDayEntryId,
  required String profileId,
  required LocalDate date,
  required String tz,
  required DateTime updatedAt,
}) {
  if (painIntensity.isEmpty) return const ObservationMutations();
  final existingPain = [
    for (final o in existingObservations)
      if (o.category == 'pain') o,
  ];
  final toUpsert = <Observation>[];
  final toDelete = <String>[];
  for (final entry in painIntensity.entries) {
    final intensity = entry.value;
    final matchingPainRows = [
      for (final o in existingPain)
        if (o.code == entry.key) o,
    ];
    if (intensity == null) {
      for (final o in matchingPainRows) {
        if (o.intensity != null) toDelete.add(o.id);
      }
      continue;
    }
    if (matchingPainRows.isNotEmpty) {
      final row = matchingPainRows.first;
      if (row.intensity != intensity) {
        toUpsert.add(row.copyWith(intensity: intensity, updatedAt: updatedAt));
      }
      continue;
    }
    toUpsert.add(
      Observation(
        id: '',
        dayEntryId: targetDayEntryId,
        profileId: profileId,
        localDate: date,
        tz: tz,
        category: 'pain',
        code: entry.key,
        intensity: intensity,
        updatedAt: updatedAt,
      ),
    );
  }
  return ObservationMutations(toUpsert: toUpsert, toDelete: toDelete);
}

/// One numeric measurement row's upsert/delete/no-op (Issue #457's day-sheet
/// entry for the `bbt`/`weight` categories #240/#255 already store): unlike
/// [computeSpottingMutations] (existence-only) or [computePainMutations]
/// (keyed by code), a numeric measurement is a single (category, no code)
/// row per day whose *value* is what changes.
///
/// [value] is `null` for "the field is empty" — the operator cleared it, so
/// any existing manual row is tombstoned (mirrors [computeSpottingMutations]'
/// unchecked case). A non-null [value] upserts: unchanged from the existing
/// row (same value, unit, and [excluded] flag) is a genuine no-op — every
/// other autosave already writes the surrounding `DayEntry` unconditionally,
/// so this only avoids a pointless `observations` write when the operator's
/// edit touched something else on the day.
///
/// Only ever matches an existing row whose `source` is
/// [ObservationSource.manual] (never a wearable/import/health-platform
/// row) — the same same-date source discipline
/// `supabase/migrations/20260914020000_numeric_measurement_units.sql` item
/// 3 documents server-side: a manually-entered BBT/weight value must never
/// overwrite or merge with a value some other source recorded for the same
/// day. A day with no existing manual row for [category] always creates a
/// fresh one rather than adopting a same-category row from another source.
ObservationMutations computeMeasurementMutations({
  required List<Observation> existingObservations,
  required String category,
  required double? value,
  required String unit,
  required bool excluded,
  required String targetDayEntryId,
  required String profileId,
  required LocalDate date,
  required String tz,
  required DateTime updatedAt,
}) {
  final matching = [
    for (final o in existingObservations)
      if (o.category == category && o.source == ObservationSource.manual) o,
  ];
  if (value == null) {
    return ObservationMutations(
      toDelete: [for (final o in matching) o.id],
    );
  }
  if (matching.isNotEmpty) {
    final row = matching.first;
    final unchanged = row.valueNum == value &&
        row.unit == unit &&
        row.excluded == excluded;
    if (unchanged) return const ObservationMutations();
    return ObservationMutations(
      toUpsert: [
        row.copyWith(
          valueNum: value,
          unit: unit,
          excluded: excluded,
          updatedAt: updatedAt,
        ),
      ],
    );
  }
  return ObservationMutations(
    toUpsert: [
      Observation(
        id: '',
        dayEntryId: targetDayEntryId,
        profileId: profileId,
        localDate: date,
        tz: tz,
        category: category,
        valueNum: value,
        unit: unit,
        excluded: excluded,
        updatedAt: updatedAt,
      ),
    ],
  );
}

/// Combines [computeSpottingMutations], [computePainMutations], and (Issue
/// #457) the BBT/weight [computeMeasurementMutations] calls into the one
/// pair of lists an autosave write commits alongside the entry (issue #471's
/// atomic write) — the pure half of `_computeObservationMutations`, which
/// also does the (impure) repository fetch of [existingObservations] and so
/// stays in `lib/ui/logging/day_sheet.dart`.
///
/// The six BBT/weight parameters default to "no measurement" (`null` value,
/// the canonical default unit, not excluded) so every pre-#457 caller —
/// including this file's own earlier tests — keeps compiling and behaving
/// identically without passing them.
ObservationMutations computeObservationMutations({
  required List<Observation> existingObservations,
  required bool spotting,
  required Map<String, int?> painIntensity,
  double? bbtValue,
  String bbtUnit = 'celsius',
  bool bbtExcluded = false,
  double? weightValue,
  String weightUnit = 'kg',
  bool weightExcluded = false,
  required String targetDayEntryId,
  required String profileId,
  required LocalDate date,
  required String tz,
  required DateTime updatedAt,
}) =>
    ObservationMutations.merge(
      ObservationMutations.merge(
        computeSpottingMutations(
          existingObservations: existingObservations,
          spotting: spotting,
          targetDayEntryId: targetDayEntryId,
          profileId: profileId,
          date: date,
          tz: tz,
          updatedAt: updatedAt,
        ),
        computePainMutations(
          existingObservations: existingObservations,
          painIntensity: painIntensity,
          targetDayEntryId: targetDayEntryId,
          profileId: profileId,
          date: date,
          tz: tz,
          updatedAt: updatedAt,
        ),
      ),
      ObservationMutations.merge(
        computeMeasurementMutations(
          existingObservations: existingObservations,
          category: 'bbt',
          value: bbtValue,
          unit: bbtUnit,
          excluded: bbtExcluded,
          targetDayEntryId: targetDayEntryId,
          profileId: profileId,
          date: date,
          tz: tz,
          updatedAt: updatedAt,
        ),
        computeMeasurementMutations(
          existingObservations: existingObservations,
          category: 'weight',
          value: weightValue,
          unit: weightUnit,
          excluded: weightExcluded,
          targetDayEntryId: targetDayEntryId,
          profileId: profileId,
          date: date,
          tz: tz,
          updatedAt: updatedAt,
        ),
      ),
    );

/// Reduces [observations] to one highest graded pain intensity per taxonomy
/// code (issue #642 review, CRAP gate split of
/// `_DaySheetState._loadExistingPainIntensity`): the pure decode/merge half
/// — filtering to live `category: 'pain'` rows that carry both a
/// [Observation.code] and a non-null [Observation.intensity], then, when
/// several already-persisted rows share one code (possible in imported
/// data; the day sheet's own local writes resolve one row per code so this
/// never diverges for entries this app created), keeping the highest
/// intensity — the severity reading a caregiver alert would act on. A code
/// with no graded row at all is simply absent from the result, never a
/// `null` entry.
Map<String, int> gradedPainIntensitiesFrom(List<Observation> observations) {
  final result = <String, int>{};
  for (final observation in observations) {
    if (observation.category != 'pain') continue;
    final code = observation.code;
    final intensity = observation.intensity;
    if (code == null || intensity == null) continue;
    final current = result[code];
    if (current == null || intensity > current) {
      result[code] = intensity;
    }
  }
  return result;
}
