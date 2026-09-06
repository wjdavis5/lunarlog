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
}
