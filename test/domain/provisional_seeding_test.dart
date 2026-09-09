/// Issue #218: the `provisional` confidence tier and the pure seeding
/// function `seedProvisionalPrediction` — seeding math, partial answers,
/// the validity gate, stale-facts roll-forward, and the forecast shape.
/// The displacement rule itself (real cycles displacing the seed) is
/// proven at the service level in `prediction_service_test.dart`, and the
/// no-facts path staying bit-identical is the existing
/// `prediction_test.dart` suite, unchanged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

void main() {
  final today = LocalDate(2026, 5, 20);

  group('CycleFacts.canSeed (issue #218 seeding gate)', () {
    test('a last-period date and a typical cycle length together seed', () {
      expect(
        CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
        ).canSeed,
        isTrue,
      );
    });

    test('every individually-skippable answer leaves nothing to seed', () {
      expect(CycleFacts.empty.canSeed, isFalse);
      expect(
        CycleFacts(typicalCycleLengthDays: 28).canSeed,
        isFalse,
        reason: 'no last-period date: a next start cannot be computed',
      );
      expect(
        CycleFacts(lastPeriodStart: LocalDate(2026, 4, 20)).canSeed,
        isFalse,
        reason: 'no typical cycle length: a next start cannot be computed',
      );
    });

    test('a cycle length outside the 15-60 validity window never seeds', () {
      // The engine itself would never treat a logged cycle of that length
      // as valid, so an estimate seeded from it could never later be
      // confirmed by real data.
      expect(
        CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 14,
        ).canSeed,
        isFalse,
      );
      expect(
        CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 61,
        ).canSeed,
        isFalse,
      );
      // The window's own boundaries are inclusive.
      expect(
        CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 15,
        ).canSeed,
        isTrue,
      );
      expect(
        CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 60,
        ).canSeed,
        isTrue,
      );
    });

    test('the typical period length alone never gates seeding', () {
      expect(
        CycleFacts(typicalPeriodLengthDays: 5).canSeed,
        isFalse,
      );
    });
  });

  group('seedProvisionalPrediction (issue #218 AC: immediate estimate)', () {
    test('seeds an ActivePrediction-equivalent at the provisional tier', () {
      final p = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      );
      expect(p, isA<ActivePrediction>());
      final active = p as ActivePrediction;
      expect(active.tier, CycleConfidence.provisional);
      expect(active.estimatedNextStart, LocalDate(2026, 5, 18),
          reason: 'last period start + typical cycle length');
      expect(active.originalEstimatedNextStart, LocalDate(2026, 5, 18));
      expect(active.meanCycleLengthDays, 28.0);
      expect(active.meanPeriodLengthDays, 5.0);
      expect(active.spreadDays, kProvisionalSpreadDays);
      expect(active.lastEpisodeStart, LocalDate(2026, 4, 20));
      expect(active.cycleDay, 31, reason: '2026-05-20 - 2026-04-20 + 1');
      expect(active.duringEpisode, isFalse,
          reason: 'the supplied bleed window (4/20-4/24) is long past');
      expect(active.daysLate, isNull);
      expect(active.unusuallyLongCycle, isFalse);
      expect(active.estimatedRangeStart, LocalDate(2026, 5, 14));
      expect(active.estimatedRangeEnd, LocalDate(2026, 5, 22));
    });

    test('claims no observed cycles: counts zero, no averaged lengths', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.averagedCycleLengths, isEmpty);
      expect(active.completedCycleCount, 0);
      expect(active.validCycleCount, 0);
    });

    test('builds the 12-cycle forecast off the supplied mean, anchored at '
        'the estimate, with the tier floored at provisional', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.forecast, hasLength(kPredictionWindowCycles));
      expect(active.forecast.first.start, active.estimatedNextStart);
      expect(active.forecast[1].start, LocalDate(2026, 6, 15));
      expect(active.forecast.last.start, LocalDate(2026, 6, 15).addDays(28 * 10));
      // The spread widens geometrically but the tier floors: there is no
      // lower honest rung below "computed from onboarding answers"
      // (`irregular` would claim observed variation a seed has no data
      // for), so every forecast cycle stays provisional.
      for (final cycle in active.forecast) {
        expect(cycle.tier, CycleConfidence.provisional);
        expect(cycle.estimatedPeriodLengthDays, 5);
      }
    });

    test('partial answers: cycle length without a last date (and vice '
        'versa) yields NotEnoughHistory, exactly like the computed path',
        () {
      for (final facts in [
        CycleFacts(typicalCycleLengthDays: 28),
        CycleFacts(lastPeriodStart: LocalDate(2026, 4, 20)),
        CycleFacts.empty,
      ]) {
        final p = seedProvisionalPrediction(facts: facts, today: today);
        expect(p, isA<NotEnoughHistory>(), reason: '$facts');
        final none = p as NotEnoughHistory;
        expect(none.episodeCount, 0);
        expect(none.completedCycleCount, 0);
        expect(none.validCycleCount, 0);
      }
    });

    test('partial answers: a missing period length falls back to '
        'kDefaultPeriodLengthDays (the same named fallback the computed '
        'path uses for an empty episode window)', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.meanPeriodLengthDays, kDefaultPeriodLengthDays.toDouble());
      expect(active.forecast.first.estimatedPeriodLengthDays,
          kDefaultPeriodLengthDays);
    });

    test('an out-of-window cycle length refuses to seed (storage keeps the '
        'answer; the predictor does not)', () {
      for (final length in [14, 61]) {
        final p = seedProvisionalPrediction(
          facts: CycleFacts(
            lastPeriodStart: LocalDate(2026, 4, 20),
            typicalCycleLengthDays: length,
          ),
          today: today,
        );
        expect(p, isA<NotEnoughHistory>(), reason: 'cycle length $length');
      }
    });

    test('a period length longer than the cycle clamps to the cycle '
        'length (mirrors the computed path\'s clamp)', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 40,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.meanPeriodLengthDays, 28.0);
    });

    test('today on the supplied start reads as cycle day 1, inside the '
        'derived bleed window', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 5, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.cycleDay, 1);
      expect(active.duringEpisode, isTrue);
    });

    test('a future-dated answer still reads as cycle day 1 (defensive '
        'clamp; the form bounds the picker)', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 5, 22),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.cycleDay, 1);
      expect(active.duringEpisode, isFalse);
    });

    test('a stale seed never freezes: the estimate rolls forward in whole '
        'supplied-cycle steps and the late count keeps growing (#221 '
        'posture, applied to the seed)', () {
      // Supplied start 2026-01-01 + 28 = 2026-01-29, 111 days past today.
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 1, 1),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.originalEstimatedNextStart, LocalDate(2026, 1, 29));
      expect(active.daysLate, 111);
      // 2026-01-29 rolls forward by whole 28-day steps to the first date
      // today is no more than kLateGraceDays (2) past: 2026-05-21.
      expect(active.estimatedNextStart, LocalDate(2026, 5, 21));
    });

    test('a supplied start more than kMaxOpenCycleDays ago is flagged '
        'unusually long and forced to irregular — provisional is '
        'displaced, never silently kept (#221 posture)', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 1, 1),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.unusuallyLongCycle, isTrue);
      expect(active.tier, CycleConfidence.irregular);
    });

    test('a fresh seed inside the open-cycle bound stays provisional and '
        'unflagged', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 5, 1),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(active.unusuallyLongCycle, isFalse);
      expect(active.tier, CycleConfidence.provisional);
    });
  });

  group('tier vocabulary (issue #218)', () {
    test('the provisional tier floors when stepped down', () {
      // `irregular` claims observed variation a seeded estimate has no
      // data for, so a far-out forecast cycle cannot degrade into it.
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      expect(
        active.forecast.every((c) => c.tier == CycleConfidence.provisional),
        isTrue,
      );
    });

    test('the domain label/summary name the tier honestly', () {
      expect(CycleConfidence.provisional.label, 'Provisional');
      expect(
        CycleConfidence.provisional.summary,
        contains('onboarding answers'),
      );
    });
  });

  group('computePrediction never returns provisional (displacement is '
      'structural)', () {
    test('a real history computes the ordinary tiers only', () {
      // Four 28-day-spaced bleeds: three valid completed cycles.
      DayEntry bleed(LocalDate date) => DayEntry(
            id: date.iso,
            profileId: 'p',
            localDate: date,
            tz: 'UTC',
            flow: FlowLevel.medium,
            updatedAt: DateTime.utc(2026, 5, 1),
          );
      final p = computePredictionFromEntries(
        entries: [
          bleed(LocalDate(2026, 1, 1)),
          bleed(LocalDate(2026, 1, 29)),
          bleed(LocalDate(2026, 2, 26)),
          bleed(LocalDate(2026, 3, 26)),
        ],
        today: today,
      );
      expect(p, isA<ActivePrediction>());
      final active = p as ActivePrediction;
      expect(active.tier, CycleConfidence.learning,
          reason: '3 valid cycles, window not yet full');
      expect(
        active.tier == CycleConfidence.high ||
            active.tier == CycleConfidence.learning ||
            active.tier == CycleConfidence.irregular,
        isTrue,
        reason: 'the computed engine only ever produces the #213 tiers',
      );
    });
  });
}
