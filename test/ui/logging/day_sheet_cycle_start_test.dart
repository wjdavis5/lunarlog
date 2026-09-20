/// Issue #887: the day sheet's flow chips make the cycle-start decision
/// implicitly — one `Light` tap on cycle day 17 silently started a new
/// cycle, closed a 16-day cycle into the averages, and flipped the
/// confidence tier from Learning to High (the exact reproduction is
/// pinned in `test/domain/logging/cycle_start_confirm_test.dart`). These
/// tests drive the disclosure + consent half end to end against the real
/// Drift repositories: the confirmation dialog on a surprising tap (with
/// its spotting alternative), no dialog on the control cases, and the
/// dismissal-time snackbar with an Undo that restores the pre-session
/// entry (#316's pattern, the one the issue asks for).
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_observations_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/models/observation_category.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

/// The issue's day: Maya is on cycle day 17 of the cycle that started
/// 2026-09-03 (her history 29 · 28 · 7 (outlier) · 23 · 28 · 29 — episode
/// starts below, one-day episodes).
final LocalDate kToday = LocalDate(2026, 9, 19);

const List<String> _kMayaStarts = [
  '2026-04-12',
  '2026-05-11',
  '2026-06-08',
  '2026-06-15',
  '2026-07-08',
  '2026-08-05',
  '2026-09-03',
];

/// The same history shifted 20 days earlier, for tests whose "expected
/// start" day must itself sit in the past — the storage layer's #848
/// date-bounds policy rejects a save dated in the real future, so a
/// fixture anchored on 2026-09-03 cannot test a day-29 write until real
/// time reaches October.
const List<String> _kMayaStartsShifted = [
  '2026-03-23',
  '2026-04-21',
  '2026-05-19',
  '2026-05-26',
  '2026-06-18',
  '2026-07-16',
  '2026-08-14',
];

/// A real-repository harness over Maya's seeded history, so the guard
/// evaluates exactly what the engine would.
class Harness {
  Harness(this.db);

  final LunarLogDatabase db;

  late DriftDayEntriesRepository entries;
  late DriftObservationsRepository observations;
  late String profileId;

  /// Optional pre-existing entry on the logged day, so a session has a
  /// genuine "before" for the Undo to restore.
  DayEntry? existingToday;

  Future<void> seed({
    bool withExistingToday = false,
    List<String> starts = _kMayaStarts,
  }) async {
    final profiles = DriftProfilesRepository(db.storage);
    profileId = (await profiles.create(displayName: 'Maya', isMinor: false)).id;
    entries = DriftDayEntriesRepository(db.storage);
    observations = DriftObservationsRepository(db.storage);
    for (final iso in starts) {
      await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: LocalDate.fromIso(iso),
        tz: 'UTC',
        flow: FlowLevel.medium,
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
    }
    if (withExistingToday) {
      existingToday = await entries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: kToday,
        tz: 'UTC',
        flow: FlowLevel.notBleeding,
        tags: const ['cramps'],
        note: 'tired',
        updatedAt: DateTime.utc(2026, 1, 1),
      ));
    }
  }

  Future<void> dispose() => db.close();
}

Future<Harness> createHarness({
  bool withExistingToday = false,
  List<String> starts = _kMayaStarts,
}) async {
  final h = Harness(LunarLogDatabase(NativeDatabase.memory()));
  await h.seed(withExistingToday: withExistingToday, starts: starts);
  return h;
}

/// A repository whose history read fails — the guard's fail-open path
/// (issue #887): no dialog, logging proceeds exactly as before. Everything
/// else forwards to the real repository underneath.
class _HistoryReadFailureRepo implements DayEntriesRepository {
  _HistoryReadFailureRepo(this._inner);

  final DayEntriesRepository _inner;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async {
    throw StateError('disk error');
  }

