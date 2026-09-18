/// Issue #763: the day sheet must dismiss from a downward drag started
/// anywhere on its header chrome, not just the ~24px drag handle.
///
/// The sheet is opened exactly the way the app opens it — a
/// `showModalBottomSheet(isScrollControlled: true, showDragHandle: true)`
/// whose body is a `SingleChildScrollView` — so these tests exercise the
/// real call-site shape, not a synthesised one.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

final LocalDate _kToday = LocalDate(2026, 8, 30);

const _headerKey = ValueKey('day-sheet-drag-header');

/// Hosts the same modal-bottom-sheet call the app's two day-sheet entry
/// points use (`month_calendar.dart`'s `_openDay` and
/// `today_log_fab.dart`'s `_openTodaySheet`).
class _SheetHost extends StatelessWidget {
  const _SheetHost(this.repository, this.profileId);

  final DayEntriesRepository repository;
  final String profileId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open-day-sheet'),
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => DaySheet(
              repository: repository,
              profileId: profileId,
              date: _kToday,
              today: _kToday,
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

/// Counts route pops so a double dismiss is observable (issue #791).
class _PopCounter extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
    super.didPop(route, previousRoute);
  }
}

Future<void> _pumpAndOpen(WidgetTester tester) async {
  // A phone-class viewport, so the sheet's editable body genuinely
  // overflows and scrolls (the shape the bug report describes).
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final profile = await DriftProfilesRepository(
    db.storage,
  ).create(displayName: 'Alice', isMinor: false);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(
          value: DriftDayEntriesRepository(db.storage),
        ),
        Provider<ObservationsRepository>.value(
          value: DriftObservationsRepository(db.storage),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: _SheetHost(
          DriftDayEntriesRepository(db.storage),
          profile.id,
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(const ValueKey('open-day-sheet')));
  await tester.pumpAndSettle();
  expect(find.byKey(_headerKey), findsOneWidget, reason: 'sheet did not open');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('issue #763: a downward drag started on the header dismisses '
      'the sheet (previously only the drag handle did)', (tester) async {
    await _pumpAndOpen(tester);

    // Well past `kSheetDragDismissDistance`, starting on the header row.
    await tester.drag(find.byKey(_headerKey), const Offset(0, 140));
    await tester.pumpAndSettle();

    expect(find.byKey(_headerKey), findsNothing);
    expect(find.byType(DaySheet), findsNothing);
  });

  testWidgets('issue #763: the header tolerates jitter and upward drags — '
      'the sheet stays open', (tester) async {
    await _pumpAndOpen(tester);

    await tester.drag(find.byKey(_headerKey), const Offset(0, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(_headerKey), findsOneWidget);

    await tester.drag(find.byKey(_headerKey), const Offset(0, -140));
    await tester.pumpAndSettle();
    expect(find.byKey(_headerKey), findsOneWidget);
  });

  testWidgets('issue #763: the existing drag handle still dismisses',
      (tester) async {
    await _pumpAndOpen(tester);

    // The handle sits at the very top-centre of the sheet, above the
    // header — dragging there must keep working exactly as before.
    final sheet = tester.getRect(find.byType(DaySheet));
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top + 6),
      const Offset(0, 220),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_headerKey), findsNothing);
  });

  testWidgets('issue #763: a downward drag starting on the scrollable content '
      'at offset 0 is left scrolling, not treated as a dismiss', (tester) async {
    await _pumpAndOpen(tester);

    final sheet = tester.getRect(find.byType(DaySheet));
    // Inside the scroll content, well below the pinned header.
    final start = Offset(sheet.center.dx, sheet.top + 260);
    await tester.dragFrom(start, const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(
      find.byKey(_headerKey),
      findsOneWidget,
      reason:
          'content drag is deliberately left to the scroll view (the issue '
          'asks for the header area only); the drag handle and header remain '
          'the dismiss affordances',
    );
  });

  testWidgets('issue #763: a drag starting on an interactive chip does not '
      'dismiss the sheet', (tester) async {
    await _pumpAndOpen(tester);

    // The first interactive chrome below the header: a flow chip.
    final chip = find.byKey(const ValueKey('spotting-chip'));
    expect(chip, findsOneWidget);
    await tester.drag(chip, const Offset(0, 260));
    await tester.pumpAndSettle();

    expect(find.byKey(_headerKey), findsOneWidget);
  });

  testWidgets('issue #791: a fast downward fling on the header pops exactly '
      'once, never the route beneath the sheet', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DriftDayEntriesRepository(db.storage);
    final profile = await DriftProfilesRepository(
      db.storage,
    ).create(displayName: 'Alice', isMinor: false);

    final observer = _PopCounter();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: repository),
          Provider<ObservationsRepository>.value(
            value: DriftObservationsRepository(db.storage),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          navigatorObservers: [observer],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const ValueKey('push-sheet-host'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _SheetHost(repository, profile.id),
                    ),
                  ),
                  child: const Text('Push'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // A route beneath the sheet, so a spurious second pop has somewhere to
    // land and the observer can count it.
    await tester.tap(find.byKey(const ValueKey('push-sheet-host')));
    await tester.pumpAndSettle();
    observer.pops = 0;

    await tester.tap(find.byKey(const ValueKey('open-day-sheet')));
    await tester.pumpAndSettle();
    expect(find.byKey(_headerKey), findsOneWidget);

    // A fast fling crosses BOTH dismiss thresholds: the distance one in
    // `_onDragUpdate`, then the velocity one in `_onDragEnd`.
    await tester.fling(find.byKey(_headerKey), const Offset(0, 200), 2000);
    await tester.pumpAndSettle();

    expect(find.byKey(_headerKey), findsNothing);
    expect(
      observer.pops,
      1,
      reason: 'one fling must dismiss only the sheet, never the route '
          'beneath it (issue #791)',
    );
  });
}
