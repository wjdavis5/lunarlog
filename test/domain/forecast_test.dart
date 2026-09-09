/// Tests for issue #133's forward-forecast derivation (U1): cycle
/// chaining off the active estimate, tier degradation, spread growth,
/// horizon coverage, and the per-date cells the calendar renders — band
/// days, first-cycle-only numerals, fixed-offset badges, and the
/// past-stays-factual clamp.
///
/// Issue #143: each [ForecastCycle]'s own fertile window and its
/// degradation in step with [ForecastCycle.tier], plus [ForecastDayCell
/// .fertileWindow] marking on the calendar-cell lookup.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart';
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

/// Steady 30-day cycles with 4-day bleeds, the open cycle starting
/// 2026-08-05; today 2026-08-30 → estimate 2026-09-04, confidence high,
/// variation 0. Six completed cycles — a full kAverageWindowCycles(6)
/// window, the minimum for `high` confidence (issue #213 item 5); the
/// extra cycle is prepended (not appended) so every other date here stays
/// unchanged.
const List<(int, int, int)> kSteadyStarts = [
  (2026, 2, 6),
  (2026, 3, 8),
  (2026, 4, 7),
  (2026, 5, 7),
  (2026, 6, 6),
  (2026, 7, 6),
  (2026, 8, 5),
];

LocalDate _d(int y, int m, int day) => LocalDate(y, m, day);

DayEntry _bleed(String profileId, LocalDate date) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: date,
  tz: 'America/Chicago',
  flow: FlowLevel.medium,
  updatedAt: DateTime.utc(2026, 1, 1),
);

(List<ForecastCycle>, ActivePrediction) _steadyForecast(
  LocalDate today,
  int horizonMonths,
) {
  final entries = [
    for (final (y, m, d) in kSteadyStarts)
      for (var i = 0; i < 4; i++) _bleed('p', _d(y, m, d).addDays(i)),
  ];
  final prediction = computePredictionFromEntries(
    entries: entries,
    today: today,
  );
  final history = deriveCycleHistoryFromEntries(entries: entries, today: today);
  final active = prediction as ActivePrediction;
  return (
    deriveForecast(
      prediction: active,
      history: history,
      today: today,
      horizonMonths: horizonMonths,
    ),
    active,
  );
}

