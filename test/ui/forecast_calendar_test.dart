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
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/forecast.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/l10n/dates.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
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

/// Four 30-day cycles ending 2026-06-26: open cycle 65 days → unusually
/// long (issue #221/A2-12: rolled forward, not paused).
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
  ProfileMode mode = ProfileMode.standard,
  bool isMinor = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final profile = await profiles.create(
    displayName: 'Alice',
    isMinor: isMinor,
    mode: mode,
  );
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
  final label = '${monthNames()[month - 1]} $year';
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
      // Nov 25 (not Nov 20, issue #143 review): cycle 3's own fertile
      // window (ovulation Nov 19, band Nov 14-20) now covers Nov 20, so
      // this picks a date clear of every band/numeral/fertile-window
      // island instead.
      await showMonthForward(tester, 2026, 11);
      expect(find.byKey(const ValueKey('predicted-2026-11-25')), findsNothing);
      expect(find.byKey(const ValueKey('fertile-2026-11-25')), findsNothing);
      // #138 (B-23): the plain-future-day dim is now a text colour on the
      // day number itself (`onSurface` at `kFutureDayTextAlpha`) instead
      // of a whole-cell `Opacity`, which dragged the numeral below usable
      // contrast — the same visual weight, applied only where it belongs.
      final dimmedNumber = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('day-cell-2026-11-25')),
          matching: find.byType(Text),
        ),
      );
      expect(
        dimmedNumber.style?.color,
        Theme.of(tester.element(find.byType(MonthCalendar))).colorScheme.onSurface
            .withValues(alpha: kFutureDayTextAlpha),
        reason: 'plain future days stay dimmed, on the number text only',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('day-cell-2026-11-25')),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: 'no whole-cell Opacity layer remains on a day cell (#138)',
      );
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-11-25')));
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

    testWidgets('a formerly-paused (>60-day open) profile shows bands, not '
        'the keep-logging strip — issue #221/A2-12: predictions never go '
        'silent', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kPausedStarts,
      );

      expect(find.byKey(const ValueKey('keep-logging-strip')), findsNothing,
          reason: 'a long open cycle now rolls the estimate forward '
              'instead of pausing predictions');
      await disposeForecast(tester, h);
    });
  });

  group('semantics and visual weight (#138 groundwork, extended by #138)', () {
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
        find.bySemanticsLabel(
          'Wednesday, August 5, Medium flow, no symptoms',
        ),
        findsOneWidget,
        reason: 'a logged bleed is announced as logged, with its flow level '
            'and symptom presence (#138 cell-label spec)',
      );
      await showMonthForward(tester, 2026, 9);
      expect(
        find.bySemanticsLabel(
          RegExp(
            'Friday, September 4, predicted period day, cycle day 1.*'
            'future date, not yet loggable',
          ),
        ),
        findsOneWidget,
        reason: 'a predicted band day is announced as predicted and '
            'not-yet-loggable, never as logged',
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

    // Issue #312 (follow-up review of #191 KTD4 / the original #312 border
    // floor): `predictedBorder` is solved for only ~3.06:1 against
    // `surface` at full alpha, so any alpha under ~0.98 already drops the
    // ring below WCAG's 3:1 non-text floor once blended — even the
    // original 0.6 floor (irregular tier's own raw band opacity) landed
    // short of that. `kPredictedBorderMinAlpha` is now 1.0, so every
    // tier's border draws at full opacity; the hatch fill lines are the
    // only thing that still scales with `forecastBandOpacity`.
    test(
        "an irregular-tier band's border alpha is floored to full opacity, "
        'above its raw (near-invisible) band fill opacity', () {
      expect(
        forecastBandOpacity(CycleConfidence.irregular),
        lessThan(kPredictedBorderMinAlpha),
        reason: 'sanity check: the raw tier fill opacity really is below '
            'the floor for this tier',
      );
      expect(
        forecastBorderOpacity(CycleConfidence.irregular),
        1.0,
      );
    });

    test(
        'every tier draws its border at full opacity, even though the '
        'fill opacity keeps scaling by tier', () {
      for (final tier in CycleConfidence.values) {
        expect(
          forecastBorderOpacity(tier),
          1.0,
          reason: '$tier border must stay at full opacity for contrast',
        );
      }
      expect(
        forecastBandOpacity(CycleConfidence.high),
        greaterThan(forecastBandOpacity(CycleConfidence.irregular)),
        reason: 'the fill opacity must still scale by tier even though '
            'the border no longer does',
      );
    });

    test('the layer palette is brightness-aware', () {
      final light = symptomLayerPalette(Brightness.light);
      final dark = symptomLayerPalette(Brightness.dark);
      expect(light, hasLength(3));
      expect(dark, hasLength(3));
      expect(light, isNot(equals(dark)));
    });

    test('the semantic label distinguishes every predicted/logged state '
        '(#138 cell-label spec: date, flow state, symptom presence, '
        'loggability)', () {
      final today = LocalDate(2026, 8, 30);
      final l10n = lookupAppLocalizations(const Locale('en'));
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
      final bleedWithSymptoms = entry(FlowLevel.heavy, tags: const ['cramps']);
      final symptoms = entry(FlowLevel.none, tags: const ['cramps']);
      final bare = entry(FlowLevel.none);
      final date = LocalDate(2026, 8, 5);

      expect(
        dayCellSemanticLabel(
          date: date,
          entry: bleed,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Wednesday, August 5, Medium flow, no symptoms',
      );
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: bleedWithSymptoms,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Wednesday, August 5, Heavy flow, symptoms logged',
      );
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: symptoms,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Wednesday, August 5, logged symptoms',
      );
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: bare,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Wednesday, August 5, logged, no symptoms',
      );
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: null,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Wednesday, August 5, not logged',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 9, 1),
          entry: null,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Tuesday, September 1, future date, not yet loggable',
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
            fertileWindow: false,
            tier: CycleConfidence.high,
            cycleIndex: 0,
          ),
          l10n: l10n,
        ),
        'Friday, September 4, predicted period day, cycle day 1, '
        'predicted cramps window, future date, not yet loggable',
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
            fertileWindow: false,
            tier: CycleConfidence.high,
            cycleIndex: 0,
          ),
          l10n: l10n,
        ),
        'Sunday, September 20, cycle day 17 of the first predicted cycle, '
        'future date, not yet loggable',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 9, 15),
          entry: null,
          today: today,
          cell: const ForecastDayCell(
            predictedBleed: false,
            cycleDayNumber: null,
            pmsBadge: false,
            crampsBadge: false,
            fertileWindow: true,
            tier: CycleConfidence.high,
            cycleIndex: 0,
          ),
          l10n: l10n,
          fertileWindowLabel: 'Estimated fertile window',
        ),
        'Tuesday, September 15, estimated fertile window, '
        'future date, not yet loggable',
      );
    });

    test('the semantic label carries today and read-only status (#138)', () {
      final today = LocalDate(2026, 8, 30);
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        dayCellSemanticLabel(
          date: today,
          entry: null,
          today: today,
          cell: null,
          l10n: l10n,
        ),
        'Sunday, August 30, not logged, today',
      );
      expect(
        dayCellSemanticLabel(
          date: LocalDate(2026, 8, 5),
          entry: null,
          today: today,
          cell: null,
          l10n: l10n,
          readOnly: true,
        ),
        'Wednesday, August 5, not logged, read-only',
      );
    });
  });

  group('AC8 (issue #143): fertile-window band', () {
    // With today = kToday (Aug 30) and kSteadyStarts, cycle 0's own fertile
    // window (Aug 16-22) is already in the past (past stays factual, KTD3)
    // and cycle 0's full-length numeral span (Sep 4 - Oct 3) would collide
    // with cycle 1's window anyway (`test/domain/forecast_test.dart`'s own
    // note on the same collision) — cycle 2's window (ovulation Oct 20,
    // band Oct 15-21) is the first clean, visible one, same as the domain
    // suite uses.
    testWidgets('a dashed ring renders on the window days, distinct from '
        'the hatched predicted band and the solid bleed fill', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );
      await showMonthForward(tester, 2026, 10);

      expect(find.byKey(const ValueKey('fertile-2026-10-15')), findsOneWidget);
      expect(find.byKey(const ValueKey('predicted-2026-10-15')), findsNothing);
      expect(find.byKey(const ValueKey('bleed-2026-10-15')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('fertile-2026-10-15')),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
        reason: 'a dashed ring painter, not a solid BoxDecoration fill',
      );
      // A day just outside the window carries no fertile marker.
      expect(find.byKey(const ValueKey('fertile-2026-10-14')), findsNothing);

      await disposeForecast(tester, h);
    });

    testWidgets('bands render in the dark theme too', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        brightness: Brightness.dark,
      );
      await showMonthForward(tester, 2026, 10);
      expect(find.byKey(const ValueKey('fertile-2026-10-15')), findsOneWidget);
      await disposeForecast(tester, h);
    });

    testWidgets(
        'the legend keys "Estimated fertile days" with a dashed swatch',
        (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );
      expect(find.text('Estimated fertile days'), findsOneWidget);
      expect(find.byKey(const ValueKey('legend-fertile')), findsOneWidget);
      await disposeForecast(tester, h);
    });

    testWidgets(
        'irregular mode hides both the band and its legend entry (#143: '
        'same false-precision reasoning as showsTierCaption/'
        'silencesLateBanner)', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        mode: ProfileMode.irregular,
      );
      expect(find.text('Estimated fertile days'), findsNothing);
      expect(find.byKey(const ValueKey('legend-fertile')), findsNothing);

      await showMonthForward(tester, 2026, 10);
      expect(find.byKey(const ValueKey('fertile-2026-10-15')), findsNothing);

      await disposeForecast(tester, h);
    });

    testWidgets(
        'available on a minor profile too — #142 removes any isMinor '
        'gating', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        isMinor: true,
      );
      await showMonthForward(tester, 2026, 10);
      expect(find.byKey(const ValueKey('fertile-2026-10-15')), findsOneWidget);
      await disposeForecast(tester, h);
    });

    testWidgets(
        'the future-day explainer names the fertile window and carries '
        'its own contraception disclaimer', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );
      await showMonthForward(tester, 2026, 10);
      await tester.tap(find.byKey(const ValueKey('day-cell-2026-10-15')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('future-explainer-fertile')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('future-explainer-fertile-disclaimer')),
        findsOneWidget,
      );
      expect(find.byType(DaySheet), findsNothing);

      await disposeForecast(tester, h);
    });

    testWidgets(
        "cycle 1's fertile window (which lands inside cycle 0's own "
        'numeral-day span, Sep 15-21 inside Sep 4 - Oct 3) renders and '
        "explains at cycle 1's own (degraded) tier, not cycle 0's — the "
        'contested overlap case, issue #143 review', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
      );
      // kToday (Aug 30) opens on August; Sep 15 needs one month forward.
      await showMonthForward(tester, 2026, 9);
      expect(find.byKey(const ValueKey('fertile-2026-09-15')), findsOneWidget);
      // The day still carries cycle 0's own numeral (day 12 of the first
      // predicted cycle, Sep 4 being day 1) even though the ring drawn is
      // cycle 1's fertile window.
      expect(find.text('12'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-09-15')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('future-explainer-fertile')),
        findsOneWidget,
      );
      expect(
        find.text('Estimate confidence: learning.'),
        findsOneWidget,
        reason: "the fertile window belongs to cycle 1 (learning), not "
            "the numeral-owning cycle 0 (high)",
      );

      await disposeForecast(tester, h);
    });

    testWidgets(
        'irregular mode: a day whose ONLY content was the fertile window '
        'renders as a plain (dimmed) future day and explains itself as '
        '"no prediction", not as a brighter "empty" prediction cell '
        '(issue #143 review)', (tester) async {
      final h = await pumpForecast(
        tester,
        today: kToday,
        bleedStarts: kSteadyStarts,
        mode: ProfileMode.irregular,
      );
      await showMonthForward(tester, 2026, 10);

      expect(find.byKey(const ValueKey('fertile-2026-10-15')), findsNothing);
      expect(
        find.byKey(const ValueKey('predicted-2026-10-15')),
        findsNothing,
      );
      // #138 (B-23): the dim is a text colour on the number now, not a
      // whole-cell Opacity layer — same assertion shape as the
      // plain-future-day case above.
      final dimmedNumber = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('day-cell-2026-10-15')),
          matching: find.byType(Text),
        ),
      );
      expect(
        dimmedNumber.style?.color,
        Theme.of(tester.element(find.byType(MonthCalendar))).colorScheme.onSurface
            .withValues(alpha: kFutureDayTextAlpha),
        reason: 'a hidden fertile-only day must stay dimmed, like any '
            'other plain future day',
      );

      await tester.tap(find.byKey(const ValueKey('day-cell-2026-10-15')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('future-explainer-none')),
        findsOneWidget,
        reason: 'must read as "no prediction for this date", not a bare '
            'confidence line for content the mode actually hides',
      );

      await disposeForecast(tester, h);
    });
  });
}
