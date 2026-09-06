/// U7 coordinator tests (R17-R19): register/refresh/remove against fakes.
/// Mirrors test/data/reminder_coordinator_test.dart's stream-fan-in shape.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/push_registration_coordinator.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/notifications/push_registration.dart';

import '../../support/fake_push_token_source.dart';

class _RegisterCall {
  _RegisterCall(this.deviceId, this.token, this.platform);
  final String deviceId;
  final String token;
  final String platform;
}

class _FakeRegistry implements PushDeviceRegistry {
  final List<_RegisterCall> registerCalls = [];
  final List<String> removeCalls = [];
  Object? nextRegisterError;
  Object? nextRemoveError;

  @override
  Future<void> register(String deviceId, String token, {required String platform}) async {
    final error = nextRegisterError;
    if (error != null) {
      nextRegisterError = null;
      throw error;
    }
    registerCalls.add(_RegisterCall(deviceId, token, platform));
  }

  @override
  Future<void> remove(String deviceId) async {
    final error = nextRemoveError;
    if (error != null) {
      nextRemoveError = null;
      throw error;
    }
    removeCalls.add(deviceId);
  }
}

void main() {
  const deviceId = 'device-1';
  const platform = 'ios';

  test('a signed-in start registers the current token exactly once with the right platform', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );

    await coordinator.start();

    expect(registry.registerCalls, hasLength(1));
    expect(registry.registerCalls.single.token, 'token-1');
    expect(registry.registerCalls.single.platform, platform);
    expect(registry.registerCalls.single.deviceId, deviceId);

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('a token refresh while signed in registers the new token; the previous row for this device is replaced, not duplicated', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );
    await coordinator.start();

    tokenSource.emitRefresh('token-2');
    await pumpEventQueue();

    expect(registry.registerCalls, hasLength(2));
    expect(registry.registerCalls[0].deviceId, deviceId);
    expect(registry.registerCalls[1].deviceId, deviceId,
        reason: 'the same device id on both calls is what makes the second an upsert-replace, not a new row');
    expect(registry.registerCalls[1].token, 'token-2');

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('sign-out deletes this device\'s registration and stops registering refreshes', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final authStates = StreamController<AuthSessionState>(sync: true);
    var current = AuthSessionState.signedIn;
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: authStates.stream,
      currentAuthState: () => current,
    );
    await coordinator.start();
    expect(registry.registerCalls, hasLength(1));

    current = AuthSessionState.signedOut;
    authStates.add(AuthSessionState.signedOut);
    await pumpEventQueue();

    expect(registry.removeCalls, [deviceId]);

    tokenSource.emitRefresh('token-2');
    await pumpEventQueue();
    expect(registry.registerCalls, hasLength(1), reason: 'no refresh registration while signed out');

    await coordinator.dispose();
    await authStates.close();
    await tokenSource.close();
  });

  test('a sign-in after a sign-out registers again', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final authStates = StreamController<AuthSessionState>(sync: true);
    var current = AuthSessionState.signedOut;
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: authStates.stream,
      currentAuthState: () => current,
    );
    await coordinator.start();
    expect(registry.registerCalls, isEmpty);

    current = AuthSessionState.signedIn;
    authStates.add(AuthSessionState.signedIn);
    await pumpEventQueue();

    expect(registry.registerCalls, hasLength(1));

    await coordinator.dispose();
    await authStates.close();
    await tokenSource.close();
  });

  test('a token-refresh event that arrives while signed out registers nothing', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedOut,
    );
    await coordinator.start();

    tokenSource.emitRefresh('token-2');
    await pumpEventQueue();

    expect(registry.registerCalls, isEmpty);

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('a registry failure is swallowed and does not cancel the auth subscription; a subsequent refresh still registers', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry()..nextRegisterError = Exception('boom');
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );
    await coordinator.start();
    expect(registry.registerCalls, isEmpty, reason: 'the first attempt threw');

    tokenSource.emitRefresh('token-2');
    await pumpEventQueue();

    expect(registry.registerCalls, hasLength(1));
    expect(registry.registerCalls.single.token, 'token-2');

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('a tap event forwards the message\'s profile_id to the injected callback; a tap with no profile_id forwards nothing', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final forwarded = <String>[];
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
      onTap: forwarded.add,
    );
    await coordinator.start();

    tokenSource.emitTap('profile-1');
    tokenSource.emitTap(null);
    await pumpEventQueue();

    expect(forwarded, ['profile-1']);

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('removeRegistration (#1 review fix) removes this device\'s registration on demand, even while disposed', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );
    await coordinator.start();
    expect(registry.removeCalls, isEmpty);

    await coordinator.removeRegistration();
    expect(registry.removeCalls, [deviceId]);

    // Callable even after dispose (app_lifecycle.dart's resetDevice calls
    // this before dispose, but a defensive call afterwards must not throw).
    await coordinator.dispose();
    await coordinator.removeRegistration();
    expect(registry.removeCalls, [deviceId, deviceId]);

    await tokenSource.close();
  });

  test('removeRegistration swallows a registry failure (best-effort)', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry()..nextRemoveError = Exception('boom');
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );
    await coordinator.start();

    await expectLater(coordinator.removeRegistration(), completes);
    expect(registry.removeCalls, isEmpty, reason: 'the one attempt threw');

    await coordinator.dispose();
    await tokenSource.close();
  });

  test('dispose cancels every subscription and a late event afterwards is a no-op', () async {
    final tokenSource = FakePushTokenSource()..tokenToReturn = 'token-1';
    final registry = _FakeRegistry();
    final coordinator = PushRegistrationCoordinator(
      tokenSource: tokenSource,
      registry: registry,
      deviceId: deviceId,
      platform: platform,
      authStates: const Stream<AuthSessionState>.empty(),
      currentAuthState: () => AuthSessionState.signedIn,
    );
    await coordinator.start();
    expect(registry.registerCalls, hasLength(1));

    await coordinator.dispose();

    tokenSource.emitRefresh('token-2');
    await pumpEventQueue();

    expect(registry.registerCalls, hasLength(1), reason: 'no activity after dispose');
    await tokenSource.close();
  });
}
