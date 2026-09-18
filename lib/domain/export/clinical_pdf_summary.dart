/// Pure builder for the on-device PDF clinician cycle summary (Issue #154).
///
/// This file has no Flutter, no `dart:io`, and no network: it turns a
/// profile's logged entries/observations plus a resolved [FhirExportRange]
/// into a plain [ClinicalPdfSummary] value. The PDF byte rendering lives in
/// `lib/domain/export/clinical_pdf.dart`; the temp-file + share-sheet
/// hand-off lives in `lib/data/export/clinical_pdf_writer.dart`. The
/// separation mirrors the JSON export (`account_export.dart` vs
/// `account_export_writer.dart`) and the FHIR export (`fhir_bundle.dart`
/// vs `fhir_bundle_writer.dart`).
///
/// **Cycle window and exclusions (issue acceptance criteria).** Cycles are
/// derived from the profile's *full* history via the same
/// `deriveEpisodes`/`bleedDatesOf` the history list, CSV export, and
/// predictions already use, then filtered to the completed cycles whose
/// start falls inside [range] — never a re-derivation with its own rules.
/// The open (in-progress) cycle is always excluded: this is a report about
/// completed cycles. Within the window:
/// - Cycles omitted from averages ([omittedCycleStarts], the #132/#568
///   exclusion set) are dropped from both the statistics and the symptom
///   grid, exactly as the app's own averages drop them.
/// - Cycles longer than `kMaxCycleDays` (60 days) are dropped from the
///   grid but *kept* in the statistics and the per-cycle history table,
///   matching Clue's own documented split (issue #154 body, A2-24).
///
/// **Derived values and disclaimers.** The only derived figures this
/// document carries are descriptive statistics over logged cycle lengths
/// (mean/median/range). No fertile-window or conception-likelihood estimate
/// is ever computed or rendered here — the summary shows logged data only.
/// Because even a descriptive statistic is a derived value, the caller
/// injects the app's existing estimate disclaimer copy
/// ([derivedValueDisclaimers], supplied by the UI layer from
/// `lib/ui/overview/estimate_copy.dart`) so the domain stays free of
/// user-facing copy and the exact in-app text is preserved. The
/// export-specific "this is not a diagnosis" line is a domain constant
/// ([kClinicalSummaryNotDiagnosisLine]) because it is part of this
/// document's own method note, not a reused app string.
///
/// **Identifier discipline.** Matches `fhir_bundle.dart`'s deliberately
/// minimal choice: the document carries only the profile's
/// [Profile.displayName]. No profile id, no birth year, no email, no
/// guardian attribution, no storage-assigned ids — none of those arguments
/// are even accepted by [buildClinicalPdfSummary].
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/local_date.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import '../prediction/prediction.dart' show kMaxCycleDays;
import '../tags.dart' as tags;
import 'fhir_export_range.dart';

/// The export-specific plain-language line the acceptance criteria require.
/// Clue's own report states plainly that it cannot provide a diagnosis; this
/// is that statement for lunarlog, kept next to the method note.
const String kClinicalSummaryNotDiagnosisLine =
    'This summary is not a diagnosis. It reports data logged by the person '
    'or their guardian and does not replace an assessment by a clinician.';

/// One completed cycle in the per-cycle history table.
class ClinicalCycleRow {
  const ClinicalCycleRow({
    required this.number,
    required this.startIso,
    required this.endIso,
    required this.cycleLengthDays,
    required this.periodLengthDays,
    required this.excludedFromAverages,
  });

  /// 1-based position within the report, oldest first.
  final int number;
  final String startIso;

  /// Inclusive end (the day before the next cycle's start).
  final String endIso;
  final int cycleLengthDays;
  final int periodLengthDays;

  /// Whether this cycle is omitted from the report's statistics/grid.
  final bool excludedFromAverages;
}

/// Mean/median/range for one measured quantity, over the included cycles.
class ClinicalRangeStat {
  const ClinicalRangeStat({
    required this.count,
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
  });

  final int count;
  final double mean;
  final double median;
  final int min;
  final int max;
}

/// One symptom row of the frequency grid: [counts] is indexed by cycle day
/// (`counts[0]` is day 1) and spans the widest included cycle.
class ClinicalSymptomRow {
  const ClinicalSymptomRow({required this.label, required this.counts});

  final String label;
  final List<int> counts;
}

/// The complete, renderer-ready document model.
class ClinicalPdfSummary {
  const ClinicalPdfSummary({
    required this.profileDisplayName,
    required this.rangeLabel,
    required this.generatedAt,
    required this.cycleLengthStat,
    required this.periodLengthStat,
    required this.cycles,
    required this.cyclesInRange,
    required this.excludedCycleCount,
    required this.symptomGrid,
    required this.graphCycleCount,
    required this.medications,
    required this.birthControlMethod,
    required this.conditions,
    required this.derivedValueDisclaimers,
  });

