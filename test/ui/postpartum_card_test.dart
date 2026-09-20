/// Issue #455 (Postpartum mode): the Postpartum-mode Cycle View surfaces —
/// the day-count card itself, its mount in [OverviewPanel] while the
/// profile's life-stage mode is `postpartum` (with the prediction-
/// suppression explanation still rendered beneath it, #528), and the
/// cycles-have-returned offer once a bleed has been logged.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';
import 'package:lunarlog/domain/onboarding/onboarding_cycle_answers.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/cycle_overrides_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/components/postpartum_card.dart';
import 'package:lunarlog/ui/overview/notification_permission_state.dart';
import 'package:lunarlog/ui/overview/overview_panel.dart';
import 'package:provider/provider.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// A day-entries stub whose `watchForProfile` yields one event (all
/// `combineLatest` needs) and whose `listForProfile` backs the exit
/// offer's bleed-date read.
class _StubDayEntriesRepository implements DayEntriesRepository {
  _StubDayEntriesRepository(this.entries);

  final List<DayEntry> entries;

  @override
  Stream<List<DayEntry>> watchForProfile(String profileId,
          {LocalDate? from, LocalDate? to}) async* {
    yield entries;
  }

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => entries;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeModesRepository implements ProfileModesRepository {
  _FakeModesRepository(this.row);

  ProfileLifecycleMode? row;

  @override
  Future<ProfileLifecycleMode?> find(String profileId) async => row;

  @override
  Stream<ProfileLifecycleMode?> watch(String profileId) => Stream.value(row);

  @override
  Future<void> save({
    required String profileId,
    required LifecycleMode mode,
    String? modeStartedOn,
    String? estimatedDueDate,
    String? postpartumBirthDate,
    String? birthControlMethod,
  }) async {}
}

class _RecordingAnswersRecorder implements OnboardingCycleAnswersRecorder {
  final List<OnboardingCycleAnswers> recorded = [];

  @override
  Future<void> record(String profileId, OnboardingCycleAnswers answers) async {
    recorded.add(answers);
  }
}

class _RecordingOverrides implements CycleOverridesRepository {
  final List<(String, String)> writes = [];

  @override
  Future<void> setExcludedFromAverage({
    required String profileId,
    required String cycleStartDate,
    required bool excluded,
  }) async {
    if (excluded) writes.add((profileId, cycleStartDate));
  }

  @override
  Future<List<CycleOverride>> listForProfile(String profileId) async => [];

  @override
  Future<Set<String>> excludedCycleStarts(String profileId) async => {};

