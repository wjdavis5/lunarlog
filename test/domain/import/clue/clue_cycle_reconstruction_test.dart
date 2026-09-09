/// Unit tests for Clue period-episode reconstruction (Issue #190):
/// spotting is excluded from bleed dates entirely (so a spotting-only run
/// derives no episode), `period/none` never counts as a bleed day, and a
/// one-skipped-day gap still merges into a single episode. Fixture:
/// `test/fixtures/clue/multi_cycle_bleeding.json`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/import/clue/clue_cycle_reconstruction.dart';
import 'package:lunarlog/domain/import/clue/clue_datapoint.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/models/local_date.dart';

LocalDate _d(String iso) => LocalDate.fromIso(iso);

void main() {
  test('a spotting-only run produces no episode, and a one-day gap inside '
      'a bleed run still merges', () {
    final bytes = File('test/fixtures/clue/multi_cycle_bleeding.json')
        .readAsBytesSync();
    final datapoints = parseClueDatapoints(bytes).datapoints;

    final episodes = reconstructClueEpisodes(datapoints);

    expect(episodes, [
      Episode(_d('2026-01-01'), _d('2026-01-04')),
      Episode(_d('2026-01-20'), _d('2026-01-22')),
    ]);
  });

  test('cluePeriodBleedDatesOf excludes spotting and the not-bleeding '
      'assertion, including entirely on days with no period datapoint', () {
    final bytes = File('test/fixtures/clue/multi_cycle_bleeding.json')
        .readAsBytesSync();
    final datapoints = parseClueDatapoints(bytes).datapoints;

    final bleedDates = cluePeriodBleedDatesOf(datapoints);

    // The spotting-only days (Jan 10-12) and the period/none day (Jan 15)
    // never enter the bleed-date set at all.
    expect(bleedDates.contains(_d('2026-01-10')), isFalse);
    expect(bleedDates.contains(_d('2026-01-11')), isFalse);
    expect(bleedDates.contains(_d('2026-01-12')), isFalse);
    expect(bleedDates.contains(_d('2026-01-15')), isFalse);
    // Jan 3 has only a spotting datapoint (no period) but still falls
    // inside the tolerated one-day gap between Jan 2 and Jan 4.
    expect(bleedDates.contains(_d('2026-01-03')), isFalse);
    expect(bleedDates, {
      _d('2026-01-01'),
      _d('2026-01-02'),
      _d('2026-01-04'),
      _d('2026-01-20'),
      _d('2026-01-21'),
      _d('2026-01-22'),
    });
  });

  group('groupClueDatapointsByDate', () {
    test('groups by date, preserving each date\'s relative order, keys '
        'iterating in date order', () {
      final jan2 = CluePeriodDatapoint(_d('2026-01-02'), ClueFlowLevel.light);
      final jan1a =
          CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.medium);
      final jan1b = ClueObservationDatapoint(
        _d('2026-01-01'),
        'pain',
        category: 'pain',
        code: 'cramps',
      );

      final grouped = groupClueDatapointsByDate([jan2, jan1a, jan1b]);

      expect(grouped.keys.toList(), [_d('2026-01-01'), _d('2026-01-02')]);
      expect(grouped[_d('2026-01-01')], [jan1a, jan1b]);
      expect(grouped[_d('2026-01-02')], [jan2]);
    });

    test('an empty input produces an empty map', () {
      expect(groupClueDatapointsByDate(const []), isEmpty);
    });
  });

  group('highestCluePeriodLevel', () {
    test('the highest bleed level wins when two period rows land on the '
        'same date', () {
      final rows = [
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.light),
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.heavy),
      ];
      expect(highestCluePeriodLevel(rows), ClueFlowLevel.heavy);
    });

    test('order does not matter — the higher level still wins either way',
        () {
      final reversed = [
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.superHeavy),
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.medium),
      ];
      expect(highestCluePeriodLevel(reversed), ClueFlowLevel.superHeavy);
    });

    test('notBleeding never beats a real bleed level, whichever side it '
        'is on', () {
      final noneFirst = [
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.notBleeding),
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.light),
      ];
      final noneLast = [
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.light),
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.notBleeding),
      ];
      expect(highestCluePeriodLevel(noneFirst), ClueFlowLevel.light);
      expect(highestCluePeriodLevel(noneLast), ClueFlowLevel.light);
    });

    test('all-notBleeding input returns notBleeding, never null', () {
      final rows = [
        CluePeriodDatapoint(_d('2026-01-01'), ClueFlowLevel.notBleeding),
      ];
      expect(highestCluePeriodLevel(rows), ClueFlowLevel.notBleeding);
    });

    test('an empty list returns null', () {
      expect(highestCluePeriodLevel(const []), isNull);
    });
  });
}