  final String profileDisplayName;
  final String rangeLabel;
  final DateTime generatedAt;

  /// Null when no cycles were included in the statistics window.
  final ClinicalRangeStat? cycleLengthStat;
  final ClinicalRangeStat? periodLengthStat;

  /// Completed cycles in [range], oldest first, excluded ones included and
  /// flagged (history is retained; see this file's doc comment).
  final List<ClinicalCycleRow> cycles;

  /// Completed cycles whose start fell inside the selected range, before
  /// any exclusion was applied.
  final int cyclesInRange;

  /// How many of [cyclesInRange] are omitted from averages.
  final int excludedCycleCount;

  /// Symptom frequency by cycle day, over the grid-eligible cycles only.
  final List<ClinicalSymptomRow> symptomGrid;

  /// How many cycles the grid covers (after omitted and >60-day drops).
  final int graphCycleCount;

  final List<String> medications;
  final String? birthControlMethod;
  final List<String> conditions;

  /// The app's exact estimate-disclaimer copy, injected by the UI layer.
  final List<String> derivedValueDisclaimers;

  /// Widest cycle-day column the grid covers, or 0 when there is no grid.
  int get maxCycleDay =>
      symptomGrid.isEmpty ? 0 : symptomGrid.first.counts.length;

  bool get hasCompletedCycles => cycles.isNotEmpty;
}

/// Builds the summary from a profile's full logged history (see this file's
/// doc comment for the window/exclusion rules). [dayEntries] and
/// [observations] are the profile's *complete* reads, not pre-filtered:
/// [range] decides the window here so a cycle's true length is known even
/// when the range's lower bound sits on a cycle start.
ClinicalPdfSummary buildClinicalPdfSummary({
  required Profile profile,
  required List<DayEntry> dayEntries,
  List<Observation> observations = const [],
  required FhirExportRange range,
  required String rangeLabel,
  required DateTime generatedAt,
  Set<LocalDate> omittedCycleStarts = const {},
  String? birthControlMethod,
  List<String> medications = const [],
  List<String> conditions = const [],
  List<String> derivedValueDisclaimers = const [],
}) {
  final episodes = deriveEpisodes(bleedDatesOf(dayEntries));
  final windowCycles = <_WindowCycle>[
    for (final cycle in _completedCycles(episodes))
      if (range.includes(cycle.start))
        (
          cycle: cycle,
          excluded: omittedCycleStarts.contains(cycle.start),
        ),
  ];
  final included = [
    for (final entry in windowCycles)
      if (!entry.excluded) entry.cycle,
  ];
  final graphCycles = [
    for (final cycle in included)
      if (cycle.cycleLengthDays <= kMaxCycleDays) cycle,
  ];

  return ClinicalPdfSummary(
    profileDisplayName: profile.displayName,
    rangeLabel: rangeLabel,
    generatedAt: generatedAt,
    cycleLengthStat: _rangeStat(
      [for (final cycle in included) cycle.cycleLengthDays],
    ),
    periodLengthStat: _rangeStat(
      [for (final cycle in included) cycle.periodLengthDays],
    ),
    cycles: [
      for (var i = 0; i < windowCycles.length; i++)
        _toRow(windowCycles[i], i + 1),
    ],
    cyclesInRange: windowCycles.length,
    excludedCycleCount: windowCycles.where((entry) => entry.excluded).length,
    symptomGrid: _buildSymptomGrid(graphCycles, dayEntries, observations),
    graphCycleCount: graphCycles.length,
    medications: List.unmodifiable(medications),
    birthControlMethod: birthControlMethod,
    conditions: List.unmodifiable(conditions),
    derivedValueDisclaimers: List.unmodifiable(derivedValueDisclaimers),
  );
}

/// A completed cycle: [start] through the day before the next episode's
/// [start]; [cycleLengthDays] is the gap to that next start and
/// [periodLengthDays] the bleed episode's own length.
typedef _Cycle = ({
  LocalDate start,
  int cycleLengthDays,
  int periodLengthDays,
});

/// One cycle in the selected window plus its omission flag.
typedef _WindowCycle = ({_Cycle cycle, bool excluded});

ClinicalCycleRow _toRow(
  _WindowCycle entry,
  int number,
) => ClinicalCycleRow(
  number: number,
  startIso: entry.cycle.start.iso,
  endIso: entry.cycle.start.addDays(entry.cycle.cycleLengthDays - 1).iso,
  cycleLengthDays: entry.cycle.cycleLengthDays,
  periodLengthDays: entry.cycle.periodLengthDays,
  excludedFromAverages: entry.excluded,
);

