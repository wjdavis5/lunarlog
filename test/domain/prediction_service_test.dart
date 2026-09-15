import 'dart:async';
import 'package:lunarlog/domain/logging/day_entry_merge_event.dart' as mergelog;

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
import 'package:lunarlog/ui/profiles/profile_controller.dart';

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

  group('onboarding facts reach createProfile (issue #530)', () {
    late CyclePredictionService seeded;
    late ProfileController controller;

    setUp(() {
      seeded = CyclePredictionService(dayEntries, profiles: profiles);
      controller = ProfileController(
        profilesRepository: profiles,
        settingsStore: DriftSettingsStore(db.storage),
      );
    });

    test(
        'a profile created through the onboarding flow\'s createProfile '
        'call, seeded with plausible last-period-start/cycle-length/'
        'period-length answers, yields a provisional-tier estimate with '
        'no logged day entries yet', () async {
      // Mirrors first_run_screen.dart's `_create()`: the cycle-questions
      // answers ride `createProfile`'s `facts:` argument rather than
      // being thrown away (the bug this issue fixes).
      final profile = await controller.createProfile(
        displayName: 'Nova',
        isMinor: false,
        facts: CycleFacts(
          lastPeriodStart: LocalDate(2026, 4, 20),
          typicalCycleLengthDays: 28,
          typicalPeriodLengthDays: 5,
        ),
      );

      // The facts must be durably on the profile row itself (not just
      // held in memory), so a later app run re-derives them the same
      // way `CyclePredictionService._factsOfProfile` does.
      final stored = await profiles.findById(profile.id);
      expect(stored!.lastPeriodStart, LocalDate(2026, 4, 20));
      expect(stored.typicalCycleLengthDays, 28);
      expect(stored.typicalPeriodLengthDays, 5);

      final p = await seeded.current(profile.id, today: () => today);
      expect(p, isA<ActivePrediction>());
      final active = p as ActivePrediction;
      expect(active.tier, CycleConfidence.provisional);
      expect(active.estimatedNextStart, LocalDate(2026, 5, 18));
      expect(active.meanCycleLengthDays, 28.0);
      expect(active.meanPeriodLengthDays, 5.0);
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

    test(
        'Issue LLA-070: a civil-date rollover recomputes with NO data '
        'emission at all -- only the injected date ticker fires, proving a '
        'long-lived subscription is not otherwise stuck until the next '
        'entries/settings change (a fake, fully test-controlled ticker, '
        'never a real timer or sleep)', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final ticker = StreamController<void>();
      addTearDown(ticker.close);
      final memoised = CyclePredictionService(stub, dateTicker: () => ticker.stream);

      var currentToday = today;
      final seen = <CyclePrediction>[];
      final sub =
          memoised.watch('p', today: () => currentToday).listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
      ];
      // Both the entries stream and the injected ticker must fire once
      // before the first combined emission -- matching every other
      // combine source's "replay on listen" convention, which the fake
      // ticker here does not get for free (unlike the real one).
      ticker.add(null);
      stub.emit(entries);
      await pumpEventQueue();
      expect(seen, hasLength(1));

      // The civil date advances; NEITHER entries NOR settings emit
      // anything -- only the ticker fires.
      currentToday = today.addDays(1);
      ticker.add(null);
      await pumpEventQueue();

      expect(seen, hasLength(2));
      expect(identical(seen[0], seen[1]), isFalse,
          reason: 'the tick alone, with no data emission whatsoever, must '
              'still recompute against the new today');
    });

    test(
        'a tick with today unchanged still re-emits (combineLatest fires on '
        'every source event) but reuses the cached prediction instance -- '
        'the #197 memo, not the ticker, is what keeps a same-day tick from '
        'wasting a real recompute', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final ticker = StreamController<void>();
      addTearDown(ticker.close);
      final memoised = CyclePredictionService(stub, dateTicker: () => ticker.stream);

      final seen = <CyclePrediction>[];
      final sub = memoised.watch('p', today: () => today).listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
      ];
      ticker.add(null);
      stub.emit(entries);
      await pumpEventQueue();
      expect(seen, hasLength(1));

      ticker.add(null); // same today, no entries/settings change
      await pumpEventQueue();

      expect(seen, hasLength(2));
      expect(identical(seen[0], seen[1]), isTrue,
          reason: 'nothing about the memo key actually changed');
    });

    test(
        'Issue LLA-070 (review round 1): CyclePredictionService.watch wired '
        'to the REAL dateRolloverTicker does not re-emit at all on repeated '
        'same-day polls -- only a genuine date change reaches the combine, '
        'so ReminderCoordinator (and both publishers) never replan/republish '
        'on every poll', () async {
      final stub = _StubDayEntriesRepository();
      addTearDown(stub.close);
      final polls = StreamController<void>();
      addTearDown(polls.close);
      var currentToday = today;
      final memoised = CyclePredictionService(
        stub,
        dateTicker: () => dateRolloverTicker(
          today: () => currentToday,
          ticks: polls.stream,
        ),
      );

      final seen = <CyclePrediction>[];
      final sub =
          memoised.watch('p', today: () => currentToday).listen(seen.add);
      addTearDown(sub.cancel);

      final entries = [
        _entry('e1', LocalDate(2026, 5, 1), DateTime.utc(2026, 5, 1)),
      ];
      stub.emit(entries);
      await pumpEventQueue();
      expect(seen, hasLength(1));

      // Several same-day polls: dateRolloverTicker itself must swallow
      // these -- no additional emission reaches watch()'s combine at all,
      // let alone a recompute.
      polls.add(null);
      polls.add(null);
      polls.add(null);
      await pumpEventQueue();
      expect(seen, hasLength(1),
          reason: 'a same-day poll must never reach the prediction stream');

      // The civil day actually rolls over.
      currentToday = today.addDays(1);
      polls.add(null);
      await pumpEventQueue();

      expect(seen, hasLength(2),
          reason: 'a genuine date change still recomputes');
      expect(identical(seen[0], seen[1]), isFalse);

      // Further same-day polls after the rollover: still nothing extra.
      polls.add(null);
      polls.add(null);
      await pumpEventQueue();
      expect(seen, hasLength(2));
    });

    test(
        'issue #225: emits PredictionsDisabled when predictions are disabled '
        'in settings, and restores prediction when re-enabled without data loss',
        () async {
      final settings = DriftSettingsStore(db.storage);
      final serviceWithSettings = CyclePredictionService(
        dayEntries,
        settings: settings,
      );

      final profile = await profiles.create(displayName: 'A', isMinor: false);

      // Create 3 valid completed cycles.
      await recordBleed(profile.id, LocalDate(2026, 1, 1), 4);
      await recordBleed(profile.id, LocalDate(2026, 1, 29), 4);
      await recordBleed(profile.id, LocalDate(2026, 2, 26), 4);
      await recordBleed(profile.id, LocalDate(2026, 3, 26), 4);

      final seen = <CyclePrediction>[];
      final sub = serviceWithSettings
          .watch(profile.id, today: () => LocalDate(2026, 4, 1))
          .listen(seen.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      expect(seen.last, isA<ActivePrediction>());
      final active = seen.last as ActivePrediction;
      expect(active.meanCycleLengthDays, 28);

      // Disable predictions in settings.
      await settings.set(predictionsEnabledSettingKey(profile.id), 'false');
      await pumpEventQueue();

      expect(seen.last, isA<PredictionsDisabled>());
      final currentPrediction = await serviceWithSettings.current(
        profile.id,
        today: () => LocalDate(2026, 4, 1),
      );
      expect(currentPrediction, isA<PredictionsDisabled>());

      // Re-enable predictions in settings.
      await settings.set(predictionsEnabledSettingKey(profile.id), 'true');
      await pumpEventQueue();

      expect(seen.last, isA<ActivePrediction>());
      final restored = seen.last as ActivePrediction;
      expect(restored.meanCycleLengthDays, 28);
    });
  });

  group('dateRolloverTicker (issue LLA-070, review round 1)', () {
    test(
        'many polls that all land on the same day emit only the initial '
        'tick; a poll that crosses midnight emits again', () async {
      final polls = StreamController<void>();
      addTearDown(polls.close);
      var currentToday = LocalDate(2026, 5, 1);
      var tickCount = 0;
      final sub = dateRolloverTicker(
        today: () => currentToday,
        ticks: polls.stream,
      ).listen((_) => tickCount++);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(tickCount, 1, reason: 'the immediate initial tick');

      // Many polls, still the same day: no re-tick.
      polls.add(null);
      polls.add(null);
      polls.add(null);
      await pumpEventQueue();
      expect(tickCount, 1,
          reason: 'same-day polls must never produce a second tick');

      // The civil day rolls over.
      currentToday = currentToday.addDays(1);
      polls.add(null);
      await pumpEventQueue();
      expect(tickCount, 2, reason: 'a genuine date change ticks again');

      // Further same-day polls after the rollover: still nothing extra.
      polls.add(null);
      polls.add(null);
      await pumpEventQueue();
      expect(tickCount, 2);

      // A second rollover ticks a third time.
      currentToday = currentToday.addDays(1);
      polls.add(null);
      await pumpEventQueue();
      expect(tickCount, 3);
    });

    test('with no ticks stream injected, the default real Stream.periodic '
        'is used but this test never waits on it -- only the immediate '
        'tick is observed here, proving the default does not block',
        () async {
      var tickCount = 0;
      final sub = dateRolloverTicker(
        today: () => LocalDate(2026, 5, 1),
      ).listen((_) => tickCount++);
      addTearDown(sub.cancel);

      await pumpEventQueue();
      expect(tickCount, 1);
    });
  });
}
