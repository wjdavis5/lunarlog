/// Widget tests for Issue #650: PR #378 threads `trackingPreferences`/
/// `isMinor` through six real entry points (`AppShell`, `TodayLogFab`,
/// `MonthCalendar`, `OverviewPanel`, `ProfileDetailScreen`,
/// `ActivityFeedScreen`) into `DaySheet`, but every `DaySheet`-level test
/// in `test/ui/logging_test.dart` constructs `DaySheet` directly — a
/// dropped forward at any one of those six sites passes the whole suite
/// unnoticed. These tests instead open the sheet through each real widget
/// and assert both values actually arrived.
///
/// Deliberately its own file (the `calendar_navigation_test.dart`
/// precedent): each test below assembles its own minimal provider tree
/// for the one site under test, rather than growing six already-large
/// suites (`logging_test.dart`, `overview_test.dart`,
/// `calendar_navigation_test.dart`, `activity_feed_test.dart`) with a
/// cross-cutting concern none of them currently covers.
///
/// Fixture: one profile, `isMinor: true`, with a `trackingPreferences`
/// document that explicitly disables `feelings`. Opening the sheet and
/// checking which category headings render proves both signals
/// independently — `feelings` staying hidden proves `trackingPreferences`
/// arrived and was applied, and `partying`/`sex_life` staying hidden
/// (never mentioned in the document, so only the `isMinor`-driven default
/// -- `kMinorDefaultHiddenTrackingCategories` -- can be hiding them) proves
/// `isMinor` arrived too. `Pain` staying visible rules out a sheet that
/// simply rendered nothing.
library;

import 'dart:async' show unawaited;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_activity_feed_repository.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/repositories/mappers.dart' show flowFromDomain;
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/care_modes.dart';
import 'package:lunarlog/domain/logging/tracking_preferences.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/domain/tags.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/app_shell.dart';
import 'package:lunarlog/ui/components/today_log_fab.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/sharing/activity_feed_screen.dart';
import 'package:provider/provider.dart';

/// Fixed "today", matching the other U5/U6 suites' convention.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Disables `feelings` only — `partying`/`sex_life` are deliberately left
/// uncurated so their absence is proof the `isMinor` default fired, not
/// this document.
final TrackingPreferences kCuratedPreferences = TrackingPreferences({
  'feelings': const TrackingCategoryPreference(enabled: false, sortOrder: 0),
});

final String kPartyingLabel =
    careModeCopyFor(ProfileMode.standard).categoryLabel(TagCategory.partying);
final String kSexLifeLabel =
    careModeCopyFor(ProfileMode.standard).categoryLabel(TagCategory.sexLife);

/// Creates the one fixture every test below opens a day sheet for: a minor
/// profile with [kCuratedPreferences] stored.
Future<Profile> curatedMinorProfile(ProfilesRepository profiles) async {
  final created = await profiles.create(displayName: 'Alice', isMinor: true);
  final withPrefs =
      await profiles.setTrackingPreferences(created.id, kCuratedPreferences);
  return withPrefs!;
}

/// Five 28-day episodes ending 2026-07-05 (`overview_test.dart`'s
/// `kLateStarts`): by [kToday] the rolled-forward estimate sits more than
/// two days in the past, so `OverviewPanel` renders the late resolver
/// (and its `Log it` button) instead of the days-until line.
final List<LocalDate> kLateStarts = [
  LocalDate(2026, 3, 15),
  LocalDate(2026, 4, 12),
  LocalDate(2026, 5, 10),
  LocalDate(2026, 6, 7),
  LocalDate(2026, 7, 5),
];

Future<void> seedLateEpisodes(
  DriftDayEntriesRepository entries,
  String profileId,
) async {
  for (final start in kLateStarts) {
    for (var i = 0; i < 4; i++) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: start.addDays(i),
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        tags: const [],
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
    }
  }
}

/// Both forwarding signals in one assertion — see the library doc comment.
void expectForwarded(WidgetTester tester) {
  expect(find.byType(DaySheet), findsOneWidget,
      reason: 'the day sheet must actually be open');
  expect(find.text('Feelings'), findsNothing,
      reason: 'trackingPreferences forwarded: the explicit disable applied');
  expect(find.text(kPartyingLabel), findsNothing,
      reason: 'isMinor forwarded: the minor-hidden default applied');
  expect(find.text(kSexLifeLabel), findsNothing,
      reason: 'isMinor forwarded: the minor-hidden default applied');
  expect(find.text('Pain'), findsOneWidget,
      reason: 'an uncurated, non-hidden category still renders');
}

