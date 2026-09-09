/// Widget tests for U6: the overview panel — AE3 (active estimate + phase,
/// no fertility vocabulary in any state), not-enough/paused/late states,
/// estimate framing (R17), cycle-day counting, profile switching, the
/// reminder-hint seam, and stream-driven refresh (F4 in-app).
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/app_lifecycle.dart'
    show RequestNotificationPermissionCallback;
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/models/profile_mode.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

/// Fixed "today" so every derived number is deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

/// Materializes a server-authored guardian row locally (mirrors
/// `test/ui/logging_test.dart`'s helper of the same name -- each suite
/// keeps its own tiny copy rather than sharing one, matching the existing
/// convention across this test directory).
RemoteProfileGuardianRow guardianRow(
  String profileId,
  String id,
  String userId,
  String role, {
  String status = 'accepted',
}) => RemoteProfileGuardianRow(
  id: id,
  profileId: profileId,
  userId: userId,
  role: role,
  status: status,
  invitedBy: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  serverVersion: 1,
);

const String kDisclaimer = 'Estimates only — not medical advice.';
const String kReminderHint = 'Reminders unavailable — notifications are off';

/// R13 vocabulary sweep: stems that must never appear in rendered text.
const List<String> kForbiddenStems = [
  'fertil',
  'ovul',
  'conceiv',
  'concepti',
  'luteal',
  'follicular',
];

/// Six 30-day episodes ending 2026-08-05: mean 30, estimate 2026-09-04,
/// cycle day 26, ≈5 days until next period, mid-cycle (not during episode).
final List<LocalDate> kActiveStarts = [
  LocalDate(2026, 3, 8),
  LocalDate(2026, 4, 7),
  LocalDate(2026, 5, 7),
  LocalDate(2026, 6, 6),
  LocalDate(2026, 7, 6),
  LocalDate(2026, 8, 5),
];

/// Two episodes only: 1 valid cycle < 3 → not enough history.
final List<LocalDate> kNotEnoughStarts = [
  LocalDate(2026, 7, 1),
  LocalDate(2026, 7, 29),
];

/// Four 30-day episodes ending 2026-06-26: open cycle 65 days > 60 →
/// unusually long (issue #221/A2-12: no more dead-end pause). Original
/// estimate Jul 26, 35 days late by Aug 30 → rolled forward twice (30-day
/// mean) to Sep 24 (still within kAverageWindowCycles(6), so the spread is
/// exactly 0 — the estimate stays a single date, not a range).
final List<LocalDate> kPausedStarts = [
  LocalDate(2026, 3, 28),
  LocalDate(2026, 4, 27),
  LocalDate(2026, 5, 27),
  LocalDate(2026, 6, 26),
];

/// Five 28-day episodes ending 2026-07-05: original estimate 2026-08-02,
/// 28 days past it by kToday (2026-08-30) → more than the 2-day grace →
/// late. Issue #221: the estimate itself rolls forward one 28-day mean
/// cycle to land exactly on kToday (2026-08-30).
final List<LocalDate> kLateStarts = [
  LocalDate(2026, 3, 15),
  LocalDate(2026, 4, 12),
  LocalDate(2026, 5, 10),
  LocalDate(2026, 6, 7),
  LocalDate(2026, 7, 5),
];

/// Four 30-day episodes ending 2026-06-26: 15 days past the original
/// July 27 estimate by 2026-08-11 (more than the 2-day grace) rolls it
/// forward one 30-day mean cycle to August 26. Feeds the interactive
/// late-resolver action tests below (issue #132 AC6) -- moved here from
/// `test/ui/cycle_history_test.dart` under issue #314, since they
/// exercise [LateResolver], which stays in `OverviewPanel`, not the
/// cycle-history section that moved to the Analysis tab.
final List<LocalDate> kSkipStarts = [
  LocalDate(2026, 3, 29),
  LocalDate(2026, 4, 28),
  LocalDate(2026, 5, 28),
  LocalDate(2026, 6, 27),
];

/// 30-day episodes ending 2026-08-28 with a 4-day bleed spanning today.
final List<LocalDate> kDuringEpisodeStarts = [
  LocalDate(2026, 4, 30),
  LocalDate(2026, 5, 30),
  LocalDate(2026, 6, 29),
  LocalDate(2026, 7, 29),
  LocalDate(2026, 8, 28),
];

/// Three completed cycles of lengths 15, 60, 15 (mean 30, population
/// std-dev ≈21.21): all three lengths are individually valid (15 and 60
/// are the window's own boundaries) so validRatio is 1.0, but the spread
/// alone puts this over kIrregularSpreadThresholdDays (7) — irregular via
/// spread, not ratio. Estimate March30+June29+30=June29 (last start
/// 2026-05-30 + mean 30); range June8–July20 (±round(21.21)=21 days).
final List<LocalDate> kIrregularSpreadStarts = [
  LocalDate(2026, 3, 1),
  LocalDate(2026, 3, 16), // 15
  LocalDate(2026, 5, 15), // 60
  LocalDate(2026, 5, 30), // 15, open
];
final LocalDate kIrregularSpreadToday = LocalDate(2026, 6, 5);

class Harness {
  Harness(this.db, this.profile, this.profiles, this.entries, this._settings);