/// Every completed cycle in [episodes] (ascending), derived from consecutive
/// episode starts. The final episode has no next start and is therefore the
/// still-open cycle, deliberately omitted.
List<_Cycle> _completedCycles(List<Episode> episodes) => [
  for (var i = 0; i + 1 < episodes.length; i++)
    (
      start: episodes[i].start,
      cycleLengthDays: episodes[i + 1].start.difference(episodes[i].start),
      periodLengthDays: episodes[i].lengthDays,
    ),
];

/// Mean/median/min/max for [values], or null when empty. Unlike the
/// prediction engine's averages, this does not drop >60-day cycles:
/// issue #154 retains them in the statistics (only the grid drops them).
ClinicalRangeStat? _rangeStat(List<int> values) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
  final total = values.fold<int>(0, (sum, value) => sum + value);
  return ClinicalRangeStat(
    count: values.length,
    mean: total / values.length,
    median: median,
    min: sorted.first,
    max: sorted.last,
  );
}

/// Symptom frequency across [graphCycles]: one row per observed symptom
/// label, one column per cycle day. Labels come from the app's real symptom
/// surface — [DayEntry.tags] (the FHIR builder's own primary source) — plus
/// any non-excluded `observations` row that carries an option code, with
/// measurement categories (bbt/weight) excluded since they are logged
/// values rather than symptoms. Rows are ordered by total frequency, then
/// label, for a deterministic document.
List<ClinicalSymptomRow> _buildSymptomGrid(
  List<_Cycle> graphCycles,
  List<DayEntry> dayEntries,
  List<Observation> observations,
) {
  if (graphCycles.isEmpty) return const [];
  final maxDay = graphCycles
      .map((cycle) => cycle.cycleLengthDays)
      .reduce((a, b) => a > b ? a : b);
  final entriesByDate = {
    for (final entry in dayEntries)
      if (entry.deletedAt == null) entry.localDate: entry,
  };
  final observationsByDate = <LocalDate, List<Observation>>{};
  for (final observation in observations) {
    if (observation.deletedAt != null) continue;
    observationsByDate
        .putIfAbsent(observation.localDate, () => [])
        .add(observation);
  }

  final counts = <String, List<int>>{};
  for (final cycle in graphCycles) {
    for (var day = 1; day <= cycle.cycleLengthDays; day++) {
      final date = cycle.start.addDays(day - 1);
      for (final label in _labelsOn(date, entriesByDate, observationsByDate)) {
        final row = counts.putIfAbsent(label, () => List.filled(maxDay, 0));
        row[day - 1] += 1;
      }
    }
  }
  final rows = [
    for (final entry in counts.entries)
      ClinicalSymptomRow(label: entry.key, counts: List.unmodifiable(entry.value)),
  ];
  rows.sort((a, b) {
    final byFrequency = _total(b.counts).compareTo(_total(a.counts));
    return byFrequency != 0 ? byFrequency : a.label.compareTo(b.label);
  });
  return List.unmodifiable(rows);
}

int _total(List<int> counts) =>
    counts.fold<int>(0, (sum, value) => sum + value);

/// The distinct symptom labels present on [date].
Set<String> _labelsOn(
  LocalDate date,
  Map<LocalDate, DayEntry> entriesByDate,
  Map<LocalDate, List<Observation>> observationsByDate,
) => {
  ..._tagLabelsOn(entriesByDate[date]),
  ..._observationLabelsOn(observationsByDate[date] ?? const <Observation>[]),
};

/// Symptom labels from [entry]'s tags: known taxonomy codes that are not
/// positive "none today" assertions, rendered with their display string.
Set<String> _tagLabelsOn(DayEntry? entry) {
  if (entry == null) return const {};
  return {
    for (final code in entry.tags)
      if (_isSymptomTag(code)) tags.tagByCode(code)?.display ?? code,
  };
}

bool _isSymptomTag(String code) =>
    tags.isValidTagCode(code) && !tags.kPositiveAssertionCodes.contains(code);

/// Symptom labels from logged option rows: an excluded row (the BBT
/// per-point flag) and a measurement category are not symptoms.
Set<String> _observationLabelsOn(List<Observation> observations) => {
  for (final observation in observations)
    if (!observation.excluded &&
        !_kMeasurementCategories.contains(observation.category))
      observation.code ?? observation.category,
};

/// Observation categories that hold a logged measurement rather than a
/// symptom (mirrors `csv_export.dart`'s dedicated bbt/weight columns).
const Set<String> _kMeasurementCategories = {'bbt', 'weight'};
