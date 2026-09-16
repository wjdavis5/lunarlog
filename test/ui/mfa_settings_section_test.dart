/// [MfaSettingsSection] (issue #268 U1/U2): the "Set up two-factor
/// authentication" tile when no factor is enrolled, the enrolment screen's
/// enroll → verify round trip, and the enrolled-factor row's remove flow.
///
/// Issue #738: the suite is parameterized by the client-side feature flag
/// (`AuthController.mfaEnabled`, backed by the `LUNARLOG_ENABLE_MFA`
/// define). The #268 tests run the flag-on build (`mfaEnabled: true` —
/// #714's exact behavior, nothing deleted); a closing group pins the
/// flag-off default: tile group hidden, enrolment screen inert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/mfa_enroll_screen.dart';
import 'package:lunarlog/ui/account/mfa_settings_section.dart';

import '../support/fake_auth_service.dart';

Finder key(String key) => find.byKey(ValueKey(key));

Future<AuthController> pumpSection(
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
      home: Scaffold(body: MfaSettingsSection(auth: controller)),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('no factor enrolled: shows the enrol tile, not a factor row',
      (tester) async {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    expect(key('mfa-enroll-tile'), findsOneWidget);
    expect(find.textContaining('Authenticator app'), findsNothing);
  });

  testWidgets('a verified factor: shows the factor row with a remove action',
      (tester) async {
    final auth = FakeAuthService()
      ..mfaFactors = [
        MfaFactor(
          id: 'factor-1',
          status: MfaFactorStatus.verified,
          createdAt: DateTime.utc(2026),
        ),
      ];
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    expect(key('mfa-enroll-tile'), findsNothing);
    expect(key('mfa-factor-tile-factor-1'), findsOneWidget);
    expect(key('mfa-remove-factor-1'), findsOneWidget);
  });

  testWidgets(
      'enrolling: the enrol screen shows the secret, and a correct code '
      'completes enrolment and refreshes the list', (tester) async {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    await tester.tap(key('mfa-enroll-tile'));
    await tester.pumpAndSettle();

    expect(key('mfa-enroll-secret'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(key('mfa-enroll-secret')).data,
      auth.enrollTotpResult.secret,
    );

    await tester.enterText(key('mfa-enroll-code-field'), '123456');
    // After a successful verify, the fake enrols the factor for real so the
    // section's post-pop reload sees it.
    auth.mfaFactors = [
      MfaFactor(
        id: auth.enrollTotpResult.factorId,
        status: MfaFactorStatus.verified,
        createdAt: DateTime.utc(2026),
      ),
    ];
    await tester.tap(key('mfa-enroll-confirm'));
    await tester.pumpAndSettle();

    expect(auth.verifyTotpCodeCalls.single.code, '123456');
    expect(key('mfa-enroll-tile'), findsNothing);
    expect(key('mfa-factor-tile-${auth.enrollTotpResult.factorId}'),
        findsOneWidget);
  });

  testWidgets('a wrong code (AuthFailure) shows its copy and stays on the '
      'enrolment screen', (tester) async {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    await tester.tap(key('mfa-enroll-tile'));
    await tester.pumpAndSettle();
    // Set only after enrollTotp() (initState) has already consumed any
    // pending `nextFailure` successfully — this fake's `nextFailure` is a
    // one-shot throw on the *next* call, whichever that is.
    auth.nextFailure = const AuthInvalidCodeFailure();
    await tester.enterText(key('mfa-enroll-code-field'), '000000');
    await tester.tap(key('mfa-enroll-confirm'));
    await tester.pumpAndSettle();

    expect(key('mfa-enroll-verify-error'), findsOneWidget);
    expect(key('mfa-enroll-code-field'), findsOneWidget,
        reason: 'a wrong code must not pop the enrolment screen');
  });

  testWidgets('a non-AuthFailure error shows the generic copy', (tester) async {
    final auth = FakeAuthService();
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    await tester.tap(key('mfa-enroll-tile'));
    await tester.pumpAndSettle();
    auth.verifyTotpCodeThrowsGeneric = true;
    await tester.enterText(key('mfa-enroll-code-field'), '000000');
    await tester.tap(key('mfa-enroll-confirm'));
    await tester.pumpAndSettle();

    expect(key('mfa-enroll-verify-error'), findsOneWidget);
  });

  testWidgets('removing a factor confirms, then calls unenrollMfaFactor and '
      'refreshes the list', (tester) async {
    final auth = FakeAuthService()
      ..mfaFactors = [
        MfaFactor(
          id: 'factor-1',
          status: MfaFactorStatus.verified,
          createdAt: DateTime.utc(2026),
        ),
      ];
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    await tester.tap(key('mfa-remove-factor-1'));
    await tester.pumpAndSettle();
    expect(find.text('Remove two-factor authentication?'), findsOneWidget);

    await tester.tap(key('mfa-remove-confirm'));
    await tester.pumpAndSettle();

    expect(auth.unenrollMfaFactorCalls, ['factor-1']);
    expect(key('mfa-factor-tile-factor-1'), findsNothing);
    expect(key('mfa-enroll-tile'), findsOneWidget);
  });

  testWidgets('cancelling the remove confirmation never calls unenroll',
      (tester) async {
    final auth = FakeAuthService()
      ..mfaFactors = [
        MfaFactor(
          id: 'factor-1',
          status: MfaFactorStatus.verified,
          createdAt: DateTime.utc(2026),
        ),
      ];
    addTearDown(auth.dispose);
    await pumpSection(tester, auth);

    await tester.tap(key('mfa-remove-factor-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(auth.unenrollMfaFactorCalls, isEmpty);
    expect(key('mfa-factor-tile-factor-1'), findsOneWidget);
  });

  group('feature flag off (issue #738 — the default build)', () {
    testWidgets('the tile group renders nothing and never lists factors, '
        'even with a verified factor on the account', (tester) async {
      final auth = FakeAuthService()
        ..mfaFactors = [
          MfaFactor(
            id: 'factor-1',
            status: MfaFactorStatus.verified,
            createdAt: DateTime.utc(2026),
          ),
        ];
      addTearDown(auth.dispose);
      await pumpSection(tester, auth, mfaEnabled: false);

      expect(key('mfa-enroll-tile'), findsNothing);
      expect(key('mfa-factor-tile-factor-1'), findsNothing);
      expect(find.textContaining('Two-factor'), findsNothing);
      // Inert, not just invisible: the service was never asked for the
      // factor list.
      expect(auth.listMfaFactorsCalls, 0);
    });

    testWidgets('the enrolment screen never starts a server-side enrolment '
        'when pushed directly (route guard, defense in depth)',
        (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MfaEnrollScreen(auth: controller),
        ),
      );
      await tester.pumpAndSettle();

      // The screen itself refuses: no enrolment round trip, no secret
      // rendered, nothing to confirm.
      expect(auth.enrollTotpCalls, 0);
      expect(key('mfa-enroll-secret'), findsNothing);
      expect(key('mfa-enroll-confirm'), findsNothing);
    });
  });
}
