/// Widget tests for issue #235: the "Compare cycles" selection mode added
/// to [CycleHistorySection] (opt-in via `onCompareSelected`, so every
/// pre-#235 caller/test is unaffected), [CycleComparisonView]'s aligned
/// rendering and empty state, and [CycleComparisonScreen]'s live wiring.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/insights/cycle_comparison.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/cycle_comparison_screen.dart';
import 'package:lunarlog/ui/insights/cycle_comparison_view.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:provider/provider.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// Three 28-day cycles ending Aug 5 (open) -- enough to exercise
/// selection with a completed pair and with the open cycle.
final List<LocalDate> kStarts = [
  LocalDate(2026, 6, 8),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

Future<void> _seed(
  DriftDayEntriesRepository entries,
  String profileId,
  List<LocalDate> starts, {
  int lengthDays = 4,
  List<String> tags = const [],
}) async {
  for (final start in starts) {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profileId,
          localDate: start.addDays(i),
          tz: 'America/Chicago',
          flow: i == 0 ? FlowLevel.heavy : FlowLevel.medium,
          tags: i == 0 ? tags : const [],
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }
}

class _HistoryHarness {
  _HistoryHarness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  late String profileId;
  List<(LocalDate, LocalDate)> compareCalls = [];

  Widget _appFor(String profileId, {bool comparable = true}) {
    final settings = DriftSettingsStore(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    return MultiProvider(
      providers: [
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        Provider<CycleExclusionList>.value(value: CycleExclusionList(settings)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CycleHistorySection(
            profileId: profileId,
            todayProvider: () => kToday,
            onCompareSelected: comparable
                ? (a, b) => compareCalls.add((a, b))
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> pump({bool comparable = true}) async {
    final profiles = DriftProfilesRepository(db.storage);
    final entries = DriftDayEntriesRepository(db.storage);
    final profile = await profiles.create(displayName: 'Alice', isMinor: false);
    profileId = profile.id;
    await _seed(entries, profile.id, kStarts);
    await tester.pumpWidget(_appFor(profile.id, comparable: comparable));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('CycleHistorySection compare selection (issue #235)', () {
    testWidgets('hidden entirely when onCompareSelected is null', (tester) async {
      final h = _HistoryHarness(tester);
      await h.pump(comparable: false);

      expect(find.byKey(const ValueKey('history-compare-toggle')), findsNothing);

      await h.dispose();
    });

    testWidgets(
      'toggling in shows a checkbox per row; selecting two enables Compare, '
      'a third stays disabled, and Compare calls back with oldest first',
      (tester) async {
        final h = _HistoryHarness(tester);
        await h.pump();

        expect(
          find.byKey(const ValueKey('history-compare-toggle')),
          findsOneWidget,
        );
        expect(find.text('Compare cycles'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('history-compare-toggle')));
        await tester.pumpAndSettle();

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0 of 2 selected'), findsOneWidget);
        final compareButton = find.byKey(const ValueKey('history-compare-open'));
        expect(tester.widget<FilledButton>(compareButton).onPressed, isNull);

        // Select the two most recent completed cycles: Jun 8 and Jul 6.
        await tester.tap(
          find.byKey(const ValueKey('history-compare-select-2026-07-06')),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 of 2 selected'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey('history-compare-select-2026-06-08')),
        );
        await tester.pumpAndSettle();
        expect(find.text('2 of 2 selected'), findsOneWidget);
        expect(tester.widget<FilledButton>(compareButton).onPressed, isNotNull);

        // A third (the open cycle) is disabled at the cap.
        final openCheckbox = tester.widget<Checkbox>(
          find.byKey(const ValueKey('history-compare-select-2026-08-05')),
        );
        expect(openCheckbox.onChanged, isNull);

        await tester.tap(compareButton);
        await tester.pumpAndSettle();

        expect(h.compareCalls, hasLength(1));
        expect(
          h.compareCalls.single,
          (LocalDate(2026, 6, 8), LocalDate(2026, 7, 6)),
          reason: 'oldest-first regardless of tap order',
        );
        // Selection mode exits after opening the comparison.
        expect(find.byKey(const ValueKey('history-compare-open')), findsNothing);
        expect(find.text('Compare cycles'), findsOneWidget);

        await h.dispose();
      },
    );

    testWidgets('Cancel exits selection mode and clears the selection', (
      tester,
    ) async {
      final h = _HistoryHarness(tester);
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('history-compare-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('history-compare-select-2026-07-06')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('history-compare-toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Compare cycles'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-compare-select-2026-07-06')),
        findsNothing,
        reason: 'checkboxes are gone once selection mode is off',
      );

      // Re-entering starts from a clean slate.
      await tester.tap(find.byKey(const ValueKey('history-compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 selected'), findsOneWidget);

      await h.dispose();
    });

    testWidgets('unchecking a selected cycle drops it from the count', (
      tester,
    ) async {
      final h = _HistoryHarness(tester);
      await h.pump();

      await tester.tap(find.byKey(const ValueKey('history-compare-toggle')));
      await tester.pumpAndSettle();
      final checkbox =
          find.byKey(const ValueKey('history-compare-select-2026-07-06'));
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 selected'), findsOneWidget);

      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 selected'), findsOneWidget);

      await h.dispose();
    });
  });

  group('CycleComparisonView (issue #235)', () {
    testWidgets('null data renders the honest not-enough-cycles empty state', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: CycleComparisonView(data: null)),
        ),
      );

      expect(
        find.byKey(const ValueKey('cycle-comparison-empty')),
        findsOneWidget,
      );
      expect(find.text('Nothing to compare yet'), findsOneWidget);
    });

    testWidgets(
      'issue #850 (U8): the empty-state body is third-person for a guardian '
      'and unchanged for the subject',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CycleComparisonView(
                data: null,
                lens: GuardianLens.guardian,
              ),
            ),
          ),
        );
        expect(
          find.text(
            "Select two cycles from this profile's cycle history to compare "
            'them side by side.',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('from your cycle history'),
          findsNothing,
        );

        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CycleComparisonView(
                data: null,
                lens: GuardianLens.subject,
              ),
            ),
          ),
        );
        expect(
          find.text(
            'Select two cycles from your cycle history to compare them side '
            'by side.',
          ),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('aligns two cycles by cycle day, showing flow, tags, and the '
        'excluded badge', (tester) async {
      final data = deriveCycleComparison(
        // A third (Mar 1) episode makes cycle B ("Feb 1") a completed
        // 28-day cycle rather than the still-open one.
        episodes: [
          for (final start in [
            LocalDate(2026, 1, 1),
            LocalDate(2026, 2, 1),
            LocalDate(2026, 3, 1),
          ])
            Episode(start, start),
        ],
        entries: [
          DayEntry(
            id: 'a',
            profileId: 'p1',
            localDate: LocalDate(2026, 1, 1),
            tz: 'UTC',
            flow: FlowLevel.heavy,
            tags: const ['cramps'],
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          DayEntry(
            id: 'a2',
            profileId: 'p1',
            localDate: LocalDate(2026, 1, 2),
            tz: 'UTC',
            flow: FlowLevel.medium,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
          DayEntry(
            id: 'b',
            profileId: 'p1',
            localDate: LocalDate(2026, 2, 1),
            tz: 'UTC',
            flow: FlowLevel.light,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
        today: LocalDate(2026, 3, 15),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
        excludedCycleStarts: {LocalDate(2026, 1, 1)},
      );

      await tester.pumpWidget(
        MaterialApp(
          // A real theme (rather than Flutter's bare default) so the
          // flow-dot color path through the actual LunarLogColors
          // extension runs, not just its no-extension fallback.
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CycleComparisonView(data: data)),
        ),
      );

      expect(find.byKey(const ValueKey('cycle-comparison-view')), findsOneWidget);
      expect(find.text('Excluded from averages'), findsOneWidget);
      expect(find.text('Heavy'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.textContaining('Cramps'), findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-comparison-day-1')), findsOneWidget);

      // Cycle A runs 31 days (next start Feb 1), cycle B runs 28 -- day 29
      // exists only because A is longer, and B's cell there reads "ended".
      // Scrolled into view since the day list is long enough that the
      // lazy `ListView` hasn't built it yet at the initial scroll offset
      // (the exact per-day alignment itself is already exhaustively
      // covered by `test/domain/insights/cycle_comparison_test.dart` --
      // this only proves the widget renders that same data).
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cycle-comparison-day-29')),
        500,
      );
      expect(find.text('Cycle ended'), findsWidgets);
    });

    testWidgets('an open side reads Ongoing with an unknown length delta', (
      tester,
    ) async {
      final episodes = [
        Episode(LocalDate(2026, 1, 1), LocalDate(2026, 1, 1)),
        Episode(LocalDate(2026, 2, 1), LocalDate(2026, 2, 1)),
      ];
      final data = deriveCycleComparison(
        episodes: episodes,
        entries: const [],
        today: LocalDate(2026, 2, 6),
        cycleAStart: LocalDate(2026, 1, 1),
        cycleBStart: LocalDate(2026, 2, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: CycleComparisonView(data: data)),
        ),
      );

      expect(find.text('Current cycle (started February 1, 2026)'),
          findsOneWidget);
      expect(find.text('Ongoing'), findsOneWidget);
      expect(find.text('Not yet known'), findsOneWidget);
    });
  });

  group('CycleComparisonScreen (issue #235)', () {
    testWidgets('renders live comparison data for the given profile and dates', (
      tester,
    ) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final profiles = DriftProfilesRepository(db.storage);
      final Profile profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await _seed(entries, profile.id, kStarts);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CycleExclusionList>.value(
              value: CycleExclusionList(settings),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CycleComparisonScreen(
              profileId: profile.id,
              cycleAStart: LocalDate(2026, 6, 8),
              cycleBStart: LocalDate(2026, 7, 6),
              todayProvider: () => kToday,
              dayEntriesRepository: entries,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Compare cycles'), findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-comparison-view')), findsOneWidget);
      expect(find.text('Heavy'), findsWidgets);

      // Unmount before closing the database (mirrors every other DB-backed
      // harness in this suite, e.g. `cycle_history_test.dart`'s
      // `disposeHistory`) so this screen's stream subscriptions are
      // cancelled in `dispose()` before the underlying NativeDatabase goes
      // away -- skipping this left a pending timer past widget-tree
      // teardown and hung the whole suite.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });
}
