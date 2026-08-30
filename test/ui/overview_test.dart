/// Widget tests for U6: the overview panel — AE3 (active estimate + phase,
/// no fertility vocabulary in any state), not-enough/paused/late states,
/// estimate framing (R17), cycle-day counting, profile switching, the
/// reminder-hint seam, and stream-driven refresh (F4 in-app).
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
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/overview/notification_availability.dart';
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
  }) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<DayEntriesRepository>.value(value: entries),
        Provider<SettingsStore>.value(value: _settings),
        Provider<CyclePredictionService>.value(
          value: CyclePredictionService(entries),
        ),
        Provider<NotificationAvailability>.value(value: availability),
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
          todayProvider: () => kToday,
        ),
      ),
    );
  }
}

Future<Harness> pumpOverview(
  WidgetTester tester, {
  NotificationAvailability availability = NotificationAvailability.available,
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
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) {
    await seed(entries, profile.id);
  }
  final harness =
      Harness(db, profile, profiles, entries, settings);
  await tester.pumpWidget(harness.appFor(profile, availability: availability));
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
      expect(find.byKey(const ValueKey('overview-late')), findsNothing,
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

      expect(find.text(kDisclaimer), findsOneWidget,
          reason: 'disclaimer sits next to the estimate (R17)');
      await disposeOverview(tester, h);
    });

    testWidgets('below-threshold profile shows the not-enough state with no '
        'partial numbers (no digits or dates leak)', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kNotEnoughStarts),
      );

      expect(find.text('Not enough history yet'), findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.textContaining('Next period estimate'), findsNothing);
      expect(find.byKey(const ValueKey('overview-late')), findsNothing);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .where((text) => text.isNotEmpty)
          .toList();
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
      expect(find.byKey(const ValueKey('overview-late')), findsNothing);
      expectNoFertilityVocabulary(tester, 'paused awaiting next period');
      await disposeOverview(tester, h);
    });

    testWidgets('late state (estimate + 2 days passed, nothing logged) shows '
        'the late indicator instead of the days-until line', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );

      expect(find.byKey(const ValueKey('overview-late')), findsOneWidget);
      expect(find.text('Period is late — log it when it starts'),
          findsOneWidget);
      expect(find.textContaining('days until next period'), findsNothing);
      expect(find.text('Next period estimate: August 2, 2026'), findsOneWidget,
          reason: 'the estimate itself stays visible with its disclaimer');
      expect(find.text(kDisclaimer), findsOneWidget);
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

    testWidgets('logging a period through the repository refreshes the '
        'overview via the stream (late state clears)', (tester) async {
      final h = await pumpOverview(
        tester,
        seed: (entries, profileId) =>
            seedEpisodes(entries, profileId, kLateStarts),
      );

      expect(find.byKey(const ValueKey('overview-late')), findsOneWidget);

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

      expect(find.byKey(const ValueKey('overview-late')), findsNothing,
          reason: 'the new episode resets the open cycle');
      expect(find.text('Period'), findsOneWidget,
          reason: 'today is now day 1 of the new episode');
      expect(find.text('≈37 days until next period'), findsOneWidget,
          reason: 'mean of [28, 28, 56] rounds to 37 from 2026-08-30');
      await disposeOverview(tester, h);
    });
  });
}
