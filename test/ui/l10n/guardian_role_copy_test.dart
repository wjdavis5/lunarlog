/// Unit tests for the Issue #545 [GuardianRole] copy mappers:
/// [guardianRoleLabel], [guardianRoleReadOnlyReason], and
/// [sharingProfileRoleSubtitle] (moved from
/// `SharingProfileInfo.roleSubtitle` in
/// `lib/domain/sharing/sharing_overview.dart`, pinned here now that it
/// renders localized copy instead of a domain-layer literal).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/guardian_role_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  group('guardianRoleLabel', () {
    test('every role maps to its ARB-backed English label', () {
      expect(guardianRoleLabel(_l10n, GuardianRole.primaryGuardian),
          'Primary Guardian');
      expect(guardianRoleLabel(_l10n, GuardianRole.coParent), 'Co-Parent');
      expect(guardianRoleLabel(_l10n, GuardianRole.caregiver), 'Caregiver');
      expect(guardianRoleLabel(_l10n, GuardianRole.viewer), 'Viewer');
    });
  });

  group('guardianRoleReadOnlyReason', () {
    test('only the viewer role has a reason', () {
      expect(guardianRoleReadOnlyReason(_l10n, GuardianRole.viewer),
          'You have view-only access to this profile.');
      expect(guardianRoleReadOnlyReason(_l10n, GuardianRole.primaryGuardian),
          isNull);
      expect(guardianRoleReadOnlyReason(_l10n, GuardianRole.coParent), isNull);
      expect(
          guardianRoleReadOnlyReason(_l10n, GuardianRole.caregiver), isNull);
    });
  });

  group('sharingProfileRoleSubtitle', () {
    test('shared profiles name the group and the role', () {
      expect(
          sharingProfileRoleSubtitle(
              _l10n,
              const SharingProfileInfo(
                  myRole: GuardianRole.coParent, acceptedCount: 2)),
          'Shared with me · Co-Parent');
      expect(
          sharingProfileRoleSubtitle(
              _l10n,
              const SharingProfileInfo(
                  myRole: GuardianRole.viewer, acceptedCount: 2)),
          'Shared with me · Viewer');
    });

    test('owned profiles name the role only when known', () {
      expect(
          sharingProfileRoleSubtitle(
              _l10n,
              const SharingProfileInfo(
                  myRole: GuardianRole.primaryGuardian, acceptedCount: 2)),
          'Primary Guardian');
      expect(
          sharingProfileRoleSubtitle(_l10n, const SharingProfileInfo.unknown()),
          isNull);
    });
  });
}
