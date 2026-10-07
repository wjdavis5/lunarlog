/// U4 wiring check: `LunarLogApp` provides an [AuthController] only when an
/// [AuthService] is passed; with `authService: null` (every existing
/// harness, and an unconfigured build) nothing account-related is provided
/// and the tree renders exactly as before (KTD11).
///
/// Also the U5/#49.1 composition-root check: each repository is built once
/// for the widget's lifetime, and the reminder coordinator plans against
/// those same instances (KTD3, R5).
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    show AndroidFlutterLocalNotificationsPlugin;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/import/account_importer.dart';
import 'package:lunarlog/data/notifications/notification_permission_gate.dart';
import 'package:lunarlog/data/notifications/notification_scheduler.dart'
    show FlutterLocalNotificationsScheduler;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/import/account_import_coordinator.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/notifications/reminder_payload.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart'
    show decodeLateSnoozes, kNotYetSnoozeDays;
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_reminder_scheduler.dart';
import '../support/fake_supabase_client.dart';
import '../support/fake_sync_engine.dart';
import '../support/fake_sync_transport.dart';
import 'gate_test.dart' show FakeGate, FakeInactivityTimers;
import 'overview_test.dart' show seedEpisodes;

Future<void> disposeApp(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

BuildContext homeContext(WidgetTester tester) =>
    tester.element(find.byType(ProfileHomeGate));

/// Three completed 28/28/25-day cycles ending a few days ago: enough
/// history for a live estimate that is still in the future, so exactly one
/// "upcoming" reminder is planned.
Future<void> seedPredictableHistory(
  DriftDayEntriesRepository entries,
  String profileId,
) =>
    seedEpisodes(entries, profileId, [
      LocalDate.today().addDays(-84),
      LocalDate.today().addDays(-56),
      LocalDate.today().addDays(-28),
      LocalDate.today().addDays(-3),
    ]);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('LunarLogApp without an auth service provides no '
      'AuthController and still renders first-run', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileHomeGate), findsOneWidget);
    expect(homeContext(tester).read<AuthController?>(), isNull);
    // The first-run surface (#216: introduction cards) renders without an
    // auth service.
    expect(find.text('A private cycle log for your family'), findsOneWidget);

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp with an auth service provides an AuthController '
      'that mirrors the service', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final service = FakeAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db, authService: service));
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

  testWidgets('LunarLogRoot gives the shared import coordinator the '
      'signed-in user id', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final service = FakeAuthService();
    addTearDown(service.dispose);
    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(requiresUnlock: false),
      dbOpener: () async => db,
      authService: service,
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await tester.pump();

    final coordinator = homeContext(tester).read<AccountImportCoordinator>()
        as DriftAccountImportCoordinator;
    expect(coordinator.currentUserIdProvider?.call(), 'u1',
        reason: 'the view-only guard and sharing notice key off the acting '
            'user; the root-built bundle must resolve it live');

    await disposeApp(tester, db);
  });

  testWidgets(
      '(#17 KTD8) a supabaseClient builds a real '
      'SupabaseAccountDeletionService and provides it down the tree, so '
      'the delete-account tile is reachable in production - not just when '
      'a test injects a fake deletion service directly', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final authService = FakeAuthService();
    addTearDown(authService.dispose);
    final transport = FakeSyncTransport();
    final client = FakeSupabaseClient();
    final engine = FakeSyncEngine();

    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(requiresUnlock: false),
      dbOpener: () async => db,
      authService: authService,
      syncTransport: transport,
      supabaseClient: client,
      syncEngineBuilder: ({
        required db,
        required authService,
        required transport,
        required gate,
      }) =>
          engine,
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    final deletion = homeContext(tester).read<AccountDeletionService?>();
    expect(deletion, isNotNull,
        reason: 'issue #17: a supabaseClient must build and provide an '
            'account deletion service, mirroring the sharing-service '
            'wiring from issue #76/PR #83');
    expect(deletion, isA<SupabaseAccountDeletionService>());

    await disposeApp(tester, db);
  });

  testWidgets(
      '(#17 R11) without a supabaseClient, no AccountDeletionService is '
      'provided', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final authService = FakeAuthService();
    addTearDown(authService.dispose);
    final transport = FakeSyncTransport();
    final engine = FakeSyncEngine();

    await tester.pumpWidget(LunarLogRoot(
      gate: FakeGate(requiresUnlock: false),
      dbOpener: () async => db,
      authService: authService,
      syncTransport: transport,
      syncEngineBuilder: ({
        required db,
        required authService,
        required transport,
        required gate,
      }) =>
          engine,
    ));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(homeContext(tester).read<AccountDeletionService?>(), isNull);

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp provides one repository instance for the '
      "widget's lifetime, not a fresh one per rebuild", (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
    await tester.pumpAndSettle();

    final before = homeContext(tester);
    final profiles = before.read<ProfilesRepository>();
    final entries = before.read<DayEntriesRepository>();
    final settings = before.read<SettingsStore>();
    final prediction = before.read<CyclePredictionService>();

    // Pumping an equivalent widget reuses the element and runs `build()`
    // again — the rebuild that used to reallocate every repository while
    // telling Provider the value was stable.
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
    await tester.pumpAndSettle();

    final after = homeContext(tester);
    expect(identical(after.read<ProfilesRepository>(), profiles), isTrue,
        reason: 'ProfilesRepository must survive a rebuild');
    expect(identical(after.read<DayEntriesRepository>(), entries), isTrue,
        reason: 'DayEntriesRepository must survive a rebuild');
    expect(identical(after.read<SettingsStore>(), settings), isTrue,
        reason: 'SettingsStore must survive a rebuild');
    expect(identical(after.read<CyclePredictionService>(), prediction), isTrue,
        reason: 'CyclePredictionService must survive a rebuild');

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp with a scheduler starts the coordinator and '
      'plans against the hoisted repositories', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final seedProfiles = DriftProfilesRepository(db.storage);
    final profile =
        await seedProfiles.create(displayName: 'Alice', isMinor: false);
    await seedPredictableHistory(
        DriftDayEntriesRepository(db.storage), profile.id);

    final scheduler = FakeReminderScheduler();
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db, scheduler: scheduler));
    await tester.pumpAndSettle();
    // The coordinator's replan is debounced; let the timer fire.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(scheduler.initializeCalls, 1);
    expect(scheduler.rescheduleCalls, isNotEmpty,
        reason: 'the coordinator planned from the seeded history');
    expect(
      scheduler.rescheduleCalls.last.map((r) => r.profileId).toSet(),
      {profile.id},
    );
    expect(
      scheduler.rescheduleCalls.last.map((r) => r.kind).toSet(),
      {ReminderKind.upcoming},
    );

    // A write through the *provided* repository replans: the coordinator
    // and the subtree are looking at the same data source.
    final plansBefore = scheduler.rescheduleCalls.length;
    final bea = await homeContext(tester)
        .read<ProfilesRepository>()
        .create(displayName: 'Bea', isMinor: false);
    await seedPredictableHistory(
        DriftDayEntriesRepository(db.storage), bea.id);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(scheduler.rescheduleCalls.length, greaterThan(plansBefore));
    expect(
      scheduler.rescheduleCalls.last.map((r) => r.profileId).toSet(),
      {profile.id, bea.id},
    );

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp hands its coordinator teardown to onTeardown',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final scheduler = FakeReminderScheduler();
    Future<void>? teardown;
    await tester.pumpWidget(LunarLogApp.withCollaborators(
      db: db,
      scheduler: scheduler,
      onTeardown: (done) => teardown = done,
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(teardown, isNull, reason: 'nothing torn down while mounted');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    expect(teardown, isNotNull,
        reason: 'dispose hands the coordinator teardown to the callback');
    // Cancelling the drift subscriptions needs the real event loop.
    await tester.runAsync(
      () => teardown!.timeout(const Duration(seconds: 10)),
    );
    await db.close();
  });

  testWidgets('a reminder action tap writes after the coordinator starts '
      'the executor (Issue #136)', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final seedProfiles = DriftProfilesRepository(db.storage);
    final profile =
        await seedProfiles.create(displayName: 'Alice', isMinor: false);

    final scheduler = FakeReminderScheduler();
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db, scheduler: scheduler));
    await tester.pumpAndSettle();

    // The "Not yet" action: writes nothing, snoozes the late reminders
    // through the same settings store the coordinator replans from.
    scheduler.launchSink!(ReminderLaunch(
      profileId: profile.id,
      kind: ReminderKind.late,
      actionId: kReminderActionNotYet,
    ));
    await tester.pumpAndSettle();

    final store = DriftSettingsStore(db.storage);
    final snoozes =
        decodeLateSnoozes(await store.get(SettingsKeys.reminderLateSnoozes));
    expect(snoozes[profile.id], LocalDate.today().addDays(kNotYetSnoozeDays));

    // The "Started" action: upserts today's entry through the same
    // database the tree reads.
    scheduler.launchSink!(ReminderLaunch(
      profileId: profile.id,
      kind: ReminderKind.upcoming,
      actionId: kReminderActionStarted,
    ));
    await tester.pumpAndSettle();

    final entry = await DriftDayEntriesRepository(db.storage)
        .find(profile.id, LocalDate.today());
    expect(entry, isNotNull);
    expect(entry!.flow, FlowLevel.medium, reason: 'the quick-log default');

    await disposeApp(tester, db);
  });

  testWidgets('a signed-in session clears both awaiting-confirmation '
      'settings through the hoisted settings store', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final store = DriftSettingsStore(db.storage);
    await store.set(SettingsKeys.awaitingConfirmationEmail, 'a@b.c');
    await store.set(SettingsKeys.awaitingMagicLinkEmail, 'a@b.c');
    final service = FakeAuthService();
    addTearDown(service.dispose);

    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db, authService: service));
    await tester.pumpAndSettle();
    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await tester.pumpAndSettle();

    expect(await store.get(SettingsKeys.awaitingConfirmationEmail), isEmpty);
    expect(await store.get(SettingsKeys.awaitingMagicLinkEmail), isEmpty);

    await disposeApp(tester, db);
  });

  testWidgets('issue #32 AC9: an unknown-email sign-in-mode request '
      'followed by a successful sign-in via another method clears '
      'awaitingMagicLinkEmail', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final store = DriftSettingsStore(db.storage);
    // The pending note for a sign-in email request to an unknown address.
    await store.set(SettingsKeys.awaitingMagicLinkEmail, 'unknown@b.c');
    final service = FakeAuthService();
    addTearDown(service.dispose);

    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db, authService: service));
    await tester.pumpAndSettle();

    // The unknown-email request itself completes silently, exactly like a
    // known one (no account created, no failure): the note stays put.
    await service.sendMagicLink(email: 'unknown@b.c', createAccount: false);
    await tester.pumpAndSettle();
    expect(service.magicLinkCalls.single,
        (email: 'unknown@b.c', createAccount: false));
    expect(
        await store.get(SettingsKeys.awaitingMagicLinkEmail), 'unknown@b.c');

    // A later successful sign-in via another method retires the note.
    await service.signInWithPassword(email: 'known@b.c', password: 'x');
    await tester.pumpAndSettle();
    expect(await store.get(SettingsKeys.awaitingMagicLinkEmail), isEmpty);

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp without a scheduler touches no notification '
      'machinery', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    // Deliberately not passed to the widget: the default (widget tests,
    // web) must leave the scheduler seam untouched.
    final scheduler = FakeReminderScheduler();
    await tester.pumpWidget(LunarLogApp.withCollaborators(db: db));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scheduler.initializeCalls, 0);
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(scheduler.cancelCalls, 0);

    await disposeApp(tester, db);
  });

  group('reminder permission requests and the system-UI window '
      '(issues #168, #1425)', () {
    // Issue #168 ran the coordinator's startup (initState -> post-frame
    // callback -> _startReminders -> coordinator.start()) inside a
    // `duringSystemUi` window, because `start()` then made an automatic
    // permission request. Issue #1425 removed that request -- it put the
    // system dialog over a black screen at first launch -- and the window
    // with it: an open window sets `GateController.obscured`, which hides
    // the whole app behind the privacy cover, so wrapping a startup that
    // shows no dialog only blanks the launch. The explicit "Turn on
    // reminders" request below, where a dialog really does appear, is the
    // one that still opens a window.
    testWidgets(
        'startup opens no system-UI window -- the app is not covered while '
        'the scheduler initializes', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final initializeGate = Completer<void>();
      final scheduler = FakeReminderScheduler(initializeGate: initializeGate);

      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(requiresUnlock: false),
        dbOpener: () async => db,
        scheduler: scheduler,
        inactivityTimerFactory: FakeInactivityTimers().factory,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // `GateShell` sits above the wrapper that hides the content, so it
      // is an anchor for the context that is present whether or not the
      // content is covered.
      final gateController =
          tester.element(find.byType(GateShell)).read<GateController>();

      expect(scheduler.initializeCalls, 1,
          reason: 'start() is in flight, parked inside initialize() -- so '
              'what follows is the state while the scheduler initializes, '
              'not the state before it began');
      expect(gateController.systemUiActive, isFalse,
          reason: 'startup presents no system UI, so it opens no window');
      expect(gateController.obscured, isFalse);
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing,
          reason: 'the pre-fix black first screen: the app sat behind the '
              'opaque cover for as long as initialize() took');
      expect(find.byType(ProfileHomeGate), findsOneWidget,
          reason: 'the content is onstage (the default finder skips '
              'offstage widgets)');
      expect(scheduler.requestPermissionCalls, 0);

      initializeGate.complete();
      await tester.pumpAndSettle();

      expect(gateController.systemUiActive, isFalse,
          reason: 'and no settling tail is left behind either -- a window '
              'that had opened would still be reported active here');
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing);
      expect(scheduler.requestPermissionCalls, 0);

      await disposeApp(tester, db);
    });

    testWidgets(
        'on Android with notifications not enabled, startup asks nothing '
        'and covers nothing; Today shows the "Turn on reminders" hint, and '
        'tapping it is what makes the request (issue #1425)', (tester) async {
      // Tall enough that Today's list builds the hint without scrolling.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // The real scheduler over a mocked platform channel, not
      // `FakeReminderScheduler`: the fake's `initialize()` could not show
      // whether the real one asks. flutter_test reports Android as the
      // platform, which is what the scheduler resolves its implementation
      // from.
      expect(defaultTargetPlatform, TargetPlatform.android);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      const channel =
          MethodChannel('dexterous.com/flutter/local_notifications');
      final calls = <String>[];
      // A fresh install on API 33+: POST_NOTIFICATIONS is off until asked.
      var notificationsEnabled = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (MethodCall call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'initialize':
            return true;
          case 'areNotificationsEnabled':
            return notificationsEnabled;
          case 'requestNotificationsPermission':
            // The system dialog, answered "Allow".
            notificationsEnabled = true;
            return true;
          default:
            return null;
        }
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profile = await DriftProfilesRepository(db.storage)
          .create(displayName: 'Alice', isMinor: false);
      final settings = DriftSettingsStore(db.storage);
      await settings.set(SettingsKeys.lastActiveProfile, profile.id);
      final scheduler = FlutterLocalNotificationsScheduler(
        settingsStore: settings,
        localTimeZoneProvider: () async => 'UTC',
        permissionGate: NotificationPermissionGate(),
      );

      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(requiresUnlock: false),
        dbOpener: () async => db,
        scheduler: scheduler,
        inactivityTimerFactory: FakeInactivityTimers().factory,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final gateController =
          tester.element(find.byType(GateShell)).read<GateController>();
      int requests() =>
          calls.where((m) => m == 'requestNotificationsPermission').length;

      expect(calls, contains('areNotificationsEnabled'),
          reason: 'initialize() ran through to its availability probe');
      expect(requests(), 0,
          reason: 'the pre-fix bug: the system dialog fired here, at '
              'launch, before the operator had seen a single screen');
      expect(gateController.systemUiActive, isFalse);
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing);

      // Never asked, so not enabled -- and Today says so, with the action.
      expect(find.byKey(const ValueKey('reminder-hint')), findsOneWidget,
          reason: 'the hint is how a never-asked install finds the '
              'permission, now that startup no longer asks');
      final action = find.byKey(const ValueKey('reminder-hint-action'));
      expect(action, findsOneWidget);
      expect(find.text('Turn on reminders'), findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(requests(), 1,
          reason: 'the in-context tap is the one and only request');
      expect(gateController.systemUiActive, isTrue,
          reason: 'this request does present a dialog, so it does run '
              'inside a window (still reported through its settling tail)');
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing,
          reason: 'and the cover came down with the dialog');
      expect(find.byKey(const ValueKey('reminder-hint')), findsNothing,
          reason: 'granted: the hint retires without waiting for a resume');

      await disposeApp(tester, db);
    });

    testWidgets(
        'the "Turn on reminders" request runs inside the system-UI window',
        (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final requestGate = Completer<void>();
      final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied,
        requestPermissionGate: requestGate,
      )..requestPermissionResult = NotificationAvailability.available;

      await tester.pumpWidget(LunarLogRoot(
        gate: FakeGate(requiresUnlock: false),
        dbOpener: () async => db,
        scheduler: scheduler,
        inactivityTimerFactory: FakeInactivityTimers().factory,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final gateController = homeContext(tester).read<GateController>();
      final requestPermission =
          homeContext(tester).read<RequestNotificationPermissionCallback>();
      expect(gateController.systemUiActive, isFalse,
          reason: 'startup left no window (or settling tail) open, so the '
              'one asserted below is this request\'s own');

      final pending = requestPermission();
      await tester.pump();

      expect(gateController.systemUiActive, isTrue,
          reason: 'the re-request dialog is system UI too');
      gateController.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(gateController.locked, isFalse,
          reason: 'this is the app\'s own request dialog, not a real '
              'departure');

      requestGate.complete();
      await pending;
      await tester.pumpAndSettle();

      await disposeApp(tester, db);
    });

    testWidgets(
        'tapping "Turn on reminders" skips the push ask after a refused '
        'request (issue #1627, #1639)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profile = await DriftProfilesRepository(db.storage)
          .create(displayName: 'Alice', isMinor: false);
      final settings = DriftSettingsStore(db.storage);
      await settings.set(SettingsKeys.lastActiveProfile, profile.id);

      final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied,
      )..requestPermissionResult = NotificationAvailability.denied;

      var pushCalls = 0;
      final ensurePush = EnsurePushRegistrationCallback(() async {
        pushCalls++;
      });

      final gateController = GateController(
        gate: FakeGate(requiresUnlock: false),
        inactivityTimerFactory: FakeInactivityTimers().factory,
      );
      addTearDown(gateController.dispose);

      await tester.pumpWidget(
        Provider<EnsurePushRegistrationCallback>.value(
          value: ensurePush,
          child: ChangeNotifierProvider<GateController>.value(
            value: gateController,
            child: LunarLogApp.withCollaborators(
              db: db,
              scheduler: scheduler,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('reminder-hint-action'));
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(scheduler.requestPermissionCalls, 1);
      expect(pushCalls, 0,
          reason: 'a refused reminder request must not chain the push ask '
              'so Android does not raise a second dialog immediately');

      await disposeApp(tester, db);
    });

    testWidgets(
        'tapping "Turn on reminders" chains the push ask after a granted '
        'request (issue #1627, #1639)', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profile = await DriftProfilesRepository(db.storage)
          .create(displayName: 'Alice', isMinor: false);
      final settings = DriftSettingsStore(db.storage);
      await settings.set(SettingsKeys.lastActiveProfile, profile.id);

      final scheduler = FakeReminderScheduler(
        initialAvailability: NotificationAvailability.denied,
      )..requestPermissionResult = NotificationAvailability.available;

      var pushCalls = 0;
      final ensurePush = EnsurePushRegistrationCallback(() async {
        pushCalls++;
      });

      final gateController = GateController(
        gate: FakeGate(requiresUnlock: false),
        inactivityTimerFactory: FakeInactivityTimers().factory,
      );
      addTearDown(gateController.dispose);

      await tester.pumpWidget(
        Provider<EnsurePushRegistrationCallback>.value(
          value: ensurePush,
          child: ChangeNotifierProvider<GateController>.value(
            value: gateController,
            child: LunarLogApp.withCollaborators(
              db: db,
              scheduler: scheduler,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('reminder-hint-action'));
      expect(action, findsOneWidget);

      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(scheduler.requestPermissionCalls, 1);
      expect(pushCalls, 1,
          reason: 'a granted reminder request proceeds with push registration');

      await disposeApp(tester, db);
    });
  });
}