void main() {
  group('deriveForecast', () {
    test('chains cycles off the estimate by the mean cycle length', () {
      final (cycles, active) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(active.estimatedNextStart, _d(2026, 9, 4));
      expect(cycles.first.start, _d(2026, 9, 4));
      for (var i = 0; i < cycles.length; i++) {
        expect(cycles[i].index, i);
        expect(
          cycles[i].start,
          _d(2026, 9, 4).addDays(30 * i),
          reason: 'cycle $i start',
        );
      }
    });

    test('bleed length comes from the mean episode length', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(cycles.first.periodLengthDays, 4);
      expect(cycles.first.end, _d(2026, 9, 7));
      expect(
        cycles.first.lengthDays,
        30,
        reason: 'full cycle length is the chaining step',
      );
    });

    test('covers the whole navigable horizon and no further', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      // Today Aug 2026 + 12 months → horizon ends 2027-08-31. Starts are
      // Sep 4 2026 + 30k; the last one at or before the horizon is
      // k = 12 (Aug 30 2027), so 13 cycles.
      expect(cycles.length, 13);
      expect(cycles.last.start, _d(2027, 8, 30));
      expect(cycles.last.start.isAfter(_d(2027, 8, 31)), isFalse);
      expect(
        cycles.last.start.addDays(30).isAfter(_d(2027, 8, 31)),
        isTrue,
        reason: 'the next cycle would pass the horizon',
      );
    });

    test('a shorter horizon derives fewer cycles', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      // Horizon ends 2026-10-31: starts Sep 4, Oct 4 → 2 cycles.
      expect(cycles.length, 2);
    });

    test('cycle 0 keeps the history tier; later cycles step down', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(
        cycles.first.tier,
        CycleConfidence.high,
        reason: 'steady history reads high',
      );
      for (var i = 1; i < cycles.length; i++) {
        expect(
          cycles[i].tier,
          CycleConfidence.learning,
          reason: 'cycle $i compounds the uncertainty',
        );
      }
    });

    test('irregular histories never upgrade with distance', () {
      // Lengths 65, 90, 95, 100 (outliers) then 28, 28, 28: valid ratio
      // 3/7 ≈ 0.43, under the engine's 0.5 threshold — reads irregular;
      // every cycle in the forecast stays irregular.
      final starts = [
        _d(2025, 5, 28), // 65: outlier
        _d(2025, 8, 1),
        _d(2025, 10, 30), // 90
        _d(2026, 2, 2), // 95
        _d(2026, 5, 13), // 100
        _d(2026, 6, 10), // 28
        _d(2026, 7, 8), // 28
        _d(2026, 8, 5), // 28, open
      ];
      final entries = [
        for (final start in starts)
          for (var i = 0; i < 4; i++) _bleed('p', start.addDays(i)),
      ];
      final today = _d(2026, 8, 30);
      final history = deriveCycleHistoryFromEntries(
        entries: entries,
        today: today,
      );
      expect(history.confidence, CycleConfidence.irregular);
      final cycles = deriveForecast(
        prediction: computePredictionFromEntries(
          entries: entries,
          today: today,
        ) as ActivePrediction,
        history: history,
        today: today,
        horizonMonths: 1,
      );
      for (final cycle in cycles) {
        expect(cycle.tier, CycleConfidence.irregular);
      }
    });

    test('spread widens one day per cycle out', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(cycles.first.spreadDays, 0, reason: 'steady history, no spread');
      expect(cycles[5].spreadDays, 5);
      expect(cycles.last.spreadDays, 12);
    });

    test('variation feeds the base spread', () {
      // Lengths 28, 28, 34 → variation 6, mean 30: spread = 6 + index.
      final starts = [
        _d(2026, 1, 5),
        _d(2026, 2, 2),
        _d(2026, 3, 2),
        _d(2026, 4, 5),
      ];
      final entries = [
        for (final start in starts)
          for (var i = 0; i < 4; i++) _bleed('p', start.addDays(i)),
      ];
      final today = _d(2026, 4, 7);
      final history = deriveCycleHistoryFromEntries(
        entries: entries,
        today: today,
      );
      expect(history.variationDays, 6);
      final cycles = deriveForecast(
        prediction: computePredictionFromEntries(
          entries: entries,
          today: today,
        ) as ActivePrediction,
        history: history,
        today: today,
        horizonMonths: 2,
      );
      expect(cycles.first.spreadDays, 6);
      expect(cycles[1].spreadDays, 7);
    });

    test('a degenerate zero-day mean derives nothing (defensive guard)', () {
      final prediction = ActivePrediction(
        today: _d(2026, 8, 30),
        lastEpisodeStart: _d(2026, 8, 5),
        estimatedNextStart: _d(2026, 9, 4),
        originalEstimatedNextStart: _d(2026, 9, 4),
        averagedCycleLengths: const [30, 30, 30],
        meanCycleLengthDays: 0,
        cycleDay: 26,
        duringEpisode: false,
        completedCycleCount: 5,
        validCycleCount: 5,
      );
      expect(
        deriveForecast(
          prediction: prediction,
          history: deriveCycleHistory(
            episodes: const [],
            today: _d(2026, 8, 30),
          ),
          today: _d(2026, 8, 30),
        ),
        isEmpty,
      );
    });

    test('degradeForecastTier steps high down once and floors the rest', () {
      expect(
        degradeForecastTier(CycleConfidence.high),
        CycleConfidence.learning,
      );
      expect(
        degradeForecastTier(CycleConfidence.learning),
        CycleConfidence.learning,
      );
      expect(
        degradeForecastTier(CycleConfidence.irregular),
        CycleConfidence.irregular,
      );
    });

    test('each cycle carries its own fertile window, at that cycle\'s own '
        '(degrading) tier — issue #143', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      // Cycle 0: start Sep 4, high tier — fertile window matches the same
      // core `fertileWindowFor` the domain-level `fertile_window_test.dart`
      // exercises directly.
      final expectedFirst = fertileWindowFor(
        start: _d(2026, 9, 4),
        tier: CycleConfidence.high,
      );
      expect(cycles.first.fertileWindow.estimatedOvulation,
          expectedFirst.estimatedOvulation);
      expect(cycles.first.fertileWindow.windowStart, expectedFirst.windowStart);
      expect(cycles.first.fertileWindow.windowEnd, expectedFirst.windowEnd);
      expect(cycles.first.fertileWindow.tier, CycleConfidence.high);

      // Cycle 1: start Oct 4, already stepped down to learning — its
      // fertile window must carry that same degraded tier, not cycle 0's.
      expect(cycles[1].start, _d(2026, 10, 4));
      expect(cycles[1].tier, CycleConfidence.learning);
      expect(cycles[1].fertileWindow.tier, CycleConfidence.learning);
      expect(
        cycles[1].fertileWindow.estimatedOvulation,
        _d(2026, 10, 4).addDays(-kDefaultLutealPhaseDays),
      );
    });
  });

  group('forecastDayCells', () {
    test('bands the first cycle with numerals across its whole length', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      // Cycle 0: Sep 4 2026, 4-day band, 30-day cycle.
      for (var i = 0; i < 30; i++) {
        final date = _d(2026, 9, 4).addDays(i);
        final cell = cells[date.iso]!;
        expect(
          cell.cycleDayNumber,
          i + 1,
          reason: 'numerals cover the whole first cycle (${date.iso})',
        );
        expect(cell.predictedBleed, i < 4, reason: 'band is 4 days');
        expect(cell.tier, CycleConfidence.high);
      }
      // Numerals never chain: October's days outside cycle 0 carry none.
      expect(
        cells[_d(2026, 10, 4).iso]!.cycleDayNumber,
        isNull,
        reason: 'cycle 1 starts Oct 4',
      );
      expect(
        cells[_d(2026, 10, 4).iso]!.predictedBleed,
        isTrue,
        reason: 'cycle 1 still has a band',
      );
      expect(
        cells[_d(2026, 10, 8).iso],
        isNull,
        reason: 'cycle 1 non-band days carry nothing',
      );
    });

    test('later cycles carry bands only, at the degraded tier', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      final cell = cells[_d(2026, 10, 5).iso]!;
      expect(cell.predictedBleed, isTrue);
      expect(cell.cycleDayNumber, isNull);
      expect(cell.tier, CycleConfidence.learning);
      expect(cell.cycleIndex, 1);
    });

    test('PMS badges cover estimate − 7 … − 1; cramps − 2 … + 2', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 1);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      final estimate = _d(2026, 9, 4);
      // Today is Aug 30, so the window's Aug 28-30 days are clamped away
      // (past stays factual); Aug 31 through Sep 3 carry the badge.
      for (final day in [
        _d(2026, 8, 31),
        _d(2026, 9, 1),
        _d(2026, 9, 2),
        _d(2026, 9, 3),
      ]) {
        expect(cells[day.iso]!.pmsBadge, isTrue, reason: day.iso);
      }
      for (final day in [_d(2026, 8, 28), _d(2026, 8, 29), _d(2026, 8, 30)]) {
        expect(cells[day.iso], isNull, reason: '${day.iso} is not after today');
      }
      for (var i = -2; i <= 2; i++) {
        expect(
          cells[estimate.addDays(i).iso]!.crampsBadge,
          isTrue,
          reason:
              'estimate ${i == 0
                  ? ''
                  : i >= 0
                  ? '+ '
                  : '− '}$i',
        );
      }
      // The two windows overlap at − 2 and − 1.
      expect(cells[estimate.addDays(-2).iso]!.crampsBadge, isTrue);
      expect(cells[estimate.addDays(-2).iso]!.predictedBleed, isFalse);
      // Band days inside the cramps window keep band + numeral + badge.
      final day1 = cells[estimate.iso]!;
      expect(day1.predictedBleed, isTrue);
      expect(day1.cycleDayNumber, 1);
      expect(day1.crampsBadge, isTrue);
    });

    test('nothing is derived at or before today (past stays factual)', () {
      // Estimate 2026-05-24, two days before today 2026-05-26: the whole
      // PMS window and most of the band are in the past.
      final starts = [
        _d(2026, 2, 1),
        _d(2026, 3, 1),
        _d(2026, 3, 29),
        _d(2026, 4, 26),
      ];
      final entries = [
        for (final start in starts)
          for (var i = 0; i < 4; i++) _bleed('p', start.addDays(i)),
      ];
      final today = _d(2026, 5, 26);
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: today,
      ) as ActivePrediction;
      expect(prediction.estimatedNextStart, _d(2026, 5, 24));
      final cycles = deriveForecast(
        prediction: prediction,
        history: deriveCycleHistoryFromEntries(
          entries: entries,
          today: today,
        ),
        today: today,
        horizonMonths: 1,
      );
      final cells = forecastDayCells(cycles: cycles, today: today);
      expect(
        cells[_d(2026, 5, 24).iso],
        isNull,
        reason: 'band day in the past',
      );
      expect(
        cells[_d(2026, 5, 26).iso],
        isNull,
        reason: 'cramps-window day equal to today',
      );
      expect(cells[_d(2026, 5, 17).iso], isNull, reason: 'PMS window past');
      final surviving = cells[_d(2026, 5, 27).iso]!;
      expect(surviving.predictedBleed, isTrue);
      expect(surviving.cycleDayNumber, 4);
      expect(
        surviving.crampsBadge,
        isFalse,
        reason: 'the cramps window ended at the estimate',
      );
    });

    test('empty cycles derive no cells', () {
      expect(
        forecastDayCells(cycles: const [], today: _d(2026, 8, 30)),
        isEmpty,
      );
    });

    test('fertile window marks each cycle\'s own days, at that cycle\'s '
        'own tier — issue #143', () {
      // horizonMonths 3 reaches cycle 2 (Nov 3) — cycle 1's own fertile
      // window (Sep 15-21) sits inside cycle 0's full 30-day numeral span
      // (Sep 4 - Oct 3, since index-0 walks its whole length, not just its
      // band), so this test deliberately reads cycle *2* instead, whose
      // fertile window (Oct 15-21) falls in the gap between cycle 0's
      // numeral span and cycle 1's own 4-day band (Oct 4-7) — an
      // uncontested range where the fertile marking is the only thing
      // deriving a cell at all.
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 3);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      expect(cycles[2].start, _d(2026, 11, 3));
      expect(cycles[2].tier, CycleConfidence.learning);

      // Cycle 0's own fertile window (ovulation Aug 21, band Aug 16-22)
      // falls entirely before today (Aug 30) — past stays factual, so none
      // of those days are derived at all.
      for (final day in [_d(2026, 8, 16), _d(2026, 8, 21), _d(2026, 8, 22)]) {
        expect(cells[day.iso], isNull, reason: '${day.iso} is in the past');
      }

      // Cycle 2's fertile window: ovulation Oct 20, band Oct 15-21.
      for (var i = 0; i < 7; i++) {
        final day = _d(2026, 10, 15).addDays(i);
        final cell = cells[day.iso]!;
        expect(cell.fertileWindow, isTrue, reason: day.iso);
        expect(cell.tier, CycleConfidence.learning, reason: day.iso);
        expect(cell.cycleIndex, 2, reason: day.iso);
        expect(
          cell.predictedBleed,
          isFalse,
          reason: 'the fertile window never overlaps its own bleed band',
        );
      }
      // A day just outside the window on either side carries nothing.
      expect(cells[_d(2026, 10, 14).iso], isNull);
      expect(cells[_d(2026, 10, 22).iso], isNull);
    });

    test(
        "cycle 1's own fertile window inherits its OWN tier/index even "
        "when it lands on a date cycle 0's numeral span already claimed — "
        'the contested overlap case (issue #143 review), not the '
        'uncontested cycle-2 case above', () {
      // horizonMonths 2 -> cycles 0 (Sep 4, high) and 1 (Oct 4, learning).
      // Cycle 1's own fertile window (ovulation Sep 20, band Sep 15-21)
      // sits inside cycle 0's full 30-day numeral span (Sep 4 - Oct 3,
      // since index-0 walks its whole length) — so those cells already
      // exist (numeral, no band, `tier: high`, `cycleIndex: 0`) before the
      // fertile-marking pass ever reaches them.
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      expect(cycles[1].start, _d(2026, 10, 4));
      expect(cycles[1].tier, CycleConfidence.learning);
      expect(cycles[1].fertileWindow.windowStart, _d(2026, 9, 15));
      expect(cycles[1].fertileWindow.windowEnd, _d(2026, 9, 21));

      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      for (var i = 0; i < 7; i++) {
        final day = _d(2026, 9, 15).addDays(i);
        final cell = cells[day.iso]!;
        expect(cell.fertileWindow, isTrue, reason: day.iso);
        // The cell's general tier/cycleIndex still belong to cycle 0's
        // numeral span (unchanged by the fertile pass) --
        expect(cell.tier, CycleConfidence.high, reason: day.iso);
        expect(cell.cycleIndex, 0, reason: day.iso);
        expect(cell.cycleDayNumber, isNotNull, reason: day.iso);
        // -- but the FERTILE-specific fields correctly carry cycle 1's own
        // (degraded) tier/index, not cycle 0's, which is the fix under
        // test.
        expect(cell.fertileTier, CycleConfidence.learning, reason: day.iso);
        expect(cell.fertileCycleIndex, 1, reason: day.iso);
      }
    });
  });
}
