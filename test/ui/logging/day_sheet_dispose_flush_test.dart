/// Issue #546: the day-sheet dismissal flush used to fire a second,
/// concurrent write whenever a `_performAutosave` write was already in
/// flight when the sheet disposed — `_setAutosaveState`'s `if (!mounted)
/// return` guard made `_saving` inert once the sheet was gone, so neither
/// `dispose()`'s own flush nor a later post-dispose `_performAutosave`
/// continuation ever saw an accurate "still saving" signal. This exercises
/// the fix directly against a controllable fake repository rather than the
/// real (fast, unblockable) drift-backed one `logging_test.dart` otherwise
/// uses for `DaySheet`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/day_sheet.dart';

final LocalDate kToday = LocalDate(2026, 8, 30);

/// Records every `saveDayEntryWithObservations` call and, while [gate] is
/// set, blocks each call on it — letting a test hold a write "in flight"
/// for as long as it needs before choosing to let it complete.
class _GatedDayEntriesRepository implements DayEntriesRepository {
  final List<DayEntry> calls = [];
  Completer<void>? gate;
  DayEntry? _saved;

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
    return saved;
  }

  @override
  Future<DayEntry> save(DayEntry entry) => saveDayEntryWithObservations(entry: entry);

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) async => _saved;

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      _saved == null ? const [] : [_saved!];

  @override
  Future<bool> hasAnyEntries(String profileId) async => _saved != null;

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      Stream.value(_saved == null ? const [] : [_saved!]);

  @override
  Future<void> delete(String profileId, LocalDate localDate) async {}
}

void main() {
  const kDelay = kDaySheetAutosaveDelay;

  Future<_GatedDayEntriesRepository> pumpSheet(WidgetTester tester) async {
    final repository = _GatedDayEntriesRepository();
    await tester.pumpWidget(MaterialApp(
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
                ),
              ),
              child: const Text('Open'),
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
}
