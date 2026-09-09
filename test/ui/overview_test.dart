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
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
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
import 'package:lunarlog/ui/components/empty_state.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/profiles/profile_detail_screen.dart';
import 'package:provider/provider.dart';

/// Fixed "today" so every derived number is deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

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

/// Four 30-day episodes ending 2026-06-26: open cycle 65 days > 60 → paused.
final List<LocalDate> kPausedStarts = [
  LocalDate(2026, 3, 28),
  LocalDate(2026, 4, 27),
  LocalDate(2026, 5, 27),
  LocalDate(2026, 6, 26),
];

/// Five 28-day episodes ending 2026-07-05: estimate 2026-08-02, today is 28
/// days past → more than the 2-day grace → late.
final List<LocalDate> kLateStarts = [
  LocalDate(2026, 3, 15),
  LocalDate(2026, 4, 12),
  LocalDate(2026, 5, 10),
  LocalDate(2026, 6, 7),
  LocalDate(2026, 7, 5),
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
  Widget appFor(
    Profile profile, {
    NotificationAvailability availability = NotificationAvailability.available,
    RequestNotificationPermissionCallback? requestPermission,
    LocalDate? today,
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
        ChangeNotifierProvider(
          create: (_) => ProfileController(
            profilesRepository: profiles,
            settingsStore: _settings,
          )..load(),
        ),
      ],
      child: MaterialApp(
        home: ProfileDetailScreen(
          profile: profile,
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
  Future<void> Function(DriftDayEntriesRepository entries, String profileId)?
      seed,
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
  final harness =
      Harness(db, profile, profiles, entries, settings);
  await tester.pumpWidget(harness.appFor(
    profile,
    availability: availability,
    requestPermission: requestPermission,
    today: today,
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
          reason: 'the estimate card and the history stats each carry it '
              '(R17; issue #132 AC8)');
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

      // Issue #132: the cycle-history card now renders below the estimate
      // card for every profile with episodes, and it legitimately shows
      // recorded dates and lengths (real history, not a partial estimate).
      // The no-partial-numbers rule (R11) governs the estimate surface, so
      // the sweep is scoped to the not-enough card itself.
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

    testWidgets('paused state (>60-day open cycle) shows awaiting next '
        'period and no estimate', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );

      expect(find.text('Awaiting next period'), findsOneWidget);
      expect(find.text('Predictions are paused until the next period is '
          'logged.'), findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.textContaining('Next period estimate'), findsNothing);
      // Issue #132 (AC7): the paused state still resolves through the
      // resolver — "log it" is right there.
      expect(find.byKey(const ValueKey('late-resolver')), findsOneWidget);
      expect(find.text('Log it'), findsOneWidget);
      expect(find.text(kDisclaimer), findsWidgets,
          reason: 'the awaiting card, resolver, and history stats each '
              'carry it');
      expectNoFertilityVocabulary(tester, 'paused awaiting next period');
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
      expect(find.text('Period is late'), findsOneWidget);
      expect(find.text('Log it'), findsOneWidget);
      expect(find.text('Skip this cycle'), findsOneWidget);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.text('Next period estimate: August 2, 2026'), findsOneWidget,
          reason: 'the estimate itself stays visible with its disclaimer');
      expect(find.text(kDisclaimer), findsWidgets,
          reason: 'the estimate card and the resolver each carry it');
      expectNoFertilityVocabulary(tester, 'late');
      await disposeOverview(tester, h);
    });

    testWidgets('mid-cycle phase reads "Cycle day N" and never "Period"',
        (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kActiveStarts),
      );

      expect(find.byKey(const ValueKey('overview-phase')),
          findsOneWidget);
      expect(find.text('Cycle day 26'), findsOneWidget);
      expect(find.text('Period'), findsNothing,
          reason: 'today is outside every episode');
      expectNoFertilityVocabulary(tester, 'mid-cycle phase');
      await disposeOverview(tester, h);
    });

    testWidgets('during an episode the phase reads "Period" and no cycle-day '
        'count shows', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kDuringEpisodeStarts),
      );

      expect(find.text('Period'), findsOneWidget);
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
      expect(find.text('Period'), findsOneWidget,
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

      final paused = await pumpOverview(
        tester,
        mode: ProfileMode.teen,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.text('Waiting for your next period'), findsOneWidget);
      expect(find.textContaining('Predictions are paused'), findsNothing);
      await disposeOverview(tester, paused);
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
      expect(find.text('Your next period is estimated around: August 2, 2026'),
          findsOneWidget);
      await disposeOverview(tester, h);
    });

    testWidgets('caregiver mode rewords the awaiting copy', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.caregiver,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.text('Awaiting next period'), findsOneWidget);
      expect(
        find.textContaining('until a period is logged for this profile'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-awaiting')),
          matching: find.text(kDisclaimer),
        ),
        findsWidgets,
        reason: 'the awaiting card carries it, and the resolver the paused '
            'state still shows carries its own copy',
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
      expect(find.text('Next period may start around: August 2, 2026'),
          findsOneWidget);
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

    testWidgets('irregular mode silences the resolver in the paused state '
        'too, keeping the disclaimer', (tester) async {
      final h = await pumpOverview(
        tester,
        mode: ProfileMode.irregular,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kPausedStarts),
      );
      expect(find.byKey(const ValueKey('late-resolver')), findsNothing);
      expect(find.byKey(const ValueKey('overview-irregular-overdue')),
          findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('overview-awaiting')),
          matching: find.text(kDisclaimer),
        ),
        findsOneWidget,
      );
      await disposeOverview(tester, h);
    });
  });
}
