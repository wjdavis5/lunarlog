/// Unit tests for the extracted [SyncCursorStorage] (issue #551 problem 1,
/// part 1 step 2): the sync cursor singleton, the learned clock offset, and
/// the dirty-scan/maintenance members, exercised directly against a real
/// drift database (SQL behaviour, not a fake).
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late SyncCursorStorage store;
  late LunarLogStorage storage;
  late DateTime now;

  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    now = t0;
    // The production wiring: the storage and the extracted store share one
    // clock, so the learned offset is a single value.
    final clock = StorageClock(clock: () => now);
    storage = LunarLogStorage(db, clock: () => now);
    store = SyncCursorStorage(db, clock);
  });

  Future<void> setProfileClean(String id) =>
      (db.update(db.profiles)..where((t) => t.id.equals(id)))
          .write(const ProfilesCompanion(dirty: Value(false)));

  Future<void> setDayEntryClean(String id) =>
      (db.update(db.dayEntries)..where((t) => t.id.equals(id)))
          .write(const DayEntriesCompanion(dirty: Value(false)));

  group('sync cursor', () {
    test('readSyncState returns the default before anything is written',
        () async {
      final state = await store.readSyncState();
      expect(state, kDefaultSyncState);
      expect(state.id, 1);
    });

    test('writeSyncState round-trips and forces the singleton id', () async {
      await store.writeSyncState(
        kDefaultSyncState.copyWith(deviceId: 'device-a', cursorProfiles: 7),
      );
      final state = await store.readSyncState();
      expect(state.id, 1);
      expect(state.deviceId, 'device-a');
      expect(state.cursorProfiles, 7);
    });

    test('setClockOffset moves the shared offset', () {
      expect(store.clockOffset, Duration.zero);
      store.setClockOffset(const Duration(minutes: 5));
      expect(store.clockOffset, const Duration(minutes: 5));
    });
  });

  group('dirty scans', () {
    test('isEmpty is true only for a database with no rows at all', () async {
      expect(await store.isEmpty(), isTrue);
      await storage.upsertProfile(displayName: 'A', isMinor: false);
      expect(await store.isEmpty(), isFalse);
    });

    test('readDirtyProfiles keyset-pages dirty rows only', () async {
      final a = await storage.upsertProfile(displayName: 'A', isMinor: false);
      final b = await storage.upsertProfile(displayName: 'B', isMinor: false);
      final c = await storage.upsertProfile(displayName: 'C', isMinor: false);
      await setProfileClean(b.id);

      final first = await store.readDirtyProfiles(limit: 1);
      expect(first.map((p) => p.id), [a.id]);
      final second =
          await store.readDirtyProfiles(limit: 10, afterId: first.single.id);
      expect(second.map((p) => p.id), [c.id]);
      expect(a.id.compareTo(c.id), lessThan(0));
    });

    test('readDirtyDayEntries excludes a row marked clean', () async {
      final profile =
          await storage.upsertProfile(displayName: 'A', isMinor: false);
      final dirty = await storage.upsertDayEntry(
        profileId: profile.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );
      final clean = await storage.upsertDayEntry(
        profileId: profile.id,
        localDate: '2026-01-14',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      await setDayEntryClean(clean.id);

      final page = await store.readDirtyDayEntries();
      expect(page.map((e) => e.id), [dirty.id]);
    });

    test('dirtyCount counts dirty rows across the synced tables', () async {
      expect(await store.dirtyCount(), 0);
      await storage.upsertProfile(displayName: 'A', isMinor: false);
      expect(await store.dirtyCount(), 1);
    });

    test('markAllDirty flags previously-clean rows and bumps local_rev',
        () async {
      final profile =
          await storage.upsertProfile(displayName: 'A', isMinor: false);
      await setProfileClean(profile.id);
      expect(await store.dirtyCount(), 0);

      await store.markAllDirty();

      expect(await store.dirtyCount(), 1);
      final rows = await store.readDirtyProfiles();
      expect(rows.single.id, profile.id);
      expect(rows.single.localRev, greaterThan(profile.localRev));
    });
  });

  group('maintenance', () {
    test('rebaseFutureStampedRows rebases a future dirty row to serverNow',
        () async {
      final future = t0.add(const Duration(hours: 1));
      final profile = await storage.upsertProfile(
        displayName: 'A',
        isMinor: false,
        updatedAt: future,
      );

      final rebased = await store.rebaseFutureStampedRows(serverNow: t0);

      expect(rebased, 1);
      final reread =
          (await storage.getProfiles(includeTombstones: true)).single;
      expect(reread.updatedAt, t0);
      expect(reread.localRev, greaterThan(profile.localRev));
    });

    test('sweepTombstones removes an old clean tombstone only', () async {
      final doomed =
          await storage.upsertProfile(displayName: 'Doomed', isMinor: false);
      final kept =
          await storage.upsertProfile(displayName: 'Kept', isMinor: false);
      await storage.softDeleteProfile(doomed.id);
      await setProfileClean(doomed.id);

      // The dirty tombstone is never swept even past the horizon.
      await storage.softDeleteProfile(kept.id);

      final swept = await store.sweepTombstones(
        olderThan: t0.add(const Duration(days: 1)),
      );

      expect(swept, 1);
      final remaining =
          (await storage.getProfiles(includeTombstones: true))
              .map((p) => p.id)
              .toList();
      expect(remaining, [kept.id]);
    });
  });
}
