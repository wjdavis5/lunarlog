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
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/sign_in_screen.dart';
import 'package:lunarlog/ui/account/sync_status_tile.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';
import '../support/pump_helpers.dart';
import 'gate_test.dart' show FakeGate;
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
    await tester.pumpWidget(LunarLogApp(
      db: db,
      authService: auth,
      syncEngine: withEngine ? engine : null,
      // Mirrors the root's reset (test/ui/device_reset_test.dart proves
      // the real order): local wipe first, server sign-out last.
      resetDevice: () async {
        resets++;
        await db.wipeAllData();
        try {
          await auth.signOut(scope: AuthSignOutScope.local);
        } on AuthFailure {
          // best effort
        }
      },
    ));
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
    auth.emit(AuthSessionState.signedIn, user: AuthUser(id: id, email: email));
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
          tester.widget<FilledButton>(key('auth-sign-in')).onPressed, isNull,
          reason: 'the action is disabled while the call is in flight');
      expect(key('auth-error'), findsNothing);

      h.auth.nextFailure = const AuthFailure.wrongPassword();
      h.auth.hold!.complete();
      h.auth.hold = null;
      await tester.pumpAndSettle();
      expect(key('auth-pending'), findsNothing);
      expect(key('auth-error'), findsOneWidget);
      expect(find.textContaining('was not accepted'), findsOneWidget);
      expect(tester.widget<Text>(key('auth-error')).data, isNot(contains('a@b.c')),
          reason: 'the error never echoes the email');
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
      expect(tester.widget<Text>(key('auth-error')).data,
          contains('12 characters'));
      expect(h.auth.signUpCalls, isEmpty);

      await tester.enterText(key('auth-password'), 'twelve chars!');
      await tester.tap(key('auth-create-account'));
      await tester.pumpAndSettle();
      expect(h.auth.signUpCalls.single.email, 'new@b.c');
      expect(key('auth-error'), findsNothing);
      expect(find.textContaining('open the link on this device'),
          findsOneWidget);
      final store = DriftSettingsStore(h.db.storage);
      expect(await store.get(SettingsKeys.awaitingConfirmationEmail),
          'new@b.c');

      // Back in Settings the status tile shows the waiting copy.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await h.settle();
      expect(find.text(kWaitingCopy), findsOneWidget);

      // The confirmation link produced a session: the setting clears.
      h.signIn(email: 'new@b.c');
      await h.settle();
      expect(find.text(kWaitingCopy), findsNothing);
      expect(await store.get(SettingsKeys.awaitingConfirmationEmail),
          anyOf(isNull, isEmpty));
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
      expect(key('auth-apple'), findsNothing,
          reason: 'the test platform is not iOS');

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
      await tester.pumpWidget(MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: controller),
            Provider<SettingsStore>.value(value: _NoopSettings()),
          ],
          child: const SignInScreen(showApple: true),
        ),
      ));
      await tester.pumpAndSettle();
      expect(key('auth-apple'), findsOneWidget);
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
      expect(find.byType(SettingsScreen), findsOneWidget,
          reason: 'exactly one pop: Settings is still the top route');
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(h.auth.signInCalls, isEmpty);
      await h.dispose();
    });

    testWidgets('a password sign-in whose session event fires before the '
        'call returns pops once and leaves the route beneath untouched',
        (tester) async {
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
      expect(find.byType(SettingsScreen), findsOneWidget,
          reason: 'a second pop would have removed Settings too');
      expect(find.text('Profiles'), findsNothing,
          reason: 'the picker under Settings must not be exposed');
      expect(find.text('Signed in as a@b.c'), findsOneWidget);
      expect(h.auth.signInCalls.single.email, 'a@b.c');
      await h.dispose();
    });

    testWidgets('a screen opened while already signed in does not complete '
        'on its initial state, nor on a non-transition notify; only a '
        'signed-out → signed-in transition completes it, once',
        (tester) async {
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      addTearDown(auth.dispose);
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);
      var completions = 0;
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.pumpAndSettle();
      expect(completions, 0, reason: 'initial state is not a transition');

      // A controller notify that is not a session transition.
      auth.emitLinkFailure(const AuthFailure.network());
      await tester.pumpAndSettle();
      expect(completions, 0);

      auth.emit(AuthSessionState.signedOut);
      await tester.pumpAndSettle();
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'u1', email: 'a@b.c'));
      await tester.pumpAndSettle();
      expect(completions, 1);

      // A duplicate emission after completion changes nothing.
      auth.emit(AuthSessionState.signedOut);
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'u1', email: 'a@b.c'));
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
      await tester.pumpWidget(LunarLogRoot(
        gate: gate,
        dbOpener: () async => db,
        authService: auth,
      ));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(key('lock-screen'), findsOneWidget);
      expect(key('recovery-new-password'), findsNothing);
      expect(find.text('Alice'), findsNothing);
      expect(auth.recoveryConsumed, 0,
          reason: 'consumed only once the gate is unlocked');

      gate.grantNext = true;
      await tester.tap(key('unlock-button'));
      await tester.pump();
      await tester.pumpAndSettle();
      await drainIsolateTraffic(tester);
      expect(key('recovery-new-password'), findsOneWidget);
      expect(find.text('Alice'), findsNothing,
          reason: 'recovery shows before any profile screen');

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
      h.engine.emitPhase(SyncPhase.idle,
          lastSyncAt: DateTime.now().toUtc(), boundUserId: 'user-a@b.c');
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
      h.engine.emitPhase(SyncPhase.idle,
          lastSyncAt: DateTime.now().toUtc(), boundUserId: 'user-a@b.c');
      await h.settle();
      expect(key('restoring'), findsNothing);
      expect(find.text('Create profile'), findsOneWidget);
      expect(key('sync-status'), findsOneWidget,
          reason: 'the tile explains the sync state beside the form');
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
      h.engine.emitPhase(SyncPhase.idle,
          lastSyncAt: DateTime.now().toUtc(), boundUserId: 'u1');
      await h.settle();
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Create profile'), findsNothing);
      await h.dispose();
    });
  });

  group('account mismatch (AE5, F7)', () {
    testWidgets('renders both actions; switch signs out locally only and '
        'keeps the data; remove resets and lands on first-run',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: AccountHarness.seedOneProfile);
      h.signIn(id: 'u2');
      h.engine.emitPhase(SyncPhase.accountMismatch, boundUserId: 'u1');
      await tester.pumpAndSettle();
      expect(key('mismatch-switch-account'), findsOneWidget);
      expect(key('mismatch-remove-data'), findsOneWidget);
      expect(find.textContaining('Hide My Email'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);

      await tester.tap(key('mismatch-switch-account'));
      await tester.pumpAndSettle();
      expect(h.auth.signOutCalls, [AuthSignOutScope.local]);
      expect(h.resets, 0);
      expect(
          (await DriftProfilesRepository(h.db.storage).list()).length, 1,
          reason: 'data untouched');
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
  });

  group('upload consent (R14, AS4)', () {
    testWidgets('renders counts and the duplicate-profile sentence; upload '
        'confirms; not now leaves the tappable tile that reopens it',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: (db) async {
        await AccountHarness.seedOneProfile(db);
        final profile =
            (await DriftProfilesRepository(db.storage).list()).single;
        final entries = DriftDayEntriesRepository(db.storage);
        await entries.save(DayEntry(
          id: '',
          profileId: profile.id,
          localDate: LocalDate(2026, 8, 1),
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const [],
          updatedAt: DateTime.utc(2026, 8, 1),
        ));
        await entries.save(DayEntry(
          id: '',
          profileId: profile.id,
          localDate: LocalDate(2026, 8, 2),
          tz: 'UTC',
          flow: FlowLevel.light,
          tags: const [],
          updatedAt: DateTime.utc(2026, 8, 2),
        ));
      });
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

      h.engine.emitPhase(SyncPhase.idle,
          lastError: SyncErrorKind.none, rejectedCount: 2);
      await tester.pumpAndSettle();
      expect(find.text('Some entries could not be uploaded'), findsOneWidget);
      await h.dispose();
    });

    testWidgets('the picker shows the status glyph only with a controller',
        (tester) async {
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
      expect(formatRelative(now.subtract(const Duration(seconds: 30)), now),
          'just now');
      expect(formatRelative(now.subtract(const Duration(minutes: 5)), now),
          '5 min ago');
      expect(formatRelative(now.subtract(const Duration(hours: 3)), now),
          '3 h ago');
      expect(formatRelative(now.subtract(const Duration(days: 2)), now),
          '2 d ago');
    });
  });

  group('sign out (R16, F6, AS3)', () {
    testWidgets('dirty rows (a tombstone-only set included) show the '
        'two-choice dialog; Sync now requests a cycle; discard resets',
        (tester) async {
      final h = AccountHarness(tester);
      await h.pump(seed: (db) async {
        final profiles = DriftProfilesRepository(db.storage);
        final p = await profiles.create(displayName: 'Alice', isMinor: false);
        final q = await profiles.create(displayName: 'Gone', isMinor: false);
        await profiles.delete(q.id);
        await db.storage.markPushed(
            table: SyncTable.profiles,
            id: p.id,
            localRevAtPush:
                (await db.storage.readDirtyProfiles()).firstWhere((r) => r.id == p.id).localRev);
      });
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
              'This removes the data from this device. It stays in your account.'),
          findsOneWidget);
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });
}

class _NoopSettings implements SettingsStore {
  @override
  Future<String?> get(String key) async => null;

  @override
  Future<void> set(String key, String value) async {}

  @override
  Stream<String?> watch(String key) => Stream.value(null);
}
