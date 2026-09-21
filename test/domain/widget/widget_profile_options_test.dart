/// Unit tests for the widget's profile-eligibility rule (issue #141):
/// archived profiles never appear, a **known viewer** never gets the
/// quick-log affordance, and an *unknown* role fails open exactly like
/// every other write surface in the app (acceptedGuardianFor's
/// null-vs-empty discipline).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/widget/widget_profile_options.dart';

Profile _profile(String id, {DateTime? archivedAt}) => Profile(
      id: id,
      displayName: 'Profile $id',
      isMinor: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      archivedAt: archivedAt,
    );

ProfileGuardian _guardian(
  String userId,
  GuardianRole role, {
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: 'g-$userId-$role',
      profileId: 'p1',
      userId: userId,
      role: role,
      status: status,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('canQuickLogFor (the write-time rule)', () {
    test('a known viewer is excluded', () {
      expect(
        canQuickLogFor(
          guardians: [_guardian('me', GuardianRole.viewer)],
          currentUserId: 'me',
        ),
        isFalse,
      );
    });

    test('every non-viewer accepted role passes', () {
      for (final role in [
        GuardianRole.primaryGuardian,
        GuardianRole.coParent,
        GuardianRole.caregiver,
      ]) {
        expect(
          canQuickLogFor(
            guardians: [_guardian('me', role)],
            currentUserId: 'me',
          ),
          isTrue,
          reason: role.name,
        );
      }
    });

    test('an unknown role fails open (no rows, no signed-in operator)',
        () {
      expect(
        canQuickLogFor(guardians: const [], currentUserId: null),
        isTrue,
        reason: 'local-only operators have no guardian rows at all',
      );
      expect(
        canQuickLogFor(
          guardians: [_guardian('someone-else', GuardianRole.viewer)],
          currentUserId: 'me',
        ),
        isTrue,
        reason:
            'a not-yet-synced membership is unknown, not known read-only',
      );
    });

    test('a pending or revoked membership is unknown, not viewer', () {
      expect(
        canQuickLogFor(
          guardians: [
            _guardian('me', GuardianRole.viewer, status: GuardianStatus.pending)
          ],
          currentUserId: 'me',
        ),
        isTrue,
      );
    });
  });

  group('widgetProfileOptions (the Settings picker rule)', () {
    // The picker calls the derivation once per profile (each profile has
    // its own guardian rows), which is exactly what these cases model.
    WidgetProfileOption optionFor({
      required List<ProfileGuardian> guardians,
      DateTime? archivedAt,
    }) =>
        widgetProfileOptions(
          profiles: [_profile('p1', archivedAt: archivedAt)],
          guardiansForProfile: guardians,
          currentUserId: 'me',
        ).single;

    test('archived profiles never appear at all', () {
      expect(
        widgetProfileOptions(
          profiles: [
            _profile('live'),
            _profile('archived', archivedAt: DateTime(2026, 9, 1)),
          ],
          guardiansForProfile: const [],
          currentUserId: 'me',
        ).map((o) => o.profileId),
        ['live'],
      );
    });

    test('a viewer-role profile is offered without quick-log', () {
      expect(
        optionFor(guardians: [_guardian('me', GuardianRole.viewer)])
            .canQuickLog,
        isFalse,
      );
    });

    test('a loggable profile is offered with quick-log', () {
      expect(
        optionFor(guardians: [_guardian('me', GuardianRole.caregiver)])
            .canQuickLog,
        isTrue,
      );
    });

    test('equality follows every field', () {
      const option = WidgetProfileOption(
        profileId: 'p1',
        profileName: 'Alice',
        canQuickLog: true,
      );
      expect(option, option);
      expect(
        option,
        const WidgetProfileOption(
          profileId: 'p1',
          profileName: 'Alice',
          canQuickLog: true,
        ),
      );
      expect(option.hashCode,
          const WidgetProfileOption(
            profileId: 'p1',
            profileName: 'Alice',
            canQuickLog: true,
          ).hashCode);
      for (final different in [
        const WidgetProfileOption(
          profileId: 'p2',
          profileName: 'Alice',
          canQuickLog: true,
        ),
        const WidgetProfileOption(
          profileId: 'p1',
          profileName: 'Beth',
          canQuickLog: true,
        ),
        const WidgetProfileOption(
          profileId: 'p1',
          profileName: 'Alice',
          canQuickLog: false,
        ),
      ]) {
        expect(option == different, isFalse);
      }
      expect(option, isNot(Object()));
    });

    test('carries the display name for the picker only', () {
      expect(optionFor(guardians: const []).profileName, 'Profile p1');
    });
  });
}
