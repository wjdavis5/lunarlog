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

    test('only the most recent 3 valid cycles feed the average', () {
      // Valid lengths 28, 30, 29, 31 -> average uses 30, 29, 31 -> 30.
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
      expect(p.averagedCycleLengths, [30, 29, 31]);
      expect(p.meanCycleLengthDays, 30.0);
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
}
