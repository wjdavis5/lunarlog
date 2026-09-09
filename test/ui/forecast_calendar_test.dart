/// Widget tests for issue #133: the twelve-month forward calendar —
/// navigation and cap, predicted bleed bands distinct from logged fills,
/// first-cycle-only numerals, fixed-offset badges, symptom layers
/// (defaults, toggling, three-layer cap), the read-only future-day
/// explainer, the keep-logging quiet state, semantic distinction, and
/// confidence-weighted rendering, walked against the issue's acceptance
/// checklist in both brightness themes.
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
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';

/// Fixed "today": 2026-08-30, cycle day 26 of the open cycle below.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Steady 30-day cycles with 4-day bleeds, open cycle starting Aug 5 →
/// estimate Sep 4, high confidence, bands Sep 4..7 then every 30 days.
final List<LocalDate> kSteadyStarts = [
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// Two episodes only: not enough history — the quiet state.
final List<LocalDate> kThinStarts = [
  LocalDate(2026, 7, 1),
  LocalDate(2026, 7, 29),
];

/// Four 30-day cycles ending 2026-06-26: open cycle 65 days → paused.
final List<LocalDate> kPausedStarts = [
  LocalDate(2026, 3, 28),
  LocalDate(2026, 4, 27),
  LocalDate(2026, 5, 27),
  LocalDate(2026, 6, 26),
];

/// Lengths 90, 95, 100 (outliers) then 28, 28, 28: estimate Sep 2. Only
/// three usable cycles feed a 6-cycle average window that is not yet full,
/// so this reads `learning` (issue #213 item 5) rather than `high` — still
/// below the top tier, which is all this suite's own assertions need (the
/// band still renders, just at a lower confidence-weighted opacity; no
/// assertion here pins the exact tier).
final List<LocalDate> kIrregularStarts = [
  LocalDate(2025, 8, 1),
  LocalDate(2025, 10, 30),
  LocalDate(2026, 2, 2),
  LocalDate(2026, 5, 13),
  LocalDate(2026, 6, 10),
  LocalDate(2026, 7, 8),
  LocalDate(2026, 8, 5),
];

class Harness {
  Harness(this.db, this.profile, this.entries, this.settings);

  final LunarLogDatabase db;
  final Profile profile;
  final DriftDayEntriesRepository entries;
  final DriftSettingsStore settings;
  late LocalDate today;

  Widget appFor(
    Profile profile, {
    Brightness brightness = Brightness.light,
    bool readOnly = false,
  }) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(
          value: DriftProfilesRepository(db.storage),
        ),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: settings),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries, settings: settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: DriftProfilesRepository(db.storage),
            settingsStore: settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: ProfileDetailScreen(
          profile: profile,
          readOnly: readOnly,
          todayProvider: () => today,
        ),
      ),
    );
  }
}