  final LunarLogDatabase db;
  final Profile profile;
  final DriftProfilesRepository profiles;
  final DriftDayEntriesRepository entries;
  final DriftSettingsStore _settings;

  /// The pumpable app for any profile over the same repositories.
  ///
  /// [authController]/[withStorage] (issue #316 review item 3) wire the
  /// same viewer-role seam `test/ui/logging_test.dart` exercises for the
  /// day sheet: without `withStorage`, [ProfileDetailScreen] gets no
  /// `LunarLogStorage` and so builds no `ProfileGuardiansRepository` at
  /// all, matching every pre-existing test's local-only tree unchanged.
  Widget appFor(
    Profile profile, {
    NotificationAvailability availability = NotificationAvailability.available,
    RequestNotificationPermissionCallback? requestPermission,
    LocalDate? today,
    bool readOnly = false,
    AuthController? authController,
    bool withStorage = false,
  }) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: _settings),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries, settings: _settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: _settings),
        ),
        Provider<CycleExclusionList>.value(
          value: CycleExclusionList(_settings),
        ),
        ChangeNotifierProvider<NotificationPermissionState>.value(
          value: NotificationPermissionState(availability),
        ),
        if (requestPermission != null)
          Provider<RequestNotificationPermissionCallback>.value(
            value: requestPermission,
          ),
        if (withStorage) Provider<LunarLogStorage>.value(value: db.storage),
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: profiles,
            settingsStore: _settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.lightTheme,
        home: ProfileDetailScreen(
          profile: profile,
          readOnly: readOnly,
          todayProvider: () => today ?? kToday,
        ),
      ),
    );
  }
}

