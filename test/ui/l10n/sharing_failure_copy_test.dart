/// Unit tests for [sharingFailureCopy] and [inviteCancellationCopy] (Issue
/// #545, moved out of `lib/domain/sharing/sharing_service.dart`'s
/// `userFacingMessage` getters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/sharing_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  group('inviteCancellationCopy', () {
    test('every outcome has non-empty, pinned copy', () {
      expect(inviteCancellationCopy(_l10n, InviteCancellation.revoked),
          'Invitation cancelled');
      expect(
          inviteCancellationCopy(_l10n, InviteCancellation.alreadyAccepted),
          'That invitation was already accepted');
      expect(inviteCancellationCopy(_l10n, InviteCancellation.alreadyRevoked),
          'That invitation was already cancelled');
      expect(inviteCancellationCopy(_l10n, InviteCancellation.expired),
          'That invitation had already expired');
    });
  });

  group('sharingFailureCopy', () {
    const allFailures = <SharingFailure>[
      SharingFailure.network(),
      SharingFailure.notFound(),
      SharingFailure.expired(),
      SharingFailure.alreadyAccepted(),
      SharingFailure.alreadyGuardian(),
      SharingFailure.unauthorized(),
      SharingFailure.notSignedIn(),
      SharingFailure.invalidToken(),
      SharingFailure.other(),
    ];

    test('every case has non-empty copy', () {
      for (final failure in allFailures) {
        expect(sharingFailureCopy(_l10n, failure), isNotEmpty,
            reason: '${failure.runtimeType} has empty copy');
      }
    });

    test('network and unauthorized copy is never a raw provider message', () {
      expect(sharingFailureCopy(_l10n, const SharingFailure.network()),
          'Network error. Please check your connection.');
      expect(sharingFailureCopy(_l10n, const SharingFailure.unauthorized()),
          'You do not have permission for this action.');
    });

    test('a no-session refusal gets its own copy, not the permission one '
        '(issue #885)', () {
      expect(
        sharingFailureCopy(_l10n, const SharingFailure.notSignedIn()),
        'Sign in to your account to manage sharing.',
      );
      expect(
        sharingFailureCopy(_l10n, const SharingFailure.notSignedIn()),
        isNot(sharingFailureCopy(_l10n, const SharingFailure.unauthorized())),
      );
    });
  });
}
