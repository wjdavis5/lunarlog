/// Tests for Issue #471: transactional atomic write for DayEntry and child observations
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/repositories/drift_day_entries_repository.dart';
import 'package:lunarlog/domain/models/day_entry.dart' as domain;
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart' as domain;
import 'package:lunarlog/domain/models/observation.dart' as domain;

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late FixedClock clock;
  late LunarLogStorage storage;
  late DriftDayEntriesRepository repository;

  final t0 = DateTime.utc(2026, 9, 1, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    repository = DriftDayEntriesRepository(storage);
    await storage.upsertProfile(
      id: 'p1',
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
  });

  group('LunarLogStorage.saveDayEntryWithObservations', () {
    test('commits day entry and observations atomically in one transaction', () async {
      final entry = await storage.saveDayEntryWithObservations(
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: ['cramps'],
        observationsToUpsert: [
          const UpsertObservationPayload(
            profileId: 'p1',
            localDate: '2026-09-01',
            tz: 'UTC',
            category: 'spotting',
            code: 'spotting',
          ),
          const UpsertObservationPayload(
            profileId: 'p1',
            localDate: '2026-09-01',
            tz: 'UTC',
            category: 'pain',
            code: 'cramps',
            intensity: 4,
          ),
        ],
      );

      expect(entry.profileId, 'p1');
      expect(entry.localDate, '2026-09-01');
      expect(entry.flow, FlowLevel.medium);
      expect(entry.tags, ['cramps']);
      expect(entry.dirty, isTrue);
      expect(entry.localRev, 1);

      final obsRows = await storage.getObservationsForProfile('p1');
      expect(obsRows, hasLength(2));
      for (final obs in obsRows) {
        expect(obs.dayEntryId, entry.id);
        expect(obs.dirty, isTrue);
        expect(obs.localRev, 1);
        expect(obs.deletedAt, isNull);
      }
      expect(obsRows.any((o) => o.category == 'spotting' && o.code == 'spotting'), isTrue);
      expect(obsRows.any((o) => o.category == 'pain' && o.code == 'cramps' && o.intensity == 4), isTrue);
    });

    test('soft-deletes requested observation IDs within the same transaction', () async {
      final initial = await storage.saveDayEntryWithObservations(
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.notBleeding,
        observationsToUpsert: [
          const UpsertObservationPayload(
            id: 'obs-spotting-1',
            profileId: 'p1',
            localDate: '2026-09-01',
            tz: 'UTC',
            category: 'spotting',
            code: 'spotting',
          ),
        ],
      );
      expect(initial.flow, FlowLevel.notBleeding);

      final obsBefore = await storage.getObservationsForDayEntry(initial.id);
      expect(obsBefore, hasLength(1));
      expect(obsBefore.single.id, 'obs-spotting-1');

      clock.now = t0.add(const Duration(seconds: 10));
      final updated = await storage.saveDayEntryWithObservations(
        id: initial.id,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        flow: FlowLevel.none,
        observationIdsToDelete: ['obs-spotting-1'],
      );

      expect(updated.id, initial.id);
      expect(updated.flow, FlowLevel.none);
      expect(updated.localRev, 2);

      final obsAfter = await storage.getObservationsForDayEntry(initial.id);
      expect(obsAfter, isEmpty, reason: 'live read filters tombstones');

      final rawObs = await (db.select(db.observations)..where((t) => t.id.equals('obs-spotting-1'))).getSingle();
      expect(rawObs.deletedAt, isNotNull);
      expect(rawObs.category, isNull);
      expect(rawObs.dirty, isTrue);
      expect(rawObs.localRev, 2);
    });

    test('pre-transaction validation failure throws and persists nothing', () async {
      // Invalid intensity: 99 (> 5)
      expect(
        () => storage.saveDayEntryWithObservations(
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          flow: FlowLevel.none,
          observationsToUpsert: [
            const UpsertObservationPayload(
              profileId: 'p1',
              localDate: '2026-09-01',
              tz: 'UTC',
              category: 'pain',
              code: 'migraine',
              intensity: 99,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );

      // Verify no day entry was created
      final entries = await storage.getDayEntries(profileId: 'p1');
      expect(entries, isEmpty);

      // Verify no observations were created
      final observations = await storage.getObservationsForProfile('p1');
      expect(observations, isEmpty);
    });

    test('invalid observation localDate throws and rolls back', () async {
      expect(
        () => storage.saveDayEntryWithObservations(
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          flow: FlowLevel.none,
          observationsToUpsert: [
            const UpsertObservationPayload(
              profileId: 'p1',
              localDate: 'not-a-date',
              tz: 'UTC',
              category: 'pain',
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );

      final entries = await storage.getDayEntries(profileId: 'p1');
      expect(entries, isEmpty);
    });

    test('atomic rollback when storage write throws inside transaction', () async {
      expect(await storage.getDayEntries(profileId: 'p1'), isEmpty);

      try {
        await db.transaction(() async {
          await storage.saveDayEntryWithObservations(
            profileId: 'p1',
            localDate: '2026-09-01',
            tz: 'UTC',
            flow: FlowLevel.heavy,
          );
          throw Exception('injected mid-transaction failure');
        });
      } catch (_) {}

      // Verify that DayEntry was rolled back completely
      final entries = await storage.getDayEntries(profileId: 'p1');
      expect(entries, isEmpty);
    });
  });

  group('DriftDayEntriesRepository.saveDayEntryWithObservations', () {
    test('persists domain entry and domain observations atomically', () async {
      final domainEntry = domain.DayEntry(
        id: '',
        profileId: 'p1',
        localDate: domain.LocalDate(2026, 9, 1),
        tz: 'UTC',
        flow: domain.FlowLevel.light,
        tags: ['spotting'],
        updatedAt: t0,
      );

      final saved = await repository.saveDayEntryWithObservations(
        entry: domainEntry,
        observationsToUpsert: [
          domain.Observation(
            id: '',
            dayEntryId: '',
            profileId: 'p1',
            localDate: domain.LocalDate(2026, 9, 1),
            tz: 'UTC',
            category: 'spotting',
            code: 'spotting',
            updatedAt: t0,
          ),
        ],
      );

      expect(saved.id, isNotEmpty);
      expect(saved.flow, domain.FlowLevel.light);

      final loaded = await repository.find('p1', domain.LocalDate(2026, 9, 1));
      expect(loaded, isNotNull);
      expect(loaded!.id, saved.id);

      final obs = await storage.getObservationsForDayEntry(saved.id);
      expect(obs, hasLength(1));
      expect(obs.single.category, 'spotting');
    });

    test('save delegates to saveDayEntryWithObservations without observations', () async {
      final domainEntry = domain.DayEntry(
        id: '',
        profileId: 'p1',
        localDate: domain.LocalDate(2026, 9, 2),
        tz: 'UTC',
        flow: domain.FlowLevel.heavy,
        updatedAt: t0,
      );

      final saved = await repository.save(domainEntry);
      expect(saved.id, isNotEmpty);
      expect(saved.flow, domain.FlowLevel.heavy);

      final obs = await storage.getObservationsForDayEntry(saved.id);
      expect(obs, isEmpty);
    });
  });
}
