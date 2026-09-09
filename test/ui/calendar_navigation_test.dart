/// Widget tests for issue #191: flow-graded calendar cells, the legend
/// strip, swipe navigation (shared with the chevrons and the Today
/// button), the month/year picker, and the weekday-header/grid alignment
/// fix.
///
/// Deliberately its own file rather than an addition to the already large
/// `test/ui/logging_test.dart` (B-2, B-11) — these tests exercise
/// `MonthCalendar` directly against a minimal provider set instead of
/// going through `ProfileDetailScreen`, since none of this issue's
/// features touch attribution/guardians/care-mode wiring.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

/// Fixed "today" (same date `test/ui/logging_test.dart` uses) so month
/// defaults and the forward navigation limit are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

class Harness {
  Harness(this.db, this.profileId);
  final LunarLogDatabase db;
  final String profileId;
}

DayEntry _entryFor(String profileId, LocalDate date, FlowLevel flow) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: date,
  tz: 'America/Chicago',
  flow: flow,
  tags: const [],
  updatedAt: DateTime.utc(2026, 1, 1),
);

Future<Harness> pumpCalendar(
  WidgetTester tester, {
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) await seed(db, profile.id);
  final entries = DriftDayEntriesRepository(db.storage);

  await tester.pumpWidget(
    MultiProvider(
      providers: [Provider<DayEntriesRepository>.value(value: entries)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: MonthCalendar(profileId: profile.id, todayProvider: () => kToday),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, profile.id);
}

Future<void> disposeCalendar(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final colors = AppTheme.lightTheme.extension<LunarLogColors>()!;

  group('legend strip', () {
    testWidgets(
        'keys every mark the grid can show: the four flow levels, a '
        'symptom day, today, and #133\'s predicted band', (tester) async {
      final h = await pumpCalendar(tester);

      expect(find.byKey(const ValueKey('calendar-legend')), findsOneWidget);
      for (final label in [
        'Spotting flow',
        'Light flow',
        'Medium flow',
        'Heavy flow',
        'Symptom day',
        'Today',
        'Predicted day',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing legend entry: $label');
      }
      await disposeCalendar(tester, h);
    });
  });

  group('flow-graded cells', () {
    testWidgets(
        'each bleed level fills with its own flow* ramp token and carries a '
        'distinct dot-count non-colour channel; spotting is a ring, not a '
        'fill', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 1), FlowLevel.spotting));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 2), FlowLevel.light));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 3), FlowLevel.medium));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 4), FlowLevel.heavy));
        },
      );

      const expected = {
        'spotting': (iso: '2026-08-01', marks: 1),
        'light': (iso: '2026-08-02', marks: 2),
        'medium': (iso: '2026-08-03', marks: 3),
        'heavy': (iso: '2026-08-04', marks: 4),
      };

      for (final level in FlowLevel.values) {
        if (level == FlowLevel.none) continue;
        final entry = expected[level.name]!;
        final iso = entry.iso;

        final container = tester.widget<Container>(
          find.byKey(ValueKey('bleed-$iso')),
        );
        final decoration = container.decoration! as BoxDecoration;
        if (level == FlowLevel.spotting) {
          expect(decoration.color, isNull, reason: 'spotting is a ring, never a fill');
          expect(decoration.border, isNotNull);
          expect(find.byKey(ValueKey('flow-spotting-dot-$iso')), findsOneWidget);
        } else {
          expect(decoration.border, isNull);
          expect(
            decoration.color,
            switch (level) {
              FlowLevel.light => colors.flowLight,
              FlowLevel.medium => colors.flowMedium,
              FlowLevel.heavy => colors.flowHeavy,
              _ => throw StateError('unreachable'),
            },
            reason: '$level should fill with its own flow* ramp token',
          );
          expect(find.byKey(ValueKey('flow-spotting-dot-$iso')), findsNothing);
        }

        final marksRow = tester.widget<Row>(
          find.byKey(ValueKey('flow-level-${level.name}-$iso')),
        );
        expect(
          marksRow.children.length,
          entry.marks,
          reason: '$level should carry ${entry.marks} intensity mark(s)',
        );
      }
      await disposeCalendar(tester, h);
    });

    testWidgets('the four flow levels use four visually distinct ramp tones '
        '(no two levels share a colour)', (tester) async {
      final tones = {
        colors.flowSpotting,
        colors.flowLight,
        colors.flowMedium,
        colors.flowHeavy,
      };
      expect(tones, hasLength(4));
    });
  });

  group('swipe navigation', () {
    testWidgets(
        'the chevrons and a drag on the grid both drive the same PageView, '
        'and navigating away and tapping Today returns to the current month',
        (tester) async {
      final h = await pumpCalendar(tester);

      expect(find.text('August 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget,
          reason: 'the chevron still drives the shared PageView');

      await tester.fling(
        find.byKey(const ValueKey('calendar-page-view')),
        const Offset(-700, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget,
          reason: 'a swipe on the grid navigates months too');
      expect(find.byKey(const ValueKey('calendar-grid-2026-10')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('today-button')));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget,
          reason: 'Today jumps back to the current month');
      expect(find.byKey(const ValueKey('day-cell-2026-08-30')), findsOneWidget);

      await disposeCalendar(tester, h);
    });
  });

  group('month/year picker', () {
    testWidgets(
        'tapping the month label opens a picker bounded by the same '
        "forward limit the chevron's nextDisabled already enforces",
        (tester) async {
      final h = await pumpCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('month-year-picker')), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(kSentryRouteNames, contains(kRouteMonthYearPickerDialog));

      await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);

      final septemberButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('month-picker-2027-9')),
      );
      expect(septemberButton.onPressed, isNull,
          reason: 'September 2027 is past the twelve-month forward limit');
      final augustButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('month-picker-2027-8')),
      );
      expect(augustButton.onPressed, isNotNull,
          reason: 'August 2027 is exactly the forward limit and stays reachable');

      await tester.tap(find.byKey(const ValueKey('month-picker-2027-8')));
      await tester.pumpAndSettle();

      expect(find.text('August 2027'), findsOneWidget);
      expect(find.byKey(const ValueKey('month-year-picker')), findsNothing);
      final nextButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next month'),
          matching: find.byType(IconButton),
        ),
      );
      expect(nextButton.onPressed, isNull,
          reason: 'navigation stops twelve months forward, same as chevron-only nav');

      await disposeCalendar(tester, h);
    });

    testWidgets('dismissing the picker without selecting a month leaves the '
        'displayed month unchanged', (tester) async {
      final h = await pumpCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('month-year-picker')), findsOneWidget);

      // Tap the scrim above the sheet to dismiss it without choosing a
      // month (the sheet's builder returns null in this path).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('month-year-picker')), findsNothing);
      expect(find.text('August 2026'), findsOneWidget);

      await disposeCalendar(tester, h);
    });
  });

  group('weekday header / grid alignment', () {
    testWidgets(
        'the weekday header and the day grid share the same horizontal '
        'padding, so the columns line up (issue #191)', (tester) async {
      final h = await pumpCalendar(tester);

      final headerPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('calendar-weekday-header')),
      );
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('calendar-grid-2026-8')),
      );
      expect(headerPadding.padding, grid.padding,
          reason: 'header and grid must share the same horizontal padding');
      expect(headerPadding.padding, const EdgeInsets.symmetric(horizontal: 4));

      await disposeCalendar(tester, h);
    });
  });
}
