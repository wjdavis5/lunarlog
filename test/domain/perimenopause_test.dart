/// Issue #196 (Perimenopause mode): the pure domain behavior — mode
/// predicate, fertile-window suppression, the day-sheet category
/// prioritization, and the current-vs-previous cycle selection that the
/// comparison-first Cycle View is built on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/perimenopause.dart';
import 'package:lunarlog/domain/tags.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

Episode _episode(LocalDate start, LocalDate end) => Episode(start, end);

void main() {
  group('isPerimenopauseMode (issue #196)', () {
    test('true only for the perimenopause life-stage mode', () {
      expect(isPerimenopauseMode(LifecycleMode.perimenopause), isTrue);
      for (final mode in LifecycleMode.values) {
        if (mode == LifecycleMode.perimenopause) continue;
        expect(isPerimenopauseMode(mode), isFalse, reason: mode.name);
      }
      // Null = no profile_modes row yet, exactly as LifecycleMode.fromDb
      // degrades to tracking.
      expect(isPerimenopauseMode(null), isFalse);
    });
  });

  group('suppressesFertileWindow (AC1)', () {
    test('true for perimenopause, false for every other mode and null', () {
      expect(suppressesFertileWindow(LifecycleMode.perimenopause), isTrue);
      for (final mode in LifecycleMode.values) {
        if (mode == LifecycleMode.perimenopause) continue;
        expect(suppressesFertileWindow(mode), isFalse, reason: mode.name);
      }
      expect(suppressesFertileWindow(null), isFalse);
    });
  });

  group('perimenopauseCategoryOrder (AC3)', () {
    test('surfaces the perimenopause cluster first, in order', () {
      final ordered = perimenopauseCategoryOrder(TagCategory.values);
      expect(
        ordered.take(kPerimenopausePriorityCategories.length),
        kPerimenopausePriorityCategories,
      );
    });

    test('is a permutation — never adds or removes a category', () {
      final ordered = perimenopauseCategoryOrder(TagCategory.values);
      expect(ordered.length, TagCategory.values.length);
      expect(ordered.toSet(), TagCategory.values.toSet());
      expect(
        ordered.whereType<TagCategory>().length,
        TagCategory.values.length,
      );
    });

    test('a category already absent (a tracking preference hid it) is not '
        'reintroduced', () {
      final base = [
        for (final category in TagCategory.values)
          if (category != TagCategory.hotFlashes) category,
      ];
      final ordered = perimenopauseCategoryOrder(base);
      expect(ordered, isNot(contains(TagCategory.hotFlashes)));
      expect(ordered.length, base.length);
      expect(ordered.toSet(), base.toSet());
    });
  });

  group('hot_flashes stays top-level in every mode (AC4)', () {
    test('the category is present in every care mode\'s order and the '
        'taxonomy carries the code', () {
      for (final mode in ProfileMode.values) {
        expect(
          careModeCopyFor(mode).categoriesInOrder,
          contains(TagCategory.hotFlashes),
          reason: mode.name,
        );
      }
      expect(
        kTagTaxonomy.any((tag) => tag.code == 'hot_flashes'),
        isTrue,
      );
      // Perimenopause only reorders it to the front; it is never removed.
      expect(
        perimenopauseCategoryOrder(TagCategory.values).first,
        TagCategory.hotFlashes,
      );
    });
  });

  group('perimenopauseComparisonStarts (AC2)', () {
    test('null with fewer than two logged cycles', () {
      expect(perimenopauseComparisonStarts(const []), isNull);
      expect(
        perimenopauseComparisonStarts([
          _episode(d(2026, 3, 1), d(2026, 3, 5)),
        ]),
        isNull,
      );
    });

    test('prefers the two most recent completed cycles (three starts)', () {
      final starts = perimenopauseComparisonStarts([
        _episode(d(2026, 3, 1), d(2026, 3, 5)),
        _episode(d(2026, 4, 1), d(2026, 4, 5)),
        _episode(d(2026, 5, 1), d(2026, 5, 5)),
      ]);
      expect(starts, isNotNull);
      // The newest start (May 1) is the open cycle; the two before it are
      // the completed pair, whose lengths are actually comparable.
      expect(starts!.previous, d(2026, 3, 1));
      expect(starts.current, d(2026, 4, 1));
    });

    test('falls back to the last two starts with only one completed cycle', () {
      final starts = perimenopauseComparisonStarts([
        _episode(d(2026, 3, 1), d(2026, 3, 5)),
        _episode(d(2026, 4, 1), d(2026, 4, 5)),
      ]);
      expect(starts, isNotNull);
      expect(starts!.previous, d(2026, 3, 1));
      expect(starts.current, d(2026, 4, 1));
    });

    test('returns the chronological last two, even for unsorted input', () {
      final starts = perimenopauseComparisonStarts([
        _episode(d(2026, 5, 1), d(2026, 5, 5)),
        _episode(d(2026, 3, 1), d(2026, 3, 5)),
        _episode(d(2026, 4, 1), d(2026, 4, 5)),
      ]);
      expect(starts, isNotNull);
      expect(starts!.previous, d(2026, 3, 1));
      expect(starts.current, d(2026, 4, 1));
    });

    test('value equality and toString are stable', () {
      final a = PerimenopauseComparisonStarts(
        previous: d(2026, 4, 1),
        current: d(2026, 5, 1),
      );
      final b = PerimenopauseComparisonStarts(
        previous: d(2026, 4, 1),
        current: d(2026, 5, 1),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('2026-04-01'));
    });
  });
}