  @override
  Future<List<DayEntryMergeEvent>> mergeEventsForDay(
          String profileId, LocalDate date) =>
      _inner.mergeEventsForDay(profileId, date);

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) =>
      _inner.saveDayEntryWithObservations(
        entry: entry,
        observationsToUpsert: observationsToUpsert,
        observationIdsToDelete: observationIdsToDelete,
      );

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      _inner.delete(profileId, localDate);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumps the app shell and opens the day sheet on [h]'s profile, on
/// [date] (default: the issue's day 17), over [existing] (default:
/// [Harness.existingToday]) and/or through a [repository] override.
Future<void> pumpSheet(
  WidgetTester tester,
  Harness h, {
  LocalDate? date,
  LocalDate? today,
  DayEntry? existing,
  DayEntriesRepository? repository,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  final sheetDate = date ?? kToday;

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ObservationsRepository>.value(value: h.observations),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open-day-sheet'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => DaySheet(
                    repository: repository ?? h.entries,
                    profileId: h.profileId,
                    date: sheetDate,
                    existing: existing ?? h.existingToday,
                    today: today ?? sheetDate,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('open-day-sheet')));
  await tester.pumpAndSettle();
}

/// Whether the flow chip row's `Light` choice is currently selected.
bool _lightSelected(WidgetTester tester) => tester
    .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Light'))
    .selected;

/// Lets the autosave debounce fire and settle.
Future<void> _settleAutosave(WidgetTester tester) async {
  await tester.pump(kDaySheetAutosaveDelay);
  await tester.pumpAndSettle();
}

