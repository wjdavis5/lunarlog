/// [PinSettingsScreen] and [PinSettingsTile] (issue #271 U1/U4): setting a
/// brand-new PIN needs no prior check; changing or turning one off requires
/// the current PIN or a fresh device credential.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/gate/pin_settings_screen.dart';
import 'package:provider/provider.dart';

import 'pin_gate_controller_test.dart' show FakePinCredentialService;
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;

Finder key(String key) => find.byKey(ValueKey(key));

Future<GateController> pumpScreen(
  WidgetTester tester,
  FakePinCredentialService pin, {
  FakeGate? gate,
}) async {
  final controller = GateController(
    gate: gate ?? FakeGate(),
    pinService: pin,
    inactivityTimerFactory: FakeInactivityTimers().factory,
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ChangeNotifierProvider<GateController>.value(
        value: controller,
        child: PinSettingsScreen(gate: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('no PIN set: only the create tile renders', (tester) async {
    final pin = FakePinCredentialService();
    await pumpScreen(tester, pin);

    expect(key('pin-create-tile'), findsOneWidget);
    expect(key('pin-change-tile'), findsNothing);
    expect(key('pin-remove-tile'), findsNothing);
  });

  testWidgets('creating a PIN needs no prior authorization', (tester) async {
    final pin = FakePinCredentialService();
    await pumpScreen(tester, pin);

    await tester.tap(key('pin-create-tile'));
    await tester.pumpAndSettle();
    await tester.enterText(key('pin-new-field'), '1234');
    await tester.enterText(key('pin-confirm-field'), '1234');
    await tester.tap(key('pin-save-button'));
    await tester.pumpAndSettle();

    expect(pin.setPinCalls, 1);
    expect(pin.storedPin, '1234');
    expect(pin.verifyCalls, isEmpty,
        reason: 'creating a brand-new PIN needs no prior verification');
    expect(key('pin-change-tile'), findsOneWidget);
  });

  testWidgets('mismatched new/confirm PIN shows an inline error and saves nothing',
      (tester) async {
    final pin = FakePinCredentialService();
    await pumpScreen(tester, pin);

    await tester.tap(key('pin-create-tile'));
    await tester.pumpAndSettle();
    await tester.enterText(key('pin-new-field'), '1234');
    await tester.enterText(key('pin-confirm-field'), '4321');
    await tester.tap(key('pin-save-button'));
    await tester.pumpAndSettle();

    expect(pin.setPinCalls, 0);
    expect(find.text("PINs don't match."), findsOneWidget);
  });

  testWidgets('a too-short PIN shows an inline error and saves nothing',
      (tester) async {
    final pin = FakePinCredentialService();
    await pumpScreen(tester, pin);

    await tester.tap(key('pin-create-tile'));
    await tester.pumpAndSettle();
    await tester.enterText(key('pin-new-field'), '12');
    await tester.enterText(key('pin-confirm-field'), '12');
    await tester.tap(key('pin-save-button'));
    await tester.pumpAndSettle();

    expect(pin.setPinCalls, 0);
    expect(find.text('Enter at least 4 digits.'), findsOneWidget);
  });

  group('changing or removing an existing PIN', () {
    late FakePinCredentialService pin;

    setUp(() {
      pin = FakePinCredentialService()
        ..pinSet = true
        ..storedPin = '1234';
    });

    testWidgets('changing requires the correct current PIN first',
        (tester) async {
      await pumpScreen(tester, pin);

      await tester.tap(key('pin-change-tile'));
      await tester.pumpAndSettle();
      expect(key('pin-auth-current-field'), findsOneWidget);

      await tester.enterText(key('pin-auth-current-field'), '1234');
      await tester.tap(key('pin-auth-verify'));
      await tester.pumpAndSettle();

      expect(key('pin-new-field'), findsOneWidget,
          reason: 'a correct current PIN opens the change form');

      await tester.enterText(key('pin-new-field'), '5678');
      await tester.enterText(key('pin-confirm-field'), '5678');
      await tester.tap(key('pin-save-button'));
      await tester.pumpAndSettle();

      expect(pin.storedPin, '5678');
    });

    testWidgets('a wrong current PIN blocks the change form from opening',
        (tester) async {
      await pumpScreen(tester, pin);

      await tester.tap(key('pin-change-tile'));
      await tester.pumpAndSettle();
      await tester.enterText(key('pin-auth-current-field'), '0000');
      await tester.tap(key('pin-auth-verify'));
      await tester.pumpAndSettle();

      expect(find.text('That PIN is incorrect.'), findsOneWidget);
      expect(key('pin-new-field'), findsNothing);
      expect(pin.storedPin, '1234', reason: 'the PIN must be unchanged');
    });

    testWidgets(
        'a granted device credential also authorizes the change, without '
        'the current PIN', (tester) async {
      final gate = FakeGate(grantNext: true);
      await pumpScreen(tester, pin, gate: gate);

      await tester.tap(key('pin-change-tile'));
      await tester.pumpAndSettle();
      await tester.tap(key('pin-auth-device-credential'));
      await tester.pumpAndSettle();

      expect(key('pin-new-field'), findsOneWidget);
      expect(pin.verifyCalls, isEmpty,
          reason: 'the device-credential path never calls verifyPin');
    });

    testWidgets('turning the PIN off requires authorization and confirmation',
        (tester) async {
      await pumpScreen(tester, pin);

      await tester.tap(key('pin-remove-tile'));
      await tester.pumpAndSettle();
      await tester.enterText(key('pin-auth-current-field'), '1234');
      await tester.tap(key('pin-auth-verify'));
      await tester.pumpAndSettle();

      expect(find.text('Turn off PIN?'), findsOneWidget);
      await tester.tap(key('pin-remove-confirm'));
      await tester.pumpAndSettle();

      expect(pin.clearPinCalls, 1);
      expect(key('pin-create-tile'), findsOneWidget);
    });

    testWidgets('cancelling the authorization dialog never opens the change '
        'form or turn-off confirmation', (tester) async {
      await pumpScreen(tester, pin);

      await tester.tap(key('pin-change-tile'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(key('pin-new-field'), findsNothing);
      expect(pin.setPinCalls, 0);
    });
  });
}
