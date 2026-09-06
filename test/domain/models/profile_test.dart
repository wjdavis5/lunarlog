/// Unit tests for the pure `Profile` value type — construction, copyWith,
/// equality/hashCode, and toString. Previously untested (no
/// `test/domain/models/` coverage existed), which is why `toString` showed
/// up as a CRAP-gate offender (0% coverage).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

Profile _profile({
  String id = 'p1',
  String displayName = 'Alex',
  bool isMinor = false,
  int sortOrder = 0,
  DateTime? archivedAt,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
  int? birthYear,
  ProfileRelationship? relationship,
  DateTime? transferredAt,
}) =>
    Profile(
      id: id,
      displayName: displayName,
      isMinor: isMinor,
      sortOrder: sortOrder,
      archivedAt: archivedAt,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
      deletedAt: deletedAt,
      birthYear: birthYear,
      relationship: relationship,
      transferredAt: transferredAt,
    );

void main() {
  group('Profile.copyWith', () {
    test('no arguments returns an equal copy', () {
      final profile = _profile();
      expect(profile.copyWith(), profile);
    });

    test('explicit null clears archivedAt and deletedAt (the _unset sentinel)', () {
      final profile = _profile(
        archivedAt: DateTime.utc(2026, 2, 1),
        deletedAt: DateTime.utc(2026, 2, 2),
      );
      final cleared = profile.copyWith(archivedAt: null, deletedAt: null);
      expect(cleared.archivedAt, isNull);
      expect(cleared.deletedAt, isNull);
    });

    test('overrides only the given fields', () {
      final profile = _profile();
      final renamed = profile.copyWith(displayName: 'Jamie');
      expect(renamed.displayName, 'Jamie');
      expect(renamed.id, profile.id);
    });

    test('copyWith() with no arguments preserves a set relationship', () {
      final profile = _profile(relationship: ProfileRelationship.daughter);
      expect(profile.copyWith().relationship, ProfileRelationship.daughter);
    });

    test('copyWith(relationship: null) clears a set relationship', () {
      final profile = _profile(relationship: ProfileRelationship.son);
      final cleared = profile.copyWith(relationship: null);
      expect(cleared.relationship, isNull);
    });

    test('copyWith(birthYear: null) clears a set birth year, and other '
        'fields are unaffected', () {
      final profile = _profile(birthYear: 2015);
      final cleared = profile.copyWith(birthYear: null);
      expect(cleared.birthYear, isNull);
      expect(cleared.displayName, profile.displayName);
    });

    test('copyWith(transferredAt: ...) sets the ownership-transfer instant', () {
      final profile = _profile();
      final transferred =
          profile.copyWith(transferredAt: DateTime.utc(2026, 4, 1));
      expect(transferred.transferredAt, DateTime.utc(2026, 4, 1));
    });
  });

  group('Profile equality and hashCode', () {
    test('same field values are equal, with matching hashCode', () {
      final a = _profile(sortOrder: 2);
      final b = _profile(sortOrder: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields are unequal', () {
      final base = _profile();
      expect(base, isNot(_profile(id: 'other')));
      expect(base, isNot(_profile(displayName: 'Other')));
      expect(base, isNot(_profile(isMinor: true)));
      expect(base, isNot(_profile(archivedAt: DateTime.utc(2026, 3, 1))));
      expect(base, isNot(_profile(deletedAt: DateTime.utc(2026, 3, 1))));
    });

    test('two Profiles differing only in birthYear are unequal and hash '
        'differently', () {
      final a = _profile(birthYear: 2010);
      final b = _profile(birthYear: 2015);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
    });

    test('two Profiles differing only in relationship are unequal', () {
      final a = _profile(relationship: ProfileRelationship.daughter);
      final b = _profile(relationship: ProfileRelationship.son);
      expect(a, isNot(b));
    });

    test('two Profiles differing only in transferredAt are unequal', () {
      final a = _profile(transferredAt: DateTime.utc(2026, 4, 1));
      final b = _profile(transferredAt: DateTime.utc(2026, 4, 2));
      expect(a, isNot(b));
    });
  });

  group('Profile.toString', () {
    test('adult, live, not archived: no markers', () {
      final s = _profile(displayName: 'Alex', isMinor: false).toString();
      expect(s, contains('p1'));
      expect(s, contains('Alex'));
      expect(s, isNot(contains('minor')));
      expect(s, isNot(contains('archived')));
      expect(s, isNot(contains('tombstoned')));
    });

    test('minor: includes the minor marker', () {
      expect(_profile(isMinor: true).toString(), contains('minor'));
    });

    test('archived: includes the archived marker', () {
      final s = _profile(archivedAt: DateTime.utc(2026, 2, 1)).toString();
      expect(s, contains('archived'));
    });

    test('tombstoned: includes the tombstoned marker', () {
      final s = _profile(deletedAt: DateTime.utc(2026, 2, 1)).toString();
      expect(s, contains('tombstoned'));
    });
  });
}
