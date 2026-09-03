/// U4 wiring check: `LunarLogApp` provides an [AuthController] only when an
/// [AuthService] is passed; with `authService: null` (every existing
/// harness, and an unconfigured build) nothing account-related is provided
/// and the tree renders exactly as before (KTD11).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import 'gate_test.dart' show FakeGate;

Future<void> disposeApp(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

BuildContext homeContext(WidgetTester tester) =>
    tester.element(find.byType(ProfileHomeGate));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('LunarLogApp without an auth service provides no '
      'AuthController and still renders first-run', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileHomeGate), findsOneWidget);
    expect(homeContext(tester).read<AuthController?>(), isNull);
    // The pre-U4 first-run surface (notice → "I understand") is untouched.
    expect(find.text('I understand'), findsOneWidget);

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp with an auth service provides an AuthController '
      'that mirrors the service', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final service = FakeAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(LunarLogApp(db: db, authService: service));
    await tester.pumpAndSettle();

    final controller = homeContext(tester).read<AuthController?>();
    expect(controller, isNotNull);
    expect(controller!.state, AuthSessionState.signedOut);

    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await tester.pump();
    expect(controller.state, AuthSessionState.signedIn);
    expect(controller.currentUserId, 'u1');

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogRoot passes the auth service through the gate shell',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final service = FakeAuthService(pendingRecovery: true);
    addTearDown(service.dispose);
    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(requiresUnlock: false),
      dbOpener: () async => db,
      authService: service,
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    final controller = homeContext(tester).read<AuthController?>();
    expect(controller, isNotNull);
    expect(controller!.pendingRecovery, isTrue,
        reason: 'latched in the service before the widget tree existed');

    await disposeApp(tester, db);
  });
}
