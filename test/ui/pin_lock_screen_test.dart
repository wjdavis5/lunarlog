/// [LockScreen] rendering the in-app PIN entry (issue #271 D-6) once
/// [GateController.pinRequired] is true, in place of the device-credential
/// content. [GateController]'s own PIN state machine is covered in
/// `pin_gate_controller_test.dart`; this suite exercises the actual widget
/// tree — entry, wrong-PIN copy, and lockout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';

import 'gate_test.dart' show FakeGate, FakeInactivityTimers;
import 'pin_gate_controller_test.dart' show FakePinCredentialService;

Finder key(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets(
      'a granted device credential + PIN set: the PIN entry replaces the '
      'device-credential content, and a correct PIN unlocks', (tester) async {
    final gate = FakeGate();
    final pin = FakePinCredentialService()
      ..pinSet = true
      ..storedPin = '1234';
    final controller = GateController(
      gate: gate,
      pinService: pin,
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await controller.unlock();
    expect(controller.pinRequired, isTrue);

    await tester.pumpWidget(LockScreen(controller: controller));

    expect(key('pin-unlock-field'), findsOneWidget);
    expect(key('unlock-button'), findsNothing,
        reason: 'the device-credential Unlock button must not also show');

    await tester.enterText(key('pin-unlock-field'), '1234');
    await tester.tap(key('pin-unlock-button'));
    await tester.pumpAndSettle();

    expect(controller.locked, isFalse);
  });

  testWidgets('a wrong PIN shows an inline error naming remaining attempts',
      (tester) async {
    final gate = FakeGate();
    final pin = FakePinCredentialService()
      ..pinSet = true
      ..storedPin = '1234';
    final controller = GateController(
      gate: gate,
      pinService: pin,
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await controller.unlock();

    await tester.pumpWidget(LockScreen(controller: controller));
    await tester.enterText(key('pin-unlock-field'), '0000');
    await tester.tap(key('pin-unlock-button'));
    await tester.pumpAndSettle();

    expect(key('pin-unlock-error'), findsOneWidget);
    expect(controller.locked, isTrue);
  });

  testWidgets(
      'no device credential enrolled + PIN set: the lock screen shows the '
      'PIN entry directly, never the no-credential dead end',
      (tester) async {
    final gate = FakeGate(canAuthenticateNext: false);
    final pin = FakePinCredentialService()
      ..pinSet = true
      ..storedPin = '1234';
    final controller = GateController(
      gate: gate,
      pinService: pin,
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await controller.unlock();

    await tester.pumpWidget(LockScreen(controller: controller));

    expect(key('pin-unlock-field'), findsOneWidget);
    expect(key('no-credential-message'), findsNothing);
  });

  testWidgets(
      'a locked-out result disables entry and shows a countdown message',
      (tester) async {
    final gate = FakeGate();
    final lockedUntil = DateTime.now().add(const Duration(minutes: 1));
    final pin = FakePinCredentialService()
      ..pinSet = true
      ..storedPin = '1234'
      ..nextVerification = PinVerification(
        outcome: PinCheckOutcome.lockedOut,
        lockedUntil: lockedUntil,
        remainingFreeAttempts: 0,
      );
    final controller = GateController(
      gate: gate,
      pinService: pin,
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await controller.unlock();

    await tester.pumpWidget(LockScreen(controller: controller));
    await tester.enterText(key('pin-unlock-field'), '1234');
    await tester.tap(key('pin-unlock-button'));
    await tester.pumpAndSettle();

    expect(key('pin-unlock-error'), findsOneWidget);
    expect(
      tester.widget<TextField>(key('pin-unlock-field')).enabled,
      isFalse,
      reason: 'entry must be disabled while locked out',
    );
    expect(controller.locked, isTrue);
  });

  testWidgets(
      'relaunching mid-lockout shows the countdown immediately, before any '
      'wrong attempt', (tester) async {
    final gate = FakeGate();
    final lockedUntil = DateTime.now().add(const Duration(minutes: 1));
    final pin = FakePinCredentialService()
      ..pinSet = true
      ..storedPin = '1234'
      ..lockout = PinLockoutState(lockedUntil: lockedUntil);
    final controller = GateController(
      gate: gate,
      pinService: pin,
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await controller.unlock();

    await tester.pumpWidget(LockScreen(controller: controller));
    await tester.pumpAndSettle();

    expect(key('pin-unlock-error'), findsOneWidget);
    expect(pin.verifyCalls, isEmpty,
        reason: 'the countdown must show without attempting a verification');
  });
}
