/// Unit tests for the health-sync policy's remaining public surface (Issue
/// #153): [ownerUserIdFor]'s resolution of the client-side ownership
/// signal (an accepted `primary_guardian` row) that
/// [HealthSyncBinding.canBind]/[HealthSyncBinding.canWrite] rely on. The
/// pure allow/deny decision itself moved to a private function in
/// `health_sync_binding.dart` (review fix — see that file's doc) and is
/// covered by `test/domain/health/health_sync_binding_test.dart` instead,
/// exercised only through [HealthSyncBinding]'s public `canBind`/`canWrite`
/// entry points.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

ProfileGuardian _guardian({
  String id = 'g1',
  String profileId = 'p1',
  String userId = 'u1',
  GuardianRole role = GuardianRole.primaryGuardian,
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: id,
      profileId: profileId,
      userId: userId,
      role: role,
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('ownerUserIdFor', () {
    test('returns the accepted primary_guardian user id', () {
      final owner = ownerUserIdFor([
        _guardian(userId: 'owner-1', role: GuardianRole.primaryGuardian),
        _guardian(id: 'g2', userId: 'caregiver-1', role: GuardianRole.caregiver),
      ]);
      expect(owner, 'owner-1');
    });

    test('ignores a pending (not-yet-accepted) primary_guardian row', () {
      final owner = ownerUserIdFor([
        _guardian(
          userId: 'owner-1',
          role: GuardianRole.primaryGuardian,
          status: GuardianStatus.pending,
        ),
      ]);
      expect(owner, isNull);
    });

    test('ignores a revoked primary_guardian row', () {
      final owner = ownerUserIdFor([
        _guardian(
          userId: 'owner-1',
          role: GuardianRole.primaryGuardian,
          status: GuardianStatus.revoked,
        ),
      ]);
      expect(owner, isNull);
    });

    test('a non-owner role (co_parent/caregiver/viewer) never resolves as '
        'owner even when accepted', () {
      final owner = ownerUserIdFor([
        _guardian(userId: 'co-parent-1', role: GuardianRole.coParent),
        _guardian(id: 'g2', userId: 'caregiver-1', role: GuardianRole.caregiver),
        _guardian(id: 'g3', userId: 'viewer-1', role: GuardianRole.viewer),
      ]);
      expect(owner, isNull);
    });

    test('empty guardians list resolves to null (fails closed)', () {
      expect(ownerUserIdFor(const []), isNull);
    });

    test('more than one accepted primary_guardian row fails closed to null '
        '(review fix) rather than arbitrarily picking one — this should '
        'never happen server-side (profile_guardians_one_primary_uq) but '
        'the client must not trust that a stale/unsynced local copy holds '
        'it', () {
      final owner = ownerUserIdFor([
        _guardian(id: 'g1', userId: 'owner-1', role: GuardianRole.primaryGuardian),
        _guardian(id: 'g2', userId: 'owner-2', role: GuardianRole.primaryGuardian),
      ]);
      expect(owner, isNull);
    });
  });
}
