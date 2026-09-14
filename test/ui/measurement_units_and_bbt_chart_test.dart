/// Widget tests for:
/// - Issue #457's per-profile BBT/weight display-unit section in Settings
///   ([MeasurementUnitsSettingsSection]).
/// - Issue #245's BBT chart mounted in the Analysis tab ([AnalysisTab]),
///   including its honest empty state.
///
/// Mirrors `test/ui/predictions_toggle_test.dart`'s `Harness` shape, with an
/// [ObservationsRepository] added for the BBT rows the chart reads.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/insights/bbt_chart.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/measurement_unit.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:lunarlog/ui/insights/bbt_chart.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    profiles = DriftProfilesRepository(db.storage);
    entries = DriftDayEntriesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    observations = DriftObservationsRepository(db.storage);
    predictionService = CyclePredictionService(entries, settings: settings);
    historyService = CycleHistoryService(entries, settings: settings);
    exclusions = CycleExclusionList(settings);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftDayEntriesRepository entries;
  late final DriftSettingsStore settings;
  late final DriftObservationsRepository observations;
  late final CyclePredictionService predictionService;
  late final CycleHistoryService historyService;
  late final CycleExclusionList exclusions;

  Widget appFor({
    required Widget home,
    ProfileController? profileController,
  }) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: settings),
        Provider<ObservationsRepository>.value(value: observations),
        Provider<CyclePredictionService>.value(value: predictionService),
        Provider<CycleHistoryService>.value(value: historyService),
        Provider<CycleExclusionList>.value(value: exclusions),
        if (profileController != null)
          ChangeNotifierProvider<ProfileController>.value(
            value: profileController,
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );
  }

  /// Logs a bleed episode of [lengthDays] starting at [start] (mirrors
  /// `predictions_toggle_test.dart`'s own helper), so [AnalysisTab] derives
  /// a real cycle for the BBT chart's cycle-day axis to plot against.
  Future<void> recordBleed(
    String profileId,
    LocalDate start,
    int lengthDays,
  ) async {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: start.addDays(i),
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const [],
          note: null,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }

  /// Seeds a manual `bbt` observation on a day that already has (or gets) a
  /// [DayEntry] — mirrors how the real day sheet always writes both
  /// together via `saveDayEntryWithObservations`: the entry is always
  /// (re)saved, even when one already exists, so `entries.watchForProfile`
  /// always ticks (`AnalysisTab._watchEntries`' entries-tick-triggered
  /// observations refetch, issue #245's doc, depends on that).
  Future<void> recordBbt(
    String profileId,
    LocalDate date,
    double celsius, {
    bool excluded = false,
  }) async {
    final existing = await entries.find(profileId, date);
    final entry = await entries.save(
      (existing ??
              DayEntry(
                id: '',
                profileId: profileId,
                localDate: date,
                tz: 'UTC',
                flow: FlowLevel.none,
                tags: const [],
                note: null,
                updatedAt: DateTime.utc(2026, 1, 1),
              ))
          .copyWith(updatedAt: DateTime.now().toUtc()),
    );
    await observations.save(
      Observation(
        id: '',
        dayEntryId: entry.id,
        profileId: profileId,
        localDate: date,
        tz: 'UTC',
        category: 'bbt',
        valueNum: celsius,
        unit: 'celsius',
        excluded: excluded,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }

  Future<void> dispose() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('MeasurementUnitsSettingsSection (Issue #457)', () {
    testWidgets(
        'single profile: shows unit selectors and switching BBT to '
        'Fahrenheit persists through ProfilesRepository', (tester) async {
      final h = Harness(tester);
      final profile =
          await h.profiles.create(displayName: 'Alice', isMinor: false);
      final controller = ProfileController(
        profilesRepository: h.profiles,
        settingsStore: h.settings,
      );
      await controller.load();

      await tester.pumpWidget(
        h.appFor(home: const SettingsScreen(), profileController: controller),
      );
      await tester.pumpAndSettle();

      final bbtSelector =
          find.byKey(const ValueKey('measurement-units-bbt'));
      final weightSelector =
          find.byKey(const ValueKey('measurement-units-weight'));
      expect(bbtSelector, findsOneWidget);
      expect(weightSelector, findsOneWidget);

      final before = await h.profiles.findById(profile.id);
      expect(before!.bbtUnit, BbtUnit.celsius, reason: 'the default');

      await tester.tap(find.descendant(
        of: bbtSelector,
        matching: find.text('°F'),
      ));
      await tester.pumpAndSettle();

      final after = await h.profiles.findById(profile.id);
      expect(after!.bbtUnit, BbtUnit.fahrenheit);
      expect(
        after.weightUnit,
        WeightUnit.kg,
        reason: 'switching BBT alone never touches the weight preference',
      );

      await tester.tap(find.descendant(
        of: weightSelector,
        matching: find.text('lb'),
      ));
      await tester.pumpAndSettle();

      final afterBoth = await h.profiles.findById(profile.id);
      expect(afterBoth!.weightUnit, WeightUnit.lb);
      expect(
        afterBoth.bbtUnit,
        BbtUnit.fahrenheit,
        reason: 'the earlier BBT switch is not clobbered by the weight one',
      );

      await h.dispose();
    });

    testWidgets('multiple profiles: each gets its own suffixed selectors, '
        'and editing one never touches the other', (tester) async {
      final h = Harness(tester);
      final p1 = await h.profiles.create(displayName: 'Alice', isMinor: false);
      final p2 = await h.profiles.create(displayName: 'Bob', isMinor: false);
      final controller = ProfileController(
        profilesRepository: h.profiles,
        settingsStore: h.settings,
      );
      await controller.load();

      await tester.pumpWidget(
        h.appFor(home: const SettingsScreen(), profileController: controller),
      );
      await tester.pumpAndSettle();

      final p1Bbt =
          find.byKey(ValueKey('measurement-units-bbt-${p1.id}'));
      final p2Bbt =
          find.byKey(ValueKey('measurement-units-bbt-${p2.id}'));
      expect(p1Bbt, findsOneWidget);
      expect(p2Bbt, findsOneWidget);

      await tester.tap(find.descendant(of: p1Bbt, matching: find.text('°F')));
      await tester.pumpAndSettle();

      expect((await h.profiles.findById(p1.id))!.bbtUnit, BbtUnit.fahrenheit);
      expect((await h.profiles.findById(p2.id))!.bbtUnit, BbtUnit.celsius);

      await h.dispose();
    });
  });

  group('AnalysisTab BBT chart (Issue #245)', () {
    testWidgets('a profile with no logged BBT shows the honest empty state, '
        'not a broken/empty chart', (tester) async {
      final h = Harness(tester);
      final profile =
          await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);

      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 1, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('analysis-bbt-chart-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart')), findsNothing);

      await h.dispose();
    });

    testWidgets('logged BBT readings render the chart, keyed by cycle', (
      tester,
    ) async {
      final h = Harness(tester);
      final profile =
          await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBbt(profile.id, LocalDate(2026, 1, 3), 36.5);
      await h.recordBbt(profile.id, LocalDate(2026, 1, 10), 36.9);

      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 1, 15),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('bbt-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsNothing);
      expect(find.byKey(const ValueKey('bbt-chart-caption')), findsOneWidget);
      expect(find.text('1 cycle shown · 36.2°C–37.2°C'), findsOneWidget);

      await h.dispose();
    });

    testWidgets('a newly logged BBT reading updates the already-open chart '
        'once the day entry it rides alongside autosaves (no manual '
        'refresh needed)', (tester) async {
      final h = Harness(tester);
      final profile =
          await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);

      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 1, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsOneWidget);

      // Written directly through the repositories -- the same atomic
      // (entry, observations) write `saveDayEntryWithObservations` performs
      // -- and picked up by the entries-stream-triggered refetch
      // (`AnalysisTab._watchEntries`), not a widget interaction.
      await h.recordBbt(profile.id, LocalDate(2026, 1, 3), 36.6);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('bbt-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsNothing);

      await h.dispose();
    });

    testWidgets('every point excluded (A1-44) reads as no data -- the '
        'empty state, not a chart with an invisible line', (tester) async {
      final h = Harness(tester);
      final profile =
          await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBbt(
        profile.id,
        LocalDate(2026, 1, 3),
        36.5,
        excluded: true,
      );

      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 1, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart')), findsNothing);

      await h.dispose();
    });

    testWidgets('the chart caption reflects the profile\'s Fahrenheit '
        'display preference', (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(
        displayName: 'Alice',
        isMinor: false,
        bbtUnit: BbtUnit.fahrenheit,
      );
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBbt(profile.id, LocalDate(2026, 1, 3), 36.72);

      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            bbtUnit: profile.bbtUnit,
            todayProvider: () => LocalDate(2026, 1, 10),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('°F'),
        findsOneWidget,
        reason: 'the caption converts for the profile\'s display unit',
      );

      await h.dispose();
    });
  });

  group('BbtChart widget (Issue #245) standalone', () {
    testWidgets('empty data renders EmptyState, not a CustomPaint', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BbtChart(data: BbtChartData(series: [], maxCycleDay: 0)),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('bbt-chart-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('bbt-chart')), findsNothing);
    });
  });
}
