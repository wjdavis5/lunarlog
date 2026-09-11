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
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
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

/// Records every `watchForProfile` call's `from`/`to` while delegating
/// everything else to a real [DriftDayEntriesRepository] (issue #197): lets
/// a widget test assert exactly which window `MonthCalendar` subscribed to,
/// and how many times, without faking storage itself.
class RecordingDayEntriesRepository implements DayEntriesRepository {
  RecordingDayEntriesRepository(this._inner);

  final DriftDayEntriesRepository _inner;
  final List<({LocalDate? from, LocalDate? to})> calls = [];

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) =>
      _inner.saveDayEntryWithObservations(
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
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    calls.add((from: from, to: to));
    return _inner.watchForProfile(profileId, from: from, to: to);
  }

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);
}

Future<Harness> pumpCalendar(
  WidgetTester tester, {
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
  // Issue #312 (large-text budget): lets a single test override the text
  // scale MediaQuery reports, without touching every other call site.
  double textScale = 1.0,
  // Issue #312 (today-ring overflow / textScaleFactor overflow review):
  // most tests want a generously tall viewport that never itself risks an
  // overflow, but a couple deliberately need a real phone-class viewport
  // (390x844 logical, dpr 1) so a would-be overflow is the thing under
  // test rather than masked by a desktop-sized canvas.
  Size physicalSize = const Size(800, 1400),
  // Issue #197: lets a test observe the entries repository's
  // `watchForProfile` calls (window bounds, call count) by wrapping the
  // real `DriftDayEntriesRepository` in a `RecordingDayEntriesRepository`.
  DayEntriesRepository Function(DriftDayEntriesRepository real)?
      wrapRepository,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) await seed(db, profile.id);
  final entries = DriftDayEntriesRepository(db.storage);
  final repository = wrapRepository == null ? entries : wrapRepository(entries);

  await tester.pumpWidget(
    MultiProvider(
      providers: [Provider<DayEntriesRepository>.value(value: repository)],
      child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
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
        'symptom day, today, #133\'s predicted band, the PMS/cramps '
        'badges, and the symptom-layer palette (issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      expect(find.byKey(const ValueKey('calendar-legend')), findsOneWidget);
      for (final label in [
        'Light flow',
        'Medium flow',
        'Heavy flow',
        'Super heavy flow (5 marks)',
        'Symptom day',
        'Today',
        'Predicted day',
        'Cramps window',
        'Symptom layer dots',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing legend entry: $label');
      }
      // Issue #247: spotting is no longer a flow level (it reads back as
      // `notBleeding`, which is never a bleed marker) and the ramp has no
      // dedicated slot for it, so the legend no longer carries a
      // "Spotting flow" entry.
      // Issue #220: this harness pumps no prediction service, so no band
      // can exist here at all - the legend must not advertise the PMS
      // swatch when the grid can never show the badge (the positive case
      // lives in forecast_calendar_test.dart's band test, which runs the
      // full provider stack).
      expect(find.text('PMS window'), findsNothing);
      expect(find.text('Spotting flow'), findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets(
        'collapses by default once the text scale reaches the large-text '
        'budget threshold, and a small toggle re-expands it (issue #312)',
        (tester) async {
      final expandedHarness = await pumpCalendar(tester, textScale: 1.5);
      expect(find.byKey(const ValueKey('legend-toggle')), findsOneWidget);
      expect(find.text('Light flow'), findsOneWidget,
          reason: 'below the 1.6 threshold the legend stays expanded');
      await disposeCalendar(tester, expandedHarness);

      final collapsedHarness = await pumpCalendar(tester, textScale: 1.6);
      expect(find.text('Light flow'), findsNothing,
          reason: 'at the 1.6 threshold the legend starts collapsed');

      await tester.tap(find.byKey(const ValueKey('legend-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Light flow'), findsOneWidget,
          reason: 'the toggle re-expands it even at a large text scale');
      await disposeCalendar(tester, collapsedHarness);
    });
  });

  group('flow-graded cells', () {
    testWidgets(
        'each bleed level fills with its own flow* ramp token and carries a '
        'distinct dot-count non-colour channel; superHeavy reuses heavy\'s '
        'ramp token with an extra mark', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 2), FlowLevel.light));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 3), FlowLevel.medium));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 4), FlowLevel.heavy));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 5), FlowLevel.superHeavy));
        },
      );

      const expected = {
        'light': (iso: '2026-08-02', marks: 2),
        'medium': (iso: '2026-08-03', marks: 3),
        'heavy': (iso: '2026-08-04', marks: 4),
        'superHeavy': (iso: '2026-08-05', marks: 5),
      };

      for (final level in FlowLevel.values) {
        final entry = expected[level.name];
        // Issue #247: `none`, the deprecated `spotting` alias, and
        // `notBleeding` are never bleed levels — none of them render a
        // `bleed-<iso>` marker at all, so they are skipped here rather
        // than asserted against a date this test never seeded.
        if (entry == null) continue;
        final iso = entry.iso;

        final container = tester.widget<Container>(
          find.byKey(ValueKey('bleed-$iso')),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.border, isNull);
        expect(
          decoration.color,
          switch (level) {
            FlowLevel.light => colors.flowLight,
            FlowLevel.medium => colors.flowMedium,
            FlowLevel.heavy || FlowLevel.superHeavy => colors.flowHeavy,
            _ => throw StateError('unreachable'),
          },
          reason: '$level should fill with its own flow* ramp token',
        );

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

    testWidgets(
        'the deprecated spotting alias and the explicit notBleeding '
        'assertion both read back as a non-bleed day (Issue #247): neither '
        'renders a bleed marker', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          // ignore: deprecated_member_use_from_same_package
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 6), FlowLevel.spotting));
          await repo.save(_entryFor(profileId, LocalDate(2026, 8, 7), FlowLevel.notBleeding));
        },
      );

      for (final iso in ['2026-08-06', '2026-08-07']) {
        expect(find.byKey(ValueKey('bleed-$iso')), findsNothing);
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

    testWidgets(
        'a bleed day that is also today draws the same ring the legend '
        'advertises as Today (issue #312 — previously dropped for any '
        'bleed level)', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(_entryFor(profileId, kToday, FlowLevel.medium));
        },
      );

      expect(find.byKey(ValueKey('today-ring-${kToday.iso}')), findsOneWidget);
      expect(find.byKey(ValueKey('bleed-${kToday.iso}')), findsOneWidget);
      await disposeCalendar(tester, h);
    });

    testWidgets(
        'a bleed-logged today cell does not overflow a 375pt-class phone '
        'viewport (issue #312, BLOCKING — today-ring wrapper overflow)',
        (tester) async {
      final h = await pumpCalendar(
        tester,
        physicalSize: const Size(390, 844),
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(_entryFor(profileId, kToday, FlowLevel.medium));
        },
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(ValueKey('today-ring-${kToday.iso}')), findsOneWidget);
      await disposeCalendar(tester, h);
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

    testWidgets('a backward swipe on the grid navigates to the previous '
        'month (issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      expect(find.text('August 2026'), findsOneWidget);

      await tester.fling(
        find.byKey(const ValueKey('calendar-page-view')),
        const Offset(700, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget,
          reason: 'a positive-dx (backward) swipe moves to the previous month');

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'a fling past the forward limit stays pinned on the boundary '
        'month — the PageView itemCount bounds it at maxPageIndex + 1 '
        '(issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      // Navigate straight to the twelve-month forward limit via the
      // picker (already covered elsewhere) rather than twelve chevron
      // taps.
      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-2027-8')));
      await tester.pumpAndSettle();
      expect(find.text('August 2027'), findsOneWidget,
          reason: 'August 2027 is exactly the twelve-month forward limit');

      await tester.fling(
        find.byKey(const ValueKey('calendar-page-view')),
        const Offset(-700, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.text('August 2027'), findsOneWidget,
          reason: 'the fling cannot move past the pinned boundary month');

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

  group('_goToMonth guard (issue #312)', () {
    // `canDrivePageController` is the pure predicate `_goToMonth`'s animate
    // and jump paths both now share (previously only the jump path guarded
    // `hasClients`, so an animate call on an unattached `PageController`
    // would throw) — directly unit-testable, unlike the private method
    // itself, since faking an unattached `PageController` isn't observable
    // through any widget-level interaction: every navigation control only
    // renders once the `PageView` (and so its `Scrollable`) has already
    // attached.
    test('does not drive the PageController when it has no clients', () {
      expect(canDrivePageController(hasClients: false), isFalse);
    });

    test('drives the PageController once it is attached', () {
      expect(canDrivePageController(hasClients: true), isTrue);
    });

    testWidgets(
        'two rapid chevron taps land on the correct month, and the header '
        "never rewinds to an earlier month mid-animation (follow-up "
        'review: an `_animateToken` generation counter now guards '
        '`_isAnimatingToMonth`\'s reset, since the first of two '
        'overlapping `animateToPage` calls resolves early — superseded, '
        'not actually settled — once the second one starts)',
        (tester) async {
      final h = await pumpCalendar(tester);

      final labelFinder = find.descendant(
        of: find.byKey(const ValueKey('month-year-label')),
        matching: find.byType(Text),
      );
      String headerText() => tester.widget<Text>(labelFinder).data!;

      const order = ['August 2026', 'September 2026', 'October 2026'];
      expect(headerText(), 'August 2026');

      await tester.tap(find.byTooltip('Next month'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byTooltip('Next month'));

      var lastIndex = order.indexOf(headerText());
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final idx = order.indexOf(headerText());
        if (idx == -1) continue;
        expect(idx, greaterThanOrEqualTo(lastIndex),
            reason: 'header rewound from ${order[lastIndex]} to '
                '${order[idx]}');
        lastIndex = idx;
      }
      await tester.pumpAndSettle();

      expect(headerText(), 'October 2026',
          reason: 'two forward taps from August land on October');

      await disposeCalendar(tester, h);
    });
  });

  group('large text budget (issue #312)', () {
    testWidgets(
        'at textScaleFactor 2.0 on a phone-class viewport the calendar '
        'renders without an overflow (issue #312 review: an 800x1400 '
        'desktop-sized canvas made this test vacuous — the legend '
        'collapse only actually matters on a real phone width)',
        (tester) async {
      final h = await pumpCalendar(
        tester,
        textScale: 2.0,
        physicalSize: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('calendar-page-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('legend-toggle')), findsOneWidget,
          reason: 'the legend is collapsed, not absent, at this scale');

      await disposeCalendar(tester, h);
    });
  });

  group('windowed entries subscription (issue #197)', () {
    test('calendarEntriesWindowFor is 45 days each side of the displayed '
        "month's own first/last day, inclusive", () {
      final (from, to) = calendarEntriesWindowFor(2026, 8);
      expect(from, LocalDate(2026, 8, 1).addDays(-45));
      expect(to, LocalDate(2026, 8, 31).addDays(45));
      expect(kCalendarWindowLookbehindDays, 45);
      expect(kCalendarWindowLookaheadDays, 45);
    });

    test(
        'the window for any displayed month covers month−1\'s first day '
        'through month+1\'s last day (review follow-up: a neighbour page '
        'rendered mid-drag must never be missing entries) — checked '
        'across every month, including both year boundaries', () {
      LocalDate firstOfMonth(int y, int m) => LocalDate(y, m, 1);
      LocalDate lastOfMonth(int y, int m) {
        final firstOfNext =
            m == 12 ? LocalDate(y + 1, 1, 1) : LocalDate(y, m + 1, 1);
        return firstOfNext.addDays(-1);
      }

      for (var year = 2024; year <= 2028; year++) {
        for (var month = 1; month <= 12; month++) {
          final (from, to) = calendarEntriesWindowFor(year, month);
          final (prevYear, prevMonth) =
              month == 1 ? (year - 1, 12) : (year, month - 1);
          final (nextYear, nextMonth) =
              month == 12 ? (year + 1, 1) : (year, month + 1);
          final prevFirst = firstOfMonth(prevYear, prevMonth);
          final nextLast = lastOfMonth(nextYear, nextMonth);
          expect(from.isAfter(prevFirst), isFalse,
              reason: 'window for $year-$month starts $from, which is '
                  'after $prevMonth\'s first day $prevFirst');
          expect(to.isBefore(nextLast), isFalse,
              reason: 'window for $year-$month ends $to, which is before '
                  '$nextMonth\'s last day $nextLast');
        }
      }
    });

    testWidgets(
        'subscribes once, to the displayed month\'s window — not full '
        'history', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) => recording = RecordingDayEntriesRepository(real),
      );

      expect(recording.calls, hasLength(1));
      final (expectedFrom, expectedTo) = calendarEntriesWindowFor(2026, 8);
      expect(recording.calls.single.from, expectedFrom);
      expect(recording.calls.single.to, expectedTo);

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'paging one month at a time stays on the same subscription while '
        'still inside its window, and only resubscribes once the '
        "displayed month's own range moves past the fetched window's edge",
        (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) => recording = RecordingDayEntriesRepository(real),
      );
      expect(recording.calls, hasLength(1));

      // September 2026 is comfortably inside August's [Jun 17, Oct 15]
      // window (calendarEntriesWindowFor(2026, 8)) — no resubscribe.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(recording.calls, hasLength(1),
          reason: 'September is still fully inside the window fetched for '
              'August');

      // October's last day (Oct 31) is past that window's Oct 15 edge —
      // this move must trigger a fresh, re-centered subscription.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);
      expect(recording.calls, hasLength(2),
          reason: "October's last day falls outside the window fetched "
              'for August');
      final (expectedFrom, expectedTo) = calendarEntriesWindowFor(2026, 10);
      expect(recording.calls.last.from, expectedFrom);
      expect(recording.calls.last.to, expectedTo);

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'a profile switch forces a fresh subscription even though the '
        'displayed month is unchanged', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) => recording = RecordingDayEntriesRepository(real),
      );
      expect(recording.calls, hasLength(1));

      final secondProfile = await DriftProfilesRepository(h.db.storage)
          .create(displayName: 'Bea', isMinor: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [Provider<DayEntriesRepository>.value(value: recording)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MonthCalendar(
                profileId: secondProfile.id,
                todayProvider: () => kToday,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(recording.calls, hasLength(2),
          reason: 'switching profiles must not reuse the old profile\'s '
              'window/subscription');
      expect(recording.calls.last.from, recording.calls.first.from);
      expect(recording.calls.last.to, recording.calls.first.to,
          reason: 'the new subscription still starts on the same '
              "(today's) displayed month");

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'crossing the window boundary and back: a jump far forward past '
        "the window hides an entry logged in the original month, and "
        'jumping back to Today re-subscribes and shows it again, with no '
        'exceptions along the way', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 8, 5), FlowLevel.medium),
          );
        },
      );

      expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-month-empty-2026-8')),
          findsNothing);

      // Jump to March 2027 via the picker — well past the ±45-day window
      // fetched for August 2026.
      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-2027-3')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('March 2027'), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsNothing,
          reason: 'August 2026 is not the displayed page any more');
      expect(find.byKey(const ValueKey('calendar-month-empty-2027-3')),
          findsOneWidget,
          reason: 'the only seeded entry is outside March 2027\'s window');

      // Jump back to Today.
      await tester.tap(find.byKey(const ValueKey('today-button')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget,
          reason: 'paging back into range must re-subscribe and show the '
              'entry again, not stay stuck on a stale window');
      expect(find.byKey(const ValueKey('calendar-month-empty-2026-8')),
          findsNothing);

      await disposeCalendar(tester, h);
    });

    testWidgets(
        "the neighbour month's entries are in the window (review "
        'follow-up): entries on month−1\'s first day and month+1\'s last '
        "day are already covered by August's own subscription — paging "
        'to either neighbour shows them with no resubscribe', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) => recording = RecordingDayEntriesRepository(real),
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          // July 1, 2026 is August's month−1's first day; September 30,
          // 2026 is August's month+1's last day.
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 7, 1), FlowLevel.medium),
          );
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 9, 30), FlowLevel.medium),
          );
        },
      );
      expect(recording.calls, hasLength(1));

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-07-01')), findsOneWidget,
          reason: "month−1's first day must already be in the window "
              "fetched for August");
      expect(recording.calls, hasLength(1),
          reason: 'no resubscribe should have been needed to show it');

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('bleed-2026-09-30')), findsOneWidget,
          reason: "month+1's last day must already be in the window "
              "fetched for August");
      expect(recording.calls, hasLength(1),
          reason: 'no resubscribe should have been needed to show it '
              'either');

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'a window crossing renders no full-bleed spinner and keeps the '
        'PageView mounted, checked on the very frame after the crossing '
        '(review follow-up: pumped without settling, since settling would '
        'let the replacement stream\'s first emission land and mask the '
        'gap this guards)', (tester) async {
      final h = await pumpCalendar(tester);

      // August -> September stays inside August's window, no crossing.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      // September -> October crosses the window fetched for August
      // (October's last day is past that window's edge) — this is the
      // resubscribe [_maybeRewatchEntriesFor] triggers synchronously in
      // the tap handler, before the new stream has ever emitted.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump(); // exactly one frame — deliberately no settle
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'a window crossing must keep rendering the previous '
              "window's entries instead of a full-bleed spinner");
      expect(find.byKey(const ValueKey('calendar-page-view')), findsOneWidget,
          reason: 'the PageView must stay mounted through the crossing, '
              'not be replaced by a spinner mid-animation');

      await disposeCalendar(tester, h);
    });
  });
}
