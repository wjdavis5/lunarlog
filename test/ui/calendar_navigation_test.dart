/// Widget tests for issue #191: flow-graded calendar cells, the legend
/// strip, swipe navigation (shared with the chevrons and the Today
/// button), the month/year picker, and the weekday-header/grid alignment
/// fix.
///
/// Deliberately its own file rather than an addition to the already large
/// `test/ui/logging_test.dart` (B-2, B-11) — these tests exercise
/// `MonthCalendar` directly against a minimal provider set instead of
/// going through `ProfileDetailScreen`, since none of this issue's
/// features touch attribution/guardians/care-mode wiring.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/prediction/cycle_history_service.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/logging/month_calendar.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:provider/provider.dart';

import '../support/erroring_day_entries_repository.dart';

/// Fixed "today" (same date `test/ui/logging_test.dart` uses) so month
/// defaults and the forward navigation limit are deterministic.
final LocalDate kToday = LocalDate(2026, 8, 30);

class Harness {
  Harness(this.db, this.profileId);
  final LunarLogDatabase db;
  final String profileId;
}

DayEntry _entryFor(String profileId, LocalDate date, FlowLevel flow) =>
    DayEntry(
      id: '',
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      flow: flow,
      tags: const [],
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Seeds a spotting observation (issue #761) on [date], creating the day
/// entry it hangs off [flow] (the day sheet's own `notBleeding` +
/// observation shape). Returns the entry so a test can seed a bleed level
/// or a legacy `flow = 'spotting'` row instead and still attach spotting.
Future<DayEntry> _seedSpotting(
  LunarLogDatabase db,
  String profileId,
  LocalDate date, {
  FlowLevel flow = FlowLevel.notBleeding,
}) async {
  final entry = await DriftDayEntriesRepository(db.storage).save(
    _entryFor(profileId, date, flow),
  );
  await DriftObservationsRepository(db.storage).save(
    Observation(
      id: '',
      dayEntryId: entry.id,
      profileId: profileId,
      localDate: date,
      tz: 'America/Chicago',
      category: 'spotting',
      code: 'spotting',
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  return entry;
}

/// Records every `watchForProfile` call's `from`/`to` while delegating
/// everything else to a real [DriftDayEntriesRepository] (issue #197): lets
/// a widget test assert exactly which window `MonthCalendar` subscribed to,
/// and how many times, without faking storage itself.
class RecordingDayEntriesRepository implements DayEntriesRepository {
  RecordingDayEntriesRepository(this._inner);

  final DriftDayEntriesRepository _inner;
  final List<({LocalDate? from, LocalDate? to})> calls = [];

  @override
  Future<DayEntry> save(DayEntry entry) => _inner.save(entry);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) => _inner.saveDayEntryWithObservations(
    entry: entry,
    observationsToUpsert: observationsToUpsert,
    observationIdsToDelete: observationIdsToDelete,
  );

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      _inner.find(profileId, localDate);

  @override
  Future<List<DayEntry>> listForProfile(String profileId) =>
      _inner.listForProfile(profileId);

  @override
  Future<bool> hasAnyEntries(String profileId) =>
      _inner.hasAnyEntries(profileId);

  @override
  Stream<bool> watchHasAnyEntries(String profileId) =>
      _inner.watchHasAnyEntries(profileId);

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) {
    calls.add((from: from, to: to));
    return _inner.watchForProfile(profileId, from: from, to: to);
  }

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  // Issue #130: no merge-notice surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForDay(
          String profileId, LocalDate date) async =>
      const [];

  @override
  Future<void> dismissMergeEvent(String profileId, String eventId) async {}

  // Issue #130: no per-profile export surface in this fake.
  @override
  Future<List<mergelog.DayEntryMergeEvent>> mergeEventsForProfile(
          String profileId) async =>
      const [];
}

/// Issue #761: an observations repository that reports exactly
/// [spottingIsos] as live spotting observations — proves `MonthCalendar`'s
/// constructor seam is what drives the marker, not the ambient provider.
class FakeSpottingObservationsRepository implements ObservationsRepository {
  FakeSpottingObservationsRepository(this.spottingIsos);

  final Set<String> spottingIsos;

  @override
  Future<List<Observation>> listForProfile(String profileId) async => [
        for (final iso in spottingIsos)
          Observation(
            id: 'obs-$iso',
            dayEntryId: 'entry-$iso',
            profileId: profileId,
            localDate: LocalDate.fromIso(iso),
            tz: 'America/Chicago',
            category: 'spotting',
            code: 'spotting',
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
      ];

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
    String dayEntryId,
  ) async => const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

/// Issue #795: an observations repository that *does* implement the
/// date-scoped spotting capability, recording the window it is asked for —
/// proves `MonthCalendar` reads the windowed spotting set, not the
/// profile's full observation history.
class RecordingSpottingRangeRepository
    implements SpottingObservationsRangeRepository {
  final List<({LocalDate from, LocalDate to})> rangeCalls = [];
  int listForProfileCalls = 0;

  @override
  Future<List<Observation>> listSpottingObservationsInRange({
    required String profileId,
    required LocalDate from,
    required LocalDate to,
  }) async {
    rangeCalls.add((from: from, to: to));
    return const [];
  }

  @override
  Future<List<Observation>> listForProfile(String profileId) async {
    listForProfileCalls++;
    return const [];
  }

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async =>
      const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
    String dayEntryId,
  ) async => const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

Future<Harness> pumpCalendar(
  WidgetTester tester, {
  Future<void> Function(LunarLogDatabase db, String profileId)? seed,
  // Issue #137: the theme the harness mounts the calendar under —
  // `AppTheme.lightTheme` by default (every existing call site unchanged),
  // or `AppTheme.darkTheme` for the dark-mode suite, which needs the real
  // seeded scheme rather than a generic `ThemeData(brightness:)` so the
  // calendar's `LunarLogColors` derivation is the production one.
  // Nullable only because `AppTheme.lightTheme` is a memoized `static
  // final`, not a const, so it cannot be an optional parameter's default
  // value.
  ThemeData? theme,
  // Issue #312 (large-text budget): lets a single test override the text
  // scale MediaQuery reports, without touching every other call site.
  double textScale = 1.0,
  // Issue #312 (today-ring overflow / textScaleFactor overflow review):
  // most tests want a generously tall viewport that never itself risks an
  // overflow, but a couple deliberately need a real phone-class viewport
  // (390x844 logical, dpr 1) so a would-be overflow is the thing under
  // test rather than masked by a desktop-sized canvas.
  Size physicalSize = const Size(800, 1400),
  // Issue #197: lets a test observe the entries repository's
  // `watchForProfile` calls (window bounds, call count) by wrapping the
  // real `DriftDayEntriesRepository` in a `RecordingDayEntriesRepository`.
  DayEntriesRepository Function(DriftDayEntriesRepository real)? wrapRepository,
  // Issue #550: wires real CyclePredictionService/CycleHistoryService
  // providers (rather than leaving MonthCalendar on its no-service
  // computePredictionFromEntries/deriveCycleHistoryFromEntries fallback,
  // which recomputes a fresh, non-identical prediction/history object
  // every build). Needed only by tests that must observe a *stable*
  // ActivePrediction across an unrelated rebuild — the #550 memoisation
  // guard, so far.
  bool withPredictionServices = false,
  // Issue #761: mounts the calendar with an explicit `observationsRepository`
  // constructor seam instead of the ambient provider, proving the widget's
  // own injected seam — the same shape `RecordingDayEntriesRepository`
  // exercises for entries. Null keeps every other test on the provider path.
  ObservationsRepository? observationsRepository,
}) async {
  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final db = LunarLogDatabase(NativeDatabase.memory());
  final profiles = DriftProfilesRepository(db.storage);
  final profile = await profiles.create(displayName: 'Alice', isMinor: false);
  if (seed != null) await seed(db, profile.id);
  final entries = DriftDayEntriesRepository(db.storage);
  final repository = wrapRepository == null ? entries : wrapRepository(entries);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<DayEntriesRepository>.value(value: repository),
        // Issue #761: the spotting marker's data path — the repository
        // itself is always provided (mirroring `lib/app.dart`), so the
        // calendar's ambient fallback has something to resolve.
        Provider<ObservationsRepository>.value(
          value: observationsRepository ?? DriftObservationsRepository(db.storage),
        ),
        if (withPredictionServices) ...[
          Provider<CyclePredictionService?>.value(
            value: CyclePredictionService(repository),
          ),
          Provider<CycleHistoryService?>.value(
            value: CycleHistoryService(repository),
          ),
        ],
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: MonthCalendar(
            profileId: profile.id,
            todayProvider: () => kToday,
            observationsRepository: observationsRepository,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return Harness(db, profile.id);
}

Future<void> disposeCalendar(WidgetTester tester, Harness h) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 100));
  await h.db.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final colors = AppTheme.lightTheme.extension<LunarLogColors>()!;

  group('legend strip', () {
    testWidgets('keys every mark the grid can show: the four flow levels, a '
        'symptom day, today, #133\'s predicted band, the PMS/cramps '
        'badges, and the symptom-layer palette (issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      // Issue #810: the legend is reference material in the info sheet now,
      // opened from the month-nav row's info action.
      await tester.tap(find.byKey(const ValueKey('legend-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('calendar-legend')), findsOneWidget);
      for (final label in [
        // Issue #761: the observation-backed spotting ring is keyed again.
        'Spotting flow',
        'Light flow',
        'Medium flow',
        'Heavy flow',
        'Super heavy flow (5 marks)',
        'Symptom day',
        'Today',
        'Predicted day',
        'Cramps window',
        'Symptom layer dots',
      ]) {
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'missing legend entry: $label',
        );
      }
      // Issue #220: this harness pumps no prediction service, so no band
      // can exist here at all - the legend must not advertise the PMS
      // swatch when the grid can never show the badge (the positive case
      // lives in forecast_calendar_test.dart's band test, which runs the
      // full provider stack).
      expect(find.text('PMS window'), findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('issue #761: the legend keys spotting with the ring swatch, '
        'not a fill (it never counts as a bleed day)', (tester) async {
      final h = await pumpCalendar(tester);

      // Issue #810: open the info sheet to reach the legend entries.
      await tester.tap(find.byKey(const ValueKey('legend-toggle')));
      await tester.pumpAndSettle();

      final entry = find.byKey(const ValueKey('legend-spotting'));
      expect(entry, findsOneWidget);

      // The row's swatch is drawn as a ring (`_LegendSwatchStyle.ring`), so
      // its Container carries a border and no fill colour — the same shape
      // the grid's spotting cell uses. Asserting the decoration (not just
      // the label) pins the visual promise the legend makes.
      final swatch = tester.widget<Container>(
        find.descendant(of: entry, matching: find.byType(Container)).first,
      );
      final decoration = swatch.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.color, isNull);
      await disposeCalendar(tester, h);
    });

    testWidgets(
      'issue #810: the legend is collapsed by default at every text scale '
      'and reachable from the month-nav info action, which also works at a '
      'large text scale',
      (tester) async {
        for (final textScale in [1.0, 1.5, 1.6, 2.0, 3.0]) {
          final h = await pumpCalendar(tester, textScale: textScale);
          expect(find.byKey(const ValueKey('legend-toggle')), findsOneWidget);
          expect(
            find.text('Light flow'),
            findsNothing,
            reason: 'the legend is collapsed by default at $textScale x',
          );
          await tester.tap(find.byKey(const ValueKey('legend-toggle')));
          await tester.pumpAndSettle();
          expect(
            find.text('Light flow'),
            findsOneWidget,
            reason:
                'the info action must reach every legend entry at '
                '$textScale x',
          );
          await disposeCalendar(tester, h);
        }
      },
    );
  });

  group('flow-graded cells', () {
    testWidgets(
      'each bleed level fills with its own flow* ramp token and carries a '
      'distinct dot-count non-colour channel; superHeavy reuses heavy\'s '
      'ramp token with an extra mark',
      (tester) async {
        final h = await pumpCalendar(
          tester,
          seed: (db, profileId) async {
            final repo = DriftDayEntriesRepository(db.storage);
            await repo.save(
              _entryFor(profileId, LocalDate(2026, 8, 2), FlowLevel.light),
            );
            await repo.save(
              _entryFor(profileId, LocalDate(2026, 8, 3), FlowLevel.medium),
            );
            await repo.save(
              _entryFor(profileId, LocalDate(2026, 8, 4), FlowLevel.heavy),
            );
            await repo.save(
              _entryFor(profileId, LocalDate(2026, 8, 5), FlowLevel.superHeavy),
            );
          },
        );

        const expected = {
          'light': (iso: '2026-08-02', marks: 2),
          'medium': (iso: '2026-08-03', marks: 3),
          'heavy': (iso: '2026-08-04', marks: 4),
          'superHeavy': (iso: '2026-08-05', marks: 5),
        };

        for (final level in FlowLevel.values) {
          final entry = expected[level.name];
          // Issue #247: `none`, the deprecated `spotting` alias, and
          // `notBleeding` are never bleed levels — none of them render a
          // `bleed-<iso>` marker at all, so they are skipped here rather
          // than asserted against a date this test never seeded.
          if (entry == null) continue;
          final iso = entry.iso;

          final container = tester.widget<Container>(
            find.byKey(ValueKey('bleed-$iso')),
          );
          final decoration = container.decoration! as BoxDecoration;
          expect(decoration.border, isNull);
          expect(decoration.color, switch (level) {
            FlowLevel.light => colors.flowLight,
            FlowLevel.medium => colors.flowMedium,
            FlowLevel.heavy || FlowLevel.superHeavy => colors.flowHeavy,
            _ => throw StateError('unreachable'),
          }, reason: '$level should fill with its own flow* ramp token');

          final marksRow = tester.widget<Row>(
            find.byKey(ValueKey('flow-level-${level.name}-$iso')),
          );
          expect(
            marksRow.children.length,
            entry.marks,
            reason: '$level should carry ${entry.marks} intensity mark(s)',
          );
        }
        await disposeCalendar(tester, h);
      },
    );

    testWidgets('issue #761: a legacy `flow = spotting` row still renders the '
        'spotting marker (the repository synthesises the observation), while '
        'an explicit notBleeding assertion stays bare', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          // ignore: deprecated_member_use_from_same_package
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 8, 6), FlowLevel.spotting),
          );
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 8, 7), FlowLevel.notBleeding),
          );
        },
      );

      // Issue #247 still holds: neither day renders a graded bleed fill.
      for (final iso in ['2026-08-06', '2026-08-07']) {
        expect(find.byKey(ValueKey('bleed-$iso')), findsNothing);
      }
      // ... but pre-#247 data is not lost: the alias renders the same
      // ring-plus-centre-dot treatment a fresh spotting observation gets,
      // via `listForProfile`'s synthesised row.
      expect(
        find.byKey(const ValueKey('spotting-2026-08-06')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('flow-spotting-dot-2026-08-06')),
        findsOneWidget,
      );
      // The explicit not-bleeding day carries no spotting fact at all.
      expect(
        find.byKey(const ValueKey('flow-spotting-dot-2026-08-07')),
        findsNothing,
      );
      await disposeCalendar(tester, h);
    });

    testWidgets('issue #761: a spotting-only day renders the ring-plus-dot '
        'marker instead of a bare cell', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          await _seedSpotting(db, profileId, LocalDate(2026, 8, 4));
        },
      );

      expect(
        find.byKey(const ValueKey('flow-spotting-dot-2026-08-04')),
        findsOneWidget,
      );
      // A ring, never a fill — spotting must stay distinguishable from
      // every graded bleed level without colour.
      final ring = tester.widget<Container>(
        find.byKey(const ValueKey('spotting-2026-08-04')),
      );
      final decoration = ring.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
      expect(decoration.color, isNull);
      expect(find.byKey(const ValueKey('bleed-2026-08-04')), findsNothing);
      await disposeCalendar(tester, h);
    });

    testWidgets('issue #761: the constructor seam alone drives the marker '
        '(an injected repository, not the ambient provider)', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          await DriftDayEntriesRepository(db.storage).save(
            _entryFor(profileId, LocalDate(2026, 8, 8), FlowLevel.notBleeding),
          );
        },
        // The db-backed provider in the harness holds no observations, so a
        // rendered marker can only have come from this seam.
        observationsRepository: FakeSpottingObservationsRepository({
          '2026-08-08',
        }),
      );

      expect(
        find.byKey(const ValueKey('flow-spotting-dot-2026-08-08')),
        findsOneWidget,
      );
      await disposeCalendar(tester, h);
    });

    testWidgets('issue #761: a day with both a bleed level and spotting '
        'renders the bleed fill, never the spotting ring', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          await _seedSpotting(
            db,
            profileId,
            LocalDate(2026, 8, 9),
            flow: FlowLevel.medium,
          );
        },
      );

      final bleed = tester.widget<Container>(
        find.byKey(const ValueKey('bleed-2026-08-09')),
      );
      final decoration = bleed.decoration! as BoxDecoration;
      expect(decoration.color, colors.flowMedium);
      expect(decoration.border, isNull);
      expect(
        find.byKey(const ValueKey('flow-spotting-dot-2026-08-09')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('spotting-2026-08-09')), findsNothing);
      await disposeCalendar(tester, h);
    });

    test('issue #761: the day-cell semantics name the spotting fact, and a '
        'bleed level still wins when both are present', () {
      final l10n = AppLocalizationsEn();

      final spottingOnly = dayCellSemanticLabel(
        date: LocalDate(2026, 8, 4),
        entry: _entryFor('p', LocalDate(2026, 8, 4), FlowLevel.notBleeding),
        today: kToday,
        cell: null,
        l10n: l10n,
        hasSpotting: true,
      );
      expect(spottingOnly, contains('Spotting flow'));
      expect(
        spottingOnly,
        isNot(contains('Not bleeding')),
        reason: 'a spotting day must not be announced as a bleed level',
      );

      final both = dayCellSemanticLabel(
        date: LocalDate(2026, 8, 9),
        entry: _entryFor('p', LocalDate(2026, 8, 9), FlowLevel.medium),
        today: kToday,
        cell: null,
        l10n: l10n,
        hasSpotting: true,
      );
      expect(both, contains('Medium flow'));
      expect(
        both,
        isNot(contains('Spotting')),
        reason: 'bleed wins: the label matches the rendered bleed fill',
      );
    });

    testWidgets('the four flow levels use four visually distinct ramp tones '
        '(no two levels share a colour)', (tester) async {
      final tones = {
        colors.flowSpotting,
        colors.flowLight,
        colors.flowMedium,
        colors.flowHeavy,
      };
      expect(tones, hasLength(4));
    });

    testWidgets('a bleed day that is also today draws the same ring the legend '
        'advertises as Today (issue #312 — previously dropped for any '
        'bleed level)', (tester) async {
      final h = await pumpCalendar(
        tester,
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          await repo.save(_entryFor(profileId, kToday, FlowLevel.medium));
        },
      );

      expect(find.byKey(ValueKey('today-ring-${kToday.iso}')), findsOneWidget);
      expect(find.byKey(ValueKey('bleed-${kToday.iso}')), findsOneWidget);
      await disposeCalendar(tester, h);
    });

    testWidgets(
      'a bleed-logged today cell does not overflow a 375pt-class phone '
      'viewport (issue #312, BLOCKING — today-ring wrapper overflow)',
      (tester) async {
        final h = await pumpCalendar(
          tester,
          physicalSize: const Size(390, 844),
          seed: (db, profileId) async {
            final repo = DriftDayEntriesRepository(db.storage);
            await repo.save(_entryFor(profileId, kToday, FlowLevel.medium));
          },
        );

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(ValueKey('today-ring-${kToday.iso}')),
          findsOneWidget,
        );
        await disposeCalendar(tester, h);
      },
    );
  });

  group('swipe navigation', () {
    testWidgets(
      'the chevrons and a drag on the grid both drive the same PageView, '
      'and navigating away and tapping Today returns to the current month',
      (tester) async {
        final h = await pumpCalendar(tester);

        expect(find.text('August 2026'), findsOneWidget);

        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(
          find.text('September 2026'),
          findsOneWidget,
          reason: 'the chevron still drives the shared PageView',
        );

        await tester.fling(
          find.byKey(const ValueKey('calendar-page-view')),
          const Offset(-700, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(
          find.text('October 2026'),
          findsOneWidget,
          reason: 'a swipe on the grid navigates months too',
        );
        expect(
          find.byKey(const ValueKey('calendar-grid-2026-10')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('today-button')));
        await tester.pumpAndSettle();
        expect(
          find.text('August 2026'),
          findsOneWidget,
          reason: 'Today jumps back to the current month',
        );
        expect(
          find.byKey(const ValueKey('day-cell-2026-08-30')),
          findsOneWidget,
        );

        await disposeCalendar(tester, h);
      },
    );

    testWidgets('a backward swipe on the grid navigates to the previous '
        'month (issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      expect(find.text('August 2026'), findsOneWidget);

      await tester.fling(
        find.byKey(const ValueKey('calendar-page-view')),
        const Offset(700, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('July 2026'),
        findsOneWidget,
        reason: 'a positive-dx (backward) swipe moves to the previous month',
      );

      await disposeCalendar(tester, h);
    });

    testWidgets('a fling past the forward limit stays pinned on the boundary '
        'month — the PageView itemCount bounds it at maxPageIndex + 1 '
        '(issue #312)', (tester) async {
      final h = await pumpCalendar(tester);

      // Navigate straight to the twelve-month forward limit via the
      // picker (already covered elsewhere) rather than twelve chevron
      // taps.
      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('month-picker-2027-8')));
      await tester.pumpAndSettle();
      expect(
        find.text('August 2027'),
        findsOneWidget,
        reason: 'August 2027 is exactly the twelve-month forward limit',
      );

      await tester.fling(
        find.byKey(const ValueKey('calendar-page-view')),
        const Offset(-700, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('August 2027'),
        findsOneWidget,
        reason: 'the fling cannot move past the pinned boundary month',
      );

      await disposeCalendar(tester, h);
    });
  });

  group('month/year picker', () {
    testWidgets('tapping the month label opens a picker bounded by the same '
        "forward limit the chevron's nextDisabled already enforces", (
      tester,
    ) async {
      final h = await pumpCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('month-year-picker')), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      expect(kSentryRouteNames, contains(kRouteMonthYearPickerDialog));

      await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
      await tester.pumpAndSettle();
      expect(find.text('2027'), findsOneWidget);

      final septemberButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('month-picker-2027-9')),
      );
      expect(
        septemberButton.onPressed,
        isNull,
        reason: 'September 2027 is past the twelve-month forward limit',
      );
      final augustButton = tester.widget<OutlinedButton>(
        find.byKey(const ValueKey('month-picker-2027-8')),
      );
      expect(
        augustButton.onPressed,
        isNotNull,
        reason: 'August 2027 is exactly the forward limit and stays reachable',
      );

      await tester.tap(find.byKey(const ValueKey('month-picker-2027-8')));
      await tester.pumpAndSettle();

      expect(find.text('August 2027'), findsOneWidget);
      expect(find.byKey(const ValueKey('month-year-picker')), findsNothing);
      final nextButton = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Next month'),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        nextButton.onPressed,
        isNull,
        reason:
            'navigation stops twelve months forward, same as chevron-only nav',
      );

      await disposeCalendar(tester, h);
    });

    testWidgets('dismissing the picker without selecting a month leaves the '
        'displayed month unchanged', (tester) async {
      final h = await pumpCalendar(tester);

      await tester.tap(find.byKey(const ValueKey('month-year-label')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('month-year-picker')), findsOneWidget);

      // Tap the scrim above the sheet to dismiss it without choosing a
      // month (the sheet's builder returns null in this path).
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('month-year-picker')), findsNothing);
      expect(find.text('August 2026'), findsOneWidget);

      await disposeCalendar(tester, h);
    });
  });

  group('weekday header / grid alignment', () {
    testWidgets('the weekday header and the day grid share the same horizontal '
        'padding, so the columns line up (issue #191)', (tester) async {
      final h = await pumpCalendar(tester);

      final headerPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('calendar-weekday-header')),
      );
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('calendar-grid-2026-8')),
      );
      expect(
        headerPadding.padding,
        grid.padding,
        reason: 'header and grid must share the same horizontal padding',
      );
      expect(headerPadding.padding, const EdgeInsets.symmetric(horizontal: 4));

      await disposeCalendar(tester, h);
    });
  });

  group('_goToMonth guard (issue #312)', () {
    // `canDrivePageController` is the pure predicate `_goToMonth`'s animate
    // and jump paths both now share (previously only the jump path guarded
    // `hasClients`, so an animate call on an unattached `PageController`
    // would throw) — directly unit-testable, unlike the private method
    // itself, since faking an unattached `PageController` isn't observable
    // through any widget-level interaction: every navigation control only
    // renders once the `PageView` (and so its `Scrollable`) has already
    // attached.
    test('does not drive the PageController when it has no clients', () {
      expect(canDrivePageController(hasClients: false), isFalse);
    });

    test('drives the PageController once it is attached', () {
      expect(canDrivePageController(hasClients: true), isTrue);
    });

    testWidgets(
      'two rapid chevron taps land on the correct month, and the header '
      "never rewinds to an earlier month mid-animation (follow-up "
      'review: an `_animateToken` generation counter now guards '
      '`_isAnimatingToMonth`\'s reset, since the first of two '
      'overlapping `animateToPage` calls resolves early — superseded, '
      'not actually settled — once the second one starts)',
      (tester) async {
        final h = await pumpCalendar(tester);

        final labelFinder = find.descendant(
          of: find.byKey(const ValueKey('month-year-label')),
          matching: find.byType(Text),
        );
        String headerText() => tester.widget<Text>(labelFinder).data!;

        const order = ['August 2026', 'September 2026', 'October 2026'];
        expect(headerText(), 'August 2026');

        await tester.tap(find.byTooltip('Next month'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byTooltip('Next month'));

        var lastIndex = order.indexOf(headerText());
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          final idx = order.indexOf(headerText());
          if (idx == -1) continue;
          expect(
            idx,
            greaterThanOrEqualTo(lastIndex),
            reason:
                'header rewound from ${order[lastIndex]} to '
                '${order[idx]}',
          );
          lastIndex = idx;
        }
        await tester.pumpAndSettle();

        expect(
          headerText(),
          'October 2026',
          reason: 'two forward taps from August land on October',
        );

        await disposeCalendar(tester, h);
      },
    );
  });

  group('large text budget (issue #312, #556, #810)', () {
    testWidgets('at textScaleFactor 2.0 on a phone-class viewport the calendar '
        'renders without an overflow, and the legend is reachable from the '
        'info action without stealing the grid vertical budget (issue #312 '
        'review: an 800x1400 desktop-sized canvas made this test vacuous — '
        'the width budget only actually matters on a real phone width)', (
      tester,
    ) async {
      final h = await pumpCalendar(
        tester,
        textScale: 2.0,
        physicalSize: const Size(390, 844),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('calendar-page-view')), findsOneWidget);
      expect(find.byKey(const ValueKey('legend-toggle')), findsOneWidget);
      expect(
        find.text('Light flow'),
        findsNothing,
        reason: '#810: the legend no longer occupies grid vertical budget',
      );

      await tester.tap(find.byKey(const ValueKey('legend-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('Light flow'), findsOneWidget);

      await disposeCalendar(tester, h);
    });
  });

  group('windowed entries subscription (issue #197)', () {
    test('calendarEntriesWindowFor is 45 days each side of the displayed '
        "month's own first/last day, inclusive", () {
      final (from, to) = calendarEntriesWindowFor(2026, 8);
      expect(from, LocalDate(2026, 8, 1).addDays(-45));
      expect(to, LocalDate(2026, 8, 31).addDays(45));
      expect(kCalendarWindowLookbehindDays, 45);
      expect(kCalendarWindowLookaheadDays, 45);
    });

    test('the window for any displayed month covers month−1\'s first day '
        'through month+1\'s last day (review follow-up: a neighbour page '
        'rendered mid-drag must never be missing entries) — checked '
        'across every month, including both year boundaries', () {
      LocalDate firstOfMonth(int y, int m) => LocalDate(y, m, 1);
      LocalDate lastOfMonth(int y, int m) {
        final firstOfNext = m == 12
            ? LocalDate(y + 1, 1, 1)
            : LocalDate(y, m + 1, 1);
        return firstOfNext.addDays(-1);
      }

      for (var year = 2024; year <= 2028; year++) {
        for (var month = 1; month <= 12; month++) {
          final (from, to) = calendarEntriesWindowFor(year, month);
          final (prevYear, prevMonth) = month == 1
              ? (year - 1, 12)
              : (year, month - 1);
          final (nextYear, nextMonth) = month == 12
              ? (year + 1, 1)
              : (year, month + 1);
          final prevFirst = firstOfMonth(prevYear, prevMonth);
          final nextLast = lastOfMonth(nextYear, nextMonth);
          expect(
            from.isAfter(prevFirst),
            isFalse,
            reason:
                'window for $year-$month starts $from, which is '
                'after $prevMonth\'s first day $prevFirst',
          );
          expect(
            to.isBefore(nextLast),
            isFalse,
            reason:
                'window for $year-$month ends $to, which is before '
                '$nextMonth\'s last day $nextLast',
          );
        }
      }
    });

    testWidgets('subscribes once, to the displayed month\'s window — not full '
        'history', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) =>
            recording = RecordingDayEntriesRepository(real),
      );

      expect(recording.calls, hasLength(1));
      final (expectedFrom, expectedTo) = calendarEntriesWindowFor(2026, 8);
      expect(recording.calls.single.from, expectedFrom);
      expect(recording.calls.single.to, expectedTo);

      await disposeCalendar(tester, h);
    });

    testWidgets(
        'issue #795: the spotting read is scoped to the same displayed-month '
        'window as the entries subscription — never the full profile history',
        (tester) async {
      final spotting = RecordingSpottingRangeRepository();
      final h = await pumpCalendar(tester, observationsRepository: spotting);

      final (expectedFrom, expectedTo) = calendarEntriesWindowFor(2026, 8);
      expect(spotting.rangeCalls, isNotEmpty);
      for (final call in spotting.rangeCalls) {
        expect(call.from, expectedFrom);
        expect(call.to, expectedTo);
      }
      expect(
        spotting.listForProfileCalls,
        0,
        reason: 'the calendar marker read must go through the windowed '
            'capability, not the profile-wide fallback',
      );

      await disposeCalendar(tester, h);
    });

    testWidgets(
      'paging one month at a time stays on the same subscription while '
      'still inside its window, and only resubscribes once the '
      "displayed month's own range moves past the fetched window's edge",
      (tester) async {
        late RecordingDayEntriesRepository recording;
        final h = await pumpCalendar(
          tester,
          wrapRepository: (real) =>
              recording = RecordingDayEntriesRepository(real),
        );
        expect(recording.calls, hasLength(1));

        // September 2026 is comfortably inside August's [Jun 17, Oct 15]
        // window (calendarEntriesWindowFor(2026, 8)) — no resubscribe.
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(find.text('September 2026'), findsOneWidget);
        expect(
          recording.calls,
          hasLength(1),
          reason:
              'September is still fully inside the window fetched for '
              'August',
        );

        // October's last day (Oct 31) is past that window's Oct 15 edge —
        // this move must trigger a fresh, re-centered subscription.
        await tester.tap(find.byTooltip('Next month'));
        await tester.pumpAndSettle();
        expect(find.text('October 2026'), findsOneWidget);
        expect(
          recording.calls,
          hasLength(2),
          reason:
              "October's last day falls outside the window fetched "
              'for August',
        );
        final (expectedFrom, expectedTo) = calendarEntriesWindowFor(2026, 10);
        expect(recording.calls.last.from, expectedFrom);
        expect(recording.calls.last.to, expectedTo);

        await disposeCalendar(tester, h);
      },
    );

    testWidgets('a profile switch forces a fresh subscription even though the '
        'displayed month is unchanged', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) =>
            recording = RecordingDayEntriesRepository(real),
      );
      expect(recording.calls, hasLength(1));

      final secondProfile = await DriftProfilesRepository(h.db.storage)
          .create(displayName: 'Bea', isMinor: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [Provider<DayEntriesRepository>.value(value: recording)],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MonthCalendar(
                profileId: secondProfile.id,
                todayProvider: () => kToday,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        recording.calls,
        hasLength(2),
        reason:
            'switching profiles must not reuse the old profile\'s '
            'window/subscription',
      );
      expect(recording.calls.last.from, recording.calls.first.from);
      expect(
        recording.calls.last.to,
        recording.calls.first.to,
        reason:
            'the new subscription still starts on the same '
            "(today's) displayed month",
      );

      await disposeCalendar(tester, h);
    });

    testWidgets(
      'crossing the window boundary and back: a jump far forward past '
      "the window hides an entry logged in the original month, and "
      'jumping back to Today re-subscribes and shows it again, with no '
      'exceptions along the way',
      (tester) async {
        final h = await pumpCalendar(
          tester,
          seed: (db, profileId) async {
            final repo = DriftDayEntriesRepository(db.storage);
            await repo.save(
              _entryFor(profileId, LocalDate(2026, 8, 5), FlowLevel.medium),
            );
          },
        );

        expect(find.byKey(const ValueKey('bleed-2026-08-05')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('calendar-month-empty-2026-8')),
          findsNothing,
        );

        // Jump to March 2027 via the picker — well past the ±45-day window
        // fetched for August 2026.
        await tester.tap(find.byKey(const ValueKey('month-year-label')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('month-picker-next-year')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('month-picker-2027-3')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('March 2027'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bleed-2026-08-05')),
          findsNothing,
          reason: 'August 2026 is not the displayed page any more',
        );
        expect(
          find.byKey(const ValueKey('calendar-month-empty-2027-3')),
          findsOneWidget,
          reason: 'the only seeded entry is outside March 2027\'s window',
        );

        // Jump back to Today.
        await tester.tap(find.byKey(const ValueKey('today-button')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('August 2026'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bleed-2026-08-05')),
          findsOneWidget,
          reason:
              'paging back into range must re-subscribe and show the '
              'entry again, not stay stuck on a stale window',
        );
        expect(
          find.byKey(const ValueKey('calendar-month-empty-2026-8')),
          findsNothing,
        );

        await disposeCalendar(tester, h);
      },
    );

    testWidgets("the neighbour month's entries are in the window (review "
        'follow-up): entries on month−1\'s first day and month+1\'s last '
        "day are already covered by August's own subscription — paging "
        'to either neighbour shows them with no resubscribe', (tester) async {
      late RecordingDayEntriesRepository recording;
      final h = await pumpCalendar(
        tester,
        wrapRepository: (real) =>
            recording = RecordingDayEntriesRepository(real),
        seed: (db, profileId) async {
          final repo = DriftDayEntriesRepository(db.storage);
          // July 1, 2026 is August's month−1's first day; September 30,
          // 2026 is August's month+1's last day.
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 7, 1), FlowLevel.medium),
          );
          await repo.save(
            _entryFor(profileId, LocalDate(2026, 9, 30), FlowLevel.medium),
          );
        },
      );
      expect(recording.calls, hasLength(1));

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bleed-2026-07-01')),
        findsOneWidget,
        reason:
            "month−1's first day must already be in the window "
            "fetched for August",
      );
      expect(
        recording.calls,
        hasLength(1),
        reason: 'no resubscribe should have been needed to show it',
      );

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('bleed-2026-09-30')),
        findsOneWidget,
        reason:
            "month+1's last day must already be in the window "
            "fetched for August",
      );
      expect(
        recording.calls,
        hasLength(1),
        reason:
            'no resubscribe should have been needed to show it '
            'either',
      );

      await disposeCalendar(tester, h);
    });

    testWidgets('a window crossing renders no full-bleed spinner and keeps the '
        'PageView mounted, checked on the very frame after the crossing '
        '(review follow-up: pumped without settling, since settling would '
        'let the replacement stream\'s first emission land and mask the '
        'gap this guards)', (tester) async {
      final h = await pumpCalendar(tester);

      // August -> September stays inside August's window, no crossing.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('September 2026'), findsOneWidget);

      // September -> October crosses the window fetched for August
      // (October's last day is past that window's edge) — this is the
      // resubscribe [_maybeRewatchEntriesFor] triggers synchronously in
      // the tap handler, before the new stream has ever emitted.
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump(); // exactly one frame — deliberately no settle
      expect(find.text('October 2026'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason:
            'a window crossing must keep rendering the previous '
            "window's entries instead of a full-bleed spinner",
      );
      expect(
        find.byKey(const ValueKey('calendar-page-view')),
        findsOneWidget,
        reason:
            'the PageView must stay mounted through the crossing, '
            'not be replaced by a spinner mid-animation',
      );

      await disposeCalendar(tester, h);
    });
  });

  group('forecast-compute memoisation (issue #550)', () {
    /// Six 30-day episodes ending 2026-08-05 (the same shape
    /// `test/ui/overview_test.dart`'s `kActiveStarts` and
    /// `test/ui/forecast_calendar_test.dart`'s `kSteadyStarts` use): high
    /// confidence, an active estimate, so `deriveForecast` actually has
    /// something to compute on every real recompute.
    final steadyStarts = [
      LocalDate(2026, 3, 8),
      LocalDate(2026, 4, 7),
      LocalDate(2026, 5, 7),
      LocalDate(2026, 6, 6),
      LocalDate(2026, 7, 6),
      LocalDate(2026, 8, 5),
    ];

    testWidgets(
      'toggling the legend does not re-run deriveForecast/forecastDayCells '
      '(the byIso/cycles/forecastByIso/activeLayers compute path is '
      'memoised, not re-derived on every setState)',
      (tester) async {
        final h = await pumpCalendar(
          tester,
          withPredictionServices: true,
          seed: (db, profileId) async {
            final entries = DriftDayEntriesRepository(db.storage);
            for (final start in steadyStarts) {
              for (var i = 0; i < 4; i++) {
                await entries.save(
                  _entryFor(profileId, start.addDays(i), FlowLevel.medium),
                );
              }
            }
          },
        );

        final computesAfterInitialLoad = debugForecastComputeCount;
        expect(
          computesAfterInitialLoad,
          greaterThan(0),
          reason:
              'the initial load must compute the forecast at least '
              'once, or this test cannot tell memoisation from a compute '
              'that never ran',
        );

        // Opening and dismissing the legend's info sheet (issue #810) is
        // not a forecast input change, so the memoised compute must not
        // re-run.
        await tester.tap(find.byKey(const ValueKey('legend-toggle')));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();

        expect(
          debugForecastComputeCount,
          computesAfterInitialLoad,
          reason:
              'opening the legend sheet re-ran the forecast compute path; '
              'it should have reused the memoised byIso/cycles/'
              'forecastByIso/activeLayers fields instead',
        );

        await disposeCalendar(tester, h);
      },
    );

    testWidgets(
      'a genuine input change (a symptom-layer toggle) still recomputes',
      (tester) async {
        final h = await pumpCalendar(
          tester,
          withPredictionServices: true,
          seed: (db, profileId) async {
            final entries = DriftDayEntriesRepository(db.storage);
            for (final start in steadyStarts) {
              for (var i = 0; i < 4; i++) {
                await entries.save(
                  _entryFor(profileId, start.addDays(i), FlowLevel.medium),
                );
              }
            }
          },
        );

        final computesAfterInitialLoad = debugForecastComputeCount;

        // This seed carries no tags, so no layer is active and the inline
        // header is hidden (issue #810); the chooser is reached through the
        // info sheet's "Symptom layers" action.
        await tester.tap(find.byKey(const ValueKey('legend-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('symptom-layers-open')));
        await tester.pumpAndSettle();
        final chip = find.byType(FilterChip).first;
        await tester.tap(chip);
        await tester.pumpAndSettle();

        expect(
          debugForecastComputeCount,
          greaterThan(computesAfterInitialLoad),
          reason:
              'the memoisation guard must not swallow a real layer-'
              'selection change',
        );

        await disposeCalendar(tester, h);
      },
    );
  });

  group('issue #543: prediction/history stream error', () {
    testWidgets(
      'a thrown error on the injected prediction stream shows InlineError '
      'with retry instead of a permanent spinner',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final db = LunarLogDatabase(NativeDatabase.memory());
        final profiles = DriftProfilesRepository(db.storage);
        final profile = await profiles.create(
          displayName: 'Alice',
          isMinor: false,
        );
        final entries = DriftDayEntriesRepository(db.storage);
        final erroringEntries = ErroringDayEntriesRepository(entries);

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<DayEntriesRepository>.value(value: entries),
              Provider<CyclePredictionService>.value(
                value: CyclePredictionService(erroringEntries),
              ),
              Provider<CycleHistoryService>.value(
                value: CycleHistoryService(erroringEntries),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: MonthCalendar(
                  profileId: profile.id,
                  todayProvider: () => kToday,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('calendar-page-view')),
          findsOneWidget,
          reason: 'sanity: healthy before the break',
        );

        erroringEntries.broken = true;
        await entries.save(
          DayEntry(
            id: '',
            profileId: profile.id,
            localDate: kToday,
            tz: 'America/Chicago',
            flow: FlowLevel.medium,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('calendar-prediction-error')),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);

        erroringEntries.broken = false;
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('calendar-prediction-error')),
          findsNothing,
          reason: 'retry re-subscribes and recovers once the failure clears',
        );
        expect(
          find.byKey(const ValueKey('calendar-page-view')),
          findsOneWidget,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await db.close();
      },
    );
  });

  group('profile-switch month preservation (issue #241)', () {
    test('hasEntriesInMonth: true for any entry in the month, false outside',
        () {
      expect(
        hasEntriesInMonth(
          [_entryFor('p', LocalDate(2026, 7, 1), FlowLevel.light)],
          2026,
          7,
        ),
        isTrue,
      );
      expect(
        hasEntriesInMonth(
          [_entryFor('p', LocalDate(2026, 7, 31), FlowLevel.light)],
          2026,
          7,
        ),
        isTrue,
        reason: 'the month\'s last day counts',
      );
      expect(
        hasEntriesInMonth(
          [
            _entryFor('p', LocalDate(2026, 6, 30), FlowLevel.light),
            _entryFor('p', LocalDate(2026, 8, 1), FlowLevel.light),
          ],
          2026,
          7,
        ),
        isFalse,
        reason: ' neighbours on either side do not',
      );
      expect(hasEntriesInMonth(const [], 2026, 7), isFalse);
    });

    /// The tree [pumpSwitchableCalendar] mounts, parameterised by the
    /// profile id — re-pumping with a different id is exactly a profile
    /// switch for the still-mounted [MonthCalendar] State.
    Widget switchableTree(DriftDayEntriesRepository entries, String id) =>
        MultiProvider(
          providers: [
            Provider<DayEntriesRepository>.value(value: entries),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: MonthCalendar(
                profileId: id,
                todayProvider: () => kToday,
              ),
            ),
          ),
        );

    /// Three profiles (Alice, Bob, Charlie) over one repository; Bob
    /// carries one July entry, Charlie none. [pump] mounts Alice's
    /// calendar; the returned [switchTo] closure switches the mounted
    /// calendar to another profile id.
    Future<
        ({
          Future<void> Function(String profileId) switchTo,
          String bobId,
          String charlieId,
        })> pumpSwitchableCalendar(WidgetTester tester, LunarLogDatabase db) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final profiles = DriftProfilesRepository(db.storage);
      final alice = await profiles.create(displayName: 'Alice', isMinor: false);
      final bob = await profiles.create(displayName: 'Bob', isMinor: false);
      final charlie =
          await profiles.create(displayName: 'Charlie', isMinor: false);
      final entries = DriftDayEntriesRepository(db.storage);
      // kToday is 2026-08-30: "the displayed month" the test navigates to
      // is July 2026, and Bob alone has an entry there.
      await entries.save(
          _entryFor(bob.id, LocalDate(2026, 7, 15), FlowLevel.medium));

      await tester.pumpWidget(switchableTree(entries, alice.id));
      await tester.pumpAndSettle();
      return (
        switchTo: (String profileId) async {
          await tester.pumpWidget(switchableTree(entries, profileId));
          await tester.pumpAndSettle();
        },
        bobId: bob.id,
        charlieId: charlie.id,
      );
    }

    testWidgets('switching to a profile with entries in the displayed month '
        'keeps that month', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final harness = await pumpSwitchableCalendar(tester, db);

      expect(find.text('August 2026'), findsOneWidget,
          reason: 'kToday is 2026-08-30, so the calendar opens on August');
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);

      await harness.switchTo(harness.bobId);
      expect(find.text('July 2026'), findsOneWidget,
          reason: 'Bob has a July entry, so the switch kept the displayed '
              'month (issue #241 B-16)');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });

    testWidgets('switching to a profile with no entries in the displayed '
        'month resets to today\'s month', (tester) async {
      final db = LunarLogDatabase(NativeDatabase.memory());
      final harness = await pumpSwitchableCalendar(tester, db);

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('July 2026'), findsOneWidget);

      await harness.switchTo(harness.charlieId);
      expect(find.text('August 2026'), findsOneWidget,
          reason: 'Charlie has no July entry, so the switch reset to '
              "today's month (the pre-#241 behavior)");
      expect(find.text('July 2026'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await db.close();
    });
  });
}
