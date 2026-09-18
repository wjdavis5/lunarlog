/// Issue #262: responsive layout — the shared max-width constraint, the
/// 7-column calendar cap at narrow and wide viewports, and day-sheet
/// usability in a landscape-sized viewport.
///
/// Purely presentational assertions: no behaviour or state change.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/responsive_body.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// In-memory repository for the calendar harness: delegates to the real
/// drift-backed store, seeded with nothing (the grid renders either way).
class _DelegatingEntriesRepository implements DayEntriesRepository {
  _DelegatingEntriesRepository(this._inner);
  final DriftDayEntriesRepository _inner;

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) => _inner.saveDayEntryWithObservations(
    entry: entry,
    observationsToUpsert: observationsToUpsert,
    observationIdsToDelete: observationIdsToDelete,
  );

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      _inner.find(profileId, localDate);

  @override
  Future<List<DayEntry>> listForProfile(String profileId) =>
      _inner.listForProfile(profileId);

  @override
  Future<bool> hasAnyEntries(String profileId) =>
      _inner.hasAnyEntries(profileId);

  @override
  Stream<bool> watchHasAnyEntries(String profileId) =>
      _inner.watchHasAnyEntries(profileId);

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) => _inner.watchForProfile(profileId, from: from, to: to);

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
    String profileId,
    LocalDate date,
  ) async => const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
    String profileId,
  ) async => const [];
}

/// Never-failing day-sheet repository: saves echo, reads are empty. Mirrors
/// the direct `DaySheet` harness `logging_test.dart` already uses.
class _QuietDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<DayEntry> save(DayEntry entry) async => entry;

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) async => entry;

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => null;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => const [];

  @override
  Future<bool> hasAnyEntries(String profileId) async => false;

  @override
  Stream<bool> watchHasAnyEntries(String profileId) => Stream.value(false);

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) => Stream.value(const []);

  @override
  Future<void> delete(String profileId, LocalDate localDate) async {}

  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
    String profileId,
    LocalDate date,
  ) async => const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
    String profileId,
  ) async => const [];
}

/// Pumps [MonthCalendar] at [physicalSize] and returns the in-memory db so
/// the caller can dispose it (the same explicit pattern
/// `calendar_navigation_test.dart` uses).
Future<LunarLogDatabase> _pumpCalendarAt(
  WidgetTester tester,
  Size physicalSize, {
  ThemeData? theme,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  final entries = _DelegatingEntriesRepository(
    DriftDayEntriesRepository(db.storage),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [Provider<DayEntriesRepository>.value(value: entries)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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

Future<void> _disposeCalendar(WidgetTester tester, LunarLogDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await db.close();
}

Future<void> _pumpDaySheetAt(
  WidgetTester tester,
  Size physicalSize, {
  ThemeData? theme,
  double textScale = 1.0,
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme ?? AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: DaySheet(
          repository: _QuietDayEntriesRepository(),
          profileId: 'p',
          date: kToday,
          today: kToday,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('ResponsiveBody (issue #262 shared max-width constraint)', () {
    /// A child that fills whatever bounded width it is given, so the
    /// assertion measures the actual cap rather than a text's intrinsic
    /// width.
    Widget filler() => const SizedBox.expand(key: ValueKey('filler'));

    testWidgets('fills a narrow viewport without capping', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResponsiveBody(child: filler())),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const ValueKey('filler'))).width, 390);
    });

    testWidgets('caps a wide viewport at the form max width', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResponsiveBody(child: filler())),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const ValueKey('filler'))).width,
        kResponsiveBodyMaxWidth,
      );
    });

    testWidgets('honours a custom max width (calendar grid)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveBody(
              maxWidth: kCalendarGridMaxWidth,
              child: filler(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const ValueKey('filler'))).width,
        kCalendarGridMaxWidth,
      );
    });
  });

  group('calendar grid at narrow and wide viewports (issue #262)', () {
    testWidgets('stays seven columns with sane cells at 390dp', (tester) async {
      final db = await _pumpCalendarAt(tester, const Size(390, 844));

      final delegate =
          tester
                  .widget<GridView>(
                    find.byKey(const ValueKey('calendar-grid-2026-8')),
                  )
                  .gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 7);

      final gridWidth = tester
          .getSize(find.byKey(const ValueKey('calendar-grid-2026-8')))
          .width;
      final cellWidth = gridWidth / 7;
      expect(cellWidth, lessThan(100));
      expect(cellWidth, greaterThan(30));
      expect(find.byKey(const ValueKey('day-cell-2026-08-30')), findsOneWidget);

      await _disposeCalendar(tester, db);
    });

    testWidgets('stays seven columns with capped cells at 1200dp', (
      tester,
    ) async {
      final db = await _pumpCalendarAt(tester, const Size(1200, 800));

      final delegate =
          tester
                  .widget<GridView>(
                    find.byKey(const ValueKey('calendar-grid-2026-8')),
                  )
                  .gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 7);

      final gridWidth = tester
          .getSize(find.byKey(const ValueKey('calendar-grid-2026-8')))
          .width;
      expect(
        gridWidth,
        lessThanOrEqualTo(kCalendarGridMaxWidth + 8),
        reason: 'the grid is capped instead of stretching full-bleed',
      );
      final cellWidth = gridWidth / 7;
      expect(cellWidth, lessThan(115));
      expect(cellWidth, greaterThan(30));
      expect(find.byKey(const ValueKey('day-cell-2026-08-30')), findsOneWidget);

      await _disposeCalendar(tester, db);
    });

    testWidgets('renders in dark mode at large text scale on a tablet', (
      tester,
    ) async {
      final db = await _pumpCalendarAt(
        tester,
        const Size(1200, 800),
        theme: AppTheme.darkTheme,
        textScale: 2.0,
      );

      final delegate =
          tester
                  .widget<GridView>(
                    find.byKey(const ValueKey('calendar-grid-2026-8')),
                  )
                  .gridDelegate
              as SliverGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, 7);
      expect(
        find.byKey(const ValueKey('calendar-weekday-header')),
        findsOneWidget,
      );

      await _disposeCalendar(tester, db);
    });
  });

  group('day sheet in landscape (issue #262)', () {
    testWidgets('chip categories and note field are reachable at 844x390', (
      tester,
    ) async {
      await _pumpDaySheetAt(tester, const Size(844, 390));

      expect(find.byKey(const ValueKey('spotting-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('pms-chip')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('autosave-status')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('note-field')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
    });

    testWidgets('note field stays reachable with the keyboard up', (
      tester,
    ) async {
      // 390dp of height is the ~300dp landscape budget plus a real keyboard
      // inset: the shell pads by viewInsets, so the field must still be
      // scrollable into view rather than hidden behind the keyboard.
      await _pumpDaySheetAt(tester, const Size(844, 390), keyboardInset: 200);

      await tester.ensureVisible(find.byKey(const ValueKey('note-field')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode at both text-scale extremes', (
      tester,
    ) async {
      await _pumpDaySheetAt(
        tester,
        const Size(844, 390),
        theme: AppTheme.darkTheme,
        textScale: 0.8,
      );
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);

      await _pumpDaySheetAt(
        tester,
        const Size(390, 844),
        theme: AppTheme.darkTheme,
        textScale: 2.0,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('note-field')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('note-field')), findsOneWidget);
    });
  });
}
