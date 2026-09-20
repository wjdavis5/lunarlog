/// Issue #204 (Conceive mode): the Conceive-mode Cycle View surfaces —
/// the per-day conception-likelihood card itself, its mandatory disclaimer
/// treatment, and its mount in [OverviewPanel] while the profile's
/// life-stage mode is `conceive`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/conceive.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/conceive_card.dart';
import 'package:lunarlog/ui/components/today_card.dart';
import 'package:lunarlog/ui/overview/estimate_copy.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:provider/provider.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

final DateTime _stamp = DateTime.utc(2026, 1, 1);

DayEntry _bleed(LocalDate date) => DayEntry(
      id: 'e-${date.iso}',
      profileId: 'p',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: _stamp,
    );

/// Four completed 28-day cycles then an open one — enough history for an
/// [ActivePrediction], whose first forecast window is still current on
/// 2026-05-05.
final List<DayEntry> _entries = [
  for (final start in [
    d(2026, 1, 1),
    d(2026, 1, 29),
    d(2026, 2, 26),
    d(2026, 3, 26),
    d(2026, 4, 23),
  ])
    _bleed(start),
];

final LocalDate _today = d(2026, 5, 5);

class _StubDayEntriesRepository implements DayEntriesRepository {
  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) async* {
    yield _entries;
  }

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => _entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeModesRepository implements ProfileModesRepository {
  _FakeModesRepository(this.row);

  ProfileLifecycleMode? row;

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async => row;

  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) => Stream.value(row);

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
  }) async {}
}

class _StubSettingsStore implements SettingsStore {
  @override
  Stream<String?> watch(String key) => Stream.value(null);
  @override
  Future<String?> get(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ProfileLifecycleMode _modeRow(LifecycleMode mode) => (
      mode: mode,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    );

Widget _app({
  required Widget child,
  required _FakeModesRepository modes,
}) {
  final entries = _StubDayEntriesRepository();
  final settings = _StubSettingsStore();
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<SettingsStore>.value(value: settings),
      Provider<CyclePredictionService>.value(
        value: CyclePredictionService(entries, settings: settings),
      ),
      Provider<CycleExclusionList>.value(value: CycleExclusionList(settings)),
      Provider<ProfileModesRepository>.value(value: modes),
      ChangeNotifierProvider(
        create: (_) =>
            NotificationPermissionState(NotificationAvailability.available),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  /// The same estimate [OverviewPanel] computes for [_entries] on [_today].
  final estimate = currentConceptionEstimate(
    computePredictionFromEntries(entries: _entries, today: _today)
        as ActivePrediction,
  )!;

  testWidgets('ConceiveCard renders the curve, peak day, and the full '
      'disclaimer treatment', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConceiveCard(
          estimate: estimate,
          dateText: (date) => date.iso,
        ),
      ),
    ));

    expect(find.byKey(const ValueKey('conceive-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('conceive-window')), findsOneWidget);
    expect(find.byKey(const ValueKey('conceive-peak')), findsOneWidget);

    // AC3/AC6: the evidence basis and the contraception disclaimer render,
    // verbatim, next to the value.
    expect(find.text(kConceiveEvidenceBasis), findsOneWidget);
    expect(find.text(kConceiveDisclaimer), findsOneWidget);
    // The #143 contraception warning still renders too — never softened.
    expect(find.text(kFertileWindowDisclaimer), findsOneWidget);
  });

  testWidgets('OverviewPanel mounts the Conceive card above the ordinary '
      'estimate while in Conceive mode (AC1)', (tester) async {
    await tester.pumpWidget(_app(
      modes: _FakeModesRepository(_modeRow(LifecycleMode.conceive)),
      child: OverviewPanel(profileId: 'p', todayProvider: () => _today),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('conceive-card')), findsOneWidget);
    // The conception curve is the headline: it sits above the ordinary
    // Today card, which still renders below it.
    final cardY =
        tester.getTopLeft(find.byKey(const ValueKey('conceive-card'))).dy;
    final todayY = tester.getTopLeft(find.byType(TodayCard)).dy;
    expect(cardY, lessThan(todayY));
  });

  testWidgets('OverviewPanel outside Conceive mode renders no Conceive card',
      (tester) async {
    await tester.pumpWidget(_app(
      modes: _FakeModesRepository(_modeRow(LifecycleMode.tracking)),
      child: OverviewPanel(profileId: 'p', todayProvider: () => _today),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('conceive-card')), findsNothing);
  });
}
