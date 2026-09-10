/// Widget tests for `FirstRunScreen` (Issue #216's onboarding rework on
/// top of the earlier split helpers): the three skippable introduction
/// cards, the cycle-questions step between the name form and creation,
/// and the pre-existing paths they sit among — the KTD9 web
/// acknowledgment split and the restoring-phase decision split
/// (`_restoreDone` / `_restoreDoneForPhase`).
///
/// The higher-level first-run flow (cards → account step → name form →
/// cycle questions; the cold-start restoring wait through the full app)
/// is also covered end-to-end in test/ui/account_test.dart and
/// test/ui/profiles_test.dart. Those harnesses never build with
/// `isWebBuild: true` and never drive the engine through every
/// [SyncPhase], so these tests mount `FirstRunScreen` directly
/// (skipping `ProfileHomeGate`/`LunarLogApp`) to reach the paths they
/// leave untouched.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/storage.dart' show LunarLogStorage;
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/restoring_screen.dart';
import 'package:lunarlog/ui/account/sync_status_controller.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_engine.dart';

/// The third card's copy — the pre-#216 notice, kept verbatim (#334's
/// repositioned text, now behind `firstRunNoticeBody` in the ARB).
const String kNoticeCopy =
    'Signing in syncs this profile across your devices and lets you share '
    'it with other guardians. Until then, everything you log stays on '
    'this device.';

/// The injected "today" for the date-picker window and mode stamping.
final LocalDate kToday = LocalDate(2026, 9, 1);

/// Mounts a bare `FirstRunScreen` over the minimal provider set it reads
/// (`ProfileController`, `SettingsStore`, `LunarLogStorage`, and
/// optionally `AuthController` / `SyncStatusController`, mirroring how
/// `lib/app.dart` only provides those last two when the build has them).
class Harness {
  Harness(this.tester, {this.pickDate}) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;

