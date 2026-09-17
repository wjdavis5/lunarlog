/// Widget and pure-function tests for `ProfileCard` (issue #241, B-15):
/// the deterministic-hue avatar, the one-line cycle status mapped from
/// every [CyclePrediction] state, and the card's rendering with and
/// without a prediction service. The #126 badge assembly is covered by
/// `test/ui/sharing_discoverability_test.dart` (its keys are mirrored
/// here on purpose); the picker-level row is covered by
/// `test/ui/profile_quick_switcher_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/profile_card.dart';

/// Fixed "today" so cycle-day numbers are deterministic (the shape
/// `test/ui/calendar_navigation_test.dart` uses).
final LocalDate kToday = LocalDate(2026, 9, 10);

/// A [DayEntriesRepository] whose `watchForProfile` emits one fixed list
/// -- exactly what [CyclePredictionService.watch] reads from it; every
/// other member fails loudly if ever called (the
/// `prediction_service_test.dart` stub shape).
class _StubDayEntries implements DayEntriesRepository {
  _StubDayEntries(this.entries);

  final List<DayEntry> entries;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      Stream.value(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DayEntry _bleed(String profileId, LocalDate date) => DayEntry(
      id: 'e-$profileId-${date.iso}',
      profileId: profileId,
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 9, 1),
    );

/// Four-day bleed episodes starting on each of [starts] (28-day gaps make
/// every completed cycle valid, so the service resolves an
/// [ActivePrediction]).
List<DayEntry> _episodes(String profileId, List<LocalDate> starts) => [
      for (final start in starts)
        for (var i = 0; i < 4; i++) _bleed(profileId, start.addDays(i)),
    ];

/// Enough completed valid cycles for an [ActivePrediction], with the
/// open cycle a month old: cycle day 28, not during an episode.
final List<LocalDate> kSettledStarts = [
  LocalDate(2026, 5, 22),
  LocalDate(2026, 6, 19),
  LocalDate(2026, 7, 17),
  LocalDate(2026, 8, 14),
];

Profile _profile() => Profile(
      id: 'p-card-1',
      displayName: 'Alice',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Future<void> pumpCard(
  WidgetTester tester, {
  required DayEntriesRepository entries,
  CyclePredictionService? service,
  Widget? trailing,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ListView(
          children: [
            ProfileCard(
              profile: _profile(),
              info: const SharingProfileInfo.unknown(),
              predictionService: service,
              todayProvider: () => kToday,
              subtitle: 'Created 2026-01-01 00:00',
              trailing: trailing,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

CyclePredictionService _service(_StubDayEntries entries) =>
    CyclePredictionService(entries);

void main() {
  group('profileAvatarHue / profileAvatarColor (pure, issue #241)', () {
    test('hue is deterministic and in [0, 360)', () {
      final first = profileAvatarHue('p-card-1');
      expect(first, profileAvatarHue('p-card-1'),
          reason: 'same id must always hash to the same hue');
      expect(first, inInclusiveRange(0, 359));
    });

    test('different ids land on different hues somewhere', () {
      // Not injective over all inputs (360 buckets), but across a
      // handful of ids at least two must differ, or every profile would
      // render the same colour and the avatar would identify nothing.
      final hues = {
        for (var i = 0; i < 8; i++) profileAvatarHue('profile-$i'),
      };
      expect(hues.length, greaterThan(1));
    });

    test('the colour pair is brightness-aware (dark mode, #727/#714)', () {
      const id = 'p-card-1';
      final light = profileAvatarColor(id, Brightness.light);
      final dark = profileAvatarColor(id, Brightness.dark);
      expect(light, isNot(dark));
      // Both stay saturated enough to separate from their own surface.
      final hslLight = HSLColor.fromColor(light);
      final hslDark = HSLColor.fromColor(dark);
      expect(hslLight.saturation, greaterThan(0.3));
      expect(hslDark.lightness, greaterThan(hslLight.lightness),
          reason: 'the dark-theme disc must be the lighter tone');
    });
  });

  group('profileCycleStatus (pure, issue #241)', () {
    final l10n = lookupAppLocalizations(const Locale('en'));

    ActivePrediction active({required bool duringEpisode}) =>
        ActivePrediction(
          today: kToday,
          lastEpisodeStart: LocalDate(2026, 8, 14),
          estimatedNextStart: LocalDate(2026, 9, 11),
          originalEstimatedNextStart: LocalDate(2026, 9, 11),
          averagedCycleLengths: const [28, 28, 28],
          meanCycleLengthDays: 28,
          cycleDay: duringEpisode ? 2 : 28,
          duringEpisode: duringEpisode,
          completedCycleCount: 3,
          validCycleCount: 3,
        );

    test('null prediction (first emission not landed) renders no status',
        () {
      expect(profileCycleStatus(prediction: null, l10n: l10n), isNull);
    });

    test('an active mid-cycle prediction reads "Cycle day N"', () {
      expect(
        profileCycleStatus(
            prediction: active(duringEpisode: false), l10n: l10n),
        'Cycle day 28',
      );
    });

    test('a prediction during a logged bleed reads "Period, day N"', () {
      expect(
        profileCycleStatus(
            prediction: active(duringEpisode: true), l10n: l10n),
        'Period, day 2',
      );
    });

    test('NotEnoughHistory reads "No history yet"', () {
      expect(
        profileCycleStatus(
          prediction: const NotEnoughHistory(
              episodeCount: 0, completedCycleCount: 0, validCycleCount: 0),
          l10n: l10n,
        ),
        'No history yet',
      );
    });

    test('PredictionsSuppressed and PredictionsDisabled read as off', () {
      expect(
        profileCycleStatus(
          prediction:
              PredictionsSuppressed(method: BirthControlMethod.pill),
          l10n: l10n,
        ),
        'Period predictions off',
      );
      expect(
        profileCycleStatus(
            prediction: const PredictionsDisabled(), l10n: l10n),
        'Period predictions off',
      );
    });
  });

  group('ProfileCard rendering (issue #241)', () {
    testWidgets('renders avatar, name, cycle-day status, and the '
        'created-date secondary line', (tester) async {
      final entries = _StubDayEntries(_episodes('p-card-1', kSettledStarts));
      await pumpCard(tester, entries: entries, service: _service(entries));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.byKey(const ValueKey('profile-avatar-p-card-1')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('profile-cycle-status-p-card-1')),
          findsOneWidget);
      expect(find.text('Cycle day 28'), findsOneWidget);
      expect(find.textContaining('Created'), findsOneWidget);
    });

    testWidgets('during a logged bleed the status reads "Period, day 2"',
        (tester) async {
      // The settled history plus an episode that started yesterday and
      // runs through today.
      final entries = _StubDayEntries(_episodes(
        'p-card-1',
        [...kSettledStarts, LocalDate(2026, 9, 9)],
      ));
      await pumpCard(tester, entries: entries, service: _service(entries));

      expect(find.text('Period, day 2'), findsOneWidget);
    });

    testWidgets('a profile with no entries reads "No history yet"',
        (tester) async {
      final entries = _StubDayEntries(const []);
      await pumpCard(tester, entries: entries, service: _service(entries));

      expect(find.text('No history yet'), findsOneWidget);
    });

    testWidgets('no prediction service: no status line, subtitle only',
        (tester) async {
      await pumpCard(tester, entries: _StubDayEntries(const []));

      expect(
          find.byKey(const ValueKey('profile-cycle-status-p-card-1')),
          findsNothing,
          reason: 'never a guessed status for a profile that was never '
              'asked about');
      expect(find.text('No history yet'), findsNothing);
      expect(find.textContaining('Created'), findsOneWidget);
    });

    testWidgets('the caller\'s trailing control (the overflow menu) renders',
        (tester) async {
      final entries = _StubDayEntries(_episodes('p-card-1', kSettledStarts));
      await pumpCard(
        tester,
        entries: entries,
        service: _service(entries),
        trailing: PopupMenuButton<String>(
          tooltip: 'Profile actions',
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
          ],
        ),
      );

      await tester.tap(find.byTooltip('Profile actions'));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
    });
  });
}
