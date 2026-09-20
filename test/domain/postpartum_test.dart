/// Issue #455 (Postpartum mode): the pure postpartum computations — the
/// day-count the overview surfaces, the "first logged bleed" trigger for
/// the cycles-have-returned offer, and the exit-exclusion interval — plus
/// the shared mode-interval predicate the picker/overview use to decide
/// whether an exit offer exists at all.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/mode_intervals.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/postpartum.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

void main() {
  group('daysSincePostpartumStart', () {
    final start = d(2026, 1, 24);

    test('counts whole civil days from the mode start', () {
      expect(
        daysSincePostpartumStart(modeStartedOn: start, today: start),
        0,
      );
      expect(
        daysSincePostpartumStart(modeStartedOn: start, today: start.addDays(1)),
        1,
      );
      expect(
        daysSincePostpartumStart(
            modeStartedOn: start, today: d(2026, 4, 24)),
        90,
      );
    });

    test('a today before the stored start clamps at 0, never negative', () {
      expect(
        daysSincePostpartumStart(
            modeStartedOn: start, today: start.addDays(-30)),
        0,
      );
    });

    test('Issue #861: a supplied birth date is the anchor, not the mode '
        'start', () {
      // The operator flips the switch 23 days after the birth; the count
      // must run from the birth date the issue collects, not the later
      // mode start.
      expect(
        daysSincePostpartumStart(
          modeStartedOn: d(2026, 1, 24),
          today: d(2026, 1, 31),
          birthDate: d(2026, 1, 1),
        ),
        30,
      );
    });

    test('Issue #861: no birth date keeps the mode-start surrogate', () {
      expect(
        daysSincePostpartumStart(
            modeStartedOn: start, today: start.addDays(5)),
        5,
      );
    });

    test('Issue #861: a today before a supplied birth date clamps at 0', () {
      expect(
        daysSincePostpartumStart(
          modeStartedOn: start,
          today: d(2025, 12, 31),
          birthDate: d(2026, 1, 1),
        ),
        0,
      );
    });
  });

  group('hasLoggedBleedSince', () {
    final start = d(2026, 1, 24);

    test('true when a bleed lands on or after the mode start', () {
      expect(
        hasLoggedBleedSince(
          bleedDates: [d(2026, 1, 24)],
          modeStartedOn: start,
        ),
        isTrue,
      );
      expect(
        hasLoggedBleedSince(
          bleedDates: [d(2026, 1, 1), d(2026, 3, 15)],
          modeStartedOn: start,
        ),
        isTrue,
      );
    });

    test('false when every bleed predates the mode start', () {
      expect(
        hasLoggedBleedSince(
          bleedDates: [d(2026, 1, 1), d(2026, 1, 23)],
          modeStartedOn: start,
        ),
        isFalse,
      );
    });

    test('false with no bleed dates at all', () {
      expect(
        hasLoggedBleedSince(bleedDates: const [], modeStartedOn: start),
        isFalse,
      );
    });

    test('an unstamped start is an honest false, not a guessed interval', () {
      expect(
        hasLoggedBleedSince(
          bleedDates: [d(2026, 3, 15)],
          modeStartedOn: null,
        ),
        isFalse,
      );
    });
  });

  group('postpartumExclusionStarts', () {
    final episodes = deriveEpisodes([
      d(2026, 1, 1),
      d(2026, 1, 24),
      d(2026, 2, 20),
      d(2026, 10, 30),
    ]);

    test('excludes every episode start in [modeStartedOn, exitedOn)', () {
      expect(
        postpartumExclusionStarts(
          episodes: episodes,
          modeStartedOn: d(2026, 1, 24),
          exitedOn: d(2026, 10, 30),
        ),
        {d(2026, 1, 24), d(2026, 2, 20)},
      );
    });

    test('a period starting exactly on the exit date is NOT excluded — '
        'it is the first real cycle of the returned cycle', () {
      final starts = postpartumExclusionStarts(
        episodes: episodes,
        modeStartedOn: d(2026, 1, 24),
        exitedOn: d(2026, 10, 30),
      );
      expect(starts.contains(d(2026, 10, 30)), isFalse);
    });

    test('the last pre-birth period (before the start) is NOT excluded', () {
      final starts = postpartumExclusionStarts(
        episodes: episodes,
        modeStartedOn: d(2026, 1, 24),
        exitedOn: d(2026, 10, 30),
      );
      expect(starts.contains(d(2026, 1, 1)), isFalse);
    });

    test('an unstamped start excludes nothing — an honest empty set', () {
      expect(
        postpartumExclusionStarts(
          episodes: episodes,
          modeStartedOn: null,
          exitedOn: d(2026, 10, 30),
        ),
        isEmpty,
      );
    });
  });

  group('hasModeIntervalExclusion', () {
    test('true for the discrete-interval modes', () {
      expect(hasModeIntervalExclusion(LifecycleMode.pregnancy), isTrue);
      expect(hasModeIntervalExclusion(LifecycleMode.postpartum), isTrue);
    });

    test('false for tracking, conceive, and the open-ended perimenopause', () {
      expect(hasModeIntervalExclusion(LifecycleMode.tracking), isFalse);
      expect(hasModeIntervalExclusion(LifecycleMode.conceive), isFalse);
      expect(hasModeIntervalExclusion(LifecycleMode.perimenopause), isFalse);
    });
  });
}
