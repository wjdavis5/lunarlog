/// Widget tests for U6: the account UI — sign-in / create-account /
/// forgot-password / Apple with pending states, the recovery route (AE8),
/// the first-run account step, the restoring step (AE13), the mismatch
/// screen (AE5), upload consent re-entry, the sync status tile, "Sync now",
/// and the sign-out dialogs. Every collaborator is a fake (KTD6); the
/// destructive reset is a recorder that wipes the in-memory database so the
/// tree re-evaluates first-run the way the real `resetDevice` does.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart' show SyncTable;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/ui/account/account_section.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart'
    show SignInWithAppleButton;

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';
import '../support/pump_helpers.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;
import 'profiles_test.dart' show kNoticeText;

const String kWaitingCopy =
    'Waiting for email confirmation — open the link on this device';
const String kUploadPendingCopy = 'Upload pending — tap to review';

class AccountHarness {
  AccountHarness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  final FakeAuthService auth = FakeAuthService();
  final FakeSyncEngine engine = FakeSyncEngine();
  int resets = 0;

  Future<void> pump({
    bool withEngine = true,
    Future<void> Function(LunarLogDatabase db)? seed,
  }) async {
    if (seed != null) await seed(db);
    await tester.pumpWidget(
      LunarLogApp(
        db: db,
        authService: auth,
        syncEngine: withEngine ? engine : null,
        // Mirrors the root's reset (test/ui/device_reset_test.dart proves
        // the real order): local wipe first, local sign-out last.
        resetDevice: () async {
          resets++;
          await db.wipeAllData();
          try {
            await auth.signOut(scope: AuthSignOutScope.local);
          } on AuthFailure {
            // best effort
          }
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
    await auth.dispose();
  }

  /// Seeds one profile with no stored last-active id so the picker (and
  /// its Settings action) is home.
  static Future<void> seedOneProfile(LunarLogDatabase db) async {
    await DriftProfilesRepository(db.storage)
        .create(displayName: 'Alice', isMinor: false);
  }

  Future<void> openSettings() async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  Future<void> settle() => drainIsolateTraffic(tester);

  void signIn({String id = 'u1', String email = 'a@b.c'}) {
    auth.emit(
      AuthSessionState.signedIn,
      user: AuthUser(id: id, email: email),
    );
  }
}

Finder key(String value) => find.byKey(ValueKey(value));

/// A few plain pumps for screens that animate forever (spinners), where
/// `pumpAndSettle` would time out.
Future<void> pumpFew(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('sign-in screen (R1, R2, R3)', () {
    testWidgets('signed out: Settings shows "Sign in"; a held call shows '
        'the pending state with the action disabled; a wrong password '
        'renders a generic error and stays on the screen', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();

      expect(key('account-sign-in'), findsOneWidget);
      expect(key('account-sign-out'), findsNothing);
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'correct horse battery');
      h.auth.hold = Completer<void>();
      await tester.tap(key('auth-sign-in'));
      await tester.pump();
      expect(key('auth-pending'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('auth-sign-in')).onPressed,
        isNull,
        reason: 'the action is disabled while the call is in flight',
      );
      expect(key('auth-error'), findsNothing);

      h.auth.nextFailure = const AuthFailure.wrongPassword();
      h.auth.hold!.complete();
      h.auth.hold = null;
      await tester.pumpAndSettle();
      expect(key('auth-pending'), findsNothing);
      expect(key('auth-error'), findsOneWidget);
      expect(find.textContaining('was not accepted'), findsOneWidget);
      expect(
        tester.widget<Text>(key('auth-error')).data,
        isNot(contains('a@b.c')),
        reason: 'the error never echoes the email',
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(h.auth.signInCalls.single.email, 'a@b.c');

      // A successful retry returns to Settings, now showing the account.
      await tester.tap(key('auth-sign-in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(key('account-sign-out'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('create-account toggle switches the primary action; a '
        '9-character password errors without calling signUp; awaiting '
        'confirmation persists the setting and the tile reads the waiting '
        'copy until a session arrives', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();

      expect(key('auth-create-account'), findsNothing);
      await tester.tap(key('auth-mode-toggle'));
      await tester.pumpAndSettle();
      expect(key('auth-create-account'), findsOneWidget);
      expect(key('auth-sign-in'), findsNothing);

      await tester.enterText(key('auth-email'), 'new@b.c');
      await tester.enterText(key('auth-password'), 'nine char');
      await tester.tap(key('auth-create-account'));
      await tester.pumpAndSettle();
      expect(key('auth-error'), findsOneWidget);
      expect(
        tester.widget<Text>(key('auth-error')).data,
        contains('12 characters'),
      );
      expect(h.auth.signUpCalls, isEmpty);

      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-create-account'));
      await tester.pumpAndSettle();
      expect(h.auth.signUpCalls.single.email, 'new@b.c');
      expect(key('auth-error'), findsNothing);
      expect(
        find.textContaining('open the link on this device'),
        findsOneWidget,
      );
      final store = DriftSettingsStore(h.db.storage);
      expect(
        await store.get(SettingsKeys.awaitingConfirmationEmail),
        'new@b.c',
      );

      // Back in Settings the status tile shows the waiting copy.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await h.settle();
      expect(find.text(kWaitingCopy), findsOneWidget);

      // The confirmation link produced a session: the setting clears.
      h.signIn(email: 'new@b.c');
      await h.settle();
      expect(find.text(kWaitingCopy), findsNothing);
      expect(
        await store.get(SettingsKeys.awaitingConfirmationEmail),
        anyOf(isNull, isEmpty),
      );
      await h.dispose();
    });

    testWidgets('forgot password sends the reset for the typed email and '
        'shows a neutral confirmation', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();

      await tester.enterText(key('auth-email'), 'who@b.c');
      await tester.tap(key('auth-forgot-password'));
      await tester.pumpAndSettle();
      expect(h.auth.passwordResetCalls, ['who@b.c']);
      expect(find.textContaining('If an account exists'), findsOneWidget);
      expect(key('auth-error'), findsNothing);
      await h.dispose();
    });

    testWidgets('a cancelled Apple credential returns to the screen with no '
        'error; the Apple button renders only on iOS', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();
      expect(
        key('auth-apple'),
        findsNothing,
        reason: 'the test platform is not iOS',
      );

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await h.pump();
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();
      expect(key('auth-apple'), findsOneWidget);

      h.auth.appleResult = const AppleSignInCancelled();
      await tester.tap(key('auth-apple'));
      await tester.pumpAndSettle();
      expect(h.auth.appleCalls, 1);
      expect(key('auth-error'), findsNothing);
      expect(find.byType(SignInScreen), findsOneWidget);
      await h.dispose();
      // Must be restored inside the test body: the binding verifies it
      // before tearDown callbacks run.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('the Apple flag is injectable', (tester) async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<SettingsStore>.value(value: _NoopSettings()),
            ],
            child: const SignInScreen(showApple: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(key('auth-apple'), findsOneWidget);
    });
  });

  group('provider buttons and passwordless entry (#2 U4; AE2, AE8, R12)', () {
    testWidgets('showGoogle: false and the null default (empty config on a '
        'non-web platform) render no Google button; true renders it (AE8)', (
      tester,
    ) async {
      await pumpStandalone(tester, showGoogle: false);
      expect(key('auth-google'), findsNothing);

      await pumpStandalone(tester);
      expect(
        key('auth-google'),
        findsNothing,
        reason: 'AppConfig.hasGoogle is false without client ids',
      );

      final semantics = tester.ensureSemantics();
      await pumpStandalone(tester, showGoogle: true);
      expect(key('auth-google'), findsOneWidget);
      expect(find.bySemanticsLabel('Sign in with Google'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('on iOS with both shown, the Apple button is the package '
        'widget, precedes Google, is at least as tall, and both precede the '
        'email form (R12)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await pumpStandalone(tester, showApple: true, showGoogle: true);
      expect(tester.widget(key('auth-apple')), isA<SignInWithAppleButton>());
      final apple = tester.getTopLeft(key('auth-apple')).dy;
      final google = tester.getTopLeft(key('auth-google')).dy;
      final email = tester.getTopLeft(key('auth-email')).dy;
      expect(apple, lessThan(google));
      expect(google, lessThan(email));
      expect(
        tester.getSize(key('auth-apple')).height,
        greaterThanOrEqualTo(tester.getSize(key('auth-google')).height),
      );
      // Restored inside the body: the binding verifies it before tearDown.
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a dismissed Google picker returns with no error, no '
        'spinner, and an editable form (AE2); providerUnavailable shows the '
        'email alternative under auth-error', (tester) async {
      final s = await pumpStandalone(tester, showGoogle: true);
      s.auth.googleResult = const GoogleSignInCancelled();
      await tester.tap(key('auth-google'));
      await tester.pumpAndSettle();
      expect(s.auth.googleCalls, 1);
      expect(key('auth-error'), findsNothing);
      expect(key('auth-pending'), findsNothing);
      expect(tester.widget<TextField>(key('auth-email')).enabled, isTrue);
      expect(s.controller.signedIn, isFalse);

      s.auth.nextFailure = const AuthFailure.providerUnavailable();
      await tester.tap(key('auth-google'));
      await tester.pumpAndSettle();
      expect(s.auth.googleCalls, 2);
      final copy = tester.widget<Text>(key('auth-error')).data!;
      expect(copy, contains('email'));
      expect(copy, isNot(contains('@')));
    });

    testWidgets('#65 AE5: the Google picker does not re-lock the app, and '
        'the screen still completes once when it returns', (tester) async {
      final gateFake = FakeGate();
      final timers = FakeInactivityTimers();
      final gate = GateController(
          gate: gateFake, inactivityTimerFactory: timers.factory);
      addTearDown(gate.dispose);
      gateFake.grantNext = true;
      await gate.unlock();
      expect(gate.locked, isFalse);

      var completions = 0;
      final s = await pumpStandalone(
        tester,
        showGoogle: true,
        gate: gate,
        onSignedIn: () => completions++,
      );
      s.auth.hold = Completer<void>();

      await tester.tap(key('auth-google'));
      await tester.pump();
      gate.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();

      expect(gate.locked, isFalse,
          reason: 'the app opened the picker itself');
      expect(gate.obscured, isTrue);

      s.auth.hold!.complete();
      s.auth.hold = null;
      gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(s.auth.googleCalls, 1);
      expect(completions, 1);
      expect(gate.locked, isFalse);
    });

    testWidgets('an email/password sign-in is unaffected: a departure during '
        'it still locks the app (#65 R7)', (tester) async {
      final gateFake = FakeGate();
      final timers = FakeInactivityTimers();
      final gate = GateController(
          gate: gateFake, inactivityTimerFactory: timers.factory);
      addTearDown(gate.dispose);
      gateFake.grantNext = true;
      await gate.unlock();
      timers.fireWithDelay(kSystemUiSettleTimeout);

      final s = await pumpStandalone(tester, gate: gate);
      s.auth.hold = Completer<void>();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'correct horse battery');
      await tester.tap(key('auth-sign-in'));
      await tester.pump();

      gate.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(gate.locked, isTrue,
          reason: 'no system UI was opened, so the policy is unchanged');

      s.auth.hold!.complete();
      s.auth.hold = null;
      await tester.pumpAndSettle();
    });

    testWidgets('a Google session completes the screen exactly once', (
      tester,
    ) async {
      var completions = 0;
      final s = await pumpStandalone(
        tester,
        showGoogle: true,
        embedded: true,
        onSignedIn: () => completions++,
      );
      await tester.tap(key('auth-google'));
      await tester.pumpAndSettle();
      expect(s.auth.googleCalls, 1);
      expect(completions, 1);
      expect(key('auth-error'), findsNothing);
    });

  });


  group('link-delivered sessions on the sign-in screen (#2 U3; AE5, R8)', () {
    testWidgets('the pushed screen pops when a session arrives without any '
        'tap and Settings beneath shows the account', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      // A magic link exchanged elsewhere in the app: only the session
      // event reaches the screen.
      h.signIn();
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsNothing);
      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason: 'exactly one pop: Settings is still the top route',
      );
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(h.auth.signInCalls, isEmpty);
      await h.dispose();
    });

    testWidgets('a password sign-in whose session event fires before the '
        'call returns pops once and leaves the route beneath untouched', (
      tester,
    ) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      await tester.tap(key('account-sign-in'));
      await tester.pumpAndSettle();

      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'correct horse battery');
      h.auth.hold = Completer<void>();
      await tester.tap(key('auth-sign-in'));
      await tester.pump();
      expect(key('auth-pending'), findsOneWidget);

      // gotrue's onAuthStateChange lands before signInWithPassword returns.
      h.signIn(id: 'user-a@b.c');
      await tester.pump();
      h.auth.hold!.complete();
      h.auth.hold = null;
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsNothing);
      expect(
        find.byType(SettingsScreen),
        findsOneWidget,
        reason: 'a second pop would have removed Settings too',
      );
      expect(
        find.text('Profiles'),
        findsNothing,
        reason: 'the picker under Settings must not be exposed',
      );
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(h.auth.signInCalls.single.email, 'a@b.c');
      await h.dispose();
    });

    testWidgets('a screen opened while already signed in does not complete '
        'on its initial state, nor on a non-transition notify; only a '
        'signed-out → signed-in transition completes it, once', (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      addTearDown(auth.dispose);
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      var completions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthController>.value(value: controller),
              Provider<SettingsStore>.value(value: _NoopSettings()),
            ],
            child: SignInScreen(
              embedded: true,
              onSignedIn: () => completions++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(completions, 0, reason: 'initial state is not a transition');

      // A controller notify that is not a session transition.
      auth.emitLinkFailure(const AuthFailure.network());
      await tester.pumpAndSettle();
      expect(completions, 0);

      auth.emit(AuthSessionState.signedOut);
      await tester.pumpAndSettle();
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      await tester.pumpAndSettle();
      expect(completions, 1);

      // A duplicate emission after completion changes nothing.
      auth.emit(AuthSessionState.signedOut);
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      await tester.pumpAndSettle();
      expect(completions, 1, reason: 'completes exactly once');
    });
  });

  group('password recovery (AE8, F4)', () {
    testWidgets('latched recovery renders nothing while locked; after unlock '
        'the recovery screen shows before any profile screen; saving calls '
        'updatePassword and returns home', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      await AccountHarness.seedOneProfile(db);
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      auth.latchRecovery();
      final gate = FakeGate(grantNext: false);
      await tester.pumpWidget(
        LunarLogRoot(gate: gate, dbOpener: () async => db, authService: auth),
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(key('lock-screen'), findsOneWidget);
      expect(key('recovery-new-password'), findsNothing);
      expect(find.text('Alice'), findsNothing);
      expect(
        auth.recoveryConsumed,
        0,
        reason: 'consumed only once the gate is unlocked',
      );

      gate.grantNext = true;
      await tester.tap(key('unlock-button'));
      await tester.pump();
      await tester.pumpAndSettle();
      await drainIsolateTraffic(tester);
      expect(key('recovery-new-password'), findsOneWidget);
      expect(
        find.text('Alice'),
        findsNothing,
        reason: 'recovery shows before any profile screen',
      );

      await tester.enterText(key('recovery-new-password'), 'a brand new pass');
      await tester.tap(key('recovery-save'));
      await tester.pumpAndSettle();
      await drainIsolateTraffic(tester);
      expect(auth.updatePasswordCalls, ['a brand new pass']);
      expect(auth.recoveryConsumed, 1);
      expect(key('recovery-new-password'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });

  group('first run (AS1, F1, F3, AE13)', () {
    testWidgets('revised notice, then the account step, then the name form '
        'after "Not now"', (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      expect(find.text(kNoticeText), findsOneWidget);
      expect(key('auth-email'), findsNothing);
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();

      expect(key('auth-email'), findsOneWidget, reason: 'account step');
      expect(find.text('Create profile'), findsNothing);
      await tester.tap(key('first-run-not-now'));
      await tester.pumpAndSettle();
      expect(key('auth-email'), findsNothing);
      expect(find.text('Create profile'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('first-run sign-in on an empty database shows restoring; '
        'the pull delivering one profile lands on the picker with no name '
        'form shown', (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-sign-in'));
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);
      expect(find.text('Create profile'), findsNothing);

      h.engine.emitPhase(SyncPhase.restoring, boundUserId: 'user-a@b.c');
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);

      // The bind-time pull applied one profile, then the cycle finished.
      await AccountHarness.seedOneProfile(h.db);
      h.engine.emitPhase(
        SyncPhase.idle,
        lastSyncAt: DateTime.now().toUtc(),
        boundUserId: 'user-a@b.c',
      );
      await h.settle();
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Create profile'), findsNothing);
      await h.dispose();
    });

    testWidgets('first-run sign-in whose pull finds no profiles falls '
        'through to the name form', (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-sign-in'));
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);

      h.engine.emitPhase(SyncPhase.restoring, boundUserId: 'user-a@b.c');
      await pumpFew(tester);
      h.engine.emitPhase(
        SyncPhase.idle,
        lastSyncAt: DateTime.now().toUtc(),
        boundUserId: 'user-a@b.c',
      );
      await h.settle();
      expect(key('restoring'), findsNothing);
      expect(find.text('Create profile'), findsOneWidget);
      expect(
        key('sync-status'),
        findsOneWidget,
        reason: 'the tile explains the sync state beside the form',
      );
      await h.dispose();
    });

    testWidgets('first-run sign-in whose bind-time restore encounters an error '
        'renders RestoreErrorScreen with a Retry action instead of the name form (Issue #39)',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await tester.enterText(key('auth-email'), 'a@b.c');
      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-sign-in'));
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);

      h.engine.emitPhase(SyncPhase.restoring, boundUserId: 'user-a@b.c');
      await pumpFew(tester);

      // Restore failed with a network or other sync error on empty-but-bound database:
      h.engine.emitPhase(
        SyncPhase.error,
        boundUserId: 'user-a@b.c',
        lastError: SyncErrorKind.network,
      );
      await h.settle();

      // Must show RestoreErrorScreen, NOT the Create profile form!
      expect(key('restoring'), findsNothing);
      expect(key('restore-error'), findsOneWidget);
      expect(find.text('Unable to restore data'), findsOneWidget);
      expect(find.text('Create a profile'), findsNothing);
      expect(key('restore-retry-button'), findsOneWidget);

      // Tapping Retry calls requestSync on the engine
      await tester.tap(key('restore-retry-button'));
      await pumpFew(tester);
      expect(h.engine.requestSyncCalls, 1);

      h.engine.emitPhase(SyncPhase.pushing, boundUserId: 'user-a@b.c');
      await pumpFew(tester);
      expect(key('restore-error'), findsOneWidget,
          reason: 'retry must not expose profile creation while pushing');
      expect(find.text('Create a profile'), findsNothing);

      h.engine.emitPhase(SyncPhase.pulling, boundUserId: 'user-a@b.c');
      await pumpFew(tester);
      expect(key('restore-error'), findsOneWidget,
          reason: 'retry must not expose profile creation while pulling');

      // Transition back to restoring, then restore completes with profile:
      h.engine.emitPhase(SyncPhase.restoring, boundUserId: 'user-a@b.c');
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);
      expect(key('restore-error'), findsNothing);

      await AccountHarness.seedOneProfile(h.db);
      h.engine.emitPhase(
        SyncPhase.idle,
        lastSyncAt: DateTime.now().toUtc(),
        boundUserId: 'user-a@b.c',
      );
      await h.settle();
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);

      await h.dispose();
    });

    testWidgets('the embedded account step advances to restoring when a '
        'session arrives without any tap, and the name form never appears '
        'for an account that holds a profile (#2 U3; R8)', (tester) async {
      final h = AccountHarness(tester);
      await h.pump();
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(key('auth-email'), findsOneWidget, reason: 'account step');

      // A magic link opened on this device: only the session event.
      h.signIn(email: 'a@b.c');
      await pumpFew(tester);
      expect(key('auth-email'), findsNothing);
      expect(key('restoring'), findsOneWidget);
      expect(find.text('Create profile'), findsNothing);
      expect(h.auth.signInCalls, isEmpty);

      h.engine.emitPhase(SyncPhase.restoring, boundUserId: 'u1');
      await pumpFew(tester);
      expect(key('restoring'), findsOneWidget);
      await AccountHarness.seedOneProfile(h.db);
      h.engine.emitPhase(
        SyncPhase.idle,
        lastSyncAt: DateTime.now().toUtc(),
        boundUserId: 'u1',
      );
      await h.settle();
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Create profile'), findsNothing);
      await h.dispose();
    });
  });

  group('account mismatch (AE5, F7)', () {
    testWidgets('renders both actions; switch signs out locally only and '
        'keeps the data; remove resets and lands on first-run', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn(id: 'u2');
      h.engine.emitPhase(SyncPhase.accountMismatch, boundUserId: 'u1');
      await tester.pumpAndSettle();
      expect(key('mismatch-switch-account'), findsOneWidget);
      expect(key('mismatch-remove-data'), findsOneWidget);
      expect(find.textContaining('Hide My Email'), findsOneWidget);
      expect(
        find.textContaining('different Google account'),
        findsOneWidget,
        reason: '#2 U5 (AE7): the Google case is named too',
      );
      expect(
        find.textContaining('Nothing has been uploaded or changed'),
        findsOneWidget,
      );
      expect(find.text('Alice'), findsNothing);

      await tester.tap(key('mismatch-switch-account'));
      await tester.pumpAndSettle();
      expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
      expect(h.resets, 0);
      expect(
        (await DriftProfilesRepository(h.db.storage).list()).length,
        1,
        reason: 'data untouched',
      );
      h.engine.emitPhase(SyncPhase.idle);
      await h.settle();
      expect(find.text('Alice'), findsOneWidget);

      // Again, this time removing the device's data.
      h.signIn(id: 'u2');
      h.engine.emitPhase(SyncPhase.accountMismatch, boundUserId: 'u1');
      await tester.pumpAndSettle();
      await tester.tap(key('mismatch-remove-data'));
      await tester.pumpAndSettle();
      await tester.tap(key('mismatch-remove-confirm'));
      await tester.pumpAndSettle();
      expect(h.resets, 1);
      h.engine.emitPhase(SyncPhase.idle);
      await h.settle();
      expect(find.text(kNoticeText), findsOneWidget, reason: 'first-run');
      await h.dispose();
    });

    testWidgets('switching accounts clears the process-global breadcrumb '
        'log even though it is a local sign-out and never touches '
        'resetDevice', (tester) async {
      addTearDown(defaultBreadcrumbLog.clear);
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn(id: 'u2');
      h.engine.emitPhase(SyncPhase.accountMismatch, boundUserId: 'u1');
      await tester.pumpAndSettle();
      defaultBreadcrumbLog.record('nav', 'overview');
      expect(defaultBreadcrumbLog.snapshot(), isNotEmpty);

      await tester.tap(key('mismatch-switch-account'));
      await tester.pumpAndSettle();

      expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
      expect(h.resets, 0, reason: 'this path never calls resetDevice');
      expect(defaultBreadcrumbLog.snapshot(), isEmpty);
      await h.dispose();
    });

    testWidgets('switching accounts clears breadcrumbs even when the '
        'local sign-out reports a failure (the local session is gone '
        'regardless, per the service contract)', (tester) async {
      addTearDown(defaultBreadcrumbLog.clear);
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn(id: 'u2');
      h.engine.emitPhase(SyncPhase.accountMismatch, boundUserId: 'u1');
      await tester.pumpAndSettle();
      defaultBreadcrumbLog.record('nav', 'overview');
      h.auth.nextFailure = const AuthFailure.network();

      await tester.tap(key('mismatch-switch-account'));
      await tester.pumpAndSettle();

      expect(defaultBreadcrumbLog.snapshot(), isEmpty);
      await h.dispose();
    });
  });

  group('sign-in methods and adding one (#2 U5; AE6, R9, R10)', () {
    testWidgets('providers [email] renders the methods subtitle and the '
        'add-Google action; [email, google] hides it', (tester) async {
      await pumpSection(tester, providers: ['email'], showAddGoogle: true);
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-add-google'), findsOneWidget);
      expect(
        key('account-add-apple'),
        findsNothing,
        reason: 'no iOS override on the test platform',
      );
      expect(key('account-link-error'), findsNothing);

      await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      expect(find.text('Sign-in methods: Email, Google'), findsOneWidget);
      expect(key('account-add-google'), findsNothing);
    });

    testWidgets('the null Google default hides the action in an '
        'unconfigured build; an empty providers list omits the subtitle', (
      tester,
    ) async {
      await pumpSection(tester, providers: ['email']);
      expect(key('account-add-google'), findsNothing);
      await pumpSection(tester, providers: []);
      expect(find.textContaining('Sign-in methods'), findsNothing);
    });

    testWidgets('account-add-apple renders only with the iOS override and '
        'when apple is absent', (tester) async {
      await pumpSection(tester, providers: ['email'], showAddApple: true);
      expect(key('account-add-apple'), findsOneWidget);
      await pumpSection(
        tester,
        providers: ['email', 'apple'],
        showAddApple: true,
      );
      expect(find.text('Sign-in methods: Email, Apple'), findsOneWidget);
      expect(key('account-add-apple'), findsNothing);
    });

    testWidgets('#65 AE5: adding a method does not re-lock the app when the '
        'picker reports a departure, and still covers the content',
        (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
      );
      final gate = s.gateController;
      // pumpSection's gate requires unlock, so it starts locked.
      s.gate.grantNext = true;
      await gate.unlock();
      gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(gate.locked, isFalse);
      s.auth.hold = Completer<void>();

      await tester.tap(key('account-add-google'));
      await tester.pump();
      // The Google picker takes over: on iOS an ASWebAuthenticationSession,
      // on Android a Credential Manager sheet.
      gate.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();

      expect(gate.locked, isFalse,
          reason: 'the app opened this picker itself; landing the operator '
              'on the lock screen mid-sign-in is the #65 complaint');
      expect(gate.obscured, isTrue,
          reason: 'covered throughout — the window never suppresses that');

      s.auth.hold!.complete();
      s.auth.hold = null;
      gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(s.auth.linkCalls, ['google']);
      expect(gate.locked, isFalse);
    });

    testWidgets('AE6: a granted re-auth calls linkGoogle and the subtitle '
        'gains Google', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
      );
      await tester.tap(key('account-add-google'));
      await tester.pumpAndSettle();
      expect(s.gate.requests, 1, reason: 'the device credential came first');
      expect(s.auth.linkCalls, ['google']);
      expect(find.text('Sign-in methods: Email, Google'), findsOneWidget);
      expect(key('account-add-google'), findsNothing);
      expect(key('account-link-error'), findsNothing);
    });

    testWidgets('AE6: a declined re-auth never calls linkGoogle and shows '
        'no copy', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
        grantReauth: false,
      );
      await tester.tap(key('account-add-google'));
      await tester.pumpAndSettle();
      expect(s.gate.requests, 1);
      expect(s.auth.linkCalls, isEmpty);
      expect(key('account-link-error'), findsNothing);
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-add-google'), findsOneWidget);
    });

    testWidgets('AE6: identityTaken shows its copy in account-link-error '
        'and leaves the subtitle unchanged', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
      );
      s.auth.nextFailure = const AuthFailure.identityTaken();
      await tester.tap(key('account-add-google'));
      await tester.pumpAndSettle();
      expect(s.auth.linkCalls, ['google']);
      expect(key('account-link-error'), findsOneWidget);
      expect(
        find.descendant(
          of: key('account-link-error'),
          matching: find.text(
            authFailureCopy(const AuthFailure.identityTaken()),
          ),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-add-google'), findsOneWidget);
    });

    testWidgets('AE6: a second tap while the first link call is held does '
        'not call linkGoogle again', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
      );
      s.auth.hold = Completer<void>();
      await tester.tap(key('account-add-google'));
      await pumpFew(tester);
      expect(s.auth.linkCalls, ['google']);
      expect(
        find.descendant(
          of: key('account-add-google'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      await tester.tap(key('account-add-google'));
      await pumpFew(tester);
      expect(s.auth.linkCalls, ['google'], reason: 'busy: no second call');
      expect(s.gate.requests, 1, reason: 'busy: no second prompt');

      s.auth.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sign-in methods: Email, Google'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the Apple action links through the same re-auth path', (
      tester,
    ) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddApple: true,
      );
      await tester.tap(key('account-add-apple'));
      await tester.pumpAndSettle();
      expect(s.gate.requests, 1);
      expect(s.auth.linkCalls, ['apple']);
      expect(find.text('Sign-in methods: Email, Apple'), findsOneWidget);
    });

    testWidgets('with no GateController provided, tapping the action does '
        'nothing: no link call and no crash', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
        provideGate: false,
      );
      await tester.tap(key('account-add-google'));
      await tester.pumpAndSettle();
      expect(s.gate.requests, 0, reason: 'never reached: no gate to ask');
      expect(s.auth.linkCalls, isEmpty);
      expect(key('account-link-error'), findsNothing);
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-add-google'), findsOneWidget);
    });

    testWidgets('a non-AuthFailure error from the link call still surfaces '
        'the generic copy in account-link-error', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email'],
        showAddGoogle: true,
      );
      s.auth.googleUnsupported = true;
      await tester.tap(key('account-add-google'));
      await tester.pumpAndSettle();
      expect(s.gate.requests, 1, reason: 'the device credential came first');
      expect(
        s.auth.linkCalls,
        isEmpty,
        reason: 'the fake throws before recording a link call',
      );
      expect(key('account-link-error'), findsOneWidget);
      expect(
        find.descendant(
          of: key('account-link-error'),
          matching: find.text(authFailureCopy(const AuthFailure.unknown())),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-add-google'), findsOneWidget);
    });
  });

  group('removing a sign-in method (#31)', () {
    testWidgets('AE1: [email] renders no remove tile; [email, google] '
        'renders account-remove-google and no account-remove-email', (
      tester,
    ) async {
      await pumpSection(tester, providers: ['email'], showAddGoogle: true);
      expect(key('account-remove-email'), findsNothing);
      expect(key('account-remove-google'), findsNothing);

      await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      expect(key('account-remove-google'), findsOneWidget);
      expect(key('account-remove-email'), findsNothing);
      expect(key('account-add-google'), findsNothing);
    });

    testWidgets('both remove tiles render for [email, google, apple] and '
        'neither add tile does', (tester) async {
      await pumpSection(
        tester,
        providers: ['email', 'google', 'apple'],
        showAddGoogle: true,
        showAddApple: true,
      );
      expect(key('account-remove-google'), findsOneWidget);
      expect(key('account-remove-apple'), findsOneWidget);
      expect(key('account-add-google'), findsNothing);
      expect(key('account-add-apple'), findsNothing);
    });

    testWidgets('a provider-only account (no email identity) renders no '
        'remove tile: the last method is pinned regardless of which '
        'provider it is', (tester) async {
      await pumpSection(tester, providers: ['google'], showAddGoogle: true);
      expect(key('account-remove-google'), findsNothing);
    });

    testWidgets('AE2: cancelling the confirmation dialog never calls '
        'reauthenticate or unlinkProvider', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Google?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(s.gate.requests, 0);
      expect(s.auth.unlinkCalls, isEmpty);
      expect(key('account-link-error'), findsNothing);
      expect(key('account-remove-google'), findsOneWidget);
    });

    testWidgets('AE3: confirming with a declined credential never calls '
        'unlinkProvider and shows no copy', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
        grantReauth: false,
      );
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pumpAndSettle();

      expect(s.gate.requests, 1);
      expect(s.auth.unlinkCalls, isEmpty);
      expect(key('account-link-error'), findsNothing);
      expect(key('account-remove-google'), findsOneWidget);
    });

    testWidgets('AE4: confirming with a granted credential calls '
        'unlinkProvider once, updates the subtitle, and brings back Add', (
      tester,
    ) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pumpAndSettle();

      expect(s.gate.requests, 1, reason: 'the device credential came first');
      expect(s.auth.unlinkCalls, ['google']);
      expect(find.text('Sign-in methods: Email'), findsOneWidget);
      expect(key('account-remove-google'), findsNothing);
      expect(key('account-add-google'), findsOneWidget);
      expect(key('account-link-error'), findsNothing);
    });

    testWidgets('AE5: lastSignInMethod renders its copy, leaves the '
        'subtitle unchanged, and re-enables the tile', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      s.auth.nextFailure = const AuthFailure.lastSignInMethod();
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pumpAndSettle();

      expect(s.auth.unlinkCalls, ['google']);
      expect(
        find.descendant(
          of: key('account-link-error'),
          matching:
              find.text(authFailureCopy(const AuthFailure.lastSignInMethod())),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Sign-in methods: Email, Google'), findsOneWidget);
      expect(key('account-remove-google'), findsOneWidget);
    });

    testWidgets('a network failure renders its copy; a non-AuthFailure '
        'error renders the unknown copy', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      s.auth.nextFailure = const AuthFailure.network();
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: key('account-link-error'),
          matching: find.text(authFailureCopy(const AuthFailure.network())),
          matchRoot: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a non-AuthFailure error from the unlink call still surfaces '
        'the generic copy in account-link-error', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      s.auth.unlinkThrowsGeneric = true;
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pumpAndSettle();

      expect(s.gate.requests, 1, reason: 'the device credential came first');
      expect(
        s.auth.unlinkCalls,
        isEmpty,
        reason: 'the fake throws before recording an unlink call',
      );
      expect(key('account-link-error'), findsOneWidget);
      expect(
        find.descendant(
          of: key('account-link-error'),
          matching: find.text(authFailureCopy(const AuthFailure.unknown())),
          matchRoot: true,
        ),
        findsOneWidget,
      );
      expect(find.text('Sign-in methods: Email, Google'), findsOneWidget);
      expect(key('account-remove-google'), findsOneWidget);
    });

    testWidgets('a second tap while the first unlinkProvider call is held '
        'does nothing, and disables the sibling Add/Remove tiles', (
      tester,
    ) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google', 'apple'],
        showAddGoogle: true,
        showAddApple: true,
      );
      s.auth.hold = Completer<void>();
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await pumpFew(tester);
      expect(s.auth.unlinkCalls, ['google']);
      expect(
        find.descendant(
          of: key('account-remove-google'),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      await tester.tap(key('account-remove-apple'));
      await pumpFew(tester);
      expect(s.auth.unlinkCalls, ['google'],
          reason: 'busy: the sibling tile is disabled');
      expect(s.gate.requests, 1);

      s.auth.hold!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Sign-in methods: Email, Apple'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('with no GateController provided, tapping Remove does '
        'nothing: no dialog, no reauthenticate, and no unlinkProvider call', (
      tester,
    ) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
        provideGate: false,
      );
      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Google?'), findsNothing);
      expect(s.gate.requests, 0);
      expect(s.auth.unlinkCalls, isEmpty);
      expect(key('account-remove-google'), findsOneWidget);
    });

    testWidgets('AE6: the whole remove ceremony runs inside one '
        'duringSystemUi window: a background lifecycle event during the '
        'credential prompt does not re-lock the app', (tester) async {
      final s = await pumpSection(
        tester,
        providers: ['email', 'google'],
        showAddGoogle: true,
      );
      final gate = s.gateController;
      s.gate.grantNext = true;
      await gate.unlock();
      gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(gate.locked, isFalse);
      s.auth.hold = Completer<void>();

      await tester.tap(key('account-remove-google'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('account-remove-confirm')));
      await tester.pump();
      gate.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();

      expect(gate.locked, isFalse,
          reason: 'the app opened this ceremony itself');
      expect(gate.obscured, isTrue);

      s.auth.hold!.complete();
      s.auth.hold = null;
      gate.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(s.auth.unlinkCalls, ['google']);
      expect(gate.locked, isFalse);
    });
  });

  group('upload consent (R14, AS4)', () {
    testWidgets('renders counts and the duplicate-profile sentence; upload '
        'confirms; not now leaves the tappable tile that reopens it', (
      tester,
    ) async {
      final h = AccountHarness(tester);
      await h.pump(
        seed: (db) async {
          await AccountHarness.seedOneProfile(db);
          final profile = (await DriftProfilesRepository(
            db.storage,
          ).list()).single;
          final entries = DriftDayEntriesRepository(db.storage);
          await entries.save(
            DayEntry(
              id: '',
              profileId: profile.id,
              localDate: LocalDate(2026, 8, 1),
              tz: 'UTC',
              flow: FlowLevel.medium,
              tags: const [],
              updatedAt: DateTime.utc(2026, 8, 1),
            ),
          );
          await entries.save(
            DayEntry(
              id: '',
              profileId: profile.id,
              localDate: LocalDate(2026, 8, 2),
              tz: 'UTC',
              flow: FlowLevel.light,
              tags: const [],
              updatedAt: DateTime.utc(2026, 8, 2),
            ),
          );
        },
      );
      h.signIn();
      h.engine.emitPhase(SyncPhase.awaitingUploadConsent, dirtyCount: 3);
      await h.settle();
      expect(key('consent-upload'), findsOneWidget);
      expect(find.textContaining('1 profile'), findsOneWidget);
      expect(find.textContaining('2 entries'), findsOneWidget);
      expect(find.textContaining('two profiles'), findsOneWidget);

      await tester.tap(key('consent-upload'));
      await tester.pumpAndSettle();
      expect(h.engine.confirmUploadCalls, 1);

      // Decline: the home shows again with the pending tile.
      await tester.tap(key('consent-not-now'));
      await h.settle();
      expect(key('consent-upload'), findsNothing);
      expect(find.text('Alice'), findsOneWidget);
      await h.openSettings();
      expect(find.text(kUploadPendingCopy), findsOneWidget);
      await tester.tap(key('sync-status'));
      await h.settle();
      expect(key('consent-upload'), findsOneWidget);
      await tester.tap(key('consent-upload'));
      await tester.pumpAndSettle();
      expect(h.engine.confirmUploadCalls, 2);
      await h.dispose();
    });
  });

  group('sync status and Sync now (Approach 7)', () {
    testWidgets('Sync now calls requestSync, is disabled while a cycle runs, '
        'and the tile reads Syncing… then Up to date', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn();
      h.engine.emitPhase(SyncPhase.idle, boundUserId: 'u1');
      await h.openSettings();
      await h.settle();

      await tester.tap(key('account-sync-now'));
      await tester.pump();
      expect(h.engine.requestSyncCalls, 1);
      h.engine.emitPhase(SyncPhase.pushing);
      await pumpFew(tester);
      expect(find.text('Syncing…'), findsOneWidget);
      expect(tester.widget<ListTile>(key('account-sync-now')).enabled, isFalse);

      h.engine.emitPhase(SyncPhase.idle, lastSyncAt: DateTime.now().toUtc());
      await tester.pumpAndSettle();
      expect(find.textContaining('Up to date'), findsOneWidget);
      expect(tester.widget<ListTile>(key('account-sync-now')).enabled, isTrue);

      h.engine.emitPhase(SyncPhase.error, lastError: SyncErrorKind.auth);
      await tester.pumpAndSettle();
      expect(find.text('Sign in again to sync'), findsOneWidget);

      h.engine.emitPhase(
        SyncPhase.idle,
        lastError: SyncErrorKind.none,
        rejectedCount: 2,
      );
      await tester.pumpAndSettle();
      expect(find.text('Some entries could not be uploaded'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('the picker shows the status glyph only with a controller', (
      tester,
    ) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile, withEngine: false);
      expect(find.byType(SyncStatusGlyph), findsNothing);
      await h.dispose();

      final h2 = AccountHarness(tester);
      await h2.pump(seed: AccountHarness.seedOneProfile);
      h2.signIn();
      h2.engine.emitPhase(SyncPhase.pulling);
      await pumpFew(tester);
      expect(find.byType(SyncStatusGlyph), findsOneWidget);
      expect(find.byTooltip('Syncing…'), findsOneWidget);
      await h2.dispose();
    });

    test('relative time copy', () {
      final now = DateTime.utc(2026, 9, 2, 12);
      expect(
        formatRelative(now.subtract(const Duration(seconds: 30)), now),
        'just now',
      );
      expect(
        formatRelative(now.subtract(const Duration(minutes: 5)), now),
        '5 min ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(hours: 3)), now),
        '3 h ago',
      );
      expect(
        formatRelative(now.subtract(const Duration(days: 2)), now),
        '2 d ago',
      );
    });

    group('syncStatusCopy branches not reached through the widget tree', () {
      final now = DateTime.utc(2026, 9, 2, 12);

      String copy({
        SyncSnapshot? snapshot,
        AuthSessionState? authState,
        bool webSyncOff = false,
      }) => syncStatusCopy(
        snapshot: snapshot,
        authState: authState,
        now: now,
        webSyncOff: webSyncOff,
      );

      test('webSyncOff wins over every other tier, including an awaiting '
          'confirmation email', () {
        expect(
          syncStatusCopy(
            snapshot: null,
            authState: null,
            awaitingConfirmationEmail: 'a@b.c',
            now: now,
            webSyncOff: true,
          ),
          kWebSyncOffCopy,
        );
      });

      test('a null snapshot (sync unconfigured for this build) shows its '
          'own copy', () {
        expect(
          copy(snapshot: null, authState: AuthSessionState.signedIn),
          'Sync is not available in this build',
        );
      });

      test('error phase: network and other/none each get their own copy '
          '(auth is covered by the widget tree)', () {
        expect(
          copy(
            snapshot: const SyncSnapshot(
              phase: SyncPhase.error,
              lastError: SyncErrorKind.network,
            ),
            authState: AuthSessionState.signedIn,
          ),
          'Could not reach the server — will retry',
        );
        expect(
          copy(
            snapshot: const SyncSnapshot(
              phase: SyncPhase.error,
              lastError: SyncErrorKind.other,
            ),
            authState: AuthSessionState.signedIn,
          ),
          'Sync failed — will retry',
        );
        expect(
          copy(
            snapshot: const SyncSnapshot(
              phase: SyncPhase.error,
              lastError: SyncErrorKind.none,
            ),
            authState: AuthSessionState.signedIn,
          ),
          'Sync failed — will retry',
        );
      });

      test('an expired session outside the error phase asks to sign in '
          'again, same copy as an auth error', () {
        expect(
          copy(
            snapshot: const SyncSnapshot(phase: SyncPhase.idle),
            authState: AuthSessionState.expired,
          ),
          kSignInAgainCopy,
        );
      });

      test('accountMismatch and paused each get their own resting copy', () {
        expect(
          copy(
            snapshot: const SyncSnapshot(phase: SyncPhase.accountMismatch),
            authState: AuthSessionState.signedIn,
          ),
          'Signed in as a different account',
        );
        expect(
          copy(
            snapshot: const SyncSnapshot(phase: SyncPhase.paused),
            authState: AuthSessionState.signedIn,
          ),
          'Sync paused',
        );
      });

      test('signed out with no rejected rows reads "Not signed in", ahead '
          'of the last-synced copy', () {
        expect(
          copy(
            snapshot: SyncSnapshot(
              phase: SyncPhase.idle,
              lastSyncAt: now.toUtc(),
            ),
            authState: AuthSessionState.signedOut,
          ),
          'Not signed in',
        );
      });

      test('signed in, idle, never synced reads "Not synced yet"', () {
        expect(
          copy(
            snapshot: const SyncSnapshot(phase: SyncPhase.idle),
            authState: AuthSessionState.signedIn,
          ),
          'Not synced yet',
        );
      });

      test('passwordRecovery counts as signed in for the resting states, '
          'same as signedIn', () {
        expect(
          copy(
            snapshot: const SyncSnapshot(phase: SyncPhase.idle),
            authState: AuthSessionState.passwordRecovery,
          ),
          'Not synced yet',
        );
      });
    });
  });

  group('sign out (R16, F6, AS3)', () {
    testWidgets('dirty rows (a tombstone-only set included) show the '
        'two-choice dialog; Sync now requests a cycle; discard resets', (
      tester,
    ) async {
      final h = AccountHarness(tester);
      await h.pump(
        seed: (db) async {
          final profiles = DriftProfilesRepository(db.storage);
          final p = await profiles.create(displayName: 'Alice', isMinor: false);
          final q = await profiles.create(displayName: 'Gone', isMinor: false);
          await profiles.delete(q.id);
          await db.storage.markPushed(
            table: SyncTable.profiles,
            id: p.id,
            localRevAtPush: (await db.storage.readDirtyProfiles())
                .firstWhere((r) => r.id == p.id)
                .localRev,
          );
        },
      );
      // Only the tombstone is dirty now — still a reason to warn.
      expect(await h.db.storage.dirtyCount(), 1);
      h.signIn();
      h.engine.emitPhase(SyncPhase.idle, boundUserId: 'u1', dirtyCount: 1);
      await h.openSettings();
      await h.settle();

      await tester.tap(key('account-sign-out'));
      await tester.pumpAndSettle();
      expect(key('account-sign-out-sync'), findsOneWidget);
      expect(key('account-sign-out-discard'), findsOneWidget);
      await tester.tap(key('account-sign-out-sync'));
      await tester.pumpAndSettle();
      expect(h.engine.requestSyncCalls, 1);
      expect(h.resets, 0);

      await tester.tap(key('account-sign-out'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-sign-out-discard'));
      await h.settle();
      expect(h.resets, 1);
      expect(find.text(kNoticeText), findsOneWidget, reason: 'first-run');
      await h.dispose();
    });

    testWidgets('zero dirty rows: single confirm naming the consequence, '
        'reset, first-run, signOutCalls == [local]', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn();
      h.engine.emitPhase(SyncPhase.idle, boundUserId: 'u1', dirtyCount: 0);
      await h.openSettings();
      await h.settle();

      await tester.tap(key('account-sign-out'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This removes the data from this device. It stays in your account.',
        ),
        findsOneWidget,
      );
      expect(key('account-sign-out-discard'), findsNothing);
      await tester.tap(key('account-sign-out-confirm'));
      await h.settle();
      expect(h.resets, 1);
      expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
      expect(find.text(kNoticeText), findsOneWidget);
      await h.dispose();
    });

    testWidgets('Sign out everywhere states the expiry caveat, calls '
        'signOut(global), then resets', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn();
      h.engine.emitPhase(SyncPhase.idle, boundUserId: 'u1', dirtyCount: 0);
      await h.openSettings();
      await h.settle();

      await tester.tap(key('account-sign-out-everywhere'));
      await tester.pumpAndSettle();
      expect(find.textContaining('10 minutes'), findsOneWidget);
      await tester.tap(key('account-sign-out-everywhere-confirm'));
      await h.settle();
      expect(h.auth.signOutCalls.first, AuthSignOutScope.global);
      expect(h.resets, 1);
      expect(find.text(kNoticeText), findsOneWidget);
      await h.dispose();
    });

    testWidgets('Sign out everywhere when global sign out fails still runs '
        'reset and shows snackbar', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn();
      h.engine.emitPhase(SyncPhase.idle, boundUserId: 'u1', dirtyCount: 0);
      await h.openSettings();
      await h.settle();

      h.auth.nextFailure = const AuthNetworkFailure();

      await tester.tap(key('account-sign-out-everywhere'));
      await tester.pumpAndSettle();
      await tester.tap(key('account-sign-out-everywhere-confirm'));
      await h.settle();

      expect(h.auth.signOutCalls.first, AuthSignOutScope.global);
      expect(h.resets, 1);
      expect(find.textContaining('Other devices were not signed out.'),
          findsOneWidget);
      await h.dispose();
    });
  });

  group('no auth service', () {
    testWidgets('the Account section is absent', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      await AccountHarness.seedOneProfile(db);
      await tester.pumpWidget(LunarLogApp(db: db));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(key('account-sign-in'), findsNothing);
      expect(find.text('Account'), findsNothing);
      expect(key('relock-toggle'), findsOneWidget);
      expect(find.byType(ProfileHomeGate), findsNothing);
      // Issue #17 R11: an unconfigured build shows neither the export nor
      // the delete tile - they render only inside the signed-in block this
      // whole section never reaches here.
      expect(key('account-export'), findsNothing);
      expect(key('account-delete'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });

  group('export and delete tiles (Issue #17 U6; R11)', () {
    testWidgets('signed out: neither tile renders', (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      await h.openSettings();
      expect(key('account-export'), findsNothing);
      expect(key('account-delete'), findsNothing);
      await h.dispose();
    });

    testWidgets('signed in with no AccountDeletionService: export renders, '
        'delete does not (export needs no deletion collaborator)',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn();
      await h.openSettings();
      await h.settle();
      expect(key('account-export'), findsOneWidget);
      expect(key('account-delete'), findsNothing);
      await h.dispose();
    });
  });
}

/// A standalone [AccountSection] over a fake service and a real
/// [GateController] whose [FakeGate] answers the re-auth prompt (#2 U5;
/// KTD5), so the linking scenarios pump the section without the app.
class StandaloneSection {
  StandaloneSection(this.auth, this.controller, this.gate, this.gateController);
  final FakeAuthService auth;
  final AuthController controller;
  final FakeGate gate;

  /// The real [GateController] in the tree, so a test can drive lifecycle
  /// through it and read the lock state (#65 U2).
  final GateController gateController;
}

Future<StandaloneSection> pumpSection(
  WidgetTester tester, {
  List<String> providers = const ['email'],
  bool? showAddGoogle,
  bool? showAddApple,
  bool grantReauth = true,
  bool provideGate = true,
}) async {
  final auth = FakeAuthService();
  addTearDown(auth.dispose);
  auth.emit(
    AuthSessionState.signedIn,
    user: AuthUser(id: 'u1', email: 'a@b.c'),
  );
  auth.providers = providers;
  final controller = AuthController(authService: auth);
  addTearDown(controller.dispose);
  final gate = FakeGate(grantNext: grantReauth);
  // Fake timers: unlocking this gate (or closing a system-UI window) arms
  // the inactivity countdown, which would otherwise leave a real 2-minute
  // Timer pending past the end of the test.
  final gateController = GateController(
      gate: gate, inactivityTimerFactory: FakeInactivityTimers().factory);
  addTearDown(gateController.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: controller),
          if (provideGate)
            ChangeNotifierProvider<GateController>.value(value: gateController),
          Provider<SettingsStore>.value(value: _NoopSettings()),
        ],
        child: Scaffold(
          body: AccountSection(
            showAddGoogle: showAddGoogle,
            showAddApple: showAddApple,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return StandaloneSection(auth, controller, gate, gateController);
}

/// A standalone [SignInScreen] over a fake service and an in-memory
/// settings store (#2 U4): the harness builds the screen without provider
/// overrides, so the Google and pending-email scenarios pump it directly.
class StandaloneSignIn {
  StandaloneSignIn(this.auth, this.controller, this.settings);
  final FakeAuthService auth;
  final AuthController controller;
  final MemorySettings settings;
}

Future<StandaloneSignIn> pumpStandalone(
  WidgetTester tester, {
  bool? showApple,
  bool? showGoogle,
  bool embedded = false,
  VoidCallback? onSignedIn,
  Map<String, String>? seed,
  GateController? gate,
}) async {
  final auth = FakeAuthService();
  addTearDown(auth.dispose);
  final controller = AuthController(authService: auth);
  addTearDown(controller.dispose);
  final settings = MemorySettings(seed);
  await tester.pumpWidget(
    MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: controller),
          if (gate != null)
            ChangeNotifierProvider<GateController>.value(value: gate),
          Provider<SettingsStore>.value(value: settings),
        ],
        child: SignInScreen(
          showApple: showApple,
          showGoogle: showGoogle,
          embedded: embedded,
          onSignedIn: onSignedIn,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return StandaloneSignIn(auth, controller, settings);
}

class MemorySettings implements SettingsStore {
  MemorySettings([Map<String, String>? seed]) : values = {...?seed};

  final Map<String, String> values;
  final _changes = StreamController<String>.broadcast();

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
    _changes.add(key);
  }

  @override
  Stream<String?> watch(String key) async* {
    yield values[key];
    await for (final changed in _changes.stream) {
      if (changed == key) yield values[key];
    }
  }
}

class _NoopSettings implements SettingsStore {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Stream<String?> watch(String key) => Stream.value(null);
}
