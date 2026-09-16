/// Issue #739's behavior matrix, both flag values: a QA build
/// (`LUNARLOG_QA_BUILD=true`, injected here as `qaBuild: true` — the
/// #738 `mfaEnabled` technique, so one default-off test run exercises
/// both sides) starts with the gate unlocked on a gated platform, never
/// re-locks (the privacy cover still applies), never arms the inactivity
/// countdown, auto-grants `reauthenticate`, and auto-passes `ensureAal2`
/// without consulting the auth service; a default build keeps today's
/// behavior for every one of those. Plus the visible markers: the
/// persistent QA banner, the app title suffix, the About version
/// suffix, and the Settings relock toggle rendered disabled with its QA
/// note.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/account/mfa_step_up_dialog.dart';
import 'package:lunarlog/ui/settings/about_section.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:lunarlog/ui/startup/qa_build_banner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_settings_store.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers, Harness;

Finder key(String key) => find.byKey(ValueKey(key));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('GateController on a QA build (issue #739)', () {
    // GateController's constructor reads WidgetsBinding.instance; plain
    // tests need the binding initialized explicitly.
    TestWidgetsFlutterBinding.ensureInitialized();

    test('starts unlocked on a gated platform and never prompts',
        () async {
      final gate = FakeGate(requiresUnlock: true);
      final controller = GateController(gate: gate, qaBuild: true);
      addTearDown(controller.dispose);

      expect(controller.locked, isFalse,
          reason: 'the whole point of the QA flag: straight into the app');
      expect(controller.relockEnabled, isFalse,
          reason: 'relock defaults off in a QA build');
      expect(gate.requests, 0,
          reason: 'no unlock prompt was ever presented');
      expect(gate.canAuthenticateRequests, 0);

      // unlock() on an already-open gate is a no-op, not a prompt.
      await controller.unlock();
      expect(controller.locked, isFalse);
      expect(gate.requests, 0);
    });

    test('relock stays off even when the persisted toggle says on, and '
        'the inactivity countdown never arms', () async {
      final gate = FakeGate(requiresUnlock: true);
      final timers = FakeInactivityTimers();
      final controller = GateController(
        gate: gate,
        qaBuild: true,
        inactivityTimerFactory: timers.factory,
      );
      addTearDown(controller.dispose);
      final store = FakeSettingsStore({SettingsKeys.relockEnabled: 'true'});
      controller.attachSettings(store);
      await pumpEventQueue();

      expect(controller.relockEnabled, isFalse,
          reason: 'the persisted "on" must not re-enable relock in a QA '
              'build — it is structurally off');
      controller.noteActivity();
      expect(timers.created, isEmpty,
          reason: 'no inactivity timer may arm while relock is off');
    });

    test('a departure covers content but never re-locks', () async {
      final gate = FakeGate(requiresUnlock: true);
      final controller = GateController(gate: gate, qaBuild: true);
      addTearDown(controller.dispose);

      controller.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(controller.locked, isFalse,
          reason: 'backgrounding must not re-lock a QA build');
      expect(controller.obscured, isTrue,
          reason: 'the snapshot cover posture is unchanged by the flag');

      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(controller.obscured, isFalse);
      expect(controller.locked, isFalse);
    });

    test('reauthenticate auto-grants without consulting the gate',
        () async {
      final gate = FakeGate(requiresUnlock: true)..grantNext = false;
      final controller = GateController(gate: gate, qaBuild: true);
      addTearDown(controller.dispose);

      final granted = await controller.reauthenticate();
      expect(granted, isTrue,
          reason: 'a QA build auto-grants even with the gate set to '
              'decline — no prompt exists to decline');
      expect(gate.requests, 0);
    });

    test('a default build keeps today\'s behavior (both flag values in '
        'one run)', () async {
      final gate = FakeGate(requiresUnlock: true);
      final controller = GateController(gate: gate, qaBuild: false);
      addTearDown(controller.dispose);

      expect(controller.locked, isTrue, reason: 'cold start still locks');
      expect(controller.relockEnabled, isTrue,
          reason: 'relock still defaults on (fail closed)');

      final granted = await controller.reauthenticate();
      expect(granted, isTrue);
      expect(gate.requests, 1,
          reason: 'a default build really runs the credential prompt');
    });
  });

  group('root cold start on a QA build (issue #739)', () {
    testWidgets('opens straight into the app: no lock screen, no prompt, '
        'database opened, banner visible', (tester) async {
      final harness = Harness(tester);
      await harness.pump(qaBuild: true);

      expect(key('lock-screen'), findsNothing,
          reason: 'the QA build must not present the unlock screen');
      expect(harness.gate.requests, 0,
          reason: 'and must not have prompted behind it either');
      expect(harness.dbOpenerCalls, 1,
          reason: 'the database opens immediately, like the un-gated web '
              'path');
      expect(find.byKey(QaBuildBanner.bannerKey), findsOneWidget,
          reason: 'the persistent QA marker rides the app shell');
      // Inline disposal (gate_test's own convention for tests that mount
      // content), plus one more frame: drift's StreamQueryStore schedules
      // a zero-duration cleanup timer while the deferred unmount runs
      // inside dispose()'s second pump, and that timer needs one further
      // frame to fire before the binding's pending-timer check.
      await harness.dispose();
      await tester.pump();
    });

    testWidgets('a default dispatch still gates first (F3, AE4)',
        (tester) async {
      final harness = Harness(tester);
      await harness.pump(grant: false, qaBuild: false);

      expect(key('lock-screen'), findsOneWidget);
      expect(harness.dbOpenerCalls, 0,
          reason: 'a declined credential never opens the database');
      expect(find.byKey(QaBuildBanner.bannerKey), findsNothing);
      await harness.dispose();
    });
  });

  group('ensureAal2 on a QA build (issue #739)', () {
    Future<AuthController> pumpEnsureAal2(
      WidgetTester tester,
      FakeAuthService auth, {
      required bool qaBuild,
    }) async {
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
      final controller = AuthController(authService: auth, mfaEnabled: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const ValueKey('trigger'),
                onPressed: () =>
                    ensureAal2(context, controller, qaBuild: qaBuild),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('auto-passes an MFA-on, step-up-required account without '
        'consulting the service', (tester) async {
      final auth = FakeAuthService()
        ..mfaStepUpRequired = true
        ..mfaFactors = [
          MfaFactor(
              id: 'factor-1',
              status: MfaFactorStatus.verified,
              createdAt: DateTime.utc(2026)),
        ];
      addTearDown(auth.dispose);
      await pumpEnsureAal2(tester, auth, qaBuild: true);

      await tester.tap(key('trigger'));
      await tester.pumpAndSettle();

      expect(find.text("Confirm it's you"), findsNothing,
          reason: 'no step-up dialog in a QA build');
      // The bypass is structural, ahead of any service resolution — the
      // same posture as #738's flag-off early return, so the two flags
      // stay independent: re-enabling MFA globally must not re-introduce
      // the prompt in QA builds.
      expect(auth.requiresMfaStepUpCalls, 0);
      expect(auth.listMfaFactorsCalls, 0);
    });

    testWidgets('a default build still steps up an enrolled account',
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
      await pumpEnsureAal2(tester, auth, qaBuild: false);

      await tester.tap(key('trigger'));
      await tester.pumpAndSettle();

      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(auth.requiresMfaStepUpCalls, 1);
    });
  });

  group('Settings relock toggle on a QA build (issue #739)', () {
    // Issue #226: the relock tile sits below the fold of the default test
    // surface.
    void useTallViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Future<void> pumpSettings(
      WidgetTester tester, {
      required bool qaBuild,
      FakeSettingsStore? store,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Provider<SettingsStore>.value(
            value: store ?? FakeSettingsStore(),
            child: SettingsScreen(qaBuild: qaBuild),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders disabled, off, with the QA note', (tester) async {
      useTallViewport(tester);
      await pumpSettings(
        tester,
        qaBuild: true,
        // The persisted toggle says ON; the QA build must still show off.
        store: FakeSettingsStore({SettingsKeys.relockEnabled: 'true'}),
      );

      final toggle =
          tester.widget<SwitchListTile>(key('relock-toggle'));
      expect(toggle.onChanged, isNull,
          reason: 'the toggle must be disabled in a QA build');
      expect(toggle.value, isFalse,
          reason: 'and must not claim relock is on when it is structurally '
              'off');
      expect(find.text(kQaBuildRelockNote), findsOneWidget);
    });

    testWidgets('a default build renders the working toggle', (tester) async {
      useTallViewport(tester);
      await pumpSettings(tester, qaBuild: false);

      final toggle =
          tester.widget<SwitchListTile>(key('relock-toggle'));
      expect(toggle.onChanged, isNotNull);
      expect(toggle.value, isTrue, reason: 'default ON (fail closed)');
      expect(find.text(kQaBuildRelockNote), findsNothing);
    });
  });

  group('QA build markers (issue #739 scope item 3)', () {
    testWidgets('the banner renders its copy', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: QaBuildBanner()));
      expect(find.byKey(QaBuildBanner.bannerKey), findsOneWidget);
      expect(find.text(kQaBuildBannerCopy), findsOneWidget);
    });

    testWidgets('the app shell shows the banner and the QA title on a QA '
        'build', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      await tester.pumpWidget(LunarLogApp.withCollaborators(
        db: db,
        showQaBanner: true,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(QaBuildBanner.bannerKey), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'lunarlog$kQaBuildVersionSuffix',
        reason: 'the OS task-switcher label carries the QA suffix',
      );
      // web_guardrails_test's teardown recipe, plus one more frame:
      // drift's StreamQueryStore schedules a zero-duration cleanup timer
      // while the deferred unmount runs, and closing the database before
      // it fires (or while the tree is still subscribed) hangs the test.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await db.close();
    });

    testWidgets('the default build shows neither banner nor suffix',
        (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
      await tester.pumpAndSettle();
      expect(find.byKey(QaBuildBanner.bannerKey), findsNothing);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
        'lunarlog',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await db.close();
    });

    testWidgets('the About version line carries the suffix on a QA build '
        'only', (tester) async {
      Future<void> pumpAbout({required bool qaBuild}) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: AboutSection(
                qaBuild: qaBuild,
                packageInfoReader: () async => PackageInfo(
                  appName: 'lunarlog',
                  packageName: 'com.wjdavis5.lunarlog',
                  version: '3.2.1',
                  buildNumber: '42',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpAbout(qaBuild: true);
      expect(find.textContaining('(QA build)'), findsOneWidget);

      // Fully unmount between the two pumps: the resolved flag is a
      // `late final` State field, so a repump over the same element
      // would keep the first resolution.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      await pumpAbout(qaBuild: false);
      expect(find.textContaining('(QA build)'), findsNothing);
      expect(find.textContaining('3.2.1'), findsOneWidget);
    });
  });
}
