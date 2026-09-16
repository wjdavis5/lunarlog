/// [ensureAal2]/the AAL2 step-up dialog (issue #268 D-6): the wrong-code
/// and generic-exception branches of its `_verify` method. The happy path
/// and the "no step-up needed" no-op are already covered end-to-end through
/// `account_deletion_test.dart`'s and `transfer_ownership_test.dart`'s own
/// AAL2 groups; this suite isolates the dialog itself.
///
/// Issue #738: parameterized by `AuthController.mfaEnabled` (the
/// `LUNARLOG_ENABLE_MFA` define). The #268 cases run the flag-on build; a
/// closing group pins the flag-off default: `ensureAal2` auto-passes
/// without consulting the service at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/mfa_step_up_dialog.dart';

import '../support/fake_auth_service.dart';

Finder key(String key) => find.byKey(ValueKey(key));

Future<AuthController> pumpEnsureAal2(
  WidgetTester tester,
  FakeAuthService auth, {
  bool mfaEnabled = true,
}) async {
  auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
  final controller = AuthController(authService: auth, mfaEnabled: mfaEnabled);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            key: const ValueKey('trigger'),
            onPressed: () => ensureAal2(context, controller),
            child: const Text('Go'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('a wrong code shows its copy and does not proceed',
      (tester) async {
    final auth = FakeAuthService()
      ..mfaStepUpRequired = true
      ..mfaFactors = [
        MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026)),
      ];
    addTearDown(auth.dispose);
    await pumpEnsureAal2(tester, auth);

    await tester.tap(key('trigger'));
    await tester.pumpAndSettle();
    auth.nextFailure = const AuthInvalidCodeFailure();
    await tester.enterText(key('mfa-step-up-code-field'), '000000');
    await tester.tap(key('mfa-step-up-confirm'));
    await tester.pumpAndSettle();

    expect(key('mfa-step-up-error'), findsOneWidget);
    expect(key('mfa-step-up-code-field'), findsOneWidget,
        reason: 'a wrong code must not dismiss the dialog');
  });

  testWidgets('a non-AuthFailure error shows the generic copy',
      (tester) async {
    final auth = FakeAuthService()
      ..mfaStepUpRequired = true
      ..mfaFactors = [
        MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026)),
      ];
    addTearDown(auth.dispose);
    await pumpEnsureAal2(tester, auth);

    await tester.tap(key('trigger'));
    await tester.pumpAndSettle();
    auth.verifyTotpCodeThrowsGeneric = true;
    await tester.enterText(key('mfa-step-up-code-field'), '000000');
    await tester.tap(key('mfa-step-up-confirm'));
    await tester.pumpAndSettle();

    expect(key('mfa-step-up-error'), findsOneWidget);
  });

  testWidgets('cancelling the dialog leaves it dismissed', (tester) async {
    final auth = FakeAuthService()
      ..mfaStepUpRequired = true
      ..mfaFactors = [
        MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026)),
      ];
    addTearDown(auth.dispose);
    await pumpEnsureAal2(tester, auth);

    await tester.tap(key('trigger'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text("Confirm it's you"), findsNothing);
    expect(auth.verifyTotpCodeCalls, isEmpty);
  });

  group('feature flag off (issue #738 — the default build)', () {
    testWidgets('ensureAal2 auto-passes with a step-up-required account, '
        'without ever consulting the service', (tester) async {
      final auth = FakeAuthService()
        ..mfaStepUpRequired = true
        ..mfaFactors = [
          MfaFactor(
              id: 'factor-1',
              status: MfaFactorStatus.verified,
              createdAt: DateTime.utc(2026)),
        ];
      addTearDown(auth.dispose);
      await pumpEnsureAal2(tester, auth, mfaEnabled: false);

      await tester.tap(key('trigger'));
      await tester.pumpAndSettle();

      expect(find.text("Confirm it's you"), findsNothing);
      expect(auth.verifyTotpCodeCalls, isEmpty);
      // The early return fires before requiresMfaStepUp is even resolved:
      // the flag-off posture is structural, not a filtered-away answer.
      expect(auth.requiresMfaStepUpCalls, 0);
      expect(auth.listMfaFactorsCalls, 0);
    });
  });
}
