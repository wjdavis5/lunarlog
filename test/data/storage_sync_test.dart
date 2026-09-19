import 'dart:convert';

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        QueryExecutor,
        QueryInterceptor,
        Value,
        driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/domain/limits.dart';
import 'package:lunarlog/data/sync/remote_rows.dart'
    show RemoteDeletedProfileRow, RemoteProfileGuardianRow;
import 'package:lunarlog/data/sync/row_codec.dart'
    show encodeDayEntry, encodeProfile;

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Captures the exact SQL/args drift sends to the executor for the first
/// `SELECT` whose text contains every string in [match] (issue #197 review
/// follow-up) — used to run `EXPLAIN QUERY PLAN` against the query
/// `readDirtyDayEntries` *actually generates*, instead of a hand-retyped
/// literal that could drift out of sync with the real query (and, worse,
/// could not have caught the bug this test now guards: `t.dirty.equals`
/// binds `?` rather than emitting the `dirty = 1` literal the partial
/// index needs).
class _CapturingInterceptor extends QueryInterceptor {
  _CapturingInterceptor(this.match);

  final List<String> match;
  String? capturedSql;
  List<Object?>? capturedArgs;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (match.every(statement.contains)) {
      capturedSql = statement;
      capturedArgs = args;
    }
    return executor.runSelect(statement, args);
  }
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
        profileId: profileId,
        includeTombstones: true,
      )).firstWhere((e) => e.id == id);

  Future<List<DayEntry>> liveFor(String profileId, String date) async =>
      (await storage.getDayEntries(profileId: profileId))
          .where((e) => e.localDate == date)
          .toList();

  RemoteProfileRow remoteProfile(
    String id, {
    String displayName = 'Remote',
    bool isMinor = false,
    String mode = 'standard',
    int sortOrder = 0,
    required DateTime updatedAt,
    DateTime? createdAt,
    DateTime? deletedAt,
    String? trackingPreferences,
  }) => RemoteProfileRow(
    id: id,
    displayName: displayName,
    isMinor: isMinor,
    mode: mode,
    sortOrder: sortOrder,
    archivedAt: null,
    createdAt: createdAt ?? updatedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    trackingPreferences: trackingPreferences,
  );

  RemoteDayEntryRow remoteEntry(
    String id, {
    required String profileId,
    String localDate = '2026-01-15',
    String tz = 'UTC',
    FlowLevel flow = FlowLevel.medium,
    List<String> tags = const ['remote'],
    String? note = 'from remote',
    bool pms = false,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) => RemoteDayEntryRow(
    id: id,
    profileId: profileId,
    localDate: localDate,
    tz: tz,
    flow: flow,
    tags: tags,
    note: note,
    pms: pms,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  RemoteProfileGuardianRow remoteGuardian(
    String id, {
    required String profileId,
    required String userId,
    String role = 'caregiver',
    required String status,
    required DateTime updatedAt,
    DateTime? createdAt,
    int serverVersion = 0,
  }) => RemoteProfileGuardianRow(
    id: id,
    profileId: profileId,
    userId: userId,
    role: role,
    status: status,
    displayName: null,
    invitedBy: null,
    createdAt: createdAt ?? updatedAt,
    updatedAt: updatedAt,
    serverVersion: serverVersion,
  );

  group('local writes and dirty reads', () {
    test('upsertProfile / upsertDayEntry / softDelete* set dirty and bump '
        'local_rev; readDirty* includes tombstones', () async {
      final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
      expect(p.dirty, isTrue);
      expect(p.localRev, 1);

      final p2 = await storage.upsertProfile(
        id: p.id,
        displayName: 'A2',
        isMinor: false,
      );
      expect(p2.localRev, 2);
      expect(p2.dirty, isTrue);

      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      expect(e.dirty, isTrue);
      expect(e.localRev, 1);

      final e2 = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
      );
      expect(e2.id, e.id);
      expect(e2.localRev, 2);

      // Push both, then soft delete: dirty again with a further bump.
      await storage.markPushed(
        table: SyncTable.profiles,
        id: p.id,
        localRevAtPush: 2,
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: e.id,
        localRevAtPush: 2,
      );
      expect(await storage.readDirtyProfiles(), isEmpty);
      expect(await storage.readDirtyDayEntries(), isEmpty);

      await storage.softDeleteDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
      );
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

    test('Issue #177: readDirtyProfiles/readDirtyDayEntries page by '
        '`limit`/`afterId` in id order, so a caller can stream a large '
        'dirty set instead of reading it all at once', () async {
      final p = await storage.upsertProfile(
        displayName: 'Owner',
        isMinor: false,
      );
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-02-${(i + 1).toString().padLeft(2, '0')}',
          tz: 'UTC',
          flow: FlowLevel.light,
        );
        ids.add(e.id);
      }
      expect(
        ids,
        ids.toList()..sort(),
        reason: 'ULIDs generated in order sort in that same order',
      );

      final page1 = await storage.readDirtyDayEntries(limit: 4);
      expect(page1.map((e) => e.id).toList(), ids.sublist(0, 4));

      final page2 = await storage.readDirtyDayEntries(
        limit: 4,
        afterId: page1.last.id,
      );
      expect(page2.map((e) => e.id).toList(), ids.sublist(4, 8));

      final page3 = await storage.readDirtyDayEntries(
        limit: 4,
        afterId: page2.last.id,
      );
      expect(
        page3.map((e) => e.id).toList(),
        ids.sublist(8, 10),
        reason: 'the final page is shorter than the limit',
      );

      final page4 = await storage.readDirtyDayEntries(
        limit: 4,
        afterId: page3.last.id,
      );
      expect(page4, isEmpty, reason: 'nothing left after the last row');

      // readDirtyProfiles takes the same two parameters (only one profile
      // here, so this just proves the call shape and the afterId cutoff).
      expect(await storage.readDirtyProfiles(limit: 1), [
        (await storage.readDirtyProfiles()).first,
      ]);
      expect(await storage.readDirtyProfiles(afterId: p.id), isEmpty);

      // No limit given still reads everything, unchanged from before.
      expect(await storage.readDirtyDayEntries(), hasLength(10));
    });

    test('issue #197: readDirtyDayEntries\' dirty=1 scan, an updated_at '
        'range scan, and the calendar\'s (profile_id, local_date) range '
        'scan each use their new index, not a full table scan', () async {
      // EXPLAIN QUERY PLAN's `detail` column names the index it picked
      // when the planner used one at all; a full scan reads "SCAN
      // day_entries" with no "USING INDEX" clause.

      // The dirty-scan case is asserted against the SQL/args
      // `readDirtyDayEntries` actually sends the executor (captured via a
      // `QueryInterceptor`), not a re-typed literal — a hand-typed
      // `WHERE dirty = 1` here would keep passing even if the production
      // query regressed back to a bound `?` parameter, which sqlite
      // cannot match against `ix_day_entries_dirty`'s partial-index
      // condition (see that method's own doc comment).
      final interceptor = _CapturingInterceptor(const ['day_entries', 'dirty']);
      final interceptedDb = LunarLogDatabase(
        NativeDatabase.memory().interceptWith(interceptor),
      );
      addTearDown(() => interceptedDb.close());
      final interceptedStorage = LunarLogStorage(
        interceptedDb,
        clock: clock.call,
      );
      await interceptedStorage.readDirtyDayEntries();

      final capturedSql = interceptor.capturedSql;
      expect(
        capturedSql,
        isNotNull,
        reason:
            'readDirtyDayEntries must issue a SELECT against '
            'day_entries mentioning dirty for the interceptor to capture',
      );
      expect(
        interceptor.capturedArgs,
        isEmpty,
        reason:
            'readDirtyDayEntries() with no limit/afterId should bind '
            'no parameters at all now that the dirty predicate is a '
            'literal too, or this EXPLAIN QUERY PLAN would need to bind '
            'them itself',
      );
      final dirtyPlan = await interceptedDb
          .customSelect('EXPLAIN QUERY PLAN $capturedSql')
          .get();
      final dirtyDetail = dirtyPlan
          .map((row) => row.data['detail'] as String)
          .join(' | ');
      expect(
        dirtyDetail,
        contains('ix_day_entries_dirty'),
        reason:
            'readDirtyDayEntries\' generated query ($capturedSql) '
            'must use ix_day_entries_dirty, not a full table scan: '
            '$dirtyDetail',
      );

      final updatedAtPlan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM day_entries '
            "WHERE updated_at > '2026-01-01T00:00:00.000000Z'",
          )
          .get();
      final updatedAtDetail = updatedAtPlan
          .map((row) => row.data['detail'] as String)
          .join(' | ');
      expect(
        updatedAtDetail,
        contains('ix_day_entries_updated_at'),
        reason:
            'an updated_at range scan must use '
            'ix_day_entries_updated_at, not a full table scan: '
            '$updatedAtDetail',
      );

      final rangePlan = await db
          .customSelect(
            'EXPLAIN QUERY PLAN SELECT * FROM day_entries WHERE '
            "profile_id = 'x' AND local_date >= '2026-06-01' "
            "AND local_date <= '2026-06-30'",
          )
          .get();
      final rangeDetail = rangePlan
          .map((row) => row.data['detail'] as String)
          .join(' | ');
      expect(
        rangeDetail,
        contains('ix_day_entries_profile_date'),
        reason:
            'the calendar\'s windowed (profile_id, local_date) range '
            'scan must use ix_day_entries_profile_date, not a full table '
            'scan: $rangeDetail',
      );
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
        note: 'private',
      );
      await storage.softDeleteDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
      );
      final tomb = await entryById(p.id, e.id);
      expect(tomb.deletedAt, isNotNull);
      expect(tomb.note, isNull);
      expect(tomb.tags, isEmpty);
      expect(
        tomb.flow,
        FlowLevel.none,
        reason:
            'issue #224: flow joins note/tags as cleared payload - a '
            'tombstone must not keep the pre-deletion flow value',
      );

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
        note: 'new',
      );
      expect(fresh.id, isNot(e.id));
      expect(fresh.note, 'new');
      expect(fresh.tags, ['headache']);
      expect(fresh.deletedAt, isNull);
      expect(await liveFor(p.id, '2026-01-15'), hasLength(1));
      expect(
        (await entryById(p.id, e.id)).note,
        isNull,
        reason: 'the old tombstone stays payload-free',
      );
    });

    test('AE11: markPushed clears dirty only when local_rev is unchanged; '
        'an edit at the same clock instant bumps local_rev and lands 1ms '
        'after the stored updated_at', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      final revAtPush = e.localRev;

      // Push in flight; the clock has not advanced, so the edit is stamped
      // strictly after the stored value (never equal — the server would
      // decline an equal timestamp and revert the edit).
      final edited = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.heavy,
      );
      expect(
        edited.updatedAt,
        e.updatedAt.add(const Duration(milliseconds: 1)),
      );
      expect(edited.localRev, revAtPush + 1);

      final cleared = await storage.markPushed(
        table: SyncTable.dayEntries,
        id: e.id,
        localRevAtPush: revAtPush,
      );
      expect(cleared, isFalse);
      expect(
        (await entryById(p.id, e.id)).dirty,
        isTrue,
        reason: 'the concurrent edit must be pushed again',
      );

      final clearedNow = await storage.markPushed(
        table: SyncTable.dayEntries,
        id: e.id,
        localRevAtPush: edited.localRev,
      );
      expect(clearedNow, isTrue);
      expect((await entryById(p.id, e.id)).dirty, isFalse);

      // Profiles behave the same way.
      expect(
        await storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush: 999,
        ),
        isFalse,
      );
      expect(
        await storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush: p.localRev,
        ),
        isTrue,
      );
      expect((await profileById(p.id)).dirty, isFalse);
    });
  });

  group('applyRemote*', () {
    test(
      'day entry: newer remote overwrites, clears dirty, keeps local_rev; '
      'older remote is ignored; equal remote (live or tombstone) applies',
      () async {
        final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
        final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
          note: 'local',
        );
        final rev = e.localRev;

        // Newer.
        final newer = e.updatedAt.add(const Duration(minutes: 1));
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(e.id, profileId: p.id, updatedAt: newer, note: 'newer'),
          ),
          isTrue,
        );
        var row = await entryById(p.id, e.id);
        expect(row.note, 'newer');
        expect(row.tags, ['remote']);
        expect(row.updatedAt, newer);
        expect(row.dirty, isFalse);
        expect(row.localRev, rev);

        // Older: untouched.
        final older = e.updatedAt.subtract(const Duration(minutes: 1));
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(e.id, profileId: p.id, updatedAt: older, note: 'older'),
          ),
          isFalse,
        );
        row = await entryById(p.id, e.id);
        expect(row.note, 'newer');
        expect(row.updatedAt, newer);

        // Equal, live: remote wins the tie.
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(e.id, profileId: p.id, updatedAt: newer, note: 'tie'),
          ),
          isTrue,
        );
        expect((await entryById(p.id, e.id)).note, 'tie');

        // Equal, tombstone: applies, payload cleared.
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(
              e.id,
              profileId: p.id,
              updatedAt: newer,
              deletedAt: newer,
              note: 'should be dropped',
            ),
          ),
          isTrue,
        );
        row = await entryById(p.id, e.id);
        expect(row.deletedAt, newer);
        expect(row.note, isNull);
        expect(row.tags, isEmpty);
        expect(row.dirty, isFalse);
        expect(await liveFor(p.id, '2026-01-15'), isEmpty);
      },
    );

    test('profile: newer remote overwrites; tombstone clears display_name; '
        'older remote is ignored; unknown id is inserted clean', () async {
      final p = await storage.upsertProfile(
        displayName: 'Local',
        isMinor: true,
      );
      final newer = p.updatedAt.add(const Duration(seconds: 1));
      expect(
        await storage.applyRemoteProfile(
          remoteProfile(
            p.id,
            displayName: 'Remote',
            isMinor: false,
            mode: 'teen',
            updatedAt: newer,
          ),
        ),
        isTrue,
      );
      var row = await profileById(p.id);
      expect(row.displayName, 'Remote');
      expect(row.isMinor, isFalse);
      expect(
        row.mode,
        'teen',
        reason: '#131: a remotely switched mode applies locally',
      );
      expect(row.dirty, isFalse);
      expect(row.localRev, p.localRev);

      expect(
        await storage.applyRemoteProfile(
          remoteProfile(p.id, displayName: 'Stale', updatedAt: p.updatedAt),
        ),
        isFalse,
      );
      expect((await profileById(p.id)).displayName, 'Remote');

      expect(
        await storage.applyRemoteProfile(
          remoteProfile(
            p.id,
            displayName: 'Gone',
            updatedAt: newer,
            deletedAt: newer,
          ),
        ),
        isTrue,
      );
      row = await profileById(p.id);
      expect(row.deletedAt, newer);
      expect(row.displayName, '');

      const other = '01J0000000000000000000000Z';
      expect(
        await storage.applyRemoteProfile(
          remoteProfile(other, displayName: 'New', updatedAt: t0),
        ),
        isTrue,
      );
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
        note: 'local',
      );
      // Postgres renders the instant as `.123+00:00`; Dart stored `.123000Z`.
      const remoteIso = '2026-01-15T08:00:00.123+00:00';
      final remoteStamp = DateTime.parse(remoteIso);
      expect(
        remoteIso,
        isNot('2026-01-15T08:00:00.123000Z'),
        reason: 'the renderings differ; the instant does not',
      );
      expect(
        remoteStamp.microsecondsSinceEpoch,
        e.updatedAt.microsecondsSinceEpoch,
      );
      // Equal instant: remote wins the tie, proving the comparison is on the
      // parsed instant and not on the string.
      expect(
        await storage.applyRemoteDayEntry(
          remoteEntry(
            e.id,
            profileId: p.id,
            updatedAt: remoteStamp,
            note: 'remote',
          ),
        ),
        isTrue,
      );
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
        note: 'local',
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: local.id,
        localRevAtPush: local.localRev,
      );

      // Remote is newer: remote wins, local loser tombstoned + dirty.
      const remoteId = '01J0000000000000000000000R';
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          remoteId,
          profileId: p.id,
          localDate: '2026-09-01',
          updatedAt: newer,
        ),
      );

      final live = await liveFor(p.id, '2026-09-01');
      expect(live.single.id, remoteId);
      expect(live.single.dirty, isFalse);
      final loser = await entryById(p.id, local.id);
      expect(loser.deletedAt, newer);
      expect(loser.updatedAt, newer);
      expect(loser.note, isNull);
      expect(
        loser.flow,
        FlowLevel.none,
        reason:
            'issue #224: the same-date resolver clears flow on the '
            'local-loser branch too, not only note/tags',
      );
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
        note: 'local edit',
      );
      expect(revived.id, remoteId, reason: 'edits keep the live ULID');
      const lateRemote = '01J0000000000000000000000S';
      await storage.applyRemoteDayEntry(
        remoteEntry(
          lateRemote,
          profileId: p.id,
          localDate: '2026-09-01',
          updatedAt: newer.add(const Duration(minutes: 1)),
        ),
      );
      final liveAfter = await liveFor(p.id, '2026-09-01');
      expect(liveAfter.single.id, remoteId);
      // Issue #663 (LLA-038 mirror): `revived` (tags []) absorbs
      // `lateRemote`'s own default tags (`['remote']`), so the survivor's
      // stamp — and therefore the tombstone's, "the local winner's
      // timestamp" — is bumped 1ms strictly past `revived.updatedAt`, not
      // left tied to it.
      expect(liveAfter.single.tags, ['remote']);
      final bumped = revived.updatedAt.add(const Duration(milliseconds: 1));
      final remoteLoser = await entryById(p.id, lateRemote);
      expect(remoteLoser.deletedAt, bumped);
      expect(remoteLoser.updatedAt, bumped);
      expect(remoteLoser.dirty, isFalse);
      expect(
        remoteLoser.flow,
        FlowLevel.none,
        reason:
            'issue #224: the same-date resolver clears flow on the '
            'remote-loser branch too — remoteEntry() defaulted this row '
            'to FlowLevel.medium, which must not survive as a tombstone',
      );

      // Equal timestamps: smaller ULID wins. Tied against the survivor's
      // real, current stamp (`bumped`, issue #663 above) — not the stale
      // pre-bump `revived.updatedAt`, which the live row has already
      // moved strictly past.
      const smallest = '01J00000000000000000000000';
      await storage.applyRemoteDayEntry(
        remoteEntry(
          smallest,
          profileId: p.id,
          localDate: '2026-09-01',
          updatedAt: bumped,
        ),
      );
      expect((await liveFor(p.id, '2026-09-01')).single.id, smallest);
      final tied = await entryById(p.id, remoteId);
      expect(tied.deletedAt, bumped,
          reason: 'both sides already carry identical tags ([\'remote\']), '
              'so this remote survivor gains nothing new and is not '
              'itself bumped past its own incoming stamp (#662\'s rule)');
      expect(tied.dirty, isTrue);
    });

    test('applyRemoteDayEntry for an unknown profile is a typed retryable '
        'error, not a crash', () async {
      await expectLater(
        storage.applyRemoteDayEntry(
          remoteEntry(
            '01J0000000000000000000000X',
            profileId: '01J0000000000000000000000P',
            updatedAt: t0,
          ),
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect(await storage.isEmpty(), isTrue);
    });
  });

  group('first-class PMS marker (Issue #220)', () {
    test(
      'a remote PMS day applies with its marker; a remote tombstone '
      'clears it; a local push carries the marker in the encoded payload',
      () async {
        final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
        final at = DateTime.utc(2026, 2, 1, 9);

        // Remote apply: the marker lands.
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(
              '01JREMOTEPMS0000000000000X',
              profileId: p.id,
              updatedAt: at,
              pms: true,
            ),
          ),
          isTrue,
        );
        var row = await entryById(p.id, '01JREMOTEPMS0000000000000X');
        expect(row.pms, isTrue);

        // Remote tombstone: the marker clears with the payload.
        expect(
          await storage.applyRemoteDayEntry(
            remoteEntry(
              '01JREMOTEPMS0000000000000X',
              profileId: p.id,
              updatedAt: at.add(const Duration(minutes: 1)),
              pms: true,
              deletedAt: at.add(const Duration(minutes: 1)),
            ),
          ),
          isTrue,
        );
        row = await entryById(p.id, '01JREMOTEPMS0000000000000X');
        expect(row.deletedAt, isNotNull);
        expect(row.pms, isFalse);

        // Local write: the marker is stored, marked dirty, and the dirty
        // payload the engine pushes encodes pms.
        final local = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-02-02',
          tz: 'UTC',
          flow: FlowLevel.none,
          pms: true,
        );
        expect(local.pms, isTrue);
        expect(local.dirty, isTrue);
        final dirty = await storage.readDirtyDayEntries();
        final json = encodeDayEntry(
          dirty.firstWhere((e) => e.localDate == '2026-02-02'),
        );
        expect(json['pms'], true);
      },
    );
  });

  group('tracking preferences (Issue #259)', () {
    test('setTrackingPreferences writes only that column plus sync '
        'bookkeeping, and null clears it', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: true);
      final revBefore = p.localRev;

      final updated = await storage.setTrackingPreferences(
          p.id, '{"mood": {"enabled": false, "sort_order": 0}}');
      expect(updated, isNotNull);
      expect(updated!.trackingPreferences,
          '{"mood": {"enabled": false, "sort_order": 0}}');
      expect(updated.dirty, isTrue,
          reason: 'the document syncs to co-guardians (AC1/AC6)');
      expect(updated.localRev, revBefore + 1);
      expect(updated.updatedAt.isAfter(p.updatedAt), isTrue,
          reason: 'stamped strictly after the stored value');
      expect(updated.displayName, 'P',
          reason: 'no other metadata column is touched');
      expect(updated.mode, 'standard');

      final cleared =
          await storage.setTrackingPreferences(p.id, null);
      expect(cleared!.trackingPreferences, '{}',
          reason: 'a clear is stored as the explicitly empty document — '
              'null would be omitted by the codec and could never propagate');
      expect(cleared.dirty, isTrue);
      expect(cleared.localRev, revBefore + 2);
    });

    test('setTrackingPreferences rejects a non-JSON-object document and '
        'no-ops on unknown and tombstoned ids', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      expect(
        () => storage.setTrackingPreferences(p.id, '["mood"]'),
        throwsArgumentError,
      );
      expect(
        () => storage.setTrackingPreferences(p.id, 'garbage'),
        throwsArgumentError,
      );
      expect(await storage.setTrackingPreferences('01J0000000000000000000000Z',
          '{"mood": {"enabled": true, "sort_order": 0}}'),
          isNull,
          reason: 'unknown profile: nothing to curate');

      await storage.softDeleteProfile(p.id);
      final tombstoned =
          await storage.getProfiles(includeTombstones: true).then((rows) =>
              rows.firstWhere((r) => r.id == p.id));
      expect(
        await storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": true, "sort_order": 0}}'),
        isNull,
        reason: 'curating a deleted profile is meaningless');
      expect(tombstoned.trackingPreferences, isNull);
    });

    test('setTrackingPreferences mirrors the server CHECK exactly (Issue '
        '#649): a document a well-formed client would never construct is '
        'rejected locally instead of poisoning the sync row on push',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);

      // An entry's value must itself be an object, not merely present.
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": "not-an-object"}'),
        throwsArgumentError,
      );
      // An entry carrying any key besides enabled/sort_order.
      expect(
        () => storage.setTrackingPreferences(p.id,
            '{"mood": {"enabled": true, "sort_order": 0, "extra": 1}}'),
        throwsArgumentError,
      );
      // enabled must be a boolean, not merely truthy.
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": "yes", "sort_order": 0}}'),
        throwsArgumentError,
      );
      // enabled is required, not just optional-and-defaulted.
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"sort_order": 0}}'),
        throwsArgumentError,
      );
      // sort_order must be present ...
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": true}}'),
        throwsArgumentError,
      );
      // ... an integer (the server's ^[0-9]{1,4}$ regex rejects a decimal
      // on the wire) ...
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": true, "sort_order": 1.5}}'),
        throwsArgumentError,
      );
      // ... never negative (no leading '-' in that regex) ...
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": true, "sort_order": -1}}'),
        throwsArgumentError,
      );
      // ... and at most 1000.
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"mood": {"enabled": true, "sort_order": 1001}}'),
        throwsArgumentError,
      );
      // Exactly 1000 and exactly 0 are both in bounds.
      final atUpperBound = await storage.setTrackingPreferences(
          p.id, '{"mood": {"enabled": true, "sort_order": 1000}}');
      expect(atUpperBound!.trackingPreferences,
          '{"mood": {"enabled": true, "sort_order": 1000}}');

      // A key that is empty, or over the server's 64-char bound.
      expect(
        () => storage.setTrackingPreferences(
            p.id, '{"": {"enabled": true, "sort_order": 0}}'),
        throwsArgumentError,
      );
      final tooLongKey = 'x' * (kMaxTrackingPreferencesKeyLength + 1);
      expect(
        () => storage.setTrackingPreferences(p.id,
            jsonEncode({tooLongKey: {'enabled': true, 'sort_order': 0}})),
        throwsArgumentError,
      );
      // Exactly at the 64-char bound is in bounds.
      final maxLengthKey = 'x' * kMaxTrackingPreferencesKeyLength;
      final atKeyBound = await storage.setTrackingPreferences(p.id,
          jsonEncode({maxLengthKey: {'enabled': true, 'sort_order': 0}}));
      expect(atKeyBound, isNotNull);

      // A valid document never rejected: the happy path stays open.
      final ok = await storage.setTrackingPreferences(
          p.id, '{"mood": {"enabled": false, "sort_order": 3}}');
      expect(ok!.trackingPreferences,
          '{"mood": {"enabled": false, "sort_order": 3}}');
    });

    test('setTrackingPreferences bounds the document’s entry count '
        '(Issue #649): a client-only bound the server CHECK does not '
        '(yet) enforce, so a runaway document fails fast locally', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);

      final tooMany = jsonEncode({
        for (var i = 0; i < kMaxTrackingPreferencesEntries + 1; i++)
          'category$i': {'enabled': true, 'sort_order': 0},
      });
      expect(
        () => storage.setTrackingPreferences(p.id, tooMany),
        throwsArgumentError,
      );

      // Exactly at the bound is accepted.
      final atBound = jsonEncode({
        for (var i = 0; i < kMaxTrackingPreferencesEntries; i++)
          'category$i': {'enabled': true, 'sort_order': 0},
      });
      final updated = await storage.setTrackingPreferences(p.id, atBound);
      expect(updated, isNotNull);
      final decoded =
          jsonDecode(updated!.trackingPreferences!) as Map<String, dynamic>;
      expect(decoded.length, kMaxTrackingPreferencesEntries);
    });

    test('a newer remote profile carrying a document applies it; the '
        'document rides every remote apply', () async {
      final p = await storage.upsertProfile(displayName: 'Local', isMinor: true);
      final newer = p.updatedAt.add(const Duration(seconds: 1));
      expect(
        await storage.applyRemoteProfile(remoteProfile(p.id,
            displayName: 'Remote',
            isMinor: true,
            updatedAt: newer,
            trackingPreferences:
                '{"partying": {"enabled": true, "sort_order": 0}}')),
        isTrue,
      );
      final row = await profileById(p.id);
      expect(row.trackingPreferences,
          '{"partying": {"enabled": true, "sort_order": 0}}');
      expect(row.dirty, isFalse);

      // A newer remote apply without the field clears it (full-row
      // semantics mirror the server's own update path).
      final evenNewer = newer.add(const Duration(seconds: 1));
      expect(
        await storage.applyRemoteProfile(remoteProfile(p.id,
            displayName: 'Remote2', isMinor: true, updatedAt: evenNewer)),
        isTrue,
      );
      expect((await profileById(p.id)).trackingPreferences, isNull);
    });
  });

  group('issue #637, LLA-039: unconfirmed post-upgrade defaults are never '
      'pushed over a real remote value', () {
    test('a profile marked unconfirmed (simulating the v12/v16 backfill) '
        'omits bbt_unit/weight_unit from its push payload while dirty for '
        'a reason that never touches the storage API\'s write paths '
        '(e.g. a sync retry re-marking dirty); a remote apply confirms it '
        'and the fields push again', () async {
      // A profile that already synced normally, then simulate what
      // `_upgradeToV16`'s backfill does to every row that predates the
      // column (db.dart; storage exposes no public API for this — it is
      // migration-only bookkeeping) — and simulate becoming dirty again
      // through something other than the storage API's own write paths
      // (bumpLocalRevForRetry: a rejected push retried, content
      // untouched), since every real local write path now clears the
      // marker itself (issue #637 review, bug 1).
      final p = await storage.upsertProfile(
          displayName: 'P', isMinor: false, bbtUnit: 'fahrenheit');
      await storage.markPushed(
          table: SyncTable.profiles,
          id: p.id,
          localRevAtPush: p.localRev);
      await (db.update(db.profiles)..where((t) => t.id.equals(p.id)))
          .write(const ProfilesCompanion(unitsUnconfirmed: Value(true)));
      await storage.bumpLocalRevForRetry(
          table: SyncTable.profiles, id: p.id);

      final dirty = await profileById(p.id);
      expect(dirty.dirty, isTrue);
      final payload = encodeProfile(dirty);
      expect(payload, isNot(contains('bbt_unit')),
          reason: 'still unconfirmed: must not push the possibly-stale '
              'default over whatever the server actually has');
      expect(payload, isNot(contains('weight_unit')));
      expect(payload['display_name'], 'P',
          reason: 'the rest of the row still pushes normally — only the '
              'two unconfirmed preferences are withheld');

      // A pull delivers the server's real (different) value: the remote
      // apply confirms the row regardless of who wins the per-id rule
      // here (a fresh insert-from-remote always confirms).
      const remoteId2 = '01J0000000000000000000003A';
      await storage.applyRemoteProfile(RemoteProfileRow(
        id: remoteId2,
        displayName: 'Remote',
        isMinor: false,
        sortOrder: 0,
        archivedAt: null,
        createdAt: t0,
        updatedAt: t0,
        deletedAt: null,
        bbtUnit: 'celsius',
        weightUnit: 'kg',
      ));
      final confirmed = (await storage.getProfiles())
          .firstWhere((row) => row.id == remoteId2);
      expect(encodeProfile(confirmed), contains('bbt_unit'),
          reason: 'once confirmed by a real remote delivery, the '
              'preference pushes again like any other column');
    });

    test('bug 3 (issue #637 review round 2): a profile edit that leaves '
        'bbt_unit/weight_unit unchanged — upsertProfile\'s full-row write '
        'merely carrying the still-unconfirmed value through, e.g. a '
        'display-name-only edit — must NOT clear unitsUnconfirmed, or '
        'the unrelated edit\'s own push would clobber the server\'s real '
        'preference (the residual LLA-039 clobber bug 1\'s original '
        'unconditional clear reintroduced)', () async {
      final p = await storage.upsertProfile(
          displayName: 'P', isMinor: false, bbtUnit: 'fahrenheit');
      await (db.update(db.profiles)..where((t) => t.id.equals(p.id)))
          .write(const ProfilesCompanion(unitsUnconfirmed: Value(true)));

      // upsertProfile is a full-row write, so bbtUnit/weightUnit ride
      // along on every call — but this edit only actually changes
      // displayName; the preference values are unchanged.
      final edited = await storage.upsertProfile(
        id: p.id,
        displayName: 'P renamed',
        isMinor: false,
        bbtUnit: 'fahrenheit',
      );
      expect(edited.dirty, isTrue);
      expect(edited.unitsUnconfirmed, isTrue,
          reason: 'bug 3: an edit that does not actually change bbt_unit/'
              'weight_unit must leave the marker alone');
      final payload = encodeProfile(edited);
      expect(payload, isNot(contains('bbt_unit')),
          reason: 'still unconfirmed: the unrelated edit must not push '
              'the possibly-stale bbt_unit/weight_unit over the '
              'server\'s real value');
      expect(payload, isNot(contains('weight_unit')));
      expect(payload['display_name'], 'P renamed',
          reason: 'the real edit still pushes normally');
    });

    test('bug 3 (issue #637 review round 2): a profile edit that '
        'actually changes bbt_unit clears unitsUnconfirmed, so the new '
        'preference pushes on that very edit', () async {
      final p = await storage.upsertProfile(
          displayName: 'P', isMinor: false, bbtUnit: 'fahrenheit');
      await (db.update(db.profiles)..where((t) => t.id.equals(p.id)))
          .write(const ProfilesCompanion(unitsUnconfirmed: Value(true)));

      final edited = await storage.upsertProfile(
        id: p.id,
        displayName: 'P',
        isMinor: false,
        bbtUnit: 'celsius',
      );
      expect(edited.dirty, isTrue);
      expect(edited.unitsUnconfirmed, isNot(true),
          reason: 'a write that actually changes bbt_unit must confirm it');
      final payload = encodeProfile(edited);
      expect(payload, contains('bbt_unit'),
          reason: 'the newly-set preference must push on this very edit');
      expect(payload['bbt_unit'], 'celsius');
      expect(payload['weight_unit'], 'kg');
    });

    test('a day entry marked unconfirmed (simulating the v12 backfill) '
        'omits pms from its push payload while dirty for a reason that '
        'never touches the storage API\'s write paths; a remote apply '
        'confirms it and pms pushes again', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-19',
        tz: 'UTC',
        flow: FlowLevel.medium,
        pms: true,
      );
      await storage.markPushed(
          table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev);
      await (db.update(db.dayEntries)..where((t) => t.id.equals(e.id)))
          .write(const DayEntriesCompanion(pmsUnconfirmed: Value(true)));
      await storage.bumpLocalRevForRetry(
          table: SyncTable.dayEntries, id: e.id);

      final dirty = await entryById(p.id, e.id);
      expect(dirty.dirty, isTrue);
      final payload = encodeDayEntry(dirty);
      expect(payload, isNot(contains('pms')),
          reason: 'still unconfirmed: must not push the possibly-stale '
              'default over whatever the server actually has');
      expect(payload['flow'], 'medium',
          reason: 'the rest of the row still pushes normally — only pms '
              'is withheld');

      await storage.applyRemoteDayEntry(remoteEntry(
        e.id,
        profileId: p.id,
        localDate: '2026-09-19',
        pms: false,
        updatedAt: dirty.updatedAt.add(const Duration(minutes: 1)),
      ));
      final confirmed = await entryById(p.id, e.id);
      expect(encodeDayEntry(confirmed), contains('pms'),
          reason: 'once confirmed by a real remote delivery, pms pushes '
              'again like any other column');
    });

    test('bug 3 (issue #637 review round 2): a day-entry edit that leaves '
        'pms unchanged — a note-only edit, upsertDayEntry\'s full-row '
        'write merely carrying the still-unconfirmed pms through — must '
        'NOT clear pmsUnconfirmed, or the unrelated edit\'s own push '
        'would clobber the server\'s real pms (the residual LLA-039 '
        'clobber the coordinator\'s round-2 review flagged: DaySheet '
        'saving a note edit while pms rides along at its stale default)',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-20',
        tz: 'UTC',
        flow: FlowLevel.medium,
        pms: true,
      );
      await (db.update(db.dayEntries)..where((t) => t.id.equals(e.id)))
          .write(const DayEntriesCompanion(pmsUnconfirmed: Value(true)));

      // upsertDayEntry is a full-row write, so pms rides along on every
      // call — but this edit only actually changes note; pms is
      // unchanged.
      final edited = await storage.upsertDayEntry(
        id: e.id,
        profileId: p.id,
        localDate: '2026-09-20',
        tz: 'UTC',
        flow: FlowLevel.medium,
        note: 'a note',
        pms: true,
      );
      expect(edited.dirty, isTrue);
      expect(edited.pmsUnconfirmed, isTrue,
          reason: 'bug 3: an edit that does not actually change pms must '
              'leave the marker alone');
      final payload = encodeDayEntry(edited);
      expect(payload, isNot(contains('pms')),
          reason: 'still unconfirmed: the unrelated (note) edit must not '
              'push the possibly-stale pms over the server\'s real value');
      expect(payload['note'], 'a note',
          reason: 'the real edit still pushes normally');
    });

    test('bug 3 (issue #637 review round 2): a day-entry edit that '
        'actually changes pms clears pmsUnconfirmed, so pms pushes on '
        'that very edit', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-21',
        tz: 'UTC',
        flow: FlowLevel.medium,
        pms: true,
      );
      await (db.update(db.dayEntries)..where((t) => t.id.equals(e.id)))
          .write(const DayEntriesCompanion(pmsUnconfirmed: Value(true)));

      final edited = await storage.upsertDayEntry(
        id: e.id,
        profileId: p.id,
        localDate: '2026-09-21',
        tz: 'UTC',
        flow: FlowLevel.medium,
        pms: false,
      );
      expect(edited.dirty, isTrue);
      expect(edited.pmsUnconfirmed, isNot(true),
          reason: 'a write that actually changes pms must confirm it');
      final payload = encodeDayEntry(edited);
      expect(payload, contains('pms'),
          reason: 'the newly-set pms must push on this very edit');
      expect(payload['pms'], false);
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
        tags: const ['cramps'],
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: local.id,
        localRevAtPush: local.localRev,
      );

      const remoteId = '01J0000000000000000000001M';
      final older = local.updatedAt.subtract(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          remoteId,
          profileId: p.id,
          localDate: '2026-09-10',
          tags: const ['heavy_flow'],
          updatedAt: older,
        ),
      );

      final winner = await entryById(p.id, local.id);
      expect(winner.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(winner.dirty, isTrue, reason: 'the merge must be pushed');
      expect(winner.localRev, local.localRev + 1);
      expect(winner.deletedAt, isNull);

      final loser = await entryById(p.id, remoteId);
      expect(
        loser.deletedAt,
        isNotNull,
        reason: 'the remote loser is a tombstone',
      );
      expect(loser.tags, isEmpty, reason: 'R12: tombstones are payload-free');
      expect(loser.note, isNull);
      expect(
        loser.flow,
        FlowLevel.none,
        reason:
            'issue #224: flow is part of the R12 payload-free '
            'guarantee too',
      );
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
        note: 'local note',
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: local.id,
        localRevAtPush: local.localRev,
      );

      const remoteId = '01J0000000000000000000001N';
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          remoteId,
          profileId: p.id,
          localDate: '2026-09-11',
          tags: const ['heavy_flow'],
          note: 'remote note',
          updatedAt: newer,
        ),
      );

      final winner = await entryById(p.id, remoteId);
      expect(winner.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(
        winner.note,
        'remote note',
        reason: 'R8: note stays last-writer-wins, unaffected by the tag merge',
      );
      expect(winner.deletedAt, isNull);
      expect(winner.dirty, isTrue, reason: 'the merge must be pushed');
      expect(winner.localRev, 1);
      expect(winner.updatedAt, newer.add(const Duration(milliseconds: 1)),
          reason: 'LLA-038 (issue #639): a merge that leaves the remote row '
              'the live survivor must be stamped strictly after the '
              'server-known timestamp it arrived with, never tied to it');

      final loser = await entryById(p.id, local.id);
      expect(loser.deletedAt, newer);
      expect(loser.tags, isEmpty);
      expect(loser.note, isNull);
      expect(
        loser.flow,
        FlowLevel.none,
        reason:
            'issue #224: flow is part of the R12 payload-free '
            'guarantee too',
      );
      expect(loser.dirty, isTrue, reason: 'a local loser must be pushed');
    });

    test(
        'LLA-038 (issue #639): a replay of the exact pre-merge remote row '
        'never wipes the tag union or re-clears dirty', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-16',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['cramps'],
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: local.id,
        localRevAtPush: local.localRev,
      );

      const remoteId = '01J0000000000000000000001P';
      final newer = local.updatedAt.add(const Duration(minutes: 5));
      final winningRemote = remoteEntry(
        remoteId,
        profileId: p.id,
        localDate: '2026-09-16',
        tags: const ['heavy_flow'],
        updatedAt: newer,
      );

      // First delivery: the merge lands as expected.
      await storage.applyRemoteDayEntry(winningRemote);
      final merged = await entryById(p.id, remoteId);
      expect(merged.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(merged.dirty, isTrue);

      // A replay of the identical, still-unpushed-by-the-server row — a
      // duplicate pull page, or the 24h reconcile's lookback window
      // re-fetching a row it has already delivered. The local loser is
      // long gone (tombstoned in the first apply), so a naive re-run of
      // the same-date resolver would find no collision, reset tags to the
      // wire-bare `remote.tags`, and clear `dirty` — silently discarding
      // the merge. The bumped `updated_at` from the first apply must
      // outrank this replay's unchanged, pre-merge stamp instead.
      final replayed = await storage.applyRemoteDayEntry(winningRemote);
      expect(replayed, isFalse,
          reason: 'the replay must lose to the already-merged local row, '
              'not re-run the resolver against it');

      final afterReplay = await entryById(p.id, remoteId);
      expect(afterReplay.tags, unorderedEquals(['cramps', 'heavy_flow']),
          reason: 'the tag union must survive an exact-timestamp replay');
      expect(afterReplay.dirty, isTrue,
          reason: 'the pending merge must still be queued for push after '
              'the replay');
    });

    test('issue #663 (LLA-038 mirror of #662): a local row that wins the '
        'same-date rule and absorbs a remote loser\'s tags is stamped '
        'strictly after the incoming remote timestamp, never tied to it',
        () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      // A "clean pulled copy" (issue #663's own precondition): applied from
      // remote, so dirty = false and updated_at is exactly what the server
      // already stores for this row's id — not a fresh local write.
      final localId = '01J0000000000000000000002A';
      final t0 = DateTime.utc(2026, 9, 17, 10);
      await storage.applyRemoteDayEntry(remoteEntry(
        localId,
        profileId: p.id,
        localDate: '2026-09-17',
        tags: const ['cramps'],
        updatedAt: t0,
      ));
      final local = await entryById(p.id, localId);
      expect(local.dirty, isFalse);
      expect(local.updatedAt, t0);

      // A remote loser for the same date, older, carrying a different tag.
      const remoteId = '01J0000000000000000000002B';
      final older = t0.subtract(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(
        remoteId,
        profileId: p.id,
        localDate: '2026-09-17',
        tags: const ['heavy_flow'],
        updatedAt: older,
      ));

      final winner = await entryById(p.id, localId);
      expect(winner.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(winner.dirty, isTrue, reason: 'the merge must be pushed');
      expect(winner.localRev, local.localRev + 1);
      expect(winner.updatedAt, t0.add(const Duration(milliseconds: 1)),
          reason: 'issue #663: a local survivor that absorbs new tags must '
              'be stamped strictly after its own prior (server-known) '
              'timestamp, never left tied to it — the same rule #662 '
              'already applies to a remote survivor');

      final loser = await entryById(p.id, remoteId);
      expect(loser.deletedAt, isNotNull);
      expect(loser.tags, isEmpty);
    });

    test('issue #663: without a strictly-after stamp, a local survivor\'s '
        'absorbed tags would be lost to a later ordinary pull of its own '
        'id still holding the server\'s pre-merge value — the bumped '
        'stamp makes that pull lose instead', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final localId = '01J0000000000000000000002C';
      final t0 = DateTime.utc(2026, 9, 18, 10);
      await storage.applyRemoteDayEntry(remoteEntry(
        localId,
        profileId: p.id,
        localDate: '2026-09-18',
        tags: const ['cramps'],
        updatedAt: t0,
      ));

      const remoteLoserId = '01J0000000000000000000002D';
      final older = t0.subtract(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(remoteEntry(
        remoteLoserId,
        profileId: p.id,
        localDate: '2026-09-18',
        tags: const ['heavy_flow'],
        updatedAt: older,
      ));
      final merged = await entryById(p.id, localId);
      expect(merged.tags, unorderedEquals(['cramps', 'heavy_flow']));
      expect(merged.updatedAt, t0.add(const Duration(milliseconds: 1)));

      // The merge was never (yet) accepted by the server: a later ordinary
      // pull page still redelivers `localId` at the server's old, pre-merge
      // value (updated_at = t0, tags = ['cramps']). Pre-#663, `merged`'s
      // stored stamp would still have been exactly t0 too — a tie, and
      // KTD5 says the remote copy wins ties — silently overwriting the
      // union with the server's bare tags and clearing dirty. With the
      // strictly-after stamp, this delivery is now strictly OLDER than
      // what is stored locally and must lose outright.
      final applied = await storage.applyRemoteDayEntry(remoteEntry(
        localId,
        profileId: p.id,
        localDate: '2026-09-18',
        tags: const ['cramps'],
        updatedAt: t0,
      ));
      expect(applied, isFalse,
          reason: 'the server\'s stale pre-merge copy must lose to the '
              'already-merged, strictly-newer local row');

      final afterPull = await entryById(p.id, localId);
      expect(afterPull.tags, unorderedEquals(['cramps', 'heavy_flow']),
          reason: 'the tag union must survive a pull of the pre-merge value');
      expect(afterPull.dirty, isTrue,
          reason: 'the pending merge must still be queued for push');
    });

    test('a remote tombstone for a date with a live local row never '
        'attempts a merge - tombstones never compete', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-12',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['cramps'],
      );

      const remoteId = '01J0000000000000000000001O';
      final t = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          remoteId,
          profileId: p.id,
          localDate: '2026-09-12',
          updatedAt: t,
          deletedAt: t,
        ),
      );

      final unaffected = await entryById(p.id, local.id);
      expect(unaffected.deletedAt, isNull);
      expect(unaffected.tags, [
        'cramps',
      ], reason: 'a tombstone never merges tags into a live row');
      final tomb = await entryById(p.id, remoteId);
      expect(tomb.deletedAt, t);
      expect(tomb.tags, isEmpty);
      expect(
        tomb.flow,
        FlowLevel.none,
        reason:
            'issue #224: a row that arrives already tombstoned is '
            'defensively cleared to FlowLevel.none too, even though this '
            'fixture still sends the remoteEntry() default '
            'FlowLevel.medium - the client does not merely trust the '
            'server to have cleared it',
      );
    });

    test('a same-id remote row that drops a tag still drops it locally - no '
        'union on the same-id path (R10)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final local = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-09-13',
        tz: 'UTC',
        flow: FlowLevel.medium,
        tags: const ['a', 'b'],
      );

      final newer = local.updatedAt.add(const Duration(minutes: 5));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          local.id,
          profileId: p.id,
          localDate: '2026-09-13',
          tags: const ['a'],
          updatedAt: newer,
        ),
      );

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
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000201A',
          profileId: p.id,
          localDate: '2026-09-14',
          tags: const ['a'],
          updatedAt: tA,
        ),
      );
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000201B',
          profileId: p.id,
          localDate: '2026-09-14',
          tags: const ['b'],
          updatedAt: tB,
        ),
      );
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000201C',
          profileId: p.id,
          localDate: '2026-09-14',
          tags: const ['c'],
          updatedAt: tC,
        ),
      );
      final ascendingLive = await liveFor(p.id, '2026-09-14');
      expect(ascendingLive.single.tags, unorderedEquals(['a', 'b', 'c']));

      // Descending arrival order, a different date so this run is
      // independent of the one above.
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000202C',
          profileId: p.id,
          localDate: '2026-09-15',
          tags: const ['c'],
          updatedAt: tC,
        ),
      );
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000202B',
          profileId: p.id,
          localDate: '2026-09-15',
          tags: const ['b'],
          updatedAt: tB,
        ),
      );
      await storage.applyRemoteDayEntry(
        remoteEntry(
          '01J000000000000000000202A',
          profileId: p.id,
          localDate: '2026-09-15',
          tags: const ['a'],
          updatedAt: tA,
        ),
      );
      final descendingLive = await liveFor(p.id, '2026-09-15');
      expect(descendingLive.single.tags, unorderedEquals(['a', 'b', 'c']));
    });

    test('a merge on a profile absent locally still raises before any merge '
        'work runs - ordering unchanged', () async {
      await expectLater(
        storage.applyRemoteDayEntry(
          remoteEntry(
            '01J000000000000000000203A',
            profileId: '01J000000000000000000203P',
            tags: const ['a'],
            updatedAt: t0,
          ),
        ),
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
        note: 'local',
      );
      final resolvedAt = e.updatedAt.add(const Duration(seconds: 1));
      await storage.applyResolved([
        remoteEntry(
          '01J0000000000000000000000U',
          profileId: p.id,
          localDate: '2026-02-01',
          updatedAt: t0,
        ),
        remoteProfile('01J0000000000000000000000V', updatedAt: t0),
        remoteEntry(
          e.id,
          profileId: p.id,
          updatedAt: resolvedAt,
          deletedAt: resolvedAt,
          note: 'dropped',
        ),
      ]);
      final all = await storage.getDayEntries(
        profileId: p.id,
        includeTombstones: true,
      );
      expect(all.map((r) => r.id), [
        e.id,
      ], reason: 'unknown ids must not be inserted');
      expect(all.single.deletedAt, resolvedAt);
      expect(all.single.note, isNull);
      expect(all.single.dirty, isFalse);
      expect(
        (await storage.getProfiles(includeTombstones: true)).map((r) => r.id),
        [p.id],
      );
    });

    test('a resolved merge event and profile_tag_registry row each take '
        'the server copy clean (Issue #257 keeps applyResolved flat at '
        'the CRAP ceiling — every per-table loop body stays covered)', () async {
      await storage.applyResolved([
        RemoteDayEntryMergeEventRow(
          id: '01J0000000000000000000000M',
          profileId: 'unknown-profile',
          localDate: '2026-01-15',
          winningRowId: '01J0000000000000000000000W',
          losingRowId: '01J0000000000000000000000L',
          field: 'note',
          losingValueText: 'resolution is a no-op for an unheld id',
          createdAt: t0,
          updatedAt: t0,
        ),
      ]);
      expect(
        await (db.select(db.dayEntryMergeEvents).get()),
        isEmpty,
        reason: 'a resolution never inserts (onlyExisting)',
      );
    });

    test('a resolved profile_tag_registry row takes the server copy clean '
        '(Issue #257)', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final created = await storage.upsertProfileTagRegistryEntry(
        profileId: p.id,
        code: 'resolved_tag',
        displayName: 'Local label',
      );
      final resolvedAt = created.updatedAt.add(const Duration(seconds: 1));
      await storage.applyResolved([
        RemoteProfileTagRegistryRow(
          id: created.id,
          profileId: p.id,
          code: 'resolved_tag',
          displayName: 'Server label',
          category: 'custom',
          createdAt: t0,
          updatedAt: resolvedAt,
          deletedAt: null,
        ),
      ]);
      final rows = await storage.getProfileTagRegistry(p.id);
      expect(rows.single.displayName, 'Server label',
          reason: 'the server copy wins an equal-timestamp decline');
      expect(rows.single.dirty, isFalse,
          reason: 'a resolved row is never pushed back');
      expect(
        await storage.readDirtyProfileTagRegistry(),
        isEmpty,
      );
    });

    test('a later live remote edit to a resolved loser revives it and '
        're-runs the same-date rule', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final a = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-03-03',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      // Resolution tombstones `a` in favour of remote `b`.
      const b = '01J0000000000000000000000B';
      final tRes = a.updatedAt.add(const Duration(minutes: 1));
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: [
          remoteEntry(
            b,
            profileId: p.id,
            localDate: '2026-03-03',
            updatedAt: tRes,
          ),
        ],
        newCursor: 10,
      );
      expect((await liveFor(p.id, '2026-03-03')).single.id, b);
      expect((await entryById(p.id, a.id)).deletedAt, tRes);

      // A newer live edit to `a` arrives: revived, and it now beats `b`.
      final tRevive = tRes.add(const Duration(minutes: 1));
      await storage.applyRemoteDayEntry(
        remoteEntry(
          a.id,
          profileId: p.id,
          localDate: '2026-03-03',
          updatedAt: tRevive,
          note: 'revived',
        ),
      );
      final live = await liveFor(p.id, '2026-03-03');
      expect(live.single.id, a.id);
      expect(live.single.note, 'revived');
      final bRow = await entryById(p.id, b);
      expect(bRow.deletedAt, tRevive);
      expect(bRow.dirty, isTrue, reason: 'b was a local live row that lost');
    });
  });

  group('applyPushResult (issue #523: atomic accepted + resolved apply)', () {
    test('a failure applying a resolved row rolls back every markPushed '
        'write from the same call — nothing is half-committed', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
        note: 'local',
      );
      expect(e.dirty, isTrue);
      expect(e.localRev, 1);

      // A resolved row for the SAME local id (so `onlyExisting` does not
      // skip it) whose profile is not held locally — `_applyDayEntry`
      // throws `RetryableSyncApplyError` from `_ensureDayEntryProfileExists`
      // partway through the resolved half of the call, *after* the accepted
      // half's `markPushed` write for `e` has already run inside the same
      // transaction.
      final badResolved = remoteEntry(
        e.id,
        profileId: 'profile-not-held-locally',
        localDate: e.localDate,
        updatedAt: e.updatedAt.add(const Duration(seconds: 1)),
      );

      await expectLater(
        storage.applyPushResult(
          accepted: [
            (table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev),
          ],
          resolved: [badResolved],
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );

      final reread = await entryById(p.id, e.id);
      expect(
        reread.dirty,
        isTrue,
        reason:
            'the markPushed write inside the same transaction as the '
            'failing resolved apply must have rolled back too — this is '
            'exactly the divergence issue #523 describes: a declined row '
            'left dirty = false holding the losing value forever',
      );
      expect(reread.localRev, e.localRev);
      expect(
        reread.note,
        'local',
        reason: 'the resolved apply itself must never have landed either',
      );
    });

    test('a clean call clears dirty on every accepted row and applies every '
        'resolved row, in one pass', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
        note: 'local',
      );
      final resolvedAt = e.updatedAt.add(const Duration(seconds: 1));

      await storage.applyPushResult(
        accepted: [
          (table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev),
        ],
        resolved: [
          remoteEntry(
            e.id,
            profileId: p.id,
            updatedAt: resolvedAt,
            note: 'server wins',
          ),
        ],
      );

      final rereadProfile = await profileById(p.id);
      expect(rereadProfile.dirty, isFalse);
      final rereadEntry = await entryById(p.id, e.id);
      expect(rereadEntry.dirty, isFalse);
      expect(rereadEntry.note, 'server wins');
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
          remoteEntry(
            r1,
            profileId: p.id,
            localDate: '2026-04-01',
            updatedAt: t0,
          ),
          remoteEntry(
            r2,
            profileId: p.id,
            localDate: '2026-04-02',
            updatedAt: t0,
          ),
        ],
        newCursor: 42,
      );
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
            remoteEntry(
              r3,
              profileId: p.id,
              localDate: '2026-04-03',
              updatedAt: t0,
            ),
            remoteEntry(
              '01J0000000000000000000000F',
              profileId: '01J0000000000000000000000Q',
              updatedAt: t0,
            ),
          ],
          newCursor: 99,
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      state = await storage.readSyncState();
      expect(state.cursorDayEntries, 42, reason: 'cursor must not advance');
      expect(
        (await storage.getDayEntries(profileId: p.id)).map((e) => e.id),
        isNot(contains(r3)),
        reason: 'the good row of a failed page rolls back too',
      );

      // Profiles page advances only the profiles cursor.
      await storage.applyRemotePage(
        table: SyncTable.profiles,
        rows: [remoteProfile('01J0000000000000000000000G', updatedAt: t0)],
        newCursor: 7,
      );
      state = await storage.readSyncState();
      expect(state.cursorProfiles, 7);
      expect(state.cursorDayEntries, 42);

      // A row of the wrong table is rejected up front.
      await expectLater(
        storage.applyRemotePage(
          table: SyncTable.profiles,
          rows: [remoteEntry(r1, profileId: p.id, updatedAt: t0)],
          newCursor: 8,
        ),
        throwsArgumentError,
      );
      expect((await storage.readSyncState()).cursorProfiles, 7);
    });

    // Issue #102: the transaction around a page is load-bearing, and the
    // test above could not prove that by itself — it pins the real path's
    // outcome but never demonstrates the divergence shape the transaction
    // prevents, so a reader (or a refactor) could mistake it for redundant
    // wrapping. This test runs the SAME mid-page failure both ways:
    // without a page-level transaction (each row its own committed write —
    // the public per-row applies, i.e. exactly what a regression that
    // drops `applyRemotePage`'s `db.transaction()` silently reverts to) a
    // failure at row k leaves rows <k stored while the cursor write is
    // never reached — rows and cursor describing different worlds. The
    // real path under the same failure keeps them together: nothing
    // lands, the cursor does not move. Removing the transaction (or
    // moving the cursor write ahead of the row loop so a later row's
    // failure strands an advanced cursor) fails the second half.
    test('issue #102: a mid-page failure diverges rows and cursor without '
        'the one-transaction contract; the real path keeps them together '
        'under the same failure', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);

      // The no-transaction variant: the same page shape a pull delivers
      // (good row, then a row referencing a profile this device does not
      // hold), applied one committed write per row instead of one page
      // transaction. This is the documented divergence the transaction
      // exists to prevent, not a behavior anyone wants.
      const v1 = '01J0000000000000000000000V';
      final variantRows = [
        remoteEntry(v1,
            profileId: p.id, localDate: '2026-06-01', updatedAt: t0),
        remoteEntry('01J0000000000000000000000W',
            profileId: '01J0000000000000000000000Q',
            localDate: '2026-06-02',
            updatedAt: t0),
      ];
      await storage.applyRemoteDayEntry(variantRows[0]);
      await expectLater(
        storage.applyRemoteDayEntry(variantRows[1]),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect(
        (await storage.getDayEntries(profileId: p.id)).map((e) => e.id),
        contains(v1),
        reason: 'the un-transactional variant commits row 1 — this is the '
            'divergence shape',
      );
      expect((await storage.readSyncState()).cursorDayEntries, 0,
          reason: 'the un-transactional variant never reaches the cursor '
              'write: rows and cursor have diverged');

      // The real path, same failure injection, distinct row ids (the
      // variant above already stored v1, and a rollback must be able to
      // prove a *fresh* row did not land).
      const r1 = '01J0000000000000000000000X';
      await expectLater(
        storage.applyRemotePage(
          table: SyncTable.dayEntries,
          rows: [
            remoteEntry(r1,
                profileId: p.id, localDate: '2026-06-03', updatedAt: t0),
            remoteEntry('01J0000000000000000000000Y',
                profileId: '01J0000000000000000000000Q',
                localDate: '2026-06-04',
                updatedAt: t0),
          ],
          newCursor: 50,
        ),
        throwsA(isA<RetryableSyncApplyError>()),
      );
      expect(
        (await storage.getDayEntries(profileId: p.id)).map((e) => e.id),
        isNot(contains(r1)),
        reason: 'the good row of the failed page rolled back with it — '
            'had applyRemotePage lost its transaction it would behave like '
            'the variant above and land',
      );
      expect((await storage.readSyncState()).cursorDayEntries, 0,
          reason: 'the cursor rolled back with the rows: one world, not two');
    });

    test('issue #525: profileGuardians now persists its own cursor, '
        'independent of every other table', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.applyRemotePage(
        table: SyncTable.profileGuardians,
        rows: [
          RemoteProfileGuardianRow(
            id: 'g-1',
            profileId: p.id,
            userId: 'user-a',
            role: 'viewer',
            status: 'accepted',
            createdAt: t0,
            updatedAt: t0,
          ),
        ],
        newCursor: 17,
      );
      final state = await storage.readSyncState();
      expect(state.cursorProfileGuardians, 17);
      expect(
        state.cursorProfiles,
        0,
        reason:
            'profileGuardians\' cursor must not bleed into another '
            'table\'s',
      );
    });
  });

  group('clock offset', () {
    test(
      'a +5 minute offset stamps local writes ahead of the test clock and '
      'a later write behind the stored value still lands strictly after',
      () async {
        final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
        final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light,
        );
        expect(e.updatedAt, t0);

        storage.setClockOffset(const Duration(minutes: 5));
        clock.now = t0.add(const Duration(seconds: 1));
        final shifted = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy,
        );
        expect(
          shifted.updatedAt,
          t0.add(const Duration(minutes: 5, seconds: 1)),
        );

        // Offset dropped: the raw clock is now behind the stored value.
        storage.setClockOffset(Duration.zero);
        clock.now = t0.add(const Duration(seconds: 2));
        final bumped = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.none,
        );
        expect(
          bumped.updatedAt,
          shifted.updatedAt.add(const Duration(milliseconds: 1)),
        );

        // Profiles and deletes use the same clock.
        storage.setClockOffset(const Duration(minutes: 5));
        await storage.softDeleteProfile(p.id);
        expect(
          (await profileById(p.id)).updatedAt,
          t0.add(const Duration(minutes: 5, seconds: 2)),
        );
        expect(storage.clockOffset, const Duration(minutes: 5));
      },
    );
  });

  group('local edit after a remote apply', () {
    test('a local edit with the clock 1s behind the applied remote row is '
        'stamped remote + 1ms and stays dirty, never equal to the server '
        'copy', () async {
      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      final remoteAt = t0.add(const Duration(minutes: 10));
      const rid = 'remote-entry-1';
      await storage.applyRemoteDayEntry(
        remoteEntry(
          rid,
          profileId: p.id,
          localDate: '2026-01-20',
          updatedAt: remoteAt,
        ),
      );
      var row = await entryById(p.id, rid);
      expect(row.updatedAt, remoteAt);
      expect(row.dirty, isFalse);

      clock.now = remoteAt.subtract(const Duration(seconds: 1));
      final edited = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-20',
        tz: 'UTC',
        flow: FlowLevel.heavy,
      );
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
        await storage.applyRemoteDayEntry(
          remoteEntry(
            rid,
            profileId: p.id,
            localDate: '2026-01-20',
            updatedAt: remoteAt,
          ),
        ),
        isFalse,
      );
      expect((await entryById(p.id, rid)).flow, FlowLevel.heavy);
    });
  });

  group('bulk state', () {
    test('markAllDirty flags live and tombstoned rows; isEmpty only when both '
        'tables have no rows at all; dirtyCount includes tombstones', () async {
      expect(await storage.isEmpty(), isTrue);
      expect(await storage.dirtyCount(), 0);

      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      expect(await storage.isEmpty(), isFalse);
      final e1 = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-16',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      await storage.softDeleteDayEntry(
        profileId: p.id,
        localDate: '2026-01-16',
      );
      expect(await storage.dirtyCount(), 3);

      await storage.markPushed(
        table: SyncTable.profiles,
        id: p.id,
        localRevAtPush: p.localRev,
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: e1.id,
        localRevAtPush: e1.localRev,
      );
      expect(
        await storage.dirtyCount(),
        1,
        reason: 'the tombstone stays dirty',
      );

      await storage.markAllDirty();
      expect(await storage.dirtyCount(), 3);
      final rows = await storage.getDayEntries(
        profileId: p.id,
        includeTombstones: true,
      );
      expect(rows.every((r) => r.dirty), isTrue);
      expect((await profileById(p.id)).dirty, isTrue);

      // A tombstone-only database is not empty.
      await storage.softDeleteDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
      );
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

      await storage.writeSyncState(
        defaults.copyWith(
          boundUserId: const Value('user-1'),
          deviceId: 'device-1',
          cursorProfiles: 3,
          cursorDayEntries: 4,
          lastSyncAt: Value(t0),
          serverClockOffsetMs: const Value(1500),
        ),
      );
      final stored = await storage.readSyncState();
      expect(stored.boundUserId, 'user-1');
      expect(stored.deviceId, 'device-1');
      expect(stored.cursorProfiles, 3);
      expect(stored.cursorDayEntries, 4);
      expect(stored.lastSyncAt, t0);
      expect(stored.serverClockOffsetMs, 1500);

      // Overwrite keeps the singleton a singleton.
      await storage.writeSyncState(stored.copyWith(cursorProfiles: 5));
      final count = await db
          .customSelect('SELECT COUNT(*) AS n FROM sync_state')
          .getSingle();
      expect(count.data['n'], 1);
      expect((await storage.readSyncState()).cursorProfiles, 5);

      // The id CHECK forbids a second row.
      await expectLater(
        db.customStatement(
          "INSERT INTO sync_state (id, device_id) VALUES (2, 'x')",
        ),
        throwsA(anything),
      );

      final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
      await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
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

  group('revocation wipe (issue #532)', () {
    /// Every table in `tables.dart` carrying a `profile_id` column,
    /// discovered from the live schema rather than hand-copied — so a new
    /// profile-scoped table added later shows up here automatically.
    Set<String> profileScopedTableNames() => {
      for (final table in db.allTables)
        if (table.$columns.any((c) => c.name == 'profile_id'))
          table.actualTableName,
    };

    /// The set [profileScopedTableNames] must equal today. Deliberately
    /// hand-maintained (not derived) so adding a new profile_id-bearing
    /// table without updating this set — and without extending the
    /// revocation-wipe assertions below to cover it — fails loudly here,
    /// rather than silently keeping a removed guardian's access to that
    /// table's content alive on their device (exactly the bug class issue
    /// #532 was).
    const kKnownProfileScopedTables = {
      'day_entries',
      'profile_guardians',
      'observations',
      'profile_modes',
      'cycle_overrides',
      'care_notes',
      'visit_prep_items',
      'day_entry_merge_events',
      'profile_tag_registry',
      'day_entry_history',
      'guardian_notes',
    };

    test('tables.dart\'s profile_id-bearing tables match the set this '
        'file\'s wipe coverage below is written against', () {
      expect(
        profileScopedTableNames(),
        kKnownProfileScopedTables,
        reason:
            'a table with a new profile_id column was added to tables.dart '
            '— add it to kKnownProfileScopedTables above AND to the '
            'coverage assertions in the test below (and, if it holds '
            'sync content rather than membership metadata, to '
            '_tombstoneRevokedSharedProfile\'s wipe itself), or a removed '
            'guardian keeps that table\'s content on their device forever',
      );
    });

    test('every profile-scoped content table (all but the membership row '
        'itself) has no live row left after a revocation apply', () async {
      const uid = 'user-a';
      await storage.writeSyncState(
        kDefaultSyncState.copyWith(boundUserId: const Value(uid)),
      );

      final p = await storage.upsertProfile(
        displayName: 'Shared',
        isMinor: false,
      );
      final entry = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
        note: 'symptom log',
      );
      await storage.upsertObservation(
        dayEntryId: entry.id,
        profileId: p.id,
        localDate: entry.localDate,
        tz: 'UTC',
        category: 'pain',
        code: 'migraine',
        intensity: 3,
      );
      await storage.upsertProfileMode(
        profileId: p.id,
        mode: 'perimenopause',
        birthControlMethod: 'iud_hormonal',
      );
      await storage.upsertCycleOverride(
        profileId: p.id,
        cycleStartDate: '2026-01-01',
        excludedFromAverage: true,
        manualStart: true,
        noteId: 'note-1',
      );
      await storage.upsertCareNote(profileId: p.id, body: 'call the doctor');
      await storage.addVisitPrepItem(profileId: p.id, body: 'ask about X');
      // Issue #801: a dated, author-scoped guardian note is health content
      // about the shared profile and must leave the removed guardian's
      // device with everything else.
      await storage.upsertGuardianNote(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        body: 'wiped with the profile',
      );
      // Issue #130: a merge-disclosure row (discarded note text — health
      // content about the shared profile) must be wiped with everything
      // else.
      // Issue #257: a custom-tag registry row (the user's own health
      // vocabulary about the shared profile) must leave the device with
      // everything else — tombstoned payload-cleared, code surviving.
      await storage.upsertProfileTagRegistryEntry(
        profileId: p.id,
        code: 'shared_custom_tag',
        displayName: 'Shared custom tag',
      );
      await db.into(db.dayEntryMergeEvents).insert(
            DayEntryMergeEventsCompanion.insert(
              id: '01JWIPE00000000000000000A',
              profileId: p.id,
              localDate: '2026-01-15',
              winningRowId: entry.id,
              losingRowId: '01JWIPE00000000000000000B',
              field: 'note',
              losingValueText: 'wiped with the profile',
              createdAt: t0,
              updatedAt: t0,
            ),
          );
      // Issue #170: a change-history row (content-free, but still the
      // family's feed) must leave the device with everything else.
      await db.into(db.dayEntryHistory).insert(
            DayEntryHistoryCompanion.insert(
              id: '01JWIPE00000000000000000C',
              entryId: entry.id,
              profileId: p.id,
              changedByUserId: 'user-b',
              changedAt: t0,
              changeKind: 'logged',
              changedFields: const ['local_date', 'note'],
            ),
          );

      // Sanity: every table actually holds live content before revocation.
      expect((await storage.getDayEntries(profileId: p.id)), isNotEmpty);
      expect((await storage.getObservationsForProfile(p.id)), isNotEmpty);
      expect((await storage.getProfileMode(p.id))?.mode, 'perimenopause');
      expect((await storage.getCycleOverridesForProfile(p.id)), isNotEmpty);
      expect((await storage.getCareNotesForProfile(p.id)), isNotEmpty);
      expect((await storage.getVisitPrepItemsForProfile(p.id)), isNotEmpty);
      expect((await storage.getGuardianNotesForProfile(p.id)), isNotEmpty);

      final revokedAt = t0.add(const Duration(hours: 1));
      await storage.applyRemoteRows([
        remoteGuardian(
          'g-1',
          profileId: p.id,
          userId: uid,
          status: 'revoked',
          updatedAt: revokedAt,
        ),
      ]);

      expect(
        await storage.getProfile(p.id),
        isNull,
        reason: 'the profile itself must be tombstoned',
      );
      expect(await storage.getDayEntries(profileId: p.id), isEmpty);
      expect(
        await storage.getObservationsForProfile(p.id),
        isEmpty,
        reason: 'issue #532: observations were missing from the wipe',
      );
      expect(
        await storage.getCycleOverridesForProfile(p.id),
        isEmpty,
        reason: 'issue #532: cycle_overrides were missing from the wipe',
      );
      expect(await storage.getCareNotesForProfile(p.id), isEmpty);
      expect(await storage.getVisitPrepItemsForProfile(p.id), isEmpty);
      // Issue #801: guardian_notes are tombstoned payload-cleared — no live
      // note and no body text left on the removed guardian's device.
      expect(await storage.getGuardianNotesForProfile(p.id), isEmpty);
      expect(
        (await db.select(db.guardianNotes).get())
            .every((row) => row.deletedAt != null && row.body == ''),
        isTrue,
      );
      // Issue #130: the profile's merge-disclosure rows are hard-deleted
      // (no tombstone on this table) — a removed guardian's device keeps
      // no trace of the family's discarded note texts.
      expect(
        await (db.select(db.dayEntryMergeEvents)
              ..where((t) => t.profileId.equals(p.id)))
            .get(),
        isEmpty,
      );
      // Issue #170: the profile's change-history rows are hard-deleted too
      // (no tombstone; machine-written feed metadata), mirroring the
      // server's own tombstone_profile_content step.
      expect(
        await (db.select(db.dayEntryHistory)
              ..where((t) => t.profileId.equals(p.id)))
            .get(),
        isEmpty,
      );
      // Issue #257: the registry row is tombstoned payload-cleared — no
      // live row (the repository read excludes tombstones) and no label
      // left on the removed guardian's device.
      expect(
        await storage.getProfileTagRegistry(p.id),
        isEmpty,
      );
      expect(
        (await db.select(db.profileTagRegistry).get())
            .every((row) =>
                row.deletedAt != null &&
                row.displayName == '' &&
                row.code == 'shared_custom_tag'),
        isTrue,
      );

      // profile_modes has no tombstone (Issue #188): an absent-row-equivalent
      // reset is the wipe for this table (issue #532).
      final mode = await storage.getProfileMode(p.id);
      expect(mode, isNotNull);
      expect(mode!.mode, 'tracking');
      expect(mode.birthControlMethod, isNull);
      expect(mode.dirty, isFalse);

      // Nothing wiped here is left dirty — the wipe must never be pushed
      // back to the server that already knows about the revocation.
      expect(await storage.dirtyCount(), 0);
    });
  });

  group('membership and checklist convergence (issue #635)', () {
    test(
        'LLA-035: a revoked membership with a higher server_version wins '
        'even though its updated_at trails a forged future timestamp',
        () async {
      const uid = 'user-a';
      await storage.writeSyncState(
        kDefaultSyncState.copyWith(boundUserId: const Value(uid)),
      );
      final p = await storage.upsertProfile(
        displayName: 'Shared',
        isMinor: false,
      );

      // The membership lands normally first (server_version 1).
      await storage.applyRemoteRows([
        remoteGuardian(
          'g-1',
          profileId: p.id,
          userId: uid,
          role: 'co_parent',
          status: 'accepted',
          updatedAt: t0,
          serverVersion: 1,
        ),
      ]);

      // The accepted co-parent PATCHes their own row's `updated_at` far
      // into the future directly (allowed by the server's column grant —
      // see conflict_rules.dart) — a real write, so server_version still
      // advances forward with it.
      final forgedFuture = DateTime.utc(2100, 1, 1);
      await storage.applyRemoteRows([
        remoteGuardian(
          'g-1',
          profileId: p.id,
          userId: uid,
          role: 'co_parent',
          status: 'accepted',
          updatedAt: forgedFuture,
          serverVersion: 5,
        ),
      ]);
      expect(
        (await storage.getGuardiansForProfile(p.id))
            .firstWhere((g) => g.id == 'g-1')
            .updatedAt,
        forgedFuture,
      );

      // The primary revokes at real server time — its `updated_at` is far
      // behind the forged future stamp, but its `server_version` is higher.
      final revokedAt = t0.add(const Duration(hours: 1));
      await storage.applyRemoteRows([
        remoteGuardian(
          'g-1',
          profileId: p.id,
          userId: uid,
          role: 'co_parent',
          status: 'revoked',
          updatedAt: revokedAt,
          serverVersion: 6,
        ),
      ]);

      final guardian = (await storage.getGuardiansForProfile(p.id))
          .firstWhere((g) => g.id == 'g-1');
      expect(guardian.status, 'revoked',
          reason: 'a per-id-by-time rule would have kept "accepted" here '
              'forever — server_version must decide instead');
      expect(guardian.serverVersion, 6);
      expect(await storage.getProfile(p.id), isNull,
          reason: 'R5: the revocation must still tombstone the shared '
              'profile once it actually applies');
    });

    test(
        'LLA-041: a re-share restores a profile a revocation wiped while '
        'it was dirty with an unpushed, clock-ahead edit', () async {
      const uid = 'user-a';
      await storage.writeSyncState(
        kDefaultSyncState.copyWith(boundUserId: const Value(uid)),
      );
      final p = await storage.upsertProfile(
        displayName: 'Shared',
        isMinor: false,
      );
      // A prior sync already landed the server's own copy at t0.
      await storage.applyRemoteProfile(
          remoteProfile(p.id, displayName: 'Shared', updatedAt: t0));

      // A local edit runs while this device's clock is well ahead of the
      // server — and is never pushed (the revocation below reaches this
      // device first).
      final clockAheadEdit = t0.add(const Duration(days: 30));
      final edited = await storage.upsertProfile(
        id: p.id,
        displayName: 'Shared (edited locally)',
        isMinor: false,
        updatedAt: clockAheadEdit,
      );
      expect(edited.dirty, isTrue);
      expect(edited.updatedAt, clockAheadEdit);

      // Revocation arrives with a real "now" timestamp, far behind the
      // dirty edit's clock-ahead stamp.
      final revokedAt = t0.add(const Duration(hours: 1));
      await storage.applyRemoteRows([
        remoteGuardian(
          'g-1',
          profileId: p.id,
          userId: uid,
          status: 'revoked',
          updatedAt: revokedAt,
        ),
      ]);
      expect(await storage.getProfile(p.id), isNull,
          reason: 'wiped by the revocation');

      // Re-share: the primary re-invites and a pull delivers the profile's
      // real server row again, still carrying its original t0 timestamp
      // (neither revoke_guardian nor accept_guardian_invitation bumps
      // profiles.updated_at) — far behind the wiped row's stale, unpushed
      // clockAheadEdit stamp.
      final restored = await storage.applyRemoteProfile(
          remoteProfile(p.id, displayName: 'Shared', updatedAt: t0));
      expect(restored, isTrue,
          reason: 'LLA-041: a stale, unpushed local updated_at must never '
              'keep a revocation wipe from being un-tombstoned by a real '
              're-share');

      final profile = await storage.getProfile(p.id);
      expect(profile, isNotNull);
      expect(profile!.displayName, 'Shared');
      expect(profile.dirty, isFalse);

      // The eviction marker is cleared, so ordinary per-id LWW resumes:
      // an older remote row no longer beats this restored one for free.
      final stale = await storage.applyRemoteProfile(remoteProfile(p.id,
          displayName: 'Stale', updatedAt: t0.subtract(const Duration(days: 1))));
      expect(stale, isFalse);
      expect((await storage.getProfile(p.id))!.displayName, 'Shared');
    });
  });

  group('deleted_profiles reader (issue #522)', () {
    test('applying a deleted_profiles row tombstones the profile and '
        'cascades exactly like a guardian revocation', () async {
      final p = await storage.upsertProfile(
        displayName: 'Purged',
        isMinor: false,
      );
      final entry = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );
      await storage.upsertObservation(
        dayEntryId: entry.id,
        profileId: p.id,
        localDate: entry.localDate,
        tz: 'UTC',
        category: 'pain',
      );
      await storage.upsertCareNote(profileId: p.id, body: 'note');

      final purgedAt = t0.add(const Duration(hours: 1));
      await storage.applyRemoteRows([
        RemoteDeletedProfileRow(profileId: p.id, deletedAt: purgedAt),
      ]);

      expect(await storage.getProfile(p.id), isNull);
      expect(await storage.getDayEntries(profileId: p.id), isEmpty);
      expect(await storage.getObservationsForProfile(p.id), isEmpty);
      expect(await storage.getCareNotesForProfile(p.id), isEmpty);
      expect(
        await storage.dirtyCount(),
        0,
        reason: 'the wipe must never be pushed back',
      );
    });

    test('a profile never held locally is a harmless no-op', () async {
      await storage.applyRemoteRows([
        RemoteDeletedProfileRow(profileId: 'never-held', deletedAt: t0),
      ]);
      expect(await storage.getProfile('never-held'), isNull);
    });

    test(
      'issue #597: applying it through applyRemotePage persists its own '
      'cursor, independent of every other table\'s',
      () async {
        final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
        await storage.applyRemotePage(
          table: SyncTable.deletedProfiles,
          rows: [RemoteDeletedProfileRow(profileId: p.id, deletedAt: t0)],
          newCursor: 999,
        );
        final state = await storage.readSyncState();
        expect(state.cursorDeletedProfiles, 999,
            reason: 'issue #597: deletedProfiles now persists a real pull '
                'cursor, the same fix #525 already applied to '
                'profileGuardians');
        expect(
          state.cursorProfiles,
          0,
          reason: 'deletedProfiles\' cursor must not bleed into another '
              'table\'s',
        );
        expect(await storage.getProfile(p.id), isNull);
      },
    );
  });

  group('applyLocalProfilePurge (issue #472)', () {
    test('tombstones the profile and cascades exactly like a deleted_profiles '
        'pull or a guardian revocation — the same wipe, applied immediately '
        'rather than waiting for the next sync cycle', () async {
      final p = await storage.upsertProfile(
        displayName: 'Purged Locally',
        isMinor: false,
      );
      final entry = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );
      await storage.upsertObservation(
        dayEntryId: entry.id,
        profileId: p.id,
        localDate: entry.localDate,
        tz: 'UTC',
        category: 'pain',
      );
      await storage.upsertCareNote(profileId: p.id, body: 'note');

      await storage.applyLocalProfilePurge(p.id);

      expect(await storage.getProfile(p.id), isNull);
      expect(await storage.getDayEntries(profileId: p.id), isEmpty);
      expect(await storage.getObservationsForProfile(p.id), isEmpty);
      expect(await storage.getCareNotesForProfile(p.id), isEmpty);
      expect(
        await storage.dirtyCount(),
        0,
        reason: 'the wipe must never be pushed back — the server already '
            'knows (this call only ever follows a server RPC that has '
            'already succeeded)',
      );
    });

    test('a profile never held locally is a harmless no-op', () async {
      await storage.applyLocalProfilePurge('never-held');
      expect(await storage.getProfile('never-held'), isNull);
    });

    test('is idempotent — a second call after the row is already gone '
        'touches nothing further', () async {
      final p = await storage.upsertProfile(
        displayName: 'Purged Twice',
        isMinor: false,
      );
      await storage.applyLocalProfilePurge(p.id);
      await storage.applyLocalProfilePurge(p.id);
      expect(await storage.getProfile(p.id), isNull);
      expect(await storage.dirtyCount(), 0);
    });
  });

  group('applyLocalImportedDataPurge (issue #883)', () {
    test('tombstones ONLY the selected profile and source — every other '
        'profile and every other source survives', () async {
      final p1 = await storage.upsertProfile(displayName: 'One', isMinor: false);
      final p2 = await storage.upsertProfile(displayName: 'Two', isMinor: false);

      // p1: a clue_import entry + observation, and a manual entry + obs.
      final p1Clue = await storage.upsertDayEntry(
        profileId: p1.id,
        localDate: '2026-01-01',
        tz: 'UTC',
        flow: FlowLevel.medium,
        source: 'clue_import',
        sourceId: 'clue-1',
      );
      final p1ClueObs = await storage.upsertObservation(
        dayEntryId: p1Clue.id,
        profileId: p1.id,
        localDate: p1Clue.localDate,
        tz: 'UTC',
        category: 'pain',
        source: 'clue_import',
      );
      final p1Manual = await storage.upsertDayEntry(
        profileId: p1.id,
        localDate: '2026-01-02',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      await storage.upsertObservation(
        dayEntryId: p1Manual.id,
        profileId: p1.id,
        localDate: p1Manual.localDate,
        tz: 'UTC',
        category: 'mood',
      );

      // p2: the SAME source on a different profile must survive untouched.
      final p2Clue = await storage.upsertDayEntry(
        profileId: p2.id,
        localDate: '2026-01-01',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        source: 'clue_import',
      );
      await storage.upsertObservation(
        dayEntryId: p2Clue.id,
        profileId: p2.id,
        localDate: p2Clue.localDate,
        tz: 'UTC',
        category: 'pain',
        source: 'clue_import',
      );

      await storage.applyLocalImportedDataPurge(
        profileId: p1.id,
        source: 'clue_import',
      );

      // p1: the clue rows are tombstoned (payload cleared, not removed),
      // the manual rows are untouched.
      final p1Live = await storage.getDayEntries(profileId: p1.id);
      expect(p1Live.map((e) => e.id), contains(p1Manual.id));
      expect(p1Live.map((e) => e.id), isNot(contains(p1Clue.id)));
      final p1Full = await storage.getDayEntries(
        profileId: p1.id,
        includeTombstones: true,
      );
      final purged = p1Full.singleWhere((e) => e.id == p1Clue.id);
      expect(purged.deletedAt, isNotNull);
      expect(purged.flow, FlowLevel.none,
          reason: 'the tombstone clears the payload, never removes the row');

      final p1LiveObs = await storage.getObservationsForProfile(p1.id);
      expect(p1LiveObs.any((o) => o.source == 'clue_import'), isFalse);
      expect(p1LiveObs.any((o) => o.source == 'manual'), isTrue);

      // p2: everything survives, including the same source on p1's twin.
      final p2Live = await storage.getDayEntries(profileId: p2.id);
      expect(p2Live.single.id, p2Clue.id);
      expect((await storage.getObservationsForProfile(p2.id)).length, 1);
      expect(await storage.getProfile(p2.id), isNotNull);
      expect(await storage.getProfile(p1.id), isNotNull,
          reason: 'a scoped purge must never touch the profile row');

      // The purged rows are NOT dirty: the local tombstone must never be
      // pushed back as a resurrection (the applyLocalProfilePurge posture).
      expect(purged.dirty, isFalse);
      final purgedObs = await storage.getObservationById(p1ClueObs.id);
      expect(purgedObs?.deletedAt, isNotNull);
      expect(purgedObs?.dirty, isFalse);
    });

    test('is idempotent and a harmless no-op for an unknown source',
        () async {
      final p = await storage.upsertProfile(displayName: 'One', isMinor: false);
      await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-01',
        tz: 'UTC',
        flow: FlowLevel.medium,
        source: 'file_import',
      );

      await storage.applyLocalImportedDataPurge(
          profileId: p.id, source: 'file_import');
      await storage.applyLocalImportedDataPurge(
          profileId: p.id, source: 'file_import');
      expect(await storage.getDayEntries(profileId: p.id), isEmpty);

      await storage.applyLocalImportedDataPurge(
          profileId: p.id, source: 'clue_import');
      expect(await storage.getDayEntries(profileId: p.id), isEmpty);
    });

    test(
      'deliberately leaves updated_at untouched and dirty: false, so a '
      'tied remote row wins if RPC was not run first (issue #905 doc)',
      () async {
        final p = await storage.upsertProfile(displayName: 'P', isMinor: false);
        final entry = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-01',
          tz: 'UTC',
          flow: FlowLevel.medium,
          source: 'clue_import',
        );
        // Purge locally.
        await storage.applyLocalImportedDataPurge(
          profileId: p.id,
          source: 'clue_import',
        );
        expect(await storage.getDayEntries(profileId: p.id), isEmpty);

        // If a remote row with the same updated_at arrives (simulating a
        // reconcile where the server never deleted the row), remote wins the
        // tie. This pins why SupabaseProfileErasureService MUST run the server
        // RPC first before calling applyLocalImportedDataPurge (#905).
        final tiedRemote = remoteEntry(
          entry.id,
          profileId: p.id,
          localDate: entry.localDate,
          updatedAt: entry.updatedAt,
          flow: FlowLevel.medium,
        );
        await storage.applyRemoteDayEntry(tiedRemote);
        final revived = await storage.getDayEntries(profileId: p.id);
        expect(revived, isNotEmpty,
            reason: 'equal timestamp remote wins tie against local non-dirty tombstone');
      },
    );
  });

  group('liveImportedSourceCounts (issue #883)', () {
    test('sums live day entries and observations per raw source, ignoring '
        'tombstones and other profiles', () async {
      final p = await storage.upsertProfile(displayName: 'One', isMinor: false);
      final other =
          await storage.upsertProfile(displayName: 'Two', isMinor: false);

      final clue = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-01',
        tz: 'UTC',
        flow: FlowLevel.medium,
        source: 'clue_import',
      );
      await storage.upsertObservation(
        dayEntryId: clue.id,
        profileId: p.id,
        localDate: clue.localDate,
        tz: 'UTC',
        category: 'pain',
        source: 'clue_import',
      );
      await storage.upsertObservation(
        dayEntryId: clue.id,
        profileId: p.id,
        localDate: clue.localDate,
        tz: 'UTC',
        category: 'energy',
        source: 'apple_health',
      );
      await storage.upsertDayEntry(
        profileId: other.id,
        localDate: '2026-01-01',
        tz: 'UTC',
        flow: FlowLevel.heavy,
        source: 'clue_import',
      );

      final counts = await storage.liveImportedSourceCounts(p.id);
      expect(counts['clue_import'], 2,
          reason: 'one day entry + one observation');
      expect(counts['apple_health'], 1);
      expect(counts.containsKey('file_import'), isFalse);

      // Tombstoning the clue observation drops it from the count.
      await storage.applyLocalImportedDataPurge(
          profileId: p.id, source: 'clue_import');
      final after = await storage.liveImportedSourceCounts(p.id);
      expect(after.containsKey('clue_import'), isFalse);
      expect(after['apple_health'], 1,
          reason: 'the other source is untouched by the scoped purge');
    });
  });

  group('bumpLocalRevForRetry (issue #568)', () {
    test('bumps local_rev and re-marks dirty on every pushable table, '
        'content untouched, and is a harmless no-op on the two pull-only '
        'tables', () async {
      final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
      await storage.markPushed(
        table: SyncTable.profiles,
        id: p.id,
        localRevAtPush: p.localRev,
      );
      await storage.bumpLocalRevForRetry(table: SyncTable.profiles, id: p.id);
      final profile = await storage.getProfile(p.id);
      expect(profile!.localRev, p.localRev + 1);
      expect(profile.dirty, isTrue);
      expect(profile.displayName, 'A', reason: 'content is untouched');

      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.light,
      );
      await storage.markPushed(
        table: SyncTable.dayEntries,
        id: e.id,
        localRevAtPush: e.localRev,
      );
      await storage.bumpLocalRevForRetry(table: SyncTable.dayEntries, id: e.id);
      final entry = await entryById(p.id, e.id);
      expect(entry.localRev, e.localRev + 1);
      expect(entry.dirty, isTrue);
      expect(entry.flow, FlowLevel.light);

      final o = await storage.upsertObservation(
        dayEntryId: e.id,
        profileId: p.id,
        localDate: e.localDate,
        tz: 'UTC',
        category: 'pain',
      );
      await storage.markPushed(
        table: SyncTable.observations,
        id: o.id,
        localRevAtPush: o.localRev,
      );
      await storage.bumpLocalRevForRetry(
        table: SyncTable.observations,
        id: o.id,
      );
      final observation = (await storage.getObservationsForDayEntry(e.id))
          .single;
      expect(observation.localRev, o.localRev + 1);
      expect(observation.dirty, isTrue);
      expect(observation.category, 'pain');

      await storage.upsertProfileMode(profileId: p.id, mode: 'tracking');
      final mode0 = (await storage.getProfileMode(p.id))!;
      await storage.markPushed(
        table: SyncTable.profileModes,
        id: p.id,
        localRevAtPush: mode0.localRev,
      );
      await storage.bumpLocalRevForRetry(
        table: SyncTable.profileModes,
        id: p.id,
      );
      final mode = (await storage.getProfileMode(p.id))!;
      expect(mode.localRev, mode0.localRev + 1);
      expect(mode.dirty, isTrue);
      expect(mode.mode, 'tracking');

      final co = await storage.upsertCycleOverride(
        profileId: p.id,
        cycleStartDate: '2026-01-01',
      );
      await storage.markPushed(
        table: SyncTable.cycleOverrides,
        id: co.id,
        localRevAtPush: co.localRev,
      );
      await storage.bumpLocalRevForRetry(
        table: SyncTable.cycleOverrides,
        id: co.id,
      );
      final override = (await storage.getCycleOverridesForProfile(p.id)).single;
      expect(override.localRev, co.localRev + 1);
      expect(override.dirty, isTrue);
      expect(override.cycleStartDate, '2026-01-01');

      final cn = await storage.upsertCareNote(profileId: p.id, body: 'note');
      await storage.markPushed(
        table: SyncTable.careNotes,
        id: cn.id,
        localRevAtPush: cn.localRev,
      );
      await storage.bumpLocalRevForRetry(table: SyncTable.careNotes, id: cn.id);
      final note = (await storage.getCareNotesForProfile(p.id)).single;
      expect(note.localRev, cn.localRev + 1);
      expect(note.dirty, isTrue);
      expect(note.body, 'note');

      final vp = await storage.addVisitPrepItem(profileId: p.id, body: 'ask');
      await storage.markPushed(
        table: SyncTable.visitPrepItems,
        id: vp.id,
        localRevAtPush: vp.localRev,
      );
      await storage.bumpLocalRevForRetry(
        table: SyncTable.visitPrepItems,
        id: vp.id,
      );
      final item = (await storage.getVisitPrepItemsForProfile(p.id)).single;
      expect(item.localRev, vp.localRev + 1);
      expect(item.dirty, isTrue);
      expect(item.body, 'ask');

      // Pull-only tables: nothing to bump, must not throw.
      await storage.bumpLocalRevForRetry(
        table: SyncTable.profileGuardians,
        id: 'irrelevant',
      );
      await storage.bumpLocalRevForRetry(
        table: SyncTable.deletedProfiles,
        id: 'irrelevant',
      );
    });

    test(
      'markPushed on the two pull-only tables is a harmless no-op',
      () async {
        expect(
          await storage.markPushed(
            table: SyncTable.profileGuardians,
            id: 'irrelevant',
            localRevAtPush: 0,
          ),
          isFalse,
        );
        expect(
          await storage.markPushed(
            table: SyncTable.deletedProfiles,
            id: 'irrelevant',
            localRevAtPush: 0,
          ),
          isFalse,
        );
      },
    );
  });

  group('rebaseFutureStampedRows (issue #641 LLA-042)', () {
    test('rebases a dirty future-stamped row to the server clock and bumps rev',
        () async {
      final profile =
          await storage.upsertProfile(displayName: 'Alice', isMinor: false);
      // Move the local clock far into the future, then log an entry: its
      // updated_at is stamped in the future and the server would reject it.
      clock.now = t0.add(const Duration(days: 365));
      final entry = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-01-16',
          tz: 'UTC',
          flow: FlowLevel.light);
      expect(entry.dirty, isTrue);
      expect(entry.updatedAt.isAfter(t0.add(const Duration(days: 364))), isTrue,
          reason: 'precondition: the entry is future-stamped');

      // The client has just learned the real server clock (≈ t0) from a push
      // that rejected this row.
      final rebased = await storage.rebaseFutureStampedRows(serverNow: t0);
      expect(rebased, 1, reason: 'exactly the future-stamped entry is rebased');

      final after = await entryById(profile.id, entry.id);
      expect(after.updatedAt, t0,
          reason: 'updated_at is rebased onto the learned server clock');
      expect(after.localRev, greaterThan(entry.localRev),
          reason: 'local_rev bumps so the row is pushable (and its rejection clears)');
    });

    test('leaves non-future dirty rows untouched and returns a count of zero',
        () async {
      final profile =
          await storage.upsertProfile(displayName: 'Bob', isMinor: false);
      final normal = await storage.upsertDayEntry(
          profileId: profile.id,
          localDate: '2026-01-16',
          tz: 'UTC',
          flow: FlowLevel.medium);
      expect(await storage.rebaseFutureStampedRows(serverNow: t0), 0,
          reason: 'nothing future-stamped is rebased');
      final after = await entryById(profile.id, normal.id);
      expect(after.updatedAt, normal.updatedAt,
          reason: 'a healthy dirty row keeps its timestamp');
      expect(after.localRev, normal.localRev,
          reason: 'a healthy dirty row keeps its rev');
    });
  });
}
