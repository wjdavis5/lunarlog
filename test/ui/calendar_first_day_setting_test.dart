/// Issue #226 consumption coverage: the Calendar section's "First day of
/// week" setting (`SettingsKeys.calendarFirstDayOfWeek`) actually reaches
/// the month grid — both the seeded value (a store that already holds
/// `'monday'` when the calendar mounts) and a live change (the picker
/// writing while the calendar is on screen, through the store's `watch`).
///
/// The date-format half's consumption is pure (`dates.dart`'s
/// preference-aware helpers plus `daySheetDateLabel`); see
/// `test/ui/l10n/dates_test.dart`'s Issue #226 group.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

import '../support/fake_settings_store.dart';

/// Same fixed "today" as `test/ui/calendar_navigation_test.dart` (August
/// 2026), so the displayed month is deterministic: August 1, 2026 is a
/// Saturday, giving 6 leading blanks under a Sunday start and 5 under a
/// Monday start.
final LocalDate kToday = LocalDate(2026, 8, 30);

Future<LunarLogDatabase> pumpCalendar(
  WidgetTester tester,
  FakeSettingsStore settings,
) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  final entries = DriftDayEntriesRepository(db.storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: settings),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: MonthCalendar(
            profileId: profile.id,
            todayProvider: () => kToday,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

/// The same teardown shape `test/ui/calendar_navigation_test.dart` uses:
/// unmount first, pump long enough for drift's zero-duration
/// `markAsClosed` timer (scheduled while the calendar's stream
/// subscriptions cancel) to actually fire, then close the database — a
/// plain `addTearDown(db.close())` leaves that timer pending and fails
/// the binding's invariants check.
Future<void> disposeCalendar(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

/// The weekday header's first visible initial, read off the header row's
/// `Text` children in layout order.
String firstHeaderInitial(WidgetTester tester) {
  final header = find.byKey(const ValueKey('calendar-weekday-header'));
  final texts = tester.widgetList<Text>(
    find.descendant(of: header, matching: find.byType(Text)),
  );
  return texts.first.data!;
}

void main() {
  testWidgets(
      'default (unset) keeps the Sunday-start layout the calendar has '
      'always had', (tester) async {
    final settings = FakeSettingsStore();
    addTearDown(settings.close);
    final db = await pumpCalendar(tester, settings);
    try {
      expect(firstHeaderInitial(tester), 'S');
      // August 1, 2026 is a Saturday: six leading blanks under Sunday
      // start.
      expect(
        find.byKey(const ValueKey('calendar-leading-blank-2026-8-5')),
        findsOneWidget,
      );
    } finally {
      await disposeCalendar(tester, db);
    }
  });

  testWidgets(
      "a stored 'monday' override re-lays-out the grid: the header starts "
      'on M and one fewer leading blank precedes August 1', (tester) async {
    final settings = FakeSettingsStore({
      SettingsKeys.calendarFirstDayOfWeek: 'monday',
    });
    addTearDown(settings.close);
    final db = await pumpCalendar(tester, settings);
    try {
      expect(firstHeaderInitial(tester), 'M');
      expect(
        find.byKey(const ValueKey('calendar-leading-blank-2026-8-4')),
        findsOneWidget,
        reason: 'Monday start puts five blanks before Saturday Aug 1',
      );
      expect(
        find.byKey(const ValueKey('calendar-leading-blank-2026-8-5')),
        findsNothing,
      );
    } finally {
      await disposeCalendar(tester, db);
    }
  });

  testWidgets(
      'a live change through the store (what the Settings picker writes) '
      're-renders the mounted calendar', (tester) async {
    final settings = FakeSettingsStore();
    addTearDown(settings.close);
    final db = await pumpCalendar(tester, settings);
    try {
      expect(firstHeaderInitial(tester), 'S');

      await settings.set(SettingsKeys.calendarFirstDayOfWeek, 'monday');
      await tester.pumpAndSettle();

      expect(firstHeaderInitial(tester), 'M');
    } finally {
      await disposeCalendar(tester, db);
    }
  });
}
