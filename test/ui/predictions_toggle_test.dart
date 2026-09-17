/// Widget tests for issue #225:
/// - Per-profile "show predictions" toggle in Settings
/// - Suppresses estimates, late banners, prediction bands, and prediction reminders when off
/// - Keeps logging, history, and statistics intact
/// - Restores prediction display immediately upon turning back on
/// - Dismissible suggestion offered on irregular confidence tier without flipping toggle
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    profiles = DriftProfilesRepository(db.storage);
    entries = DriftDayEntriesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    predictionService = CyclePredictionService(entries, settings: settings);
    historyService = CycleHistoryService(entries, settings: settings);
    exclusions = CycleExclusionList(settings);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftDayEntriesRepository entries;
  late final DriftSettingsStore settings;
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
        Provider<CyclePredictionService>.value(value: predictionService),
        Provider<CycleHistoryService>.value(value: historyService),
        Provider<CycleExclusionList>.value(value: exclusions),
        ChangeNotifierProvider<NotificationPermissionState>.value(
          value: NotificationPermissionState(NotificationAvailability.available),
        ),
        if (profileController != null)
          ChangeNotifierProvider<ProfileController>.value(value: profileController),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        onGenerateRoute: (routeSettings) {
          final builder = kAppRoutes[routeSettings.name];
          if (builder != null) {
            return buildNamedRoute<void>(
              name: routeSettings.name!,
              builder: builder,
            );
          }
          return null;
        },
        home: Scaffold(body: home),
      ),
    );
  }

  Future<void> recordBleed(String profileId, LocalDate start, int lengthDays) async {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: start.addDays(i),
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
    }
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

  group('Settings predictions toggle', () {
    testWidgets('shows toggle for single profile and toggles predictions on/off',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(displayName: 'Alice', isMinor: false);
      final controller = ProfileController(
        profilesRepository: h.profiles,
        settingsStore: h.settings,
      );
      await controller.load();

      await tester.pumpWidget(
        h.appFor(
          home: const SettingsScreen(),
          profileController: controller,
        ),
      );
      await tester.pumpAndSettle();

      // Find toggle with single profile key
      final toggleFinder = find.byKey(const ValueKey('predictions-toggle'));
      expect(toggleFinder, findsOneWidget);

      final switchTile = tester.widget<SwitchListTile>(toggleFinder);
      expect(switchTile.value, isTrue);

      // Toggle off
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      final storedOff = await h.settings.get(predictionsEnabledSettingKey(profile.id));
      expect(storedOff, 'false');

      // Toggle back on
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      final storedOn = await h.settings.get(predictionsEnabledSettingKey(profile.id));
      expect(storedOn, 'true');

      await h.dispose();
    });

    testWidgets('shows separate toggles for multiple profiles',
        (tester) async {
      final h = Harness(tester);
      final p1 = await h.profiles.create(displayName: 'Alice', isMinor: false);
      final p2 = await h.profiles.create(displayName: 'Bob', isMinor: false);
      final controller = ProfileController(
        profilesRepository: h.profiles,
        settingsStore: h.settings,
      );
      await controller.load();

      await tester.pumpWidget(
        h.appFor(
          home: const SettingsScreen(),
          profileController: controller,
        ),
      );
      await tester.pumpAndSettle();

      final toggle1 = find.byKey(ValueKey('predictions-toggle-${p1.id}'));
      final toggle2 = find.byKey(ValueKey('predictions-toggle-${p2.id}'));
      expect(toggle1, findsOneWidget);
      expect(toggle2, findsOneWidget);

      // Toggle p1 off
      await tester.tap(toggle1);
      await tester.pumpAndSettle();

      expect(await h.settings.get(predictionsEnabledSettingKey(p1.id)), 'false');
      expect(await h.settings.get(predictionsEnabledSettingKey(p2.id)), isNull);

      await h.dispose();
    });
  });

  group('OverviewPanel predictions disabled card', () {
    testWidgets(
        'renders PredictionsDisabledCard and suppresses estimate when off, '
        'and tapping Manage in Settings navigates to Settings', (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 3, 26), 4);

      // Initially on: shows active prediction card
      await tester.pumpWidget(
        h.appFor(
          home: OverviewPanel(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 4, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('overview-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-days-until')), findsOneWidget);
      expect(find.byKey(const ValueKey('predictions-disabled')), findsNothing);

      // Turn predictions off
      await h.settings.set(predictionsEnabledSettingKey(profile.id), 'false');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('predictions-disabled')), findsOneWidget);
      expect(find.byKey(const ValueKey('predictions-disabled-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-active')), findsNothing);
      expect(find.byKey(const ValueKey('overview-days-until')), findsNothing);

      // Tap "Manage in Settings"
      await tester.tap(find.byKey(const ValueKey('predictions-disabled-settings-btn')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);

      await h.dispose();
    });
  });

  group('OverviewPanel irregular suggestion card', () {
    testWidgets(
        'shows dismissible suggestion card when tier is irregular, '
        'settings button navigates without toggling, and dismiss hides it',
        (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(displayName: 'Alice', isMinor: false);
      // Irregular spread: cycles 15, 60, 15
      await h.recordBleed(profile.id, LocalDate(2026, 3, 1), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 3, 16), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 5, 15), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 5, 30), 4);

      await tester.pumpWidget(
        h.appFor(
          home: OverviewPanel(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 6, 5),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final suggestionCard =
          find.byKey(const ValueKey('overview-irregular-prediction-suggestion'));
      expect(suggestionCard, findsOneWidget);

      // Tap Manage in Settings: opens Settings, does NOT change predictions toggle
      await tester.tap(find.byKey(const ValueKey('irregular-suggestion-settings')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(await h.settings.get(predictionsEnabledSettingKey(profile.id)), isNull);

      // Navigate back to overview
      final NavigatorState navigator = tester.state(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      expect(suggestionCard, findsOneWidget);

      // Tap Dismiss
      await tester.tap(find.byKey(const ValueKey('irregular-suggestion-dismiss')));
      await tester.pumpAndSettle();

      expect(suggestionCard, findsNothing);
      expect(
        await h.settings.get(predictionsSuggestionDismissedSettingKey(profile.id)),
        'true',
      );

      await h.dispose();
    });
  });

  group('OverviewPanel long cycle predictions off button', () {
    testWidgets('navigates to Settings when tapped', (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(displayName: 'Alice', isMinor: false);
      // Open cycle > 60 days
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 3, 26), 4);

      await tester.pumpWidget(
        h.appFor(
          home: OverviewPanel(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 6, 1), // 67 days after March 26
          ),
        ),
      );
      await tester.pumpAndSettle();

      final btn = find.byKey(const ValueKey('long-cycle-predictions-off'));
      await tester.scrollUntilVisible(btn, 100);
      expect(btn, findsOneWidget);

      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);

      await h.dispose();
    });
  });

  group('AnalysisTab predictions disabled', () {
    testWidgets(
        'renders PredictionsDisabledCard, suppresses stats card, '
        'and keeps CycleHistorySection intact', (tester) async {
      final h = Harness(tester);
      final profile = await h.profiles.create(displayName: 'Alice', isMinor: false);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await h.recordBleed(profile.id, LocalDate(2026, 3, 26), 4);

      // With predictions on
      await tester.pumpWidget(
        h.appFor(
          home: AnalysisTab(
            profileId: profile.id,
            todayProvider: () => LocalDate(2026, 4, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('analysis-stats')), findsOneWidget);
      expect(find.byType(CycleHistorySection), findsOneWidget);
      expect(find.byKey(const ValueKey('predictions-disabled')), findsNothing);

      // Turn predictions off
      await h.settings.set(predictionsEnabledSettingKey(profile.id), 'false');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('predictions-disabled')), findsOneWidget);
      expect(find.byKey(const ValueKey('analysis-stats')), findsNothing);
      expect(find.byType(CycleHistorySection), findsOneWidget);

      await h.dispose();
    });
  });
}