Future<Harness> pumpOverview(
  WidgetTester tester, {
  NotificationAvailability availability = NotificationAvailability.available,
  ProfileMode mode = ProfileMode.standard,
  RequestNotificationPermissionCallback? requestPermission,
  LocalDate? today,
  bool readOnly = false,
  AuthController? authController,
  bool withStorage = false,
  Future<void> Function(DriftDayEntriesRepository entries, String profileId)?
      seed,
  /// Applied after the profile exists but before the widget pumps, so a
  /// guardian row can name the profile id (issue #316 review item 3).
  Future<void> Function(LunarLogStorage storage, String profileId)?
      seedGuardians,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final settings = DriftSettingsStore(db.storage);
  final entries = DriftDayEntriesRepository(db.storage);
  final profile = await profiles.create(
      displayName: 'Alice', isMinor: false, mode: mode);
  if (seed != null) {
    await seed(entries, profile.id);
  }
  if (seedGuardians != null) {
    await seedGuardians(db.storage, profile.id);
  }
  final harness =
      Harness(db, profile, profiles, entries, settings);
  await tester.pumpWidget(harness.appFor(
    profile,
    availability: availability,
    requestPermission: requestPermission,
    today: today,
    readOnly: readOnly,
    authController: authController,
    withStorage: withStorage,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Overview'));
  await tester.pumpAndSettle();
  return harness;
}

/// Same drift-stream teardown discipline as U4/U5 suites.
Future<void> disposeOverview(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

Future<void> seedEpisodes(
  DriftDayEntriesRepository entries,
  String profileId,
  List<LocalDate> starts, {
  int lengthDays = 4,
}) async {
  for (final start in starts) {
    for (var i = 0; i < lengthDays; i++) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
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
}

/// R13 sweep over every rendered Text in the tree for the given state.
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
      expect(lower.contains(stem), isFalse,
          reason: 'state "$state" renders "$text" containing "$stem" (R13)');
    }
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('U6 overview (R11/R13/R17, AE3)', () {
    testWidgets('active profile with 3+ valid cycles shows next-period '
        'estimate and cycle day; vocabulary sweep is clean', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.text('Cycle day 26'), findsOneWidget);
      expect(find.text('Next period estimate: September 4, 2026'),
          findsOneWidget);
      expect(find.text('≈5 days until next period'), findsOneWidget);
      expect(find.byKey(const ValueKey('late-resolver')), findsNothing,
          reason: 'not late: estimate is 5 days ahead');
      // Issue #314: CycleHistorySection no longer mounts on Overview --
      // it lives exclusively on the Analysis tab now (test/ui/
      // cycle_history_test.dart, test/ui/analysis_tab_test.dart).
      expect(find.byKey(const ValueKey('history-card')), findsNothing);
      expectNoFertilityVocabulary(tester, 'active mid-cycle');
      await disposeOverview(tester, h);
    });

    testWidgets('every estimate block carries the R17 disclaimer',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.text(kDisclaimer), findsWidgets,
          reason: 'the Today card carries it, plus the late resolver or '
              'status line whenever one of those also renders (R17)');
      await disposeOverview(tester, h);
    });

    testWidgets('below-threshold profile shows the not-enough state with no '
        'partial numbers (no digits or dates leak from the estimate card)',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kNotEnoughStarts),
      );

      expect(find.text('Not enough history yet'), findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.textContaining('Next period estimate'), findsNothing);
      expect(find.byKey(const ValueKey('late-resolver')), findsNothing);
      // Issue #187: the not-enough state is now the shared EmptyState
      // component, not a bespoke card.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-not-enough')),
          matching: find.byType(EmptyState),
        ),
        findsOneWidget,
      );

      // Issue #314: the sweep is scoped to the not-enough card itself
      // (rather than the whole tree) because the no-partial-numbers rule
      // (R11) governs the estimate surface specifically -- the "See cycle
      // history" link right below it is plain, digit-free copy either
      // way, so scoping is now belt-and-suspenders rather than load-
      // bearing the way it was when the cycle-history card (with its own
      // legitimate dates and lengths) used to render there too.
      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('overview-not-enough')),
          matching: find.byType(Text),
        ),
      ).map((text) => text.data ?? '').where((text) => text.isNotEmpty);
      expect(texts, isNotEmpty);
      for (final text in texts) {
        expect(RegExp(r'\d').hasMatch(text), isFalse,
            reason: 'partial number leaked in not-enough state: "$text"');
      }
      expectNoFertilityVocabulary(tester, 'not enough history');
      await disposeOverview(tester, h);
    });

    testWidgets('unusually-long-cycle state (>60-day open cycle) keeps a '
        'live rolled estimate and the "unusually long" prompt — issue '
        '#221/A2-12: no more dead-end pause', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );

      // The old dead-end card is gone: this is the same active-estimate
      // card every other state renders, just at irregular confidence with
      // a rolled-forward estimate and the extra prompt below.
      expect(find.byKey(const ValueKey('overview-active')), findsOneWidget);
      expect(find.text('Awaiting next period'), findsNothing);
      expect(find.textContaining('Predictions are paused'), findsNothing);
      expect(find.text('Cycle day 66'), findsOneWidget);
      expect(find.text('Next period estimate: September 24, 2026'),
          findsOneWidget,
          reason: 'rolled forward twice (30-day mean) from the original '
              'Jul 26 estimate');
      expect(
        find.text('Irregular — Cycles vary a lot — treat estimates as '
            'rough guides.'),
        findsOneWidget,
        reason: 'issue #221/A2-12 forces the irregular tier past 60 open '
            'days',
      );
      // Issue #132 (AC7): still resolves through the resolver — "log it"
      // is right there — and now also the dedicated long-cycle prompt.
      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);
      expect(find.text('35 days late'), findsOneWidget);
      expect(find.text('Log it'), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-long-cycle-prompt')),
          findsOneWidget);
      expect(find.text('This cycle is unusually long'), findsOneWidget);
      expect(find.text('Exclude this cycle'), findsOneWidget);
      expect(find.text('Turn off predictions (coming soon)'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('long-cycle-predictions-off')),
            )
            .onPressed,
        isNull,
        reason: 'issue #225 is not built yet -- the button is an honestly '
            'disabled placeholder, not a live one that only shows a '
            'snackbar',
      );
      expect(find.text(kDisclaimer), findsWidgets,
          reason: 'the Today card and the resolver each carry it');
      expectNoFertilityVocabulary(tester, 'unusually long cycle');

      // Issue #132 (AC7)/#314: the resolver's "log it" is the way through
      // this state, and (now that the history section moved to Insights)
      // opens the ordinary day sheet the same as anywhere else.
      await tester.tap(find.byKey(const ValueKey('resolver-log')));
      await tester.pumpAndSettle();
      expect(find.byType(DaySheet), findsOneWidget);
      await disposeOverview(tester, h);
    });

    testWidgets('the long-cycle prompt\'s "Exclude this cycle" feeds the '
        'same exclusion list as the resolver\'s "Skip this cycle", and '
        'confirms once the write completes; "Turn off predictions" is '
        'disabled (issue #225 not yet built)', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );

      // The not-yet-built #225 action never even shows a snackbar now --
      // it is a disabled button, so tapping it (were that possible) is not
      // exercised here; the disabled state itself is pinned above.

      await tester.tap(find.byKey(const ValueKey('long-cycle-exclude')));
      await tester.pump();
      expect(
        find.text('This cycle is excluded from future averages.'),
        findsOneWidget,
        reason: 'the prompt keeps showing (the cycle is still open), so a '
            'brief confirmation is the only visible sign the tap did '
            'anything',
      );
      await tester.pumpAndSettle();
      expect(
        parseOmittedCycles(
          await h._settings.get(omittedCyclesSettingKey(h.profile.id)),
        ),
        contains(LocalDate(2026, 6, 26)),
        reason: 'exclude feeds the same exclusion list as manual omit / '
            'the resolver\'s skip',
      );
      await disposeOverview(tester, h);
    });

    testWidgets('late state (estimate + 2 days passed, nothing logged) shows '
        'the three-option resolver instead of the days-until line',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );

      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);
      expect(find.text('28 days late'), findsOneWidget);
      expect(find.text('Log it'), findsOneWidget);
      expect(find.text('Skip this cycle'), findsOneWidget);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.text('Next period estimate: August 30, 2026'), findsOneWidget,
          reason: 'the estimate itself rolled forward one 28-day mean '
              'cycle (issue #221) and stays visible with its disclaimer');
      expect(find.byKey(const ValueKey('overview-long-cycle-prompt')),
          findsNothing,
          reason: 'only 56 days open — not past kMaxOpenCycleDays');
      expect(find.text(kDisclaimer), findsWidgets,
          reason: 'the estimate card and the resolver each carry it');
      expectNoFertilityVocabulary(tester, 'late');
      await disposeOverview(tester, h);
    });

    group('provisional onboarding-seeded estimate (issue #218)', () {
    testWidgets('a profile with cycle facts and no logged cycles shows the '
        'provisional estimate, tier caption, and disclaimer — never the '
        'not-enough state', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final profile = await profiles.create(
        displayName: 'Alice',
        isMinor: false,
        lastPeriodStart: LocalDate(2026, 8, 7),
        typicalCycleLengthDays: 28,
        typicalPeriodLengthDays: 5,
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<DayEntriesRepository>.value(value: entries),
            Provider<SettingsStore>.value(value: settings),
            // The one behavioral difference from the harness above: the
            // profiles repository is wired, so the service can seed.
            Provider<CyclePredictionService>.value(
              value: CyclePredictionService(entries,
                  settings: settings, profiles: profiles),
            ),
            Provider<CycleExclusionList>.value(
              value: CycleExclusionList(settings),
            ),
            ChangeNotifierProvider<NotificationPermissionState>.value(
              value:
                  NotificationPermissionState(NotificationAvailability.available),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: OverviewPanel(profileId: profile.id, todayProvider: () => kToday),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2026-08-07 + 28 = 2026-09-04; provisional is not `high`, so the
      // estimate renders as the ±kProvisionalSpreadDays range.
      expect(
        find.text('Next period estimate: August 31, 2026 – September 8, 2026'),
        findsOneWidget,
      );
      expect(find.text('Provisional — Based on your onboarding answers — '
          'estimates improve once real cycles are logged.'), findsOneWidget);
      expect(find.text('≈5 days until next period'), findsOneWidget);
      expect(find.text('Provisional'), findsOneWidget,
          reason: 'the Today card confidence chip');
      expect(find.byKey(const ValueKey('overview-not-enough')), findsNothing);
      expect(find.byKey(const ValueKey('overview-tier-caption')),
          findsOneWidget);
      // R17: the disclaimer sits next to the seeded estimate like any
      // other.
      expect(find.text(kDisclaimer), findsWidgets);

      // Same teardown discipline as disposeOverview: unmount, let the
      // drift stream store's close-timer fire, then close the database —
      // otherwise the pending FakeTimer fails the test's invariants.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('skipping the questions keeps the not-enough state exactly '
        'as today (a facts-less profile with no repository wiring is the '
        'pre-#218 behavior)', (tester) async {
      final h = await pumpOverview(tester);
      expect(find.byKey(const ValueKey('overview-not-enough')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-tier-caption')), findsNothing);
      await disposeOverview(tester, h);
    });
  });

  group('issue #132 (AC6): three-option late resolver actions -- moved '
        'here from cycle_history_test.dart under issue #314, since the '
        'resolver stays in OverviewPanel while the cycle-history section '
        'it used to sit next to moved to the Analysis tab', () {
      testWidgets('skip this cycle appends the open start to the '
          'exclusion list and replans the late window; undoing through '
          'the same exclusion list the Insights history section reads '
          'restores it', (tester) async {
        final h = await pumpOverview(
          tester,
          today: LocalDate(2026, 8, 11),
          seed: (entries, profileId) =>
              seedEpisodes(entries, profileId, kSkipStarts),
        );

        expect(find.text('Next period estimate: August 26, 2026'),
            findsOneWidget);
        expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('resolver-skip')));
        await tester.pumpAndSettle();

        expect(find.text('Next period estimate: August 26, 2026'),
            findsOneWidget,
            reason: 'the skip advances the un-rolled estimate one '
                'averaged cycle (Jul 27 + 30) to the same date the late '
                'roll had already reached');
        expect(find.byKey(const ValueKey('late-resolver')), findsNothing,
            reason: 'the late window replanned -- no longer late');
        expect(
          parseOmittedCycles(
            await h._settings.get(omittedCyclesSettingKey(h.profile.id)),
          ),
          contains(LocalDate(2026, 6, 27)),
          reason: 'skip feeds the same device-local exclusion list the '
              'cycle-history section on Insights reads',
        );

        // Issue #314: the history section's own "Undo" button on the
        // open-cycle row lived on this screen before; it moved to
        // Insights along with the section, so this drives the same
        // CycleExclusionList it would have called directly instead.
        await CycleExclusionList(h._settings)
            .include(h.profile.id, LocalDate(2026, 6, 27));
        await tester.pumpAndSettle();
        expect(find.text('Next period estimate: August 26, 2026'),
            findsOneWidget,
            reason: 'reversible: including it restores the late window');
        expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);
        await disposeOverview(tester, h);
      });

      testWidgets('remind me in 3 days snoozes the resolver until the '
          'snooze date', (tester) async {
        final h = await pumpOverview(
          tester,
          today: LocalDate(2026, 8, 11),
          seed: (entries, profileId) =>
              seedEpisodes(entries, profileId, kSkipStarts),
        );

        await tester.tap(find.byKey(const ValueKey('resolver-remind')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('late-resolver')), findsNothing);
        expect(find.byKey(const ValueKey('late-snoozed')), findsOneWidget);
        expect(
          find.text('We will check back on August 14.'),
          findsOneWidget,
          reason: 'today (Aug 11) + 3 days',
        );
        expect(
          await h._settings.get(lateSnoozeSettingKey(h.profile.id)),
          '2026-08-14',
        );

        await tester.tap(find.byKey(const ValueKey('late-snooze-show-now')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('late-resolver')),
          findsOneWidget,
          reason: 'the snooze is dismissible early',
        );
        await disposeOverview(tester, h);
      });

      testWidgets('a read-only (archived) profile sees the late line but '
          'no actions -- the resolver still renders, "Log it"/"Skip this '
          'cycle"/"Remind me in 3 days" are absent (issue #314 review '
          'item 1)', (tester) async {
        final h = await pumpOverview(
          tester,
          today: LocalDate(2026, 8, 11),
          readOnly: true,
          seed: (entries, profileId) =>
              seedEpisodes(entries, profileId, kSkipStarts),
        );

        expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);
        expect(find.text('15 days late'), findsOneWidget);
        expect(find.text('Log it'), findsNothing);
        expect(find.text('Skip this cycle'), findsNothing);
        expect(find.text('Remind me in 3 days'), findsNothing);
        await disposeOverview(tester, h);
      });
    });

    testWidgets('mid-cycle phase reads "Cycle day N" and never "Period"',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      // Issue #209: the plain-text phase headline moved into the Today
      // card's cycle wheel (its centre label carries this key now).
      expect(find.byKey(const ValueKey('cycle-wheel-center-label')),
          findsOneWidget);
      expect(find.text('Cycle day 26'), findsOneWidget);
      expect(find.text('Period'), findsNothing,
          reason: 'today is outside every episode');
      expectNoFertilityVocabulary(tester, 'mid-cycle phase');
      await disposeOverview(tester, h);
    });

    testWidgets('during an episode the phase reads "Period · day N" and no '
        'bare "Cycle day" count shows', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kDuringEpisodeStarts),
      );

      // Issue #209: the wheel's centre label carries the day count too.
      expect(find.text('Period · day 3'), findsOneWidget);
      expect(find.textContaining('Cycle day'), findsNothing);
      expect(find.text('Next period estimate: September 27, 2026'),
          findsOneWidget);
      expectNoFertilityVocabulary(tester, 'during episode');
      await disposeOverview(tester, h);
    });

    testWidgets('issue #213: an irregular-tier estimate renders as a range '
        'with the tier caption', (tester) async {
      final h = await pumpOverview(
        tester,
        today: kIrregularSpreadToday,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kIrregularSpreadStarts),
      );

      expect(find.byKey(const ValueKey('overview-tier-caption')),
          findsOneWidget);
      expect(
        find.text('Irregular — Cycles vary a lot — treat estimates as '
            'rough guides.'),
        findsOneWidget,
      );
      expect(
        find.text('Next period estimate: June 8, 2026 – July 20, 2026'),
        findsOneWidget,
        reason: 'below-high tiers show a range (± round(spreadDays)) '
            'instead of one exact date',
      );
      expectNoFertilityVocabulary(tester, 'irregular-tier range');
      await disposeOverview(tester, h);
    });

    testWidgets('issue #213: a degenerate (rounded-zero) spread falls back '
        'to the single date instead of a redundant range', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      // kActiveStarts has 5 steady 30-day cycles: the 6-cycle average
      // window (kAverageWindowCycles) is not yet full, so the tier reads
      // learning rather than high (issue #213 item 5) and the caption
      // renders — but the population std-dev of five identical lengths is
      // exactly 0, so estimatedRangeStart == estimatedRangeEnd. The
      // estimate line must still show the single date, never
      // "September 4, 2026 – September 4, 2026".
      expect(find.byKey(const ValueKey('overview-tier-caption')),
          findsOneWidget);
      expect(
        find.text('Learning — Still learning — estimates improve after a '
            'few more cycles.'),
        findsOneWidget,
      );
      expect(find.text('Next period estimate: September 4, 2026'),
          findsOneWidget,
          reason: 'a degenerate zero spread must fall back to the single '
              'date');
      expect(
        find.textContaining('September 4, 2026 – September 4, 2026'),
        findsNothing,
      );
      await disposeOverview(tester, h);
    });

    testWidgets('switching profiles swaps overview content with no '
        'carryover', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final alice = await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: true);
      await seedEpisodes(entries, alice.id, kActiveStarts);
      await seedEpisodes(entries, bob.id, kNotEnoughStarts);
      final h = Harness(db, alice, profiles, entries, settings);

      await tester.pumpWidget(h.appFor(alice));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Cycle day 26'), findsOneWidget);
      expect(find.text('Next period estimate: September 4, 2026'),
          findsOneWidget);

      await tester.pumpWidget(h.appFor(bob));
      await tester.pumpAndSettle();
      expect(find.text('Not enough history yet'), findsOneWidget);
      expect(find.text('Cycle day 26'), findsNothing,
          reason: 'no cross-profile carryover');
      expect(find.text('Next period estimate: September 4, 2026'),
          findsNothing);
      expectNoFertilityVocabulary(tester, 'switched profile');
      await disposeOverview(tester, h);
    });

    testWidgets('reminder hint renders only when the injected availability '
        'flag says denied', (tester) async {
      final h = await pumpOverview(
        tester,
        availability: NotificationAvailability.denied,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.text(kReminderHint), findsOneWidget);

      await tester.pumpWidget(
          h.appFor(h.profile, availability: NotificationAvailability.available));
      await tester.pumpAndSettle();
      expect(find.text(kReminderHint), findsNothing);
      expect(find.text('Cycle day 26'), findsOneWidget,
          reason: 'overview content survives the availability re-pump');
      await disposeOverview(tester, h);
    });

    testWidgets(
        'the reminder hint has no "Turn on reminders" action when no '
        'permission-request seam is provided (issue #168 fallback)',
        (tester) async {
      final h = await pumpOverview(
        tester,
        availability: NotificationAvailability.denied,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.text(kReminderHint), findsOneWidget);
      expect(find.text('Turn on reminders'), findsNothing);
      await disposeOverview(tester, h);
    });

    testWidgets(
        'tapping "Turn on reminders" (issue #168) calls the injected '
        'request seam', (tester) async {
      var calls = 0;
      final h = await pumpOverview(
        tester,
        availability: NotificationAvailability.denied,
        requestPermission:
            RequestNotificationPermissionCallback(() async {
          calls++;
        }),
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      final button = find.byKey(const ValueKey('reminder-hint-action'));
      expect(button, findsOneWidget);
      expect(find.text('Turn on reminders'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(calls, 1);
      await disposeOverview(tester, h);
    });

    testWidgets(
        'the "Turn on reminders" button disables itself while the request '
        'is in flight and re-enables once it resolves', (tester) async {
      final gate = Completer<void>();
      final h = await pumpOverview(
        tester,
        availability: NotificationAvailability.denied,
        requestPermission:
            RequestNotificationPermissionCallback(() => gate.future),
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      final button = find.byKey(const ValueKey('reminder-hint-action'));
      await tester.tap(button);
      await tester.pump();

      expect(
        tester.widget<TextButton>(button).onPressed,
        isNull,
        reason: 'a second tap while the first request is in flight must '
            'not fire another one',
      );

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.widget<TextButton>(button).onPressed, isNotNull);
      await disposeOverview(tester, h);
    });

    testWidgets('logging a period through the repository refreshes the '
        'overview via the stream (late state clears)', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );

      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);

      await h.entries.save(DayEntry(
        id: '',
        profileId: h.profile.id,
        localDate: kToday,
        tz: 'America/Chicago',
        flow: FlowLevel.medium,
        tags: const [],
        note: null,
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: null,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('late-resolver')), findsNothing,
          reason: 'the new episode resets the open cycle');
      expect(find.text('Period · day 1'), findsOneWidget,
          reason: 'today is now day 1 of the new episode');
      expect(find.text('≈34 days until next period'), findsOneWidget,
          reason: 'issue #213 widened the prediction window to 12 cycles '
              '(was 3): mean of all five lengths [28, 28, 28, 28, 56] is '
              '33.6, rounding to 34 from 2026-08-30');
      await disposeOverview(tester, h);
    });
  });

  group('care modes (Issue #131, R12)', () {
    testWidgets('the estimate disclaimer is present in every mode, without '
        'exception', (tester) async {
      for (final mode in ProfileMode.values) {
        final h = await pumpOverview(
          tester,
          mode: mode,
          seed: (entries, profileId) =>
              seedEpisodes(entries, profileId, kActiveStarts),
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('overview-active')),
            matching: find.text(kDisclaimer),
          ),
          findsOneWidget,
          reason: 'mode ${mode.name} must carry the disclaimer (R17/#131)',
        );
        await disposeOverview(tester, h);
      }
    });

    testWidgets('teen mode changes the overview vocabulary: not-enough and '
        'awaiting copy differ, disclaimer stays', (tester) async {
      final notEnough = await pumpOverview(
        tester,
        mode: ProfileMode.teen,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kNotEnoughStarts),
      );
      expect(find.text('Your record is just getting started'), findsOneWidget);
      expect(find.text('Not enough history yet'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-not-enough')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
      );
      await disposeOverview(tester, notEnough);

      // Issue #221/A2-12: an open cycle past sixty days is no longer its
      // own dead-end "awaiting" card — it renders the same active-estimate
      // card every other state does, with the mode-agnostic "unusually
      // long" prompt alongside it.
      final longCycle = await pumpOverview(
        tester,
        mode: ProfileMode.teen,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.text('Waiting for your next period'), findsNothing);
      expect(find.textContaining('Predictions are paused'), findsNothing);
      expect(find.byKey(const ValueKey('overview-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-long-cycle-prompt')),
          findsOneWidget);
      await disposeOverview(tester, longCycle);
    });

    testWidgets('teen mode keeps the standard resolver when late (teen is '
        'not a reduced app, and honest late framing still applies)',
        (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.teen,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );
      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget,
          reason: 'only irregular silences the resolver');
      expect(
        find.text('Your next period is estimated around: August 30, 2026'),
        findsOneWidget,
        reason: 'issue #221: rolled forward one 28-day mean cycle',
      );
      await disposeOverview(tester, h);
    });

    testWidgets('caregiver mode still shows the unusually-long-cycle prompt '
        '(mode-agnostic) alongside its own copy', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.caregiver,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.byKey(const ValueKey('overview-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-long-cycle-prompt')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-active')),
          matching: find.text(kDisclaimer),
        ),
        findsWidgets,
        reason: 'the estimate card carries it, and the resolver the '
            'unusually-long state still shows carries its own copy',
      );
      await disposeOverview(tester, h);
    });

    testWidgets('irregular mode silences the late resolver and rewords the '
        'overview status (roadmap U6 test scenario)', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.irregular,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );
      expect(find.byKey(const ValueKey('late-resolver')), findsNothing,
          reason: 'irregular silences the late banner (#131)');
      expect(find.text('Log it'), findsNothing);
      expect(find.byKey(const ValueKey('overview-irregular-overdue')),
          findsOneWidget);
      expect(find.textContaining('variation like this is common'),
          findsOneWidget);
      expect(find.text('Next period may start around: August 30, 2026'),
          findsOneWidget,
          reason: 'issue #221: rolled forward one 28-day mean cycle');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-active')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
        reason: 'silencing the banner never silences the disclaimer',
      );
      // Issue #131/#213 cheap fix: kLateStarts' 5 steady cycles would show
      // the "Learning" tier caption in standard mode (the 6-cycle window
      // is not yet full) — irregular mode's own overdue line already
      // carries that framing, so the separate caption is silenced too.
      expect(find.byKey(const ValueKey('overview-tier-caption')),
          findsNothing,
          reason: 'irregular mode silences the tier caption (#131/#213)');
      expectNoFertilityVocabulary(tester, 'irregular late');
      await disposeOverview(tester, h);
    });

    testWidgets('irregular mode silences the resolver in the '
        'unusually-long-cycle state too, keeping the disclaimer and the '
        'mode-agnostic long-cycle prompt', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.irregular,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.byKey(const ValueKey('late-resolver')), findsNothing);
      expect(find.byKey(const ValueKey('overview-irregular-overdue')),
          findsOneWidget);
      // Issue #221/A2-12: the "unusually long" prompt is not the late
      // banner — it still renders even though irregular mode silences
      // that banner.
      expect(find.byKey(const ValueKey('overview-long-cycle-prompt')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-active')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
      );
      await disposeOverview(tester, h);
    });
  });

  group('issue #209: Today card (cycle wheel + one-tap quick log)', () {
    testWidgets('renders the wheel, next-period estimate, confidence chip, '
        'and disclaimer exactly once', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.byKey(const ValueKey('today-card')), findsOneWidget);
      expect(find.byKey(const ValueKey('cycle-wheel-center-label')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('today-card')),
          matching: find.text('Next period estimate: September 4, 2026'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('today-card-confidence-chip')),
          findsOneWidget);
      // Descendant-scoped (rather than a bare `find.text`) since the
      // history section's own confidence chip carries the same tier
      // label on Insights (issue #314: no longer on this screen at all).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('today-card-confidence-chip')),
          matching: find.text('Learning'),
        ),
        findsOneWidget,
        reason: 'kActiveStarts has not yet filled the 6-cycle average '
            'window (issue #213 item 5)',
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('today-card')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
      );
      await disposeOverview(tester, h);
    });

    testWidgets('tapping "Period started today" logs a medium-flow entry '
        'for today through the ordinary DayEntriesRepository path, and the '
        'wheel updates to reflect it', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(await h.entries.find(h.profile.id, kToday), isNull);

      await tester.tap(find.byKey(const ValueKey('today-card-log-action')));
      await tester.pumpAndSettle();

      final saved = await h.entries.find(h.profile.id, kToday);
      expect(saved, isNotNull);
      expect(saved!.flow, FlowLevel.medium);
      expect(find.text('Period · day 1'), findsOneWidget,
          reason: 'the new episode recomputes the prediction stream');
      await disposeOverview(tester, h);
    });

    testWidgets('a second tap is idempotent: no duplicate entry, and an '
        'already-heavier flow is never downgraded', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) async {
          await seedEpisodes(entries, profileId, kActiveStarts);
          // Today is already logged heavier than the quick-log default.
          await entries.save(DayEntry(
            id: '',
            profileId: profileId,
            localDate: kToday,
            tz: 'America/Chicago',
            flow: FlowLevel.heavy,
            tags: const [],
            note: 'already logged',
            updatedAt: DateTime.utc(2026, 1, 1),
            deletedAt: null,
          ));
        },
      );

      await tester.tap(find.byKey(const ValueKey('today-card-log-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-card-log-action')));
      await tester.pumpAndSettle();

      final all = await h.entries.listForProfile(h.profile.id);
      final todays = all.where((e) => e.localDate == kToday).toList();
      expect(todays, hasLength(1),
          reason: 'a second tap must never create a second entry');
      expect(todays.single.flow, FlowLevel.heavy,
          reason: 'a flow already logged heavier than the quick-log '
              'default must never be downgraded');
      expect(todays.single.note, 'already logged',
          reason: 'the rest of the existing entry is preserved');
      await disposeOverview(tester, h);
    });

    testWidgets('the quick-log action is hidden (not merely disabled) for '
        'a read-only (archived) profile, though the wheel/estimate stay '
        'visible', (tester) async {
      final h = await pumpOverview(
        tester,
        readOnly: true,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.byKey(const ValueKey('today-card')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-card-log-action')),
        findsNothing,
      );
      await disposeOverview(tester, h);
    });

    testWidgets('irregular mode silences the confidence chip too (same '
        'flag that silences the tier caption)', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.irregular,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );

      expect(
        find.byKey(const ValueKey('today-card-confidence-chip')),
        findsNothing,
      );
      await disposeOverview(tester, h);
    });
  });

  group('issue #314: "See cycle history" link', () {
    testWidgets(
        'no AppShellScope is mounted here (ProfileDetailScreen pumps '
        'OverviewPanel outside any AppShell), so the link renders '
        'nothing rather than a dead button', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(
        find.byKey(const ValueKey('overview-see-history-link')),
        findsNothing,
      );
      await disposeOverview(tester, h);
    });

    testWidgets(
        'still absent in the not-enough-history state -- the link is '
        'gated on the shell scope, not on which card renders above it',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kNotEnoughStarts),
      );

      expect(
        find.byKey(const ValueKey('overview-see-history-link')),
        findsNothing,
      );
      await disposeOverview(tester, h);
    });
  });

  group('issue #316 review item 3: viewer-role gate on the Today card '
      'quick-log action', () {
    testWidgets('an accepted viewer guardian hides the quick-log action '
        'entirely (the same live guardian watch TodayLogFab and '
        'MonthCalendar already use)', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-doc'));
      final authController = AuthController(authService: auth);
      final h = await pumpOverview(
        tester,
        authController: authController,
        withStorage: true,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
        seedGuardians: (storage, profileId) => storage.applyRemoteRows([
          guardianRow(profileId, 'g-doc', 'user-doc', 'viewer'),
        ]),
      );

      expect(find.byKey(const ValueKey('today-card')), findsOneWidget,
          reason: 'the wheel/estimate stay visible -- only the write '
              'action is gated');
      expect(
        find.byKey(const ValueKey('today-card-log-action')),
        findsNothing,
      );

      authController.dispose();
      await auth.dispose();
      await disposeOverview(tester, h);
    });

    testWidgets('an accepted co-parent guardian keeps the quick-log action '
        'visible', (tester) async {
      final auth = FakeAuthService()
        ..emit(AuthSessionState.signedIn,
            user: const AuthUser(id: 'user-parent'));
      final authController = AuthController(authService: auth);
      final h = await pumpOverview(
        tester,
        authController: authController,
        withStorage: true,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
        seedGuardians: (storage, profileId) => storage.applyRemoteRows([
          guardianRow(profileId, 'g-parent', 'user-parent', 'co_parent'),
        ]),
      );

      expect(
        find.byKey(const ValueKey('today-card-log-action')),
        findsOneWidget,
      );

      authController.dispose();
      await auth.dispose();
      await disposeOverview(tester, h);
    });
  });

  group('issue #316 review item 5: undo + disclosure on the quick-log '
      'write', () {
    testWidgets('a successful write shows a confirmation snackbar with an '
        'Undo action; undo after a create removes the entry entirely',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(await h.entries.find(h.profile.id, kToday), isNull);

      await tester.tap(find.byKey(const ValueKey('today-card-log-action')));
      await tester.pumpAndSettle();

      expect(await h.entries.find(h.profile.id, kToday), isNotNull);
      expect(
        find.text('Recorded a medium-flow period start for today.'),
        findsOneWidget,
      );
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(await h.entries.find(h.profile.id, kToday), isNull,
          reason: 'undo after a create removes the entry the tap made, '
              'through the ordinary DayEntriesRepository delete path');
      await disposeOverview(tester, h);
    });

    testWidgets('undo after an upgrade restores the prior flow level and '
        'preserves tags/note', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) async {
          await seedEpisodes(entries, profileId, kActiveStarts);
          await entries.save(DayEntry(
            id: '',
            profileId: profileId,
            localDate: kToday,
            tz: 'America/Chicago',
            flow: FlowLevel.light,
            tags: const ['cramps'],
            note: 'before the quick log',
            updatedAt: DateTime.utc(2026, 1, 1),
            deletedAt: null,
          ));
        },
      );

      await tester.tap(find.byKey(const ValueKey('today-card-log-action')));
      await tester.pumpAndSettle();

      final upgraded = await h.entries.find(h.profile.id, kToday);
      expect(upgraded, isNotNull);
      expect(upgraded!.flow, FlowLevel.medium);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      final restored = await h.entries.find(h.profile.id, kToday);
      expect(restored, isNotNull);
      expect(restored!.flow, FlowLevel.light,
          reason: 'undo restores the prior flow level exactly');
      expect(restored.tags, ['cramps']);
      expect(restored.note, 'before the quick log');
      await disposeOverview(tester, h);
    });
  });

  group('issue #314 review item 3: OverviewPanel.trailingChildren', () {
    testWidgets(
        'a trailing widget renders inside the same ListView, below the '
        'estimate content', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final profile =
          await profiles.create(displayName: 'Alice', isMinor: false);
      await seedEpisodes(entries, profile.id, kActiveStarts);

      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<DayEntriesRepository>.value(value: entries),
          Provider<SettingsStore>.value(value: settings),
          Provider<CyclePredictionService>.value(
            value: CyclePredictionService(entries, settings: settings),
          ),
          Provider<CycleExclusionList>.value(
            value: CycleExclusionList(settings),
          ),
          ChangeNotifierProvider<NotificationPermissionState>.value(
            value:
                NotificationPermissionState(NotificationAvailability.available),
          ),
        ],
        child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: OverviewPanel(
              profileId: profile.id,
              todayProvider: () => kToday,
              trailingChildren: const [
                Text('trailing marker', key: ValueKey('trailing-marker')),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('overview-active')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byKey(const ValueKey('trailing-marker')),
        ),
        findsOneWidget,
        reason: 'trailingChildren is appended inside the panel\'s own '
            'ListView -- one scroll region, not a second scrollable',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });
}
