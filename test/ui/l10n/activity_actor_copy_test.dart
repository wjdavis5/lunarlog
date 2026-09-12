/// Unit tests for [activityActorLabel] (Issue #545, moved out of
/// `lib/domain/activity/activity_feed.dart`, which hardcoded English copy
/// directly in the domain layer).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/activity_actor_copy.dart';

final _l10n = AppLocalizationsEn();

ProfileGuardian _guardian(
  String userId, {
  String? displayName,
  GuardianRole role = GuardianRole.coParent,
  GuardianStatus status = GuardianStatus.accepted,
}) =>
    ProfileGuardian(
      id: 'g-$userId',
      profileId: 'p1',
      userId: userId,
      role: role,
      status: status,
      displayName: displayName,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('activityActorLabel', () {
    final guardians = [
      _guardian('u1', displayName: 'Mom'),
      _guardian('u2'), // no display name -> role label
      _guardian('u3', displayName: ''), // empty display name -> role label
    ];

    test('null id stays null; never an invented actor', () {
      expect(activityActorLabel(_l10n, null, 'me', guardians), isNull);
    });

    test('current user reads as "you"', () {
      expect(activityActorLabel(_l10n, 'me', 'me', guardians), 'you');
      expect(activityActorLabel(_l10n, 'me', 'me', const []), 'you');
    });

    test('display name, then role label, then "a guardian", never a uuid',
        () {
      expect(activityActorLabel(_l10n, 'u1', 'me', guardians), 'Mom');
      expect(activityActorLabel(_l10n, 'u2', 'me', guardians), 'Co-Parent');
      expect(activityActorLabel(_l10n, 'u3', 'me', guardians), 'Co-Parent');
      expect(activityActorLabel(_l10n, 'unknown-uuid', 'me', guardians),
          'a guardian');
      expect(activityActorLabel(_l10n, 'unknown-uuid', 'me', const []),
          'a guardian');
    });

    test('a revoked guardian still resolves by name (historical rows)', () {
      final revoked = [
        _guardian('ex', displayName: 'Ex', status: GuardianStatus.revoked),
      ];
      expect(activityActorLabel(_l10n, 'ex', 'me', revoked), 'Ex');
    });
  });
}
