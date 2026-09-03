/// U4: [AuthController] over the domain [AuthService] (KTD6) — mirrors the
/// service's state stream, exposes the recovery latch that the service set
/// before any widget existed (KTD8), and notifies once per change.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';

import '../support/fake_auth_service.dart';

void main() {
  late FakeAuthService service;

  setUp(() => service = FakeAuthService());
  tearDown(() => service.dispose());

  AuthController controller() {
    final c = AuthController(authService: service);
    addTearDown(c.dispose);
    return c;
  }

  test('starts from the service\'s current state', () {
    service.emit(AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'));
    final c = controller();
    expect(c.state, AuthSessionState.signedIn);
    expect(c.currentUserId, 'u1');
    expect(c.currentUser?.email, 'a@b.c');
    expect(c.signedIn, isTrue);
  });

  test('reflects signedOut → signedIn → expired and notifies once per change',
      () async {
    final c = controller();
    var notifications = 0;
    c.addListener(() => notifications++);
    expect(c.state, AuthSessionState.signedOut);

    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await Future<void>.delayed(Duration.zero);
    expect(c.state, AuthSessionState.signedIn);
    expect(c.currentUserId, 'u1');
    expect(notifications, 1);

    // A repeated identical state (e.g. a token refresh) is not a change.
    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);

    service.emit(AuthSessionState.expired);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, AuthSessionState.expired);
    expect(c.currentUserId, isNull);
    expect(c.signedIn, isFalse);
    expect(notifications, 2);

    service.emit(AuthSessionState.signedOut);
    await Future<void>.delayed(Duration.zero);
    expect(c.state, AuthSessionState.signedOut);
    expect(notifications, 3);
  });

  test('a recovery latched before the controller subscribes is visible on '
      'first read; consumeRecovery clears it', () async {
    service.latchRecovery();
    final c = controller();
    expect(c.pendingRecovery, isTrue, reason: 'latched in the service');
    expect(c.state, AuthSessionState.passwordRecovery);

    var notifications = 0;
    c.addListener(() => notifications++);
    c.consumeRecovery();
    expect(c.pendingRecovery, isFalse);
    expect(service.recoveryConsumed, 1);
    expect(notifications, 1);

    // Consuming again is a no-op.
    c.consumeRecovery();
    expect(service.recoveryConsumed, 1);
    expect(notifications, 1);
  });

  test('a second recovery event before consumption does not double-notify',
      () async {
    final c = controller();
    var notifications = 0;
    c.addListener(() => notifications++);

    service.latchRecovery();
    await Future<void>.delayed(Duration.zero);
    expect(c.pendingRecovery, isTrue);
    expect(notifications, 1);

    service.latchRecovery();
    await Future<void>.delayed(Duration.zero);
    expect(c.pendingRecovery, isTrue);
    expect(notifications, 1);
  });

  test('link failures are surfaced as typed values and can be consumed',
      () async {
    final c = controller();
    var notifications = 0;
    c.addListener(() => notifications++);

    service.emitLinkFailure(const AuthFailure.unknown());
    await Future<void>.delayed(Duration.zero);
    expect(c.pendingLinkFailure, isA<AuthUnknownFailure>());
    expect(notifications, 1);

    c.consumeLinkFailure();
    expect(c.pendingLinkFailure, isNull);
    expect(service.linkFailureConsumed, 1);
    expect(notifications, 2);
  });

  test('a link failure latched before subscribing is visible on first read',
      () {
    service.pendingLinkFailure = const AuthFailure.network();
    final c = controller();
    expect(c.pendingLinkFailure, isA<AuthNetworkFailure>());
  });

  test('delegates passwordless send and verify to the service (#2 U7)',
      () async {
    final c = controller();
    await c.sendMagicLink(email: 'a@b.c', createAccount: false);
    await c.sendMagicLink(email: 'n@b.c', createAccount: true);
    expect(service.magicLinkCalls, [
      (email: 'a@b.c', createAccount: false),
      (email: 'n@b.c', createAccount: true),
    ]);
    expect(c.state, AuthSessionState.signedOut);

    final user = await c.verifyEmailCode(email: 'a@b.c', code: '12345678');
    await Future<void>.delayed(Duration.zero);
    expect(service.codeCalls, [(email: 'a@b.c', code: '12345678')]);
    expect(user.email, 'a@b.c');
    expect(c.state, AuthSessionState.signedIn);
    expect(c.currentUser, user);

    service.nextFailure = const AuthFailure.invalidCode();
    await expectLater(c.verifyEmailCode(email: 'a@b.c', code: '0'),
        throwsA(isA<AuthInvalidCodeFailure>()));
  });

  test('stops listening after dispose', () async {
    final c = AuthController(authService: service);
    var notifications = 0;
    c.addListener(() => notifications++);
    c.dispose();
    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 0);
  });
}
