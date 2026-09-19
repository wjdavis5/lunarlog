/// Unit tests for the pure PDF clinician summary builder (Issue #154).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/clinical_pdf_summary.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/profile.dart';

Profile _profile({String displayName = 'Riley'}) => Profile(
  id: 'p1',
  displayName: displayName,
  isMinor: false,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

DayEntry _bleed(
  String id,
  LocalDate date, {
  List<String> tags = const [],
  String profileId = 'p1',
}) => DayEntry(
  id: id,
  profileId: profileId,
  localDate: date,
  tz: 'UTC',
  flow: FlowLevel.medium,
  tags: tags,
  updatedAt: DateTime.utc(2026, 1, 1),
);

Observation _observation(
  String id,
  LocalDate date, {
  required String category,
  String? code,
  bool excluded = false,
}) => Observation(
  id: id,
  dayEntryId: 'd-$id',
  profileId: 'p1',
  localDate: date,
  tz: 'UTC',
  category: category,
  code: code,
  excluded: excluded,
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Two bleed days per cycle, cycles [gapDays] apart.
List<DayEntry> _entriesFor(List<LocalDate> starts, {int gapDays = 1}) => [
  for (var i = 0; i < starts.length; i++) ...[
    _bleed('e$i-a', starts[i]),
    _bleed('e$i-b', starts[i].addDays(gapDays)),
  ],
];

List<LocalDate> _starts(int count, {int gapDays = 28}) => [
  for (var i = 0; i < count; i++) LocalDate(2025, 1, 1).addDays(i * gapDays),
];

ClinicalPdfSummary _summary(
  List<DayEntry> entries, {
  List<Observation> observations = const [],
  Set<LocalDate> omitted = const {},
  String? birthControlMethod,
  List<String> medications = const [],
  List<String> conditions = const [],
  List<String> disclaimers = const [],
  String rangeLabel = 'Last 6 cycles',
  DateTime? generatedAt,
}) {
  final starts = _starts(8);
  return buildClinicalPdfSummary(
    profile: _profile(),
    dayEntries: entries,
    observations: observations,
    range: FhirExportRange(
      preset: FhirExportRangePreset.last6Cycles,
      start: starts[1],
    ),
    rangeLabel: rangeLabel,
    generatedAt: generatedAt ?? DateTime.utc(2026, 6, 1, 12),
    omittedCycleStarts: omitted,
    birthControlMethod: birthControlMethod,
    medications: medications,
    conditions: conditions,
    derivedValueDisclaimers: disclaimers,
  );
}

void main() {
  final starts = _starts(8);
  final entries = _entriesFor(starts);

  test('six most-recent completed cycles are selected, oldest first, and '
      'the open cycle is never listed', () {
    final summary = _summary(entries);
    expect(summary.cycles, hasLength(6));
    expect(summary.cyclesInRange, 6);
    expect(summary.cycles.first.startIso, starts[1].iso);
    expect(summary.cycles.last.startIso, starts[6].iso);
    expect(
      summary.cycles.map((row) => row.number),
      [1, 2, 3, 4, 5, 6],
    );
    // The oldest cycle (starts[0]) is outside the six-cycle window.
    expect(
      summary.cycles.map((row) => row.startIso),
      isNot(contains(starts[0].iso)),
    );
    // The still-open cycle (starts[7]) is not a completed cycle.
    expect(
      summary.cycles.map((row) => row.startIso),
      isNot(contains(starts[7].iso)),
    );
  });

  test('cycle and period statistics are computed over the included cycles', () {
    final summary = _summary(entries);
    final cycle = summary.cycleLengthStat!;
    expect(cycle.count, 6);
    expect(cycle.mean, 28);
    expect(cycle.median, 28);
    expect(cycle.min, 28);
    expect(cycle.max, 28);
    final period = summary.periodLengthStat!;
    expect(period.count, 6);
    expect(period.mean, 2);
    expect(period.min, 2);
    expect(period.max, 2);
    expect(summary.cycles.every((row) => row.cycleLengthDays == 28), isTrue);
    expect(summary.cycles.every((row) => row.periodLengthDays == 2), isTrue);
    expect(summary.cycles.first.endIso, starts[1].addDays(27).iso);
  });

  test('a cycle omitted from averages is dropped from statistics and grid '
      'but retained in the history table with its flag', () {
    final summary = _summary(entries, omitted: {starts[2]});
    expect(summary.cycles, hasLength(6));
    expect(summary.excludedCycleCount, 1);
    final omittedRow = summary.cycles.singleWhere(
      (row) => row.startIso == starts[2].iso,
    );
    expect(omittedRow.excludedFromAverages, isTrue);
    expect(summary.cycleLengthStat!.count, 5);
    expect(summary.graphCycleCount, 5);
  });

  test('a cycle longer than 60 days is dropped from the grid but kept in '
      'statistics and the table', () {
    final longStarts = [0, 28, 56, 126, 154, 182, 210, 238]
        .map((offset) => LocalDate(2025, 1, 1).addDays(offset))
        .toList();
    final longEntries = _entriesFor(longStarts);
    final summary = _summary(longEntries);
    expect(summary.cycles, hasLength(6));
    expect(summary.cycles.any((row) => row.cycleLengthDays == 70), isTrue);
    expect(summary.cycleLengthStat!.count, 6);
    expect(summary.cycleLengthStat!.max, 70);
    expect(summary.graphCycleCount, 5);
  });

  test('the symptom grid counts occurrences by cycle day across the included '
      'cycles and skips positive assertions', () {
    final tagsByDate = <LocalDate, List<String>>{
      starts[1]: const ['cramps', 'pain_free'],
      starts[1].addDays(1): const ['cramps'],
      starts[2]: const ['cramps'],
      starts[3].addDays(1): const ['headache'],
    };
    final withTags = [
      for (final start in starts) ...[
        _bleed('t-${start.iso}', start, tags: tagsByDate[start] ?? const []),
        _bleed(
          't-${start.iso}-b',
          start.addDays(1),
          tags: tagsByDate[start.addDays(1)] ?? const [],
        ),
      ],
    ];
    final summary = _summary(withTags);
    final cramps = summary.symptomGrid.singleWhere(
      (row) => row.label == 'Cramps',
    );
    expect(cramps.counts[0], 2);
    expect(cramps.counts[1], 1);
    expect(cramps.counts.reduce((a, b) => a + b), 3);
    final headache = summary.symptomGrid.singleWhere(
      (row) => row.label == 'Headache',
    );
    expect(headache.counts[1], 1);
    expect(summary.symptomGrid.first.label, 'Cramps');
    expect(
      summary.symptomGrid.any((row) => row.label == 'Pain free'),
      isFalse,
    );
    expect(summary.maxCycleDay, 28);
  });

  test('observations contribute symptom labels, but excluded and measurement '
      'rows do not', () {
    final observations = [
      _observation('o1', starts[1], category: 'pain', code: 'migraine'),
      _observation(
        'o2',
        starts[2],
        category: 'pain',
        code: 'migraine',
        excluded: true,
      ),
      _observation('o3', starts[3], category: 'bbt'),
    ];
    final summary = _summary(entries, observations: observations);
    final migraine = summary.symptomGrid.singleWhere(
      (row) => row.label == 'migraine',
    );
    expect(migraine.counts[0], 1);
    expect(summary.symptomGrid.any((row) => row.label == 'bbt'), isFalse);
  });

  test('profile name, range label, generated instant, and injected metadata '
      'are carried through', () {
    final summary = _summary(
      entries,
      birthControlMethod: 'Combined pill',
      medications: const ['Ibuprofen'],
      conditions: const ['Migraine'],
      disclaimers: const ['Estimates only.'],
      rangeLabel: 'Last 3 cycles',
      generatedAt: DateTime.utc(2026, 2, 3, 4, 5),
    );
    expect(summary.profileDisplayName, 'Riley');
    expect(summary.rangeLabel, 'Last 3 cycles');
    expect(summary.generatedAt, DateTime.utc(2026, 2, 3, 4, 5));
    expect(summary.birthControlMethod, 'Combined pill');
    expect(summary.medications, ['Ibuprofen']);
    expect(summary.conditions, ['Migraine']);
    expect(summary.derivedValueDisclaimers, ['Estimates only.']);
  });

  test('empty medication/condition lists default to empty, not null', () {
    final summary = _summary(entries);
    expect(summary.medications, isEmpty);
    expect(summary.birthControlMethod, isNull);
    expect(summary.conditions, isEmpty);
  });

  test('no history yields an empty, honest summary', () {
    final summary = buildClinicalPdfSummary(
      profile: _profile(),
      dayEntries: const [],
      range: FhirExportRange.everything,
      rangeLabel: 'Everything',
      generatedAt: DateTime.utc(2026, 6, 1),
    );
    expect(summary.cycles, isEmpty);
    expect(summary.cycleLengthStat, isNull);
    expect(summary.periodLengthStat, isNull);
    expect(summary.symptomGrid, isEmpty);
    expect(summary.maxCycleDay, 0);
    expect(summary.hasCompletedCycles, isFalse);
  });

  test('the not-a-diagnosis line is a stable domain constant', () {
    expect(kClinicalSummaryNotDiagnosisLine, contains('not a diagnosis'));
  });

  group('Issue #797 — kMinCycleDays floor and irregular cycle handling', () {
    test(
        'cycles shorter than kMinCycleDays (15 days) are dropped from cycle '
        'length statistics and grid, but kept in the table flagged isIrregular',
        () {
      // 7 starts producing 6 completed cycles:
      // 2026-04-12 -> 2026-05-11 (29 days)
      // 2026-05-11 -> 2026-06-08 (28 days)
      // 2026-06-08 -> 2026-06-15 (7 days)   <- irregular (< 15 days)
      // 2026-06-15 -> 2026-07-08 (23 days)
      // 2026-07-08 -> 2026-08-05 (28 days)
      // 2026-08-05 -> 2026-09-03 (29 days)
      // 2026-09-03 -> open cycle
      final exactStarts = [
        LocalDate(2026, 4, 12),
        LocalDate(2026, 5, 11),
        LocalDate(2026, 6, 8),
        LocalDate(2026, 6, 15),
        LocalDate(2026, 7, 8),
        LocalDate(2026, 8, 5),
        LocalDate(2026, 9, 3),
      ];
      final exactEntries = [
        for (var i = 0; i < exactStarts.length; i++) ...[
          _bleed('e$i-a', exactStarts[i]),
          _bleed('e$i-b', exactStarts[i].addDays(1)),
        ],
      ];

      final summary = buildClinicalPdfSummary(
        profile: _profile(),
        dayEntries: exactEntries,
        range: FhirExportRange.everything,
        rangeLabel: 'Everything',
        generatedAt: DateTime.utc(2026, 9, 18, 12),
      );

      // All 6 completed cycles are preserved in the history table.
      expect(summary.cycles, hasLength(6));
      expect(summary.cyclesInRange, 6);
      expect(summary.excludedCycleCount, 0);

      // Row 3 is the 7-day cycle: flagged irregular, not omitted by user.
      final shortCycle = summary.cycles[2];
      expect(shortCycle.cycleLengthDays, 7);
      expect(shortCycle.isIrregular, isTrue);
      expect(shortCycle.excludedFromAverages, isFalse);

      // Other rows are normal: not irregular.
      expect(summary.cycles[0].cycleLengthDays, 29);
      expect(summary.cycles[0].isIrregular, isFalse);
      expect(summary.cycles[1].cycleLengthDays, 28);
      expect(summary.cycles[1].isIrregular, isFalse);
      expect(summary.cycles[3].cycleLengthDays, 23);
      expect(summary.cycles[3].isIrregular, isFalse);
      expect(summary.cycles[4].cycleLengthDays, 28);
      expect(summary.cycles[4].isIrregular, isFalse);
      expect(summary.cycles[5].cycleLengthDays, 29);
      expect(summary.cycles[5].isIrregular, isFalse);

      // Cycle length statistics: 7-day cycle excluded, n=5, mean=27.4.
      final cycleStat = summary.cycleLengthStat!;
      expect(cycleStat.count, 5);
      expect(cycleStat.mean, closeTo(27.4, 0.001));
      expect(cycleStat.median, 28);
      expect(cycleStat.min, 23);
      expect(cycleStat.max, 29);

      // Period length statistics: all 6 bleed periods included (n=6).
      final periodStat = summary.periodLengthStat!;
      expect(periodStat.count, 6);
      expect(periodStat.mean, 2);

      // Symptom grid: only valid cycles included (graphCycleCount = 5).
      expect(summary.graphCycleCount, 5);
    });

    test('boundary values for isIrregular: 14 is irregular, 15 and 60 are normal, 61 is irregular', () {
      final boundaryStarts = [
        LocalDate(2025, 1, 1),
        LocalDate(2025, 1, 15), // cycle 1: 14 days (< 15)
        LocalDate(2025, 1, 30), // cycle 2: 15 days (== 15)
        LocalDate(2025, 2, 27), // cycle 3: 28 days (normal)
        LocalDate(2025, 4, 28), // cycle 4: 60 days (== 60)
        LocalDate(2025, 6, 28), // cycle 5: 61 days (> 60)
        LocalDate(2025, 7, 28), // open cycle
      ];
      final boundaryEntries = _entriesFor(boundaryStarts);

      final summary = buildClinicalPdfSummary(
        profile: _profile(),
        dayEntries: boundaryEntries,
        range: FhirExportRange.everything,
        rangeLabel: 'Everything',
        generatedAt: DateTime.utc(2026, 1, 1),
      );

      expect(summary.cycles[0].cycleLengthDays, 14);
      expect(summary.cycles[0].isIrregular, isTrue);

      expect(summary.cycles[1].cycleLengthDays, 15);
      expect(summary.cycles[1].isIrregular, isFalse);

      expect(summary.cycles[2].cycleLengthDays, 28);
      expect(summary.cycles[2].isIrregular, isFalse);

      expect(summary.cycles[3].cycleLengthDays, 60);
      expect(summary.cycles[3].isIrregular, isFalse);

      expect(summary.cycles[4].cycleLengthDays, 61);
      expect(summary.cycles[4].isIrregular, isTrue);

      // Cycle stat includes 15, 28, 60, 61, 30 -> 5 cycles.
      // 14 is excluded (< 15).
      expect(summary.cycleLengthStat!.count, 5);
      expect(summary.cycleLengthStat!.min, 15);
      expect(summary.cycleLengthStat!.max, 61);

      // Graph cycles drops < 15 and > 60 -> 15, 28, 60, 30 -> 4 cycles.
      expect(summary.graphCycleCount, 4);
    });

    test('all cycles shorter than kMinCycleDays yields null cycleLengthStat', () {
      final shortStarts = [
        LocalDate(2025, 1, 1),
        LocalDate(2025, 1, 8),  // 7 days
        LocalDate(2025, 1, 15), // 7 days
        LocalDate(2025, 1, 22), // 7 days
        LocalDate(2025, 1, 29), // open cycle
      ];
      final shortEntries = _entriesFor(shortStarts);

      final summary = buildClinicalPdfSummary(
        profile: _profile(),
        dayEntries: shortEntries,
        range: FhirExportRange.everything,
        rangeLabel: 'Everything',
        generatedAt: DateTime.utc(2026, 1, 1),
      );

      expect(summary.cycles, hasLength(4));
      expect(summary.cycles.every((c) => c.isIrregular), isTrue);
      expect(summary.cycleLengthStat, isNull);
      expect(summary.periodLengthStat!.count, 4);
      expect(summary.graphCycleCount, 0);
    });
  });
}
