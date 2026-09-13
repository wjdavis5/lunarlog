/// Issue #528: `LifecycleMode` is wired into `CyclePredictionService` so
/// `pregnancy`/`postpartum`/`perimenopause` suppress period prediction (and,
/// by extension, the estimate-relative reminders that only ever consume an
/// `ActivePrediction` — see `lib/data/notifications/reminder_coordinator.dart`)
/// instead of silently running the ordinary "days late" estimate against a
/// cycle that isn't the regular ovulatory one the model assumes.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

/// A caller-driven day-entry stream, matching the sibling birth-control
/// service test's stub.
class _StubDayEntriesRepository implements DayEntriesRepository {
  final _controller = StreamController<List<DayEntry>>.broadcast();

  void emit(List<DayEntry> entries) => _controller.add(entries);

  Future<void> close() => _controller.close();

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) => _controller.stream;

  @override
  Future<DayEntry> save(DayEntry entry) => throw UnimplementedError();

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Object?> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) => throw UnimplementedError();

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      throw UnimplementedError();

  /// Backs [CyclePredictionService.current]'s one-shot read; tests using it
  /// pre-seed via [emit] and read the latest event synchronously since the
  /// stream never actually needs to be awaited for that call path.
  List<DayEntry> currentEntries = const [];

  @override
  Future<List<DayEntry>> listForProfile(String profileId) async =>
      currentEntries;

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      throw UnimplementedError();

  @override
  Future<bool> hasAnyEntries(String profileId) async =>
      currentEntries.isNotEmpty;
}

/// Three completed, regular cycles (four episode starts) — enough for an
/// ordinary `ActivePrediction` when no lifecycle mode or birth control is in
/// effect (used to prove the suppression is what's actually silencing the
/// estimate, not merely a lack of history — mirrors the sibling
/// birth-control service test's history fixture).
List<DayEntry> _regularHistory() => [
  for (final start in [
    d(2026, 1, 1),
    d(2026, 1, 29),
    d(2026, 2, 28),
    d(2026, 4, 1),
  ])
    DayEntry(
      id: 'entry-${start.iso}',
      profileId: 'p',
      localDate: start,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: DateTime.utc(2026, 1, 1),
    ),
];

void main() {
  group('LifecycleMode suppression (issue #528)', () {
    test('pregnancy/postpartum/perimenopause return PredictionsSuppressed '
        'carrying the mode, even with a full regular history', () async {
      for (final mode in [
        LifecycleMode.pregnancy,
        LifecycleMode.postpartum,
        LifecycleMode.perimenopause,
      ]) {
        final entries = _StubDayEntriesRepository();
        addTearDown(entries.close);
        final service = CyclePredictionService(
          entries,
          lifecycleModeFor: (_) => Stream.value(mode),
        );
        final watchStream = service.watch('p', today: () => d(2026, 4, 10));
        // combineLatest needs every source to emit at least once; a full
        // regular history is fed in deliberately to prove the suppression
        // isn't merely a lack of history.
        final afterHistoryFuture = watchStream.first;
        entries.emit(_regularHistory());
        final afterHistory = await afterHistoryFuture;
        expect(afterHistory, isA<PredictionsSuppressed>(), reason: mode.name);
        expect(
          (afterHistory as PredictionsSuppressed).lifecycleMode,
          mode,
          reason: mode.name,
        );
        expect(afterHistory.method, isNull, reason: mode.name);
      }
    });

    test('tracking and conceive are unaffected: an ordinary regular history '
        'still yields ActivePrediction', () async {
      for (final mode in [LifecycleMode.tracking, LifecycleMode.conceive]) {
        final entries = _StubDayEntriesRepository();
        addTearDown(entries.close);
        final service = CyclePredictionService(
          entries,
          lifecycleModeFor: (_) => Stream.value(mode),
        );
        final resultFuture = service
            .watch('p', today: () => d(2026, 4, 10))
            .first;
        entries.emit(_regularHistory());
        final result = await resultFuture;
        expect(result, isA<ActivePrediction>(), reason: mode.name);
      }
    });

    test('no lifecycleModeFor provider keeps the exact pre-#528 behavior '
        '(tracking)', () async {
      final entries = _StubDayEntriesRepository();
      addTearDown(entries.close);
      final service = CyclePredictionService(entries);
      final resultFuture = service
          .watch('p', today: () => d(2026, 4, 10))
          .first;
      entries.emit(_regularHistory());
      final result = await resultFuture;
      expect(result, isA<ActivePrediction>());
    });

    test(
      'current() (one-shot) also suppresses for an in-effect mode',
      () async {
        final entries = _StubDayEntriesRepository()
          ..currentEntries = _regularHistory();
        addTearDown(entries.close);
        // current() reads listForProfile, not the watch stream.
        final service = CyclePredictionService(
          entries,
          lifecycleModeFor: (_) => Stream.value(LifecycleMode.pregnancy),
        );
        final result = await service.current('p', today: () => d(2026, 4, 10));
        expect(result, isA<PredictionsSuppressed>());
        expect(
          (result as PredictionsSuppressed).lifecycleMode,
          LifecycleMode.pregnancy,
        );
      },
    );

    test(
      'a mode change re-derives through the #197 memo: switching from '
      'tracking to pregnancy on unchanged entries suppresses immediately',
      () async {
        final entries = _StubDayEntriesRepository();
        addTearDown(entries.close);
        final mode = StreamController<LifecycleMode>.broadcast();
        addTearDown(mode.close);
        final service = CyclePredictionService(
          entries,
          lifecycleModeFor: (_) => mode.stream,
        );
        final seen = <CyclePrediction>[];
        final sub = service
            .watch('p', today: () => d(2026, 4, 10))
            .listen(seen.add);
        addTearDown(sub.cancel);

        mode.add(LifecycleMode.tracking);
        entries.emit(_regularHistory());
        await pumpEventQueue();
        expect(seen.last, isA<ActivePrediction>());

        // Same entries, mode switches to pregnancy: must re-derive to
        // suppressed rather than reusing the cached ActivePrediction.
        mode.add(LifecycleMode.pregnancy);
        await pumpEventQueue();
        expect(seen.last, isA<PredictionsSuppressed>());

        // Switching back to tracking on the same unchanged entries resumes
        // ordinary prediction (A2-32: "switching is free and reversible").
        mode.add(LifecycleMode.tracking);
        await pumpEventQueue();
        expect(seen.last, isA<ActivePrediction>());
      },
    );
  });
}
