/// Tests for issue #143's calendar-method fertile-window/ovulation
/// estimation: window arithmetic at the default and a custom luteal-phase
/// length, tier passthrough (never a separately derived tier), `null` for
/// the not-enough-history case, and the shared `fertileWindowFor` core
/// `forecast_test.dart`'s per-cycle degradation also exercises.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

LocalDate _d(int y, int m, int day) => LocalDate(y, m, day);

/// A minimal [ActivePrediction] with only [estimatedNextStart] and [tier]
/// varied — the rest are dummy, internally-consistent values irrelevant to
/// this file's pure arithmetic/tier-passthrough assertions.
ActivePrediction _prediction({
  required LocalDate estimatedNextStart,
  CycleConfidence tier = CycleConfidence.high,
}) {
  return ActivePrediction(
    today: _d(2026, 8, 1),
    lastEpisodeStart: _d(2026, 7, 1),
    estimatedNextStart: estimatedNextStart,
    originalEstimatedNextStart: estimatedNextStart,
    averagedCycleLengths: const [30, 30, 30],
    meanCycleLengthDays: 30,
    cycleDay: 1,
    duringEpisode: false,
    completedCycleCount: 6,
    validCycleCount: 6,
    tier: tier,
  );
}

/// An [ActivePrediction] with a fully explicit [forecast] (issue #143
/// review, `currentFertileWindow`'s own suite below): unlike [_prediction],
/// which always leaves `forecast` at its default `const []`, this lets a
/// test control each forecast cycle's own start/tier directly — the exact
/// shape needed to prove `currentFertileWindow` reads a *forecast cycle's*
/// tier, not [ActivePrediction.tier] (which happens to equal
/// `forecast.first.tier` by the #299 invariant, so a test that never varies
/// them independently could not tell the two apart).
ActivePrediction _predictionWithForecast({
  required LocalDate today,
  required List<PredictedCycle> forecast,
  CycleConfidence tier = CycleConfidence.high,
}) {
  return ActivePrediction(
    today: today,
    lastEpisodeStart: _d(2026, 7, 1),
    estimatedNextStart: forecast.isEmpty ? today : forecast.first.start,
    originalEstimatedNextStart: forecast.isEmpty ? today : forecast.first.start,
    averagedCycleLengths: const [30, 30, 30],
    meanCycleLengthDays: 30,
    cycleDay: 1,
    duringEpisode: false,
    completedCycleCount: 6,
    validCycleCount: 6,
    tier: tier,
    forecast: forecast,
  );
}

