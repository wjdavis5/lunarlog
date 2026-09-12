import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

LocalDate d(int y, int m, int day) => LocalDate(y, m, day);

List<Episode> episodesFromStarts(List<LocalDate> starts, [int length = 4]) => [
      for (final start in starts) Episode(start, start.addDays(length - 1)),
    ];

/// A caller-driven day-entry stream for the service tests below.
class _StubDayEntriesRepository implements DayEntriesRepository {
  final _controller = StreamController<List<DayEntry>>.broadcast();

  void emit(List<DayEntry> entries) => _controller.add(entries);

  Future<void> close() => _controller.close();

  @override
  Stream<List<DayEntry>> watchForProfile(
    String profileId, {
    LocalDate? from,
    LocalDate? to,
  }) =>
      _controller.stream;

  @override
  Future<DayEntry> save(DayEntry entry) => throw UnimplementedError();

  @override
  Future<DayEntry> saveDayEntryWithObservations({
    required DayEntry entry,
    List<Object?> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<DayEntry?> find(String profileId, LocalDate localDate) =>
      throw UnimplementedError();

  @override
  Future<List<DayEntry>> listForProfile(String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      throw UnimplementedError();
}

void main() {
  group('birthControlPredictionKind classification (issue #233)', () {
    test('withdrawal-bleed / cyclic methods classify as pack-driven', () {
      expect(
        birthControlPredictionKind(BirthControlMethod.pill),
        BirthControlPredictionKind.withdrawalBleed,
      );
      expect(
        birthControlPredictionKind(BirthControlMethod.patch),
        BirthControlPredictionKind.withdrawalBleed,
      );
      expect(
        birthControlPredictionKind(BirthControlMethod.ring),
        BirthControlPredictionKind.withdrawalBleed,
      );
    });

    test('continuous methods classify as continuous', () {
      for (final method in [
        BirthControlMethod.shot,
        BirthControlMethod.implant,
        BirthControlMethod.hormonalIud,
        BirthControlMethod.copperIud,
      ]) {
        expect(
          birthControlPredictionKind(method),
          BirthControlPredictionKind.continuous,
          reason: method.name,
        );
      }
    });

    test('non-tracked answers classify as null (never reach the predictor)', () {
      for (final method in [
        BirthControlMethod.none,
        BirthControlMethod.condom,
        BirthControlMethod.other,
        BirthControlMethod.unknown,
      ]) {
        expect(birthControlPredictionKind(method), isNull, reason: method.name);
      }
    });
  });

  group('continuous methods suppress period prediction (issue #233)', () {
    test('IUD with no bleeds -> explicit PredictionsSuppressed, never '
        'NotEnoughHistory', () {
      final result = computePrediction(
        episodes: const [],
        today: d(2026, 6, 1),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.hormonalIud,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(result, isA<PredictionsSuppressed>());
      expect(result, isNot(isA<NotEnoughHistory>()));
      expect((result as PredictionsSuppressed).method,
          BirthControlMethod.hormonalIud);
      expect(result.statusLabel, contains('predictions suppressed'));
    });

    test('implant suppresses even with a full valid history', () {
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.implant,
          startedOn: LocalDate(2026, 3, 1),
        ),
      );
      expect(result, isA<PredictionsSuppressed>());
    });

    test('shot and copper IUD also suppress', () {
      for (final method in [
        BirthControlMethod.shot,
        BirthControlMethod.copperIud,
      ]) {
        final result = computePrediction(
          episodes: const [],
          today: d(2026, 6, 1),
          birthControl: ActiveBirthControl(
            method: method,
            startedOn: d(2026, 1, 1),
          ),
        );
        expect(result, isA<PredictionsSuppressed>(), reason: method.name);
      }
    });
  });

  group('withdrawal-bleed methods predict from the pack schedule '
      '(issue #233)', () {
    test('pill with no logged bleeds anchors on the regimen start + 28 days',
        () {
      final result = computePrediction(
        episodes: const [],
        today: d(2026, 1, 15),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(result, isA<ActivePrediction>());
      final p = result as ActivePrediction;
      expect(p.lastEpisodeStart, d(2026, 1, 1));
      expect(p.estimatedNextStart, d(2026, 1, 29));
      expect(p.meanCycleLengthDays, 28.0);
      expect(p.tier, CycleConfidence.high);
      expect(p.spreadDays, 0);
      expect(p.averagedCycleLengths, isEmpty);
    });

    test('patch anchors on the most recent bleed logged on/after the start',
        () {
      final result = computePrediction(
        episodes: episodesFromStarts([d(2026, 2, 1)]),
        today: d(2026, 2, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.patch,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      final p = result as ActivePrediction;
      expect(p.lastEpisodeStart, d(2026, 2, 1));
      expect(p.estimatedNextStart, d(2026, 3, 1));
    });

    test('a bleed logged before the regimen start is not treated as a '
        'withdrawal bleed', () {
      final result = computePrediction(
        episodes: episodesFromStarts([d(2025, 12, 1)]),
        today: d(2026, 1, 15),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.ring,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      final p = result as ActivePrediction;
      expect(p.lastEpisodeStart, d(2026, 1, 1),
          reason: 'the pre-regimen bleed must not anchor the pack cadence');
      expect(p.estimatedNextStart, d(2026, 1, 29));
    });

    test('a late pack-driven estimate rolls forward in whole pack-length '
        'steps', () {
      final result = computePrediction(
        episodes: const [],
        today: d(2026, 2, 20),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      final p = result as ActivePrediction;
      expect(p.originalEstimatedNextStart, d(2026, 1, 29));
      expect(p.estimatedNextStart, d(2026, 2, 26),
          reason: '2026-01-29 + one 28-day pack length');
      expect(p.isLate, isTrue);
    });

    test('withdrawal-bleed method with no recorded start falls back to the '
        'history-based path (no pack anchor)', () {
      final result = computePrediction(
        episodes: const [],
        today: d(2026, 6, 1),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: null,
        ),
      );
      expect(result, isA<NotEnoughHistory>());
    });
  });

  group('method switch / clear re-enables appropriate behavior (issue #233)',
      () {
    final episodes = episodesFromStarts(
        [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]);
    final today = d(2026, 4, 10);

    test('switching continuous -> withdrawal-bleed yields a pack-driven '
        'estimate on the same history', () {
      final suppressed = computePrediction(
        episodes: episodes,
        today: today,
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.shot,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(suppressed, isA<PredictionsSuppressed>());

      final reEnabled = computePrediction(
        episodes: episodes,
        today: today,
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(reEnabled, isA<ActivePrediction>());
    });

    test('clearing the method returns the ordinary history-based predictor '
        'without requiring new history', () {
      final withMethod = computePrediction(
        episodes: episodes,
        today: today,
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.implant,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(withMethod, isA<PredictionsSuppressed>());

      // Cleared (null) -> the same logged history is usable as before and
      // yields an ActivePrediction (3 valid cycles).
      final cleared = computePrediction(
        episodes: episodes,
        today: today,
        birthControl: null,
      );
      expect(cleared, isA<ActivePrediction>());
      expect((cleared as ActivePrediction).estimatedNextStart, d(2026, 5, 1));
    });
  });

  group('service wiring re-derives on a birth-control state change '
      '(issue #233)', () {
    test('a provider change from none to continuous -> suppressed; to '
        'withdrawal-bleed -> pack-driven; cleared -> history again', () async {
      final entries = _StubDayEntriesRepository();
      final birthControl = StreamController<BirthControlState?>.broadcast();
      final service = CyclePredictionService(
        entries,
        birthControlStateFor: (_) => birthControl.stream,
      );
      final seen = <CyclePrediction>[];
      final sub = service.watch('p', today: () => d(2026, 6, 1)).listen(seen.add);
      addTearDown(sub.cancel);
      addTearDown(birthControl.close);
      addTearDown(entries.close);

      // Kick the day-entry source once (broadcast, no replay) so the
      // combine triple can emit; it then stays empty across the steps.
      entries.emit(const []);

      // No method in effect -> NotEnoughHistory.
      birthControl.add(null);
      await pumpEventQueue();
      expect(seen.last, isA<NotEnoughHistory>());

      // Continuous method (IUD) -> suppressed.
      birthControl.add((
        method: BirthControlMethod.hormonalIud.toDb(),
        startedOn: '2026-01-01',
        stoppedOn: null,
      ));
      await pumpEventQueue();
      expect(seen.last, isA<PredictionsSuppressed>());

      // Withdrawal-bleed method (pill) -> pack-driven estimate.
      birthControl.add((
        method: BirthControlMethod.pill.toDb(),
        startedOn: '2026-01-01',
        stoppedOn: null,
      ));
      await pumpEventQueue();
      expect(seen.last, isA<ActivePrediction>());
      final packDriven = seen.last as ActivePrediction;
      expect(packDriven.meanCycleLengthDays, 28.0,
          reason: 'pack-schedule-driven, anchored on the regimen start');
      // The estimate is anchored on 2026-01-01 + 28 days and rolled forward
      // in whole pack-length steps (issue #221 never-silent posture) because
      // today (2026-06-01) is well past it — it must sit on the 28-day
      // cadence and near-term, never freeze far in the past.
      expect(
        packDriven.originalEstimatedNextStart,
        d(2026, 1, 29),
      );
      expect(
        packDriven.estimatedNextStart.difference(d(2026, 1, 29)) % 28,
        0,
      );
      expect(packDriven.daysUntilNextStart, inInclusiveRange(0, 30));

      // Clearing the method returns the ordinary predictor (NotEnoughHistory
      // again — no logged cycles) without needing fresh history.
      birthControl.add(null);
      await pumpEventQueue();
      expect(seen.last, isA<NotEnoughHistory>());
    });
  });
}
