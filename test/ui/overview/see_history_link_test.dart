/// Widget tests for the Today tab's "See cycle history" link inside a shell
/// (`OverviewPanel` under an `AppShellScope`).
///
/// The link switches to Insights, whose `CycleHistorySection` renders
/// nothing until a period has been logged. It used to show for every
/// profile inside a shell, so a profile that had only its onboarding
/// answers was offered a link to an empty place. It now shows only when the
/// profile has cycle history, read off the same `CycleHistoryView` the
/// section renders.
///
/// The no-shell half of the gate (issue #314) stays where it was, in
/// `test/ui/overview_test.dart`; the tab switch through the real shell is
/// in `test/ui/app_shell_test.dart`.
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
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/app_shell_scope.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:provider/provider.dart';

import '../../support/erroring_day_entries_repository.dart';

/// Fixed "today" so the seeded estimates are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

const Key kLink = ValueKey('overview-see-history-link');

/// Rendered by the panel's body in every prediction state, so finding it
/// proves the panel got past loading and the link's absence is a decision.
const Key kPanelBody = ValueKey('overview-disclaimer');

/// Onboarding answers that seed a provisional estimate on [kToday]: last
/// period 2026-08-07, 28-day cycle.
final LocalDate kOnboardingLastPeriod = LocalDate(2026, 8, 7);
const int kOnboardingCycleDays = 28;

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    profiles = DriftProfilesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    entries = DriftDayEntriesRepository(db.storage);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftSettingsStore settings;
  late final DriftDayEntriesRepository entries;

  /// Every tab the link asked the shell to switch to.
  final List<AppTab> selected = [];

  /// A profile whose onboarding answers seed a provisional estimate, with
  /// nothing logged.
  Future<Profile> createOnboardedProfile(String name) => profiles.create(
        displayName: name,
        isMinor: false,
        lastPeriodStart: kOnboardingLastPeriod,
        typicalCycleLengthDays: kOnboardingCycleDays,
        typicalPeriodLengthDays: 5,
      );

  /// Logs a four-day period starting on each of [starts].
  Future<void> logPeriods(String profileId, List<LocalDate> starts) async {
    for (final start in starts) {
      for (var i = 0; i < 4; i++) {
        await entries.save(
          DayEntry(
            id: '',
            profileId: profileId,
            localDate: start.addDays(i),
            tz: 'America/Chicago',
            flow: FlowLevel.medium,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
      }
    }
  }

  /// Pumps a bare [OverviewPanel] for [profileId]. [inShell] mounts the
  /// `AppShellScope` a real shell provides; [historyService] is what the
  /// tree offers as `CycleHistoryService` (null: none at all).
  Future<void> pump(
    String profileId, {
    bool inShell = true,
    bool withHistoryService = true,
    CycleHistoryService? historyService,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Widget panel = Scaffold(
      body: OverviewPanel(profileId: profileId, todayProvider: () => kToday),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(value: _predictions),
          if (withHistoryService)
            Provider<CycleHistoryService>.value(
              value: historyService ?? _history,
            ),
          Provider<CycleExclusionList>.value(
            value: CycleExclusionList(settings),
          ),
          ChangeNotifierProvider<NotificationPermissionState>.value(
            value: _permission,
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: inShell
              ? AppShellScope(
                  current: AppTab.today,
                  select: selected.add,
                  child: panel,
                )
              : panel,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  late final CyclePredictionService _predictions = CyclePredictionService(
    entries,
    settings: settings,
    profiles: profiles,
  );
  late final CycleHistoryService _history =
      CycleHistoryService(entries, settings: settings);
  late final NotificationPermissionState _permission =
      NotificationPermissionState(NotificationAvailability.available);

  /// Same drift-stream teardown discipline as the other overview suites.
  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a profile with only its onboarding answers gets no link: '
      'there is an estimate to show, but no cycle history to go and see',
      (tester) async {
    final h = Harness(tester);
    final profile = await h.createOnboardedProfile('Alice');
    await h.pump(profile.id);

    // The estimate itself is there, seeded from the onboarding answers...
    expect(find.text('Provisional'), findsOneWidget);
    expect(find.byKey(const ValueKey('today-card')), findsOneWidget);
    // (The panel is laid out past where the link goes: the disclaimer is
    // the last thing in its list.)
    expect(find.byKey(kPanelBody), findsOneWidget);
    // ...but nothing has been logged, so Insights has no history to show.
    expect(
      find.byKey(kLink),
      findsNothing,
      reason: 'the link would switch to an Insights tab with no history',
    );
    await h.dispose();
  });

  testWidgets('a brand-new profile with no answers and nothing logged gets '
      'no link either', (tester) async {
    final h = Harness(tester);
    final profile =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.pump(profile.id);

    expect(find.byKey(kPanelBody), findsOneWidget);
    expect(find.byKey(kLink), findsNothing);
    await h.dispose();
  });

  testWidgets('a profile with logged periods gets the link, and tapping it '
      'asks the shell for Insights', (tester) async {
    final h = Harness(tester);
    final profile =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.logPeriods(profile.id, [
      LocalDate(2026, 6, 1),
      LocalDate(2026, 6, 29),
      LocalDate(2026, 7, 27),
      LocalDate(2026, 8, 24),
    ]);
    await h.pump(profile.id);

    expect(find.byKey(kLink), findsOneWidget);
    expect(find.text('See cycle history'), findsOneWidget);

    await tester.tap(find.byKey(kLink));
    await tester.pump();
    expect(h.selected, [AppTab.insights]);
    await h.dispose();
  });

  testWidgets('one logged period is history, even though the estimate is '
      'still provisional -- the estimate\'s tier cannot decide the link',
      (tester) async {
    final h = Harness(tester);
    final profile = await h.createOnboardedProfile('Alice');
    await h.logPeriods(profile.id, [LocalDate(2026, 8, 20)]);
    await h.pump(profile.id);

    expect(find.text('Provisional'), findsOneWidget,
        reason: 'one logged period completes no cycle');
    expect(
      find.byKey(kLink),
      findsOneWidget,
      reason: 'Insights lists that period as the open cycle',
    );
    await h.dispose();
  });

  testWidgets('the link appears the moment a first period is logged and '
      'goes again when that entry is deleted', (tester) async {
    final h = Harness(tester);
    final profile = await h.createOnboardedProfile('Alice');
    await h.pump(profile.id);
    expect(find.byKey(kLink), findsNothing);

    await h.entries.save(
      DayEntry(
        id: '',
        profileId: profile.id,
        localDate: kToday,
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLink), findsOneWidget);

    await h.entries.delete(profile.id, kToday);
    await tester.pumpAndSettle();
    expect(find.byKey(kLink), findsNothing);
    await h.dispose();
  });

  testWidgets('an entry with no bleeding is not cycle history: the link '
      'follows the history list, not "has any entry"', (tester) async {
    final h = Harness(tester);
    final profile = await h.createOnboardedProfile('Alice');
    await h.entries.save(
      DayEntry(
        id: '',
        profileId: profile.id,
        localDate: kToday,
        tz: 'America/Chicago',
        flow: FlowLevel.none,
        tags: const ['cramps'],
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await h.pump(profile.id);

    expect(await h.entries.hasAnyEntries(profile.id), isTrue);
    expect(find.byKey(kPanelBody), findsOneWidget);
    expect(find.byKey(kLink), findsNothing);
    await h.dispose();
  });

  testWidgets('switching the panel to another profile re-decides the link '
      'for that profile', (tester) async {
    final h = Harness(tester);
    final logged =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.logPeriods(logged.id, [
      LocalDate(2026, 7, 27),
      LocalDate(2026, 8, 24),
    ]);
    final onboardedOnly = await h.createOnboardedProfile('Bea');

    await h.pump(logged.id);
    expect(find.byKey(kLink), findsOneWidget);

    await h.pump(onboardedOnly.id);
    expect(find.text('Provisional'), findsOneWidget);
    expect(
      find.byKey(kLink),
      findsNothing,
      reason: 'the previous profile\'s history must not carry over',
    );

    await h.pump(logged.id);
    expect(find.byKey(kLink), findsOneWidget);
    await h.dispose();
  });

  testWidgets('outside a shell there is still no link, with or without '
      'history (the issue #314 gate is unchanged)', (tester) async {
    final h = Harness(tester);
    final profile =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.logPeriods(profile.id, [
      LocalDate(2026, 7, 27),
      LocalDate(2026, 8, 24),
    ]);
    await h.pump(profile.id, inShell: false);

    expect(find.byKey(kPanelBody), findsOneWidget);
    expect(find.byKey(kLink), findsNothing);
    await h.dispose();
  });

  testWidgets('no CycleHistoryService in the tree: no link, and no throw',
      (tester) async {
    final h = Harness(tester);
    final profile =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.logPeriods(profile.id, [
      LocalDate(2026, 7, 27),
      LocalDate(2026, 8, 24),
    ]);
    await h.pump(profile.id, withHistoryService: false);

    expect(find.byKey(kPanelBody), findsOneWidget);
    expect(find.byKey(kLink), findsNothing);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });

  testWidgets('a failing history stream hides the link rather than leaving '
      'a stale one', (tester) async {
    final h = Harness(tester);
    final profile =
        await h.profiles.create(displayName: 'Alice', isMinor: false);
    await h.logPeriods(profile.id, [
      LocalDate(2026, 7, 27),
      LocalDate(2026, 8, 24),
    ]);
    // Only the history service reads through the erroring decorator, so
    // the estimate above the link keeps rendering.
    final erroring = ErroringDayEntriesRepository(h.entries);
    await h.pump(
      profile.id,
      historyService: CycleHistoryService(erroring, settings: h.settings),
    );
    expect(find.byKey(kLink), findsOneWidget);

    erroring.broken = true;
    await h.entries.save(
      DayEntry(
        id: '',
        profileId: profile.id,
        localDate: kToday,
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(kPanelBody), findsOneWidget);
    expect(find.byKey(kLink), findsNothing);
    expect(tester.takeException(), isNull);
    await h.dispose();
  });
}
