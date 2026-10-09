import 'dart:async';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/birth_control.dart';
import 'package:lunarlog/domain/conceive.dart';
import 'package:lunarlog/domain/episodes/episodes.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/fertile_window.dart';
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
  Future<bool> hasAnyEntries(String profileId) => throw UnimplementedError();

  @override
  Stream<bool> watchHasAnyEntries(String profileId) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String profileId, LocalDate localDate) =>
      throw UnimplementedError();

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

void main() {
  group('birthControlPredictionKind classification (issue #233, #1118)', () {
    // The single source of truth for every member of the enum: a newly
    // added method cannot slip through unclassified without this failing.
    const expected = <BirthControlMethod, BirthControlPredictionKind?>{
      BirthControlMethod.pill: BirthControlPredictionKind.withdrawalBleed,
      BirthControlMethod.patch: BirthControlPredictionKind.withdrawalBleed,
      BirthControlMethod.ring: BirthControlPredictionKind.withdrawalBleed,
      BirthControlMethod.shot: BirthControlPredictionKind.continuous,
      BirthControlMethod.implant: BirthControlPredictionKind.continuous,
      BirthControlMethod.hormonalIud: BirthControlPredictionKind.continuous,
      BirthControlMethod.copperIud: null,
      BirthControlMethod.none: null,
      BirthControlMethod.condom: null,
      BirthControlMethod.other: null,
      BirthControlMethod.unknown: null,
    };

    test('classifies every BirthControlMethod', () {
      expect(
        expected.keys.toSet(),
        BirthControlMethod.values.toSet(),
        reason: 'every enum member needs an expected classification',
      );
      for (final method in BirthControlMethod.values) {
        expect(
          birthControlPredictionKind(method),
          expected[method],
          reason: method.name,
        );
      }
    });

    test('copper IUD is not period-suppressing and keeps ordinary estimates '
        '(issue #1118)', () {
      expect(
        birthControlPredictionKind(BirthControlMethod.copperIud),
        isNull,
      );
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 4, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.copperIud,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(result, isA<ActivePrediction>(),
          reason: 'a copper IUD must not pause period estimates (ACOG '
              'FAQ184: it contains no hormones and does not stop periods)');
      expect((result as ActivePrediction).basis, PredictionBasis.statistical,
          reason: 'a copper IUD keeps the ordinary ovulatory-basis estimate');
    });

    test('copper IUD with a long open cycle still reaches the late/'
        'unusually-long state, never a silent pause (issue #1118)', () {
      final result = computePrediction(
        episodes: episodesFromStarts(
            [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]),
        today: d(2026, 6, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.copperIud,
          startedOn: LocalDate(2026, 1, 1),
        ),
      );
      expect(result, isA<ActivePrediction>());
      final p = result as ActivePrediction;
      expect(p.basis, PredictionBasis.statistical);
      expect(p.unusuallyLongCycle, isTrue);
      expect(p.isLate, isTrue);
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

    test('shot also suppresses', () {
      final result = computePrediction(
        episodes: const [],
        today: d(2026, 6, 1),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.shot,
          startedOn: d(2026, 1, 1),
        ),
      );
      expect(result, isA<PredictionsSuppressed>());
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
      expect(p.basis, PredictionBasis.regimenSchedule,
          reason: 'Issue LLA-064: a pack schedule carries no ovulatory '
              'signal — fertile-window consumers must check this');
    });

    // Issue #1716: a pack profile that never logs a withdrawal bleed must
    // not read "late" forever — the regimen estimate goes stale at the same
    // bound the statistical path uses (max(4 x 28, kMinStaleHistoryDays) =
    // 120 days open for a 28-day pack).
    test('issue #1716: a never-logging pack profile goes stale at the shared '
        'bound, not late forever', () {
      final startedOn = LocalDate(2026, 1, 1);
      ActivePrediction pack(LocalDate today) => computePrediction(
            episodes: const [],
            today: today,
            birthControl: ActiveBirthControl(
              method: BirthControlMethod.pill,
              startedOn: startedOn,
            ),
          ) as ActivePrediction;

      // 120 open days (the floor) is still a long cycle, not stale.
      final atBound = pack(LocalDate(2026, 4, 30));
      expect(atBound.cycleDay, 120);
      expect(atBound.staleHistory, isFalse);

      // 121 open days is stale — the issue's 163-days-late scenario is far
      // past it.
      final past = pack(LocalDate(2026, 5, 1));
      expect(past.staleHistory, isTrue);
      expect(past.basis, PredictionBasis.regimenSchedule,
          reason: 'the stale flag does not change the basis');

      // A logged withdrawal bleed re-anchors and clears the state.
      final reAnchored = computePrediction(
        episodes: episodesFromStarts([LocalDate(2026, 4, 25)]),
        today: LocalDate(2026, 5, 1),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.pill,
          startedOn: startedOn,
        ),
      ) as ActivePrediction;
      expect(reAnchored.staleHistory, isFalse);
      expect(reAnchored.lastEpisodeStart, LocalDate(2026, 4, 25));
    });

    test(
        'Issue LLA-071: a future-dated logged bleed is never selected as the '
        'withdrawal-bleed anchor', () {
      final withoutFuture = computePrediction(
        episodes: episodesFromStarts([d(2026, 2, 1)]),
        today: d(2026, 2, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.patch,
          startedOn: LocalDate(2026, 1, 1),
        ),
      ) as ActivePrediction;

      final withFuture = computePrediction(
        episodes: episodesFromStarts([d(2026, 2, 1), d(2026, 2, 25)]),
        today: d(2026, 2, 10),
        birthControl: ActiveBirthControl(
          method: BirthControlMethod.patch,
          startedOn: LocalDate(2026, 1, 1),
        ),
      ) as ActivePrediction;

      expect(withFuture.lastEpisodeStart, withoutFuture.lastEpisodeStart);
      expect(withFuture.estimatedNextStart, withoutFuture.estimatedNextStart);
      expect(withFuture.cycleDay, greaterThan(0));
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

    test('withdrawal-bleed method with no start date and enough history '
        'carries a non-ovulatory basis: no fertile window, no conception '
        'curve (issue #1118 follow-up)', () {
      final episodes = episodesFromStarts(
          [d(2026, 1, 1), d(2026, 1, 29), d(2026, 2, 28), d(2026, 4, 1)]);
      for (final method in [
        BirthControlMethod.pill,
        BirthControlMethod.patch,
        BirthControlMethod.ring,
      ]) {
        final result = computePrediction(
          episodes: episodes,
          today: d(2026, 4, 10),
          birthControl: ActiveBirthControl(method: method, startedOn: null),
        );
        expect(result, isA<ActivePrediction>(), reason: method.name);
        final p = result as ActivePrediction;
        expect(
          p.basis,
          PredictionBasis.statisticalOnHormonalMethod,
          reason: method.name,
        );
        expect(
          currentFertileWindow(p),
          isNull,
          reason: '${method.name}: no pack anchor means no ovulatory signal',
        );
        expect(currentConceptionEstimate(p), isNull, reason: method.name);
      }
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

    test('a calendar-invalid start date degrades to the no-method path '
        'instead of throwing through the stream (issue #1718)', () async {
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

      entries.emit(const []);
      birthControl.add((
        method: BirthControlMethod.pill.toDb(),
        // Shape-valid, not a real calendar day: a hand-run sync_push (or a
        // modified client) can store this, and every pulling device must
        // keep estimating.
        startedOn: '2026-02-30',
        stoppedOn: null,
      ));
      await pumpEventQueue();

      expect(seen, isNotEmpty,
          reason: 'the stream must still emit; a throw here would take '
              'down estimates, calendar bands and reminders');
      expect(seen.last, isA<NotEnoughHistory>(),
          reason: 'the invalid date fails to the no-method path');
    });
  });
}
