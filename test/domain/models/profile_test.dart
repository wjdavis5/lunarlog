/// Unit tests for the pure `Profile` value type — construction, copyWith,
/// equality/hashCode, and toString. Previously untested (no
/// `test/domain/models/` coverage existed), which is why `toString` showed
/// up as a CRAP-gate offender (0% coverage).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/models/profile_relationship.dart';

Profile _profile({
  String id = 'p1',
  String displayName = 'Alex',
  bool isMinor = false,
  ProfileMode mode = ProfileMode.standard,
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
      mode: mode,
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

    test('mode defaults to standard and copyWith switches it (Issue #131)',
        () {
      expect(_profile().mode, ProfileMode.standard);
      final teen = _profile().copyWith(mode: ProfileMode.teen);
      expect(teen.mode, ProfileMode.teen);
      expect(teen.copyWith().mode, ProfileMode.teen,
          reason: 'copyWith with no arguments preserves the mode');
    });
  });

  group('ProfileMode (Issue #131)', () {
    test('toDb/fromDb round-trip the live modes, the legacy caregiver wire '
        'value still parses (as standard), and unknown degrades to standard '
        'rather than throwing (Issue #131/#850)', () {
      for (final mode in [
        ProfileMode.standard,
        ProfileMode.teen,
        ProfileMode.irregular,
      ]) {
        expect(ProfileMode.fromDb(mode.toDb()), mode);
      }
      // Issue #850: `caregiver` is retired as a mode — its wire value is
      // still emitted by toDb and accepted by fromDb, but a parse folds it
      // to the neutral default (the #853 `irregular` precedent).
      expect(ProfileMode.caregiver.toDb(), 'caregiver',
          reason: 'the legacy wire value is never renamed');
      expect(ProfileMode.fromDb('caregiver'), ProfileMode.standard,
          reason: 'a stored pre-#850 caregiver row reads as standard');
      expect(ProfileMode.fromDb('future_mode'), ProfileMode.standard);
      expect(ProfileMode.fromDb(null), ProfileMode.standard);
    });

    test('every mode carries non-empty label and hint (copy review)', () {
      for (final mode in ProfileMode.values) {
        expect(mode.label, isNotEmpty);
        expect(mode.hint, isNotEmpty);
      }
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

    test('two Profiles differing only in mode are unequal (Issue #131)', () {
      final a = _profile(mode: ProfileMode.standard);
      final b = _profile(mode: ProfileMode.teen);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
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

  group('minor status derivation (Issue #820)', () {
    test('a present birth year wins over a disagreeing minor flag, both '
        'directions', () {
      // Flagged minor, but the birth year says clearly adult.
      final flaggedButAdult =
          _profile(isMinor: true, birthYear: 1980);
      expect(flaggedButAdult.isMinorAsOfYear(2026), isFalse);

      // Not flagged, but the birth year says clearly a minor.
      final unflaggedButMinor =
          _profile(isMinor: false, birthYear: 2020);
      expect(unflaggedButMinor.isMinorAsOfYear(2026), isTrue);
    });

    test('a null birth year preserves the stored flag exactly', () {
      expect(_profile(isMinor: true, birthYear: null).isMinorAsOfYear(2026),
          isTrue);
      expect(_profile(isMinor: false, birthYear: null).isMinorAsOfYear(2026),
          isFalse);
    });

    test('the <= 18 boundary fails closed across the whole calendar year '
        'Y + 18 (Issue #296 behavior preserved)', () {
      // Someone born in year Y is 18-or-younger for all of Y + 18.
      expect(_profile(birthYear: 2008).isMinorAsOfYear(2026), isTrue);
      expect(_profile(birthYear: 2007).isMinorAsOfYear(2026), isFalse);
      expect(_profile(birthYear: 2026 - 18).isMinorAsOfYear(2026), isTrue);
      expect(_profile(birthYear: 2026 - 19).isMinorAsOfYear(2026), isFalse);
    });

    test('isMinorAsOf uses the supplied clock, never a wall-clock read', () {
      final profile = _profile(birthYear: 2008);
      expect(profile.isMinorAsOf(DateTime.utc(2026, 1, 1)), isTrue);
      expect(profile.isMinorAsOf(DateTime.utc(2030, 1, 1)), isFalse);
    });

    test('deriveMinorStatus is the single shared rule', () {
      expect(deriveMinorStatus(storedIsMinor: true, birthYear: 1980, currentYear: 2026), isFalse);
      expect(deriveMinorStatus(storedIsMinor: false, birthYear: null, currentYear: 2026), isFalse);
      expect(deriveMinorStatus(storedIsMinor: true, birthYear: null, currentYear: 2026), isTrue);
      expect(deriveMinorStatus(storedIsMinor: false, birthYear: 2020, currentYear: 2026), isTrue);
    });
  });
}
