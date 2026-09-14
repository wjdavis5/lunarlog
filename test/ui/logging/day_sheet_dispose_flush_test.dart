/// Issue #546: the day-sheet dismissal flush used to fire a second,
/// concurrent write whenever a `_performAutosave` write was already in
/// flight when the sheet disposed — `_setAutosaveState`'s `if (!mounted)
/// return` guard made `_saving` inert once the sheet was gone, so neither
/// `dispose()`'s own flush nor a later post-dispose `_performAutosave`
/// continuation ever saw an accurate "still saving" signal. This exercises
/// the fix directly against a controllable fake repository rather than the
/// real (fast, unblockable) drift-backed one `logging_test.dart` otherwise
/// uses for `DaySheet`.
///
/// Issue #601's whole-repository audit follow-up added two more findings
/// this same `Completer`-gated harness is the natural place to pin:
///
/// * **LLA-001** — an older autosave write completing must never clear a
///   *newer* edit that arrived while it was in flight. The sealed
///   `DaySheetSaveState` refactor (issue #601) fixes this by construction
///   (`daySheetSettleWrite` preserves `queuedNext` as the settled `Dirty`
///   state rather than discarding it); the groups below prove it two ways
///   the pre-refactor code could still have gotten wrong: while the sheet
///   stays open (the newer edit is itself autosaved once its own debounce
///   elapses), and when the sheet is dismissed immediately after the older
///   write settles but before the newer edit's own debounce has fired
///   (dispose must still flush it).
/// * **LLA-003** — an autosave write already in flight when Delete is
///   confirmed must not be allowed to complete *after* deletion and
///   resurrect the row (its own upsert writes `deletedAt: null`). `_delete`
///   now awaits any in-flight write, after first moving `_saveState` to
///   the terminal `DaySheetDeleting` — see that class's own doc in
///   `day_sheet_save_state.dart` for why that ordering is what actually
///   closes the race, not merely the await by itself.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/domain/repositories/observations_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';
import 'package:provider/provider.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// A trivial no-observations fake — `existing != null` makes `DaySheet`
/// load the spotting toggle's initial state via a non-nullable
/// `Provider.of<ObservationsRepository>`, so the LLA-003 group (the only
/// one that pumps with `existing:` set) needs one in the tree at all, even
/// though nothing in those tests exercises spotting/pain itself.
class _NoObservationsRepository implements ObservationsRepository {
  @override
  Future<List<Observation>> listForProfile(String profileId) async => const [];

  @override
  Future<List<Observation>> listForDayEntry(String dayEntryId) async => const [];

  @override
  Future<List<Observation>> listForDayEntryWithLegacyAlias(
    String dayEntryId,
  ) async =>
      const [];

  @override
  Future<Observation> save(Observation observation) async => observation;

  @override
  Future<void> delete(String id) async {}
}

/// Records every `saveDayEntryWithObservations` call and, while [gate] is
/// set, blocks each call on it — letting a test hold a write "in flight"
/// for as long as it needs before choosing to let it complete.
///
/// [deleted]/[deleteCalls] track `delete()` for the LLA-003 regression
/// group below: every successful [saveDayEntryWithObservations] clears
/// [deleted] again, mirroring the real upsert's `deletedAt: null` write
/// (`lib/data/db/storage_local_writes.dart`) that is exactly what lets an
/// outstanding autosave resurrect a deleted row if it is allowed to land
/// after the delete.
class _GatedDayEntriesRepository implements DayEntriesRepository {
  final List<DayEntry> calls = [];
  Completer<void>? gate;
  DayEntry? _saved;
  bool deleted = false;
  int deleteCalls = 0;

