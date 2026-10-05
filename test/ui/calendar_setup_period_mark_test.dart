/// Widget tests for issue #1469: the last-period date given at setup shows
/// on the month calendar as its own mark — a dotted ring in the period
/// colour that is visibly not a logged day — with a legend row and a label
/// that says where it came from, while the estimate still counts from it.
///
/// The decision is the engine's (`ActivePrediction.cycleStartIsSupplied`),
/// so every test mounts `MonthCalendar` over a real
/// `CyclePredictionService` wired to the profiles and profile-modes
/// repositories, the way `AppDependencies` wires it: the profile's stored
/// answers reach the calendar through the estimate, never through a second
/// path.
///
/// Every test that asserts the mark is *absent* first shows it present and
/// then makes the one change that should remove it, so none of them can
/// pass on a calendar that never draws the mark at all.
library;

import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_guardians_repository.dart';
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart'
    show predictionsEnabledSettingKey;
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/setup_period_mark.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';
import '../support/wcag_contrast.dart';

/// Monday. The issue's own repro date.
final LocalDate kToday = LocalDate(2026, 10, 5);

/// Thursday, in today's month: the supplied date most tests use, so the
/// mark is on the page the calendar opens on.
final LocalDate kSupplied = LocalDate(2026, 10, 1);

/// Thursday, a month back: the issue's repro ("cycle day 33 of about 28
/// days" on [kToday]).
final LocalDate kIssueSupplied = LocalDate(2026, 9, 3);

const String kSuppliedLabel =
    'Thursday, October 1, last period start from setup, not logged';
const String kPlainLabel = 'Thursday, October 1, not logged';
const String kLegendLabel = 'Last period start from setup (not logged)';

class Harness {
  Harness(
    this.db,
    this.profile,
    this.profiles,
    this.entries,
    this.settings,
    this.modes,
  );

  final LunarLogDatabase db;
  final Profile profile;
  final DriftProfilesRepository profiles;
  final DriftDayEntriesRepository entries;
  final DriftSettingsStore settings;
  final DriftProfileModesRepository modes;

  /// Logs a four-day period starting on [start].
  Future<void> logPeriod(LocalDate start) async {
    for (var i = 0; i < 4; i++) {
      await entries.save(entryFor(profile.id, start.addDays(i)));
    }
  }
}

DayEntry entryFor(
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.medium,
  List<String> tags = const [],
}) => DayEntry(
  id: '',
  profileId: profileId,
  localDate: date,
  tz: 'America/Chicago',
  flow: flow,
  tags: tags,
  updatedAt: DateTime.utc(2026, 1, 1),
);

/// Mounts one [MonthCalendar] for a profile created with the given setup
/// answers. [seed] runs before the first frame; [viewerRole] signs in an
/// accepted, non-subject member with that role (the guardian lens).
Future<Harness> pumpCalendar(
  WidgetTester tester, {
  required LocalDate? lastPeriodStart,
  Future<void> Function(Harness h)? seed,
  ThemeData? theme,
  String? viewerRole,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final modes = DriftProfileModesRepository(db.storage);
  final profile = await profiles.create(
    displayName: 'Alice',
    isMinor: false,
    lastPeriodStart: lastPeriodStart,
    typicalCycleLengthDays: 28,
    typicalPeriodLengthDays: 5,
  );
  final harness = Harness(db, profile, profiles, entries, settings, modes);
  if (seed != null) await seed(harness);

  AuthController? authController;
  if (viewerRole != null) {
    const viewerId = 'user-aunt';
    await db.storage.applyRemoteRows([
      RemoteProfileGuardianRow(
        id: 'g-$viewerId',
        profileId: profile.id,
        userId: viewerId,
        role: viewerRole,
        status: 'accepted',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        serverVersion: 1,
      ),
    ]);
    final auth = FakeAuthService()
      ..emit(AuthSessionState.signedIn, user: const AuthUser(id: viewerId));
    authController = AuthController(authService: auth);
  }

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<ObservationsRepository>.value(
          value: DriftObservationsRepository(db.storage),
        ),
        Provider<SettingsStore>.value(value: settings),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(
            entries,
            settings: settings,
            profiles: profiles,
            lifecycleModeFor: (profileId) => modes
                .watch(profileId)
                .map((row) => row?.mode ?? LifecycleMode.tracking),
          ),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(
          body: MonthCalendar(
            profileId: profile.id,
            todayProvider: () => kToday,
            guardiansRepository: viewerRole == null
                ? null
                : DriftProfileGuardiansRepository(db.storage),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> disposeCalendar(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

Future<void> goBackOneMonth(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Previous month'));
  await tester.pumpAndSettle();
}

Future<void> openLegend(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('legend-toggle')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('calendar-legend')), findsOneWidget);
}

Future<void> closeLegend(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('calendar-legend')), findsNothing);
}

Finder markOn(LocalDate date) =>
    find.byKey(ValueKey('setup-period-${date.iso}'));

/// Every setup mark in the tree, whatever day it is on.
final Finder anyMark = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('setup-period-');
});

