/// Issue #540: `profileGuardianToDomain` must fail *closed* on an
/// unrecognised `role`/`status` — never propagate `GuardianRole.fromDb`/
/// `GuardianStatus.fromDb`'s null through to a domain [ProfileGuardian]
/// this codebase has no null-role/null-status representation for.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/repositories/mappers.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

db.ProfileGuardianData _row({required String role, required String status}) =>
    db.ProfileGuardianData(
      id: 'g1',
      profileId: 'p1',
      userId: 'u1',
      role: role,
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('profileGuardianToDomain (issue #540)', () {
    test('a recognised role and status map through unchanged', () {
      final guardian =
          profileGuardianToDomain(_row(role: 'co_parent', status: 'accepted'));
      expect(guardian.role, GuardianRole.coParent);
      expect(guardian.status, GuardianStatus.accepted);
    });

    test('an unrecognised role fails closed to viewer (least privilege)', () {
      final guardian =
          profileGuardianToDomain(_row(role: 'super_admin', status: 'accepted'));
      expect(guardian.role, GuardianRole.viewer);
      expect(guardian.role.canLog, isFalse);
      expect(guardian.role.canEditProfile, isFalse);
      expect(guardian.role.canManageGuardians, isFalse);
      expect(guardian.role.canDeleteProfile, isFalse);
    });

    test('an unrecognised status fails closed to revoked, never accepted',
        () {
      final guardian =
          profileGuardianToDomain(_row(role: 'viewer', status: 'super_active'));
      expect(guardian.status, GuardianStatus.revoked);
    });

    test('both unrecognised at once fail closed on both fields', () {
      final guardian =
          profileGuardianToDomain(_row(role: 'nonsense', status: 'nonsense'));
      expect(guardian.role, GuardianRole.viewer);
      expect(guardian.status, GuardianStatus.revoked);
    });
  });
}
