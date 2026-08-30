import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

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

void main() {
  group('episode merging', () {
    test('a one-day gap merges into a single episode', () {
      // Bleed days Jan 1–3 plus Jan 5 (only Jan 4 missing).
      final episodes = deriveEpisodes([d(2026, 1, 1), d(2026, 1, 2), d(2026, 1, 3), d(2026, 1, 5)]);
      expect(episodes, hasLength(1));
      expect(episodes.single.start, d(2026, 1, 1));
      expect(episodes.single.end, d(2026, 1, 5));
      expect(episodes.single.lengthDays, 5);
    });

    test('a two-day gap splits into two episodes', () {
      // Bleed days Jan 1–3 plus Jan 6 (Jan 4 and 5 missing).
      final episodes = deriveEpisodes([d(2026, 1, 1), d(2026, 1, 2), d(2026, 1, 3), d(2026, 1, 6)]);
      expect(episodes, hasLength(2));
      expect(episodes[0], Episode(d(2026, 1, 1), d(2026, 1, 3)));
      expect(episodes[1], Episode(d(2026, 1, 6), d(2026, 1, 6)));
      expect(episodes[1].lengthDays, 1);
    });

    test('single date yields a single-day episode; unsorted duplicate input is normalized',
        () {
      final episodes = deriveEpisodes([d(2026, 3, 10), d(2026, 3, 10), d(2026, 2, 2)]);
      expect(episodes, hasLength(2));
      expect(episodes[0], Episode(d(2026, 2, 2), d(2026, 2, 2)));
      expect(episodes[1], Episode(d(2026, 3, 10), d(2026, 3, 10)));
    });

    test('empty input yields no episodes', () {
      expect(deriveEpisodes(const []), isEmpty);
    });

    test('episode contains covers its whole span', () {
      final e = Episode(d(2026, 1, 1), d(2026, 1, 5));
      expect(e.contains(d(2026, 1, 1)), isTrue);
      expect(e.contains(d(2026, 1, 3)), isTrue);
      expect(e.contains(d(2026, 1, 5)), isTrue);
      expect(e.contains(d(2026, 1, 6)), isFalse);
      expect(e.contains(d(2025, 12, 31)), isFalse);
    });
  });

  group('bleed dates from entries', () {
    test('any flow above none counts as a bleed day; none does not', () {
      final dates = bleedDatesOf([
        entry(d(2026, 4, 1), FlowLevel.spotting),
        entry(d(2026, 4, 2), FlowLevel.none),
        entry(d(2026, 4, 3), FlowLevel.heavy),
        entry(d(2026, 4, 4), FlowLevel.light),
        entry(d(2026, 4, 5), FlowLevel.medium),
      ]);
      expect(dates, {
        d(2026, 4, 1),
        d(2026, 4, 3),
        d(2026, 4, 4),
        d(2026, 4, 5),
      });
    });

    test('spotting-only days form episodes', () {
      final episodes =
          deriveEpisodes(bleedDatesOf([entry(d(2026, 4, 1), FlowLevel.spotting)]));
      expect(episodes, hasLength(1));
      expect(episodes.single.lengthDays, 1);
    });

    test('tombstoned entries are excluded defensively', () {
      final deleted = entry(d(2026, 4, 1), FlowLevel.heavy)
          .copyWith(deletedAt: DateTime.utc(2026, 4, 2));
      expect(bleedDatesOf([deleted]), isEmpty);
    });
  });

  group('property: arbitrary date sets', () {
    test('episodes never overlap, cover every bleed date, and are maximal', () {
      final random = Random(42);
      for (var iteration = 0; iteration < 200; iteration++) {
        final count = 1 + random.nextInt(60);
        final dates = <LocalDate>{
          for (var i = 0; i < count; i++)
            LocalDate(2025, 1, 1).addDays(random.nextInt(730)),
        };
        final episodes = deriveEpisodes(dates);

        // Sortedness and non-overlap with a hard gap between episodes:
        // non-merged neighbors are >= 3 days apart end-to-start.
        for (var i = 1; i < episodes.length; i++) {
          expect(episodes[i - 1].start.isBefore(episodes[i].start), isTrue);
          expect(episodes[i].start.difference(episodes[i - 1].end),
              greaterThanOrEqualTo(3),
              reason: 'episodes must be separated by >= 2 non-bleed days');
        }

        // Coverage: every bleed date falls in exactly one episode.
        var coveredDates = 0;
        for (final date in dates) {
          final containing =
              episodes.where((e) => e.contains(date)).toList();
          expect(containing, hasLength(1),
              reason: '${date.iso} covered ${containing.length} times');
          coveredDates++;
        }
        expect(coveredDates, dates.length);

        // Maximality: no bleed date sits within 2 days before a start or
        // after an end (it would have been merged into the neighbor).
        for (final e in episodes) {
          for (final offset in [-2, -1, 0]) {
            expect(dates.contains(e.start.addDays(offset)), offset == 0,
                reason: 'start-1/start-2 must not be bleed dates');
          }
          for (final offset in [0, 1, 2]) {
            expect(dates.contains(e.end.addDays(offset)), offset == 0,
                reason: 'end+1/end+2 must not be bleed dates');
          }
        }
      }
    });
  });
}
