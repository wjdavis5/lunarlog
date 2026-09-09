/// Unit tests for the pure health-sync write policy (Issue #153). Covers
/// every deny reason plus the allow path, and [ownerUserIdFor]'s resolution
/// of the client-side ownership signal (an accepted `primary_guardian`
/// row) that [canSyncProfile] relies on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_policy.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';

Profile _profile({
  String id = 'p1',
  bool isMinor = false,
}) =>
    Profile(
      id: id,
      displayName: 'Test Profile',
      isMinor: isMinor,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

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
  group('canSyncProfile', () {
    test('no profile mapped -> noBinding, no writes possible', () {
      final result = canSyncProfile(
        profile: _profile(),
        boundProfileId: null,
        signedInUserId: 'u1',
        ownerUserId: 'u1',
      );
      expect(result, HealthSyncCheck.noBinding);
      expect(result.isAllowed, isFalse);
    });

    test('mapped profile matches, owner signed in -> allowed', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1'),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: 'u1',
      );
      expect(result, HealthSyncCheck.allowed);
      expect(result.isAllowed, isTrue);
    });

    test('mismatched profile (bound to a different one) -> profileNotBound, '
        'write refused', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p2'),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: 'u1',
      );
      expect(result, HealthSyncCheck.profileNotBound);
      expect(result.isAllowed, isFalse);
    });

    test('guardian-only (non-owner) account on a mapped profile -> notOwner, '
        'write refused', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1'),
        boundProfileId: 'p1',
        signedInUserId: 'caregiver-1',
        ownerUserId: 'owner-1',
      );
      expect(result, HealthSyncCheck.notOwner);
      expect(result.isAllowed, isFalse);
    });

    test('signed out (no signedInUserId) on an otherwise-eligible mapped '
        'profile -> notOwner, fails closed', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1'),
        boundProfileId: 'p1',
        signedInUserId: null,
        ownerUserId: 'owner-1',
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    test('unresolved owner (guardians not yet synced) -> notOwner, fails '
        'closed rather than allowing', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1'),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: null,
      );
      expect(result, HealthSyncCheck.notOwner);
    });

    test('minor profile without ownership transfer -> minorRequiresTransfer, '
        'write refused even for the owner', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1', isMinor: true),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: 'u1',
      );
      expect(result, HealthSyncCheck.minorRequiresTransfer);
      expect(result.isAllowed, isFalse);
    });

    test('minor profile is allowed when minorBindingAllowed is explicitly '
        'set (the one-line product-decision flip) and every other check '
        'passes', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1', isMinor: true),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: 'u1',
        minorBindingAllowed: true,
      );
      expect(result, HealthSyncCheck.allowed);
    });

    test('minorBindingAllowed does not bypass the ownership or binding '
        'checks — order of checks still matters', () {
      expect(
        canSyncProfile(
          profile: _profile(id: 'p1', isMinor: true),
          boundProfileId: 'p1',
          signedInUserId: 'caregiver-1',
          ownerUserId: 'owner-1',
          minorBindingAllowed: true,
        ),
        HealthSyncCheck.notOwner,
      );
      expect(
        canSyncProfile(
          profile: _profile(id: 'p2', isMinor: true),
          boundProfileId: 'p1',
          signedInUserId: 'u1',
          ownerUserId: 'u1',
          minorBindingAllowed: true,
        ),
        HealthSyncCheck.profileNotBound,
      );
    });

    test('defaults to minorBindingAllowed: false when omitted', () {
      final result = canSyncProfile(
        profile: _profile(id: 'p1', isMinor: true),
        boundProfileId: 'p1',
        signedInUserId: 'u1',
        ownerUserId: 'u1',
      );
      expect(result, HealthSyncCheck.minorRequiresTransfer);
    });
  });

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
  });
}
