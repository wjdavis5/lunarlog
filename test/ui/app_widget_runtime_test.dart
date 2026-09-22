/// App-shell integration for the home-screen widget runtime (issue #141):
/// with an armed store in the bundle, `_initWidgetCoordinator` wires the
/// publisher (which writes the boundary payload through the store) and the
/// quick-log executor (which applies a widget tap's write through the real
/// repositories — here with no gate above the app, the same default-unlocked
/// posture the reminder executor tests use). A null store — every other
/// test — must leave no payload writes behind.
///
/// Issue #1016: a materialized write is no longer silent. The shell
/// acknowledges it with the same snackbar + Undo the in-app Today card
/// shows, and jumps to the logged profile's Today tab through the
/// launch-payload seam — including when the write named a profile other
/// than the active one, and for a same-profile write while the operator
/// sits on another tab (the issue's repro). A dropped intent — a viewer's
/// role re-check at write time — emits no outcome, so it stays silent on
/// every axis: no write, no snackbar, no jump.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/app_lifecycle.dart' show GateController;
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/gate/app_gate.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';
import 'package:lunarlog/domain/widget/widget_data_store.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';
import 'package:lunarlog/ui/components/app_shell_scope.dart' show AppTab;
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

/// Capturing fake store: records payloads and exposes a controllable tap
/// stream, so the runtime is exercised end-to-end without the plugin.
class _FakeWidgetStore implements WidgetDataStore {
  final payloads = <Map<String, String>>[];
  final _launches = StreamController<Uri>();

  void emit(Uri uri) => _launches.add(uri);

  @override
  Future<void> savePayload(Map<String, String> payload) async =>
      payloads.add(Map.of(payload));

  @override
  Future<void> refresh() async {}

  @override
  Future<Uri?> initialLaunch() async => null;

  @override
  Stream<Uri> get launches => _launches.stream;
}

/// A gate that never requires unlocking — the same shape
/// `app_shell_test.dart` uses for its launch-payload tests: the shell
/// wiring is exercised, the device-credential path is not.
class _NoLockGate implements AppGate {
  @override
  bool get requiresUnlock => false;

  @override
  Future<bool> canAuthenticate() async => true;

  @override
  Future<bool> requestAccess() async => true;
}

/// Materializes a server-authored guardian row locally (mirrors
/// `app_shell_test.dart`'s helper of the same name).
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role,
) => RemoteProfileGuardianRow(
  id: id,
  profileId: profileId,
  userId: userId,
  role: role,
  status: 'accepted',
  invitedBy: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverVersion: 1,
);

DriftDayEntriesRepository _entriesOf(LunarLogDatabase db) =>
    DriftDayEntriesRepository(db.storage);

Future<(LunarLogDatabase, String)> _pumpApp(
  WidgetTester tester,
  _FakeWidgetStore store,
) async {
  final db = LunarLogDatabase(NativeDatabase.memory());
  final profile = await DriftProfilesRepository(db.storage)
      .create(displayName: 'Alice', isMinor: false);
  await DriftSettingsStore(db.storage)
      .set(SettingsKeys.lastActiveProfile, profile.id);
  await tester.pumpWidget(LunarLogApp.withCollaborators(
    db: db,
    widgetDataStore: store,
  ));
  await tester.pumpAndSettle();
  return (db, profile.id);
}

/// Two live profiles (Alice active) behind an optional gate, so the
/// issue #1016 jump tests can route a write for either profile.
Future<(LunarLogDatabase, String, String)> _pumpTwoProfiles(
  WidgetTester tester,
  _FakeWidgetStore store, {
  GateController? gate,
  Future<void> Function(LunarLogDatabase db) seed = _seedNothing,
}) async {
  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final alice = await profiles.create(displayName: 'Alice', isMinor: false);
  final bob = await profiles.create(displayName: 'Bob', isMinor: false);
  await DriftSettingsStore(db.storage)
      .set(SettingsKeys.lastActiveProfile, alice.id);
  await seed(db);
  await tester.pumpWidget(
    gate == null
        ? LunarLogApp.withCollaborators(db: db, widgetDataStore: store)
        : ChangeNotifierProvider<GateController>.value(
            value: gate,
            child: LunarLogApp.withCollaborators(db: db, widgetDataStore: store),
          ),
  );
  await tester.pumpAndSettle();
  return (db, alice.id, bob.id);
}

