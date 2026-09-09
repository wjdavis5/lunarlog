/// Widget tests for issue #132: the cycle-history section (R4/R5) — the
/// reverse-chronological list, omit-from-average with reversibility,
/// confidence framing, statistics, read-only gating, and the disclaimer/
/// device-local captions.
///
/// Issue #314: [CycleHistorySection] no longer mounts inside
/// `OverviewPanel`/`ProfileDetailScreen` — its only production mount point
/// is now `AnalysisTab` (Insights), covered by `test/ui/
/// analysis_tab_test.dart`. This file mounts the section directly instead
/// (the same isolated pattern the old "showStatistics/showDisclaimer"
/// group already used), so it stays focused on the section's own
/// mechanics without coupling to whichever screen happens to host it. Two
/// groups that tested cross-widget behavior moved elsewhere:
///
/// * The three-option late resolver (AC6) and the unusually-long-cycle
///   "log it" path (AC7) test [LateResolver], which stays in
///   `OverviewPanel` — moved to `test/ui/overview_test.dart`.
/// * The auth-driven attribution seam (a sign-in not disturbing the
///   mounted history) tested `OverviewPanel`'s own auth listener, not
///   anything [CycleHistorySection] does itself (it never reads
///   `AuthController`) — the equivalent listener now lives on
///   `AnalysisTab`, so that test moved to `test/ui/analysis_tab_test.dart`.
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
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/ui/overview/cycle_history_section.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

const String kDisclaimer = 'Estimates only — not medical advice.';
const String kDeviceLocalNote =
    'Omissions stay on this device — other devices are not affected.';

/// R13 vocabulary sweep over every rendered Text in the tree.
const List<String> kForbiddenStems = [
  'fertil',
  'ovul',
  'conceiv',
  'concepti',
  'luteal',
  'follicular',
];

/// Six 30-day cycles ending 2026-08-05 (kToday Aug 30 = cycle day 26): a
/// full kAverageWindowCycles(6) window, the minimum for `high` confidence
/// (issue #213 item 5). Prepended one extra 30-day cycle ahead of the
/// original five so the open cycle's start (Aug 5, and so kToday's cycle
/// day) stays unchanged for every other test sharing this fixture.
final List<LocalDate> kSteadyStarts = [
  LocalDate(2026, 2, 6),
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// Two episodes only (one completed cycle): confidence reads learning.
final List<LocalDate> kLearningStarts = [
  LocalDate(2026, 7, 1),
  LocalDate(2026, 7, 29),
];

/// Seven completed cycles of which only the last three (28s) are valid:
/// lengths 65, 90, 95, 100, then 28, 28, 28 — valid ratio 3/7 ≈ 0.43, under
/// the engine's 0.5 threshold, reads irregular (issue #213: ratio is now
/// recency-windowed over all completed cycles, not just the averaged
/// three, so a boundary-exact 0.5 no longer suffices — see
/// kIrregularSpreadThresholdDays/kIrregularValidRatioThreshold).
final List<LocalDate> kIrregularRatioStarts = [
  LocalDate(2025, 5, 28), // 65: outlier
  LocalDate(2025, 8, 1),
  LocalDate(2025, 10, 30), // 90: outlier
  LocalDate(2026, 2, 2), // 95: outlier
  LocalDate(2026, 5, 13), // 100: outlier
  LocalDate(2026, 6, 10), // 28
  LocalDate(2026, 7, 8), // 28
  LocalDate(2026, 8, 5), // 28, open cycle
];

/// Lengths 28, 28, 20, 28: the 20-day cycle is the one STARTING Apr 5 (it
/// runs Apr 5 -> Apr 25).
final List<LocalDate> kShortOutlierStarts = [
  LocalDate(2026, 2, 8), // 28-day cycle starts here
  LocalDate(2026, 3, 8), // 28
  LocalDate(2026, 4, 5), // 20 (the short outlier)
  LocalDate(2026, 4, 25), // 28
  LocalDate(2026, 5, 23), // 28; open cycle
];

/// 30-day cycles, used by the read-only group below.
final List<LocalDate> kSkipStarts = [
  LocalDate(2026, 3, 29),
  LocalDate(2026, 4, 28),
  LocalDate(2026, 5, 28),
  LocalDate(2026, 6, 27),
];

class Harness {
  Harness(this.db, this.profile, this.entries, this.settings);

  final LunarLogDatabase db;
  final Profile profile;
  final DriftDayEntriesRepository entries;
  final DriftSettingsStore settings;

  /// Mounts [CycleHistorySection] directly (issue #314 -- see the file
  /// doc comment for why this is no longer through `OverviewPanel`/
  /// `ProfileDetailScreen`).
  Widget appFor({bool readOnly = false}) {
    return MultiProvider(
      providers: [
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        Provider<CycleExclusionList>.value(
          value: CycleExclusionList(settings),
        ),
      ],
      child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CycleHistorySection(
            profileId: profile.id,
            todayProvider: () => today,
            readOnly: readOnly,
          ),
        ),
      ),
    );
  }

  late LocalDate today;
}

