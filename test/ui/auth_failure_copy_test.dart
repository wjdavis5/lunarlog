/// `authFailureCopy` (#2 U2; KTD4, R14): every [AuthFailure] kind has
/// generic copy that names no email, no provider error text, and no token;
/// the exhaustive switch is the contract that a new failure cannot ship
/// without copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';

void main() {
  test('the new failure kinds carry the pinned copy', () {
    expect(
      authFailureCopy(const AuthFailure.providerUnavailable()),
      "That sign-in method isn't available on this device. Use email "
          'instead.',
    );
    expect(authFailureCopy(const AuthFailure.expiredLink()),
        'That sign-in link is no longer valid. Request a new one.');
    expect(authFailureCopy(const AuthFailure.invalidCode()),
        'That code was not accepted. Check it or request a new email.');
    expect(authFailureCopy(const AuthFailure.identityTaken()),
        'That sign-in method already belongs to another account.');
    expect(authFailureCopy(const AuthFailure.signUpClosed()),
        'New accounts for this app are set up by the account owner.');
    expect(
      authFailureCopy(const AuthFailure.lastSignInMethod()),
      'That is the only way left to sign in to this account. Add '
          'another method first.',
    );
  });

  test('every kind has non-empty, email-free copy', () {
    const failures = <AuthFailure>[
      AuthFailure.wrongPassword(),
      AuthFailure.weakPassword(),
      AuthFailure.network(),
      AuthFailure.unknown(),
      AuthFailure.expiredLink(),
      AuthFailure.invalidCode(),
      AuthFailure.providerUnavailable(),
      AuthFailure.identityTaken(),
      AuthFailure.signUpClosed(),
      AuthFailure.lastSignInMethod(),
    ];
    for (final failure in failures) {
      final copy = authFailureCopy(failure);
      expect(copy, isNotEmpty);
      expect(copy, isNot(contains('@')));
      expect(copy.toLowerCase(), isNot(contains('token')));
      expect(copy.toLowerCase(), isNot(contains('exception')));
    }
  });

  test(
      'providerUnavailable copy names no provider (#30 U4; R5) — it now '
      'also covers a passkey ceremony that could not run', () {
    final copy = authFailureCopy(const AuthFailure.providerUnavailable());
    expect(copy.toLowerCase(), isNot(contains('google')));
    expect(copy.toLowerCase(), isNot(contains('apple')));
    expect(copy.toLowerCase(), isNot(contains('passkey')));
  });
}