  @override
  Stream<Set<String>> watchExcludedCycleStarts(String profileId) =>
      Stream.value({});

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubSettingsStore implements SettingsStore {
  @override
  Stream<String?> watch(String key) => Stream.value(null);
  @override
  Future<String?> get(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<DayEntry> _bleedEntries(List<LocalDate> dates) => [
      for (final date in dates)
        DayEntry(
          id: 'entry-${date.iso}',
          profileId: 'p',
          localDate: date,
          tz: 'UTC',
          flow: FlowLevel.medium,
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
    ];

Widget _app({
  required Widget child,
  required _FakeModesRepository modes,
  required DayEntriesRepository entries,
  OnboardingCycleAnswersRecorder? recorder,
  CycleOverridesRepository? overrides,
}) {
  final settings = _StubSettingsStore();
  return MultiProvider(
    providers: [
      Provider<DayEntriesRepository>.value(value: entries),
      Provider<SettingsStore>.value(value: settings),
      Provider<CyclePredictionService>.value(
        value: CyclePredictionService(
          entries,
          settings: settings,
          lifecycleModeFor: (_) =>
              Stream.value(modes.row?.mode ?? LifecycleMode.tracking),
        ),
      ),
      Provider<CycleExclusionList>.value(
        value: CycleExclusionList(settings, overrides: overrides),
      ),
      Provider<ProfileModesRepository>.value(value: modes),
      if (recorder != null)
        Provider<OnboardingCycleAnswersRecorder>.value(value: recorder),
      ChangeNotifierProvider(
        create: (_) => NotificationPermissionState(
          NotificationAvailability.available,
        ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

ProfileLifecycleMode _postpartumRow({
  String? startedOn = '2026-01-24',
  String? birthDate,
}) =>
    (
      mode: LifecycleMode.postpartum,
      modeStartedOn: startedOn,
      estimatedDueDate: null,
      postpartumBirthDate: birthDate,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    );

void main() {
  testWidgets('PostpartumCard renders the day count', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PostpartumCard(daysSinceStart: 12)),
    ));
    expect(find.byKey(const ValueKey('postpartum-day')), findsOneWidget);
    expect(find.text('Day 12 of postpartum'), findsOneWidget);
    expect(find.byKey(const ValueKey('postpartum-start-missing')), findsNothing);
  });

  testWidgets('Issue #861: a birth-date count says "since birth", never '
      '"of postpartum"', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: PostpartumCard(daysSinceStart: 12, sinceBirth: true),
      ),
    ));
    expect(find.text('Day 12 since birth'), findsOneWidget);
    expect(find.text('Day 12 of postpartum'), findsNothing);
  });

  testWidgets('PostpartumCard with no start renders the honest '
      'not-recorded line, never a fabricated day count', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: PostpartumCard()),
    ));
    expect(
      find.byKey(const ValueKey('postpartum-start-missing')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('postpartum-day')), findsNothing);
  });

  testWidgets('PostpartumCard renders the return offer and invokes the '
      'switch callback', (tester) async {
    var switched = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PostpartumCard(
          daysSinceStart: 30,
          showReturnOffer: true,
          onSwitchToTracking: () => switched = true,
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('postpartum-return-offer')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('postpartum-return-action')));
    await tester.pump();
    expect(switched, isTrue);
  });

  testWidgets('PostpartumCard never renders the offer while no start is '
      'recorded, and omits the action for a read-only caller',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PostpartumCard(
          showReturnOffer: true,
          onSwitchToTracking: () {},
        ),
      ),
    ));
    expect(
      find.byKey(const ValueKey('postpartum-return-offer')),
      findsNothing,
    );

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PostpartumCard(
          daysSinceStart: 30,
          showReturnOffer: true,
          canSwitch: false,
          onSwitchToTracking: () {},
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('postpartum-return-offer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('postpartum-return-action')), findsNothing);
  });

  testWidgets('OverviewPanel mounts the day card above the suppression '
      'explanation while in Postpartum mode', (tester) async {
    final modes = _FakeModesRepository(_postpartumRow());
    await tester.pumpWidget(_app(
      modes: modes,
      entries: _StubDayEntriesRepository(const []),
      child: OverviewPanel(
        profileId: 'p',
        // 2026-03-25 is 60 days after the 2026-01-24 start.
        todayProvider: () => d(2026, 3, 25),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('postpartum-card')), findsOneWidget);
    expect(find.text('Day 60 of postpartum'), findsOneWidget);
    // #528's suppression explanation stays visible beneath the counter.
    expect(find.byKey(const ValueKey('predictions-suppressed')),
        findsOneWidget);
    // No bleed logged: no cycles-have-returned offer yet.
    expect(find.byKey(const ValueKey('postpartum-return-offer')), findsNothing);
  });

  testWidgets('Issue #861: a supplied birth date moves the count and the '
      'copy to "since birth"', (tester) async {
    final modes = _FakeModesRepository(
      _postpartumRow(startedOn: '2026-01-24', birthDate: '2026-01-01'),
    );
    await tester.pumpWidget(_app(
      modes: modes,
      entries: _StubDayEntriesRepository(const []),
      child: OverviewPanel(
        profileId: 'p',
        // 2026-03-25 is 83 days after the 2026-01-01 birth (and only 60
        // after the 2026-01-24 mode start) — the count must use the birth.
        todayProvider: () => d(2026, 3, 25),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Day 83 since birth'), findsOneWidget);
    expect(find.text('Day 60 of postpartum'), findsNothing);
  });

  testWidgets('Issue #861: no birth date keeps the mode-start count and '
      'the "of postpartum" copy', (tester) async {
    final modes = _FakeModesRepository(_postpartumRow());
    await tester.pumpWidget(_app(
      modes: modes,
      entries: _StubDayEntriesRepository(const []),
      child: OverviewPanel(
        profileId: 'p',
        todayProvider: () => d(2026, 3, 25),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Day 60 of postpartum'), findsOneWidget);
    expect(find.textContaining('since birth'), findsNothing);
  });

  testWidgets('OverviewPanel outside Postpartum mode renders no day card',
      (tester) async {
    final modes = _FakeModesRepository((
      mode: LifecycleMode.tracking,
      modeStartedOn: null,
      estimatedDueDate: null,
      postpartumBirthDate: null,
      birthControlMethod: null,
      birthControlStartedOn: null,
      birthControlStoppedOn: null,
    ));
    await tester.pumpWidget(_app(
      modes: modes,
      entries: _StubDayEntriesRepository(const []),
      child: OverviewPanel(
        profileId: 'p',
        todayProvider: () => d(2026, 3, 25),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('postpartum-card')), findsNothing);
  });

  testWidgets('OverviewPanel offers cycles-have-returned once a bleed is '
      'logged during the interval, and the action switches the mode then '
      'offers the interval exclusion', (tester) async {
    final modes = _FakeModesRepository(_postpartumRow());
    final recorder = _RecordingAnswersRecorder();
    final overrides = _RecordingOverrides();
    // The pre-birth period plus a bleed logged after the mode started.
    final entries = _bleedEntries([d(2026, 1, 1), d(2026, 2, 20)]);
    await tester.pumpWidget(_app(
      modes: modes,
      entries: _StubDayEntriesRepository(entries),
      recorder: recorder,
      overrides: overrides,
      child: OverviewPanel(
        profileId: 'p',
        todayProvider: () => d(2026, 3, 25),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('postpartum-return-offer')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('postpartum-return-action')));
    await tester.pumpAndSettle();

    // The switch went through the onboarding recorder, preserving the
    // birth-control answer, and nominated Period Tracking.
    expect(recorder.recorded, hasLength(1));
    expect(recorder.recorded.single.lifecycleMode, LifecycleMode.tracking);
    // The exit exclusion offer then appeared against the postpartum
    // interval, and accepting it wrote the in-interval start.
    await tester
        .tap(find.byKey(const ValueKey('postpartum-exit-exclusion-accept')));
    await tester.pumpAndSettle();
    expect(overrides.writes, [('p', '2026-02-20')]);
  });
}
