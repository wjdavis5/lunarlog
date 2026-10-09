/// The device's memory of health-store records she deleted (Issue #1561),
/// against a real database: which deletions the storage layer remembers,
/// which it does not, and what clears the memory.
///
/// The rule being pinned: a record is remembered when she deletes its row
/// on this phone, a day or one entry on a day, and at no other time.
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

  // A deletion that arrives by sync is not remembered. Removing a store's
  // imported data sends deletions to every device too, and nothing in a row
  // tells that from a day someone deleted; remembering either would stop a
  // later import from bringing the data back, with no way to undo it on
  // this phone. Telling the two apart needs the server's help (#1576).
  group('a deletion that arrives by sync is not remembered', () {
    test('a live imported day deleted on another device', () async {
      final day = await importedDay();
      await storage.applyRemoteDayEntry(
        remoteDay(day, updatedAt: t1, deletedAt: t1),
      );
      expect(await storage.getDayEntry(profileId: 'p1', localDate: date),
          isNull);
      expect(await remembered(), isEmpty);
    });

    test('a day that arrives already deleted', () async {
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
      expect(await remembered(), isEmpty);
    });

    test('an imported entry, in a page as well as one row at a time',
        () async {
      final day = await importedDay(source: 'manual', sourceId: null);
      final spotting = await importedSpotting(day);
      await storage.applyRemoteRows([
        remoteSpotting(spotting, updatedAt: t1, deletedAt: t1),
      ]);
      final other = await importedSpotting(day, sourceId: 'spot-2');
      await storage.applyRemoteObservation(
        remoteSpotting(other, updatedAt: t1, deletedAt: t1),
      );
      expect(await remembered(), isEmpty);
    });

    test('and one that she had deleted here keeps the moment she did',
        () async {
      final day = await importedDay();
      clock.now = t1;
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      await storage.applyRemoteDayEntry(
        remoteDay(day, updatedAt: t2, deletedAt: t2),
      );
      expect(await remembered(), {hk: t1});
    });
  });

  group('what clears it', () {
    final hc = healthImportDeletionId('health_connect', 'hc-1@5');

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

    // On an iPhone the days carry `healthkit` and the entries on them
    // `apple_health`. Removing the days (`healthkit`) is a clean slate for
    // the whole store — the server cascades the entries on those days — so
    // both sources' memories go. Removing the measurements (`apple_health`)
    // touches no day, so only its own memory goes (Issue #1587 item 5: it
    // used to clear `healthkit`'s too, so a day she had deleted came back
    // on the next import).
    for (final (named, remaining) in [
      ('healthkit', [hc]),
      ('apple_health', [hk, hc]),
    ]) {
      test('removing Apple Health\'s imported data, named as $named, '
          'forgets what she deleted with it and nothing else', () async {
        await deleteThree();
        expect((await remembered()).keys, unorderedEquals([hk, spot, hc]));

        await storage.applyLocalImportedDataPurge(
          profileId: 'p1',
          source: named,
        );
        expect((await remembered()).keys, unorderedEquals(remaining));
      });
    }

    test('removing Health Connect\'s forgets Health Connect\'s alone, and '
        'the rows the removal deletes are not remembered', () async {
      await deleteThree();
      // A live day of the source being removed.
      await importedDay(
        localDate: '2026-08-03',
        source: 'health_connect',
        sourceId: 'hc-9@5',
      );
      await storage.applyLocalImportedDataPurge(
        profileId: 'p1',
        source: 'health_connect',
      );
      expect((await remembered()).keys, unorderedEquals([hk, spot]));
      expect(
        (await storage.findDayEntryBySource(
          profileId: 'p1',
          source: 'health_connect',
          sourceId: 'hc-9@5',
        ))!
            .deletedAt,
        isNotNull,
      );
    });

    test('removing a file import\'s data, or a source whose name begins '
        'another\'s, forgets nothing', () async {
      await deleteThree();
      for (final source in ['clue_import', 'health', 'apple']) {
        await storage.applyLocalImportedDataPurge(
          profileId: 'p1',
          source: source,
        );
      }
      expect((await remembered()).keys, unorderedEquals([hk, spot, hc]));
    });

    test('the import forgets a record only while it still carries the '
        'moment the import read', () async {
      await deleteThree();
      final read = await remembered();

      // Deleted again since the import read it: a new moment, and kept.
      await importedDay();
      clock.now = t2;
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);

      await storage.forgetHealthImportDeletions('p1', {
        hk: read[hk]!,
        spot: read[spot]!,
        'healthkit|never-remembered': t0,
      });
      expect(await remembered(), {hk: t2, hc: read[hc]});

      await storage.forgetHealthImportDeletions('p1', const {});
      expect((await remembered()).keys, unorderedEquals([hk, hc]));
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

  group('an undo, and a row going live again (Issue #1587)', () {
    test('an undo removes the day without remembering the store records '
        'on it — an import may bring them back', () async {
      final day = await importedDay();
      await importedSpotting(day);
      clock.now = t1;
      await storage.softDeleteDayEntryForUndo(
        profileId: 'p1',
        localDate: date,
      );

      // The same tombstones the ordinary delete writes...
      final row = (await storage.findDayEntryBySource(
        profileId: 'p1',
        source: 'healthkit',
        sourceId: 'rec-1',
      ))!;
      expect(row.deletedAt, t1);
      // ...but no memory: the case where Undo used to shadow a record
      // nobody deleted.
      expect(await remembered(), isEmpty);
    });

    test('saving a remembered record live again forgets it — the undo '
        'saved back, no import pass needed', () async {
      final day = await importedDay();
      clock.now = t1;
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      expect((await remembered()).keys, [hk]);

      // The day sheet's Undo saves the same row back.
      await storage.upsertDayEntry(
        id: day.id,
        profileId: 'p1',
        localDate: date,
        tz: 'UTC',
        flow: FlowLevel.heavy,
        source: 'healthkit',
        sourceId: 'rec-1',
        updatedAt: t2,
      );
      expect(await remembered(), isEmpty);

      // And deleting it again is remembered anew.
      await storage.softDeleteDayEntry(profileId: 'p1', localDate: date);
      expect((await remembered()).keys, [hk]);
    });

    test('an observation saved live again forgets its record too', () async {
      final day = await importedDay();
      final spotting = await importedSpotting(day);
      clock.now = t1;
      await storage.softDeleteObservation(spotting.id);
      expect((await remembered()).keys, [spot]);

      await storage.upsertObservation(
        id: spotting.id,
        dayEntryId: day.id,
        profileId: 'p1',
        localDate: date,
        tz: 'UTC',
        category: 'spotting',
        code: 'spotting',
        source: 'apple_health',
        sourceId: 'spot-1',
        updatedAt: t2,
      );
      expect(await remembered(), isEmpty);
    });

    test('the remembered-deletion counts name each source', () async {
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
      expect(
        await storage.rememberedImportedSourceCounts('p1'),
        {'healthkit': 1, 'apple_health': 1, 'health_connect': 1},
      );
      expect(await storage.rememberedImportedSourceCounts('p10'), isEmpty);
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
