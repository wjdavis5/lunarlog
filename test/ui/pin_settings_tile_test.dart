/// [PinSettingsTile] (issue #271): self-hides with no [GateController] or
/// no [GateController.pinAvailable], otherwise shows the current PIN status
/// and navigates to [PinSettingsScreen] on tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/gate_controller.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/gate/pin_settings_tile.dart';
import 'package:provider/provider.dart';

import 'gate_test.dart' show FakeGate, FakeInactivityTimers;
import 'pin_gate_controller_test.dart' show FakePinCredentialService;

Finder key(String key) => find.byKey(ValueKey(key));

class _NoopGate implements AppGate {
  @override
  bool get requiresUnlock => true;

  @override
  Future<bool> canAuthenticate() async => true;

  @override
  Future<bool> requestAccess() async => true;
}

Future<void> pumpTile(WidgetTester tester, GateController? controller) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: controller == null
            ? const PinSettingsTile()
            : ChangeNotifierProvider<GateController?>.value(
                value: controller,
                child: const PinSettingsTile(),
              ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no GateController at all: renders nothing', (tester) async {
    await pumpTile(tester, null);
    expect(key('pin-settings-tile'), findsNothing);
  });

  testWidgets('a GateController with no PIN service: renders nothing',
      (tester) async {
    final controller = GateController(gate: _NoopGate());
    addTearDown(controller.dispose);
    await pumpTile(tester, controller);
    expect(key('pin-settings-tile'), findsNothing);
  });

  testWidgets('PIN available, none set: shows the Off subtitle', (tester) async {
    final controller = GateController(
      gate: _NoopGate(),
      pinService: FakePinCredentialService(),
    );
    addTearDown(controller.dispose);
    await pumpTile(tester, controller);

    expect(key('pin-settings-tile'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('PIN available and set: shows the On subtitle', (tester) async {
    final controller = GateController(
      gate: _NoopGate(),
      pinService: FakePinCredentialService()..pinSet = true,
    );
    addTearDown(controller.dispose);
    await pumpTile(tester, controller);

    expect(key('pin-settings-tile'), findsOneWidget);
    expect(
      find.text('On — an additional lock layer on top of your device '
          'credential.'),
      findsOneWidget,
    );
  });

  testWidgets('tapping the tile pushes PinSettingsScreen', (tester) async {
    final controller = GateController(
      gate: FakeGate(),
      pinService: FakePinCredentialService(),
      inactivityTimerFactory: FakeInactivityTimers().factory,
    );
    addTearDown(controller.dispose);
    await pumpTile(tester, controller);

    await tester.tap(key('pin-settings-tile'));
    await tester.pumpAndSettle();

    expect(key('pin-create-tile'), findsOneWidget);
  });
}
