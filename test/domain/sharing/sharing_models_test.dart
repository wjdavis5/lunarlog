/// Unit tests for domain models and value types in sharing_service.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/profile_guardian.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';

void main() {
  group('GeneratedInvite equality and hashCode', () {
    final now = DateTime.utc(2026, 9, 4);
    final invite1 = GeneratedInvite(
      invitationId: 'inv-1',
      profileId: 'p-1',
      role: GuardianRole.coParent,
      rawToken: 'token-raw',
      tokenHash: 'hash',
      inviteUri: Uri.parse('lunarlog://invite?code=123'),
      expiresAt: now,
    );
    final invite2 = GeneratedInvite(
      invitationId: 'inv-1',
      profileId: 'p-1',
      role: GuardianRole.coParent,
      rawToken: 'token-raw',
      tokenHash: 'hash',
      inviteUri: Uri.parse('lunarlog://invite?code=123'),
      expiresAt: now,
    );

    test('identical and equal instances compare equal', () {
      expect(invite1, invite1);
      expect(invite1, invite2);
      expect(invite1.hashCode, invite2.hashCode);
    });

    test('differing fields compare unequal', () {
      expect(
        invite1,
        isNot(GeneratedInvite(
          invitationId: 'inv-2',
          profileId: 'p-1',
          role: GuardianRole.coParent,
          rawToken: 'token-raw',
          tokenHash: 'hash',
          inviteUri: Uri.parse('lunarlog://invite?code=123'),
          expiresAt: now,
        )),
      );
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(invite1 == 'not an invite', isFalse);
    });
  });

  group('AcceptedInviteResult equality and hashCode', () {
    const res1 = AcceptedInviteResult(
      profileId: 'p-1',
      profileName: 'Luna',
      role: GuardianRole.coParent,
    );
    const res2 = AcceptedInviteResult(
      profileId: 'p-1',
      profileName: 'Luna',
      role: GuardianRole.coParent,
    );

    test('equal instances compare equal', () {
      expect(res1, res1);
      expect(res1, res2);
      expect(res1.hashCode, res2.hashCode);
    });

    test('differing fields compare unequal', () {
      expect(
        res1,
        isNot(const AcceptedInviteResult(
          profileId: 'p-2',
          profileName: 'Luna',
          role: GuardianRole.coParent,
        )),
      );
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(res1 == 'not a result', isFalse);
    });
  });

  group('SharingFailure types', () {
    test('constructors and message descriptions', () {
      expect(const SharingFailure.expired(), isA<SharingExpiredFailure>());
      expect(const SharingFailure.alreadyAccepted(), isA<SharingAlreadyAcceptedFailure>());
      expect(const SharingFailure.alreadyGuardian(), isA<SharingAlreadyGuardianFailure>());
      expect(const SharingFailure.notFound(), isA<SharingNotFoundFailure>());
      expect(const SharingFailure.invalidToken(), isA<SharingInvalidTokenFailure>());
      expect(const SharingFailure.unauthorized(), isA<SharingUnauthorizedFailure>());
      expect(const SharingFailure.network(), isA<SharingNetworkFailure>());
      expect(const SharingFailure.other(), isA<SharingOtherFailure>());
    });
  });
}
