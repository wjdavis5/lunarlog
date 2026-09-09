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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/notifications/reminder_payload.dart';
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/account/supabase_account_deletion_service.dart';
import 'package:lunarlog/domain/account/account_deletion_service.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
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
    await tester.pumpWidget(LunarLogApp(db: db));
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
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();

    final before = homeContext(tester);
    final profiles = before.read<ProfilesRepository>();
    final entries = before.read<DayEntriesRepository>();
    final settings = before.read<SettingsStore>();
    final prediction = before.read<CyclePredictionService>();

    // Pumping an equivalent widget reuses the element and runs `build()`
    // again — the rebuild that used to reallocate every repository while
    // telling Provider the value was stable.
    await tester.pumpWidget(LunarLogApp(db: db));
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
    await tester.pumpWidget(LunarLogApp(db: db, scheduler: scheduler));
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
    await homeContext(tester)
        .read<ProfilesRepository>()
        .create(displayName: 'Bea', isMinor: false);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(scheduler.rescheduleCalls.length, greaterThan(plansBefore));

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp hands its coordinator teardown to onTeardown',
      (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final scheduler = FakeReminderScheduler();
    Future<void>? teardown;
    await tester.pumpWidget(LunarLogApp(
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
    await tester.pumpWidget(LunarLogApp(db: db, scheduler: scheduler));
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

    await tester.pumpWidget(LunarLogApp(db: db, authService: service));
    await tester.pumpAndSettle();
    service.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'u1'));
    await tester.pumpAndSettle();

    expect(await store.get(SettingsKeys.awaitingConfirmationEmail), isEmpty);
    expect(await store.get(SettingsKeys.awaitingMagicLinkEmail), isEmpty);

    await disposeApp(tester, db);
  });

  testWidgets('LunarLogApp without a scheduler touches no notification '
      'machinery', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    // Deliberately not passed to the widget: the default (widget tests,
    // web) must leave the scheduler seam untouched.
    final scheduler = FakeReminderScheduler();
    await tester.pumpWidget(LunarLogApp(db: db));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(scheduler.initializeCalls, 0);
    expect(scheduler.rescheduleCalls, isEmpty);
    expect(scheduler.cancelCalls, 0);

    await disposeApp(tester, db);
  });

  group('reminder permission requests run inside the system-UI window '
      '(issue #168)', () {
    // The automatic startup request (initState -> post-frame callback ->
    // _startReminders -> coordinator.start()) now runs inside the same
    // `duringSystemUi` window as the explicit re-request below. It cannot
    // be wrapped directly from `initState` -- opening the window's
    // synchronous `notifyListeners()` would hit `LunarLogRootState` calling
    // `setState()` mid-build -- so `_LunarLogAppState` constructs the
    // coordinator synchronously in `initState` but defers only the
    // `start()` call to a post-frame callback, which runs safely after the
    // ancestor's build phase has finished.
    testWidgets(
        'the automatic startup request also runs inside the system-UI '
        'window', (tester) async {
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

      // Not `homeContext` (`find.byType(ProfileHomeGate)`): the automatic
      // startup request's system-UI window is already open by this point
      // (it opens as part of the very first settle, unlike the manual tap
      // below, which only opens one after the harness has already
      // captured its context) and `GateController.obscured` — content
      // must stay covered while the app's own system UI is up — makes
      // `GateShell` mark `ProfileHomeGate` offstage for the duration,
      // which the default `skipOffstage: true` finder would miss.
      // `GateShell` itself sits above that offstage wrapper and is never
      // hidden, so it is a safe, always-present anchor for the context.
      final gateController =
          tester.element(find.byType(GateShell)).read<GateController>();

      expect(gateController.systemUiActive, isTrue,
          reason: 'the automatic startup permission request is system UI '
              'too');
      gateController.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(gateController.locked, isFalse,
          reason: 'this is the app\'s own startup request, not a real '
              'departure');

      initializeGate.complete();
      await tester.pumpAndSettle();

      // Not `systemUiActive` here: closing a window starts a settling
      // tail (bounded by `settleTimeout`) during which it deliberately
      // stays reported as active — see `GateController._closeSystemUiWindow`.
      expect(scheduler.initializeCalls, 1);

      await disposeApp(tester, db);
    });

    testWidgets(
        'the "Turn on reminders" re-request is wrapped the same way',
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
  });
}
