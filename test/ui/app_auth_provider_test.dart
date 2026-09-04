/// U4 wiring check: `LunarLogApp` provides an [AuthController] only when an
/// [AuthService] is passed; with `authService: null` (every existing
/// harness, and an unconfigured build) nothing account-related is provided
/// and the tree renders exactly as before (KTD11).
///
/// Also the U5/#49.1 composition-root check: each repository is built once
/// for the widget's lifetime, and the reminder coordinator plans against
/// those same instances (KTD3, R5).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/notifications/scheduling.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/profiles/profile_home_gate.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_reminder_scheduler.dart';
import 'gate_test.dart' show FakeGate;
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
}