Future<void> _seedNothing(LunarLogDatabase db) async {}

/// Unmounts the app before the database closes (the prediction service's
/// foreground timer must be canceled with its subscriptions, or the test
/// binding's pending-timer invariant fails) — the same teardown shape
/// app_shell_test.dart's Harness uses. Any snackbar a widget write
/// surfaced still holds its auto-hide timer, so it is cleared and pumped
/// past first.
Future<void> teardown(WidgetTester tester, LunarLogDatabase db) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .clearSnackBars();
  await tester.pump();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

Finder snackbarContent() =>
    find.byKey(const ValueKey('widget-quick-log-snackbar'));

void main() {
  testWidgets('an armed store publishes the payload and a widget tap '
      'logs today for the active profile', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await _pumpApp(tester, store);

    // The publisher wrote the (discreet) payload for the active profile.
    expect(store.payloads, isNotEmpty);
    expect(
        store.payloads.last[WidgetCycleStatePayload.keyProfileId], profileId);
    expect(store.payloads.last[WidgetCycleStatePayload.keyCanQuickLog], '1');

    // A widget tap routes through the executor: today's entry is written
    // through the real repository (the quick-log flow rule).
    store.emit(Uri.parse(widgetQuickLogUri(profileId)));
    await tester.pumpAndSettle();

    final entry = await _entriesOf(db).find(profileId, LocalDate.today());
    expect(entry, isNotNull,
        reason: 'the widget tap applied the quick-log write');
    // Issue #1016: the write acknowledges itself.
    expect(snackbarContent(), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);
    await teardown(tester, db);
  });

  testWidgets('a plain widget-open tap writes nothing', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await _pumpApp(tester, store);

    store.emit(Uri.parse(widgetOpenUri()));
    await tester.pumpAndSettle();

    final entry = await _entriesOf(db).find(profileId, LocalDate.today());
    expect(entry, isNull);
    expect(snackbarContent(), findsNothing);
    await teardown(tester, db);
  });

  group('issue #1016: the materialized write acknowledges itself', () {
    testWidgets('the snackbar carries Undo, and Undo deletes the day the '
        'tap created', (tester) async {
      final store = _FakeWidgetStore();
      final (db, profileId) = await _pumpApp(tester, store);

      store.emit(Uri.parse(widgetQuickLogUri(profileId)));
      await tester.pumpAndSettle();

      expect(
          (await _entriesOf(db).find(profileId, LocalDate.today()))!.flow,
          FlowLevel.medium);
      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();

      expect(await _entriesOf(db).find(profileId, LocalDate.today()), isNull,
          reason: 'the Undo restores the empty prior day (a tombstone)');
      await teardown(tester, db);
    });

    testWidgets('Undo restores the full pre-write entry the day already '
        'had — the shared undoQuickLog semantics', (tester) async {
      final store = _FakeWidgetStore();
      final db = LunarLogDatabase(NativeDatabase.memory());
      final profile = await DriftProfilesRepository(db.storage)
          .create(displayName: 'Alice', isMinor: false);
      await DriftSettingsStore(db.storage)
          .set(SettingsKeys.lastActiveProfile, profile.id);
      final prior = await _entriesOf(db).save(DayEntry(
        id: '',
        profileId: profile.id,
        localDate: LocalDate.today(),
        tz: 'America/Chicago',
        flow: FlowLevel.light,
        note: 'tender',
        updatedAt: DateTime.now().toUtc(),
      ));
      await tester.pumpWidget(LunarLogApp.withCollaborators(
        db: db,
        widgetDataStore: store,
      ));
      await tester.pumpAndSettle();

      store.emit(Uri.parse(widgetQuickLogUri(profile.id)));
      await tester.pumpAndSettle();
      // The write upgraded the flow (never downgraded) and kept the note.
      final written =
          await _entriesOf(db).find(profile.id, LocalDate.today());
      expect(written!.flow, FlowLevel.medium);
      expect(written.note, 'tender');

      await tester.tap(find.byType(SnackBarAction));
      await tester.pumpAndSettle();

      final restored = await _entriesOf(db).find(profile.id, LocalDate.today());
      expect(restored, isNotNull);
      expect(restored!.flow, FlowLevel.light,
          reason: 'the Undo puts the pre-write entry back, not a delete');
      expect(restored.note, 'tender');
      expect(restored.id, prior.id);
      await teardown(tester, db);
    });

    testWidgets('a same-profile write while the operator is on More jumps '
        'back to Today (the issue repro)', (tester) async {
      final store = _FakeWidgetStore();
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);
      final (db, aliceId, _) =
          await _pumpTwoProfiles(tester, store, gate: gate);

      await tester.tap(find.byKey(const ValueKey('app-shell-tab-more')));
      await tester.pumpAndSettle();

      store.emit(Uri.parse(widgetQuickLogUri(aliceId)));
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.today.index,
          reason: 'the acknowledgement lands the operator on Today, not '
              'wherever the app happened to be');
      expect(snackbarContent(), findsOneWidget);
      expect(await _entriesOf(db).find(aliceId, LocalDate.today()),
          isNotNull);
      await teardown(tester, db);
    });

    testWidgets('a write for a different profile switches to that profile '
        'and lands on its Today tab', (tester) async {
      final store = _FakeWidgetStore();
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);
      final (db, aliceId, bobId) =
          await _pumpTwoProfiles(tester, store, gate: gate);

      store.emit(Uri.parse(widgetQuickLogUri(bobId)));
      await tester.pumpAndSettle();

      expect(find.text('Bob'), findsOneWidget,
          reason: 'the active profile switched to the logged profile — the '
              'write went there, so the acknowledgement shows there');
      final navBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.today.index);
      expect(await _entriesOf(db).find(bobId, LocalDate.today()), isNotNull);
      expect(await _entriesOf(db).find(aliceId, LocalDate.today()), isNull,
          reason: 'only the named profile was written');
      await teardown(tester, db);
    });

    testWidgets('a dropped intent (viewer role at write time) stays '
        'silent: no write, no snackbar, no jump', (tester) async {
      final store = _FakeWidgetStore();
      final gate = GateController(gate: _NoLockGate());
      addTearDown(gate.dispose);
      final auth = FakeAuthService();
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'user-doc'));

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final alice =
          await profiles.create(displayName: 'Alice', isMinor: false);
      final aliceId = alice.id;
      await profiles.create(displayName: 'Bob', isMinor: false);
      await DriftSettingsStore(db.storage)
          .set(SettingsKeys.lastActiveProfile, aliceId);
      await db.storage.applyRemoteRows([
        guardianRow(aliceId, 'g-doc', 'user-doc', 'viewer'),
      ]);
      await tester.pumpWidget(
        ChangeNotifierProvider<GateController>.value(
          value: gate,
          child: LunarLogApp.withCollaborators(
            db: db,
            authService: auth,
            widgetDataStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('app-shell-tab-more')));
      await tester.pumpAndSettle();

      store.emit(Uri.parse(widgetQuickLogUri(aliceId)));
      await tester.pumpAndSettle();

      expect(snackbarContent(), findsNothing,
          reason: 'a drop emits no outcome — the surfaced-drop line of '
              'issue #1016 is deliberately out of scope, so #141 silence '
              'on non-writes stands');
      final navBar = tester.widget<NavigationBar>(
          find.byType(NavigationBar));
      expect(navBar.selectedIndex, AppTab.more.index,
          reason: 'no jump either — nothing happened');
      expect(await _entriesOf(db).find(aliceId, LocalDate.today()), isNull);
      await teardown(tester, db);
    });
  });
}
