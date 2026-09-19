/// Issue #245: the pure data shaping behind the BBT chart —
/// [deriveBbtChartData]'s cycle-day resolution/exclusion/source filtering,
/// and the axis-geometry/opacity helpers the painter turns into pixels.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/insights/bbt_chart.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';

Observation _bbt(
  String id,
  LocalDate date,
  double celsius, {
  bool excluded = false,
  DateTime? updatedAt,
  ObservationCategory category = ObservationCategory.bbt,
  ObservationSource source = ObservationSource.manual,
  String unit = 'celsius',
}) =>
    Observation(
      id: id,
      dayEntryId: 'e-${date.iso}',
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      category: category,
      valueNum: celsius,
      unit: unit,
      excluded: excluded,
      source: source,
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  group('deriveBbtChartData', () {
    test('no episodes at all: empty data, no crash', () {
      final data = deriveBbtChartData(
        episodes: const [],
        observations: const [],
      );
      expect(data.isEmpty, isTrue);
      expect(data.series, isEmpty);
      expect(data.maxCycleDay, 0);
    });

    test('episodes with no bbt observations: one series per cycle, all '
        'empty', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: const [],
      );
      expect(data.isEmpty, isTrue);
      expect(data.series, hasLength(1));
      expect(data.series.single.points, isEmpty);
    });

    test('a bbt reading resolves to the right 1-based cycle day', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [_bbt('o1', LocalDate(2026, 1, 1), 36.5)],
      );
      expect(data.series.single.points.single.cycleDay, 1);
      final data2 = deriveBbtChartData(
        episodes: episodes,
        observations: [_bbt('o1', LocalDate(2026, 1, 5), 36.9)],
      );
      expect(data2.series.single.points.single.cycleDay, 5);
    });

    test('two cycles: a reading is assigned to the cycle it actually falls '
        'in, and maxCycleDay is the widest across every cycle', () {
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 1, 29), LocalDate(2026, 2, 1)),
      ];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [
          _bbt('o1', LocalDate(2026, 1, 10), 36.5), // cycle 1, day 10
          _bbt('o2', LocalDate(2026, 2, 5), 36.8), // cycle 2, day 8
        ],
      );
      expect(data.series, hasLength(2));
      expect(data.series[0].points.single.cycleDay, 10);
      expect(data.series[1].points.single.cycleDay, 8);
      expect(data.maxCycleDay, 10);
    });

    test('a reading before the very first cycle start is dropped, not '
        'crashed on or misattributed', () {
      final episodes = [Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [_bbt('o1', LocalDate(2026, 1, 1), 36.5)],
      );
      expect(data.series.single.points, isEmpty);
    });

    test('an excluded reading (A1-44) is never plotted', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [
          _bbt('o1', LocalDate(2026, 1, 2), 36.5, excluded: true),
        ],
      );
      expect(data.isEmpty, isTrue);
    });

    test('a tombstoned reading is never plotted', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final row = _bbt('o1', LocalDate(2026, 1, 2), 36.5)
          .copyWith(deletedAt: DateTime.utc(2026, 1, 3));
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [row],
      );
      expect(data.isEmpty, isTrue);
    });

    test('a non-bbt category row is ignored', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [
          _bbt('o1', LocalDate(2026, 1, 2), 61.0,
              category: ObservationCategory.weight),
        ],
      );
      expect(data.isEmpty, isTrue);
    });

    test('a Fahrenheit-stored row is converted to Celsius for plotting', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [
          _bbt('o1', LocalDate(2026, 1, 1), 98.096, unit: 'fahrenheit'),
        ],
      );
      expect(data.series.single.points.single.celsius, closeTo(36.72, 1e-6));
    });

    test('two live rows on the same date: the most recently updated one '
        'wins', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [
          _bbt(
            'o1',
            LocalDate(2026, 1, 1),
            36.5,
            updatedAt: DateTime.utc(2026, 1, 1, 8),
          ),
          _bbt(
            'o2',
            LocalDate(2026, 1, 1),
            36.9,
            updatedAt: DateTime.utc(2026, 1, 1, 9),
          ),
        ],
      );
      expect(data.series.single.points.single.celsius, 36.9);
    });

    test('an open (still-running) cycle plots readings past the last '
        'episode start with no upper bound', () {
      final episodes = [Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 4))];
      final data = deriveBbtChartData(
        episodes: episodes,
        observations: [_bbt('o1', LocalDate(2026, 2, 28), 36.6)],
      );
      expect(data.series.single.points.single.cycleDay, 28);
    });
  });

  group('bbtChartRecentSeries', () {
    BbtCycleSeries seriesWithOnePoint(int startDay) => BbtCycleSeries(
          cycleStart: LocalDate(2026, 1, startDay),
          points: [
            BbtPoint(
              cycleDay: 1,
              celsius: 36.5,
              date: LocalDate(2026, 1, startDay),
            ),
          ],
        );

    test('drops cycles with no points entirely', () {
      final data = BbtChartData(
        series: [
          BbtCycleSeries(cycleStart: LocalDate(2026, 1, 1), points: const []),
          seriesWithOnePoint(10),
        ],
        maxCycleDay: 1,
      );
      final recent = bbtChartRecentSeries(data);
      expect(recent, hasLength(1));
    });

    test('caps to the most recent maxCycles, keeping the newest-last order',
        () {
      final data = BbtChartData(
        series: [for (var i = 1; i <= 10; i++) seriesWithOnePoint(i)],
        maxCycleDay: 1,
      );
      final recent = bbtChartRecentSeries(data, maxCycles: 3);
      expect(recent, hasLength(3));
      expect(
        recent.map((s) => s.cycleStart.day),
        [8, 9, 10],
        reason: 'the three most recent, oldest-first within that window',
      );
    });

    test('fewer cycles than the cap: returns all of them unchanged', () {
      final data = BbtChartData(series: [seriesWithOnePoint(1)], maxCycleDay: 1);
      expect(bbtChartRecentSeries(data, maxCycles: 6), hasLength(1));
    });
  });

  group('bbtChartValueRange', () {
    test('empty values: a fixed default range around 36.0', () {
      final (min, max) = bbtChartValueRange(const []);
      expect(max - min, closeTo(kBbtChartPaddingCelsius * 2, 1e-9));
    });

    test('a single value: padded on both sides, never a zero-width range',
        () {
      final (min, max) = bbtChartValueRange([36.7]);
      expect(min, closeTo(36.7 - kBbtChartPaddingCelsius, 1e-9));
      expect(max, closeTo(36.7 + kBbtChartPaddingCelsius, 1e-9));
    });

    test('several values: the padded min/max of the whole set', () {
      final (min, max) = bbtChartValueRange([36.3, 36.9, 36.5]);
      expect(min, closeTo(36.3 - kBbtChartPaddingCelsius, 1e-9));
      expect(max, closeTo(36.9 + kBbtChartPaddingCelsius, 1e-9));
    });
  });

  group('bbtChartXFraction', () {
    test('day 1 of any range is always the left edge', () {
      expect(bbtChartXFraction(1, 10), 0.0);
    });

    test('the last day of the range is the right edge', () {
      expect(bbtChartXFraction(10, 10), 1.0);
    });

    test('a degenerate range (maxCycleDay <= 1) never divides by zero',
        () {
      expect(bbtChartXFraction(1, 1), 0.0);
      expect(bbtChartXFraction(1, 0), 0.0);
    });
  });

  group('bbtChartYFraction', () {
    test('the low end of the range is 0.0, the high end is 1.0', () {
      expect(bbtChartYFraction(36.0, 36.0, 37.0), 0.0);
      expect(bbtChartYFraction(37.0, 36.0, 37.0), 1.0);
    });

    test('the midpoint is 0.5', () {
      expect(bbtChartYFraction(36.5, 36.0, 37.0), closeTo(0.5, 1e-9));
    });

    test('a degenerate (non-positive) range never divides by zero', () {
      expect(bbtChartYFraction(36.0, 36.0, 36.0), 0.5);
    });
  });

  group('bbtChartCycleOpacity', () {
    test('a single cycle shown is always full opacity', () {
      expect(bbtChartCycleOpacity(0, 1), 1.0);
    });

    test('the most recent cycle (index 0) is always full opacity', () {
      expect(bbtChartCycleOpacity(0, 6), 1.0);
    });

    test('opacity strictly decreases moving away from the most recent '
        'cycle', () {
      final opacities = [for (var i = 0; i < 6; i++) bbtChartCycleOpacity(i, 6)];
      for (var i = 1; i < opacities.length; i++) {
        expect(opacities[i], lessThan(opacities[i - 1]));
      }
    });

    test('opacity never drops below the floor', () {
      expect(bbtChartCycleOpacity(5, 6), greaterThanOrEqualTo(0.35));
    });
  });
}
