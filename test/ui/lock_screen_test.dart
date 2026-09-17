/// Widget tests for [LockScreen]'s split denial copy (issue #534):
/// [GateDenialReason.deniedByUser] keeps the existing retry message and
/// Unlock button, while [GateDenialReason.noCredentialEnrolled] gets its
/// own prominent explanation and a primary "Open device settings" action
/// instead of the old footnote below an apparently-broken button. The
/// settings launch itself is injected as a fake — this suite never touches
/// `url_launcher`'s platform channel.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/ui/gate/lock_screen.dart';

import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

Finder byKey(String key) => find.byKey(ValueKey(key));

void main() {
  testWidgets(
      'noCredentialEnrolled: prominent message + settings button, no '
      'footnote-style denial message', (tester) async {
    final gate = FakeGate(canAuthenticateNext: false);
    final controller = GateController(gate: gate);
    addTearDown(controller.dispose);
    await controller.unlock();
    expect(controller.denialReason, GateDenialReason.noCredentialEnrolled);

    var settingsLaunches = 0;
    await tester.pumpWidget(LockScreen(
      controller: controller,
      openDeviceSettings: () async {
        settingsLaunches++;
      },
    ));

    expect(byKey('no-credential-message'), findsOneWidget,
        reason: 'the no-credential explanation is the primary content, '
            'not a footnote');
    final settingsButton = byKey('open-device-settings-button');
    expect(settingsButton, findsOneWidget,
        reason: 'a clear "Open device settings" action must be present');
    expect(tester.widget(settingsButton), isA<FilledButton>(),
        reason: 'the settings action is a prominent FilledButton, not a '
            'small text link');
    expect(byKey('lock-denied-message'), findsNothing,
        reason: 'the generic decline copy must not also render here');

    await tester.tap(settingsButton);
    await tester.pump();

    expect(settingsLaunches, 1,
        reason: 'tapping the button must invoke the injected launcher, '
            'never call url_launcher directly from the widget');
  });

  testWidgets(
      'noCredentialEnrolled: the secondary "Try again" action re-runs the '
      'gate\'s own unlock check', (tester) async {
    final gate = FakeGate(canAuthenticateNext: false);
    final controller = GateController(gate: gate);
    addTearDown(controller.dispose);
    await controller.unlock();
    final checksBefore = gate.canAuthenticateRequests;

    await tester.pumpWidget(LockScreen(
      controller: controller,
      openDeviceSettings: () async {},
    ));
    await tester.tap(byKey('unlock-retry-button'));
    await tester.pump();

    expect(gate.canAuthenticateRequests, greaterThan(checksBefore));
  });

  testWidgets(
      'deniedByUser: retry copy + Unlock button, no settings action',
      (tester) async {
    final gate = FakeGate(canAuthenticateNext: true, grantNext: false);
    final controller = GateController(
        gate: gate, inactivityTimerFactory: FakeInactivityTimers().factory);
    addTearDown(controller.dispose);
    await controller.unlock();
    expect(controller.denialReason, GateDenialReason.deniedByUser);

    await tester.pumpWidget(LockScreen(controller: controller));

    expect(byKey('lock-denied-message'), findsOneWidget);
    expect(byKey('unlock-button'), findsOneWidget);
    expect(byKey('open-device-settings-button'), findsNothing,
        reason: 'a declined prompt is retryable — no settings deep link');
    expect(byKey('no-credential-message'), findsNothing);
  });

  testWidgets('the two denial states render distinct primary copy',
      (tester) async {
    final noCredentialGate = FakeGate(canAuthenticateNext: false);
    final noCredentialController = GateController(gate: noCredentialGate);
    addTearDown(noCredentialController.dispose);
    await noCredentialController.unlock();
    await tester.pumpWidget(LockScreen(controller: noCredentialController));
    final noCredentialText = tester
        .widget<Text>(byKey('no-credential-message'))
        .data;

    final deniedGate =
        FakeGate(canAuthenticateNext: true, grantNext: false);
    final deniedController = GateController(
        gate: deniedGate,
        inactivityTimerFactory: FakeInactivityTimers().factory);
    addTearDown(deniedController.dispose);
    await deniedController.unlock();
    await tester.pumpWidget(LockScreen(controller: deniedController));
    final deniedText =
        tester.widget<Text>(byKey('lock-denied-message')).data;

    expect(noCredentialText, isNot(equals(deniedText)));
  });
}
