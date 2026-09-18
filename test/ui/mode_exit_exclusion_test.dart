/// Issues #192 (Pregnancy) and #455 (Postpartum): the mode-exit exclusion
/// offer — the dialog shown when leaving a discrete-interval life-stage
/// mode, the `cycle_overrides` writes an acceptance performs, and the
/// nothing-written decline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/cycle_override.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/repositories/cycle_overrides_repository.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/mode_exit_exclusion.dart';
import 'package:provider/provider.dart';

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
  final Map<String, String?> _values = {};
  @override
  Future<String?> get(String key) async => _values[key];
  @override
  Future<void> set(String key, String? value) async {
    _values[key] = value;
  }

  @override
  Stream<String?> watch(String key) => Stream.value(_values[key]);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Enough of a day-entries repository for the tree wrapper: returns the
/// same pregnancy-shaped bleed history the pure tests use (the
/// pregnancy-long period, one mid-pregnancy breakthrough episode, and the
/// exit-day period).
class _StubDayEntriesRepository implements DayEntriesRepository {
  @override
  Future<List<DayEntry>> listForProfile(String profileId) async => [
          for (final date in kPastPregnancyBleedDates)
            DayEntry(
              id: 'entry-${date.iso}',
              profileId: profileId,
              localDate: date,
              tz: 'UTC',
              flow: FlowLevel.medium,
              updatedAt: DateTime.utc(2025, 1, 1),
            ),
        ];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<LocalDate> get kPregnancyBleedDates => [
      LocalDate(2026, 1, 1),
      LocalDate(2026, 1, 24), // the pregnancy "cycle" starts here
      LocalDate(2026, 3, 15), // mid-pregnancy breakthrough episode
      LocalDate(2026, 10, 30), // exit-day period: the first real cycle
    ];

/// The tree-wrapper test's dates: unlike [kPregnancyBleedDates] (whose
/// exit-day period the pure tests pin against an explicit `exitedOn`),
/// the wrapper derives `exitedOn` from the REAL clock's today, so these
/// must be unambiguously in the past whenever the suite runs — no
/// boundary date, just the two in-interval episodes plus the
/// pre-pregnancy one.
List<LocalDate> get kPastPregnancyBleedDates => [
      LocalDate(2025, 1, 1),
      LocalDate(2025, 1, 24), // the pregnancy "cycle" starts here
      LocalDate(2025, 3, 15), // mid-pregnancy breakthrough episode
    ];

/// A postpartum-shaped history: the last pre-birth period, then lochia and
/// spotting logged after the mode started, and the exit-day period.
List<LocalDate> get kPostpartumBleedDates => [
      LocalDate(2026, 1, 1),
      LocalDate(2026, 1, 24), // postpartum mode starts here
      LocalDate(2026, 2, 20), // lochia/spotting episode
      LocalDate(2026, 10, 30), // exit-day period: the first real cycle
    ];

Widget _host(Widget child) => MultiProvider(
      providers: [
        Provider<CycleExclusionList>.value(
          value: CycleExclusionList(_StubSettingsStore()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

void main() {
  for (final (mode, dates, acceptKey) in [
    (
      LifecycleMode.pregnancy,
      kPregnancyBleedDates,
      'pregnancy-exit-exclusion-accept',
    ),
    (
      LifecycleMode.postpartum,
      kPostpartumBleedDates,
      'postpartum-exit-exclusion-accept',
    ),
  ]) {
    testWidgets('${mode.name}: accepting writes one exclusion per cycle '
        'start inside the interval — never the exit-day period',
        (tester) async {
      final overrides = _RecordingOverrides();
      final exclusions = CycleExclusionList(
        _StubSettingsStore(),
        overrides: overrides,
      );
      var offered = false;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final outcome = await offerModeExitExclusion(
              context,
              exitedMode: mode,
              modeStartedOn: '2026-01-24',
              exitedOn: LocalDate(2026, 10, 30),
              bleedDates: dates,
              exclusions: exclusions,
              profileId: 'p1',
              readOnly: false,
            );
            offered = outcome.accepted;
          },
          child: const Text('offer'),
        ),
      )));
      await tester.tap(find.text('offer'));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey(acceptKey)), findsOneWidget);
      await tester.tap(find.byKey(ValueKey(acceptKey)));
      await tester.pumpAndSettle();
      expect(offered, isTrue);
      // The in-interval start(s) are excluded; 2026-10-30 (the exit-day
      // period, the first real cycle after the mode) is not.
      expect(
        overrides.writes,
        [
          ('p1', '2026-01-24'),
          if (mode == LifecycleMode.postpartum)
            ('p1', '2026-02-20')
          else
            ('p1', '2026-03-15'),
        ],
      );
    });

    testWidgets('${mode.name}: declining writes nothing — the cycles stay '
        'excludable later', (tester) async {
      final overrides = _RecordingOverrides();
      final exclusions = CycleExclusionList(
        _StubSettingsStore(),
        overrides: overrides,
      );
      var offered = false;
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            final outcome = await offerModeExitExclusion(
              context,
              exitedMode: mode,
              modeStartedOn: '2026-01-24',
              exitedOn: LocalDate(2026, 10, 30),
              bleedDates: dates,
              exclusions: exclusions,
              profileId: 'p1',
              readOnly: false,
            );
            offered = outcome.accepted;
          },
          child: const Text('offer'),
        ),
      )));
      await tester.tap(find.text('offer'));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(ValueKey('${mode.toDb()}-exit-exclusion-decline')));
      await tester.pumpAndSettle();
      expect(offered, isFalse);
      expect(overrides.writes, isEmpty);
    });
  }

  testWidgets('an unstamped pregnancy offers nothing (no honest interval '
      'to exclude)', (tester) async {
    final overrides = _RecordingOverrides();
    final exclusions = CycleExclusionList(
      _StubSettingsStore(),
      overrides: overrides,
    );
    var offered = 'unset';
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final outcome = await offerModeExitExclusion(
            context,
            exitedMode: LifecycleMode.pregnancy,
            modeStartedOn: null,
            exitedOn: LocalDate(2026, 10, 30),
            bleedDates: kPregnancyBleedDates,
            exclusions: exclusions,
            profileId: 'p1',
            readOnly: false,
          );
          offered = outcome.accepted ? 'accepted' : 'declined';
        },
        child: const Text('offer'),
      ),
    )));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(offered, 'declined');
    expect(find.byKey(const ValueKey('pregnancy-exit-exclusion-accept')),
        findsNothing);
    expect(overrides.writes, isEmpty);
  });

  testWidgets('a read-only caller never sees the offer or performs writes',
      (tester) async {
    final overrides = _RecordingOverrides();
    final exclusions = CycleExclusionList(
      _StubSettingsStore(),
      overrides: overrides,
    );
    var offered = 'unset';
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final outcome = await offerModeExitExclusion(
            context,
            exitedMode: LifecycleMode.postpartum,
            modeStartedOn: '2026-01-24',
            exitedOn: LocalDate(2026, 10, 30),
            bleedDates: kPostpartumBleedDates,
            exclusions: exclusions,
            profileId: 'p1',
            readOnly: true,
          );
          offered = outcome.accepted ? 'accepted' : 'declined';
        },
        child: const Text('offer'),
      ),
    )));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(offered, 'declined');
    expect(find.byKey(const ValueKey('postpartum-exit-exclusion-accept')),
        findsNothing);
    expect(overrides.writes, isEmpty);
  });

  testWidgets('a mode with no discrete interval (tracking) offers nothing',
      (tester) async {
    final overrides = _RecordingOverrides();
    final exclusions = CycleExclusionList(
      _StubSettingsStore(),
      overrides: overrides,
    );
    var offered = 'unset';
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          final outcome = await offerModeExitExclusion(
            context,
            exitedMode: LifecycleMode.tracking,
            modeStartedOn: '2026-01-24',
            exitedOn: LocalDate(2026, 10, 30),
            bleedDates: kPostpartumBleedDates,
            exclusions: exclusions,
            profileId: 'p1',
            readOnly: false,
          );
          offered = outcome.accepted ? 'accepted' : 'declined';
        },
        child: const Text('offer'),
      ),
    )));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(offered, 'declined');
    expect(find.byType(AlertDialog), findsNothing);
    expect(overrides.writes, isEmpty);
  });

  testWidgets('the tree wrapper writes and surfaces the snackbar on '
      'accept, and skips the offer entirely on an empty interval',
      (tester) async {
    final overrides = _RecordingOverrides();
    final exclusions = CycleExclusionList(
      _StubSettingsStore(),
      overrides: overrides,
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<CycleExclusionList>.value(value: exclusions),
        Provider<DayEntriesRepository>.value(
          value: _StubDayEntriesRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => offerModeExitExclusionFromTree(
                context,
                exitedMode: LifecycleMode.pregnancy,
                profileId: 'p1',
                modeStartedOn: '2025-01-24',
              ),
              child: const Text('offer'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('pregnancy-exit-exclusion-accept')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('pregnancy-exit-exclusion-snackbar')),
        findsOneWidget);
    expect(overrides.writes, [('p1', '2025-01-24'), ('p1', '2025-03-15')]);
  });

  testWidgets('the tree wrapper never offers when no seam is wired (the '
      'exact pre-#192 behavior)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => offerModeExitExclusionFromTree(
              context,
              exitedMode: LifecycleMode.postpartum,
              profileId: 'p1',
              modeStartedOn: '2026-01-24',
            ),
            child: const Text('offer'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('offer'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('postpartum-exit-exclusion-accept')),
        findsNothing);
  });
}