/// Mirrors `test/ui/activity_feed_test.dart`'s helper of the same name.
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String userId,
  String role, {
  String? displayName,
}) =>
    RemoteProfileGuardianRow(
      id: 'g-$userId',
      profileId: profileId,
      userId: userId,
      role: role,
      status: 'accepted',
      displayName: displayName,
      invitedBy: null,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Same drift-stream teardown discipline every other suite in this
/// directory uses (`logging_test.dart`/`overview_test.dart`/
/// `calendar_navigation_test.dart`/`activity_feed_test.dart`'s own
/// `dispose*` helpers): unmounting the tree first lets a widget's
/// `dispose()` cancel its own timers/subscriptions before the database
/// closes underneath it — skipping this step is what a bare
/// `addTearDown(db.close)` got wrong here originally, tripping
/// flutter_test's own "Timer still pending" invariant on whichever site's
/// widgets keep a live subscription open (`GuardianWatchMixin`, the
/// activity feed's own stream).
Future<void> disposeHarness(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

/// Mirrors `test/ui/activity_feed_test.dart`'s helper of the same name.
RemoteDayEntryRow entryRow(
  String profileId,
  String id,
  LocalDate date, {
  String? loggedByUserId,
}) =>
    RemoteDayEntryRow(
      id: id,
      profileId: profileId,
      localDate: date.iso,
      tz: 'UTC',
      flow: flowFromDomain(FlowLevel.medium),
      tags: const ['cramps'],
      note: null,
      updatedAt: DateTime.utc(2026, 8, 20),
      deletedAt: null,
      loggedByUserId: loggedByUserId,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('TodayLogFab forwards trackingPreferences/isMinor into the '
      'day sheet it opens (Issue #650)', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final profile = await curatedMinorProfile(profiles);

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<DayEntriesRepository>.value(value: entries)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TodayLogFab(
              profileId: profile.id,
              trackingPreferences: profile.trackingPreferences,
              isMinor: profile.isMinor,
              todayProvider: () => kToday,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('today-log-fab')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });

  testWidgets('MonthCalendar forwards trackingPreferences/isMinor into the '
      'day sheet it opens (Issue #650)', (tester) async {
    // The default 800x600 test viewport clips the calendar grid's later
    // rows off-screen (calendar_navigation_test.dart's own setup) — a
    // generously tall viewport is needed so today's cell is actually
    // hittable.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final profile = await curatedMinorProfile(profiles);

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<DayEntriesRepository>.value(value: entries)],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MonthCalendar(
              profileId: profile.id,
              trackingPreferences: profile.trackingPreferences,
              isMinor: profile.isMinor,
              todayProvider: () => kToday,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey('day-cell-${kToday.iso}')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });

  testWidgets('ActivityFeedScreen forwards trackingPreferences/isMinor into '
      'the day sheet a tapped row opens (Issue #650)', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final observations = DriftObservationsRepository(db.storage);
    final activity = DriftActivityFeedRepository(db.storage);
    final profile = await curatedMinorProfile(profiles);

    // A feed needs 2+ accepted guardians to render at all (AC6), plus one
    // entry row to tap through.
    await db.storage.applyRemoteRows([
      guardianRow(profile.id, 'user-mom', 'primary_guardian',
          displayName: 'Mom'),
      guardianRow(profile.id, 'user-dad', 'co_parent', displayName: 'Dad'),
      entryRow(profile.id, 'e-forward', LocalDate(2026, 8, 19),
          loggedByUserId: 'user-mom'),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<ObservationsRepository>.value(value: observations),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ActivityFeedScreen(
            profile: profile,
            repository: activity,
            todayProvider: () => kToday,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester
        .tap(find.byKey(const ValueKey('activity-item-entry:e-forward')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });

  testWidgets('ProfileDetailScreen forwards trackingPreferences/isMinor into '
      'the Calendar tab’s day sheet (Issue #650)', (tester) async {
    // Same generously tall viewport as the MonthCalendar test above — this
    // screen's default tab renders the same calendar grid.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final settings = DriftSettingsStore(db.storage);
    final profile = await curatedMinorProfile(profiles);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(
            value: CyclePredictionService(entries, settings: settings),
          ),
          Provider<CycleHistoryService>.value(
            value: CycleHistoryService(entries, settings: settings),
          ),
          ChangeNotifierProvider(
            create: (_) {
              final controller = ProfileController(
                profilesRepository: profiles,
                settingsStore: settings,
              );
              unawaited(controller.load());
              return controller;
            },
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProfileDetailScreen(
            profile: profile,
            todayProvider: () => kToday,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Defaults to the Calendar tab (initiallyShowOverview defaults false).
    await tester.tap(find.byKey(ValueKey('day-cell-${kToday.iso}')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });

  testWidgets('OverviewPanel forwards trackingPreferences/isMinor into the '
      'late resolver’s day sheet (Issue #650)', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final settings = DriftSettingsStore(db.storage);
    final profile = await curatedMinorProfile(profiles);
    await seedLateEpisodes(entries, profile.id);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(
            value: CyclePredictionService(entries, settings: settings),
          ),
          Provider<CycleHistoryService>.value(
            value: CycleHistoryService(entries, settings: settings),
          ),
          Provider<CycleExclusionList>.value(
            value: CycleExclusionList(settings),
          ),
          ChangeNotifierProvider<NotificationPermissionState>.value(
            value:
                NotificationPermissionState(NotificationAvailability.available),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: OverviewPanel(
              profileId: profile.id,
              trackingPreferences: profile.trackingPreferences,
              isMinor: profile.isMinor,
              todayProvider: () => kToday,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget,
        reason: 'the seeded episodes must actually produce the late state');
    await tester.tap(find.byKey(const ValueKey('resolver-log')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });

  testWidgets('AppShell forwards trackingPreferences/isMinor into the day '
      'sheet its Log-today FAB opens (Issue #650)', (tester) async {
    final db = LunarLogDatabase(NativeDatabase.memory());
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final settings = DriftSettingsStore(db.storage);
    final profile = await curatedMinorProfile(profiles);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(
            value: CyclePredictionService(entries, settings: settings),
          ),
          Provider<CycleHistoryService>.value(
            value: CycleHistoryService(entries, settings: settings),
          ),
          ChangeNotifierProvider<NotificationPermissionState>.value(
            value:
                NotificationPermissionState(NotificationAvailability.available),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppShell(
            profile: profile,
            todayProvider: () => kToday,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // AppShell opens on the Today tab, which is where the FAB already is
    // (Today and Calendar both show it) — no tab switch needed.
    await tester.tap(find.byKey(const ValueKey('today-log-fab')));
    await tester.pumpAndSettle();
    expectForwarded(tester);
    await disposeHarness(tester, db);
  });
}