/// Dismisses the sheet by tapping the modal barrier above it.
Future<void> _dismissSheet(WidgetTester tester) async {
  await tester.tapAt(const Offset(400, 20));
  await tester.pumpAndSettle();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('the confirmation dialog', () {
    testWidgets('a day-17 light tap asks before starting a new cycle',
        (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsOneWidget);
      expect(find.textContaining('cycle day 17'), findsOneWidget,
          reason: 'the plain-language copy names the day, per the issue');
      expect(find.textContaining('after 16 days'), findsOneWidget,
          reason: 'the copy names the cycle length this tap would close');
      expect(_lightSelected(tester), isFalse,
          reason: 'nothing is selected while the decision is pending');
    });

    testWidgets('"Start new cycle" writes the flow and shows the Undo '
        'snackbar on dismissal; Undo tombstones the created day',
        (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-confirm')));
      await tester.pumpAndSettle();
      expect(_lightSelected(tester), isTrue);

      await _settleAutosave(tester);
      final saved = await h.entries.find(h.profileId, kToday);
      expect(saved?.flow, FlowLevel.light,
          reason: 'the confirmed write lands through the ordinary path');

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();
      expect(await h.entries.find(h.profileId, kToday), isNull,
          reason: 'Undo restores the pre-session state exactly — the day '
              'was created by this session, so it is tombstoned');
    });

    testWidgets('"Log spotting instead" records spotting and never starts '
        'a cycle', (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-spotting')));
      await tester.pumpAndSettle();

      expect(_lightSelected(tester), isFalse,
          reason: 'the bleed level is not written — that was the decision '
              'being asked');
      expect(
        tester
            .widget<FilterChip>(find.byKey(const ValueKey('spotting-chip')))
            .selected,
        isTrue,
        reason: 'the spotting alternative is visibly on',
      );

      await _settleAutosave(tester);
      final saved = await h.entries.find(h.profileId, kToday);
      expect(saved?.flow, FlowLevel.notBleeding,
          reason: 'spotting-only days assert notBleeding (#247), never a '
              'bleed level');
      final rows = await h.observations.listForDayEntry(saved!.id);
      expect(
        rows.any((o) => o.category == ObservationCategory.spotting),
        isTrue,
        reason: 'spotting is its own observation row',
      );

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsNothing,
          reason: 'the spotting path changes no cycle start — nothing to '
              'disclose or undo');
    });

    testWidgets('cancel leaves the day untouched', (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsNothing);
      expect(_lightSelected(tester), isFalse);
      await _settleAutosave(tester);
      expect(await h.entries.find(h.profileId, kToday), isNull,
          reason: 'a cancelled decision writes nothing');

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsNothing);
    });

    testWidgets('a confirmed start does not re-ask on a further bleed-level '
        'change', (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-confirm')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Heavy').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsNothing,
          reason: 'the consent decision was made; changing between bleed '
              'levels moves nothing at the cycle boundary');
    });
  });

  group('the control cases', () {
    testWidgets('a day-2 light tap needs no confirmation', (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h, date: LocalDate(2026, 9, 4));

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsNothing);
      expect(_lightSelected(tester), isTrue);
      await _settleAutosave(tester);
      expect((await h.entries.find(h.profileId, LocalDate(2026, 9, 4)))?.flow,
          FlowLevel.light);

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsNothing,
          reason: 'the day merged into the running episode — no cycle start '
              'changed');
    });

    testWidgets('an expected day-29 start skips the dialog but still gets '
        'the Undo snackbar', (tester) async {
      // The shifted fixture: open cycle anchored 2026-08-14, so her own
      // mean (~27.4 days) lands the expected start on 2026-09-11 — a day
      // the storage layer will accept (see _kMayaStartsShifted).
      final expected = LocalDate(2026, 9, 11); // Aug 14 + 28: right on her mean
      final h = await createHarness(starts: _kMayaStartsShifted);
      addTearDown(h.dispose);
      await pumpSheet(tester, h, date: expected, today: expected);

      await tester.tap(find.text('Medium').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsNothing,
          reason: '28 days is not early for this history');
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Medium'))
            .selected,
        isTrue,
      );

      await _settleAutosave(tester);
      expect((await h.entries.find(h.profileId, expected))?.flow,
          FlowLevel.medium);

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsOneWidget,
          reason: 'an expected start still changed the cycle-start set — '
              '#887 asks for the Undo on every such write');
    });
  });

  group('the undo restores the pre-session entry', () {
    testWidgets('an existing entry comes back exactly as it was',
        (tester) async {
      final h = await createHarness(withExistingToday: true);
      addTearDown(h.dispose);
      await pumpSheet(tester, h);
      final previous = h.existingToday!;

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-confirm')));
      await _settleAutosave(tester);
      expect((await h.entries.find(h.profileId, kToday))?.flow,
          FlowLevel.light);

      await _dismissSheet(tester);
      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();
      final restored = await h.entries.find(h.profileId, kToday);
      expect(restored?.id, previous.id,
          reason: 'the same row is restored, not a fresh entry');
      expect(restored?.flow, FlowLevel.notBleeding);
      expect(restored?.tags, const ['cramps']);
      expect(restored?.note, 'tired');
    });

    testWidgets('a still-debounced flush at dismissal still discloses and '
        'undoes', (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h);

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cycle-start-confirm')));
      await tester.pumpAndSettle();
      // No autosave settle: the write is still inside the debounce window
      // when the sheet is dismissed.
      await _dismissSheet(tester);

      expect(find.byKey(const ValueKey('day-sheet-cycle-start-snackbar')),
          findsOneWidget,
          reason: 'the dismissal-time flush is a cycle-start change too');
      await _settleAutosave(tester);
      expect((await h.entries.find(h.profileId, kToday))?.flow,
          FlowLevel.light,
          reason: 'the dismissal flush persisted the debounced write');

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();
      expect(await h.entries.find(h.profileId, kToday), isNull);
    });
  });

  group('the guard fails open', () {
    testWidgets('a history-read failure logs without a dialog',
        (tester) async {
      final h = await createHarness();
      addTearDown(h.dispose);
      await pumpSheet(tester, h, repository: _HistoryReadFailureRepo(h.entries));

      await tester.tap(find.text('Light').first);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('cycle-start-confirm-dialog')),
          findsNothing,
          reason: 'a guard whose read failed must never block logging — '
              'exactly the pre-#887 behavior');
      expect(_lightSelected(tester), isTrue);
    });
  });
}
