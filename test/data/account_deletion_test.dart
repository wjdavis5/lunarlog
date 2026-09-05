/// U1 (R14): account deletion runs online with confirmation, cascades the
/// server rows, revokes the Apple token on a best-effort basis, and resets
/// the device to first-run. Offline deletion refuses and removes nothing;
/// an email-only account skips Apple revocation cleanly.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/account/account_deletion.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

void main() {
  group('AccountDeletionService', () {
    test('success cascades server rows, revokes Apple, then resets device',
        () async {
      final calls = <String>[];
      final service = AccountDeletionService(
        deleteServerData: () async => calls.add('server'),
        revokeAppleToken: () async => calls.add('revoke'),
        resetDevice: () async => calls.add('reset'),
      );
      await service.deleteAccount(
        signedIn: true,
        providers: const [AuthProviders.email, AuthProviders.apple],
      );
      expect(calls, ['server', 'revoke', 'reset']);
    });

    test('email-only account skips Apple revocation cleanly', () async {
      var revoked = false;
      final service = AccountDeletionService(
        deleteServerData: () async {},
        revokeAppleToken: () async => revoked = true,
        resetDevice: () async {},
      );
      await service.deleteAccount(
        signedIn: true,
        providers: const [AuthProviders.email],
      );
      expect(revoked, isFalse);
    });

    test('a failing Apple revocation still resets the device', () async {
      var reset = false;
      final service = AccountDeletionService(
        deleteServerData: () async {},
        revokeAppleToken: () async => throw Exception('revoke failed'),
        resetDevice: () async => reset = true,
      );
      await service.deleteAccount(
        signedIn: true,
        providers: const [AuthProviders.apple],
      );
      expect(reset, isTrue);
    });

    test('offline deletion refuses and removes nothing', () async {
      var revoked = false;
      var reset = false;
      final service = AccountDeletionService(
        deleteServerData: () async =>
            throw const AccountDeletionError.offline(),
        revokeAppleToken: () async => revoked = true,
        resetDevice: () async => reset = true,
      );
      await expectLater(
        service.deleteAccount(
          signedIn: true,
          providers: const [AuthProviders.apple],
        ),
        throwsA(const AccountDeletionError.offline()),
      );
      expect(revoked, isFalse, reason: 'no revocation attempt while offline');
      expect(reset, isFalse, reason: 'no local reset while offline');
    });

    test('a server failure resets nothing', () async {
      var reset = false;
      final service = AccountDeletionService(
        deleteServerData: () async =>
            throw const AccountDeletionError.server(),
        revokeAppleToken: () async {},
        resetDevice: () async => reset = true,
      );
      await expectLater(
        service.deleteAccount(signedIn: true, providers: const []),
        throwsA(const AccountDeletionError.server()),
      );
      expect(reset, isFalse);
    });

    test('deletion while signed out refuses without a server call', () async {
      var serverCalled = false;
      final service = AccountDeletionService(
        deleteServerData: () async => serverCalled = true,
        revokeAppleToken: () async {},
        resetDevice: () async {},
      );
      await expectLater(
        service.deleteAccount(signedIn: false, providers: const []),
        throwsA(const AccountDeletionError.notSignedIn()),
      );
      expect(serverCalled, isFalse);
    });

    test('failures carry kinds only, never content', () {
      expect('${const AccountDeletionError.offline()}',
          'AccountDeletionError.offline');
      expect('${const AccountDeletionError.server()}',
          'AccountDeletionError.server');
      expect('${const AccountDeletionError.notSignedIn()}',
          'AccountDeletionError.notSignedIn');
    });
  });
}
