/// Issue #196 (Perimenopause mode): the comparison-first Cycle View card —
/// its change-spotting summary, its honest not-enough-cycles state, the
/// route it opens (Issue #235's comparison screen), and its mount in
/// [OverviewPanel] while `profile_modes.mode = 'perimenopause'`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/components/perimenopause_card.dart';
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

/// Three episodes: Jan 1-5 (31-day cycle), Feb 1-5 (37-day cycle), then an
/// open one starting Mar 10. The two completed cycles differ by 6 days, so
/// the card has a real length delta to report.
final List<DayEntry> _threeCycles = [
  for (final start in [d(2026, 1, 1), d(2026, 2, 1), d(2026, 3, 10)])
    for (var offset = 0; offset < 3; offset++)
      _bleed(start.addDays(offset)),
];

/// One logged cycle only — the honest empty state.
final List<DayEntry> _oneCycle = [
  for (var offset = 0; offset < 3; offset++)
    _bleed(d(2026, 3, 1).addDays(offset)),
];

/// Two starts only: one completed cycle plus an open one, so the length line
/// is honestly "still in progress".
final List<DayEntry> _oneCompleted = [
  for (final start in [d(2026, 1, 1), d(2026, 2, 1)])
    for (var offset = 0; offset < 3; offset++)
      _bleed(start.addDays(offset)),
];

class _StubEntries implements DayEntriesRepository {
  _StubEntries(this._entries);

  final List<DayEntry> _entries;

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) =>
      Stream.value(_entries);

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => _entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubSettings implements SettingsStore {
  @override
  Stream<String?> watch(String key) => Stream.value(null);
  @override
  Future<String?> get(String key) async => null;
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

ProfileLifecycleMode _modeRow(LifecycleMode mode) => (
      mode: mode,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    );

class _RouteRecorder extends NavigatorObserver {
  final List<String?> pushedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route.settings.name);
  }
}

Widget _cardApp(
  List<DayEntry> entries, {
  required LocalDate today,
  NavigatorObserver? observer,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: [?observer],
    home: Scaffold(
      body: PerimenopauseCard(
        profileId: 'p',
        todayProvider: () => today,
        dayEntriesRepository: _StubEntries(entries),
      ),
    ),
  );
}

Widget _overviewApp({
  required _FakeModesRepository modes,
  required LifecycleMode lifecycleMode,
}) {
  final entries = _StubEntries(_threeCycles);
  final settings = _StubSettings();
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<SettingsStore>.value(value: settings),
      Provider<CyclePredictionService>.value(
        value: CyclePredictionService(
          entries,
          settings: settings,
          lifecycleModeFor: (_) => Stream.value(lifecycleMode),
        ),
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
      home: Scaffold(
        body: OverviewPanel(
          profileId: 'p',
          todayProvider: () => d(2026, 4, 1),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the change-spotting summary for two completed cycles',
      (tester) async {
    await tester.pumpWidget(_cardApp(_threeCycles, today: d(2026, 4, 1)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perimenopause-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('perimenopause-change-summary')),
      findsOneWidget,
    );
    // 37-day cycle vs 31-day cycle = 6 days longer, stated as text.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('perimenopause-length-change')),
          )
          .data,
      contains('6 days longer'),
    );
    // The emphasis is a weight (issue #808: the ramp's semibold, not w700),
    // never colour-only (a11y).
    final lengthText = tester.widget<Text>(
      find.byKey(const ValueKey('perimenopause-length-change')),
    );
    expect(lengthText.style?.fontWeight, FontWeight.w600);
    // Issue #862: the copy names the completed cycles the card actually
    // compares, never "this cycle" (which every other surface uses for the
    // still-open one).
    expect(lengthText.data, contains('last completed cycle'));
    expect(lengthText.data, isNot(contains('This cycle')));
    expect(
      find.textContaining('the one before it'),
      findsWidgets,
      reason: 'both the length line and the bleed-day line name the pair',
    );
  });

  testWidgets('stays honest with fewer than two cycles', (tester) async {
    await tester.pumpWidget(_cardApp(_oneCycle, today: d(2026, 3, 20)));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('perimenopause-not-enough')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('perimenopause-change-summary')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('perimenopause-compare-button')),
      findsNothing,
    );
  });

  testWidgets('states the current cycle is still in progress when only one '
      'completed cycle exists', (tester) async {
    await tester.pumpWidget(_cardApp(_oneCompleted, today: d(2026, 3, 1)));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('perimenopause-length-change')),
          )
          .data,
      contains('still in progress'),
    );
  });

  testWidgets('the compare button opens the Issue #235 comparison screen',
      (tester) async {
    final recorder = _RouteRecorder();
    await tester.pumpWidget(
      _cardApp(_threeCycles, today: d(2026, 4, 1), observer: recorder),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('perimenopause-compare-button')));
    await tester.pumpAndSettle();

    expect(recorder.pushedRoutes, contains(kRouteCycleComparisonScreen));
  });

  testWidgets('OverviewPanel mounts the card and the suppressed-prediction '
      'card, never a late banner, in Perimenopause mode', (tester) async {
    await tester.pumpWidget(_overviewApp(
      modes: _FakeModesRepository(_modeRow(LifecycleMode.perimenopause)),
      lifecycleMode: LifecycleMode.perimenopause,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perimenopause-card')), findsOneWidget);
    // #528 suppresses prediction for this mode, so the explicit suppressed
    // state renders — there is no days-late countdown left to show.
    expect(find.byKey(const ValueKey('predictions-suppressed')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-days-until')), findsNothing);
    expect(find.byKey(const ValueKey('late-resolver')), findsNothing);
  });

  testWidgets('OverviewPanel in Period Tracking mode renders no '
      'perimenopause card', (tester) async {
    await tester.pumpWidget(_overviewApp(
      modes: _FakeModesRepository(_modeRow(LifecycleMode.tracking)),
      lifecycleMode: LifecycleMode.tracking,
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('perimenopause-card')), findsNothing);
  });
}
