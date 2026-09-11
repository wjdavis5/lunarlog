import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/observation.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/repositories/day_entries_repository.dart';

/// A [DayEntriesRepository] whose `watchForProfile` stream is entirely
/// caller-driven (issue #197): lets a test emit several ticks in a row —
/// including two carrying the exact same entries — to prove
/// [CyclePredictionService.watch] only recomputes when the cheap stamp
/// (row count + max `updatedAt`) actually changes. Every other member is
/// unused by these tests and throws if ever called.
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
    List<Observation> observationsToUpsert = const [],
    List<String> observationIdsToDelete = const [],
  }) => throw UnimplementedError();

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

DayEntry _entry(String id, LocalDate date, DateTime updatedAt) => DayEntry(
      id: id,
      profileId: 'p',
      localDate: date,
      tz: 'UTC',
      flow: FlowLevel.medium,
      updatedAt: updatedAt,
    );

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late DriftProfilesRepository profiles;
  late DriftDayEntriesRepository dayEntries;
  late CyclePredictionService service;

  final today = LocalDate(2026, 5, 20);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    profiles = DriftProfilesRepository(db.storage);
    dayEntries = DriftDayEntriesRepository(db.storage);
    service = CyclePredictionService(dayEntries);
  });

  Future<void> recordBleed(String profileId, LocalDate start, int lengthDays,
      {FlowLevel flow = FlowLevel.medium}) async {
    for (var i = 0; i < lengthDays; i++) {
      await dayEntries.save(DayEntry(
        id: '',
        profileId: profileId,
        localDate: start.addDays(i),
        tz: 'UTC',
        flow: flow,
        tags: const [],
        note: null,
        updatedAt: DateTime.utc(2026, 1, 1),
        deletedAt: null,
      ));
    }
  }

  test('AE2: backfilling an earlier period start changes derived episodes '
      'and recomputes the estimate via the stream', () async {
    final profile = await profiles.create(displayName: 'A', isMinor: false);

    final seen = <CyclePrediction>[];
    final sub = service.watch(profile.id, today: () => today).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen.first, isA<NotEnoughHistory>());

    // Two recorded episodes: a 63-day gap (invalid) then a 28-day gap.
    await recordBleed(profile.id, LocalDate(2026, 2, 1), 4);
    await recordBleed(profile.id, LocalDate(2026, 4, 5), 3);
    await recordBleed(profile.id, LocalDate(2026, 5, 3), 1);
    await pumpEventQueue();
    expect(seen.last, isA<NotEnoughHistory>(),
        reason: '63-day and 28-day gaps leave only 1 valid cycle');
    expect((seen.last as NotEnoughHistory).episodeCount, 3);

    // Backfill the missing period inside the 63-day gap.
    await recordBleed(profile.id, LocalDate(2026, 3, 4), 2);
    await pumpEventQueue();

    expect(seen.last, isA<ActivePrediction>());
    final p = seen.last as ActivePrediction;
    // Intervals now 31, 32, 28 — all valid; mean 30.33 rounds to 30.
    expect(p.averagedCycleLengths, [31, 32, 28]);
    expect(p.estimatedNextStart, LocalDate(2026, 6, 2));
    expect(p.lastEpisodeStart, LocalDate(2026, 5, 3));
    expect(p.cycleDay, 18);
    expect(p.daysUntilNextStart, 13);
  });

  test('tombstoning a bleed date recomputes the prediction (tombstones excluded)',
      () async {
    final profile = await profiles.create(displayName: 'A', isMinor: false);
    await recordBleed(profile.id, LocalDate(2026, 2, 1), 4);
    await recordBleed(profile.id, LocalDate(2026, 3, 4), 2);
    await recordBleed(profile.id, LocalDate(2026, 4, 5), 3);
    await recordBleed(profile.id, LocalDate(2026, 5, 3), 1);

    final seen = <CyclePrediction>[];
    final sub = service.watch(profile.id, today: () => today).listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen.last, isA<ActivePrediction>());
    expect((seen.last as ActivePrediction).lastEpisodeStart,
        LocalDate(2026, 5, 3));

    // The latest episode is a single day; tombstoning it removes the episode.
    await dayEntries.delete(profile.id, LocalDate(2026, 5, 3));
    await pumpEventQueue();

    expect(seen.last, isA<NotEnoughHistory>(),
        reason: 'only 2 valid cycles remain after the tombstone');
    expect((seen.last as NotEnoughHistory).episodeCount, 3);
    expect(
      (await dayEntries.listForProfile(profile.id))
          .map((e) => e.localDate)
          .contains(LocalDate(2026, 5, 3)),
      isFalse,
      reason: 'tombstoned date must not appear in domain reads',
    );
  });

  test('R3: predictions are computed per profile with no cross-talk', () async {
    final a = await profiles.create(displayName: 'A', isMinor: false);
    final b = await profiles.create(displayName: 'B', isMinor: true);

    await recordBleed(a.id, LocalDate(2026, 2, 1), 4);
    await recordBleed(a.id, LocalDate(2026, 3, 4), 2);
    await recordBleed(a.id, LocalDate(2026, 4, 5), 3);
    await recordBleed(a.id, LocalDate(2026, 5, 3), 1);

    final seenForA = <CyclePrediction>[];
    final subA = service.watch(a.id, today: () => today).listen(seenForA.add);
    addTearDown(subA.cancel);
    final seenForB = <CyclePrediction>[];
    final subB = service.watch(b.id, today: () => today).listen(seenForB.add);
    addTearDown(subB.cancel);
    await pumpEventQueue();

    expect(seenForA.last, isA<ActivePrediction>());
    expect((seenForA.last as ActivePrediction).estimatedNextStart,
        LocalDate(2026, 6, 2));
    expect(seenForB.last, isA<NotEnoughHistory>());

    // Activity under B must not move A's numbers.
    await recordBleed(b.id, LocalDate(2026, 5, 10), 5);
    await pumpEventQueue();
    expect(seenForA.last, isA<ActivePrediction>());
    expect((seenForA.last as ActivePrediction).estimatedNextStart,
        LocalDate(2026, 6, 2));
    expect((seenForB.last as NotEnoughHistory).episodeCount, 1);
  });

  test('current() computes a one-shot prediction from stored entries', () async {
    final profile = await profiles.create(displayName: 'A', isMinor: false);
    await recordBleed(profile.id, LocalDate(2026, 2, 1), 4);
    await recordBleed(profile.id, LocalDate(2026, 3, 4), 2);
    await recordBleed(profile.id, LocalDate(2026, 4, 5), 3);
    await recordBleed(profile.id, LocalDate(2026, 5, 3), 1);

    final p = await service.current(profile.id, today: () => today);
    expect(p, isA<ActivePrediction>());
    expect((p as ActivePrediction).estimatedNextStart, LocalDate(2026, 6, 2));
  });

  group('omission-aware watch (issue #132)', () {
    late DriftSettingsStore settings;
    late CyclePredictionService omissionAware;

    setUp(() {
      settings = DriftSettingsStore(db.storage);
      omissionAware = CyclePredictionService(dayEntries, settings: settings);
    });

    test('omitting a cycle through the store re-derives the estimate',
        () async {
      final profile = await profiles.create(displayName: 'A', isMinor: false);
      // Lengths 28, 28, 48, 28 (the 48-day cycle starts 2026-02-26).
      await recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await recordBleed(profile.id, LocalDate(2026, 4, 15), 4);
      await recordBleed(profile.id, LocalDate(2026, 5, 13), 4);

      final seen = <CyclePrediction>[];
      final sub =
          omissionAware.watch(profile.id, today: () => today).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(seen.last, isA<ActivePrediction>());
      // Issue #213 widened the prediction window to 12 cycles (was 3), so
      // all four lengths feed the average before omission.
      expect((seen.last as ActivePrediction).averagedCycleLengths,
          [28, 28, 48, 28]);

      await CycleExclusionList(settings)
          .omit(profile.id, LocalDate(2026, 2, 26));
      await pumpEventQueue();

      final after = seen.last as ActivePrediction;
      expect(after.averagedCycleLengths, [28, 28, 28]);
      expect(after.estimatedNextStart, LocalDate(2026, 6, 10));
    });

    test('restoring the cycle moves the estimate back', () async {
      final profile = await profiles.create(displayName: 'A', isMinor: false);
      await recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await recordBleed(profile.id, LocalDate(2026, 4, 15), 4);
      await recordBleed(profile.id, LocalDate(2026, 5, 13), 4);
      final exclusions = CycleExclusionList(settings);
      await exclusions.omit(profile.id, LocalDate(2026, 2, 26));

      final seen = <CyclePrediction>[];
      final sub =
          omissionAware.watch(profile.id, today: () => today).listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect((seen.last as ActivePrediction).estimatedNextStart,
          LocalDate(2026, 6, 10));

      await exclusions.include(profile.id, LocalDate(2026, 2, 26));
      await pumpEventQueue();
      // Issue #213 widened the prediction window to 12 cycles (was 3): all
      // four lengths average to 33.0 exactly, not the old 3-cycle 34.67.
      expect((seen.last as ActivePrediction).estimatedNextStart,
          LocalDate(2026, 6, 15));
    });

    test('current() reads the omission list too', () async {
      final profile = await profiles.create(displayName: 'A', isMinor: false);
      await recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await recordBleed(profile.id, LocalDate(2026, 4, 15), 4);
      await recordBleed(profile.id, LocalDate(2026, 5, 13), 4);
      await CycleExclusionList(settings)
          .omit(profile.id, LocalDate(2026, 2, 26));

      final p = await omissionAware.current(profile.id, today: () => today);
      expect((p as ActivePrediction).estimatedNextStart,
          LocalDate(2026, 6, 10));
    });
  });

    group('provisional seeding (issue #218)', () {
      late CyclePredictionService seeded;

      setUp(() {
        seeded = CyclePredictionService(dayEntries, profiles: profiles);
      });

      test('a profile with facts but no logged cycles gets an immediate '
          'provisional estimate', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        );

        final p = await seeded.current(profile.id, today: () => today);
        expect(p, isA<ActivePrediction>());
        final active = p as ActivePrediction;
        expect(active.tier, CycleConfidence.provisional);
        expect(active.estimatedNextStart, LocalDate(2026, 5, 18));
        expect(active.meanCycleLengthDays, 28.0);
        expect(active.meanPeriodLengthDays, 5.0);
      });

      test('watch() emits the provisional estimate and re-derives when the '
          'facts are edited (the profile-settings edit path)', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        );

        final seen = <CyclePrediction>[];
        final sub =
            seeded.watch(profile.id, today: () => today).listen(seen.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(seen.last, isA<ActivePrediction>());
        expect((seen.last as ActivePrediction).tier,
            CycleConfidence.provisional);
        expect(
            (seen.last as ActivePrediction).estimatedNextStart, LocalDate(2026, 5, 18));

        // Edit the typical cycle length the way the profile-settings seam
        // does: a whole-row update through the repository.
        await profiles.update(profile.copyWith(typicalCycleLengthDays: 30));
        await pumpEventQueue();
        expect((seen.last as ActivePrediction).estimatedNextStart,
            LocalDate(2026, 5, 20),
            reason: 'the edited answer moves the seed');
      });

      test('skipping the questions keeps NotEnoughHistory exactly as '
          'today (no-facts path bit-identical)', () async {
        final profile = await profiles.create(displayName: 'A', isMinor: false);

        final seen = <CyclePrediction>[];
        final sub =
            seeded.watch(profile.id, today: () => today).listen(seen.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();

        final none = seen.last;
        expect(none, isA<NotEnoughHistory>());
        expect((none as NotEnoughHistory).episodeCount, 0);
        expect(none.completedCycleCount, 0);
        expect(none.validCycleCount, 0);
      });

      test('a service constructed without a profiles repository never '
          'seeds, even when the profile carries facts', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        );

        final p =
            await service.current(profile.id, today: () => today);
        expect(p, isA<NotEnoughHistory>());
      });

      test('displacement: once 3 real valid cycles land, the computed '
          'result wins and provisional is never returned again', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        );

        final seen = <CyclePrediction>[];
        final sub =
            seeded.watch(profile.id, today: () => today).listen(seen.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect((seen.last as ActivePrediction).tier,
            CycleConfidence.provisional);

        // Two recorded cycles: still provisional (fewer than 3 valid).
        await recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
        await recordBleed(profile.id, LocalDate(2026, 2, 1), 4);
        await pumpEventQueue();
        expect((seen.last as ActivePrediction).tier,
            CycleConfidence.provisional,
            reason: '2 valid cycles stay below kMinCompletedValidCycles');

        // The third valid completed cycle displaces the seed: four bleed
        // starts (1/1, 2/1, 3/2, 4/1) span three valid intervals
        // (31, 29, 30), and the estimate is now computed from the logged
        // history, with no blending of the onboarding numbers.
        await recordBleed(profile.id, LocalDate(2026, 3, 2), 4);
        await recordBleed(profile.id, LocalDate(2026, 4, 1), 4);
        await pumpEventQueue();
        final active = seen.last as ActivePrediction;
        expect(active.tier, isNot(CycleConfidence.provisional));
        expect(active.averagedCycleLengths, isNotEmpty,
            reason: 'the estimate is computed from real cycle lengths');
        expect(active.validCycleCount, 3);

        // And it stays displaced when yet another cycle lands.
        await recordBleed(profile.id, LocalDate(2026, 4, 29), 4);
        await pumpEventQueue();
        expect((seen.last as ActivePrediction).tier,
            isNot(CycleConfidence.provisional));
      });

      test('an out-of-window answer is stored but never seeds '
          '(CycleFacts.canSeed gates)', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 90,
          typicalPeriodLengthDays: 5,
        );

        final p = await seeded.current(profile.id, today: () => today);
        expect(p, isA<NotEnoughHistory>());
      });

      test('a facts edit re-derives through the memo: an unrelated '
          'profile-row change does not, a changed fact does (issue #197 '
          'key extension)', () async {
        final profile = await profiles.create(
          displayName: 'A',
          isMinor: false,
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        );

        final seen = <CyclePrediction>[];
        final sub =
            seeded.watch(profile.id, today: () => today).listen(seen.add);
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(seen, hasLength(1));
        final beforeRename = seen.last;

        // An unrelated profile edit (a rename): the facts are unchanged,
        // so the memo must reuse the cached prediction object.
        await profiles.update(profile.copyWith(displayName: 'Renamed'));
        await pumpEventQueue();
        expect(identical(beforeRename, seen.last), isTrue,
            reason: 'an unchanged facts stamp must reuse the cached '
                'prediction');

        // A real facts edit must recompute.
        await profiles.update(profile.copyWith(typicalCycleLengthDays: 35));
        await pumpEventQueue();
        expect((seen.last as ActivePrediction).estimatedNextStart,
            LocalDate(2026, 5, 25),
            reason: '2026-04-20 + 35');
      });
    });

  group('memoised recomputation (issue #197)', () {
    test('two emissions carrying the same entries stamp compute the '
        'prediction once — the second reuses the same object, it does '
        'not just happen to equal it', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final memoised = CyclePredictionService(stub);

      final seen = <CyclePrediction>[];
      final sub =
          memoised.watch('p', today: () => today).listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
      ];
      stub.emit(entries);
      await pumpEventQueue();
      // A distinct List instance carrying equal rows (same count, same
      // max updatedAt) — a stubbed high-frequency emitter re-ticking with
      // nothing new, the case this memoisation targets.
      stub.emit(List.of(entries));
      await pumpEventQueue();

      expect(seen, hasLength(2),
          reason: 'the stream itself still emits on both ticks');
      expect(identical(seen[0], seen[1]), isTrue,
          reason: 'an unchanged stamp must reuse the cached prediction '
              'instead of recomputing');
    });

    test('a genuinely changed stamp does recompute', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final memoised = CyclePredictionService(stub);

      final seen = <CyclePrediction>[];
      final sub =
          memoised.watch('p', today: () => today).listen(seen.add);
      addTearDown(sub.cancel);

      stub.emit([_entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1))]);
      await pumpEventQueue();
      stub.emit([
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
        _entry('e2', LocalDate(2026, 5, 2), DateTime.utc(2026, 5, 2)),
      ]);
      await pumpEventQueue();

      expect(seen, hasLength(2));
      expect(identical(seen[0], seen[1]), isFalse,
          reason: 'a changed row count must recompute, not reuse the '
              'cached prediction');
    });

    test('omission-aware watch also memoises on (entries stamp, omission '
        'set), and recomputes when only the omission set changes',
        () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final settingsDb = LunarLogDatabase(NativeDatabase.memory());
      addTearDown(() => settingsDb.close());
      final omissionSettings = DriftSettingsStore(settingsDb.storage);
      final omissionAwareMemoised =
          CyclePredictionService(stub, settings: omissionSettings);

      final seen = <CyclePrediction>[];
      final sub = omissionAwareMemoised
          .watch('p', today: () => today)
          .listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 2, 1), DateTime.utc(2026, 2, 1)),
      ];
      stub.emit(entries);
      await pumpEventQueue();
      // Same entries stamp, re-ticked — must reuse the cached prediction.
      stub.emit(List.of(entries));
      await pumpEventQueue();
      expect(identical(seen[0], seen[1]), isTrue,
          reason: 'an unchanged (stamp, omissions) pair must reuse the '
              'cached prediction');

      // The entries stamp is unchanged, but the omission set now is —
      // this must recompute even though the entries list itself did not
      // change.
      await CycleExclusionList(omissionSettings)
          .omit('p', LocalDate(2026, 2, 1));
      await pumpEventQueue();
      expect(identical(seen.last, seen[1]), isFalse,
          reason: 'a changed omission set must recompute even when the '
              'entries stamp alone is unchanged');
    });

    test(
        'a changed flow recomputes even when row count and max updatedAt '
        'are unchanged (review follow-up: a synced edit writes the remote '
        'updatedAt verbatim, which can be older than the profile max, so '
        'the old count+max stamp alone missed it)', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final memoised = CyclePredictionService(stub);

      final seen = <CyclePrediction>[];
      final sub = memoised.watch('p', today: () => today).listen(seen.add);
      addTearDown(sub.cancel);

      final t1 = DateTime.utc(2026, 5, 1);
      final t2 = DateTime.utc(2026, 5, 2); // stays the max in both emissions
      stub.emit([
        _entry('e1', LocalDate(2026, 5, 1), t1),
        _entry('e2', LocalDate(2026, 5, 2), t2),
      ]);
      await pumpEventQueue();

      // Same ids, dates, and updatedAts (so the same count and the same
      // max) — but e1's flow changed. A synced remote edit landing with an
      // updatedAt that does not move the profile's max is exactly this
      // case, since per-row LWW writes the remote timestamp verbatim.
      stub.emit([
        DayEntry(
          id: 'e1',
          profileId: 'p',
          localDate: LocalDate(2026, 5, 1),
          tz: 'UTC',
          flow: FlowLevel.heavy,
          updatedAt: t1,
        ),
        _entry('e2', LocalDate(2026, 5, 2), t2),
      ]);
      await pumpEventQueue();

      expect(seen, hasLength(2));
      expect(identical(seen[0], seen[1]), isFalse,
          reason: 'a changed flow must recompute even when row count and '
              'max updatedAt are unchanged');
    });

    test('today advancing recomputes even with unchanged entries (review '
        'follow-up: watch documents today is evaluated per emission so '
        'subscriptions stay correct across midnight — the memo key must '
        'include it)', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final memoised = CyclePredictionService(stub);

      var currentToday = today;
      final seen = <CyclePrediction>[];
      final sub = memoised
          .watch('p', today: () => currentToday)
          .listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
      ];
      stub.emit(entries);
      await pumpEventQueue();

      currentToday = today.addDays(1);
      // A distinct List instance carrying equal rows — the entries
      // fingerprint alone is unchanged, only today advanced.
      stub.emit(List.of(entries));
      await pumpEventQueue();

      expect(seen, hasLength(2));
      expect(identical(seen[0], seen[1]), isFalse,
          reason: 'today advancing must recompute even though the entries '
              'fingerprint is unchanged');
    });
  });
}
