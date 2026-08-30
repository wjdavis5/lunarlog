import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';

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
}
