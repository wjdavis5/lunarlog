/// Unit tests for the pure ProfileGuardian value type.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

ProfileGuardian _guardian({
  String id = 'g1',
  String profileId = 'p1',
  String userId = 'u1',
  GuardianRole role = GuardianRole.primaryGuardian,
  GuardianStatus status = GuardianStatus.accepted,
  String? displayName = 'Mom',
  String? invitedBy,
  DateTime? createdAt,
  DateTime? updatedAt,
}) =>
    ProfileGuardian(
      id: id,
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      invitedBy: invitedBy,
      createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
      updatedAt: updatedAt ?? DateTime.utc(2026, 1, 1),
    );

void main() {
  group('ProfileGuardian.copyWith', () {
    test('no arguments returns equal instance', () {
      final g = _guardian();
      expect(g.copyWith(), g);
    });

    test('overrides specific fields', () {
      final g = _guardian();
      final updated = g.copyWith(
        displayName: 'New Name',
        role: GuardianRole.coParent,
      );
      expect(updated.displayName, 'New Name');
      expect(updated.role, GuardianRole.coParent);
      expect(updated.id, g.id);
      expect(updated.userId, g.userId);
    });
  });

  group('ProfileGuardian equality and hashCode', () {
    test('identical instance is equal to itself', () {
      final g = _guardian();
      expect(g, g);
      expect(g.hashCode, _guardian().hashCode);
    });

    test('equal instances compare equal', () {
      final a = _guardian();
      final b = _guardian();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing fields compare unequal', () {
      final base = _guardian();
      expect(base, isNot(_guardian(id: 'other')));
      expect(base, isNot(_guardian(profileId: 'other')));
      expect(base, isNot(_guardian(userId: 'other')));
      expect(base, isNot(_guardian(role: GuardianRole.viewer)));
      expect(base, isNot(_guardian(status: GuardianStatus.revoked)));
      expect(base, isNot(_guardian(displayName: 'other')));
      expect(base, isNot(_guardian(invitedBy: 'inviter')));
      expect(base, isNot(_guardian(createdAt: DateTime.utc(2026, 5, 1))));
      expect(base, isNot(_guardian(updatedAt: DateTime.utc(2026, 5, 1))));
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(_guardian() == 'not a guardian', isFalse);
    });
  });

  group('ProfileGuardian.toString', () {
    test('string representation includes profile, user, role, status and name', () {
      final g = _guardian(displayName: 'Papa');
      final s = g.toString();
      expect(s, contains('p1'));
      expect(s, contains('u1'));
      expect(s, contains('primaryGuardian'));
      expect(s, contains('accepted'));
      expect(s, contains('Papa'));
    });
  });

  group('GuardianRole and GuardianStatus enums', () {
    test('toDb and fromDb round-trip properly', () {
      for (final role in GuardianRole.values) {
        expect(GuardianRole.fromDb(role.toDb()), role);
        expect(role.label.isNotEmpty, isTrue);
      }
      for (final status in GuardianStatus.values) {
        expect(GuardianStatus.fromDb(status.toDb()), status);
      }
    });

    test('unknown db value throws ArgumentError', () {
      expect(() => GuardianRole.fromDb('unknown'), throwsArgumentError);
      expect(() => GuardianStatus.fromDb('unknown'), throwsArgumentError);
    });

    test('readOnlyReason is set only for the one role that cannot log '
        '(Issue #3 gap-closure plan, U6)', () {
      expect(GuardianRole.viewer.canLog, isFalse);
      expect(GuardianRole.viewer.readOnlyReason, isNotNull);
      expect(GuardianRole.viewer.readOnlyReason, isNotEmpty);
      for (final role
          in GuardianRole.values.where((r) => r != GuardianRole.viewer)) {
        expect(role.canLog, isTrue);
        expect(role.readOnlyReason, isNull);
      }
    });
  });

  group('acceptedGuardianFor', () {
    test('returns null when currentUserId is null', () {
      expect(acceptedGuardianFor([_guardian(userId: 'u1')], null), isNull);
    });

    test('returns null when the list is empty', () {
      expect(acceptedGuardianFor(const [], 'u1'), isNull);
    });

    test('returns null when no row matches the current user', () {
      expect(
        acceptedGuardianFor([_guardian(userId: 'other')], 'u1'),
        isNull,
      );
    });

    test('returns null for a matching row that is not accepted', () {
      expect(
        acceptedGuardianFor(
          [_guardian(userId: 'u1', status: GuardianStatus.revoked)],
          'u1',
        ),
        isNull,
      );
    });

    test('returns the matching accepted row', () {
      final g = _guardian(userId: 'u1', role: GuardianRole.viewer);
      expect(acceptedGuardianFor([g], 'u1'), g);
    });
  });
}