  /// Blocks [delete] itself, separately from [gate] (which only blocks
  /// [saveDayEntryWithObservations]) — lets a test hold the delete call
  /// open long enough to dispose the sheet while `_saveState` still reads
  /// `DaySheetDeleting`, not yet `DaySheetDeleted`.
  Completer<void>? deleteGate;

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) async {
    calls.add(entry);
    final g = gate;
    if (g != null) await g.future;
    final saved = entry.id.isEmpty ? entry.copyWith(id: 'e${calls.length}') : entry;
    _saved = saved;
    deleted = false;
    return saved;
  }

  @override
  Future<DayEntry> save(DayEntry entry) => saveDayEntryWithObservations(entry: entry);

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async =>
      deleted ? null : _saved;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      (deleted || _saved == null) ? const [] : [_saved!];

  @override
  Future<bool> hasAnyEntries(String profileId) async => !deleted && _saved != null;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      Stream.value((deleted || _saved == null) ? const [] : [_saved!]);

  @override
  Future<void> delete(String profileId, LocalDate localDate) async {
    deleteCalls++;
    final g = deleteGate;
    if (g != null) await g.future;
    deleted = true;
  }
}

DayEntry _existingEntry({String note = 'existing'}) => DayEntry(
      id: 'e0',
      profileId: 'p1',
      localDate: kToday,
      tz: 'UTC',
      flow: FlowLevel.medium,
      note: note,
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  const kDelay = kDaySheetAutosaveDelay;

  Future<_GatedDayEntriesRepository> pumpSheet(
    WidgetTester tester, {
    DayEntry? existing,
  }) async {
    final repository = _GatedDayEntriesRepository();
    if (existing != null) repository._saved = existing;
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ObservationsRepository>.value(
          value: _NoObservationsRepository(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('open'),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DaySheet(
                    repository: repository,
                    profileId: 'p1',
                    date: kToday,
                    today: kToday,
                    existing: existing,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> typeNote(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('note-field')), text);
  }

  /// Taps the delete affordance and confirms the dialog — mirrors
  /// `logging_test.dart`'s own delete flow exactly (same tooltip/button
  /// text), except it never calls `pumpAndSettle`: while a gated write is
  /// still held, the autosave status slot behind the dialog renders an
  /// indeterminate `CircularProgressIndicator`, whose repeating animation
  /// means `pumpAndSettle` never observes "no more scheduled frames" and
  /// times out -- the same reason the two pre-existing tests in this file
  /// only ever `pump()` explicit durations while a gate is held. Returns
  /// once the confirm tap's `onPressed` has fired; the caller awaits
  /// whatever else it needs to (LLA-003's whole point is that `_delete`'s
  /// own continuation can be left suspended here, awaiting a held write).
  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Delete entry'));
    await tester.pump(); // open the dialog
    await tester.pump(const Duration(milliseconds: 300)); // its entrance transition
    expect(find.text('Delete this entry?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
  }

  testWidgets(
      'a write already in flight when the sheet disposes is not joined by '
      'a second, concurrent write for a later edit (issue #546)',
      (tester) async {
    final repository = await pumpSheet(tester);

    // First edit: debounce fires, the write starts and blocks on `gate`.
    final gate = Completer<void>();
    repository.gate = gate;
    await typeNote(tester, 'first');
    await tester.pump(kDelay);
    expect(repository.calls, hasLength(1),
        reason: 'the debounced autosave started its write');

    // Second edit while the first write is still in flight.
    await typeNote(tester, 'first second');

    // Dispose the sheet (pop it) while the first write is still blocked.
    Navigator.of(tester.element(find.byKey(const ValueKey('open'))))
        .pop();
    await tester.pump();

    expect(repository.calls, hasLength(1),
        reason: 'the dismissal flush must not fire a second, concurrent '
            'write while one is already in flight — before the fix, the '
            'flush read a stale (never-updated-while-unmounted) `_saving` '
            'and fired anyway');

    // Let the first write complete.
    gate.complete();
    await tester.pumpAndSettle();

    // The second edit must not be silently dropped: `_onAutosaveSuccess`
    // resetting `_saving` (even though the sheet is gone) is what lets the
    // queued continuation actually run the second write.
    expect(repository.calls, hasLength(2),
        reason: 'the second edit, queued behind the first write, must '
            'still be written once the first completes — silently '
            'dropping it would be exactly the "no telemetry" data loss '
            'issue #546 reported');
    expect(repository.calls.last.note, 'first second');
  });

  testWidgets(
      'a write that completes after disposal still lets its own '
      'continuation see an accurate _saving, not a stuck stale value',
      (tester) async {
    final repository = await pumpSheet(tester);

    final gate = Completer<void>();
    repository.gate = gate;
    await typeNote(tester, 'a');
    await tester.pump(kDelay);
    expect(repository.calls, hasLength(1));

    // No second edit this time -- just dispose mid-write and let it finish.
    Navigator.of(tester.element(find.byKey(const ValueKey('open'))))
        .pop();
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    // A single call: nothing to queue, and completion must not throw
    // (`setState` after dispose) or leave any pending timers/microtasks --
    // `tester.pumpAndSettle()` above would hang or the test would flag a
    // pending timer otherwise.
    expect(repository.calls, hasLength(1));
  });

  group('LLA-001: an older autosave must not clear a newer pending edit', () {
    testWidgets(
        'an edit made while an earlier write is still in flight survives '
        'that write\'s success and is itself written once its own '
        'debounce elapses -- while the sheet stays open, no dispose '
        'involved', (tester) async {
      final repository = await pumpSheet(tester);

      final gate = Completer<void>();
      repository.gate = gate;
      await typeNote(tester, 'A');
      await tester.pump(kDelay);
      expect(repository.calls, hasLength(1),
          reason: 'the debounced autosave for A started its write');

      // B arrives while A's write is still blocked on `gate`.
      await typeNote(tester, 'A then B');

      // Let A's write complete.
      gate.complete();
      await tester.pump();

      // A's success must not have thrown B away: nothing new written yet
      // (B's own debounce has not elapsed), but B must still be queued.
      expect(repository.calls, hasLength(1),
          reason: 'B has not been written yet -- it is still waiting out '
              'its own debounce, not lost when A settled');

      // B's own debounce timer (armed when it was typed) now elapses.
      await tester.pump(kDelay);
      await tester.pumpAndSettle();

      expect(repository.calls, hasLength(2),
          reason: 'B must still be written once its own debounce elapses '
              "-- A's success must not have unconditionally cleared it "
              '(the LLA-001 finding)');
      expect(repository.calls.last.note, 'A then B');
      expect((await repository.find('p1', kToday))?.note, 'A then B');
    });

    testWidgets(
        'if the sheet is dismissed right after the earlier write settles '
        '-- before the newer edit\'s own debounce has elapsed -- dispose '
        'still flushes the newer edit rather than treating the sheet as '
        'clean', (tester) async {
      final repository = await pumpSheet(tester);

      final gate = Completer<void>();
      repository.gate = gate;
      await typeNote(tester, 'A');
      await tester.pump(kDelay);
      expect(repository.calls, hasLength(1));

      await typeNote(tester, 'A then B');

      gate.complete();
      await tester.pump(); // A settles; state becomes Dirty(B), not Saved.

      expect(repository.calls, hasLength(1),
          reason: 'B has not been written yet at dismissal time');

      Navigator.of(tester.element(find.byKey(const ValueKey('open'))))
          .pop();
      await tester.pumpAndSettle();

      expect(repository.calls, hasLength(2),
          reason: 'dispose must flush B -- the sheet is Dirty, not clean, '
              'at the moment it is dismissed');
      expect(repository.calls.last.note, 'A then B');
      expect(
        (await repository.find('p1', kToday))?.note,
        'A then B',
        reason: 'reopening the day must show B\'s content, not A\'s stale '
            'write',
      );
    });
  });

  group('LLA-003: an outstanding autosave must not resurrect an explicitly '
      'deleted entry', () {
    testWidgets(
        'a delete confirmed while an earlier write is still in flight '
        'does not get undone once that write completes', (tester) async {
      final repository =
          await pumpSheet(tester, existing: _existingEntry());

      final gate = Completer<void>();
      repository.gate = gate;
      await typeNote(tester, 'edited');
      await tester.pump(kDelay);
      expect(repository.calls, hasLength(1),
          reason: 'the debounced autosave started its write and is now '
              'held');

      await confirmDelete(tester);
      // `_delete` is now suspended awaiting the held write -- confirm it
      // has not raced ahead and called `repository.delete()` yet.
      expect(repository.deleted, isFalse,
          reason: 'delete() must wait for the in-flight write rather than '
              'racing it');

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue,
          reason: 'the held write must not resurrect the entry once '
              'delete() proceeds -- daySheetSettleWrite must see '
              'DaySheetDeleting, not DaySheetSaving, by the time it '
              'settles');
      expect(repository.deleteCalls, 1);
      expect(repository.calls, hasLength(1),
          reason: 'no further save call may fire after Delete was '
              'confirmed');
    });

    testWidgets(
        'a delete confirmed while an earlier write is in flight AND a '
        'newer edit is already queued behind it discards the queued edit '
        'too -- it must never be written after deletion', (tester) async {
      final repository =
          await pumpSheet(tester, existing: _existingEntry());

      final gate = Completer<void>();
      repository.gate = gate;
      await typeNote(tester, 'A');
      await tester.pump(kDelay);
      expect(repository.calls, hasLength(1));

      // A newer edit arrives while A's write is still in flight.
      await typeNote(tester, 'A then B');

      await confirmDelete(tester);
      expect(repository.deleted, isFalse);

      gate.complete();
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue, reason: 'deletion still wins');
      expect(
        repository.calls,
        hasLength(1),
        reason: 'the queued edit (B) must be discarded, not written -- '
            'deleting supersedes it, and writing it after delete() would '
            'resurrect the entry with B\'s content instead of leaving it '
            'deleted',
      );
    });

    testWidgets(
        'a delete with nothing in flight behaves exactly as before -- no '
        'regression on the common case', (tester) async {
      final repository =
          await pumpSheet(tester, existing: _existingEntry());

      await confirmDelete(tester);
      await tester.pumpAndSettle();

      expect(repository.deleted, isTrue);
      expect(find.byType(DaySheet), findsNothing,
          reason: 'the sheet closes on a successful delete, same as '
              'always');
    });

    testWidgets(
        'the sheet being torn down while the delete call itself is still '
        'in flight (DaySheetDeleting, not yet DaySheetDeleted) does not '
        'crash and does not block the delete from completing -- exercises '
        'dispose()\'s own DaySheetDeleting/DaySheetDeleted Noop branch, '
        'which owns whatever happens next entirely on _delete\'s own '
        'still-running continuation', (tester) async {
      final repository =
          await pumpSheet(tester, existing: _existingEntry());

      final deleteGate = Completer<void>();
      repository.deleteGate = deleteGate;

      await tester.tap(find.byTooltip('Delete entry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Delete this entry?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      // `_delete` is now suspended awaiting `repository.delete()`, with
      // `_saveState` already `DaySheetDeleting` -- but the sheet has not
      // popped itself yet (that only happens after `delete()` resolves).
      await tester.pump();
      expect(repository.deleted, isFalse);

      // The sheet is torn down by something other than `_delete`'s own
      // eventual pop -- e.g. the host route being replaced. `dispose()`
      // must not throw, and must not try to act on `DaySheetDeleting` on
      // `_delete`'s behalf.
      Navigator.of(tester.element(find.byKey(const ValueKey('open'))))
          .pop();
      await tester.pump();
      expect(tester.takeException(), isNull);

      // `_delete`'s own continuation (unaffected by the widget's teardown)
      // still runs delete() to completion once released.
      deleteGate.complete();
      await tester.pump();
      await tester.pump();
      expect(repository.deleted, isTrue);
      expect(repository.deleteCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
