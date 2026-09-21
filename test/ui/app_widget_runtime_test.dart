/// App-shell integration for the home-screen widget runtime (issue #141):
/// with an armed store in the bundle, `_initWidgetCoordinator` wires the
/// publisher (which writes the boundary payload through the store) and the
/// quick-log executor (which applies a widget tap's write through the real
/// repositories — here with no gate above the app, the same default-unlocked
/// posture the reminder executor tests use). A null store — every other
/// test — must leave no payload writes behind.
///
/// Issue #1016 adds the acknowledgement: a landed quick-log shows the same
/// snackbar + Undo the in-app today card does (restoring the pre-write
/// entry), an at-or-above flow is called out without changing anything, and
/// a viewer-role tap still writes nothing and says nothing.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' show SizedBox, SnackBar, ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart' show RemoteProfileGuardianRow;
import 'package:lunarlog/domain/auth/auth_service.dart'
    show AuthSessionState, AuthUser;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/widget/widget_cycle_state.dart';
import 'package:lunarlog/domain/widget/widget_data_store.dart';
import 'package:lunarlog/domain/widget/widget_quick_log_intent.dart';

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

void main() {
  Future<(LunarLogDatabase, String)> pumpApp(
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

  /// Unmounts the app before the database closes (the prediction service's
  /// foreground timer must be canceled with its subscriptions, or the test
  /// binding's pending-timer invariant fails) — the same teardown shape
  /// app_shell_test.dart's Harness uses.
  Future<void> teardown(WidgetTester tester, LunarLogDatabase db) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }

  testWidgets('an armed store publishes the payload and a widget tap '
      'logs today for the active profile', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await pumpApp(tester, store);

    // The publisher wrote the (discreet) payload for the active profile.
    expect(store.payloads, isNotEmpty);
    expect(
        store.payloads.last[WidgetCycleStatePayload.keyProfileId], profileId);
    expect(store.payloads.last[WidgetCycleStatePayload.keyCanQuickLog], '1');

    // A widget tap routes through the executor: today's entry is written
    // through the real repository (the quick-log flow rule).
    store.emit(Uri.parse(widgetQuickLogUri(profileId)));
    await tester.pumpAndSettle();

    final entry = await DriftDayEntriesRepository(db.storage)
        .find(profileId, LocalDate.today());
    expect(entry, isNotNull,
        reason: 'the widget tap applied the quick-log write');
    await teardown(tester, db);
  });

  testWidgets('a plain widget-open tap writes nothing', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await pumpApp(tester, store);

    store.emit(Uri.parse(widgetOpenUri()));
    await tester.pumpAndSettle();

    final entry = await DriftDayEntriesRepository(db.storage)
        .find(profileId, LocalDate.today());
    expect(entry, isNull);
    await teardown(tester, db);
  });

  testWidgets('a widget quick-log shows the logged snackbar, and Undo '
      'restores the heavier prior entry exactly', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await pumpApp(tester, store);
    final entries = DriftDayEntriesRepository(db.storage);

    await entries.save(DayEntry(
      id: '',
      profileId: profileId,
      localDate: LocalDate.today(),
      tz: 'America/Chicago',
      flow: FlowLevel.light,
      note: 'cramps',
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

    store.emit(Uri.parse(widgetQuickLogUri(profileId)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('widget-quick-log-snackbar')),
      findsOneWidget,
      reason: 'the gated widget write is acknowledged, never silent',
    );
    expect((await entries.find(profileId, LocalDate.today()))!.flow,
        FlowLevel.medium,
        reason: 'the tap raised the lighter hand-logged value');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    final restored = await entries.find(profileId, LocalDate.today());
    expect(restored!.flow, FlowLevel.light);
    expect(restored.note, 'cramps');
    expect(restored.tz, 'America/Chicago');
    await teardown(tester, db);
  });

  testWidgets('Undo of a widget-created entry tombstones it', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await pumpApp(tester, store);
    final entries = DriftDayEntriesRepository(db.storage);

    store.emit(Uri.parse(widgetQuickLogUri(profileId)));
    await tester.pumpAndSettle();
    expect(await entries.find(profileId, LocalDate.today()), isNotNull);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(await entries.find(profileId, LocalDate.today()), isNull);
    await teardown(tester, db);
  });

  testWidgets('an at-or-above flow says "Already logged" and never '
      'downgrades', (tester) async {
    final store = _FakeWidgetStore();
    final (db, profileId) = await pumpApp(tester, store);
    final entries = DriftDayEntriesRepository(db.storage);
    await entries.save(DayEntry(
      id: '',
      profileId: profileId,
      localDate: LocalDate.today(),
      tz: 'America/New_York',
      flow: FlowLevel.heavy,
      updatedAt: DateTime.utc(2026, 1, 1),
    ));

    store.emit(Uri.parse(widgetQuickLogUri(profileId)));
    await tester.pumpAndSettle();

    expect(find.text('Already logged for today.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('widget-quick-log-snackbar')),
      findsNothing,
      reason: 'nothing changed, so there is nothing to undo',
    );
    expect((await entries.find(profileId, LocalDate.today()))!.flow,
        FlowLevel.heavy);
    await teardown(tester, db);
  });

  testWidgets('a viewer-role widget tap writes nothing and shows no '
      'acknowledgement', (tester) async {
    final store = _FakeWidgetStore();
    final db = LunarLogDatabase(NativeDatabase.memory());
    final auth = FakeAuthService()
      ..emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'viewer-1', email: 'v@b.c'));
    final profile = await DriftProfilesRepository(db.storage)
        .create(displayName: 'Alice', isMinor: false);
    await DriftSettingsStore(db.storage)
        .set(SettingsKeys.lastActiveProfile, profile.id);
    await db.storage.applyRemoteRows([
      RemoteProfileGuardianRow(
        id: 'g-viewer',
        profileId: profile.id,
        userId: 'viewer-1',
        role: 'viewer',
        status: 'accepted',
        displayName: 'Viewer',
        invitedBy: null,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    ]);
    await tester.pumpWidget(LunarLogApp.withCollaborators(
      db: db,
      widgetDataStore: store,
      authService: auth,
    ));
    await tester.pumpAndSettle();

    store.emit(Uri.parse(widgetQuickLogUri(profile.id)));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing,
        reason: 'a dropped intent is never acknowledged as a write');
    final entry = await DriftDayEntriesRepository(db.storage)
        .find(profile.id, LocalDate.today());
    expect(entry, isNull, reason: 'the render flag is never an authorization');
    await teardown(tester, db);
    await auth.dispose();
  });
}
