/// Date-range selection for the clinical (FHIR) export flow (Issue #459).
///
/// `buildFhirDocumentBundle` (`lib/domain/export/fhir_bundle.dart`) has
/// always accepted whatever pre-filtered `dayEntries`/`observations` a
/// caller passes it — see that file's own doc comment: "expected
/// pre-filtered to [profile]'s own id and whatever date range the caller
/// wants exported". This file is the caller-side piece
/// `docs/clinical/fhir-export.md`'s former "No date range yet" section
/// flagged as still missing: resolving a preset (or an explicit custom
/// start/end) to a concrete [FhirExportRange] and filtering entries/
/// observations to it before they ever reach the builder. The builder
/// itself needs no change.
library;

import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../models/observation.dart';
import '../prediction/cycle_history.dart';

/// The presets `ExportRangePickerSheet` offers, in display order. [custom]
/// carries its own explicit start/end rather than one derived from cycle
/// history or a fixed calendar window.
enum FhirExportRangePreset {
  last3Cycles,
  last6Cycles,
  last12Cycles,
  last12Months,
  everything,
  custom,
}

/// A resolved, concrete date range. [start]/[end] are both inclusive civil
/// dates and both nullable — null on either side means "no bound" on that
/// side: an [everything] range has both null; every cycle-count and
/// last-12-months preset leaves [end] null on purpose, so the range always
/// reaches through the newest data, an in-progress (open) cycle included.
class FhirExportRange {
  const FhirExportRange({required this.preset, this.start, this.end});

  final FhirExportRangePreset preset;
  final LocalDate? start;
  final LocalDate? end;

  /// The whole-history default every export used before this issue —
  /// still available as its own preset, distinct from "no lower bound
  /// because fewer than N cycles exist yet" ([fhirExportRangeForCycleCount]
  /// degrading the same way).
  static const FhirExportRange everything = FhirExportRange(
    preset: FhirExportRangePreset.everything,
  );

  bool includes(LocalDate date) {
    final lowerBound = start;
    if (lowerBound != null && date.isBefore(lowerBound)) return false;
    final upperBound = end;
    if (upperBound != null && date.isAfter(upperBound)) return false;
    return true;
  }

  /// [entries] narrowed to dates this range [includes], order preserved.
  List<DayEntry> filterEntries(List<DayEntry> entries) => [
    for (final entry in entries)
      if (includes(entry.localDate)) entry,
  ];

  /// [observations] narrowed to dates this range [includes], order
  /// preserved.
  List<Observation> filterObservations(List<Observation> observations) => [
    for (final observation in observations)
      if (includes(observation.localDate)) observation,
  ];
}

/// The export tile's opening default (#459 AC1): the six most-recent
/// completed cycles — see [fhirExportRangeForCycleCount].
FhirExportRange defaultFhirExportRange({
  required List<DayEntry> entries,
  required LocalDate today,
}) => fhirExportRangeForCycleCount(
  cycleCount: 6,
  preset: FhirExportRangePreset.last6Cycles,
  entries: entries,
  today: today,
);

/// Resolves a "last N completed cycles" preset to a concrete range:
/// [start] is the Nth-most-recent completed cycle's episode start, derived
/// via `lib/domain/episodes/episodes.dart` through the same
/// [deriveCycleHistoryFromEntries] the history list and predictions
/// already use — never a re-derivation with its own rules. [end] stays
/// null (see [FhirExportRange]'s doc comment). Fewer than [cycleCount]
/// completed cycles in the whole history resolves to "no lower bound"
/// (everything logged so far) rather than an empty or partial range.
FhirExportRange fhirExportRangeForCycleCount({
  required int cycleCount,
  required FhirExportRangePreset preset,
  required List<DayEntry> entries,
  required LocalDate today,
}) {
  final history = deriveCycleHistoryFromEntries(entries: entries, today: today);
  // `items` is reverse-chronological with the open cycle (if any) pinned
  // first (cycle_history.dart's own doc comment); every other item is a
  // completed cycle, already newest-first.
  final completed = [
    for (final item in history.items)
      if (!item.isOpen) item,
  ];
  if (completed.length < cycleCount) {
    return FhirExportRange(preset: preset);
  }
  return FhirExportRange(
    preset: preset,
    start: completed[cycleCount - 1].start,
  );
}

/// Resolves the "last 12 months" preset: [start] is exactly 12 calendar
/// months before [today] (matching a clinician's own "the past year"
/// expectation rather than a fixed 365-day window); [end] stays null for
/// the same "always include the newest data" reason the cycle-count
/// presets leave it null.
FhirExportRange fhirExportRangeForLast12Months(LocalDate today) =>
    FhirExportRange(
      preset: FhirExportRangePreset.last12Months,
      start: today.addMonths(-12),
    );

/// A custom operator-chosen range: both [start] and [end] are required and
/// inclusive (unlike the presets, which always leave [end] open) — the
/// picker's custom step collects a concrete start and end date, not a
/// half-open window.
FhirExportRange customFhirExportRange({
  required LocalDate start,
  required LocalDate end,
}) => FhirExportRange(
  preset: FhirExportRangePreset.custom,
  start: start,
  end: end,
);

/// The cycle count each cycle-based [FhirExportRangePreset] resolves to —
/// shared between [resolveFhirExportRangePreset] and anything else (e.g. a
/// future PDF export reusing the same picker, per #459's "Related") that
/// needs the mapping without duplicating it.
const Map<FhirExportRangePreset, int> kFhirExportRangeCycleCounts = {
  FhirExportRangePreset.last3Cycles: 3,
  FhirExportRangePreset.last6Cycles: 6,
  FhirExportRangePreset.last12Cycles: 12,
};

/// Resolves any [preset] to a concrete [FhirExportRange] — the one place
/// that dispatches on [FhirExportRangePreset], so `ExportRangePickerSheet`
/// itself stays a thin caller. [customStart]/[customEnd] are required only
/// for [FhirExportRangePreset.custom]; every other preset ignores them.
FhirExportRange resolveFhirExportRangePreset({
  required FhirExportRangePreset preset,
  required List<DayEntry> entries,
  required LocalDate today,
  LocalDate? customStart,
  LocalDate? customEnd,
}) {
  final cycleCount = kFhirExportRangeCycleCounts[preset];
  if (cycleCount != null) {
    return fhirExportRangeForCycleCount(
      cycleCount: cycleCount,
      preset: preset,
      entries: entries,
      today: today,
    );
  }
  if (preset == FhirExportRangePreset.last12Months) {
    return fhirExportRangeForLast12Months(today);
  }
  if (preset == FhirExportRangePreset.everything) {
    return FhirExportRange.everything;
  }
  // The only preset left: FhirExportRangePreset.custom.
  if (customStart == null || customEnd == null) {
    throw ArgumentError(
      'customStart and customEnd are both required for FhirExportRangePreset.custom',
    );
  }
  return customFhirExportRange(start: customStart, end: customEnd);
}
