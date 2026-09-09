import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';

ProfileGuardian _guardian(
  String userId,
  GuardianRole role, {
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: 'g-$userId-${role.name}',
      profileId: 'p-1',
      userId: userId,
      role: role,
      status: status,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('SharingProfileInfo.group', () {
    test('unknown role reads as owned (fail open, never shared)', () {
      expect(const SharingProfileInfo.unknown().group,
          ProfileSharingGroup.owned);
    });

    test('primary guardian reads as owned', () {
      const info = SharingProfileInfo(
          myRole: GuardianRole.primaryGuardian, acceptedCount: 1);
      expect(info.group, ProfileSharingGroup.owned);
    });

    test('co-parent, caregiver, and viewer read as shared with me', () {
      for (final role in [
        GuardianRole.coParent,
        GuardianRole.caregiver,
        GuardianRole.viewer,
      ]) {
        final info = SharingProfileInfo(myRole: role, acceptedCount: 2);
        expect(info.group, ProfileSharingGroup.sharedWithMe,
            reason: 'role $role');
      }
    });
  });

  group('SharingProfileInfo.isCoManaged', () {
    test('zero or one accepted guardian is not co-managed', () {
      expect(
          const SharingProfileInfo(myRole: null, acceptedCount: 0).isCoManaged,
          isFalse);
      expect(
          const SharingProfileInfo(
                  myRole: GuardianRole.primaryGuardian, acceptedCount: 1)
              .isCoManaged,
          isFalse);
    });

    test('two accepted guardians is co-managed', () {
      expect(
          const SharingProfileInfo(
                  myRole: GuardianRole.primaryGuardian, acceptedCount: 2)
              .isCoManaged,
          isTrue);
    });
  });

  group('SharingProfileInfo.fromGuardians', () {
    test('resolves my role and counts only accepted rows', () {
      final info = SharingProfileInfo.fromGuardians(
        [
          _guardian('u-mom', GuardianRole.primaryGuardian),
          _guardian('u-dad', GuardianRole.coParent),
          _guardian('u-pending', GuardianRole.caregiver,
              status: GuardianStatus.pending),
          _guardian('u-revoked', GuardianRole.viewer,
              status: GuardianStatus.revoked),
        ],
        'u-dad',
      );
      expect(info.myRole, GuardianRole.coParent);
      expect(info.acceptedCount, 2);
      expect(info.group, ProfileSharingGroup.sharedWithMe);
      expect(info.isCoManaged, isTrue);
    });

    test('null user and unmatched user both resolve to unknown role', () {
      final rows = [_guardian('u-mom', GuardianRole.primaryGuardian)];
      expect(SharingProfileInfo.fromGuardians(rows, null).myRole, isNull);
      expect(
          SharingProfileInfo.fromGuardians(rows, 'u-stranger').myRole, isNull);
    });

    test('empty rows resolve to unknown with zero guardians', () {
      final info = SharingProfileInfo.fromGuardians(const [], 'u-mom');
      expect(info.myRole, isNull);
      expect(info.acceptedCount, 0);
      expect(info.group, ProfileSharingGroup.owned);
    });
  });

  group('SharingProfileInfo.canShowPendingBadge', () {
    test('unknown caller may see the badge (pre-sync discipline)', () {
      expect(SharingProfileInfo.canShowPendingBadge(null), isTrue);
    });

    test('managers may see the badge', () {
      expect(
          SharingProfileInfo.canShowPendingBadge(
              GuardianRole.primaryGuardian),
          isTrue);
      expect(SharingProfileInfo.canShowPendingBadge(GuardianRole.coParent),
          isTrue);
    });

    test('caregiver and viewer never get a badge fetch', () {
      expect(SharingProfileInfo.canShowPendingBadge(GuardianRole.caregiver),
          isFalse);
      expect(SharingProfileInfo.canShowPendingBadge(GuardianRole.viewer),
          isFalse);
    });
  });

  group('SharingProfileInfo.roleSubtitle', () {
    test('shared profiles name the group and the role', () {
      expect(
          SharingProfileInfo.roleSubtitle(const SharingProfileInfo(
              myRole: GuardianRole.coParent, acceptedCount: 2)),
          'Shared with me · Co-Parent');
      expect(
          SharingProfileInfo.roleSubtitle(const SharingProfileInfo(
              myRole: GuardianRole.viewer, acceptedCount: 2)),
          'Shared with me · Viewer');
    });

    test('owned profiles name the role only when known', () {
      expect(
          SharingProfileInfo.roleSubtitle(const SharingProfileInfo(
              myRole: GuardianRole.primaryGuardian, acceptedCount: 2)),
          'Primary Guardian');
      expect(
          SharingProfileInfo.roleSubtitle(
              const SharingProfileInfo.unknown()),
          isNull);
    });
  });
}
