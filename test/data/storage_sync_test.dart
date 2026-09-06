import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
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

/// U3 storage sync API (KTD4, KTD5): dirty tracking, local revisions,
/// compare-before-write remote applies, payload-free tombstones, the
/// server-offset clock, and the sync_state singleton.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late LunarLogDatabase db;
  late FixedClock clock;
  late LunarLogStorage storage;

  final t0 = DateTime.utc(2026, 1, 15, 8);

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    addTearDown(() => db.close());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
  });

  Future<Profile> profileById(String id) async =>
      (await storage.getProfiles(includeTombstones: true))
          .firstWhere((p) => p.id == id);

  Future<DayEntry> entryById(String profileId, String id) async =>
      (await storage.getDayEntries(
              profileId: profileId, includeTombstones: true))
          .firstWhere((e) => e.id == id);

  Future<List<DayEntry>> liveFor(String profileId, String date) async =>
      (await storage.getDayEntries(profileId: profileId))
          .where((e) => e.localDate == date)
          .toList();

  RemoteProfileRow remoteProfile(
    String id, {
    String displayName = 'Remote',
    bool isMinor = false,
    int sortOrder = 0,
    required DateTime updatedAt,
    DateTime? createdAt,
    DateTime? deletedAt,
  }) =>
      RemoteProfileRow(
        id: id,
        displayName: displayName,
        isMinor: isMinor,
        sortOrder: sortOrder,
        archivedAt: null,
        createdAt: createdAt ?? updatedAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  RemoteDayEntryRow remoteEntry(
    String id, {
    required String profileId,
    String localDate = '2026-01-15',
    String tz = 'UTC',
    FlowLevel flow = FlowLevel.medium,
    List<String> tags = const ['remote'],
    String? note = 'from remote',
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) =>
      RemoteDayEntryRow(
        id: id,
        profileId: profileId,
        localDate: localDate,
        tz: tz,
        flow: flow,
        tags: tags,
        note: note,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );

  group('local writes and dirty reads', () {
    test('upsertProfile / upsertDayEntry / softDelete* set dirty and bump '
        'local_rev; readDirty* includes tombstones', () async {
      final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
      expect(p.dirty, isTrue);
      expect(p.localRev, 1);

      final p2 = await storage.upsertProfile(
          id: p.id, displayName: 'A2', isMinor: false);
      expect(p2.localRev, 2);
      expect(p2.dirty, isTrue);

      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      expect(e.dirty, isTrue);
      expect(e.localRev, 1);

      final e2 = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(e2.id, e.id);
      expect(e2.localRev, 2);

      // Push both, then soft delete: dirty again with a further bump.
      await storage.markPushed(
          table: SyncTable.profiles, id: p.id, localRevAtPush: 2);
      await storage.markPushed(
          table: SyncTable.dayEntries, id: e.id, localRevAtPush: 2);
      expect(await storage.readDirtyProfiles(), isEmpty);
      expect(await storage.readDirtyDayEntries(), isEmpty);

      await storage.softDeleteDayEntry(
          profileId: p.id, localDate: '2026-01-15');
      await storage.softDeleteProfile(p.id);

      final dirtyProfiles = await storage.readDirtyProfiles();
      expect(dirtyProfiles.single.id, p.id);
      expect(dirtyProfiles.single.deletedAt, isNotNull);
      expect(dirtyProfiles.single.localRev, 3);

      final dirtyEntries = await storage.readDirtyDayEntries();
      expect(dirtyEntries.single.id, e.id);
      expect(dirtyEntries.single.deletedAt, isNotNull);
      expect(dirtyEntries.single.localRev, 3);
    });

    test('tombstones carry no payload; a later upsert for the same date '
        'creates a new live row with its own payload', () async {
      final p = await storage.upsertProfile(displayName: 'Luna', isMinor: true);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          tags: const ['cramps'],
          note: 'private');
      await storage.softDeleteDayEntry(
          profileId: p.id, localDate: '2026-01-15');
      final tomb = await entryById(p.id, e.id);
      expect(tomb.deletedAt, isNotNull);
      expect(tomb.note, isNull);
      expect(tomb.tags, isEmpty);
      expect(tomb.flow, FlowLevel.heavy,
          reason: 'flow is an enum, not content; only note/tags are cleared');

      await storage.softDeleteProfile(p.id);
      final pt = await profileById(p.id);
      expect(pt.deletedAt, isNotNull);
      expect(pt.displayName, '');

      clock.now = t0.add(const Duration(hours: 1));
      final fresh = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
          tags: const ['headache'],
          note: 'new');
      expect(fresh.id, isNot(e.id));
      expect(fresh.note, 'new');
      expect(fresh.tags, ['headache']);
      expect(fresh.deletedAt, isNull);
      expect(await liveFor(p.id, '2026-01-15'), hasLength(1));
      expect((await entryById(p.id, e.id)).note, isNull,
          reason: 'the old tombstone stays payload-free');
    });

    test('AE11: markPushed clears dirty only when local_rev is unchanged; '
        'an edit at the same clock instant bumps local_rev and lands 1ms '
        'after the stored updated_at', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      final revAtPush = e.localRev;

      // Push in flight; the clock has not advanced, so the edit is stamped
      // strictly after the stored value (never equal — the server would
      // decline an equal timestamp and revert the edit).
      final edited = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(edited.updatedAt, e.updatedAt.add(const Duration(milliseconds: 1)));
      expect(edited.localRev, revAtPush + 1);

      final cleared = await storage.markPushed(
          table: SyncTable.dayEntries, id: e.id, localRevAtPush: revAtPush);
      expect(cleared, isFalse);
      expect((await entryById(p.id, e.id)).dirty, isTrue,
          reason: 'the concurrent edit must be pushed again');

      final clearedNow = await storage.markPushed(
          table: SyncTable.dayEntries,
          id: e.id,
          localRevAtPush: edited.localRev);
      expect(clearedNow, isTrue);
      expect((await entryById(p.id, e.id)).dirty, isFalse);

      // Profiles behave the same way.
      expect(
          await storage.markPushed(
              table: SyncTable.profiles, id: p.id, localRevAtPush: 999),
          isFalse);
      expect(
          await storage.markPushed(
              table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev),
          isTrue);
      expect((await profileById(p.id)).dirty, isFalse);
    });
  });

  group('applyRemote*', () {
    test('day entry: newer remote overwrites, clears dirty, keeps local_rev; '
        'older remote is ignored; equal remote (live or tombstone) applies',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'local');
      final rev = e.localRev;

      // Newer.
      final newer = e.updatedAt.add(const Duration(minutes: 1));
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(e.id,
              profileId: p.id, updatedAt: newer, note: 'newer')),
          isTrue);
      var row = await entryById(p.id, e.id);
      expect(row.note, 'newer');
      expect(row.tags, ['remote']);
      expect(row.updatedAt, newer);
      expect(row.dirty, isFalse);
      expect(row.localRev, rev);

      // Older: untouched.
      final older = e.updatedAt.subtract(const Duration(minutes: 1));
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(e.id,
              profileId: p.id, updatedAt: older, note: 'older')),
          isFalse);
      row = await entryById(p.id, e.id);
      expect(row.note, 'newer');
      expect(row.updatedAt, newer);

      // Equal, live: remote wins the tie.
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(e.id,
              profileId: p.id, updatedAt: newer, note: 'tie')),
          isTrue);
      expect((await entryById(p.id, e.id)).note, 'tie');

      // Equal, tombstone: applies, payload cleared.
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(e.id,
              profileId: p.id,
              updatedAt: newer,
              deletedAt: newer,
              note: 'should be dropped')),
          isTrue);
      row = await entryById(p.id, e.id);
      expect(row.deletedAt, newer);
      expect(row.note, isNull);
      expect(row.tags, isEmpty);
      expect(row.dirty, isFalse);
      expect(await liveFor(p.id, '2026-01-15'), isEmpty);
    });

    test('profile: newer remote overwrites; tombstone clears display_name; '
        'older remote is ignored; unknown id is inserted clean', () async {
      final p = await storage.upsertProfile(displayName: 'Local', isMinor: true);
      final newer = p.updatedAt.add(const Duration(seconds: 1));
      expect(
          await storage.applyRemoteProfile(remoteProfile(p.id,
              displayName: 'Remote', isMinor: false, updatedAt: newer)),
          isTrue);
      var row = await profileById(p.id);
      expect(row.displayName, 'Remote');
      expect(row.isMinor, isFalse);
      expect(row.dirty, isFalse);
      expect(row.localRev, p.localRev);

      expect(
          await storage.applyRemoteProfile(remoteProfile(p.id,
              displayName: 'Stale', updatedAt: p.updatedAt)),
          isFalse);
      expect((await profileById(p.id)).displayName, 'Remote');

      expect(
          await storage.applyRemoteProfile(remoteProfile(p.id,
              displayName: 'Gone', updatedAt: newer, deletedAt: newer)),
          isTrue);
      row = await profileById(p.id);
      expect(row.deletedAt, newer);
      expect(row.displayName, '');

      const other = '01J0000000000000000000000Z';
      expect(
          await storage.applyRemoteProfile(
              remoteProfile(other, displayName: 'New', updatedAt: t0)),
          isTrue);
      row = await profileById(other);
      expect(row.displayName, 'New');
      expect(row.dirty, isFalse);
      expect(row.localRev, 0);
    });

    test('a timestamp round-tripped through the remote ISO rendering '
        'compares equal to the local value', () async {
      clock.now = DateTime.parse('2026-01-15T08:00:00.123000Z');
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'local');
      // Postgres renders the instant as `.123+00:00`; Dart stored `.123000Z`.
      const remoteIso = '2026-01-15T08:00:00.123+00:00';
      final remoteStamp = DateTime.parse(remoteIso);
      expect(remoteIso, isNot('2026-01-15T08:00:00.123000Z'),
          reason: 'the renderings differ; the instant does not');
      expect(remoteStamp.microsecondsSinceEpoch,
          e.updatedAt.microsecondsSinceEpoch);
      // Equal instant: remote wins the tie, proving the comparison is on the
      // parsed instant and not on the string.
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(e.id,
              profileId: p.id, updatedAt: remoteStamp, note: 'remote')),
          isTrue);
      expect((await entryById(p.id, e.id)).note, 'remote');
    });

    test('AE3: a live remote row for a date held by a different live local '
        'ULID resolves by the same-date rule; the loser is tombstoned with '
        'the winner timestamp; a local loser is marked dirty', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-01',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'local');
      await storage.markPushed(
          table: SyncTable.dayEntries,
          id: local.id,
          localRevAtPush: local.localRev);

      // Remote is newer: remote wins, local loser tombstoned + dirty.
      const remoteId = '01J0000000000000000000000R';
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(remoteId,
          profileId: p.id, localDate: '2026-09-01', updatedAt: newer));

      final live = await liveFor(p.id, '2026-09-01');
      expect(live.single.id, remoteId);
      expect(live.single.dirty, isFalse);
      final loser = await entryById(p.id, local.id);
      expect(loser.deletedAt, newer);
      expect(loser.updatedAt, newer);
      expect(loser.note, isNull);
      expect(loser.dirty, isTrue, reason: 'a local loser must be pushed');
      expect(loser.localRev, local.localRev + 1);

      // Now the local live row is newer than an incoming remote for the
      // same date: the remote loses and is stored as a tombstone stamped
      // with the local winner's timestamp, not dirty (the server resolves
      // it when the local winner is pushed).
      clock.now = newer.add(const Duration(minutes: 10));
      final revived = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-01',
          tz: 'UTC',
          flow: FlowLevel.heavy,
          note: 'local edit');
      expect(revived.id, remoteId, reason: 'edits keep the live ULID');
      const lateRemote = '01J0000000000000000000000S';
      await storage.applyRemoteDayEntry(remoteEntry(lateRemote,
          profileId: p.id,
          localDate: '2026-09-01',
          updatedAt: newer.add(const Duration(minutes: 1))));
      final liveAfter = await liveFor(p.id, '2026-09-01');
      expect(liveAfter.single.id, remoteId);
      final remoteLoser = await entryById(p.id, lateRemote);
      expect(remoteLoser.deletedAt, revived.updatedAt);
      expect(remoteLoser.updatedAt, revived.updatedAt);
      expect(remoteLoser.dirty, isFalse);

      // Equal timestamps: smaller ULID wins.
      const smallest = '01J00000000000000000000000';
      await storage.applyRemoteDayEntry(remoteEntry(smallest,
          profileId: p.id,
          localDate: '2026-09-01',
          updatedAt: revived.updatedAt));
      expect((await liveFor(p.id, '2026-09-01')).single.id, smallest);
      final tied = await entryById(p.id, remoteId);
      expect(tied.deletedAt, revived.updatedAt);
      expect(tied.dirty, isTrue);
    });

    test('applyRemoteDayEntry for an unknown profile is a typed retryable '
        'error, not a crash', () async {
      await expectLater(
        storage.applyRemoteDayEntry(remoteEntry('01J0000000000000000000000X',
            profileId: '01J0000000000000000000000P', updatedAt: t0)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect(await storage.isEmpty(), isTrue);
    });
  });

  group('same-date tag merge (Issue #3 gap-closure plan, Unit U5)', () {
    test('a remote row that loses the same-date rule merges its tags into '
        'the surviving local row and marks that row dirty with a bumped '
        'localRev (R7/R11)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-10',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['cramps']);
      await storage.markPushed(
          table: SyncTable.dayEntries,
          id: local.id,
          localRevAtPush: local.localRev);

      const remoteId = '01J0000000000000000000001M';
      final older = local.updatedAt.subtract(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(remoteId,
          profileId: p.id,
          localDate: '2026-09-10',
          tags: const ['heavy_flow'],
          updatedAt: older));

      final winner = await entryById(p.id, local.id);
      expect(winner.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(winner.dirty, isTrue, reason: 'the merge must be pushed');
      expect(winner.localRev, local.localRev + 1);
      expect(winner.deletedAt, isNull);

      final loser = await entryById(p.id, remoteId);
      expect(loser.deletedAt, isNotNull, reason: 'the remote loser is a tombstone');
      expect(loser.tags, isEmpty, reason: 'R12: tombstones are payload-free');
      expect(loser.note, isNull);
    });

    test('a remote row that wins the same-date rule writes the union onto '
        'the remote row and leaves the local loser a tombstone with empty '
        'tags and null note (R7, R12)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-11',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['cramps'],
          note: 'local note');
      await storage.markPushed(
          table: SyncTable.dayEntries,
          id: local.id,
          localRevAtPush: local.localRev);

      const remoteId = '01J0000000000000000000001N';
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(remoteId,
          profileId: p.id,
          localDate: '2026-09-11',
          tags: const ['heavy_flow'],
          note: 'remote note',
          updatedAt: newer));

      final winner = await entryById(p.id, remoteId);
      expect(winner.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(winner.note, 'remote note',
          reason: 'R8: note stays last-writer-wins, unaffected by the tag merge');
      expect(winner.deletedAt, isNull);

      final loser = await entryById(p.id, local.id);
      expect(loser.deletedAt, newer);
      expect(loser.tags, isEmpty);
      expect(loser.note, isNull);
      expect(loser.dirty, isTrue, reason: 'a local loser must be pushed');
    });

    test('a remote tombstone for a date with a live local row never '
        'attempts a merge - tombstones never compete', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-12',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['cramps']);

      const remoteId = '01J0000000000000000000001O';
      final t = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(remoteId,
          profileId: p.id,
          localDate: '2026-09-12',
          updatedAt: t,
          deletedAt: t));

      final unaffected = await entryById(p.id, local.id);
      expect(unaffected.deletedAt, isNull);
      expect(unaffected.tags, ['cramps'],
          reason: 'a tombstone never merges tags into a live row');
      final tomb = await entryById(p.id, remoteId);
      expect(tomb.deletedAt, t);
      expect(tomb.tags, isEmpty);
    });

    test('a same-id remote row that drops a tag still drops it locally - no '
        'union on the same-id path (R10)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-09-13',
          tz: 'UTC',
          flow: FlowLevel.medium,
          tags: const ['a', 'b']);

      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(local.id,
          profileId: p.id,
          localDate: '2026-09-13',
          tags: const ['a'],
          updatedAt: newer));

      final row = await entryById(p.id, local.id);
      expect(row.tags, ['a'], reason: 'the removed tag must stay removed');
    });

    test('three colliding rows converge to the union regardless of the '
        'order they arrive in (R9)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final tA = t0;
      final tB = t0.add(const Duration(minutes: 1));
      final tC = t0.add(const Duration(minutes: 2));

      // Ascending arrival order.
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000201A',
          profileId: p.id, localDate: '2026-09-14', tags: const ['a'], updatedAt: tA));
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000201B',
          profileId: p.id, localDate: '2026-09-14', tags: const ['b'], updatedAt: tB));
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000201C',
          profileId: p.id, localDate: '2026-09-14', tags: const ['c'], updatedAt: tC));
      final ascendingLive = await liveFor(p.id, '2026-09-14');
      expect(ascendingLive.single.tags, unorderedEquals(['a', 'b', 'c']));

      // Descending arrival order, a different date so this run is
      // independent of the one above.
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000202C',
          profileId: p.id, localDate: '2026-09-15', tags: const ['c'], updatedAt: tC));
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000202B',
          profileId: p.id, localDate: '2026-09-15', tags: const ['b'], updatedAt: tB));
      await storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000202A',
          profileId: p.id, localDate: '2026-09-15', tags: const ['a'], updatedAt: tA));
      final descendingLive = await liveFor(p.id, '2026-09-15');
      expect(descendingLive.single.tags, unorderedEquals(['a', 'b', 'c']));
    });

    test('a merge on a profile absent locally still raises before any merge '
        'work runs - ordering unchanged', () async {
      await expectLater(
        storage.applyRemoteDayEntry(remoteEntry('01J000000000000000000203A',
            profileId: '01J000000000000000000203P',
            tags: const ['a'],
            updatedAt: t0)),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect(await storage.isEmpty(), isTrue);
    });
  });

  group('applyResolved', () {
    test('unknown id is a no-op; known id takes the server copy with '
        'dirty = false', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'local');
      final resolvedAt = e.updatedAt.add(const Duration(seconds: 1));
      await storage.applyResolved([
        remoteEntry('01J0000000000000000000000U',
            profileId: p.id, localDate: '2026-02-01', updatedAt: t0),
        remoteProfile('01J0000000000000000000000V', updatedAt: t0),
        remoteEntry(e.id,
            profileId: p.id,
            updatedAt: resolvedAt,
            deletedAt: resolvedAt,
            note: 'dropped'),
      ]);
      final all = await storage.getDayEntries(
          profileId: p.id, includeTombstones: true);
      expect(all.map((r) => r.id), [e.id],
          reason: 'unknown ids must not be inserted');
      expect(all.single.deletedAt, resolvedAt);
      expect(all.single.note, isNull);
      expect(all.single.dirty, isFalse);
      expect(
          (await storage.getProfiles(includeTombstones: true)).map((r) => r.id),
          [p.id]);
    });

    test('a later live remote edit to a resolved loser revives it and '
        're-runs the same-date rule', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final a = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-03-03',
          tz: 'UTC',
          flow: FlowLevel.light);
      // Resolution tombstones `a` in favour of remote `b`.
      const b = '01J0000000000000000000000B';
      final tRes = a.updatedAt.add(const Duration(minutes: 1));
      await storage.applyRemotePage(
          table: SyncTable.dayEntries,
          rows: [
            remoteEntry(b, profileId: p.id, localDate: '2026-03-03', updatedAt: tRes),
          ],
          newCursor: 10);
      expect((await liveFor(p.id, '2026-03-03')).single.id, b);
      expect((await entryById(p.id, a.id)).deletedAt, tRes);

      // A newer live edit to `a` arrives: revived, and it now beats `b`.
      final tRevive = tRes.add(const Duration(minutes: 1));
      await storage.applyRemoteDayEntry(remoteEntry(a.id,
          profileId: p.id,
          localDate: '2026-03-03',
          updatedAt: tRevive,
          note: 'revived'));
      final live = await liveFor(p.id, '2026-03-03');
      expect(live.single.id, a.id);
      expect(live.single.note, 'revived');
      final bRow = await entryById(p.id, b);
      expect(bRow.deletedAt, tRevive);
      expect(bRow.dirty, isTrue, reason: 'b was a local live row that lost');
    });
  });

  group('applyRemotePage', () {
    test('commits rows and the table cursor together; a throwing row '
        'leaves both untouched', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      const r1 = '01J0000000000000000000000C';
      const r2 = '01J0000000000000000000000D';
      await storage.applyRemotePage(
          table: SyncTable.dayEntries,
          rows: [
            remoteEntry(r1, profileId: p.id, localDate: '2026-04-01', updatedAt: t0),
            remoteEntry(r2, profileId: p.id, localDate: '2026-04-02', updatedAt: t0),
          ],
          newCursor: 42);
      var state = await storage.readSyncState();
      expect(state.cursorDayEntries, 42);
      expect(state.cursorProfiles, 0);
      expect(await storage.getDayEntries(profileId: p.id), hasLength(2));

      // Second page: one good row, one with a missing profile.
      const r3 = '01J0000000000000000000000E';
      await expectLater(
        storage.applyRemotePage(
            table: SyncTable.dayEntries,
            rows: [
              remoteEntry(r3, profileId: p.id, localDate: '2026-04-03', updatedAt: t0),
              remoteEntry('01J0000000000000000000000F',
                  profileId: '01J0000000000000000000000Q', updatedAt: t0),
            ],
            newCursor: 99),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      state = await storage.readSyncState();
      expect(state.cursorDayEntries, 42, reason: 'cursor must not advance');
      expect((await storage.getDayEntries(profileId: p.id)).map((e) => e.id),
          isNot(contains(r3)),
          reason: 'the good row of a failed page rolls back too');

      // Profiles page advances only the profiles cursor.
      await storage.applyRemotePage(
          table: SyncTable.profiles,
          rows: [remoteProfile('01J0000000000000000000000G', updatedAt: t0)],
          newCursor: 7);
      state = await storage.readSyncState();
      expect(state.cursorProfiles, 7);
      expect(state.cursorDayEntries, 42);

      // A row of the wrong table is rejected up front.
      await expectLater(
        storage.applyRemotePage(
            table: SyncTable.profiles,
            rows: [remoteEntry(r1, profileId: p.id, updatedAt: t0)],
            newCursor: 8),
        throwsArgumentError,
      );
      expect((await storage.readSyncState()).cursorProfiles, 7);
    });

  });

  group('clock offset', () {
    test('a +5 minute offset stamps local writes ahead of the test clock and '
        'a later write behind the stored value still lands strictly after',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      expect(e.updatedAt, t0);

      storage.setClockOffset(const Duration(minutes: 5));
      clock.now = t0.add(const Duration(seconds: 1));
      final shifted = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(shifted.updatedAt,
          t0.add(const Duration(minutes: 5, seconds: 1)));

      // Offset dropped: the raw clock is now behind the stored value.
      storage.setClockOffset(Duration.zero);
      clock.now = t0.add(const Duration(seconds: 2));
      final bumped = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.none);
      expect(bumped.updatedAt,
          shifted.updatedAt.add(const Duration(milliseconds: 1)));

      // Profiles and deletes use the same clock.
      storage.setClockOffset(const Duration(minutes: 5));
      await storage.softDeleteProfile(p.id);
      expect((await profileById(p.id)).updatedAt,
          t0.add(const Duration(minutes: 5, seconds: 2)));
      expect(storage.clockOffset, const Duration(minutes: 5));
    });
  });

  group('local edit after a remote apply', () {
    test('a local edit with the clock 1s behind the applied remote row is '
        'stamped remote + 1ms and stays dirty, never equal to the server '
        'copy', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final remoteAt = t0.add(const Duration(minutes: 10));
      const rid = 'remote-entry-1';
      await storage.applyRemoteDayEntry(remoteEntry(rid,
          profileId: p.id, localDate: '2026-01-20', updatedAt: remoteAt));
      var row = await entryById(p.id, rid);
      expect(row.updatedAt, remoteAt);
      expect(row.dirty, isFalse);

      clock.now = remoteAt.subtract(const Duration(seconds: 1));
      final edited = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-20',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      expect(edited.id, rid);
      expect(edited.updatedAt, remoteAt.add(const Duration(milliseconds: 1)));
      expect(edited.dirty, isTrue);
      expect(edited.flow, FlowLevel.heavy);

      // The stored row agrees, and a re-apply of the same remote copy
      // (equal to what the server holds) no longer wins.
      row = await entryById(p.id, rid);
      expect(row.updatedAt, remoteAt.add(const Duration(milliseconds: 1)));
      expect(row.dirty, isTrue);
      expect(
          await storage.applyRemoteDayEntry(remoteEntry(rid,
              profileId: p.id, localDate: '2026-01-20', updatedAt: remoteAt)),
          isFalse);
      expect((await entryById(p.id, rid)).flow, FlowLevel.heavy);
    });
  });

  group('bulk state', () {
    test('markAllDirty flags live and tombstoned rows; isEmpty only when both '
        'tables have no rows at all; dirtyCount includes tombstones',
        () async {
      expect(await storage.isEmpty(), isTrue);
      expect(await storage.dirtyCount(), 0);

      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      expect(await storage.isEmpty(), isFalse);
      final e1 = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-16',
          tz: 'UTC',
          flow: FlowLevel.light);
      await storage.softDeleteDayEntry(
          profileId: p.id, localDate: '2026-01-16');
      expect(await storage.dirtyCount(), 3);

      await storage.markPushed(
          table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev);
      await storage.markPushed(
          table: SyncTable.dayEntries, id: e1.id, localRevAtPush: e1.localRev);
      expect(await storage.dirtyCount(), 1, reason: 'the tombstone stays dirty');

      await storage.markAllDirty();
      expect(await storage.dirtyCount(), 3);
      final rows = await storage.getDayEntries(
          profileId: p.id, includeTombstones: true);
      expect(rows.every((r) => r.dirty), isTrue);
      expect((await profileById(p.id)).dirty, isTrue);

      // A tombstone-only database is not empty.
      await storage.softDeleteDayEntry(
          profileId: p.id, localDate: '2026-01-15');
      await storage.softDeleteProfile(p.id);
      expect(await storage.isEmpty(), isFalse);
      expect(await storage.dirtyCount(), 3);
    });

    test('sync_state round-trips, defaults when missing, and is removed by '
        'wipeAllData together with every row', () async {
      final defaults = await storage.readSyncState();
      expect(defaults.id, 1);
      expect(defaults.boundUserId, isNull);
      expect(defaults.deviceId, '');
      expect(defaults.cursorProfiles, 0);
      expect(defaults.cursorDayEntries, 0);
      expect(defaults.lastFullPullAt, isNull);
      expect(defaults.lastSyncAt, isNull);
      expect(defaults.lastError, isNull);
      expect(defaults.serverClockOffsetMs, isNull);

      await storage.writeSyncState(defaults.copyWith(
        boundUserId: const Value('user-1'),
        deviceId: 'device-1',
        cursorProfiles: 3,
        cursorDayEntries: 4,
        lastSyncAt: Value(t0),
        serverClockOffsetMs: const Value(1500),
      ));
      final stored = await storage.readSyncState();
      expect(stored.boundUserId, 'user-1');
      expect(stored.deviceId, 'device-1');
      expect(stored.cursorProfiles, 3);
      expect(stored.cursorDayEntries, 4);
      expect(stored.lastSyncAt, t0);
      expect(stored.serverClockOffsetMs, 1500);

      // Overwrite keeps the singleton a singleton.
      await storage.writeSyncState(stored.copyWith(cursorProfiles: 5));
      final count = await db.customSelect('SELECT COUNT(*) AS n FROM sync_state').getSingle();
      expect(count.data['n'], 1);
      expect((await storage.readSyncState()).cursorProfiles, 5);

      // The id CHECK forbids a second row.
      await expectLater(
        db.customStatement(
            "INSERT INTO sync_state (id, device_id) VALUES (2, 'x')"),
        throwsA(anything),
      );

      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      await storage.setSetting(key: 'k', value: 'v');
      await db.wipeAllData();
      expect(await storage.isEmpty(), isTrue);
      expect(await storage.getSetting('k'), isNull);
      final after = await storage.readSyncState();
      expect(after.deviceId, '');
      expect(after.cursorProfiles, 0);
      expect(after.boundUserId, isNull);
    });
  });
}