Future<Harness> pumpHistory(
  WidgetTester tester, {
  required LocalDate today,
  required List<LocalDate> starts,
  bool readOnly = false,
  int bleedDays = 4,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  for (final start in starts) {
    for (var i = 0; i < bleedDays; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profile.id,
          localDate: start.addDays(i),
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          tags: const [],
          note: null,
          updatedAt: DateTime.utc(2026, 1, 1),
          deletedAt: null,
        ),
      );
    }
  }
  final harness = Harness(db, profile, entries, settings)..today = today;
  await tester.pumpWidget(harness.appFor(readOnly: readOnly));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> disposeHistory(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

void expectNoFertilityVocabulary(WidgetTester tester, String state) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? '')
      .where((text) => text.isNotEmpty)
      .toList();
  expect(texts, isNotEmpty, reason: 'state "$state" rendered no text');
  for (final text in texts) {
    final lower = text.toLowerCase();
    for (final stem in kForbiddenStems) {
      expect(
        lower.contains(stem),
        isFalse,
        reason: 'state "$state" renders "$text" containing "$stem" (R13)',
      );
    }
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final aug30 = LocalDate(2026, 8, 30);

  group('AC1: history list', () {
    testWidgets('reverse-chronological with the open cycle pinned on top', (
      tester,
    ) async {
      final h = await pumpHistory(tester, today: aug30, starts: kSteadyStarts);

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(
        find.text('Current cycle — started August 5, 2026'),
        findsOneWidget,
        reason: 'the open cycle pins to the top',
      );
      // Completed cycles, newest first.
      expect(
        tester.widgetList<Text>(find.byType(Text)).map((t) => t.data),
        containsAllInOrder([
          'July 6, 2026',
          'June 6, 2026',
          'May 7, 2026',
          'April 7, 2026',
          'March 8, 2026',
          'February 6, 2026',
        ]),
        reason: 'reverse-chronological below the open cycle',
      );
      expect(
        find.text('30 days'),
        findsNWidgets(7),
        reason: 'six completed rows plus the avg-cycle statistic',
      );
      expectNoFertilityVocabulary(tester, 'history list');
      await disposeHistory(tester, h);
    });

    testWidgets('no history card for a profile with no episodes', (
      tester,
    ) async {
      final h = await pumpHistory(tester, today: aug30, starts: const []);
      expect(find.byKey(const ValueKey('history-card')), findsNothing);
      await disposeHistory(tester, h);
    });
  });

  group('AC2/AC3: omit-from-average', () {
    testWidgets(
        'omitting a cycle marks its row visibly excluded but still '
        'visible, and toggling Include reverses it', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 6, 21),
        starts: kShortOutlierStarts,
      );

      expect(
        find.byKey(const ValueKey('history-item-2026-04-05')),
        findsOneWidget,
      );
      expect(find.text('Excluded from averages'), findsNothing);
      expect(
        find.byKey(const ValueKey('history-omit-2026-04-05')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('history-omit-2026-04-05')));
      await tester.pumpAndSettle();

      // Still visible, visibly excluded (AC3).
      expect(
        find.byKey(const ValueKey('history-item-2026-04-05')),
        findsOneWidget,
      );
      expect(find.text('Excluded from averages'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-include-2026-04-05')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('history-include-2026-04-05')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Excluded from averages'),
        findsNothing,
        reason: 'reversible: including it clears the excluded styling',
      );
      expect(
        find.byKey(const ValueKey('history-omit-2026-04-05')),
        findsOneWidget,
        reason: 'the Omit affordance comes back',
      );
      await disposeHistory(tester, h);
    });

    testWidgets('outliers outside the 15-60 window are auto-flagged with no '
        'omit toggle', (tester) async {
      final h = await pumpHistory(
        tester,
        today: aug30,
        starts: kIrregularRatioStarts,
      );
      expect(
        find.byKey(const ValueKey('history-outlier-2025-10-30')),
        findsOneWidget,
      );
      expect(find.text('Outlier — never averaged'), findsNWidgets(4));
      expect(
        find.byKey(const ValueKey('history-omit-2025-10-30')),
        findsNothing,
        reason: 'already excluded — a manual omit would be a no-op',
      );
      await disposeHistory(tester, h);
    });
  });

  group('AC2/AC3: open-cycle skip/undo (issue #314 review item 2)', () {
    testWidgets(
        'omitting the open cycle shows the "Skipped — excluded from '
        'averages" subtitle and an Undo control on its row; tapping Undo '
        'includes it again', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 8, 11),
        starts: kSkipStarts,
      );
      final openStart = LocalDate(2026, 6, 27);

      // The open cycle has no "Omit" affordance of its own on this
      // section (only `LateResolver`'s "Skip this cycle" writes it, and
      // that widget is not mounted here) -- so drive the same
      // `CycleExclusionList` directly, exactly as the task says.
      await CycleExclusionList(h.settings).omit(h.profile.id, openStart);
      await tester.pumpAndSettle();

      expect(
        find.text('Current cycle — started June 27, 2026'),
        findsOneWidget,
      );
      expect(find.text('Skipped — excluded from averages'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-undo-skip')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('history-undo-skip')));
      await tester.pumpAndSettle();

      expect(find.text('Skipped — excluded from averages'), findsNothing);
      expect(find.byKey(const ValueKey('history-undo-skip')), findsNothing);
      expect(
        parseOmittedCycles(
          await h.settings.get(omittedCyclesSettingKey(h.profile.id)),
        ),
        isNot(contains(openStart)),
        reason: 'Undo drives CycleExclusionList.include, restoring the '
            'cycle to the average',
      );
      await disposeHistory(tester, h);
    });
  });

  group('AC4/AC5: confidence and statistics', () {
    testWidgets('steady 30-day history: high confidence, avg cycle 30, avg '
        'period 4, variation 0, disclaimer, device-local note', (tester) async {
      final h = await pumpHistory(tester, today: aug30, starts: kSteadyStarts);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-confidence')),
          matching: find.text('High confidence'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('steady'), findsOneWidget);
      expect(find.text('Avg cycle'), findsOneWidget);
      expect(find.text('30 days'), findsAtLeastNWidgets(1));
      expect(find.text('Avg period'), findsOneWidget);
      expect(find.text('4 days'), findsOneWidget);
      expect(find.text('Variation'), findsOneWidget);
      expect(find.text('0 days'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-card')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
        reason: 'the statistics carry the disclaimer (AC8)',
      );
      expect(
        find.text(kDeviceLocalNote),
        findsOneWidget,
        reason: 'multi-device divergence is stated, not hidden (KTD2)',
      );
      await disposeHistory(tester, h);
    });

    testWidgets('below three valid cycles reads learning', (tester) async {
      final h = await pumpHistory(
        tester,
        today: aug30,
        starts: kLearningStarts,
      );
      expect(find.text('Learning'), findsOneWidget);
      expect(find.textContaining('Still learning'), findsOneWidget);
      await disposeHistory(tester, h);
    });

    testWidgets('a low valid ratio reads irregular', (tester) async {
      final h = await pumpHistory(
        tester,
        today: aug30,
        starts: kIrregularRatioStarts,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('history-confidence')),
          matching: find.text('Irregular'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('vary a lot'), findsOneWidget);
      expectNoFertilityVocabulary(tester, 'irregular confidence');
      await disposeHistory(tester, h);
    });
  });

  group('read-only callers', () {
    testWidgets(
        'an archived profile (or a viewer-role guardian) sees the '
        'history with no omit/include affordance', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 8, 11),
        starts: kSkipStarts,
        readOnly: true,
      );

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('history-omit-2026-05-28')),
        findsNothing,
      );
      expect(find.textContaining('Omit'), findsNothing);
      expect(find.textContaining('Include'), findsNothing);
      await disposeHistory(tester, h);
    });
  });

  group('showStatistics/showDisclaimer (#223 follow-up)', () {
    testWidgets(
        'both false renders neither the stats row nor the disclaimer -- '
        'the shape AnalysisTab mounts this section with, since its own '
        'headline card owns those numbers', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      for (final start in kSteadyStarts) {
        for (var i = 0; i < 4; i++) {
          await entries.save(DayEntry(
            id: '',
            profileId: profile.id,
            localDate: start.addDays(i),
            tz: 'America/Chicago',
            flow: FlowLevel.medium,
            tags: const [],
            note: null,
            updatedAt: DateTime.utc(2026, 1, 1),
            deletedAt: null,
          ));
        }
      }

      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<CycleHistoryService>.value(
            value: CycleHistoryService(entries, settings: settings),
          ),
          Provider<CycleExclusionList>.value(
            value: CycleExclusionList(settings),
          ),
        ],
        child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CycleHistorySection(
              profileId: profile.id,
              todayProvider: () => aug30,
              showStatistics: false,
              showDisclaimer: false,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-stats')), findsNothing);
      expect(find.byKey(const ValueKey('history-disclaimer')), findsNothing);
      // The rest of the card (item list, device-local note) is unaffected.
      expect(find.text('Cycle history'), findsOneWidget);
      expect(
        find.text(
          'Omissions stay on this device — other devices are not affected.',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });
}
