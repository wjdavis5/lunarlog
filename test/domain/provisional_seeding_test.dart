/// Issue #218: the `provisional` confidence tier and the pure seeding
/// function `seedProvisionalPrediction` — seeding math, partial answers,
/// the validity gate, stale-facts roll-forward, and the forecast shape.
/// The displacement rule itself (real cycles displacing the seed) is
/// proven at the service level in `prediction_service_test.dart`, and the
/// no-facts path staying bit-identical is the existing
/// `prediction_test.dart` suite, unchanged.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
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

    test('builds the horizon-sized forecast off the supplied mean, '
        'anchored at the estimate, with the tier floored at provisional '
        '(issue #693: horizon-sized, not the old fixed 12-cycle count)', () {
      final active = seedProvisionalPrediction(
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
        today: today,
      ) as ActivePrediction;
      // today 2026-05-20 → the horizon ends 2027-05-31; the estimate
      // (2026-05-18, still within the late grace) chains in 28-day
      // steps: 28*(i-1) ≤ 378 days of headroom → 14 cycles, the last
      // starting 2026-05-18 + 28*13 = 2027-05-17 (a 15th would start
      // 2027-06-14, past the horizon).
      expect(active.forecast, hasLength(14));
      expect(active.forecast.first.start, active.estimatedNextStart);
      expect(active.forecast[1].start, LocalDate(2026, 6, 15));
      expect(active.forecast.last.start, LocalDate(2026, 6, 15).addDays(28 * 12));
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

  group('a logged period re-anchors the seed (issue #1392)', () {
    // The issue's first repro, on this file's `today`: a seed 30 days old
    // with a 28-day typical cycle reads "2 days past the estimate, cycle
    // day 31" until a period is logged.
    final lateSeed = CycleFacts(
      lastPeriodStart: LocalDate(2026, 4, 20),
      typicalCycleLengthDays: 28,
      typicalPeriodLengthDays: 5,
    );
    // The second repro: a seed 13 days old (cycle day 14).
    final earlySeed = CycleFacts(
      lastPeriodStart: LocalDate(2026, 5, 7),
      typicalCycleLengthDays: 28,
      typicalPeriodLengthDays: 5,
    );

    ActivePrediction seeded(CycleFacts facts, List<Episode> episodes) =>
        seedProvisionalPrediction(
          facts: facts,
          today: today,
          episodes: episodes,
        ) as ActivePrediction;

    test('late period: a period logged today starts the cycle today', () {
      final before = seeded(lateSeed, const []);
      expect(before.cycleDay, 31);
      expect(before.daysUntilNextPeriod, -2);

      final after = seeded(lateSeed, [Episode(today, today)]);
      expect(after.lastEpisodeStart, today);
      expect(after.cycleDay, 1);
      expect(after.duringEpisode, isTrue);
      expect(after.daysLate, isNull);
      expect(after.daysUntilNextPeriod, 28);
      expect(after.originalEstimatedNextStart, LocalDate(2026, 6, 17));
      expect(after.estimatedNextStart, LocalDate(2026, 6, 17));
      expect(after.forecast.first.start, LocalDate(2026, 6, 17));
      expect(after.forecast[1].start, LocalDate(2026, 7, 15));
    });

    test('early period: a period logged on cycle day 14 starts a new '
        'cycle instead of leaving the seed-based estimate in place', () {
      final before = seeded(earlySeed, const []);
      expect(before.cycleDay, 14);
      expect(before.estimatedNextStart, LocalDate(2026, 6, 4));

      final after = seeded(earlySeed, [Episode(today, today)]);
      expect(after.lastEpisodeStart, today);
      expect(after.cycleDay, 1);
      expect(after.estimatedNextStart, LocalDate(2026, 6, 17));
    });

    test('re-anchoring keeps the supplied answers and the provisional '
        'tier: one logged period completes no cycle', () {
      final after = seeded(lateSeed, [Episode(today, today)]);
      expect(after.tier, CycleConfidence.provisional);
      expect(after.meanCycleLengthDays, 28.0);
      expect(after.meanPeriodLengthDays, 5.0);
      expect(after.spreadDays, kProvisionalSpreadDays);
      expect(after.averagedCycleLengths, isEmpty);
      expect(after.completedCycleCount, 0);
      expect(after.validCycleCount, 0);
      expect(
        after.forecast.every((c) => c.tier == CycleConfidence.provisional),
        isTrue,
      );
    });

    test('the latest of several logged periods is the anchor, whatever '
        'order they arrive in', () {
      final after = seeded(lateSeed, [
        Episode(LocalDate(2026, 5, 14), LocalDate(2026, 5, 17)),
        Episode(LocalDate(2026, 4, 22), LocalDate(2026, 4, 25)),
      ]);
      expect(after.lastEpisodeStart, LocalDate(2026, 5, 14));
      expect(after.cycleDay, 7);
      expect(after.estimatedNextStart, LocalDate(2026, 6, 11));
    });

    test('a logged period that ended before the supplied start is an '
        'earlier period: the anchor never moves backwards', () {
      final after = seeded(earlySeed, [
        Episode(LocalDate(2026, 4, 9), LocalDate(2026, 4, 12)),
      ]);
      expect(after.lastEpisodeStart, LocalDate(2026, 5, 7));
      expect(after.cycleDay, 14);
      expect(after.estimatedNextStart, LocalDate(2026, 6, 4));
      expect(after.duringEpisode, isFalse);
    });

    test('a logged period that began just before the supplied start and '
        'runs past it is the same period: its logged start wins', () {
      // Onboarding said 5/7; the days actually logged are 5/5-5/8.
      final after = seeded(earlySeed, [
        Episode(LocalDate(2026, 5, 5), LocalDate(2026, 5, 8)),
      ]);
      expect(after.lastEpisodeStart, LocalDate(2026, 5, 5));
      expect(after.cycleDay, 16);
      expect(after.estimatedNextStart, LocalDate(2026, 6, 2));
    });

    test('a future-dated logged period never anchors today\'s cycle '
        '(issue LLA-071)', () {
      final after = seeded(earlySeed, [
        Episode(LocalDate(2026, 5, 25), LocalDate(2026, 5, 27)),
      ]);
      expect(after.lastEpisodeStart, LocalDate(2026, 5, 7));
      expect(after.cycleDay, 14);
    });

    test('once the anchor is a logged period, the log decides which days '
        'are period days: the estimated bleed window no longer applies',
        () {
      // A one-day logged period yesterday: today is cycle day 2 and not
      // inside a logged episode, exactly as the computed path reads it.
      final yesterday = today.addDays(-1);
      final after = seeded(lateSeed, [Episode(yesterday, yesterday)]);
      expect(after.lastEpisodeStart, yesterday);
      expect(after.cycleDay, 2);
      expect(after.duringEpisode, isFalse);
    });

    test('the estimated bleed window still applies while the anchor is '
        'the onboarding answer', () {
      final facts = CycleFacts(
        lastPeriodStart: today.addDays(-2),
        typicalCycleLengthDays: 28,
        typicalPeriodLengthDays: 5,
      );
      // An older logged period changes nothing about the current one.
      final after = seeded(facts, [
        Episode(LocalDate(2026, 4, 20), LocalDate(2026, 4, 23)),
      ]);
      expect(after.lastEpisodeStart, today.addDays(-2));
      expect(after.cycleDay, 3);
      expect(after.duringEpisode, isTrue);
    });

    test('a logged period replaces a stale seed: the long-cycle flag is '
        'measured from the logged start, so provisional is kept', () {
      final staleSeed = CycleFacts(
        lastPeriodStart: LocalDate(2026, 1, 1),
        typicalCycleLengthDays: 28,
        typicalPeriodLengthDays: 5,
      );
      expect(seeded(staleSeed, const []).unusuallyLongCycle, isTrue);

      final after = seeded(staleSeed, [
        Episode(LocalDate(2026, 5, 1), LocalDate(2026, 5, 4)),
      ]);
      expect(after.unusuallyLongCycle, isFalse);
      expect(after.staleHistory, isFalse);
      expect(after.tier, CycleConfidence.provisional);
      expect(after.daysLate, isNull);
      expect(after.estimatedNextStart, LocalDate(2026, 5, 29));
    });

    test('seedProvisionalPredictionFromEntries derives the episodes from '
        'raw entries (the call the service and the web facade make)', () {
      DayEntry entry(LocalDate date, FlowLevel flow) => DayEntry(
            id: date.iso,
            profileId: 'p',
            localDate: date,
            tz: 'UTC',
            flow: flow,
            updatedAt: DateTime.utc(2026, 5, 20),
          );
      final after = seedProvisionalPredictionFromEntries(
        facts: lateSeed,
        entries: [
          entry(today.addDays(-1), FlowLevel.heavy),
          entry(today, FlowLevel.medium),
        ],
        today: today,
      ) as ActivePrediction;
      expect(after.lastEpisodeStart, today.addDays(-1));
      expect(after.cycleDay, 2);
      expect(after.duringEpisode, isTrue);

      // Only a bleed day starts a cycle: an explicit "not bleeding today"
      // entry (issue #247) leaves the onboarding anchor where it was.
      final notBleeding = seedProvisionalPredictionFromEntries(
        facts: lateSeed,
        entries: [entry(today, FlowLevel.notBleeding)],
        today: today,
      ) as ActivePrediction;
      expect(notBleeding.lastEpisodeStart, LocalDate(2026, 4, 20));
      expect(notBleeding.cycleDay, 31);
    });

    test('facts that cannot seed still return NotEnoughHistory, logged '
        'periods or not', () {
      final p = seedProvisionalPrediction(
        facts: CycleFacts(lastPeriodStart: LocalDate(2026, 4, 20)),
        today: today,
        episodes: [Episode(today, today)],
      );
      expect(p, isA<NotEnoughHistory>());
    });
  });

  group('cycleStartIsSupplied says when the cycle counts from the setup '
      'answer (issue #1469)', () {
    // 13 days before this file's `today`.
    final supplied = LocalDate(2026, 5, 7);
    final facts = CycleFacts(
      lastPeriodStart: supplied,
      typicalCycleLengthDays: 28,
      typicalPeriodLengthDays: 5,
    );

    ActivePrediction seeded(List<Episode> episodes, {LocalDate? on}) =>
        seedProvisionalPrediction(
          facts: facts,
          today: on ?? today,
          episodes: episodes,
        ) as ActivePrediction;

    test('true for the pure onboarding seed, whose start is the supplied '
        'date', () {
      final p = seeded(const []);
      expect(p.cycleStartIsSupplied, isTrue);
      expect(p.lastEpisodeStart, supplied);
    });

    test('still true when only an earlier period is logged: the supplied '
        'date stays the most recent start known', () {
      final p = seeded([
        Episode(LocalDate(2026, 4, 9), LocalDate(2026, 4, 12)),
      ]);
      expect(p.cycleStartIsSupplied, isTrue);
      expect(p.lastEpisodeStart, supplied);
    });

    test('false once a period logged after the supplied date starts the '
        'cycle, although the tier is still provisional', () {
      final p = seeded([Episode(today, today)]);
      expect(p.cycleStartIsSupplied, isFalse);
      expect(p.lastEpisodeStart, today);
      expect(p.tier, CycleConfidence.provisional);
    });

    test('false when the same period is logged day by day, on the supplied '
        'date or straddling it', () {
      expect(
        seeded([Episode(supplied, supplied.addDays(3))]).cycleStartIsSupplied,
        isFalse,
      );
      final straddling = seeded([
        Episode(LocalDate(2026, 5, 5), LocalDate(2026, 5, 8)),
      ]);
      expect(straddling.cycleStartIsSupplied, isFalse);
      expect(straddling.lastEpisodeStart, LocalDate(2026, 5, 5));
    });

    test('a future-dated logged period does not take over (issue LLA-071)',
        () {
      final p = seeded([
        Episode(LocalDate(2026, 5, 25), LocalDate(2026, 5, 27)),
      ]);
      expect(p.cycleStartIsSupplied, isTrue);
    });

    test('still true once the seed is old enough to read irregular: the '
        'tier changes, where the cycle counts from does not', () {
      final p = seeded(const [], on: supplied.addDays(75));
      expect(p.unusuallyLongCycle, isTrue);
      expect(p.tier, CycleConfidence.irregular);
      expect(p.cycleStartIsSupplied, isTrue);
    });

    test('never set on an estimate computed from logged cycles', () {
      final computed = computePrediction(
        episodes: [
          for (final start in [
            LocalDate(2026, 2, 11),
            LocalDate(2026, 3, 11),
            LocalDate(2026, 4, 8),
            LocalDate(2026, 5, 6),
          ])
            Episode(start, start.addDays(3)),
        ],
        today: today,
      );
      expect(computed, isA<ActivePrediction>());
      expect((computed as ActivePrediction).cycleStartIsSupplied, isFalse);
    });
  });

  group('a skipped provisional cycle advances the estimate (issue #1412)',
      () {
    // 35 days before this file's `today` with a 28-day typical cycle: the
    // estimate (2026-05-13) is 7 days past, so the late resolver shows.
    final lateSeed = CycleFacts(
      lastPeriodStart: LocalDate(2026, 4, 15),
      typicalCycleLengthDays: 28,
      typicalPeriodLengthDays: 5,
    );

    ActivePrediction seeded(
      CycleFacts facts, {
      List<Episode> episodes = const [],
      Set<LocalDate> omitted = const {},
    }) =>
        seedProvisionalPrediction(
          facts: facts,
          today: today,
          episodes: episodes,
          omittedCycleStarts: omitted,
        ) as ActivePrediction;

    test('skipping the onboarding-anchored cycle moves the estimate one '
        'supplied cycle length later and it is no longer overdue', () {
      final before = seeded(lateSeed);
      expect(before.originalEstimatedNextStart, LocalDate(2026, 5, 13));
      expect(before.daysLate, 7);
      expect(before.isLate, isTrue);
      expect(before.estimatedNextStart, LocalDate(2026, 6, 10),
          reason: 'the late roll, one 28-day step past the original');

      // The key the late resolver records: the prediction's own
      // lastEpisodeStart.
      final after = seeded(lateSeed, omitted: {before.lastEpisodeStart});
      expect(after.originalEstimatedNextStart, LocalDate(2026, 6, 10),
          reason: '2026-04-15 + 28 + one skipped 28-day cycle');
      expect(after.estimatedNextStart, LocalDate(2026, 6, 10));
      expect(after.forecast.first.start, LocalDate(2026, 6, 10));
      expect(after.forecast[1].start, LocalDate(2026, 7, 8));
      expect(after.daysLate, isNull);
      expect(after.isLate, isFalse);
      expect(after.daysUntilNextPeriod, 21);
    });

    test('a skip changes only the estimate: the open cycle, its day count, '
        'the supplied answers and the provisional tier stay as they were',
        () {
      final before = seeded(lateSeed);
      final after = seeded(lateSeed, omitted: {LocalDate(2026, 4, 15)});
      expect(after.lastEpisodeStart, before.lastEpisodeStart);
      expect(after.cycleDay, 36);
      expect(after.duringEpisode, isFalse);
      expect(after.tier, CycleConfidence.provisional);
      expect(after.meanCycleLengthDays, 28.0);
      expect(after.meanPeriodLengthDays, 5.0);
      expect(after.spreadDays, kProvisionalSpreadDays);
      expect(after.averagedCycleLengths, isEmpty);
      expect(after.completedCycleCount, 0);
      expect(after.unusuallyLongCycle, isFalse);
      expect(after.staleHistory, isFalse);
    });

    test('the advance is exactly kSkipAdvanceCycles supplied cycles, like '
        'the computed path\'s mean-length advance', () {
      final facts = CycleFacts(
        lastPeriodStart: LocalDate(2026, 4, 15),
        typicalCycleLengthDays: 31,
      );
      final skipped = seeded(facts, omitted: {LocalDate(2026, 4, 15)});
      expect(
        skipped.originalEstimatedNextStart,
        LocalDate(2026, 4, 15).addDays(31 + 31 * kSkipAdvanceCycles),
      );
    });

    test('a skip keyed on a logged anchor advances from the logged start '
        '(issue #1392\'s anchor rules are untouched)', () {
      // Onboarding said 3/10; one period is logged 4/15-4/18, so that is
      // where the open cycle starts.
      final facts = CycleFacts(
        lastPeriodStart: LocalDate(2026, 3, 10),
        typicalCycleLengthDays: 28,
      );
      final episodes = [
        Episode(LocalDate(2026, 4, 15), LocalDate(2026, 4, 18)),
      ];
      final before = seeded(facts, episodes: episodes);
      expect(before.lastEpisodeStart, LocalDate(2026, 4, 15));
      expect(before.daysLate, 7);

      final after = seeded(
        facts,
        episodes: episodes,
        omitted: {LocalDate(2026, 4, 15)},
      );
      expect(after.lastEpisodeStart, LocalDate(2026, 4, 15));
      expect(after.originalEstimatedNextStart, LocalDate(2026, 6, 10));
      expect(after.daysLate, isNull);
      expect(after.duringEpisode, isFalse);

      // The onboarding date is no longer the anchor, so an omission keyed
      // on it is not a skip of the open cycle.
      final staleKey = seeded(
        facts,
        episodes: episodes,
        omitted: {LocalDate(2026, 3, 10)},
      );
      expect(staleKey.originalEstimatedNextStart, LocalDate(2026, 5, 13));
      expect(staleKey.daysLate, 7);
    });

    test('logging the next period supersedes the skip: the new start is '
        'the anchor and the old omission no longer applies', () {
      final after = seeded(
        lateSeed,
        episodes: [Episode(today, today)],
        omitted: {LocalDate(2026, 4, 15)},
      );
      expect(after.lastEpisodeStart, today);
      expect(after.cycleDay, 1);
      expect(after.originalEstimatedNextStart, LocalDate(2026, 6, 17));
      expect(after.estimatedNextStart, LocalDate(2026, 6, 17));
    });

    test('a skipped cycle that outlasts the advance is late again and '
        'still rolls forward (#221 posture)', () {
      // today is 2026-05-20: 79 days after a 3/2 start. Skipped estimate
      // 3/2 + 56 = 4/27, 23 days past.
      final facts = CycleFacts(
        lastPeriodStart: LocalDate(2026, 3, 2),
        typicalCycleLengthDays: 28,
      );
      final after = seeded(facts, omitted: {LocalDate(2026, 3, 2)});
      expect(after.originalEstimatedNextStart, LocalDate(2026, 4, 27));
      expect(after.daysLate, 23);
      expect(after.estimatedNextStart, LocalDate(2026, 5, 25));
    });

    test('"Exclude this cycle" on a seed past kMaxOpenCycleDays records the '
        'same key: the days-late count drops one supplied cycle while the '
        'long-cycle flag stays, exactly as on the computed path', () {
      // 64 open days (> kMaxOpenCycleDays) on a 30-day typical cycle.
      final facts = CycleFacts(
        lastPeriodStart: LocalDate(2026, 3, 17),
        typicalCycleLengthDays: 30,
      );
      final before = seeded(facts);
      expect(before.unusuallyLongCycle, isTrue);
      expect(before.daysLate, 34);

      final after = seeded(facts, omitted: {before.lastEpisodeStart});
      expect(after.originalEstimatedNextStart, LocalDate(2026, 5, 16));
      expect(after.daysLate, 4);
      expect(after.unusuallyLongCycle, isTrue,
          reason: 'a skip never closes the open cycle');
      expect(after.tier, CycleConfidence.irregular);
      expect(after.staleHistory, isFalse);
    });

    test('seedProvisionalPredictionFromEntries forwards the omission list '
        '(the call the service and the web facade make)', () {
      final after = seedProvisionalPredictionFromEntries(
        facts: lateSeed,
        entries: const [],
        today: today,
        omittedCycleStarts: {LocalDate(2026, 4, 15)},
      ) as ActivePrediction;
      expect(after.originalEstimatedNextStart, LocalDate(2026, 6, 10));
      expect(after.daysLate, isNull);
    });

    test('no omission, or one keyed on another date, leaves the seed '
        'exactly as before', () {
      expect(seeded(lateSeed).originalEstimatedNextStart,
          LocalDate(2026, 5, 13));
      expect(
        seeded(lateSeed, omitted: {LocalDate(2026, 4, 14)})
            .originalEstimatedNextStart,
        LocalDate(2026, 5, 13),
      );
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
