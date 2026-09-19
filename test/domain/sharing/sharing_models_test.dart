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

  group('InvitePreview equality and hashCode (Issue #594)', () {
    final expiresAt = DateTime.utc(2026, 9, 20);
    final preview1 = InvitePreview(
      profileDisplayName: 'Riley',
      role: GuardianRole.caregiver,
      expiresAt: expiresAt,
    );
    final preview2 = InvitePreview(
      profileDisplayName: 'Riley',
      role: GuardianRole.caregiver,
      expiresAt: expiresAt,
    );

    test('identical and equal instances compare equal', () {
      expect(preview1, preview1);
      expect(preview1, preview2);
      expect(preview1.hashCode, preview2.hashCode);
    });

    test('differing fields compare unequal', () {
      expect(
        preview1,
        isNot(InvitePreview(
          profileDisplayName: 'Someone Else',
          role: GuardianRole.caregiver,
          expiresAt: expiresAt,
        )),
      );
      expect(
        preview1,
        isNot(InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.viewer,
          expiresAt: expiresAt,
        )),
      );
      expect(
        preview1,
        isNot(InvitePreview(
          profileDisplayName: 'Riley',
          role: GuardianRole.caregiver,
          expiresAt: expiresAt.add(const Duration(hours: 1)),
        )),
      );
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(preview1 == 'not a preview', isFalse);
    });
  });

  group('PendingInvite equality and hashCode', () {
    final now = DateTime.utc(2026, 9, 6);
    final expires = DateTime.utc(2026, 9, 8);
    PendingInvite invite({String recipientLabel = 'Grandma'}) => PendingInvite(
          invitationId: 'inv-1',
          profileId: 'p-1',
          role: GuardianRole.viewer,
          recipientLabel: recipientLabel,
          createdAt: now,
          expiresAt: expires,
        );

    test('identical and equal instances compare equal', () {
      expect(invite(), invite());
      expect(invite().hashCode, invite().hashCode);
    });

    test('differing fields compare unequal', () {
      expect(invite(), isNot(invite(recipientLabel: 'Grandpa')));
      expect(
        invite(),
        isNot(PendingInvite(
          invitationId: 'inv-2',
          profileId: 'p-1',
          role: GuardianRole.viewer,
          recipientLabel: 'Grandma',
          createdAt: now,
          expiresAt: expires,
        )),
      );
    });

    test('different type is not equal', () {
      // ignore: unrelated_type_equality_checks
      expect(invite() == 'not an invite', isFalse);
    });

    test('isExpiredAt derives from expiresAt vs the supplied clock reading', () {
      // Issue #304: `isExpired` (a getter reading `DateTime.now()` itself)
      // became `isExpiredAt(DateTime now)` so `lib/domain` never reads the
      // wall clock -- this test pins its own reference instant instead of
      // racing the real one.
      final reference = DateTime.utc(2026, 1, 2, 12);
      PendingInvite withExpiry(DateTime expiresAt) => PendingInvite(
            invitationId: 'inv-1',
            profileId: 'p-1',
            role: GuardianRole.viewer,
            recipientLabel: 'Grandma',
            createdAt: now,
            expiresAt: expiresAt,
          );
      expect(
        withExpiry(reference.add(const Duration(hours: 1)))
            .isExpiredAt(reference),
        isFalse,
      );
      expect(
        withExpiry(reference.subtract(const Duration(hours: 1)))
            .isExpiredAt(reference),
        isTrue,
      );
    });
  });

  group('InviteCancellation.fromDb', () {
    test('round-trips every known outcome', () {
      expect(InviteCancellation.fromDb('revoked'), InviteCancellation.revoked);
      expect(InviteCancellation.fromDb('already_revoked'), InviteCancellation.alreadyRevoked);
      expect(InviteCancellation.fromDb('already_accepted'), InviteCancellation.alreadyAccepted);
      expect(InviteCancellation.fromDb('expired'), InviteCancellation.expired);
    });

    test('an unknown value fails loudly rather than defaulting to success', () {
      expect(() => InviteCancellation.fromDb('unknown'), throwsArgumentError);
    });

    // Issue #545: InviteCancellation.userFacingMessage moved to
    // inviteCancellationCopy (lib/ui/l10n/sharing_failure_copy.dart) — the
    // domain type is fieldless data now. Copy coverage moved to
    // test/ui/l10n/sharing_failure_copy_test.dart.
  });

  group('SharingFailure types', () {
    test('constructors and message descriptions', () {
      expect(const SharingFailure.expired(), isA<SharingExpiredFailure>());
      expect(const SharingFailure.alreadyAccepted(), isA<SharingAlreadyAcceptedFailure>());
      expect(const SharingFailure.alreadyGuardian(), isA<SharingAlreadyGuardianFailure>());
      expect(const SharingFailure.notFound(), isA<SharingNotFoundFailure>());
      expect(const SharingFailure.invalidToken(), isA<SharingInvalidTokenFailure>());
      expect(const SharingFailure.unauthorized(), isA<SharingUnauthorizedFailure>());
      expect(const SharingFailure.notSignedIn(), isA<SharingNotSignedInFailure>());
      expect(const SharingFailure.network(), isA<SharingNetworkFailure>());
      expect(const SharingFailure.other(), isA<SharingOtherFailure>());
    });
  });
}