void main() {
  group('estimateFertileWindow', () {
    test('null prediction -> null (the NotEnoughHistory case)', () {
      expect(estimateFertileWindow(null), isNull);
    });

    test('default 14-day luteal phase: ovulation and window boundaries', () {
      final prediction = _prediction(estimatedNextStart: _d(2026, 9, 4));
      final fertile = estimateFertileWindow(prediction)!;

      expect(fertile.estimatedOvulation, _d(2026, 8, 21));
      expect(fertile.windowStart, _d(2026, 8, 16));
      expect(fertile.windowEnd, _d(2026, 8, 22));
      // Window spans lead + ovulation day + trail = 5 + 1 + 1 = 7 days.
      expect(
        fertile.windowEnd.difference(fertile.windowStart) + 1,
        kFertileWindowLeadDays + 1 + kFertileWindowTrailDays,
      );
    });

    test('kDefaultLutealPhaseDays is 14 (Clue-matched)', () {
      expect(kDefaultLutealPhaseDays, 14);
    });

    test('custom luteal-phase length shifts ovulation and the window with it', () {
      final prediction = _prediction(estimatedNextStart: _d(2026, 9, 4));
      final fertile =
          estimateFertileWindow(prediction, lutealPhaseDays: 10)!;

      expect(fertile.estimatedOvulation, _d(2026, 8, 25));
      expect(fertile.windowStart, _d(2026, 8, 20));
      expect(fertile.windowEnd, _d(2026, 8, 26));
    });

    test('a month/year boundary crossing computes correctly', () {
      // Jan 3, 2027 minus 14 days crosses back into December 2026.
      final prediction = _prediction(estimatedNextStart: _d(2027, 1, 3));
      final fertile = estimateFertileWindow(prediction)!;

      expect(fertile.estimatedOvulation, _d(2026, 12, 20));
      expect(fertile.windowStart, _d(2026, 12, 15));
      expect(fertile.windowEnd, _d(2026, 12, 21));
    });

    test('tier passthrough: carries the exact same tier as the period '
        'prediction, for every tier value', () {
      for (final tier in CycleConfidence.values) {
        final prediction = _prediction(
          estimatedNextStart: _d(2026, 9, 4),
          tier: tier,
        );
        expect(estimateFertileWindow(prediction)!.tier, tier);
      }
    });
  });

  group('fertileWindowFor (the shared core)', () {
    test('matches estimateFertileWindow for the same inputs', () {
      const tier = CycleConfidence.learning;
      final viaCore = fertileWindowFor(start: _d(2026, 9, 4), tier: tier);
      final viaPrediction = estimateFertileWindow(
        _prediction(estimatedNextStart: _d(2026, 9, 4), tier: tier),
      )!;

      expect(viaCore.estimatedOvulation, viaPrediction.estimatedOvulation);
      expect(viaCore.windowStart, viaPrediction.windowStart);
      expect(viaCore.windowEnd, viaPrediction.windowEnd);
      expect(viaCore.tier, viaPrediction.tier);
    });

    test('a zero luteal phase is still well-defined (ovulation == start)', () {
      final fertile = fertileWindowFor(
        start: _d(2026, 9, 4),
        tier: CycleConfidence.high,
        lutealPhaseDays: 0,
      );
      expect(fertile.estimatedOvulation, _d(2026, 9, 4));
      expect(fertile.windowStart, _d(2026, 8, 30));
      expect(fertile.windowEnd, _d(2026, 9, 5));
    });

    test('toString names ovulation, window, and tier', () {
      final fertile = fertileWindowFor(
        start: _d(2026, 9, 4),
        tier: CycleConfidence.high,
      );
      final text = fertile.toString();
      expect(text, contains('2026-08-21'));
      expect(text, contains('high'));
    });
  });

  group('currentFertileWindow (issue #143 review)', () {
    test('null prediction -> null (the NotEnoughHistory case)', () {
      expect(currentFertileWindow(null), isNull);
    });

    test("the first forecast cycle's window, when it has not passed", () {
      // Cycle 1's window is Aug 16-22 (ovulation Aug 21); "today" Aug 20
      // sits inside it, so it has not passed.
      final prediction = _predictionWithForecast(
        today: _d(2026, 8, 20),
        forecast: [
          PredictedCycle(
            cycleIndex: 1,
            start: LocalDate(2026, 9, 4),
            estimatedPeriodLengthDays: 4,
            tier: CycleConfidence.high,
            spreadDays: 0,
          ),
        ],
      );
      final fertile = currentFertileWindow(prediction)!;
      expect(fertile.windowStart, _d(2026, 8, 16));
      expect(fertile.windowEnd, _d(2026, 8, 22));
      expect(fertile.tier, CycleConfidence.high);
    });

    test(
        "cycle 1's window already passed -> falls through to cycle 2's own "
        "window, at cycle 2's own (different) tier, not "
        "ActivePrediction.tier / cycle 1's tier (the contested overlap "
        'case — issue #143 review)', () {
      // Cycle 1: start Sep 4, high -> ovulation Aug 21, window Aug 16-22
      // (already before "today" below). Cycle 2: start Oct 4, degraded to
      // `learning` -> ovulation Sep 20, window Sep 15-21 (not yet past).
      final prediction = _predictionWithForecast(
        today: _d(2026, 9, 18),
        tier: CycleConfidence.high, // the live/first-cycle tier
        forecast: [
          PredictedCycle(
            cycleIndex: 1,
            start: LocalDate(2026, 9, 4),
            estimatedPeriodLengthDays: 4,
            tier: CycleConfidence.high,
            spreadDays: 1,
          ),
          PredictedCycle(
            cycleIndex: 2,
            start: LocalDate(2026, 10, 4),
            estimatedPeriodLengthDays: 4,
            tier: CycleConfidence.learning,
            spreadDays: 1.4,
          ),
        ],
      );
      final fertile = currentFertileWindow(prediction)!;
      expect(fertile.windowStart, _d(2026, 9, 15));
      expect(fertile.windowEnd, _d(2026, 9, 21));
      expect(
        fertile.tier,
        CycleConfidence.learning,
        reason: "must read cycle 2's own tier, never fall back to "
            'ActivePrediction.tier (high, cycle 1\'s tier)',
      );
    });

    test('every forecasted cycle\'s window already passed -> null '
        '(defensive: an empty or entirely-stale forecast hides the row '
        'rather than showing something misleading)', () {
      final prediction = _predictionWithForecast(
        today: _d(2027, 1, 1),
        forecast: [
          PredictedCycle(
            cycleIndex: 1,
            start: LocalDate(2026, 9, 4),
            estimatedPeriodLengthDays: 4,
            tier: CycleConfidence.high,
            spreadDays: 0,
          ),
        ],
      );
      expect(currentFertileWindow(prediction), isNull);

      final emptyForecast = _predictionWithForecast(
        today: _d(2026, 8, 30),
        forecast: const [],
      );
      expect(currentFertileWindow(emptyForecast), isNull);
    });

    test('a custom luteal-phase length still applies to whichever cycle '
        'is returned', () {
      // With lutealPhaseDays 10, cycle 1's window becomes Aug 20-26; "today"
      // Aug 20 sits at its very start, so it has not passed.
      final prediction = _predictionWithForecast(
        today: _d(2026, 8, 20),
        forecast: [
          PredictedCycle(
            cycleIndex: 1,
            start: LocalDate(2026, 9, 4),
            estimatedPeriodLengthDays: 4,
            tier: CycleConfidence.high,
            spreadDays: 0,
          ),
        ],
      );
      final fertile = currentFertileWindow(prediction, lutealPhaseDays: 10)!;
      expect(fertile.estimatedOvulation, _d(2026, 8, 25));
    });
  });
}
