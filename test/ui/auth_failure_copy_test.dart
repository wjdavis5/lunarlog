/// `authFailureCopy` (#2 U2; KTD4, R14): every [AuthFailure] kind has
/// generic copy that names no email, no provider error text, and no token;
/// the exhaustive switch is the contract that a new failure cannot ship
/// without copy.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/auth_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  test('the new failure kinds carry the pinned copy', () {
    expect(
      authFailureCopy(_l10n, const AuthFailure.providerUnavailable()),
      "That sign-in method isn't available on this device. Use email "
          'instead.',
    );
    expect(authFailureCopy(_l10n, const AuthFailure.expiredLink()),
        'That sign-in link is no longer valid. Request a new one.');
    expect(authFailureCopy(_l10n, const AuthFailure.invalidCode()),
        'That code was not accepted. Check it or request a new email.');
    expect(authFailureCopy(_l10n, const AuthFailure.identityTaken()),
        'That sign-in method already belongs to another account.');
    expect(authFailureCopy(_l10n, const AuthFailure.signUpClosed()),
        'New accounts for this app are set up by the account owner.');
    expect(
      authFailureCopy(_l10n, const AuthFailure.lastSignInMethod()),
      'That is the only way left to sign in to this account. Add '
          'another method first.',
    );
    expect(
      authFailureCopy(_l10n, const AuthFailure.rateLimited()),
      'Too many attempts. Wait a little while, then try again.',
    );
    expect(
      authFailureCopy(_l10n, const AuthFailure.misconfigured()),
      'That sign-in method is not set up for this app right now. Try '
          'another way to sign in.',
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
      AuthFailure.rateLimited(),
      AuthFailure.misconfigured(),
    ];
    for (final failure in failures) {
      final copy = authFailureCopy(_l10n, failure);
      expect(copy, isNotEmpty);
      expect(copy, isNot(contains('@')));
      expect(copy.toLowerCase(), isNot(contains('token')));
      expect(copy.toLowerCase(), isNot(contains('exception')));
    }
  });

  test(
      'providerUnavailable copy names no provider (#30 U4; R5) — it now '
      'also covers a passkey ceremony that could not run', () {
    final copy = authFailureCopy(_l10n, const AuthFailure.providerUnavailable());
    expect(copy.toLowerCase(), isNot(contains('google')));
    expect(copy.toLowerCase(), isNot(contains('apple')));
    expect(copy.toLowerCase(), isNot(contains('passkey')));
  });
}
