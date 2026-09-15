/// Issue #235: the pure data shaping behind the side-by-side cycle
/// comparison — cycle-day alignment, flow/tag carry-through, the excluded
/// flag, the open-cycle bound, the [kMaxCycleDays] cap, and the compared
/// statistics.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/insights/cycle_comparison.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart' show kMaxCycleDays;

DayEntry _entry(
  LocalDate date,
  FlowLevel flow, {
  List<String> tags = const [],
}) =>
    DayEntry(
      id: 'e-${date.iso}',
      profileId: 'p1',
      localDate: date,
      tz: 'UTC',
      flow: flow,
      tags: tags,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('deriveCycleComparison', () {
    test('unknown cycle start returns null', () {
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final result = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 1, 10),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2099, 1, 1),
      );
      expect(result, isNull);
    });

    test('aligns two completed cycles by cycle day, carrying flow and tags', () {
      // Cycle A: Jan 1-4 (episode), next start Feb 1 -> length 31.
      // Cycle B: Feb 1-3, next start Mar 1 -> length 28.
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 3)),
        Episode(LocalDate(2026, 3, 1), LocalDate(2026, 3, 1)),
      ];
      final entries = [
        _entry(LocalDate(2026, 1, 1), FlowLevel.medium, tags: const ['cramps']),
        _entry(LocalDate(2026, 1, 2), FlowLevel.heavy),
        _entry(LocalDate(2026, 2, 1), FlowLevel.light, tags: const ['fatigue']),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: entries,
        today: LocalDate(2026, 3, 15),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
      );

      expect(data, isNotNull);
      expect(data!.sideA.cycleStart, LocalDate(2026, 1, 1));
      expect(data.sideA.lengthDays, 31);
      expect(data.sideA.isOpen, isFalse);
      expect(data.sideA.excluded, isFalse);
      expect(data.sideA.days, hasLength(31));
      expect(data.sideA.days[0].cycleDay, 1);
      expect(data.sideA.days[0].flow, FlowLevel.medium);
      expect(data.sideA.days[0].tags, ['cramps']);
      expect(data.sideA.days[1].flow, FlowLevel.heavy);
      expect(data.sideA.days[2].flow, isNull); // Jan 3: nothing logged.
      expect(data.sideA.bleedDayCount, 2);

      expect(data.sideB.cycleStart, LocalDate(2026, 2, 1));
      expect(data.sideB.lengthDays, 28);
      expect(data.sideB.days, hasLength(28));
      expect(data.sideB.days[0].flow, FlowLevel.light);
      expect(data.sideB.days[0].tags, ['fatigue']);
      expect(data.sideB.bleedDayCount, 1);

      expect(data.maxCycleDay, 31);
      expect(data.stats.lengthDeltaDays, 28 - 31);
      expect(data.stats.bleedDayCountDelta, 1 - 2);
    });

    test('the still-open cycle is bounded by today, not a next start', () {
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 3)),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 2, 6), // 6 days into the open cycle.
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
      );

      expect(data!.sideB.isOpen, isTrue);
      expect(data.sideB.lengthDays, isNull);
      expect(data.sideB.days, hasLength(6));
      expect(data.sideB.days.last.cycleDay, 6);
      expect(data.sideB.days.last.date, LocalDate(2026, 2, 6));
      // An open side's unknown length makes the length delta unknown too.
      expect(data.stats.lengthDeltaDays, isNull);
    });

    test('excluded cycle starts are marked, not silently included', () {
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 3)),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 2, 10),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
        excludedCycleStarts: {LocalDate(2026, 1, 1)},
      );

      expect(data!.sideA.excluded, isTrue);
      expect(data.sideB.excluded, isFalse);
    });

    test('a cycle length is capped at kMaxCycleDays days out from its start', () {
      // Next start is 90 days after cycle A's own start -- far outside the
      // valid window; the comparison must not render 90 aligned rows.
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 4, 1), LocalDate(2026, 4, 3)),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 4, 10),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 4, 1),
      );

      expect(data!.sideA.days, hasLength(kMaxCycleDays));
      expect(data.sideA.lengthDays, kMaxCycleDays);
    });

    test('an overdue open cycle is also capped at kMaxCycleDays', () {
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4)),
        Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 3)),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 6, 1), // Far more than kMaxCycleDays later.
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
      );

      expect(data!.sideB.isOpen, isTrue);
      expect(data.sideB.days, hasLength(kMaxCycleDays));
    });

    test('a tombstoned entry is not carried into a day row', () {
      // Explicit episodes (rather than deriving from these same entries)
      // so a tombstoned bleed day dropping out of `bleedDatesOf` doesn't
      // also erase the episode itself -- isolating this to the
      // entriesByDate lookup this file builds on top of [episodes].
      final episodes = [Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 4))];
      final tombstoned = _entry(LocalDate(2026, 1, 1), FlowLevel.heavy)
          .copyWith(deletedAt: DateTime.utc(2026, 1, 5));
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: [tombstoned],
        today: LocalDate(2026, 1, 10),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 1, 1),
      );

      expect(data!.sideA.days.first.flow, isNull);
    });
  });

  group('deriveCycleComparisonFromEntries', () {
    test('derives episodes from entries the same way cycle_history.dart does', () {
      final entries = [
        _entry(LocalDate(2026, 1, 1), FlowLevel.medium),
        _entry(LocalDate(2026, 1, 2), FlowLevel.medium),
        _entry(LocalDate(2026, 2, 1), FlowLevel.medium),
      ];
      final data = deriveCycleComparisonFromEntries(
        entries: entries,
        today: LocalDate(2026, 2, 10),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
      );

      expect(data, isNotNull);
      expect(data!.sideA.lengthDays, 31);
    });
  });
}
