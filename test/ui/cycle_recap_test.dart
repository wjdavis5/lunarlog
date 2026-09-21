/// Issue #852: the cycle-end recap card mounted on the Analysis tab — it
/// renders once for a completed cycle with enough history, is dismissible,
/// stays dismissed for that cycle across a remount, stays in its honest
/// learning state on thin history, and never uses range/comparison language
/// in `irregular` mode.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/insights/cycle_recap.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/insights/analysis_tab.dart';
import 'package:provider/provider.dart';

/// Seven 30-day episodes ending 2026-08-05: six completed cycles, all 30
/// days, so the engine reads mean 30 and spread 0. Same fixture as
/// `analysis_tab_test.dart`'s `kSteadyStarts`.
final List<LocalDate> kSteadyStarts = [
  LocalDate(2026, 2, 6),
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// Two episodes only: one completed cycle, below the engine's estimate
/// threshold, so the recap must stay in its learning state.
final List<LocalDate> kOneCycleStarts = [
  LocalDate(2026, 7, 1),
  LocalDate(2026, 7, 29),
];

final LocalDate kToday = LocalDate(2026, 8, 30);

Future<void> seedEpisodes(
  DriftDayEntriesRepository entries,
  String profileId,
  List<LocalDate> starts, {
  int lengthDays = 4,
}) async {
  for (final start in starts) {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profileId,
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
}

class Harness {
  Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory());

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftSettingsStore settings = DriftSettingsStore(db.storage);
  late final DriftDayEntriesRepository entries =
      DriftDayEntriesRepository(db.storage);

  Widget widgetFor(
    String profileId, {
    ProfileMode mode = ProfileMode.standard,
    LocalDate? today,
  }) {
    return MultiProvider(
      providers: [
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries, settings: settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        Provider<CycleExclusionList>.value(value: CycleExclusionList(settings)),
        Provider<SettingsStore>.value(value: settings),
        Provider<DayEntriesRepository>.value(value: entries),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnalysisTab(
            profileId: profileId,
            mode: mode,
            todayProvider: () => today ?? kToday,
            settingsStore: settings,
          ),
        ),
      ),
    );
  }

  /// Creates a profile, seeds entries, writes [baseline] (when non-null) to
  /// the recap store, mounts the tab, and settles.
  Future<String> pump({
    required List<LocalDate> starts,
    CycleRecapState? baseline,
    ProfileMode mode = ProfileMode.standard,
    LocalDate? today,
  }) async {
    final profiles = DriftProfilesRepository(db.storage);
    final profile = await profiles.create(displayName: 'Alice', isMinor: false);
    await seedEpisodes(entries, profile.id, starts);
    if (baseline != null) {
      await settings.set(
        cycleRecapSettingKey(profile.id),
        encodeCycleRecapState(baseline),
      );
    }
    await tester.pumpWidget(
      widgetFor(profile.id, mode: mode, today: today),
    );
    await tester.pumpAndSettle();
    return profile.id;
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

String? textAt(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Text>(finder).data;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('a completed cycle with enough history renders the recap once, '
      'with the engine\'s own facts', (tester) async {
    final h = Harness(tester);
    final profileId = await h.pump(
      starts: kSteadyStarts,
      // Baseline one cycle back, so the Jul 6 - Aug 5 cycle just completed.
      baseline: const CycleRecapState(
        recorded: true,
        seenCycleIso: '2026-06-06',
      ),
    );

    expect(find.byKey(const ValueKey('cycle-recap-card')), findsOneWidget);
    expect(find.text('Cycle 6 wrapped up'), findsOneWidget);
    expect(
      textAt(tester, 'cycle-recap-length'),
      'This cycle lasted 30 days.',
    );
    expect(
      textAt(tester, 'cycle-recap-range'),
      'Your usual range is 30 days.',
    );
    expect(
      textAt(tester, 'cycle-recap-comparison'),
      'About the same length as the cycle before it.',
    );
    // No statistic change was supplied, so no change line is invented.
    expect(
      find.byKey(const ValueKey('cycle-recap-statistic-change')),
      findsNothing,
    );
    expect(profileId, isNotEmpty);

    await h.dispose();
  });

  testWidgets('dismissing hides the recap and it never re-shows for the same '
      'cycle, even after a remount', (tester) async {
    final h = Harness(tester);
    final profileId = await h.pump(
      starts: kSteadyStarts,
      baseline: const CycleRecapState(
        recorded: true,
        seenCycleIso: '2026-06-06',
      ),
    );

    expect(find.byKey(const ValueKey('cycle-recap-card')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cycle-recap-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-recap-card')), findsNothing);

    // The dismissal is persisted device-locally: a fresh mount (new State,
    // same store) must not show the same cycle again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(h.widgetFor(profileId));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cycle-recap-card')), findsNothing);

    final stored = decodeCycleRecapState(
      await h.settings.get(cycleRecapSettingKey(profileId)),
    );
    expect(stored.seenCycleIso, '2026-07-06');

    await h.dispose();
  });

  testWidgets('one completed cycle shows the learning state and makes no '
      'estimate-backed claim', (tester) async {
    final h = Harness(tester);
    await h.pump(
      starts: kOneCycleStarts,
      // Recorded before any cycle had completed, so the first completed
      // cycle is the moment being marked.
      baseline: const CycleRecapState(recorded: true),
    );

    expect(find.byKey(const ValueKey('cycle-recap-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cycle-recap-learning')),
      findsOneWidget,
    );
    expect(
      find.text('Still learning — estimates appear once a few cycles are '
          'recorded.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('cycle-recap-range')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-comparison')), findsNothing);
    expect(
      find.byKey(const ValueKey('cycle-recap-statistic-change')),
      findsNothing,
    );

    await h.dispose();
  });

  testWidgets('a profile that has never been seen adopts a silent baseline '
      'instead of retroactively showing an old cycle', (tester) async {
    final h = Harness(tester);
    final profileId = await h.pump(starts: kSteadyStarts);

    expect(find.byKey(const ValueKey('cycle-recap-card')), findsNothing);
    final stored = decodeCycleRecapState(
      await h.settings.get(cycleRecapSettingKey(profileId)),
    );
    expect(stored.recorded, isTrue);
    expect(stored.seenCycleIso, '2026-07-06');
    expect(stored.snapshot, isNotNull);

    await h.dispose();
  });

  testWidgets('irregular mode never uses range or comparison language', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.pump(
      starts: kSteadyStarts,
      mode: ProfileMode.irregular,
      baseline: const CycleRecapState(
        recorded: true,
        seenCycleIso: '2026-06-06',
      ),
    );

    expect(find.byKey(const ValueKey('cycle-recap-card')), findsOneWidget);
    expect(textAt(tester, 'cycle-recap-length'), isNotNull);
    expect(find.byKey(const ValueKey('cycle-recap-range')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-comparison')), findsNothing);
    expect(find.byKey(const ValueKey('cycle-recap-compare')), findsNothing);

    await h.dispose();
  });
}