final Finder legendRow = find.byKey(const ValueKey('legend-setup-period'));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final lightColors = AppTheme.lightTheme.extension<LunarLogColors>()!;

  group('the mark on the supplied date', () {
    testWidgets('the supplied date carries the mark and a label that says '
        'where it came from, and nothing is written for it', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);

      expect(markOn(kSupplied), findsOneWidget);
      expect(find.bySemanticsLabel(kSuppliedLabel), findsOneWidget);
      // It is not drawn as anything the grid already had: no logged fill,
      // no spotting ring, no estimated band, and not the plain day circle.
      for (final other in ['bleed', 'spotting', 'predicted', 'fertile']) {
        expect(
          find.byKey(ValueKey('$other-${kSupplied.iso}')),
          findsNothing,
          reason: 'the supplied day must not render as $other',
        );
      }
      expect(
        find.byKey(ValueKey('day-circle-${kSupplied.iso}')),
        findsNothing,
      );
      // The invariant on `Profile.lastPeriodStart`: an answer is not an
      // observation, so showing it never creates a day entry.
      expect(await h.entries.listForProfile(h.profile.id), isEmpty);
      await disposeCalendar(tester, h);
    });

    testWidgets('no other day carries it', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);

      expect(anyMark, findsOneWidget);
      expect(markOn(LocalDate(2026, 10, 2)), findsNothing);
      expect(
        find.bySemanticsLabel('Friday, October 2, not logged'),
        findsOneWidget,
        reason: 'an ordinary unlogged day keeps its old label',
      );
      expect(
        find.byKey(const ValueKey('day-circle-2026-10-02')),
        findsOneWidget,
      );
      await disposeCalendar(tester, h);
    });

    testWidgets('it is a ring of dots in the period colour, with no fill and '
        'no solid ring', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);

      final mark = markOn(kSupplied);
      final diameter = tester.getSize(mark).width;
      final dots = setupPeriodDotCountFor(diameter);
      // Every circle the mark paints is one dot: exactly as many as the
      // ring carries, each a filled dot one ring-stroke wide — so no
      // full-size fill (a logged day) and no stroked ring (today,
      // spotting) is painted.
      expect(mark, paintsExactlyCountTimes(#drawCircle, dots));
      expect(
        mark,
        paints..circle(
          radius: kCalendarRingStrokeWidth / 2,
          color: setupPeriodMarkColor(lightColors),
          style: PaintingStyle.fill,
        ),
      );
      for (final call in [#drawArc, #drawLine, #drawRRect, #drawDRRect]) {
        expect(mark, paintsExactlyCountTimes(call, 0));
      }
      await disposeCalendar(tester, h);
    });

    testWidgets('it draws in the dark theme, in that theme\'s period colour', (
      tester,
    ) async {
      final darkColors = AppTheme.darkTheme.extension<LunarLogColors>()!;
      final h = await pumpCalendar(
        tester,
        lastPeriodStart: kSupplied,
        theme: AppTheme.darkTheme,
      );

      expect(
        markOn(kSupplied),
        paints..circle(color: setupPeriodMarkColor(darkColors)),
      );
      expect(find.bySemanticsLabel(kSuppliedLabel), findsOneWidget);
      await disposeCalendar(tester, h);
    });

    testWidgets('when the supplied date is today, today\'s ring and the mark '
        'both draw, with a gap between them', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kToday);

      final ring = find.byKey(ValueKey('today-ring-${kToday.iso}'));
      expect(ring, findsOneWidget);
      expect(markOn(kToday), findsOneWidget);
      expect(
        tester.getSize(ring).width - tester.getSize(markOn(kToday)).width,
        kSetupPeriodTodayInset,
      );
      expect(
        find.bySemanticsLabel(
          'Monday, October 5, last period start from setup, not logged, '
          'today',
        ),
        findsOneWidget,
      );
      await disposeCalendar(tester, h);
    });

    testWidgets('tapping the mark opens the day sheet for that date, empty, '
        'as for any other past day', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);

      await tester.tap(markOn(kSupplied));
      await tester.pumpAndSettle();

      final sheet = tester.widget<DaySheet>(find.byType(DaySheet));
      expect(sheet.date, kSupplied);
      expect(
        sheet.existing,
        isNull,
        reason: 'the sheet opens empty: the mark is not an entry',
      );
      expect(sheet.readOnly, isFalse);
      await disposeCalendar(tester, h);
    });
  });

  group('the empty-month message', () {
    testWidgets('the month whose only content is the mark is not "No entries '
        'this month"; other empty months still are', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kIssueSupplied);

      // October (today's month) has nothing in it at all.
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-10')),
        findsOneWidget,
      );

      await goBackOneMonth(tester);
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-9')),
        findsNothing,
      );
      expect(find.text('No entries this month'), findsNothing);
      expect(markOn(kIssueSupplied), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Thursday, September 3, last period start from setup, not logged',
        ),
        findsOneWidget,
      );

      await goBackOneMonth(tester);
      expect(find.text('August 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-8')),
        findsOneWidget,
      );
      expect(anyMark, findsNothing);
      await disposeCalendar(tester, h);
    });
  });

  group('the legend row', () {
    testWidgets('keys the mark with a dotted swatch while it can appear', (
      tester,
    ) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);

      await openLegend(tester);
      expect(legendRow, findsOneWidget);
      expect(find.text(kLegendLabel), findsOneWidget);
      final swatch = find.descendant(
        of: legendRow,
        matching: find.byType(CustomPaint),
      );
      expect(
        swatch,
        paintsExactlyCountTimes(#drawCircle, setupPeriodDotCountFor(14)),
        reason: 'the swatch is the same ring of dots the grid draws',
      );
      expect(
        swatch,
        paints..circle(color: setupPeriodMarkColor(lightColors)),
      );
      await disposeCalendar(tester, h);
    });

    testWidgets('goes when the answers stop seeding an estimate: a date with '
        'no cycle length has no mark and no legend row', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);
      await openLegend(tester);
      expect(legendRow, findsOneWidget);
      await closeLegend(tester);

      // The date is still on the profile; without a cycle length there is
      // no estimate for it to explain.
      await h.profiles.update(
        h.profile.copyWith(typicalCycleLengthDays: null),
      );
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(find.bySemanticsLabel(kPlainLabel), findsOneWidget);
      await openLegend(tester);
      expect(legendRow, findsNothing);
      expect(find.text(kLegendLabel), findsNothing);
      await disposeCalendar(tester, h);
    });
  });

  group('a logged day wins', () {
    testWidgets('logging a period on the supplied day replaces the mark with '
        'the logged fill, and the legend row goes', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);
      expect(markOn(kSupplied), findsOneWidget);

      await h.entries.save(entryFor(h.profile.id, kSupplied));
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(
        find.byKey(ValueKey('bleed-${kSupplied.iso}')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Thursday, October 1, Medium flow, no symptoms'),
        findsOneWidget,
      );
      await openLegend(tester);
      expect(legendRow, findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('logging anything on the supplied day replaces the mark, even '
        'an entry that is not a period', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);
      expect(markOn(kSupplied), findsOneWidget);

      // A symptom-only entry starts no cycle, so the estimate still counts
      // from the supplied date — the day is logged all the same, and the
      // logged rendering wins.
      await h.entries.save(
        entryFor(
          h.profile.id,
          kSupplied,
          flow: FlowLevel.none,
          tags: const ['headache'],
        ),
      );
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(
        find.bySemanticsLabel('Thursday, October 1, logged symptoms'),
        findsOneWidget,
      );
      // Drawn as the logged symptom day it now is: the ordinary circle, with
      // the day's symptom-layer dot under it (headache is the profile's
      // most-used tag, so it is an active layer by default).
      expect(
        find.byKey(ValueKey('day-circle-${kSupplied.iso}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('layer-dot-headache-${kSupplied.iso}')),
        findsOneWidget,
      );
      await openLegend(tester);
      expect(
        legendRow,
        findsNothing,
        reason: 'the legend never keys a mark the grid cannot draw',
      );
      await disposeCalendar(tester, h);
    });
  });

  group('once the estimate no longer counts from the setup answer', () {
    testWidgets('a period logged after the supplied date takes over: the '
        'mark goes, the legend row goes, and that month is empty again', (
      tester,
    ) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kIssueSupplied);
      await goBackOneMonth(tester);
      expect(find.text('September 2026'), findsOneWidget);
      expect(markOn(kIssueSupplied), findsOneWidget);

      await h.logPeriod(LocalDate(2026, 10, 1));
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(
        find.bySemanticsLabel('Thursday, September 3, not logged'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-9')),
        findsOneWidget,
      );
      await openLegend(tester);
      expect(legendRow, findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('an earlier logged period leaves the mark; once the profile '
        'has logged cycles of its own, the mark and the legend row go', (
      tester,
    ) async {
      // One period logged a month before the supplied date: the estimate
      // still counts from the supplied date.
      final h = await pumpCalendar(
        tester,
        lastPeriodStart: kSupplied,
        seed: (h) => h.logPeriod(LocalDate(2026, 9, 2)),
      );
      expect(markOn(kSupplied), findsOneWidget);

      // Three more make three completed cycles: the estimate now comes from
      // the log, and the answers are displaced.
      for (final start in [
        LocalDate(2026, 6, 10),
        LocalDate(2026, 7, 8),
        LocalDate(2026, 8, 5),
      ]) {
        await h.logPeriod(start);
      }
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(find.bySemanticsLabel(kPlainLabel), findsOneWidget);
      await openLegend(tester);
      expect(legendRow, findsNothing);
      await disposeCalendar(tester, h);
    });
  });

  group('the mark follows the estimate\'s visibility', () {
    testWidgets('turning estimates off removes the mark and its legend row, '
        'and the month reads empty', (tester) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);
      expect(markOn(kSupplied), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-10')),
        findsNothing,
      );

      await h.settings.set(
        predictionsEnabledSettingKey(h.profile.id),
        'false',
      );
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(find.bySemanticsLabel(kPlainLabel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-month-empty-2026-10')),
        findsOneWidget,
      );
      await openLegend(tester);
      expect(legendRow, findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('a life-stage mode that suppresses estimates removes it', (
      tester,
    ) async {
      final h = await pumpCalendar(tester, lastPeriodStart: kSupplied);
      expect(markOn(kSupplied), findsOneWidget);

      await h.modes.save(
        profileId: h.profile.id,
        mode: LifecycleMode.pregnancy,
      );
      await tester.pumpAndSettle();

      expect(anyMark, findsNothing);
      expect(find.bySemanticsLabel(kPlainLabel), findsOneWidget);
      await openLegend(tester);
      expect(legendRow, findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('a view-only member sees the mark, and the day stays as '
        'inert as any other day they cannot log', (tester) async {
      final h = await pumpCalendar(
        tester,
        lastPeriodStart: kSupplied,
        viewerRole: 'viewer',
      );

      expect(markOn(kSupplied), findsOneWidget);
      expect(
        find.bySemanticsLabel('$kSuppliedLabel, read-only'),
        findsOneWidget,
      );
      await tester.tap(markOn(kSupplied));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsNothing);
      await disposeCalendar(tester, h);
    });
  });

  group('setupPeriodMarkDateFor', () {
    final supplied = LocalDate(2026, 9, 3);
    CyclePrediction seeded({
      LocalDate? start,
      LocalDate? today,
      List<Episode> episodes = const [],
    }) => seedProvisionalPrediction(
      facts: CycleFacts(
        lastPeriodStart: start ?? supplied,
        typicalCycleLengthDays: 28,
        typicalPeriodLengthDays: 5,
      ),
      today: today ?? kToday,
      episodes: episodes,
    );

    test('is the supplied date while the estimate counts from it', () {
      expect(setupPeriodMarkDateFor(seeded(), kToday), supplied);
    });

    test('still marks a seed more than 60 days old: the estimate is flagged '
        'unusually long and reads irregular, but it is still shown and still '
        'counts from the supplied date', () {
      final today = supplied.addDays(75);
      final prediction = seeded(today: today) as ActivePrediction;
      expect(prediction.unusuallyLongCycle, isTrue);
      expect(prediction.tier, CycleConfidence.irregular);
      expect(prediction.staleHistory, isFalse);
      expect(setupPeriodMarkDateFor(prediction, today), supplied);
    });

    test('is null once the seed is stale: the calendar withholds the whole '
        'estimate then, and the mark goes with it', () {
      final today = supplied.addDays(200);
      final prediction = seeded(today: today) as ActivePrediction;
      expect(prediction.staleHistory, isTrue);
      expect(prediction.cycleStartIsSupplied, isTrue);
      expect(setupPeriodMarkDateFor(prediction, today), isNull);
    });

    test('is null once a logged period is the cycle start', () {
      final logged = Episode(LocalDate(2026, 10, 1), LocalDate(2026, 10, 4));
      expect(
        setupPeriodMarkDateFor(seeded(episodes: [logged]), kToday),
        isNull,
      );
    });

    test('never marks a supplied date after today', () {
      final future = kToday.addDays(3);
      final prediction = seeded(start: future) as ActivePrediction;
      expect(prediction.cycleStartIsSupplied, isTrue);
      expect(setupPeriodMarkDateFor(prediction, kToday), isNull);
    });

    test('marks a supplied date that is today', () {
      expect(setupPeriodMarkDateFor(seeded(start: kToday), kToday), kToday);
    });

    test('is null for every state that shows no estimate', () {
      for (final prediction in <CyclePrediction>[
        const PredictionsDisabled(),
        const PredictionsSuppressed(lifecycleMode: LifecycleMode.pregnancy),
        const PredictionsSuppressed(method: BirthControlMethod.hormonalIud),
        const NotEnoughHistory(
          episodeCount: 0,
          completedCycleCount: 0,
          validCycleCount: 0,
          usableCycleCount: 0,
        ),
      ]) {
        expect(
          setupPeriodMarkDateFor(prediction, kToday),
          isNull,
          reason: '$prediction',
        );
      }
    });

    test('is null for a pack-schedule estimate: it counts from the method\'s '
        'start, not from a setup answer', () {
      final packDriven = computePrediction(
        episodes: const [],
        today: kToday,
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: LocalDate(2026, 9, 1),
        ),
      );
      expect(packDriven, isA<ActivePrediction>());
      expect(setupPeriodMarkDateFor(packDriven, kToday), isNull);
    });
  });

  group('dayCellSemanticLabel with the setup mark', () {
    final l10n = AppLocalizationsEn();
    final date = LocalDate(2026, 8, 31);

    test('names the mark between the date and "not logged"', () {
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: null,
          today: kToday,
          cell: null,
          l10n: l10n,
          isSetupPeriodStart: true,
        ),
        'Monday, August 31, last period start from setup, not logged',
      );
    });

    test('a logged day is announced as logged, whatever the flag says', () {
      expect(
        dayCellSemanticLabel(
          date: date,
          entry: entryFor('p', date),
          today: kToday,
          cell: null,
          l10n: l10n,
          isSetupPeriodStart: true,
        ),
        'Monday, August 31, Medium flow, no symptoms',
      );
    });

    test('a future day keeps its own label', () {
      final future = kToday.addDays(2);
      expect(
        dayCellSemanticLabel(
          date: future,
          entry: null,
          today: kToday,
          cell: null,
          l10n: l10n,
          isSetupPeriodStart: true,
        ),
        isNot(contains('last period start from setup')),
      );
    });
  });

  group('the mark\'s colour and dots', () {
    for (final themeEntry in {
      'light': AppTheme.lightTheme,
      'dark': AppTheme.darkTheme,
    }.entries) {
      test('${themeEntry.key} theme: the dots clear the 3:1 non-text floor '
          'against the surfaces a day cell sits on', () {
        final theme = themeEntry.value;
        final color = setupPeriodMarkColor(
          theme.extension<LunarLogColors>()!,
        );
        for (final background in {
          'surface': theme.colorScheme.surface,
          'surfaceContainerLow': theme.colorScheme.surfaceContainerLow,
        }.entries) {
          final ratio = wcagContrastRatio(color, background.value);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: '${themeEntry.key} mark/${background.key} was $ratio',
          );
        }
      });
    }

    test('the dots never run together into a solid ring, at the legend\'s '
        'size or any grid cell size', () {
      for (final diameter in [14.0, 26.0, 34.0, 48.0, 68.0]) {
        final count = setupPeriodDotCountFor(diameter);
        final ringLength = math.pi * (diameter - kCalendarRingStrokeWidth);
        expect(count, greaterThanOrEqualTo(kSetupPeriodMinDots));
        expect(
          ringLength / count,
          greaterThan(2 * kCalendarRingStrokeWidth),
          reason:
              'at $diameter px the gap between dots must be at least one '
              'dot wide',
        );
      }
    });
  });
}
