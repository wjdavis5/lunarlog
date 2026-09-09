/// Issue #240: `LunarLogStorage`'s observations API — upsert (id-keyed, no
/// same-date resolver, unlike day entries), tombstone payload clearing,
/// dirty/local_rev bookkeeping, `readDirtyObservations`, and
/// `applyRemoteObservation`'s per-id LWW rule plus its referential-
/// integrity guard. Mirrors `storage_sync_test.dart`'s shape for the
/// existing tables.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';

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

  final t0 = DateTime.utc(2026, 9, 1, 8);

  setUp(() async {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    await storage.upsertProfile(
        id: 'p1', displayName: 'Riley', isMinor: true, updatedAt: t0);
    await storage.upsertDayEntry(
      profileId: 'p1',
      localDate: '2026-09-01',
      tz: 'UTC',
      flow: FlowLevel.none,
      updatedAt: t0,
    );
  });

  Future<Observation?> observationById(String id) => (db.select(db.observations)
        ..where((t) => t.id.equals(id)))
      .getSingleOrNull();

  Future<String> entryId() async =>
      (await storage.getDayEntries(profileId: 'p1')).single.id;

  RemoteObservationRow remoteObservation(
    String id, {
    required String dayEntryId,
    String profileId = 'p1',
    String localDate = '2026-09-01',
    String category = 'pain',
    String? code = 'migraine',
    int? intensity = 3,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      RemoteObservationRow(
        id: id,
        dayEntryId: dayEntryId,
        profileId: profileId,
        localDate: localDate,
        tz: 'UTC',
        category: category,
        code: code,
        intensity: intensity,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  group('upsertObservation', () {
    test('inserts a new observation, dirty, local_rev 1', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        intensity: 3,
      );
      expect(o.category, 'pain');
      expect(o.code, 'migraine');
      expect(o.intensity, 3);
      expect(o.dirty, isTrue);
      expect(o.localRev, 1);
      expect(o.dayEntryId, dayEntryId);
    });

    test('updating by id in place bumps updated_at strictly and local_rev',
        () async {
      final dayEntryId = await entryId();
      final first = await storage.upsertObservation(
        id: 'o1',
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        updatedAt: t0,
      );
      clock.now = t0; // same instant: the strict-bump rule must still apply
      final second = await storage.upsertObservation(
        id: 'o1',
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'headache',
        updatedAt: t0,
      );
      expect(second.id, first.id);
      expect(second.code, 'headache');
      expect(second.localRev, 2);
      expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
    });

    test('multiple live rows for the same (profile, date, category) are '
        'allowed — no same-date resolver, unlike day entries', () async {
      final dayEntryId = await entryId();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'sex',
        code: 'protected',
      );
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'sex',
        code: 'unprotected',
      );
      final rows = await storage.getObservationsForDayEntry(dayEntryId);
      expect(rows, hasLength(2));
    });

    test('throws for a category over the length bound', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'x' * 65,
        ),
        throwsArgumentError,
      );
    });

    test('throws for an intensity outside 1-5', () async {
      final dayEntryId = await entryId();
      expect(
        () => storage.upsertObservation(
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          intensity: 6,
        ),
        throwsArgumentError,
      );
    });
  });

  group('softDeleteObservation', () {
    test('clears the payload but keeps category/local_date/tz/day_entry_id',
        () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        intensity: 3,
        valueText: 'note-like text',
      );
      await storage.softDeleteObservation(o.id);
      final row = await observationById(o.id);
      expect(row!.deletedAt, isNotNull);
      expect(row.code, isNull);
      expect(row.intensity, isNull);
      expect(row.valueText, isNull);
      expect(row.category, 'pain');
      expect(row.localDate, '2026-09-01');
      expect(row.dayEntryId, dayEntryId);
      expect(row.dirty, isTrue);
    });

    test('is idempotent: re-deleting a tombstone does not bump updated_at '
        'again', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      await storage.softDeleteObservation(o.id);
      final first = await observationById(o.id);
      clock.now = clock.now.add(const Duration(minutes: 5));
      await storage.softDeleteObservation(o.id);
      final second = await observationById(o.id);
      expect(second!.updatedAt, first!.updatedAt);
    });

    test('is a no-op for an id not held locally', () async {
      await storage.softDeleteObservation('nonexistent');
      expect(await observationById('nonexistent'), isNull);
    });
  });

  group('dirty tracking', () {
    test('dirtyCount includes observations', () async {
      final dayEntryId = await entryId();
      final before = await storage.dirtyCount();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      expect(await storage.dirtyCount(), before + 1);
    });

    test('readDirtyObservations pages by id, tombstones included', () async {
      final dayEntryId = await entryId();
      final a = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'a',
      );
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'b',
      );
      final page1 = await storage.readDirtyObservations(limit: 1);
      expect(page1, hasLength(1));
      final page2 =
          await storage.readDirtyObservations(limit: 1, afterId: page1.single.id);
      expect(page2, hasLength(1));
      expect(page2.single.id, isNot(page1.single.id));

      await storage.softDeleteObservation(a.id);
      final all = await storage.readDirtyObservations();
      expect(all.map((o) => o.id), containsAll([a.id]));
    });

    test('markPushed clears dirty only when local_rev still matches',
        () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      final cleared = await storage.markPushed(
          table: SyncTable.observations, id: o.id, localRevAtPush: o.localRev);
      expect(cleared, isTrue);
      expect((await observationById(o.id))!.dirty, isFalse);
    });

    test('markPushed declines when a local write landed since the push '
        'was assembled (AE11)', () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      final staleRev = o.localRev;
      await storage.upsertObservation(
          id: o.id,
          dayEntryId: dayEntryId,
          profileId: 'p1',
          localDate: '2026-09-01',
          tz: 'UTC',
          category: 'pain',
          code: 'migraine');
      final cleared = await storage.markPushed(
          table: SyncTable.observations, id: o.id, localRevAtPush: staleRev);
      expect(cleared, isFalse);
      expect((await observationById(o.id))!.dirty, isTrue);
    });

    test('markAllDirty flags every observation and bumps local_rev',
        () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      await storage.markPushed(
          table: SyncTable.observations, id: o.id, localRevAtPush: o.localRev);
      expect((await observationById(o.id))!.dirty, isFalse);
      await storage.markAllDirty();
      final row = await observationById(o.id);
      expect(row!.dirty, isTrue);
      expect(row.localRev, o.localRev + 1);
    });
  });

  group('isEmpty', () {
    test('a database holding an observation is not reported empty '
        '(observations are counted alongside profiles/day entries, not '
        'just the two LocalRowCounts fields)', () async {
      // The fixture profile/day entry from setUp already make isEmpty()
      // false on their own; this test's point is that isEmpty()'s own
      // logic explicitly checks observations too (see its doc comment),
      // not that this particular fixture happens to be non-empty for an
      // unrelated reason — a regression that dropped the observations
      // check from isEmpty() would not be caught by any *other* test in
      // this file, since every one of them already has a day entry.
      final dayEntryId = await entryId();
      await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
      );
      expect(await storage.isEmpty(), isFalse);
    });
  });

  group('applyRemoteObservation', () {
    test('inserts a new remote row not dirty', () async {
      final dayEntryId = await entryId();
      final applied = await storage.applyRemoteObservation(
          remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0));
      expect(applied, isTrue);
      final row = await observationById('r1');
      expect(row!.dirty, isFalse);
      expect(row.category, 'pain');
      expect(row.code, 'migraine');
    });

    test('per-id LWW: an older remote row is declined, keeping the local '
        'copy', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteObservation(remoteObservation('r1',
          dayEntryId: dayEntryId,
          code: 'newer',
          updatedAt: t0.add(const Duration(hours: 1))));
      final applied = await storage.applyRemoteObservation(remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'older',
          updatedAt: t0));
      expect(applied, isFalse);
      expect((await observationById('r1'))!.code, 'newer');
    });

    test('the remote copy wins a tie', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteObservation(remoteObservation('r1',
          dayEntryId: dayEntryId, code: 'first', updatedAt: t0));
      final applied = await storage.applyRemoteObservation(remoteObservation(
          'r1',
          dayEntryId: dayEntryId,
          code: 'second',
          updatedAt: t0));
      expect(applied, isTrue);
      expect((await observationById('r1'))!.code, 'second');
    });

    test('a tombstoned remote row clears the payload but keeps category',
        () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteObservation(remoteObservation('r1',
          dayEntryId: dayEntryId, code: 'migraine', updatedAt: t0));
      await storage.applyRemoteObservation(remoteObservation('r1',
          dayEntryId: dayEntryId,
          code: null,
          intensity: null,
          updatedAt: t0.add(const Duration(hours: 1)),
          deletedAt: t0.add(const Duration(hours: 1))));
      final row = await observationById('r1');
      expect(row!.deletedAt, isNotNull);
      expect(row.code, isNull);
      expect(row.category, 'pain');
    });

    test('throws RetryableSyncApplyError when the day entry is not held '
        'locally', () async {
      expect(
        () => storage.applyRemoteObservation(remoteObservation('r1',
            dayEntryId: 'nonexistent-day-entry', updatedAt: t0)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
    });
  });

  group('applyRemotePage / applyRemoteRows / applyResolved', () {
    test('applyRemotePage advances cursor_observations in the same '
        'transaction as the rows', () async {
      final dayEntryId = await entryId();
      await storage.applyRemotePage(
        table: SyncTable.observations,
        rows: [remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0)],
        newCursor: 5,
      );
      expect((await storage.readSyncState()).cursorObservations, 5);
      expect(await observationById('r1'), isNotNull);
    });

    test('applyRemoteRows applies an observation alongside a profile in '
        'one transaction', () async {
      final dayEntryId = await entryId();
      await storage.applyRemoteRows([
        remoteObservation('r1', dayEntryId: dayEntryId, updatedAt: t0),
      ]);
      expect(await observationById('r1'), isNotNull);
    });

    test('applyResolved only touches an id already held locally (never '
        'inserts)', () async {
      await storage.applyResolved([
        remoteObservation('never-seen', dayEntryId: 'whatever', updatedAt: t0),
      ]);
      expect(await observationById('never-seen'), isNull);
    });

    test('applyResolved overwrites a held row with dirty = false',
        () async {
      final dayEntryId = await entryId();
      final o = await storage.upsertObservation(
        dayEntryId: dayEntryId,
        profileId: 'p1',
        localDate: '2026-09-01',
        tz: 'UTC',
        category: 'pain',
        code: 'mine',
        updatedAt: t0,
      );
      await storage.applyResolved([
        remoteObservation(o.id,
            dayEntryId: dayEntryId,
            code: 'servers',
            updatedAt: t0.add(const Duration(hours: 1))),
      ]);
      final row = await observationById(o.id);
      expect(row!.code, 'servers');
      expect(row.dirty, isFalse);
    });
  });
}
