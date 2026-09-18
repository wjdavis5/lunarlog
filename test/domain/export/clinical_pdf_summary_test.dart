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
}
