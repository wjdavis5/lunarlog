/// Unit tests for the clinical-export date-range selection (Issue #459):
/// preset resolution, filtering, and — the "builder test that the range is
/// honoured" the issue's acceptance criteria ask for — that a resolved
/// range's [FhirExportRange.filterEntries] output, fed into
/// [buildFhirDocumentBundle], changes which flow Observations the Bundle
/// carries.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/fhir_bundle.dart';
import 'package:lunarlog/domain/export/fhir_export_range.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/models/profile.dart';

DayEntry _entry(String id, LocalDate date, {String profileId = 'p1'}) =>
    DayEntry(
      id: id,
      profileId: profileId,
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Observation _observation(
  String id,
  LocalDate date, {
  String profileId = 'p1',
}) => Observation(
  id: id,
  dayEntryId: 'd-$id',
  profileId: profileId,
  localDate: date,
  tz: 'UTC',
  category: ObservationCategory.weight,
  valueNum: 60,
  unit: 'kg',
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Five single-day episode starts, 40 days apart — the newest is always an
/// open cycle (no next start yet), the other four are completed cycles.
/// Mirrors `test/ui/clinical_export_tile_test.dart`'s own fixture.
List<LocalDate> _fiveCycleStarts() => [
  for (var i = 0; i < 5; i++) LocalDate(2025, 1, 1).addDays(i * 40),
];

void main() {
  final starts = _fiveCycleStarts();
  final today = LocalDate(2026, 6, 1);

  group('FhirExportRange.includes / filterEntries / filterObservations', () {
    test('everything (both bounds null) includes any date', () {
      expect(
        FhirExportRange.everything.includes(LocalDate(1900, 1, 1)),
        isTrue,
      );
      expect(
        FhirExportRange.everything.includes(LocalDate(2100, 1, 1)),
        isTrue,
      );
    });

    test('a lower bound excludes dates before it, includes on/after', () {
      final range = FhirExportRange(
        preset: FhirExportRangePreset.custom,
        start: LocalDate(2026, 1, 10),
      );
      expect(range.includes(LocalDate(2026, 1, 9)), isFalse);
      expect(range.includes(LocalDate(2026, 1, 10)), isTrue);
      expect(range.includes(LocalDate(2026, 1, 11)), isTrue);
    });

    test('an upper bound excludes dates after it, includes on/before', () {
      final range = FhirExportRange(
        preset: FhirExportRangePreset.custom,
        end: LocalDate(2026, 1, 10),
      );
      expect(range.includes(LocalDate(2026, 1, 11)), isFalse);
      expect(range.includes(LocalDate(2026, 1, 10)), isTrue);
      expect(range.includes(LocalDate(2026, 1, 9)), isTrue);
    });

    test('filterEntries/filterObservations narrow to the inclusive range,'
        ' order preserved', () {
      final range = FhirExportRange(
        preset: FhirExportRangePreset.custom,
        start: LocalDate(2026, 1, 2),
        end: LocalDate(2026, 1, 3),
      );
      final entries = [
        _entry('e1', LocalDate(2026, 1, 1)),
        _entry('e2', LocalDate(2026, 1, 2)),
        _entry('e3', LocalDate(2026, 1, 3)),
        _entry('e4', LocalDate(2026, 1, 4)),
      ];
      final observations = [
        _observation('o1', LocalDate(2026, 1, 1)),
        _observation('o2', LocalDate(2026, 1, 2)),
      ];
      expect(range.filterEntries(entries).map((e) => e.id), ['e2', 'e3']);
      expect(range.filterObservations(observations).map((o) => o.id), ['o2']);
    });
  });

  group('fhirExportRangeForCycleCount / defaultFhirExportRange', () {
    test('picks the Nth-most-recent completed cycle\'s start as the lower '
        'bound, with no upper bound', () {
      final entries = [for (final s in starts) _entry('e-${s.iso}', s)];
      // 4 completed cycles exist (starts[0..3]); "last 3" excludes the
      // oldest (starts[0]) and starts from starts[1] (the 3rd-most-recent
      // completed cycle).
      final range = fhirExportRangeForCycleCount(
        cycleCount: 3,
        preset: FhirExportRangePreset.last3Cycles,
        entries: entries,
        today: today,
      );
      expect(range.start, starts[1]);
      expect(range.end, isNull);
      expect(range.preset, FhirExportRangePreset.last3Cycles);
    });

    test('fewer completed cycles than requested resolves to no lower '
        'bound (everything so far)', () {
      final entries = [for (final s in starts) _entry('e-${s.iso}', s)];
      // Only 4 completed cycles exist; asking for 6 must not throw or
      // produce a partial/empty range.
      final range = fhirExportRangeForCycleCount(
        cycleCount: 6,
        preset: FhirExportRangePreset.last6Cycles,
        entries: entries,
        today: today,
      );
      expect(range.start, isNull);
      expect(range.end, isNull);
    });

    test('no entries at all resolves to no lower bound', () {
      final range = fhirExportRangeForCycleCount(
        cycleCount: 6,
        preset: FhirExportRangePreset.last6Cycles,
        entries: const [],
        today: today,
      );
      expect(range.start, isNull);
    });

    test('defaultFhirExportRange is the last-6-cycles preset', () {
      final entries = [for (final s in starts) _entry('e-${s.iso}', s)];
      final range = defaultFhirExportRange(entries: entries, today: today);
      expect(range.preset, FhirExportRangePreset.last6Cycles);
      // Only 4 completed cycles exist, fewer than 6 — no lower bound,
      // matching today's whole-history behaviour for a profile with under
      // 6 cycles logged.
      expect(range.start, isNull);
    });
  });

  group('fhirExportRangeForLast12Months', () {
    test('starts exactly 12 calendar months before today, no upper bound', () {
      final range = fhirExportRangeForLast12Months(today);
      expect(range.preset, FhirExportRangePreset.last12Months);
      expect(range.start, today.addMonths(-12));
      expect(range.end, isNull);
    });
  });

  group('customFhirExportRange', () {
    test('carries both bounds and the custom preset', () {
      final range = customFhirExportRange(
        start: LocalDate(2026, 1, 1),
        end: LocalDate(2026, 3, 1),
      );
      expect(range.preset, FhirExportRangePreset.custom);
      expect(range.start, LocalDate(2026, 1, 1));
      expect(range.end, LocalDate(2026, 3, 1));
    });
  });

  group('resolveFhirExportRangePreset', () {
    final entries = [for (final s in starts) _entry('e-${s.iso}', s)];

    test('dispatches cycle-count presets to fhirExportRangeForCycleCount', () {
      final range = resolveFhirExportRangePreset(
        preset: FhirExportRangePreset.last3Cycles,
        entries: entries,
        today: today,
      );
      expect(range.start, starts[1]);
    });

    test('dispatches last12Months to fhirExportRangeForLast12Months', () {
      final range = resolveFhirExportRangePreset(
        preset: FhirExportRangePreset.last12Months,
        entries: entries,
        today: today,
      );
      expect(range.start, today.addMonths(-12));
    });

    test('dispatches everything to FhirExportRange.everything', () {
      final range = resolveFhirExportRangePreset(
        preset: FhirExportRangePreset.everything,
        entries: entries,
        today: today,
      );
      expect(range.start, isNull);
      expect(range.end, isNull);
    });

    test('dispatches custom to customFhirExportRange when both dates are '
        'given', () {
      final range = resolveFhirExportRangePreset(
        preset: FhirExportRangePreset.custom,
        entries: entries,
        today: today,
        customStart: LocalDate(2026, 2, 1),
        customEnd: LocalDate(2026, 2, 28),
      );
      expect(range.start, LocalDate(2026, 2, 1));
      expect(range.end, LocalDate(2026, 2, 28));
    });

    test('throws for custom with a missing start or end', () {
      expect(
        () => resolveFhirExportRangePreset(
          preset: FhirExportRangePreset.custom,
          entries: entries,
          today: today,
          customEnd: LocalDate(2026, 2, 28),
        ),
        throwsArgumentError,
      );
      expect(
        () => resolveFhirExportRangePreset(
          preset: FhirExportRangePreset.custom,
          entries: entries,
          today: today,
          customStart: LocalDate(2026, 2, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the range actually reaches buildFhirDocumentBundle (#459 AC)', () {
    Profile profile() => Profile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    List<Map<String, Object?>> flowObservationsOf(Map<String, Object?> bundle) {
      final entries = (bundle['entry'] as List).cast<Map>();
      return [
        for (final e in entries)
          if ((e['resource'] as Map).containsKey('valueCodeableConcept'))
            (e['resource'] as Map).cast<String, Object?>(),
      ];
    }

    test('a narrower range excludes the oldest entry\'s flow Observation '
        'from the built Bundle; "everything" keeps it', () {
      final dayEntries = [for (final s in starts) _entry('e-${s.iso}', s)];

      final narrow = fhirExportRangeForCycleCount(
        cycleCount: 3,
        preset: FhirExportRangePreset.last3Cycles,
        entries: dayEntries,
        today: today,
      );
      final narrowBundle = buildFhirDocumentBundle(
        profile: profile(),
        dayEntries: narrow.filterEntries(dayEntries),
        exportedAt: DateTime.utc(2026, 6, 1),
        appVersion: '1.0.0',
      );
      final narrowDates = [
        for (final o in flowObservationsOf(narrowBundle))
          o['effectiveDateTime'],
      ];
      expect(narrowDates, isNot(contains(starts.first.iso)));
      expect(narrowDates, contains(starts.last.iso));

      final everythingBundle = buildFhirDocumentBundle(
        profile: profile(),
        dayEntries: FhirExportRange.everything.filterEntries(dayEntries),
        exportedAt: DateTime.utc(2026, 6, 1),
        appVersion: '1.0.0',
      );
      final everythingDates = [
        for (final o in flowObservationsOf(everythingBundle))
          o['effectiveDateTime'],
      ];
      expect(everythingDates, contains(starts.first.iso));
    });
  });
}
