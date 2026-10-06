/// The device's memory of deleted health-store records (Issue #1561),
/// against a real database: which deletions the storage layer remembers,
/// which it does not, and what clears the memory.
///
/// The rule being pinned: a record is remembered at the moment its row
/// stops being live by a deletion of that row. Removing a source's imported
/// data is not that, and neither is the echo of a deletion this device
/// already made.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/domain/health/health_import_deletions.dart';

class _Clock {
  _Clock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late _Clock clock;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 9, 1, 8);
  final t1 = DateTime.utc(2026, 9, 2, 8);
  final t2 = DateTime.utc(2026, 9, 3, 8);
  const date = '2026-08-01';
  final hk = healthImportDeletionId('healthkit', 'rec-1');
  final spot = healthImportDeletionId('apple_health', 'spot-1');

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = _Clock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    for (final id in ['p1', 'p10']) {
      await storage.upsertProfile(
        id: id,
        displayName: 'Riley',
        isMinor: true,
        updatedAt: t0,
      );
    }
  });

  Future<Map<String, DateTime>> remembered([String profileId = 'p1']) =>
      storage.readHealthImportDeletions(profileId);

  Future<DayEntry> importedDay({
    String profileId = 'p1',
    String localDate = date,
    String source = 'healthkit',
    String? sourceId = 'rec-1',
  }) =>
      storage.upsertDayEntry(
        profileId: profileId,
        localDate: localDate,
        tz: 'UTC',
        flow: FlowLevel.heavy,
        source: source,
        sourceId: sourceId,
        updatedAt: t0,
      );

  Future<Observation> importedSpotting(
    DayEntry day, {
    String source = 'apple_health',
    String? sourceId = 'spot-1',
  }) =>
      storage.upsertObservation(
        dayEntryId: day.id,
        profileId: day.profileId,
        localDate: day.localDate,
        tz: 'UTC',
        category: 'spotting',
        code: 'spotting',
        source: source,
        sourceId: sourceId,
        updatedAt: t0,
      );

  RemoteDayEntryRow remoteDay(
    DayEntry row, {
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      RemoteDayEntryRow(
        id: row.id,
        profileId: row.profileId,
        localDate: row.localDate,
        tz: row.tz,
        flow: deletedAt == null ? row.flow : FlowLevel.none,
        tags: const [],
        note: null,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        source: row.source,
        sourceId: row.sourceId,
      );

  RemoteObservationRow remoteSpotting(
    Observation row, {
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      RemoteObservationRow(
        id: row.id,
        dayEntryId: row.dayEntryId,
        profileId: row.profileId,
        localDate: row.localDate,
        tz: row.tz,
        category: deletedAt == null ? 'spotting' : null,
        code: deletedAt == null ? 'spotting' : null,
        source: row.source,
        sourceId: row.sourceId,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  group('a deletion made on this device', () {
    test('nothing is remembered while the day is live', () async {
      await importedDay();
      expect(await remembered(), isEmpty);
    });

    test('deleting an imported day remembers its record, with the moment '
        'the row was deleted', () async {
      await importedDay();
      clock.now = t1;
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);

      final row = (await storage.findDayEntryBySource(
        profileId: 'p1',
        source: 'healthkit',
        sourceId: 'rec-1',
      ))!;
      expect(await remembered(), {hk: row.deletedAt});
      expect(row.deletedAt, t1);
      // Another profile's memory is its own, and `p1` is not a prefix of
      // `p10` as far as the keys go.
      expect(await remembered('p10'), isEmpty);
    });

    test('a day she logged herself, and a day that is not there, leave '
        'nothing behind', () async {
      await importedDay(source: 'manual', sourceId: null);
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      await storage.softDeleteDayEntry(
        profileId: 'p1',
        localDate: '2026-08-02',
      );
      expect(await remembered(), isEmpty);
    });

    test('a day from a file import is not a health-store record', () async {
      await importedDay(source: 'clue_import', sourceId: 'clue-1');
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      expect(await remembered(), isEmpty);
    });

    test('deleting the day remembers the imported entries on it', () async {
      final day = await importedDay(source: 'manual', sourceId: null);
      await importedSpotting(day);
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      expect((await remembered()).keys, [spot]);
    });

    // The day sheet removes one entry from a day by saving the day with the
    // entry's id in `observationIdsToDelete`. The review of the first
    // design found this path remembered nothing.
    test('removing one imported entry through the day sheet\'s save '
        'remembers it', () async {
      final day = await importedDay(source: 'manual', sourceId: null);
      final spotting = await importedSpotting(day);
      final handLogged = await importedSpotting(
        day,
        source: 'manual',
        sourceId: null,
      );
      clock.now = t1;
      await storage.saveDayEntryWithObservations(
        id: day.id,
        profileId: 'p1',
        localDate: date,
        tz: 'UTC',
        flow: FlowLevel.heavy,
        observationIdsToDelete: [spotting.id, handLogged.id],
      );
      expect(await remembered(), {spot: t1});

      // Removing it again, or one that is not held, adds nothing and does
      // not move the time.
      clock.now = t2;
      await storage.softDeleteObservation(spotting.id);
      await storage.softDeleteObservation('no-such-entry');
      expect(await remembered(), {spot: t1});
    });
  });

  group('a deletion that arrives by sync', () {
    test('a live imported day deleted on another device is remembered',
        () async {
      final day = await importedDay();
      await storage.applyRemoteDayEntry(
        remoteDay(day, updatedAt: t1, deletedAt: t1),
      );
      expect(await storage.getDayEntry(profileId: 'p1', localDate: date),
          isNull);
      expect(await remembered(), {hk: t1});
    });

    test('a day that arrives already deleted is remembered', () async {
      await storage.applyRemoteDayEntry(
        RemoteDayEntryRow(
          id: 'never-seen-live',
          profileId: 'p1',
          localDate: date,
          tz: 'UTC',
          flow: FlowLevel.none,
          tags: const [],
          note: null,
          updatedAt: t1,
          deletedAt: t1,
          source: 'healthkit',
          sourceId: 'rec-1',
        ),
      );
      expect(await remembered(), {hk: t1});
    });

    test('the echo of this device\'s own deletion does not move its time',
        () async {
      final day = await importedDay();
      clock.now = t1;
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      await storage.applyRemoteDayEntry(
        remoteDay(day, updatedAt: t2, deletedAt: t2),
      );
      expect(await remembered(), {hk: t1});
    });

    // What lets an import after "Remove imported data" bring the days
    // back: the server's copy of the removal lands on rows this device
    // has already deleted.
    test('the echo of this device\'s own removal of imported data is not '
        'remembered', () async {
      final day = await importedDay();
      final spotting = await importedSpotting(day);
      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: 'healthkit',
      );
      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: 'apple_health',
      );
      await storage.applyRemoteRows([
        remoteDay(day, updatedAt: t1, deletedAt: t1),
        remoteSpotting(spotting, updatedAt: t1, deletedAt: t1),
      ]);
      expect(await remembered(), isEmpty);
    });

    test('a live copy, and a deletion older than the local row, change '
        'nothing', () async {
      final day = await importedDay();
      await storage.applyRemoteDayEntry(remoteDay(day, updatedAt: t1));
      expect(await remembered(), isEmpty);

      // The local row is newer than the server's deletion, so the server's
      // copy is not applied and the day stays live.
      await storage.upsertDayEntry(
        id: day.id,
        profileId: 'p1',
        localDate: date,
        tz: 'UTC',
        flow: FlowLevel.light,
        source: 'healthkit',
        sourceId: 'rec-1',
        updatedAt: t2,
      );
      await storage.applyRemoteDayEntry(
        remoteDay(day, updatedAt: t1, deletedAt: t1),
      );
      expect(await storage.getDayEntry(profileId: 'p1', localDate: date),
          isNotNull);
      expect(await remembered(), isEmpty);
    });

    test('an imported entry deleted on another device is remembered, in a '
        'page as well as one row at a time', () async {
      final day = await importedDay(source: 'manual', sourceId: null);
      final spotting = await importedSpotting(day);
      await storage.applyRemoteRows([
        remoteSpotting(spotting, updatedAt: t1, deletedAt: t1),
      ]);
      expect(await remembered(), {spot: t1});

      // Arriving already deleted.
      await storage.applyRemoteObservation(
        RemoteObservationRow(
          id: 'never-seen-live',
          dayEntryId: day.id,
          profileId: 'p1',
          localDate: date,
          tz: 'UTC',
          source: 'apple_health',
          sourceId: 'spot-2',
          updatedAt: t2,
          deletedAt: t2,
        ),
      );
      expect(await remembered(), {
        spot: t1,
        healthImportDeletionId('apple_health', 'spot-2'): t2,
      });
    });

    test('a live copy of an entry, and the echo of a deletion made here, '
        'change nothing', () async {
      final day = await importedDay(source: 'manual', sourceId: null);
      final spotting = await importedSpotting(day);
      await storage.applyRemoteObservation(
        remoteSpotting(spotting, updatedAt: t1),
      );
      expect(await remembered(), isEmpty);

      clock.now = t1.add(const Duration(hours: 1));
      await storage.softDeleteObservation(spotting.id);
      final at = (await remembered())[spot];
      await storage.applyRemoteObservation(
        remoteSpotting(spotting, updatedAt: t2, deletedAt: t2),
      );
      expect(await remembered(), {spot: at});
    });
  });

  group('what clears it', () {
    Future<void> deleteThree() async {
      final day = await importedDay();
      await importedSpotting(day);
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      await importedDay(
        localDate: '2026-08-02',
        source: 'health_connect',
        sourceId: 'hc-1@5',
      );
      await storage.softDeleteDayEntry(
        profileId: 'p1',
        localDate: '2026-08-02',
      );
    }

    test('removing a source\'s imported data forgets that source and no '
        'other, and its own deleted rows are not remembered', () async {
      await deleteThree();
      final hc = healthImportDeletionId('health_connect', 'hc-1@5');
      expect((await remembered()).keys, unorderedEquals([hk, spot, hc]));

      // A live day of the source being removed.
      await importedDay(localDate: '2026-08-03', sourceId: 'rec-9');
      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: 'healthkit',
      );
      expect((await remembered()).keys, unorderedEquals([spot, hc]));
      expect(
        (await storage.findDayEntryBySource(
          profileId: 'p1',
          source: 'healthkit',
          sourceId: 'rec-9',
        ))!
            .deletedAt,
        isNotNull,
      );

      // A source whose name begins another's does not take it along.
      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: 'health',
      );
      expect((await remembered()).keys, unorderedEquals([spot, hc]));
    });

    test('the import forgets the records it names, and only those', () async {
      await deleteThree();
      await storage.forgetHealthImportDeletions('p1', [hk, 'healthkit|other']);
      expect((await remembered()).keys, hasLength(2));
      expect((await remembered()).keys, isNot(contains(hk)));
      await storage.forgetHealthImportDeletions('p1', const []);
      expect((await remembered()).keys, hasLength(2));
    });

    test('a profile wiped from this device takes its memory with it, and '
        'leaves another profile\'s alone', () async {
      await deleteThree();
      await importedDay(profileId: 'p10', sourceId: 'rec-7');
      await storage.softDeleteDayEntry(profileId: 'p10', localDate: date);

      await storage.applyLocalProfilePurge('p1');
      expect(await remembered(), isEmpty);
      expect((await remembered('p10')).keys, [
        healthImportDeletionId('healthkit', 'rec-7'),
      ]);
    });
  });

  test('a value that is not a time still reads as a deleted record', () async {
    await storage.setSetting(
      key: 'health_import_deleted_p1|healthkit|rec-1',
      value: 'not a number',
    );
    expect(await remembered(), {
      hk: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    });
  });

  test('other settings are not read as deleted records', () async {
    await storage.setSetting(key: 'health_import_deleted_p1', value: '{}');
    await storage.setSetting(key: 'health_import_deletedXp1|a|b', value: '1');
    await storage.setSetting(key: 'health_store_profile_id', value: 'p1');
    expect(await remembered(), isEmpty);
  });
}
