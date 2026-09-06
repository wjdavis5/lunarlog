/// Unit tests for `AuthService`'s `ConfirmedIdentity` extension (issue #77):
/// the shared "which session states count as an authenticated identity"
/// rule consumed by `SupabaseSyncEngine` and `RealtimeSyncCoordinator`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

import '../../support/fake_auth_service.dart';

void main() {
  group('AuthService.confirmedUserId', () {
    late FakeAuthService auth;

    setUp(() => auth = FakeAuthService());
    tearDown(() => auth.dispose());

    test('signedOut (the default) is not confirmed', () {
      expect(auth.state, AuthSessionState.signedOut);
      expect(auth.confirmedUserId, isNull);
    });

    test('signedIn returns the current user id', () {
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      expect(auth.confirmedUserId, 'u1');
    });

    test('passwordRecovery carries a user but is not confirmed', () {
      auth.latchRecovery(user: const AuthUser(id: 'u1'));
      expect(auth.currentUser, isNotNull,
          reason: 'a recovery session does carry a user');
      expect(auth.confirmedUserId, isNull,
          reason: 'a recovery session must not bind sync/realtime identity');
    });

    test('expired is not confirmed even if a stale user id lingers', () {
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      auth.emit(AuthSessionState.expired);
      expect(auth.confirmedUserId, isNull);
    });
  });

  group('Passkey cancellation results (#30 U2)', () {
    test('PasskeySignInCancelled is value-equal to a fresh instance', () {
      expect(const PasskeySignInCancelled(), const PasskeySignInCancelled());
      expect(const PasskeySignInCancelled().hashCode,
          const PasskeySignInCancelled().hashCode);
    });

    test('PasskeySignInCancelled.toString carries no provider detail', () {
      expect(
          const PasskeySignInCancelled().toString(), 'PasskeySignInCancelled');
    });

    test('PasskeyRegistrationCancelled is value-equal to a fresh instance',
        () {
      expect(const PasskeyRegistrationCancelled(),
          const PasskeyRegistrationCancelled());
      expect(const PasskeyRegistrationCancelled().hashCode,
          const PasskeyRegistrationCancelled().hashCode);
    });

    test('PasskeyRegistrationCancelled.toString carries no provider detail',
        () {
      expect(const PasskeyRegistrationCancelled().toString(),
          'PasskeyRegistrationCancelled');
    });
  });

  group('AuthFailure subtypes (#30 U2)', () {
    test('every reachable subtype is one of the known fieldless kinds', () {
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
        // Exhaustive switch over the sealed hierarchy: fails to *compile*
        // if a new AuthFailure subtype is ever added without being listed
        // here, which is exactly the guard KTD4 asks for — no passkey path
        // may introduce an unenumerated, potentially field-carrying kind.
        switch (failure) {
          case AuthWrongPasswordFailure():
          case AuthWeakPasswordFailure():
          case AuthNetworkFailure():
          case AuthUnknownFailure():
          case AuthExpiredLinkFailure():
          case AuthInvalidCodeFailure():
          case AuthProviderUnavailableFailure():
          case AuthIdentityTakenFailure():
          case AuthSignUpClosedFailure():
          case AuthLastSignInMethodFailure():
        }
      }
      expect(failures.length, 10);
    });
  });

  group('FakeAuthService passkey outcomes (#30 U2)', () {
    test('signInWithPasskey returns the configured session', () async {
      final auth = FakeAuthService()
        ..passkeySignInResult =
            const PasskeySignInSession(AuthUser(id: 'user-passkey'));
      addTearDown(auth.dispose);

      final result = await auth.signInWithPasskey();

      expect(result, isA<PasskeySignInSession>());
      expect(auth.state, AuthSessionState.signedIn);
      expect(auth.passkeySignInCalls, 1);
    });

    test('signInWithPasskey returns cancellation without signing in',
        () async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      final result = await auth.signInWithPasskey();

      expect(result, const PasskeySignInCancelled());
      expect(auth.state, AuthSessionState.signedOut);
    });

    test('registerPasskey throws before touching the platform when signed out',
        () async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);

      await expectLater(
          auth.registerPasskey(), throwsA(isA<AuthUnknownFailure>()));
      expect(auth.registerPasskeyCalls, 0);
    });

    test('registerPasskey returns the configured outcome once signed in',
        () async {
      final auth =
          FakeAuthService(initialState: AuthSessionState.signedIn)
            ..passkeyRegistrationResult = const PasskeyRegistrationSuccess(
                AuthUser(id: 'user-passkey'));
      addTearDown(auth.dispose);

      final result = await auth.registerPasskey();

      expect(result, isA<PasskeyRegistrationSuccess>());
      expect(auth.registerPasskeyCalls, 1);
    });

    test('registerPasskey throws UnsupportedError when unavailable', () async {
      final auth = FakeAuthService(initialState: AuthSessionState.signedIn)
        ..passkeyUnsupported = true;
      addTearDown(auth.dispose);

      await expectLater(
          auth.registerPasskey(), throwsA(isA<UnsupportedError>()));
    });
  });
}
