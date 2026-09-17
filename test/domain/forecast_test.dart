/// Tests for issue #133's forward-forecast derivation, rebuilt for issue
/// #300 (calendar forecast consumes the engine's `ActivePrediction.forecast`
/// instead of its own curve): [deriveForecast] is now a thin adapter, so
/// these tests prove the adapter's own job — re-indexing, horizon
/// truncation, and each cycle's own fertile window — while deferring the
/// confidence-degradation/spread-widening curve itself to
/// `prediction_test.dart`'s coverage of `ActivePrediction.forecast` (the
/// single place that curve now lives). `forecastDayCells`'s per-date
/// rendering rules are otherwise unchanged by #300 and still fully covered
/// here.
///
/// Issue #143: each [ForecastCycle]'s own fertile window and its
/// degradation in step with [ForecastCycle.tier], plus [ForecastDayCell
/// .fertileWindow] marking on the calendar-cell lookup.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart';
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/pms.dart';
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
  final active = prediction as ActivePrediction;
  return (
    deriveForecast(prediction: active, today: today, horizonMonths: horizonMonths),
    active,
  );
}

void main() {
  group('deriveForecast', () {
    test('the first cycle equals the active estimate itself -- start and '
        'tier both (issue #300 AC: the calendar and the overview headline '
        'can never disagree, because both trace back to the same '
        'ActivePrediction.forecast.first)', () {
      final (cycles, active) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(cycles.first.start, active.estimatedNextStart);
      expect(cycles.first.tier, active.tier);
      expect(cycles.first.index, 0);
    });

    test('every cycle mirrors the engine''s own ActivePrediction.forecast '
        'entry -- start, tier, spread, and period length are read, never '
        're-derived', () {
      final (cycles, active) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(cycles, isNotEmpty);
      expect(cycles.length, lessThanOrEqualTo(active.forecast.length));
      for (var i = 0; i < cycles.length; i++) {
        final predicted = active.forecast[i];
        expect(cycles[i].index, i, reason: 'cycle $i index (0-based)');
        expect(cycles[i].index, predicted.cycleIndex - 1,
            reason: 'cycle $i re-indexes the engine''s 1-based cycleIndex');
        expect(cycles[i].start, predicted.start, reason: 'cycle $i start');
        expect(cycles[i].tier, predicted.tier, reason: 'cycle $i tier');
        expect(cycles[i].spreadDays, predicted.spreadDays.round(),
            reason: 'cycle $i spreadDays');
        expect(cycles[i].periodLengthDays, predicted.estimatedPeriodLengthDays,
            reason: 'cycle $i periodLengthDays');
      }
    });

    test('lengthDays is the constant chaining step every cycle shares '
        '(rounded meanCycleLengthDays), the same value the engine chains '
        'PredictedCycle.start by', () {
      final (cycles, active) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      final expected = active.meanCycleLengthDays.round();
      for (final cycle in cycles) {
        expect(cycle.lengthDays, expected);
      }
      expect(cycles.first.lengthDays, 30);
    });

    test('bleed length comes from the engine''s own estimated period '
        'length', () {
      final (cycles, _) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      expect(cycles.first.periodLengthDays, 4);
      expect(cycles.first.end, _d(2026, 9, 7));
    });

    test('the engine''s horizon-sized forecast covers the whole navigable '
        'horizon (issue #693) -- a 12-month horizon over 30-day steady '
        'cycles needs 13 cycles, which the pre-#693 fixed 12-cycle cap '
        'truncated one cycle short of the navigable horizon', () {
      final (cycles, active) = _steadyForecast(
        _d(2026, 8, 30),
        kForecastHorizonMonths,
      );
      // Estimate 2026-09-04, horizon ends 2027-08-31, 30-day steps:
      // 30*(i-1) ≤ 361 days of headroom → 13 cycles, the last starting
      // 2027-08-30 (a 14th would start 2027-09-29, past the horizon).
      expect(active.forecast.length, 13,
          reason: 'the engine emits every cycle up to the horizon '
              '(kPredictionHorizonMonths), capped by kMaxForecastCycles');
      expect(cycles.length, 13,
          reason: 'every engine cycle here starts before the 12-month '
              'horizon ends, so the adapter truncates nothing -- engine '
              'and calendar agree on the horizon by construction (#693)');
      expect(cycles.last.start, active.forecast.last.start);
      expect(cycles.last.start, _d(2027, 8, 30));
    });

    test('a shorter horizon still truncates below the engine''s own '
        'forecast (issue #693 kept this adapter''s horizon cut)', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      // Horizon ends 2026-10-31: starts Sep 4, Oct 4 -> 2 cycles.
      expect(cycles.length, 2);
      expect(cycles.last.start, _d(2026, 10, 4));
    });

    test('irregular histories never upgrade with distance (the engine''s '
        'own tier-stepping floors at irregular, same as before #300)', () {
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
      final active = computePredictionFromEntries(
        entries: entries,
        today: today,
      ) as ActivePrediction;
      expect(active.tier, CycleConfidence.irregular);
      final cycles = deriveForecast(
        prediction: active,
        today: today,
        horizonMonths: 1,
      );
      expect(cycles, isNotEmpty);
      for (final cycle in cycles) {
        expect(cycle.tier, CycleConfidence.irregular);
      }
    });

    test('a degenerate zero-length engine forecast derives nothing '
        '(defensive: the engine itself never emits a zero-length forecast '
        'for a real ActivePrediction, but a hand-built fixture with an '
        'empty forecast list must not crash the adapter)', () {
      final prediction = ActivePrediction(
        today: _d(2026, 8, 30),
        lastEpisodeStart: _d(2026, 8, 5),
        estimatedNextStart: _d(2026, 9, 4),
        originalEstimatedNextStart: _d(2026, 9, 4),
        averagedCycleLengths: const [30, 30, 30],
        meanCycleLengthDays: 30,
        cycleDay: 26,
        duringEpisode: false,
        completedCycleCount: 5,
        validCycleCount: 5,
        forecast: const [],
      );
      expect(
        deriveForecast(prediction: prediction, today: _d(2026, 8, 30)),
        isEmpty,
      );
    });

    test('each cycle carries its own fertile window, at that cycle''s own '
        'engine-computed tier — issue #143', () {
      final (cycles, active) = _steadyForecast(
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
      expect(cycles.first.fertileWindow!.estimatedOvulation,
          expectedFirst.estimatedOvulation);
      expect(cycles.first.fertileWindow!.windowStart, expectedFirst.windowStart);
      expect(cycles.first.fertileWindow!.windowEnd, expectedFirst.windowEnd);
      expect(cycles.first.fertileWindow!.tier, CycleConfidence.high);

      // Cycle 1: its fertile window carries whatever tier the engine gave
      // that cycle (read from active.forecast, never hand-assumed) -- the
      // fertile window's own tier must always track its owning cycle's
      // tier, whatever that engine-computed value is.
      expect(cycles[1].start, active.forecast[1].start);
      expect(cycles[1].fertileWindow!.tier, cycles[1].tier);
      expect(
        cycles[1].fertileWindow!.estimatedOvulation,
        cycles[1].start.addDays(-kDefaultLutealPhaseDays),
      );
    });

    test(
        'Issue LLA-064: a regimen-schedule (pack-driven) prediction never '
        'gets a fertile window on any forecast cycle', () {
      final prediction = ActivePrediction(
        today: _d(2026, 1, 15),
        lastEpisodeStart: _d(2026, 1, 1),
        estimatedNextStart: _d(2026, 1, 29),
        originalEstimatedNextStart: _d(2026, 1, 29),
        averagedCycleLengths: const [],
        meanCycleLengthDays: 28,
        cycleDay: 15,
        duringEpisode: false,
        completedCycleCount: 0,
        validCycleCount: 0,
        tier: CycleConfidence.high,
        basis: PredictionBasis.regimenSchedule,
        forecast: [
          PredictedCycle(
            cycleIndex: 1,
            start: _d(2026, 1, 29),
            estimatedPeriodLengthDays: 5,
            tier: CycleConfidence.high,
            spreadDays: 0,
          ),
          PredictedCycle(
            cycleIndex: 2,
            start: _d(2026, 2, 26),
            estimatedPeriodLengthDays: 5,
            tier: CycleConfidence.high,
            spreadDays: 0,
          ),
        ],
      );
      final cycles = deriveForecast(
        prediction: prediction,
        today: _d(2026, 1, 15),
        horizonMonths: 2,
      );
      expect(cycles, isNotEmpty);
      for (final cycle in cycles) {
        expect(cycle.fertileWindow, isNull);
      }
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

    test('later cycles carry bands only, at that cycle''s own '
        'engine-computed tier', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      final cell = cells[_d(2026, 10, 5).iso]!;
      expect(cell.predictedBleed, isTrue);
      expect(cell.cycleDayNumber, isNull);
      expect(cell.tier, cycles[1].tier);
      expect(cell.cycleIndex, 1);
    });

    test('PMS badges are data-driven: they cover the PmsEstimate band, '
        'clamped to after today (Issue #220)', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 1);
      // Issue #220: the band comes from the 6-cycle averages
      // (computePmsEstimate), not a fixed lead. Onset 5 / length 3 off the
      // 2026-09-04 estimate puts the band on Aug 30 … Sep 1; today is
      // Aug 30, so that first day is clamped away (past stays factual).
      final pms = PmsEstimate(
        meanOnsetDaysBeforeNextPeriod: 5,
        meanLengthDays: 3,
        usableIntervalCount: 4,
        tier: CycleConfidence.high,
        predictedStart: _d(2026, 8, 30),
        predictedEnd: _d(2026, 9, 1),
      );
      final cells = forecastDayCells(
        cycles: cycles,
        today: _d(2026, 8, 30),
        pms: pms,
      );
      for (final day in [_d(2026, 8, 31), _d(2026, 9, 1)]) {
        expect(cells[day.iso]!.pmsBadge, isTrue, reason: day.iso);
      }
      for (final day in [_d(2026, 8, 28), _d(2026, 8, 29), _d(2026, 8, 30)]) {
        expect(cells[day.iso], isNull, reason: '${day.iso} is not after today');
      }
      // Days outside the band carry no badge, even where the old fixed
      // 7-day lead window used to reach (Sep 2–3).
      for (final day in [_d(2026, 9, 2), _d(2026, 9, 3)]) {
        expect(cells[day.iso]?.pmsBadge ?? false, isFalse, reason: day.iso);
      }
    });

    test('below the PMS hard minimum (no PmsEstimate) no PMS badge renders '
        'anywhere; cramps keep their fixed window', () {
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 1);
      final estimate = _d(2026, 9, 4);
      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      for (final cell in cells.values) {
        expect(cell.pmsBadge, isFalse,
            reason: 'Issue #220: no band without the logged-interval minimum');
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

    test('fertile window marks each cycle''s own days, at that cycle''s '
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
        expect(cell.tier, cycles[2].tier, reason: day.iso);
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
      // horizonMonths 2 -> cycles 0 (Sep 4) and 1 (Oct 4).
      // Cycle 1's own fertile window (ovulation Sep 20, band Sep 15-21)
      // sits inside cycle 0's full 30-day numeral span (Sep 4 - Oct 3,
      // since index-0 walks its whole length) — so those cells already
      // exist (numeral, no band, cycle 0's own tier/index) before the
      // fertile-marking pass ever reaches them.
      final (cycles, _) = _steadyForecast(_d(2026, 8, 30), 2);
      expect(cycles[1].start, _d(2026, 10, 4));
      expect(cycles[1].fertileWindow!.windowStart, _d(2026, 9, 15));
      expect(cycles[1].fertileWindow!.windowEnd, _d(2026, 9, 21));

      final cells = forecastDayCells(cycles: cycles, today: _d(2026, 8, 30));
      for (var i = 0; i < 7; i++) {
        final day = _d(2026, 9, 15).addDays(i);
        final cell = cells[day.iso]!;
        expect(cell.fertileWindow, isTrue, reason: day.iso);
        // The cell's general tier/cycleIndex still belong to cycle 0's
        // numeral span (unchanged by the fertile pass) --
        expect(cell.tier, cycles[0].tier, reason: day.iso);
        expect(cell.cycleIndex, 0, reason: day.iso);
        expect(cell.cycleDayNumber, isNotNull, reason: day.iso);
        // -- but the FERTILE-specific fields correctly carry cycle 1's own
        // tier/index, not cycle 0's, which is the fix under test.
        expect(cell.fertileTier, cycles[1].tier, reason: day.iso);
        expect(cell.fertileCycleIndex, 1, reason: day.iso);
      }
    });
  });
}