  /// Injected date-picker callable; defaults to one that never picks.
  final Future<DateTime?> Function(
      BuildContext, DateTime, DateTime, DateTime)? pickDate;

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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<ProfileController>.value(value: profiles),
          Provider<SettingsStore>.value(value: settings),
          Provider<LunarLogStorage>.value(value: db.storage),
          if (auth != null)
            ChangeNotifierProvider<AuthController>.value(value: auth),
          if (sync != null)
            ChangeNotifierProvider<SyncStatusController>.value(value: sync),
        ],
        child: FirstRunScreen(
          isWebBuild: isWebBuild,
          todayProvider: () => kToday,
          pickDate: pickDate ?? (_, _, _, _) async => null,
        ),
      ),
    ));
    await tester.pump();
  }

  /// Order matters (matches `disposeApp` in test/ui/profiles_test.dart):
  /// unmounting cancels the drift-watch streams the widget tree owns, and
  /// [profiles] (constructed outside the tree and injected via `.value`,
  /// so Provider never auto-disposes it) has its own stream to cancel too
  /// — both schedule zero-duration cleanup timers that must be drained by
  /// a real pump *before* `db.close()`, or close() waits on a
  /// cancellation that never gets a chance to run.
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    profiles.dispose();
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('introduction cards (#216)', () {
    testWidgets('Next walks value → guardians → notice; "I understand" '
        'ends the intro and persists the flag', (tester) async {
      final h = Harness(tester);
      await h.pump();

      // Card 1: identity/value — headline, claims, brand wordmark.
      expect(find.text('A private cycle log for your family'), findsOneWidget);
      expect(find.text('LunarLog'), findsOneWidget);
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('first-run-card-notice')),
          findsNothing,
          reason: 'one card at a time');
      expect(await h.settings.get(SettingsKeys.firstRunNoticeShown), isNull);

      await tester.tap(find.byKey(const ValueKey('first-run-next')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('first-run-card-guardians')),
          findsOneWidget,
          reason: 'card 2 explains profiles and guardians');
      expect(find.text('About the minor checkbox'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('first-run-next')));
      await tester.pumpAndSettle();
      expect(find.text(kNoticeCopy), findsOneWidget,
          reason: 'card 3 is today\'s data/sync notice, kept verbatim');
      expect(find.text('I understand'), findsOneWidget,
          reason: 'the notice keeps today\'s advance label');
      expect(await h.settings.get(SettingsKeys.firstRunNoticeShown), isNull,
          reason: 'not acknowledged until the notice card is finished');

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(await h.settings.get(SettingsKeys.firstRunNoticeShown), 'true');
      expect(find.byKey(const ValueKey('care-mode-dropdown')),
          findsOneWidget,
          reason: 'falls through to the name form (no auth in this tree)');
      await h.dispose();
    });

    testWidgets('Skip on any card clears the whole introduction — one tap, '
        'and the notice flag is still persisted', (tester) async {
      final h = Harness(tester);
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('first-run-skip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsNothing);
      expect(find.text(kNoticeCopy), findsNothing,
          reason: 'skipping card 1 never renders cards 2 or 3');
      expect(await h.settings.get(SettingsKeys.firstRunNoticeShown), 'true',
          reason: 'the intro (incl. the notice step) is one skippable unit');
      expect(find.byKey(const ValueKey('care-mode-dropdown')),
          findsOneWidget);
      await h.dispose();
    });

    testWidgets('a preset notice flag skips the intro entirely (relaunch '
        'and cold-start-link parity)', (tester) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
      await h.pump();

      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsNothing);
      expect(find.byKey(const ValueKey('care-mode-dropdown')),
          findsOneWidget);
      await h.dispose();
    });
  });

  group('cycle questions (#216)', () {
    /// A harness with the introduction pre-acknowledged (these tests
    /// target the questions, not the cards) and the name form filled and
    /// continued past.
    Future<Harness> pumpedToCycle(WidgetTester tester,
        {Future<DateTime?> Function(
                BuildContext, DateTime, DateTime, DateTime)?
            pickDate}) async {
      final h = Harness(tester, pickDate: pickDate);
      await h.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
      await h.pump();
      await tester.enterText(find.byType(TextFormField), 'Nova');
      await tester.tap(find.byKey(const ValueKey('first-run-continue')));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('Continue with an empty name stays on the form',
        (tester) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('first-run-continue')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-goal')), findsNothing,
          reason: 'the name must validate before the questions');
      await h.dispose();
    });

    testWidgets('the five questions render after the name form, each '
        'individually skippable; Back returns to the form with the name '
        'kept', (tester) async {
      final h = await pumpedToCycle(tester);

      expect(find.text('Last period start'), findsOneWidget);
      expect(find.text('Typical cycle length (days)'), findsOneWidget);
      expect(find.text('Typical period length (days)'), findsOneWidget);
      expect(find.text('Birth-control method'), findsOneWidget);
      expect(find.text('Goal / mode'), findsOneWidget);
      expect(find.text('Create profile'), findsOneWidget,
          reason: 'the final action keeps today\'s label');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('care-mode-dropdown')),
          findsOneWidget);
      expect(find.text('Nova'), findsOneWidget,
          reason: 'the name survives the round trip');
      await h.dispose();
    });

    testWidgets('out-of-range numbers are rejected until fixed',
        (tester) async {
      final h = await pumpedToCycle(tester);

      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-cycle')), '5');
      await tester.ensureVisible(find.byKey(const ValueKey('cycle-create')));
      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a number between 10 and 90'), findsOneWidget);
      expect(
          (await DriftProfilesRepository(h.db.storage).list()), isEmpty,
          reason: 'nothing is created while validation fails');

      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-period')), '21');
      await tester.ensureVisible(find.byKey(const ValueKey('cycle-create')));
      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();
      expect(
          find.text('Enter a number between 1 and 14'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-cycle')), '28');
      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-period')), '5');
      await tester.ensureVisible(find.byKey(const ValueKey('cycle-create')));
      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();
      expect((await DriftProfilesRepository(h.db.storage).list()).single
          .displayName, 'Nova');
      await h.dispose();
    });

    testWidgets('answers persist through the recorder seam: goal/mode and '
        'birth control into profile_modes', (tester) async {
      DateTime? capturedInitial;
      DateTime? capturedFirst;
      DateTime? capturedLast;
      final h = await pumpedToCycle(
        tester,
        pickDate: (context, initial, first, last) async {
          capturedInitial = initial;
          capturedFirst = first;
          capturedLast = last;
          return DateTime(2026, 8, 20);
        },
      );

      // Last period: the injected picker is bounded (no future dates, a
      // one-year lookback) and its result renders as a civil date.
      await tester
          .tap(find.byKey(const ValueKey('cycle-last-period-choose')));
      await tester.pumpAndSettle();
      expect(capturedLast, DateTime(2026, 9, 1));
      expect(capturedFirst, DateTime(2025, 9, 1));
      expect(capturedInitial, DateTime(2026, 9, 1));
      expect(find.byKey(const ValueKey('cycle-last-period-value')),
          findsOneWidget,
          reason: 'the picked date is shown');

      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-cycle')), '28');
      await tester.enterText(
          find.byKey(const ValueKey('cycle-typical-period')), '5');

      await tester.tap(
          find.byKey(const ValueKey('cycle-birth-control')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pill').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cycle-goal')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conceive').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const ValueKey('cycle-create')));
      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();

      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.displayName, 'Nova');
      final modeRow = await h.db.storage.getProfileMode(profiles.single.id);
      expect(modeRow, isNotNull,
          reason: 'a non-default goal creates the lazy row');
      expect(modeRow!.mode, 'conceive');
      expect(modeRow.birthControlMethod, 'pill',
          reason: 'Issue #260 stores the canonical vocabulary id');
      expect(modeRow.modeStartedOn, '2026-09-01',
          reason: 'a mode change stamps today (injected clock)');
      await h.dispose();
    });

    testWidgets('skipping every question creates the profile and writes no '
        'profile_modes row (the lazy-default contract)', (tester) async {
      final h = await pumpedToCycle(tester);

      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();

      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.displayName, 'Nova');
      expect(await h.db.storage.getProfileMode(profiles.single.id), isNull,
          reason: 'tracking + not answered means nothing to store');
      await h.dispose();
    });

    testWidgets('Clear removes a picked last-period date', (tester) async {
      final h = await pumpedToCycle(
        tester,
        pickDate: (_, _, _, _) async => DateTime(2026, 8, 20),
      );
      await tester
          .tap(find.byKey(const ValueKey('cycle-last-period-choose')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('cycle-last-period-clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-last-period-value')),
          findsNothing);
      expect(find.byKey(const ValueKey('cycle-last-period-choose')),
          findsOneWidget,
          reason: 'back to the unanswered state');
      await h.dispose();
    });
  });

  group('web acknowledgment (KTD9; _checkWebAcknowledgment split)', () {
    testWidgets('an unacknowledged web build blocks on the dialog before '
        'the introduction, persists the acknowledgment, then falls through',
        (tester) async {
      final h = Harness(tester);
      await h.pump(isWebBuild: true);

      // initState's async settings read has not resolved yet: a data-free
      // scaffold, no dialog, no cards.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsNothing);

      // The settings read resolves, then the dialog is scheduled
      // post-frame.
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Development build'), findsOneWidget);
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsNothing,
          reason: 'the introduction waits behind the blocking dialog');

      await tester.tap(find.byKey(const Key('web-acknowledge')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(await h.settings.get(SettingsKeys.webModalAcknowledged), 'true',
          reason: 'onAcknowledged persisted through the extracted helper');
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsOneWidget,
          reason: 'falls through to the first onboarding card');
      await h.dispose();
    });

    testWidgets('an already-acknowledged web build skips the dialog '
        'entirely and goes straight to the first card', (tester) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.webModalAcknowledged, 'true');
      await h.pump(isWebBuild: true);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsOneWidget);
      await h.dispose();
    });

    testWidgets('a non-web build never runs the acknowledgment check: no '
        'dialog, straight to the first card', (tester) async {
      final h = Harness(tester);
      await h.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const ValueKey('first-run-card-value')),
          findsOneWidget);
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
      expect(find.byKey(const ValueKey('first-run-continue')),
          findsNothing);

      engine.emitPhase(SyncPhase.restoring, boundUserId: 'u1');
      await tester.pump();
      expect(find.byType(RestoringScreen), findsOneWidget,
          reason: 'restoring itself never ends the wait');

      engine.emitPhase(SyncPhase.idle,
          lastSyncAt: DateTime.now().toUtc(), boundUserId: 'u1');
      await tester.pump();
      expect(find.byType(RestoringScreen), findsNothing,
          reason: 'idle after having been in restoring ends the wait');
      expect(find.byKey(const ValueKey('first-run-continue')),
          findsOneWidget,
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
      expect(find.byKey(const ValueKey('first-run-continue')),
          findsOneWidget);
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
        final (h, _, _) = await restoringHarness(
            tester, initialSnapshot: SyncSnapshot(phase: phase));

        expect(find.byType(RestoringScreen), findsNothing,
            reason: '$phase is home-gate territory, not a restoring wait');
        expect(find.byKey(const ValueKey('first-run-continue')),
            findsOneWidget);
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

  group('care-mode picker (Issue #131)', () {
    testWidgets('the creation form offers the care modes and persists the '
        'chosen one', (tester) async {
      final h = Harness(tester);
      await h.settings.set(SettingsKeys.firstRunNoticeShown, 'true');
      await h.pump();
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('care-mode-dropdown')), findsOneWidget,
          reason: 'mode is selectable at profile creation (#131 scope)');
      await tester.enterText(find.byType(TextFormField), 'Nova');
      await tester.tap(find.byType(DropdownButton<ProfileMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Irregular cycles').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('first-run-continue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-create')));
      await tester.pumpAndSettle();

      final profiles = await DriftProfilesRepository(h.db.storage).list();
      expect(profiles.single.displayName, 'Nova');
      expect(profiles.single.mode, ProfileMode.irregular);
      await h.dispose();
    });
  });
}
