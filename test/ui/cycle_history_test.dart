/// Widget tests for issue #132: the cycle-history section (R4/R5) and the
/// three-option late resolver (R6), walked against the issue's acceptance
/// checklist — reverse-chronological list, omit-from-average moving the
/// estimate, reversibility, confidence framing, statistics, the resolver's
/// three options, the paused "log it" path, snooze, read-only, and the
/// disclaimer/device-local captions.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/account/auth_controller.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';

import '../support/fake_auth_service.dart';

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

/// Five 30-day cycles ending 2026-08-05 (kToday Aug 30 = cycle day 26).
final List<LocalDate> kSteadyStarts = [
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

/// Six completed cycles of which only the last three (28s) are valid:
/// lengths 90, 95, 100 then 28, 28, 28 — valid ratio 0.5 reads irregular.
final List<LocalDate> kIrregularRatioStarts = [
  LocalDate(2025, 8, 1),
  LocalDate(2025, 10, 30), // 90: outlier
  LocalDate(2026, 2, 2), // 95: outlier
  LocalDate(2026, 5, 13), // 100: outlier
  LocalDate(2026, 6, 10), // 28
  LocalDate(2026, 7, 8), // 28
  LocalDate(2026, 8, 5), // 28, open cycle
];

/// Lengths 28, 28, 20, 28: the 20-day cycle is the one STARTING Apr 5 (it
/// runs Apr 5 -> Apr 25); it drags the mean to 25.33 -> estimate Jun 17,
/// and today Jun 21 makes that late. Omitting it restores 28, 28, 28 ->
/// estimate Jun 20 -> not late.
final List<LocalDate> kShortOutlierStarts = [
  LocalDate(2026, 2, 8), // 28-day cycle starts here
  LocalDate(2026, 3, 8), // 28
  LocalDate(2026, 4, 5), // 20 (the short outlier)
  LocalDate(2026, 4, 25), // 28
  LocalDate(2026, 5, 23), // 28; open cycle
];

/// 30-day cycles with today day 45 of the open cycle: estimate Jul 27 is
/// 15 days past -> late; skipping advances the estimate to Aug 26.
final List<LocalDate> kSkipStarts = [
  LocalDate(2026, 3, 29),
  LocalDate(2026, 4, 28),
  LocalDate(2026, 5, 28),
  LocalDate(2026, 6, 27),
];

/// Four 30-day cycles ending 2026-06-26: open cycle 65 days -> paused.
final List<LocalDate> kPausedStarts = [
  LocalDate(2026, 3, 28),
  LocalDate(2026, 4, 27),
  LocalDate(2026, 5, 27),
  LocalDate(2026, 6, 26),
];

class Harness {
  Harness(this.db, this.profile, this.entries, this.settings);

  final LunarLogDatabase db;
  final Profile profile;
  final DriftDayEntriesRepository entries;
  final DriftSettingsStore settings;

  Widget appFor(
    Profile profile, {
    bool readOnly = false,
    AuthController? authController,
  }) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(
          value: DriftProfilesRepository(db.storage),
        ),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: settings),
        if (authController != null)
          ChangeNotifierProvider<AuthController>.value(value: authController),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries, settings: settings),
        ),
        Provider<CycleHistoryService>.value(
          value: CycleHistoryService(entries, settings: settings),
        ),
        Provider<CycleExclusionList>.value(value: CycleExclusionList(settings)),
        ChangeNotifierProvider<NotificationPermissionState>.value(
          value: NotificationPermissionState(
            NotificationAvailability.available,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: DriftProfilesRepository(db.storage),
            settingsStore: settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
        home: ProfileDetailScreen(
          profile: profile,
          readOnly: readOnly,
          todayProvider: () => today,
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
  await tester.pumpWidget(harness.appFor(profile, readOnly: readOnly));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Overview'));
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
        ]),
        reason: 'reverse-chronological below the open cycle',
      );
      expect(
        find.text('30 days'),
        findsNWidgets(6),
        reason: 'five completed rows plus the avg-cycle statistic',
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
    testWidgets('omitting an outlier cycle moves the estimate and clears the '
        'false late flag; the row stays visible and reversible', (
      tester,
    ) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 6, 21),
        starts: kShortOutlierStarts,
      );

      expect(find.text('Next period estimate: June 17, 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('late-resolver')),
        findsOneWidget,
        reason: 'the dragged-down mean makes this a false late',
      );

      await tester.tap(find.byKey(const ValueKey('history-omit-2026-04-05')));
      await tester.pumpAndSettle();

      expect(
        find.text('Next period estimate: June 20, 2026'),
        findsOneWidget,
        reason: 'the estimate moves once the outlier stops feeding it',
      );
      expect(
        find.byKey(const ValueKey('late-resolver')),
        findsNothing,
        reason: 'the false late flag clears',
      );
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
        find.text('Next period estimate: June 17, 2026'),
        findsOneWidget,
        reason: 'reversible: including it restores the old estimate',
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
      expect(find.text('Outlier — never averaged'), findsNWidgets(3));
      expect(
        find.byKey(const ValueKey('history-omit-2025-10-30')),
        findsNothing,
        reason: 'already excluded — a manual omit would be a no-op',
      );
      await disposeHistory(tester, h);
    });
  });

  group('AC4/AC5: confidence and statistics', () {
    testWidgets('steady 30-day history: high confidence, avg cycle 30, avg '
        'period 4, variation 0, disclaimer, device-local note', (tester) async {
      final h = await pumpHistory(tester, today: aug30, starts: kSteadyStarts);

      expect(find.text('High confidence'), findsOneWidget);
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
      expect(find.text('Irregular'), findsOneWidget);
      expect(find.textContaining('vary a lot'), findsOneWidget);
      expectNoFertilityVocabulary(tester, 'irregular confidence');
      await disposeHistory(tester, h);
    });
  });

  group('AC6: three-option late resolver', () {
    testWidgets('skip this cycle appends the open start to the exclusion list '
        'and replans the late window', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 8, 11),
        starts: kSkipStarts,
      );

      expect(find.text('Next period estimate: July 27, 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('resolver-skip')));
      await tester.pumpAndSettle();

      expect(
        find.text('Next period estimate: August 26, 2026'),
        findsOneWidget,
        reason: 'the skip advances the estimate one averaged cycle',
      );
      expect(
        find.byKey(const ValueKey('late-resolver')),
        findsNothing,
        reason: 'the late window replanned — no longer late',
      );
      expect(
        parseOmittedCycles(
          await h.settings.get(omittedCyclesSettingKey(h.profile.id)),
        ),
        contains(LocalDate(2026, 6, 27)),
        reason: 'skip feeds the same exclusion list as manual omit',
      );
      expect(
        find.text('Current cycle — started June 27, 2026'),
        findsOneWidget,
      );
      expect(find.text('Skipped — excluded from averages'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('history-undo-skip')));
      await tester.pumpAndSettle();
      expect(
        find.text('Next period estimate: July 27, 2026'),
        findsOneWidget,
        reason: 'undoing the skip restores the late window',
      );
      await disposeHistory(tester, h);
    });

    testWidgets('remind me in 3 days snoozes the resolver until the snooze '
        'date', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 8, 11),
        starts: kSkipStarts,
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
        await h.settings.get(lateSnoozeSettingKey(h.profile.id)),
        '2026-08-14',
      );

      await tester.tap(find.byKey(const ValueKey('late-snooze-show-now')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('late-resolver')),
        findsOneWidget,
        reason: 'the snooze is dismissible early',
      );
      await disposeHistory(tester, h);
    });

    testWidgets('"log it" opens the day sheet for today', (tester) async {
      final h = await pumpHistory(
        tester,
        today: LocalDate(2026, 8, 11),
        starts: kSkipStarts,
      );

      await tester.tap(find.byKey(const ValueKey('resolver-log')));
      await tester.pumpAndSettle();

      expect(find.byType(DaySheet), findsOneWidget);
      await disposeHistory(tester, h);
    });
  });

  group('AC7: paused state resolves through log it', () {
    testWidgets('an open cycle over sixty days shows the resolver with the '
        'log-it action', (tester) async {
      final h = await pumpHistory(tester, today: aug30, starts: kPausedStarts);

      expect(find.text('Awaiting next period'), findsOneWidget);
      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('resolver-log')));
      await tester.pumpAndSettle();
      expect(
        find.byType(DaySheet),
        findsOneWidget,
        reason: 'the way through the paused state is logging',
      );
      await disposeHistory(tester, h);
    });
  });

  group('read-only callers', () {
    testWidgets('an archived profile sees the history and the late '
        'information without any actions', (tester) async {
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
      expect(find.text('Log it'), findsNothing);
      expect(find.text('Skip this cycle'), findsNothing);
      expect(find.text('Remind me in 3 days'), findsNothing);
      expect(
        find.text('Period is late'),
        findsOneWidget,
        reason: 'the informational line remains',
      );
      await disposeHistory(tester, h);
    });
  });

  group('auth-driven attribution seam', () {
    testWidgets('signing in while the overview is mounted updates the '
        'attribution context without disturbing the history', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = LunarLogDatabase(NativeDatabase.memory());
      final profiles = DriftProfilesRepository(db.storage);
      final settings = DriftSettingsStore(db.storage);
      final entries = DriftDayEntriesRepository(db.storage);
      final profile = await profiles.create(displayName: 'Alice', isMinor: false);
      for (var i = 0; i < 4; i++) {
        await entries.save(DayEntry(
          id: '',
          profileId: profile.id,
          localDate: LocalDate(2026, 6, 27).addDays(i),
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const [],
          note: null,
          updatedAt: DateTime.utc(2026, 1, 1),
          deletedAt: null,
        ));
      }

      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final controller = AuthController(authService: auth);
      addTearDown(controller.dispose);

      final h = Harness(db, profile, entries, settings)
        ..today = LocalDate(2026, 7, 15);
      await tester.pumpWidget(h.appFor(profile, authController: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      // A sign-in while mounted re-runs the panel's auth listener; the
      // history and estimate stay coherent across the change.
      auth.emit(
        AuthSessionState.signedIn,
        user: const AuthUser(id: 'user-1'),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-card')), findsOneWidget);
      expectNoFertilityVocabulary(tester, 'signed-in attribution refresh');
      await disposeHistory(tester, h);
    });
  });
}
