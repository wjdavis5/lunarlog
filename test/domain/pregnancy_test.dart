/// Issue #192 (Pregnancy mode): the pure pregnancy computations —
/// Naegele's-rule due-date derivation, the week-of-pregnancy counter, and
/// the exit-exclusion interval — plus the regression the issue itself
/// demands: a pregnancy with mid-pregnancy breakthrough episodes
/// permanently poisons the post-pregnancy cycle mean today, and the
/// offered exclusion (a `cycle_overrides` row per cycle start inside the
/// interval) restores it exactly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/pregnancy.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

DayEntry _bleed(LocalDate date) => DayEntry(
      id: 'entry-${date.iso}',
      profileId: 'p',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('estimatedDueDateFromLastPeriod (Naegele\'s rule)', () {
    test('adds exactly kGestationDays (280)', () {
      expect(
        estimatedDueDateFromLastPeriod(d(2026, 9, 14)),
        d(2027, 6, 21),
      );
      expect(kGestationDays, 280);
    });
  });

  group('pregnancyWeekOf', () {
    final lmp = d(2026, 9, 14);
    final due = estimatedDueDateFromLastPeriod(lmp);

    test('day of the last period start reads week 0', () {
      expect(pregnancyWeekOf(dueDate: due, today: lmp), 0);
    });

    test('gestational day 7 reads week 1 (floor of days/7)', () {
      expect(pregnancyWeekOf(dueDate: due, today: lmp.addDays(7)), 1);
      expect(pregnancyWeekOf(dueDate: due, today: lmp.addDays(13)), 1);
      expect(pregnancyWeekOf(dueDate: due, today: lmp.addDays(14)), 2);
    });

    test('the due date itself reads week 40', () {
      expect(pregnancyWeekOf(dueDate: due, today: due), 40);
    });

    test('an overdue pregnancy keeps counting past 40', () {
      expect(pregnancyWeekOf(dueDate: due, today: due.addDays(7)), 41);
    });

    test('a today before the implied last period start clamps at 0, '
        'never a negative week', () {
      expect(pregnancyWeekOf(dueDate: due, today: lmp.addDays(-30)), 0);
    });
  });

  group('pregnancyExclusionStarts', () {
    final episodes = deriveEpisodes([
      d(2026, 1, 1),
      d(2026, 3, 15),
      d(2026, 5, 2),
      d(2026, 10, 30),
    ]);

    test('excludes every episode start in [modeStartedOn, exitedOn)', () {
      expect(
        pregnancyExclusionStarts(
          episodes: episodes,
          modeStartedOn: d(2026, 1, 24),
          exitedOn: d(2026, 10, 30),
        ),
        {d(2026, 3, 15), d(2026, 5, 2)},
      );
    });

    test('the mode-start cycle itself (the pregnancy-long "cycle") is '
        'excluded when it starts inside the interval', () {
      expect(
        pregnancyExclusionStarts(
          episodes: episodes,
          modeStartedOn: d(2026, 1, 1),
          exitedOn: d(2026, 10, 30),
        ),
        {d(2026, 1, 1), d(2026, 3, 15), d(2026, 5, 2)},
      );
    });

    test('a period starting exactly on the exit date is NOT excluded — '
        'it is the first real post-pregnancy cycle', () {
      final starts = pregnancyExclusionStarts(
        episodes: episodes,
        modeStartedOn: d(2026, 1, 24),
        exitedOn: d(2026, 10, 30),
      );
      expect(starts.contains(d(2026, 10, 30)), isFalse);
    });

    test('an unstamped pregnancy (null modeStartedOn) excludes nothing — '
        'an honest empty set, not a guessed interval', () {
      expect(
        pregnancyExclusionStarts(
          episodes: episodes,
          modeStartedOn: null,
          exitedOn: d(2026, 10, 30),
        ),
        isEmpty,
      );
    });

    test('pre-pregnancy cycles are never excluded', () {
      final starts = pregnancyExclusionStarts(
        episodes: episodes,
        modeStartedOn: d(2026, 1, 24),
        exitedOn: d(2026, 10, 30),
      );
      expect(starts.contains(d(2026, 1, 1)), isFalse);
    });
  });

  group('the post-pregnancy mean (Issue #192\'s regression)', () {
    // The canonical poisoning scenario, matching how a real pregnancy
    // renders today: four steady 28-day cycles, then a pregnancy
    // (mode_started_on = 2026-01-24, the last real period start), two
    // mid-pregnancy breakthrough-bleed episodes inside it, the pregnancy
    // exit on 2026-10-30 with the first real post-pregnancy period the
    // same day, and four steady 28-day cycles after.
    final bleedStarts = [
      // Pre-pregnancy: four steady 28-day cycles.
      d(2025, 11, 1), d(2025, 11, 29), d(2025, 12, 27), d(2026, 1, 24),
      // Mid-pregnancy breakthrough episodes.
      d(2026, 3, 15), d(2026, 5, 2),
      // Exit-day period + four post-pregnancy 28-day cycles.
      d(2026, 10, 30), d(2026, 11, 27), d(2026, 12, 25), d(2027, 1, 22),
    ];
    final entries = [for (final start in bleedStarts) _bleed(start)];
    final modeStartedOn = d(2026, 1, 24);
    final exitedOn = d(2026, 10, 30);
    final today = d(2027, 1, 23);
    final episodes = deriveEpisodes(bleedStarts);

    test('WITHOUT the exclusion the mean is poisoned (the current bug, '
        'reproduced)', () {
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: today,
      );
      // The 50- and 48-day apparent cycles the breakthrough episodes
      // manufacture sit INSIDE the 15-60 validity window, so they feed
      // the mean: (28*3 + 50 + 48 + 28*3) / 8 = 33.25, not 28.
      expect(prediction, isA<ActivePrediction>());
      final active = prediction as ActivePrediction;
      expect(active.averagedCycleLengths, containsAll([50, 48]));
      expect(active.meanCycleLengthDays, 33.25);
    });

    test('WITH the offered exclusion accepted the mean is exactly the '
        'pre-pregnancy 28 days', () {
      final exclusions = pregnancyExclusionStarts(
        episodes: episodes,
        modeStartedOn: modeStartedOn,
        exitedOn: exitedOn,
      );
      expect(exclusions, {d(2026, 1, 24), d(2026, 3, 15), d(2026, 5, 2)});
      final prediction = computePredictionFromEntries(
        entries: entries,
        today: today,
        omittedCycleStarts: exclusions,
      );
      expect(prediction, isA<ActivePrediction>());
      final active = prediction as ActivePrediction;
      expect(active.averagedCycleLengths,
          everyElement(28), reason: 'only the real 28-day cycles remain');
      expect(active.meanCycleLengthDays, 28.0);
    });

    test('declining still auto-flags the pregnancy-long cycle as a '
        'candidate outlier in cycle history (#132\'s mechanism)', () {
      // No exclusions written — the declined branch.
      final history = deriveCycleHistory(
        episodes: episodes,
        today: today,
        omittedCycleStarts: const {},
      );
      // The 05-02 → 10-30 apparent cycle (181 days) is outside the 15-60
      // validity window, so cycle history auto-flags it as an outlier
      // (never averaged, always eligible for the manual omit toggle).
      final longCycle = history.items
          .firstWhere((item) => item.start == d(2026, 5, 2));
      expect(longCycle.lengthDays, 181);
      expect(longCycle.outlier, isTrue,
          reason: 'auto-flagged without any exclusion row');
      expect(longCycle.omitted, isFalse,
          reason: 'declining writes nothing; the toggle stays available');
      // And accepting later flips exactly that flag per cycle — the
      // same mechanism the exit offer drives in bulk.
      final withExclusion = deriveCycleHistory(
        episodes: episodes,
        today: today,
        omittedCycleStarts: {d(2026, 5, 2)},
      );
      expect(
        withExclusion.items
            .firstWhere((item) => item.start == d(2026, 5, 2))
            .omitted,
        isTrue,
      );
    });
  });
}
