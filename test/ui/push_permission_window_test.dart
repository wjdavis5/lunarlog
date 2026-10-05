/// Issue #1425: push registration's launch-time permission ask against the
/// real [GateController].
///
/// The system permission dialog reports its own lifecycle departure
/// (`inactive`) for as long as it is up. Outside a system-UI window the
/// gate reads that as the operator leaving: it covers the content and,
/// once its 3-second grace runs out, locks the app behind the dialog the
/// operator is still reading. The ask therefore runs inside
/// `GateController.duringSystemUi` — and only when a dialog can appear, so
/// a launch whose permission is already settled opens no window and shows
/// no cover.
///
/// Driven through the real `FirebasePushTokenSource` with fakes for the
/// two `firebase_messaging` calls only; the decision table itself is in
/// `test/domain/notifications/push_permission_plan_test.dart` and the
/// runner's own cases in `test/data/notifications/
/// push_permission_ask_test.dart`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/notifications/firebase_push_token_source.dart';
import 'package:lunarlog/data/notifications/notification_permission_gate.dart';
import 'package:lunarlog/domain/notifications/push_permission_plan.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/gate_controller.dart';

import '../support/fake_settings_store.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

class _Harness {
  _Harness() {
    controller = GateController(
      gate: FakeGate(),
      inactivityTimerFactory: timers.factory,
    );
  }

  final timers = FakeInactivityTimers();
  late final GateController controller;

  /// A gated app, unlocked, with the unlock prompt's own system-UI window
  /// fully settled — so any window seen afterwards is the push ask's.
  Future<void> unlock() async {
    await controller.unlock();
    timers.fireWithDelay(kSystemUiSettleTimeout);
    expect(controller.locked, isFalse);
    expect(controller.systemUiActive, isFalse);
    expect(controller.obscured, isFalse);
  }

  FirebasePushTokenSource source({
    required bool withWindow,
    int refusalsOnRecord = 0,
  }) =>
      FirebasePushTokenSource(
        permissionGate: NotificationPermissionGate(),
        duringSystemUi: withWindow ? controller.duringSystemUi : null,
        settingsStore: FakeSettingsStore({
          SettingsKeys.androidNotificationDeniedAttempts: '$refusalsOnRecord',
        }),
      );

  /// The system dialog comes up (the platform reports `inactive`) and the
  /// operator is still reading it when the gate's grace runs out.
  void dialogStaysUpPastTheGrace() {
    controller.didChangeAppLifecycleState(AppLifecycleState.inactive);
    timers.fireWithDelay(kSystemUiSettleTimeout);
  }
}

void main() {
  // GateController's constructor reads WidgetsBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final isAndroid in [true, false]) {
    final platform = isAndroid ? 'Android' : 'Darwin';

    test('$platform: the push ask runs inside a system-UI window, so the '
        'gate does not re-lock while the dialog is up', () async {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await h.unlock();
      final dialog = Completer<PushPermissionState>();

      final ask = h.source(withWindow: true).askPermission(
            isAndroid: isAndroid,
            currentState: () async => PushPermissionState.undetermined,
            request: () => dialog.future,
          );
      await pumpEventQueue();

      expect(h.controller.systemUiActive, isTrue,
          reason: 'the request is in flight inside the window');

      h.dialogStaysUpPastTheGrace();

      expect(h.controller.locked, isFalse,
          reason: 'the dialog is the app\'s own system UI, not a departure');

      dialog.complete(PushPermissionState.refused);
      h.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await ask;
      h.timers.fireWithDelay(kSystemUiSettleTimeout);

      expect(h.controller.locked, isFalse);
      expect(h.controller.systemUiActive, isFalse,
          reason: 'the window closed with the request and has settled');
      expect(h.controller.obscured, isFalse,
          reason: 'no cover is left behind once the dialog is answered');
    });
  }

  test('without the window the same dialog locks the app -- what the '
      'window is there to prevent', () async {
    // Falsification coverage for the test above: the identical sequence,
    // with the ask run bare, ends locked.
    final h = _Harness();
    addTearDown(h.controller.dispose);
    await h.unlock();
    final dialog = Completer<PushPermissionState>();

    final ask = h.source(withWindow: false).askPermission(
          isAndroid: true,
          currentState: () async => PushPermissionState.undetermined,
          request: () => dialog.future,
        );
    await pumpEventQueue();
    expect(h.controller.systemUiActive, isFalse);

    h.dialogStaysUpPastTheGrace();

    expect(h.controller.locked, isTrue);

    dialog.complete(PushPermissionState.refused);
    await ask;
  });

  test('a launch whose permission is already settled opens no window and '
      'shows no cover', () async {
    // Settled either way: already granted, or refused twice so that
    // Android no longer shows its dialog.
    for (final (settled, refusals) in [
      (PushPermissionState.granted, 0),
      (PushPermissionState.refused, 2),
    ]) {
      final h = _Harness();
      addTearDown(h.controller.dispose);
      await h.unlock();
      var notifications = 0;
      h.controller.addListener(() => notifications++);
      var requests = 0;

      await h.source(withWindow: true, refusalsOnRecord: refusals)
          .askPermission(
        isAndroid: true,
        currentState: () async => settled,
        request: () async {
          requests++;
          return settled;
        },
      );

      expect(requests, 0, reason: '$settled');
      expect(h.controller.systemUiActive, isFalse, reason: '$settled');
      expect(h.controller.obscured, isFalse, reason: '$settled');
      expect(notifications, 0,
          reason: '$settled: the gate was never touched, so nothing '
              'rebuilt and no cover flashed');
    }
  });

  test('Darwin with a decided permission still makes its request, but '
      'opens no window for it', () async {
    final h = _Harness();
    addTearDown(h.controller.dispose);
    await h.unlock();
    var notifications = 0;
    h.controller.addListener(() => notifications++);
    var requests = 0;

    await h.source(withWindow: true).askPermission(
          isAndroid: false,
          currentState: () async => PushPermissionState.refused,
          request: () async {
            requests++;
            return PushPermissionState.refused;
          },
        );

    expect(requests, 1);
    expect(h.controller.systemUiActive, isFalse);
    expect(notifications, 0);
  });
}