Future<Harness> pumpForecast(
  WidgetTester tester, {
  required LocalDate today,
  required List<LocalDate> bleedStarts,
  int bleedDays = 4,
  Map<LocalDate, List<String>> tagDays = const {},
  Brightness brightness = Brightness.light,
  bool readOnly = false,
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
  for (final start in bleedStarts) {
    for (var i = 0; i < bleedDays; i++) {
      await entries.save(
        DayEntry(
          id: '',
          profileId: profile.id,
          localDate: start.addDays(i),
          tz: 'America/Chicago',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }
  }
  for (final day in tagDays.entries) {
    await entries.save(
      DayEntry(
        id: '',
        profileId: profile.id,
        localDate: day.key,
        tz: 'America/Chicago',
        flow: FlowLevel.none,
        tags: day.value,
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  }
  final harness = Harness(db, profile, entries, settings)..today = today;
  await tester.pumpWidget(
    harness.appFor(profile, brightness: brightness, readOnly: readOnly),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> disposeForecast(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

/// Walks the calendar forward (from today's month) until [label] shows.
Future<void> showMonthForward(WidgetTester tester, int year, int month) async {
  final label = '${kMonthNames[month - 1]} $year';
  var guard = 0;
  while (find.text(label).evaluate().isEmpty) {
    expect(guard++, lessThan(40), reason: 'month never reached: $label');
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
  }
  expect(find.text(label), findsOneWidget);
}

IconButton nextButton(WidgetTester tester) => tester.widget<IconButton>(
  find.ancestor(
    of: find.byTooltip('Next month'),
    matching: find.byType(IconButton),
  ),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('AC1: forward navigation', () {
    testWidgets('runs twelve months forward and stops there', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      expect(
        find.text('August 2026'),
        findsOneWidget,
        reason: "today's month is the default",
      );
      expect(nextButton(tester).onPressed, isNotNull);
      await showMonthForward(tester, 2027, 8);
      expect(
        find.text('August 2027'),
        findsOneWidget,
        reason: 'twelve months past August 2026',
      );
      expect(
        nextButton(tester).onPressed,
        isNull,
        reason: 'the cap is exactly twelve months forward',
      );
      await disposeForecast(tester, h);
    });
  });

  group('AC2: predicted bands distinct from logged fills', () {
    testWidgets('six months ahead shows hatched bands; logged days stay '
        'solid fills', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      // Logged fills in the current month render as bleed cells, never
      // predicted ones.
      expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget);
      expect(find.byKey(const ValueKey('predicted-2026-08-05')), findsNothing);

      // Six-plus months ahead (March 2027): the cycle starting 2027-03-03
      // carries a predicted band, rendered hatched (a CustomPaint), never
      // as a logged bleed fill.
      await showMonthForward(tester, 2027, 3);
      expect(
        find.byKey(const ValueKey('predicted-2027-03-03')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('bleed-2027-03-03')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('predicted-2027-03-03')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: 'the band is a hatch painter, not a solid BoxDecoration',
      );
      await disposeForecast(tester, h);
    });

    testWidgets('bands render in the dark theme too', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        brightness: Brightness.dark,
      );
      await showMonthForward(tester, 2026, 9);
      expect(
        find.byKey(const ValueKey('predicted-2026-09-04')),
        findsOneWidget,
      );
      await disposeForecast(tester, h);
    });
  });

  group('AC3: cycle-day numerals on the first predicted cycle only', () {
    testWidgets('numerals cover the first predicted cycle and stop at its '
        'end', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      await showMonthForward(tester, 2026, 9);
      expect(
        find.byKey(const ValueKey('cycle-day-numeral-2026-09-04')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('cycle-day-numeral-2026-09-04')),
            )
            .data,
        '1',
        reason: 'the numeral counts from the estimated start',
      );

      // October: numerals run to Oct 3 (cycle day 30); the next cycle's
      // band starts Oct 4 with no numeral.
      await showMonthForward(tester, 2026, 10);
      expect(
        find.byKey(const ValueKey('cycle-day-numeral-2026-10-03')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cycle-day-numeral-2026-10-04')),
        findsNothing,
        reason: 'numerals never chain across later cycles',
      );
      expect(
        find.byKey(const ValueKey('predicted-2026-10-04')),
        findsOneWidget,
        reason: 'the second predicted cycle still carries its band',
      );
      await disposeForecast(tester, h);
    });

    testWidgets('fixed-offset badges appear around the estimate', (
      tester,
    ) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      await showMonthForward(tester, 2026, 9);
      // Estimate Sep 4: PMS window Aug 28..Sep 3 (future half: Aug 31..Sep
      // 3 — Aug 31 renders on the current month, so check from September),
      // cramps window Sep 2..Sep 6.
      expect(
        find.byKey(const ValueKey('pms-badge-2026-09-03')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pms-badge-2026-09-04')),
        findsNothing,
        reason: 'the PMS window ends the day before the estimate',
      );
      expect(
        find.byKey(const ValueKey('cramps-badge-2026-09-02')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cramps-badge-2026-09-06')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cramps-badge-2026-09-07')),
        findsNothing,
        reason: 'the cramps window ends two days past the estimate',
      );
      await disposeForecast(tester, h);
    });
  });

  group('AC4/AC5: symptom layers', () {
    testWidgets('default to the three most-used tags and toggle '
        'matching days; a fourth layer is refused', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        tagDays: {
          // headache ×3, fatigue ×2, cramps ×1, bloating ×1 → defaults
          // [headache, fatigue, cramps] (the 1-count tie breaks in
          // taxonomy order, where bloating precedes cramps — moot here).
          LocalDate(2026, 8, 10): const ['headache'],
          LocalDate(2026, 8, 11): const ['headache', 'cramps'],
          LocalDate(2026, 8, 12): const ['fatigue', 'bloating'],
          LocalDate(2026, 8, 13): const ['headache', 'fatigue'],
        },
      );

      // Expand the panel.
      await tester.tap(find.byKey(const ValueKey('symptom-layers-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('symptom-layers-panel')),
        findsOneWidget,
      );

      bool selected(String code) => tester
          .widget<FilterChip>(find.byKey(ValueKey('layer-chip-$code')))
          .selected;
      expect(selected('headache'), isTrue);
      expect(selected('cramps'), isTrue);
      expect(selected('fatigue'), isTrue);
      expect(
        selected('bloating'),
        isFalse,
        reason: 'the fourth-most-used tag is not a default layer',
      );

      // Layer dots render for matching days (a bleed-free tag day here).
      expect(
        find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('layer-dot-cramps-2026-08-11')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('layer-dot-fatigue-2026-08-12')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('layer-dot-bloating-2026-08-12')),
        findsNothing,
        reason: 'an inactive layer never marks a day',
      );

      // Toggling a layer off hides its matching days; back on restores.
      await tester.tap(find.byKey(const ValueKey('layer-chip-cramps')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('layer-dot-cramps-2026-08-11')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('layer-dot-headache-2026-08-10')),
        findsOneWidget,
        reason: 'other layers are untouched',
      );
      await tester.tap(find.byKey(const ValueKey('layer-chip-cramps')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('layer-dot-cramps-2026-08-11')),
        findsOneWidget,
      );

      // With three active, a fourth is refused with a hint.
      await tester.tap(find.byKey(const ValueKey('layer-chip-bloating')));
      await tester.pump();
      expect(find.byKey(const ValueKey('layer-limit-snack')), findsOneWidget);
      expect(selected('bloating'), isFalse);
      expect(
        find.byKey(const ValueKey('layer-dot-bloating-2026-08-12')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 4));
      await disposeForecast(tester, h);
    });

    testWidgets('a symptom-only day whose tags are all untracked falls '
        'back to the generic marker', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        tagDays: {
          LocalDate(2026, 8, 10): const ['headache'],
          LocalDate(2026, 8, 11): const ['headache', 'cramps'],
          LocalDate(2026, 8, 12): const ['headache', 'fatigue'],
          LocalDate(2026, 8, 13): const ['cramps', 'fatigue'],
          LocalDate(2026, 8, 14): const ['bloating'],
        },
      );

      expect(
        find.byKey(const ValueKey('symptom-dot-2026-08-14')),
        findsOneWidget,
        reason: 'no active layer matches, so the generic dot shows',
      );
      expect(
        find.byKey(const ValueKey('layer-dot-bloating-2026-08-14')),
        findsNothing,
      );
      await disposeForecast(tester, h);
    });
  });

  group('AC6: future cells open the explainer, never the log sheet', () {
    testWidgets('band, PMS, numeral-only, and plain future dates each '
        'explain their predicted state', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      // A predicted band day.
      await showMonthForward(tester, 2026, 9);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-09-04')));
      await tester.pumpAndSettle();
      expect(
        find.byType(DaySheet),
        findsNothing,
        reason: 'the future logging lock stays',
      );
      expect(find.byKey(const ValueKey('future-explainer')), findsOneWidget);
      expect(find.text('September 4, 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('future-explainer-band')),
        findsOneWidget,
      );
      expect(
        find.textContaining('cycle day 1 of the first predicted cycle'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // A PMS-window day.
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-09-03')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('future-explainer-pms')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // A numeral-only day inside the first predicted cycle.
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-09-20')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('future-explainer-numeral')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // A plain future day with no prediction at all, dimmed as locked.
      await showMonthForward(tester, 2026, 11);
      expect(find.byKey(const ValueKey('predicted-2026-11-20')), findsNothing);
      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byKey(const ValueKey('day-cell-2026-11-20')),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.35, reason: 'plain future days stay dimmed');
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-11-20')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('future-explainer-none')),
        findsOneWidget,
      );
      expect(find.byType(DaySheet), findsNothing);
      await disposeForecast(tester, h);
    });

    testWidgets('the explainer opens in read-only mode too', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        readOnly: true,
      );

      await showMonthForward(tester, 2026, 9);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-09-04')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('future-explainer')), findsOneWidget);
      expect(find.byType(DaySheet), findsNothing);
      await disposeForecast(tester, h);
    });
  });

  group('AC7: the no-estimate quiet state', () {
    testWidgets('thin history shows the keep-logging strip and no bands', (
      tester,
    ) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kThinStarts,
      );

      expect(find.byKey(const ValueKey('keep-logging-strip')), findsOneWidget);
      expect(find.textContaining('Keep logging'), findsOneWidget);
      await showMonthForward(tester, 2026, 9);
      expect(find.byKey(const ValueKey('keep-logging-strip')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('predicted-2026-09-04')),
        findsNothing,
        reason: 'no estimate means no bands anywhere',
      );
      expect(
        find.byKey(const ValueKey('cycle-day-numeral-2026-09-04')),
        findsNothing,
      );
      await disposeForecast(tester, h);
    });

    testWidgets('a paused prediction shows the paused strip wording', (
      tester,
    ) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kPausedStarts,
      );

      expect(find.byKey(const ValueKey('keep-logging-strip')), findsOneWidget);
      expect(find.textContaining('Predictions are paused'), findsOneWidget);
      await disposeForecast(tester, h);
    });
  });

  group('semantics and visual weight (#138 groundwork)', () {
    testWidgets('predicted and logged days carry distinct semantics labels', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );

      expect(
        find.bySemanticsLabel('August 5, logged period day'),
        findsOneWidget,
        reason: 'a logged bleed is announced as logged',
      );
      await showMonthForward(tester, 2026, 9);
      expect(
        find.bySemanticsLabel(
          RegExp('September 4, predicted period day, cycle day 1'),
        ),
        findsOneWidget,
        reason: 'a predicted band day is announced as predicted',
      );
      handle.dispose();
      await disposeForecast(tester, h);
    });

    testWidgets('a below-high-confidence history still bands, at its own '
        'weight', (
      tester,
    ) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kIrregularStarts,
      );

      await showMonthForward(tester, 2026, 9);
      expect(
        find.byKey(const ValueKey('predicted-2026-09-02')),
        findsOneWidget,
      );
      await disposeForecast(tester, h);
    });
  });

  group('pure helpers', () {
    test('band opacity maps confidence to descending visual weight', () {
      expect(
        forecastBandOpacity(CycleConfidence.high),
        greaterThan(forecastBandOpacity(CycleConfidence.learning)),
      );
      expect(
        forecastBandOpacity(CycleConfidence.learning),
        greaterThan(forecastBandOpacity(CycleConfidence.irregular)),
      );
    });

    test('the layer palette is brightness-aware', () {
      final light = symptomLayerPalette(Brightness.light);
      final dark = symptomLayerPalette(Brightness.dark);
      expect(light, hasLength(3));
      expect(dark, hasLength(3));
      expect(light, isNot(equals(dark)));
    });

    test('the semantic label distinguishes every predicted/logged state', () {
      final today = LocalDate(2026, 8, 30);
      DayEntry entry(FlowLevel flow, {List<String> tags = const []}) =>
          DayEntry(
            id: '',
            profileId: 'p',
            localDate: LocalDate(2026, 8, 5),
            tz: 'America/Chicago',
            flow: flow,
            tags: tags,
            updatedAt: DateTime.utc(2026, 1, 1),
          );
      final bleed = entry(FlowLevel.medium);
      final symptoms = entry(FlowLevel.none, tags: const ['cramps']);
      final bare = entry(FlowLevel.none);
      final date = LocalDate(2026, 8, 5);

      expect(
        dayCellSemanticLabel(
          date: date,
          entry: bleed,
          today: today,
          cell: null,
        ),
        'August 5, logged period day',
      );
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: symptoms,
          today: today,
          cell: null,
        ),
        'August 5, logged symptoms',
      );
      expect(
        dayCellSemanticLabel(date: date, entry: bare, today: today, cell: null),
        'August 5, logged',
      );
      expect(
        dayCellSemanticLabel(date: date, entry: null, today: today, cell: null),
        'August 5, not logged',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 9, 1),
          entry: null,
          today: today,
          cell: null,
        ),
        'September 1, future date, not yet loggable',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 9, 4),
          entry: null,
          today: today,
          cell: const ForecastDayCell(
            predictedBleed: true,
            cycleDayNumber: 1,
            pmsBadge: false,
            crampsBadge: true,
            tier: CycleConfidence.high,
            cycleIndex: 0,
          ),
        ),
        'September 4, predicted period day, cycle day 1, '
        'predicted cramps window',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 9, 20),
          entry: null,
          today: today,
          cell: const ForecastDayCell(
            predictedBleed: false,
            cycleDayNumber: 17,
            pmsBadge: false,
            crampsBadge: false,
            tier: CycleConfidence.high,
            cycleIndex: 0,
          ),
        ),
        'September 20, cycle day 17 of the first predicted cycle',
      );
    });
  });
}
