/// Widget tests targeting `FirstRunScreen`'s two extracted helpers directly
/// (quality-gate follow-up): the KTD9 web-acknowledgment split
/// (`_checkWebAcknowledgment` / `_showWebAcknowledgmentDialog`) and the
/// restoring-phase decision split (`_restoreDone` / `_restoreDoneForPhase`).
///
/// The higher-level first-run flow (notice → account step → name form; the
/// cold-start restoring wait through the full app) is already covered
/// end-to-end in test/ui/account_test.dart and test/ui/profiles_test.dart.
/// Those harnesses never build with `isWebBuild: true` and never drive the
/// engine through every `SyncPhase`, so these tests mount `FirstRunScreen`
/// directly (skipping `ProfileHomeGate`/`LunarLogApp`) to reach the paths
/// they leave untouched.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';

/// Mounts a bare `FirstRunScreen` over the minimal provider set it reads
/// (`ProfileController`, `SettingsStore`, and optionally `AuthController` /
/// `SyncStatusController`, mirroring how `lib/app.dart` only provides those
/// last two when the build has them).
class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final SettingsStore settings = DriftSettingsStore(db.storage);
  late final ProfileController profiles = ProfileController(
    profilesRepository: DriftProfilesRepository(db.storage),
    settingsStore: settings,
  );

  Future<void> pump({
    bool isWebBuild = false,
    AuthController? auth,
    SyncStatusController? sync,
  }) async {
    await profiles.load();
    await tester.pumpWidget(MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileController>.value(value: profiles),
          Provider<SettingsStore>.value(value: settings),
          if (auth != null)
            ChangeNotifierProvider<AuthController>.value(value: auth),
          if (sync != null)
            ChangeNotifierProvider<SyncStatusController>.value(value: sync),
        ],
        child: FirstRunScreen(isWebBuild: isWebBuild),
      ),
    ));
    await tester.pump();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    profiles.dispose();
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('web acknowledgment (KTD9; _checkWebAcknowledgment split)', () {
    testWidgets('an unacknowledged web build blocks on the dialog before '
        'the notice, persists the acknowledgment, then falls through',
        (tester) async {
      final h = Harness(tester);
      await h.pump(isWebBuild: true);

      // initState's async settings read has not resolved yet: a data-free
      // scaffold, no dialog, no notice.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(kFirstRunNoticeCopy), findsNothing);

      // The settings read resolves, then the dialog is scheduled
      // post-frame.
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Development build'), findsOneWidget);
      expect(find.text(kFirstRunNoticeCopy), findsNothing,
          reason: 'the notice waits behind the blocking dialog');

      await tester.tap(find.byKey(const Key('web-acknowledge')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await h.settings.get(SettingsKeys.webModalAcknowledged), 'true',
          reason: 'onAcknowledged persisted through the extracted helper');
      expect(find.text(kFirstRunNoticeCopy), findsOneWidget,
          reason: 'falls through to the next first-run step');
      await h.dispose();
    });

    testWidgets('an already-acknowledged web build skips the dialog '
        'entirely and goes straight to the notice', (tester) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.webModalAcknowledged, 'true');
      await h.pump(isWebBuild: true);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(kFirstRunNoticeCopy), findsOneWidget);
      await h.dispose();
    });

    testWidgets('a non-web build never runs the acknowledgment check: no '
        'dialog, straight to the notice', (tester) async {
      final h = Harness(tester);
      await h.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(kFirstRunNoticeCopy), findsOneWidget);
      await h.dispose();
    });
  });

  group('restoring-phase decision (_restoreDone / _restoreDoneForPhase)', () {
    /// A first run that starts already signed in with a sync controller
    /// (the cold-start-link path): the notice is pre-acknowledged and the
    /// account step is skipped (a session exists), isolating every
    /// assertion to the restoring wait itself.
    Future<(Harness, FakeAuthService, FakeSyncEngine)> restoringHarness(
      WidgetTester tester, {
      SyncSnapshot initialSnapshot = SyncSnapshot.initial,
    }) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
      final auth = FakeAuthService(
        initialState: AuthSessionState.signedIn,
        user: const AuthUser(id: 'u1', email: 'a@b.c'),
      );
      addTearDown(auth.dispose);
      final engine = FakeSyncEngine(initial: initialSnapshot);
      await h.pump(
        auth: AuthController(authService: auth),
        sync: SyncStatusController(engine: engine),
      );
      return (h, auth, engine);
    }

    testWidgets('idle with no bound user and nothing seen yet keeps '
        'waiting; restoring then settling to idle ends it', (tester) async {
      final (h, _, engine) = await restoringHarness(tester);

      expect(find.byType(RestoringScreen), findsOneWidget,
          reason: 'idle, unbound, never having seen restoring: still waits');
      expect(find.text('Create profile'), findsNothing);

      engine.emitPhase(SyncPhase.restoring, boundUserId: 'u1');
      await tester.pump();
      expect(find.byType(RestoringScreen), findsOneWidget,
          reason: 'restoring itself never ends the wait');

      engine.emitPhase(SyncPhase.idle,
          lastSyncAt: DateTime.now().toUtc(), boundUserId: 'u1');
      await tester.pump();
      expect(find.byType(RestoringScreen), findsNothing,
          reason: 'idle after having been in restoring ends the wait');
      expect(find.text('Create profile'), findsOneWidget,
          reason: 'zero profiles falls through to the name form');
      await h.dispose();
    });

    testWidgets('a bound user from the start ends the wait immediately, '
        'even without ever passing through restoring', (tester) async {
      final (h, _, _) = await restoringHarness(
        tester,
        initialSnapshot:
            const SyncSnapshot(phase: SyncPhase.idle, boundUserId: 'u1'),
      );

      expect(find.byType(RestoringScreen), findsNothing);
      expect(find.text('Create profile'), findsOneWidget);
      await h.dispose();
    });

    for (final phase in [
      SyncPhase.error,
      SyncPhase.awaitingUploadConsent,
      SyncPhase.accountMismatch,
    ]) {
      testWidgets(
          '$phase ends the wait immediately regardless of the bound user',
          (tester) async {
        final (h, _, _) =
            await restoringHarness(tester, initialSnapshot: SyncSnapshot(phase: phase));

        expect(find.byType(RestoringScreen), findsNothing,
            reason: '$phase is home-gate territory, not a restoring wait');
        expect(find.text('Create profile'), findsOneWidget);
        await h.dispose();
      });
    }

    testWidgets('pushing (a non-restoring, non-terminal phase) is treated '
        'like idle: still waits until a bound user or a prior restoring',
        (tester) async {
      final (h, _, engine) = await restoringHarness(
        tester,
        initialSnapshot: const SyncSnapshot(phase: SyncPhase.pushing),
      );

      expect(find.byType(RestoringScreen), findsOneWidget);

      engine.emitPhase(SyncPhase.pushing, boundUserId: 'u1');
      await tester.pump();
      expect(find.byType(RestoringScreen), findsNothing,
          reason: 'a bound user ends the wait from any non-restoring phase');
      await h.dispose();
    });

    testWidgets('the session going away while restoring ends the wait',
        (tester) async {
      final (h, auth, _) = await restoringHarness(tester);
      expect(find.byType(RestoringScreen), findsOneWidget);

      auth.emit(AuthSessionState.signedOut);
      await tester.pump();
      expect(find.byType(RestoringScreen), findsNothing,
          reason: 'no session means nothing left to restore for');
      await h.dispose();
    });
  });
}
