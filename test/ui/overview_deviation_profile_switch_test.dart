/// Issue #1709: the deviation card is per-profile. The overview panel is
/// updated in place on a profile switch (no key), so its cached snapshot —
/// and a read still in flight behind it — must never paint under the newly
/// selected profile, and a dismissal must record the key that produced the
/// snapshot.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/health/health_deviation.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:provider/provider.dart';

/// The snapshot the previously viewed profile produced.
final HealthDeviationSnapshot _snapshotOfD = HealthDeviationSnapshot(
  insights: [
    HealthDeviationInsight(
      kind: HealthDeviationKind.prolongedMenstrualPeriods,
      start: LocalDate(2026, 7, 1),
      end: LocalDate(2026, 7, 12),
    ),
  ],
  observedAt: DateTime.utc(2026, 9, 15),
);

/// A device-local [HealthDeviationInsights] stand-in: returns the configured
/// snapshot per profile, or a future the test completes itself when
/// `pending[profileId]` is set.
class _FakeDeviationInsights implements HealthDeviationInsights {
  _FakeDeviationInsights({this.snapshots = const {}});

  final Map<String, HealthDeviationSnapshot> snapshots;
  final Map<String, Completer<HealthDeviationSnapshot?>> pending = {};
  final List<String> visibleCalls = [];
  final List<(String, HealthDeviationSnapshot)> dismissals = [];

  @override
  Future<HealthDeviationSnapshot?> visibleSnapshot(String profileId) {
    visibleCalls.add(profileId);
    final completer = pending[profileId];
    if (completer != null) return completer.future;
    return Future.value(snapshots[profileId]);
  }

  @override
  Future<void> dismiss(
    String profileId,
    HealthDeviationSnapshot snapshot,
  ) async {
    dismissals.add((profileId, snapshot));
  }

  @override
  Future<HealthDeviationSnapshot> refresh() async =>
      const HealthDeviationSnapshot();
}

/// A bare [OverviewPanel] over an in-memory store, with the deviation seam
/// wired. Pumping it again with another [profileId] updates the panel in
/// place, exactly as the shell does on a profile switch (no key).
Widget _host(
  LunarLogDatabase db, {
  required String profileId,
  required _FakeDeviationInsights deviation,
}) {
  final settings = DriftSettingsStore(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<SettingsStore>.value(value: settings),
      Provider<CyclePredictionService>.value(
        value: CyclePredictionService(entries, settings: settings),
      ),
      Provider<CycleExclusionList>.value(value: CycleExclusionList(settings)),
      ChangeNotifierProvider<NotificationPermissionState>.value(
        value: NotificationPermissionState(NotificationAvailability.available),
      ),
      Provider<HealthDeviationInsights?>.value(value: deviation),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: OverviewPanel(
          profileId: profileId,
          todayProvider: () => LocalDate(2026, 8, 30),
        ),
      ),
    ),
  );
}

Future<void> _tearDown(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  void sizeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('a snapshot from the previously viewed profile never paints '
      'under the new profile', (tester) async {
    sizeView(tester);
    final db = LunarLogDatabase(NativeDatabase.memory());
    final deviation = _FakeDeviationInsights(snapshots: {'d': _snapshotOfD});

    await tester.pumpWidget(_host(db, profileId: 'd', deviation: deviation));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('health-deviation-card')),
      findsOneWidget,
      reason: 'sanity: the viewed profile shows its own snapshot',
    );

    await tester.pumpWidget(_host(db, profileId: 'a', deviation: deviation));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('health-deviation-card')),
      findsNothing,
      reason: 'issue #1709: the previous profile\'s cached snapshot must not '
          'render under the new profile',
    );
    expect(deviation.dismissals, isEmpty);
    await _tearDown(tester, db);
  });

  testWidgets('a read in flight for the previous profile is dropped after '
      'the switch', (tester) async {
    sizeView(tester);
    final db = LunarLogDatabase(NativeDatabase.memory());
    final deviation = _FakeDeviationInsights();
    deviation.pending['d'] = Completer<HealthDeviationSnapshot?>();

    await tester.pumpWidget(_host(db, profileId: 'd', deviation: deviation));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('health-deviation-card')),
      findsNothing,
      reason: 'sanity: the read has not landed yet',
    );

    await tester.pumpWidget(_host(db, profileId: 'a', deviation: deviation));
    await tester.pumpAndSettle();

    deviation.pending['d']!.complete(_snapshotOfD);
    // Settle so a pre-fix stale paint would have landed by the assertion.
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('health-deviation-card')),
      findsNothing,
      reason: 'issue #1709: a read that started for the previous profile must '
          'not paint under the new one',
    );
    await _tearDown(tester, db);
  });

  testWidgets('dismissing records the key that produced the snapshot',
      (tester) async {
    sizeView(tester);
    final db = LunarLogDatabase(NativeDatabase.memory());
    final deviation = _FakeDeviationInsights(snapshots: {'d': _snapshotOfD});

    await tester.pumpWidget(_host(db, profileId: 'd', deviation: deviation));
    await tester.pumpAndSettle();
    final dismiss = find.byKey(const ValueKey('health-deviation-dismiss'));
    await tester.ensureVisible(dismiss);
    await tester.tap(dismiss);
    await tester.pump();

    expect(deviation.dismissals, hasLength(1));
    expect(deviation.dismissals.single.$1, 'd');
    expect(find.byKey(const ValueKey('health-deviation-card')), findsNothing);
    await _tearDown(tester, db);
  });
}
