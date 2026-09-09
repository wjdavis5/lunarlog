import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// Episodes from start dates, each bleeding [length] days (4 by default).
List<Episode> episodesFromStarts(List<LocalDate> starts, [int length = 4]) => [
      for (final start in starts) Episode(start, start.addDays(length - 1)),
    ];

DayEntry entry(LocalDate date, FlowLevel flow) => DayEntry(
      id: 'row-${date.iso}',
      profileId: 'profile01',
      localDate: date,
      tz: 'UTC',
      flow: flow,
      tags: const [],
      note: null,
      updatedAt: DateTime.utc(2026, 1, 1),
      deletedAt: null,
    );

/// One single-day entry per start date.
List<DayEntry> entriesFromStarts(List<LocalDate> starts, FlowLevel flow) => [
      for (final start in starts) entry(start, flow),
    ];

void main() {
  group('history gates (KTD5)', () {
    test('no episodes at all -> NotEnoughHistory', () {
      final result = computePrediction(episodes: const [], today: d(2026, 6, 1));
      expect(result, isA<NotEnoughHistory>());
      final nth = result as NotEnoughHistory;
      expect(nth.episodeCount, 0);
      expect(nth.completedCycleCount, 0);
      expect(nth.validCycleCount, 0);
      expect(nth.statusLabel, isNotEmpty);
    });

    test('two completed valid cycles -> NotEnoughHistory (never partial numbers)',
        () {
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28)]),
        today: d(2026, 3, 5),
      );
      expect(result, isA<NotEnoughHistory>());
      final nth = result as NotEnoughHistory;
      expect(nth.episodeCount, 3);
      expect(nth.completedCycleCount, 2);
      expect(nth.validCycleCount, 2);
    });

    test('three completed cycles but only two valid -> NotEnoughHistory', () {
      // Lengths 28, 90, 28: the 90-day cycle is invalid.
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 5, 29), d(2026, 6, 26)]),
        today: d(2026, 7, 1),
      );
      expect(result, isA<NotEnoughHistory>());
      expect((result as NotEnoughHistory).validCycleCount, 2);
      expect(result.completedCycleCount, 3);
    });

    test('three completed valid cycles -> estimate appears', () {
      // Lengths 28, 30, 32 -> mean 30 -> estimate = Apr 1 + 30 = May 1.
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 10),
      );
      expect(result, isA<ActivePrediction>());
      final p = result as ActivePrediction;
      expect(p.lastEpisodeStart, d(2026, 4, 1));
      expect(p.averagedCycleLengths, [28, 30, 32]);
      expect(p.meanCycleLengthDays, 30.0);
      expect(p.estimatedNextStart, d(2026, 5, 1));
      expect(p.cycleDay, 10);
      expect(p.daysUntilNextStart, 21);
      expect(p.duringEpisode, isFalse);
      expect(p.isLate, isFalse);
    });

    test('cycle day 1 and "period" phase during the latest episode', () {
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 2),
      );
      final p = result as ActivePrediction;
      expect(p.duringEpisode, isTrue);
      expect(p.cycleDay, 2);
      expect(p.phaseLabel, 'period');
      expect(p.daysUntilNextStart, 29);
      expect(p.untilNextPeriodLabel, '≈29 days until next period');
    });

    test('until-next-period label singularizes one day', () {
      final p = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 30),
      ) as ActivePrediction;
      expect(p.daysUntilNextStart, 1);
      expect(p.untilNextPeriodLabel, '≈1 day until next period');
    });
  });

  group('validity window and averaging', () {
    test('lengths 28, 30, 90, 28: the 90-day outlier is excluded from the '
        'average but kept in history', () {
      final result = computePrediction(
        episodes: episodesFromStarts([
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 2, 28),
          d(2026, 5, 29),
          d(2026, 6, 26),
        ]),
        today: d(2026, 7, 1),
      );
      final p = result as ActivePrediction;
      expect(p.completedCycleCount, 4, reason: 'the outlier stays in history');
      expect(p.validCycleCount, 3);
      expect(p.averagedCycleLengths, [28, 30, 28]);
      expect(p.meanCycleLengthDays, closeTo(86 / 3, 1e-9));
      // mean 28.67 rounds to 29: Jun 26 + 29 = Jul 25.
      expect(p.estimatedNextStart, d(2026, 7, 25));
      expect(p.cycleDay, 6);
      expect(p.daysUntilNextStart, 24);
    });

    test('issue #213: the prediction window is 12 cycles, not 3 — all 4 '
        'valid lengths feed the average now', () {
      // Valid lengths 28, 30, 29, 31, all within kRecencyWindowCycles(12)
      // and kPredictionWindowCycles(12) -> average uses all four -> 29.5,
      // which still rounds to 30 (a coincidence of this fixture, not a
      // general property). Before issue #213 (kMaxAveragedCycles=3), only
      // the most recent three (30, 29, 31) fed the average; that narrower
      // window is exactly what this issue replaces (A2-13).
      final result = computePrediction(
        episodes: episodesFromStarts([
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 2, 28),
          d(2026, 3, 29),
          d(2026, 4, 29),
        ]),
        today: d(2026, 5, 5),
      );
      final p = result as ActivePrediction;
      expect(p.averagedCycleLengths, [28, 30, 29, 31]);
      expect(p.meanCycleLengthDays, 29.5);
      expect(p.estimatedNextStart, d(2026, 5, 29));
    });

    test('boundary cycle lengths: 15 and 60 are valid, 14 and 61 are not', () {
      ActivePrediction predict(List<int> lengths) {
        var start = d(2026, 1, 1);
        final starts = <LocalDate>[start];
        for (final length in lengths.take(3)) {
          start = start.addDays(length);
          starts.add(start);
        }
        return computePrediction(
                episodes: episodesFromStarts(starts), today: start.addDays(5))
            as ActivePrediction;
      }

      expect(predict([15, 15, 15]).validCycleCount, 3);
      expect(predict([60, 60, 60]).validCycleCount, 3);
      expect(
        computePrediction(
          episodes: episodesFromStarts([
            d(2026, 1, 1),
            d(2026, 1, 15), // 14 days: invalid
            d(2026, 2, 14),
            d(2026, 3, 15),
          ]),
          today: d(2026, 3, 20),
        ),
        isA<NotEnoughHistory>(),
        reason: 'a 14-day cycle is below the valid window',
      );
      expect(
        computePrediction(
          episodes: episodesFromStarts([
            d(2026, 1, 1),
            d(2026, 3, 2), // 60 days: valid
            d(2026, 5, 1), // 60 days: valid
            d(2026, 6, 30), // 60 days: valid
          ]),
          today: d(2026, 7, 5),
        ),
        isA<ActivePrediction>(),
      );
    });
  });

  group('paused and late states', () {
    final starts = [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 3, 29)];

    test('open cycle beyond 60 days -> paused awaiting next period, no extrapolation',
        () {
      final result =
          computePrediction(episodes: episodesFromStarts(starts), today: d(2026, 6, 15));
      expect(result, isA<PausedAwaitingNextPeriod>());
      final paused = result as PausedAwaitingNextPeriod;
      expect(paused.lastEpisodeStart, d(2026, 3, 29));
      expect(paused.daysSinceLastEpisodeStart, 78);
      expect(paused.statusLabel, 'awaiting next period');
    });

    test('open cycle of exactly 60 days is not paused yet', () {
      final result =
          computePrediction(episodes: episodesFromStarts(starts), today: d(2026, 5, 28));
      expect(result, isA<ActivePrediction>());
      expect((result as ActivePrediction).cycleDay, 61);
    });

    test('open cycle of 61 days is paused', () {
      final result =
          computePrediction(episodes: episodesFromStarts(starts), today: d(2026, 5, 29));
      expect(result, isA<PausedAwaitingNextPeriod>());
    });

    test('late when today is more than 2 days past the estimate', () {
      // Lengths 28, 28, 28 -> estimate Apr 23.
      final late = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26)]),
        today: d(2026, 4, 26),
      ) as ActivePrediction;
      expect(late.estimatedNextStart, d(2026, 4, 23));
      expect(late.daysUntilNextStart, -3);
      expect(late.isLate, isTrue);

      final boundary = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26)]),
        today: d(2026, 4, 25),
      ) as ActivePrediction;
      expect(boundary.daysUntilNextStart, -2);
      expect(boundary.isLate, isFalse,
          reason: 'estimate + 2 days is not late yet');
    });
  });

  group('predictions from raw entries', () {
    test('spotting-only episodes count as period starts', () {
      final result = computePredictionFromEntries(
        entries: entriesFromStarts(
          [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26)],
          FlowLevel.spotting,
        ),
        today: d(2026, 4, 2),
      );
      expect(result, isA<ActivePrediction>());
      expect((result as ActivePrediction).estimatedNextStart, d(2026, 4, 23));
    });

    test('flow-none entries never form episodes', () {
      final result = computePredictionFromEntries(
        entries: entriesFromStarts(
          [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26)],
          FlowLevel.none,
        ),
        today: d(2026, 4, 2),
      );
      expect(result, isA<NotEnoughHistory>());
      expect((result as NotEnoughHistory).episodeCount, 0);
    });

    test('entries with mixed flows derive merged episodes before predicting',
        () {
      // Jan 1-3 heavy + Jan 5 spotting = one episode starting Jan 1.
      final result = computePredictionFromEntries(
        entries: [
          entry(d(2026, 1, 1), FlowLevel.heavy),
          entry(d(2026, 1, 2), FlowLevel.medium),
          entry(d(2026, 1, 3), FlowLevel.light),
          entry(d(2026, 1, 5), FlowLevel.spotting),
          entry(d(2026, 1, 4), FlowLevel.none),
          entry(d(2026, 2, 1), FlowLevel.medium),
          entry(d(2026, 3, 1), FlowLevel.medium),
          entry(d(2026, 3, 29), FlowLevel.medium),
        ],
        today: d(2026, 4, 5),
      );
      final p = result as ActivePrediction;
      expect(p.averagedCycleLengths, [31, 28, 28]);
      expect(p.lastEpisodeStart, d(2026, 3, 29));
    });
  });

  group('R13: output vocabulary guard', () {
    const forbiddenStems = [
      'ovulat',
      'fertili',
      'luteal',
      'follicular',
      'concei',
    ];

    test('no prediction output exposes fertility-phase vocabulary', () {
      final results = <CyclePrediction>[
        computePrediction(episodes: const [], today: d(2026, 6, 1)),
        computePrediction(
          episodes: episodesFromStarts(
              [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28)]),
          today: d(2026, 3, 5),
        ),
        computePrediction(
          episodes:
              episodesFromStarts([d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 3, 29)]),
          today: d(2026, 6, 15),
        ),
        computePrediction(
          episodes: episodesFromStarts(
              [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
          today: d(2026, 4, 10),
        ),
        computePrediction(
          episodes: episodesFromStarts(
              [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 26)]),
          today: d(2026, 4, 26),
        ),
      ];

      final outputs = <String>[];
      for (final result in results) {
        outputs.add(result.toString());
        switch (result) {
          case ActivePrediction(:final phaseLabel, :final untilNextPeriodLabel):
            outputs.addAll([phaseLabel, untilNextPeriodLabel]);
          case PausedAwaitingNextPeriod(:final statusLabel):
            outputs.add(statusLabel);
          case NotEnoughHistory(:final statusLabel):
            outputs.add(statusLabel);
        }
      }
      // Also assert the phase vocabulary is exactly the settled one.
      outputs.add(
        (results[3] as ActivePrediction).duringEpisode ? 'period' : '',
      );

      expect(outputs, isNotEmpty);
      for (final output in outputs) {
        for (final stem in forbiddenStems) {
          expect(output.toLowerCase().contains(stem), isFalse,
              reason: 'output "$output" leaks "$stem"');
        }
      }
    });

    test('phase output is date-based only: period / cycle day / days-until', () {
      final p = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 10),
      ) as ActivePrediction;
      expect(p.duringEpisode, isFalse);
      expect(p.phaseLabel, 'cycle day 10');
      expect(p.untilNextPeriodLabel, '≈21 days until next period');
      expect(p.cycleDay, 10);
    });
  });

  group('omit-from-average (issue #132, R4)', () {
    test('omitting a completed cycle start drops its length from the average '
        'and moves the estimate', () {
      // Lengths 28, 28, 48, 28. Issue #213 widened the prediction window
      // to 12 cycles (was 3), so without omission all four lengths feed
      // the average: (28+28+48+28)/4 = 33.0 exactly: May 13 + 33 = Jun 15.
      // Omitting the 48-day cycle (start Feb 26) leaves 28, 28, 28 -> 28:
      // May 13 + 28 = Jun 10.
      final starts = [
        d(2026, 1, 1),
        d(2026, 1, 29), // 28
        d(2026, 2, 26), // 28
        d(2026, 4, 15), // 48
        d(2026, 5, 13), // 28
      ];
      final before = computePrediction(
        episodes: episodesFromStarts(starts),
        today: d(2026, 5, 20),
      ) as ActivePrediction;
      expect(before.averagedCycleLengths, [28, 28, 48, 28]);
      expect(before.meanCycleLengthDays, 33.0);

      final after = computePrediction(
        episodes: episodesFromStarts(starts),
        today: d(2026, 5, 20),
        omittedCycleStarts: {d(2026, 2, 26)},
      ) as ActivePrediction;
      expect(after.averagedCycleLengths, [28, 28, 28],
          reason: 'the omitted length simply drops out (the 12-cycle window '
              'has room for all the rest already)');
      expect(after.meanCycleLengthDays, 28.0);
      expect(after.estimatedNextStart, before.estimatedNextStart.addDays(-5));
    });

    test('omitting below three usable cycles degrades to NotEnoughHistory, '
        'never partial numbers', () {
      // Lengths 28, 30, 32; omitting any one leaves two usable.
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 10),
        omittedCycleStarts: {d(2026, 1, 1)},
      );
      expect(result, isA<NotEnoughHistory>());
      final nth = result as NotEnoughHistory;
      expect(nth.episodeCount, 4);
      expect(nth.completedCycleCount, 3);
      expect(nth.validCycleCount, 3,
          reason: 'the window-valid count ignores omissions');
    });

    test('omitting a length already outside the window changes nothing', () {
      // Lengths 28, 90, 30, 32: the 90-day cycle is already invalid.
      final starts = [
        d(2026, 1, 1),
        d(2026, 1, 29),
        d(2026, 4, 29), // 90 days: outside the window
        d(2026, 5, 29),
        d(2026, 6, 30),
      ];
      final plain = computePrediction(
        episodes: episodesFromStarts(starts),
        today: d(2026, 7, 5),
      );
      final omitted = computePrediction(
        episodes: episodesFromStarts(starts),
        today: d(2026, 7, 5),
        omittedCycleStarts: {d(2026, 1, 29)},
      );
      expect(omitted.toString(), plain.toString());
    });

    test('a length is attributed to the cycle that starts it, not ends it',
        () {
      // Lengths 32, 28, 48, 28. Omitting the *second* start drops its 28;
      // the older 32 slides in and the 48 stays.
      final result = computePrediction(
        episodes: episodesFromStarts([
          d(2025, 11, 30),
          d(2026, 1, 1),
          d(2026, 1, 29),
          d(2026, 3, 18),
          d(2026, 4, 15),
        ]),
        today: d(2026, 4, 20),
        omittedCycleStarts: {d(2026, 1, 1)},
      ) as ActivePrediction;
      expect(result.averagedCycleLengths, [32, 48, 28]);
    });

    test('computePredictionFromEntries forwards the omission set', () {
      final result = computePredictionFromEntries(
        entries: entriesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 26), d(2026, 3, 28)],
            FlowLevel.medium),
        today: d(2026, 4, 1),
        omittedCycleStarts: {d(2026, 1, 29)},
      );
      expect(result, isA<NotEnoughHistory>(),
          reason: 'lengths 28, 28, 30 minus one omitted leaves two usable');
    });
  });

  group('skip this cycle (issue #132, R6)', () {
    // 30-day cycles; today is day 45 of the open cycle: estimate was
    // Apr 27 + 30 = May 27, more than the 2-day grace past -> late.
    final starts = [
      d(2026, 1, 27),
      d(2026, 2, 26),
      d(2026, 3, 28),
      d(2026, 4, 27),
    ];
    final today = d(2026, 6, 11);

    test('skipping the open cycle advances the estimate one averaged cycle '
        'and clears the late flag', () {
      final late = computePrediction(
        episodes: episodesFromStarts(starts),
        today: today,
      ) as ActivePrediction;
      expect(late.isLate, isTrue);

      final skipped = computePrediction(
        episodes: episodesFromStarts(starts),
        today: today,
        omittedCycleStarts: {starts.last},
      ) as ActivePrediction;
      expect(
        skipped.estimatedNextStart,
        late.estimatedNextStart.addDays(30),
        reason: '30-day mean x kSkipAdvanceCycles(1) beyond the base estimate',
      );
      expect(skipped.isLate, isFalse,
          reason: 'the skip replans the late window (R6)');
      expect(skipped.meanCycleLengthDays, late.meanCycleLengthDays,
          reason: 'the skip does not change the average itself');
    });

    test('when the next period is finally logged, the skipped cycle length '
        'stays out of the average', () {
      // The next period arrives 2026-05-31: the skipped cycle ran 34 days
      // (in-window, so only the omission keeps it out), and the new open
      // cycle is normal.
      final withNext = [...starts, d(2026, 5, 31)];
      final result = computePrediction(
        episodes: episodesFromStarts(withNext),
        today: d(2026, 6, 5),
        omittedCycleStarts: {starts.last},
      ) as ActivePrediction;
      expect(result.averagedCycleLengths, [30, 30, 30],
          reason: 'the 34-day skipped cycle never poisons the mean');
      expect(result.estimatedNextStart, d(2026, 6, 30));
    });

    test('a skip does not lift the sixty-day pause', () {
      // Open cycle at day 70: paused regardless of the skip — the way
      // through remains "log it" (issue #132 AC).
      final result = computePrediction(
        episodes: episodesFromStarts([
          d(2025, 12, 2),
          d(2026, 1, 1),
          d(2026, 1, 31),
          d(2026, 3, 2),
        ]),
        today: d(2026, 5, 11),
        omittedCycleStarts: {d(2026, 3, 2)},
      );
      expect(result, isA<PausedAwaitingNextPeriod>());
    });
  });

  group('recency bound before validity filtering (issue #213, A2-13 fix)', () {
    test('stale valid cycles behind a long recent gap of invalid ones no '
        'longer feed a full-confidence estimate', () {
      // 3 old valid 28-day cycles, then 12 more (invalid, 90-day) cycles —
      // 15 completed cycles total. kRecencyWindowCycles (12) is applied to
      // the raw chronological list *before* validity filtering, so the 12
      // most recent completed cycles (all invalid here) are the only ones
      // ever considered; the 3 old valid ones sit entirely outside that
      // window and must never feed the estimate, however few valid cycles
      // exist since. Before issue #213 (validity-filter-then-window), the
      // unwindowed valid list would have surfaced exactly those 3 old
      // cycles as a full-confidence, badly stale estimate.
      var start = d(2024, 1, 1);
      final starts = <LocalDate>[start];
      for (var i = 0; i < 3; i++) {
        start = start.addDays(28);
        starts.add(start);
      }
      for (var i = 0; i < 12; i++) {
        start = start.addDays(90);
        starts.add(start);
      }
      final today = start.addDays(5);

      final result = computePrediction(
        episodes: episodesFromStarts(starts),
        today: today,
      );
      expect(result, isA<NotEnoughHistory>(),
          reason: 'the 3 valid cycles are outside the 12-cycle recency '
              'window; the fix must not reach back for them');
      final nth = result as NotEnoughHistory;
      expect(nth.completedCycleCount, 15);
      expect(nth.validCycleCount, 3,
          reason: 'full-history validCycleCount is still reported for '
              'context; only the *usable-for-the-estimate* count is '
              'recency-windowed');
    });

    test('the same stale cycles DO feed the estimate once they are still '
        'inside the 12-cycle window', () {
      // Same shape as above but with only 8 invalid cycles after the 3
      // valid ones (11 completed total, all within the 12-cycle window),
      // so the 3 old valid cycles are still visible to the estimate.
      var start = d(2024, 1, 1);
      final starts = <LocalDate>[start];
      for (var i = 0; i < 3; i++) {
        start = start.addDays(28);
        starts.add(start);
      }
      for (var i = 0; i < 8; i++) {
        start = start.addDays(90);
        starts.add(start);
      }
      final today = start.addDays(5);

      final result = computePrediction(
        episodes: episodesFromStarts(starts),
        today: today,
      );
      expect(result, isA<ActivePrediction>());
      final p = result as ActivePrediction;
      expect(p.averagedCycleLengths, [28, 28, 28]);
    });
  });

  group('confidence tier thresholds (issue #213, provisional)', () {
    test('fewer than kMinCompletedValidCycles in the average window always '
        'reads learning, regardless of spread or ratio', () {
      expect(
        confidenceTierFor(
          validCycleCountInWindow: kMinCompletedValidCycles - 1,
          spreadDays: 0,
          validRatio: 1.0,
        ),
        CycleConfidence.learning,
      );
    });

    test('spread exactly at the threshold still reads high; just over it '
        'reads irregular', () {
      expect(
        confidenceTierFor(
          validCycleCountInWindow: 6,
          spreadDays: kIrregularSpreadThresholdDays,
          validRatio: 1.0,
        ),
        CycleConfidence.high,
        reason: 'the boundary itself is not "over" the threshold',
      );
      expect(
        confidenceTierFor(
          validCycleCountInWindow: 6,
          spreadDays: kIrregularSpreadThresholdDays + 0.01,
          validRatio: 1.0,
        ),
        CycleConfidence.irregular,
      );
    });

    test('valid ratio exactly at the threshold still reads high; just '
        'under it reads irregular', () {
      expect(
        confidenceTierFor(
          validCycleCountInWindow: 6,
          spreadDays: 0,
          validRatio: kIrregularValidRatioThreshold,
        ),
        CycleConfidence.high,
        reason: 'the boundary itself is not "under" the threshold',
      );
      expect(
        confidenceTierFor(
          validCycleCountInWindow: 6,
          spreadDays: 0,
          validRatio: kIrregularValidRatioThreshold - 0.01,
        ),
        CycleConfidence.irregular,
      );
    });
  });

  group('period-length aggregation (issue #213, item 3)', () {
    test('meanPeriodLengthDays averages Episode.lengthDays over the '
        '6-cycle average window', () {
      final starts = [
        d(2026, 1, 1),
        d(2026, 1, 29),
        d(2026, 2, 26),
        d(2026, 3, 26),
      ];
      const bleedLengths = [3, 4, 5, 4];
      final episodes = [
        for (var i = 0; i < starts.length; i++)
          Episode(starts[i], starts[i].addDays(bleedLengths[i] - 1)),
      ];
      final result = computePrediction(
        episodes: episodes,
        today: starts.last.addDays(5),
      );
      final p = result as ActivePrediction;
      expect(p.meanPeriodLengthDays, closeTo(4.0, 1e-9));
    });
  });

  group('forecast sequence (issue #213, item 4)', () {
    test('a steady, high-tier history forecasts kPredictionWindowCycles '
        'cycles, all at high tier with zero spread', () {
      final starts = [for (var i = 0; i < 6; i++) d(2026, 1, 1).addDays(30 * i)];
      final result = computePrediction(
        episodes: episodesFromStarts(starts),
        today: starts.last.addDays(5),
      );
      final p = result as ActivePrediction;
      expect(p.tier, CycleConfidence.high);
      expect(p.spreadDays, 0);
      expect(p.forecast, hasLength(kPredictionWindowCycles));
      expect(p.forecast.first.start, p.estimatedNextStart);
      for (var i = 0; i < p.forecast.length; i++) {
        final cycle = p.forecast[i];
        expect(cycle.cycleIndex, i + 1);
        expect(cycle.start, p.estimatedNextStart.addDays(30 * i));
        expect(cycle.spreadDays, 0);
        expect(cycle.tier, CycleConfidence.high,
            reason: 'zero spread never crosses the irregular threshold, '
                'however far out the forecast goes');
      }
    });

    test('an irregular-tier history forecasts every cycle at irregular, '
        'and the spread widens further out', () {
      // Lengths 90, 95, 100, 65 (all invalid) then 24, 28, 32 (valid,
      // spread > 0): valid ratio 3/7 ≈ 0.43 < 0.5 reads irregular even
      // though the 24/28/32 spread alone (≈3.27) would not.
      final starts = [
        d(2025, 1, 1),
        d(2025, 4, 1), // 90: invalid
        d(2025, 7, 5), // 95: invalid
        d(2025, 10, 13), // 100: invalid
        d(2025, 12, 17), // 65: invalid
        d(2026, 1, 10), // 24: valid
        d(2026, 2, 7), // 28: valid
        d(2026, 3, 11), // 32: valid
      ];
      final result = computePrediction(
        episodes: episodesFromStarts(starts),
        today: starts.last.addDays(5),
      );
      final p = result as ActivePrediction;
      expect(p.tier, CycleConfidence.irregular);
      expect(p.forecast, hasLength(kPredictionWindowCycles));
      for (final cycle in p.forecast) {
        expect(cycle.tier, CycleConfidence.irregular,
            reason: 'irregular never upgrades with distance');
      }
      expect(
        p.forecast[1].spreadDays,
        greaterThan(p.forecast[0].spreadDays),
        reason: 'spread still widens geometrically even once already '
            'irregular',
      );
    });
  });
}
