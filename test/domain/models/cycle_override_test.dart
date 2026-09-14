/// Unit tests for the pure `CycleOverride` value type (Issue #188) —
/// equality/hashCode (via the `_sameIdentity`/`_sameDetails` split) and
/// toString. Mirrors `observation_test.dart`'s shape.
///
/// `copyWith` was removed (Issue #606/#610/#611/#626 bundle review,
/// LLA-084 CRAP-gate follow-up): a repo-wide grep found zero call sites —
/// every write path (`DriftCycleOverridesRepository`,
/// `AccountImporter._applyCycleOverride`) calls
/// `LunarLogStorage.upsertCycleOverride(...)` directly with individual
/// named fields rather than copying an existing domain instance — so it
/// was dead code, deleted rather than tested.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';

CycleOverride _override({
  String id = 'o1',
  String profileId = 'p1',
  String cycleStartDate = '2026-09-01',
  bool excludedFromAverage = false,
  bool manualStart = false,
  String? noteId,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) =>
    CycleOverride(
      id: id,
      profileId: profileId,
      cycleStartDate: cycleStartDate,
      excludedFromAverage: excludedFromAverage,
      manualStart: manualStart,
      noteId: noteId,
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 1),
      deletedAt: deletedAt,
    );

void main() {
  group('CycleOverride.isTombstone', () {
    test('false when deletedAt is null', () {
      expect(_override().isTombstone, isFalse);
    });

    test('true when deletedAt is set', () {
      expect(_override(deletedAt: DateTime.utc(2026, 9, 2)).isTombstone,
          isTrue);
    });
  });

  group('CycleOverride equality and hashCode', () {
    test('identical instance is equal to itself', () {
      final override = _override();
      // ignore: prefer_const_constructors
      expect(override == override, isTrue);
    });

    test('same field values are equal, with matching hashCode', () {
      final a = _override(
          excludedFromAverage: true, manualStart: true, noteId: 'n1');
      final b = _override(
          excludedFromAverage: true, manualStart: true, noteId: 'n1');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing identity fields (id/profileId/cycleStartDate) '
        'are unequal (exercises _sameIdentity via ==)', () {
      final base = _override();
      expect(base, isNot(_override(id: 'other')));
      expect(base, isNot(_override(profileId: 'other')));
      expect(base, isNot(_override(cycleStartDate: '2026-09-02')));
    });

    test('same identity but differing detail fields are unequal '
        '(exercises _sameDetails via ==)', () {
      final base = _override();
      expect(base, isNot(_override(excludedFromAverage: true)));
      expect(base, isNot(_override(manualStart: true)));
      expect(base, isNot(_override(noteId: 'n1')));
      expect(base, isNot(_override(updatedAt: DateTime.utc(2026, 9, 5))));
      expect(base, isNot(_override(deletedAt: DateTime.utc(2026, 9, 5))));
    });

    test('not equal to a different type', () {
      // ignore: unrelated_type_equality_checks
      expect(_override() == 'not a CycleOverride', isFalse);
    });
  });

  group('CycleOverride.toString', () {
    test('base case: no excluded/manual/tombstoned markers', () {
      final s = _override().toString();
      expect(s, contains('o1'));
      expect(s, contains('p1'));
      expect(s, contains('2026-09-01'));
      expect(s, isNot(contains('excluded')));
      expect(s, isNot(contains('manual')));
      expect(s, isNot(contains('tombstoned')));
    });

    test('excludedFromAverage: includes the excluded marker only', () {
      final s = _override(excludedFromAverage: true).toString();
      expect(s, contains('excluded'));
      expect(s, isNot(contains('manual')));
      expect(s, isNot(contains('tombstoned')));
    });

    test('manualStart: includes the manual marker only', () {
      final s = _override(manualStart: true).toString();
      expect(s, contains('manual'));
      expect(s, isNot(contains('excluded')));
      expect(s, isNot(contains('tombstoned')));
    });

    test('tombstoned: includes the tombstoned marker only', () {
      final s = _override(deletedAt: DateTime.utc(2026, 9, 2)).toString();
      expect(s, contains('tombstoned'));
      expect(s, isNot(contains('excluded')));
      expect(s, isNot(contains('manual')));
    });

    test('all three markers combined', () {
      final s = _override(
        excludedFromAverage: true,
        manualStart: true,
        deletedAt: DateTime.utc(2026, 9, 2),
      ).toString();
      expect(s, contains('excluded'));
      expect(s, contains('manual'));
      expect(s, contains('tombstoned'));
    });
  });
}
