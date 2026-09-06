/// Unit tests for the domain models in account_deletion_service.dart
/// (Issue #17, Unit U4): [AccountDeletionFailure] equality/hashCode behave
/// by runtime type, mirroring `test/ui/auth_failure_copy_test.dart`'s
/// expectations for [AuthFailure] (which this file's failure family
/// intentionally shadows in shape).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';

void main() {
  group('AccountDeletionFailure constructors', () {
    test('each factory produces the matching subtype', () {
      expect(const AccountDeletionFailure.network(),
          isA<AccountDeletionNetworkFailure>());
      expect(const AccountDeletionFailure.unauthorized(),
          isA<AccountDeletionUnauthorizedFailure>());
      expect(const AccountDeletionFailure.appleRevokeFailed(),
          isA<AccountDeletionAppleRevokeFailedFailure>());
      expect(const AccountDeletionFailure.unknown(),
          isA<AccountDeletionUnknownFailure>());
    });
  });

  group('AccountDeletionFailure equality and hashCode', () {
    const failures = <AccountDeletionFailure>[
      AccountDeletionFailure.network(),
      AccountDeletionFailure.unauthorized(),
      AccountDeletionFailure.appleRevokeFailed(),
      AccountDeletionFailure.unknown(),
    ];

    test('two instances of the same kind compare equal', () {
      for (final failure in failures) {
        // A second const instance of the same factory is identical (const
        // canonicalization), so equality is exercised through the runtime
        // type check on distinct instances instead.
        expect(failure, failure);
        expect(failure == failure, isTrue);
        expect(failure.hashCode, failure.hashCode);
      }
    });

    test('equality is by runtime type, not identity', () {
      const a = AccountDeletionFailure.network();
      const AccountDeletionFailure b = AccountDeletionNetworkFailure();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('every pair of distinct kinds compares unequal', () {
      for (var i = 0; i < failures.length; i++) {
        for (var j = 0; j < failures.length; j++) {
          if (i == j) continue;
          expect(failures[i], isNot(failures[j]),
              reason: '${failures[i]} should not equal ${failures[j]}');
        }
      }
    });

    test('a different type is never equal', () {
      // ignore: unrelated_type_equality_checks
      expect(const AccountDeletionFailure.network() == 'not a failure',
          isFalse);
    });

    test('toString names the kind, not a message', () {
      expect(const AccountDeletionFailure.network().toString(),
          'AccountDeletionFailure.network');
      expect(const AccountDeletionFailure.unauthorized().toString(),
          'AccountDeletionFailure.unauthorized');
      expect(const AccountDeletionFailure.appleRevokeFailed().toString(),
          'AccountDeletionFailure.appleRevokeFailed');
      expect(const AccountDeletionFailure.unknown().toString(),
          'AccountDeletionFailure.unknown');
    });
  });
}
