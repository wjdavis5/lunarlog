/// Issue #42 storage-side pinning tests: the batched push-marking
/// (`markPushedBatch` behind `applyPushResult`), the page-wide batched
/// lookups behind `applyRemotePage` / `applyRemoteRows` (the `_PageLookup`
/// prefetch and its write-through), and the statement-count bounds that
/// make the batching itself — not just its outcome — the pinned contract.
library;

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
import 'package:lunarlog/data/sync/remote_rows.dart';

/// Counts statements by verb, so a test can pin *how many* statements a
/// batched path issues (one per chunk / per prefetch lookup) instead of
/// only pinning its final state. `INSERT ... RETURNING` / `UPDATE ...
/// RETURNING` reach the executor through [runSelect] (that is how drift
/// implements `writeReturning`), so read-selects are counted as statements
/// *starting with* `SELECT` and the RETURNING writes fall through to the
/// insert/update tallies by their own verb.
class _CountingInterceptor extends QueryInterceptor {
  int reads = 0;
  int updates = 0;
  int inserts = 0;

  /// `insertReturning`/`writeReturning` statements (SQL `INSERT ...`
  /// / `UPDATE ... RETURNING`), which reach the executor through
  /// [runSelect] — the issue #42 write-through's zero-extra-statement
  /// channel.
  int returningInserts = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (statement.startsWith('SELECT')) {
      reads++;
    } else if (statement.startsWith('INSERT')) {
      returningInserts++;
    }
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    updates++;
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    inserts++;
    return executor.runInsert(statement, args);
  }
}

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final t0 = DateTime.utc(2026, 1, 15, 8);

  /// A fresh intercepted database + storage pair.
  (LunarLogStorage, _CountingInterceptor, Future<void> Function()) makeRig() {
    final interceptor = _CountingInterceptor();
    final db = LunarLogDatabase(
      NativeDatabase.memory().interceptWith(interceptor),
    );
    final clock = FixedClock(t0);
    final storage = LunarLogStorage(db, clock: clock.call);
    return (storage, interceptor, db.close);
  }

  RemoteProfileRow remoteProfile(
    String id, {
    String displayName = 'Remote',
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) => RemoteProfileRow(
    id: id,
    displayName: displayName,
    isMinor: false,
    sortOrder: 0,
    archivedAt: null,
    createdAt: updatedAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  RemoteDayEntryRow remoteEntry(
    String id, {
    required String profileId,
    String localDate = '2026-01-15',
    FlowLevel flow = FlowLevel.medium,
    List<String> tags = const ['remote'],
    String? note = 'from remote',
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) => RemoteDayEntryRow(
    id: id,
    profileId: profileId,
    localDate: localDate,
    tz: 'UTC',
    flow: flow,
    tags: tags,
    note: note,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );

  String isoDate(int i) => DateTime.utc(
    2025,
    1,
    1,
  ).add(Duration(days: i)).toIso8601String().substring(0, 10);

  group('markPushedBatch (issue #42 finding 1)', () {
    test('clears dirty on every matching row across tables and returns the '
        'cleared count', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );

      final cleared = await storage.markPushedBatch([
        (table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev),
        (table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev),
      ]);

      expect(cleared, 2);
      expect(
        (await storage.getProfiles(includeTombstones: true)).single.dirty,
        isFalse,
      );
      expect(
        (await storage.getDayEntries(
          profileId: p.id,
          includeTombstones: true,
        )).single.dirty,
        isFalse,
      );
    });

    test(
      'AE11 guard preserved: a row whose local_rev changed since the push '
      'was assembled stays dirty while the rest of the batch clears',
      () async {
        final (storage, _, close) = makeRig();
        addTearDown(close);
        final a = await storage.upsertProfile(displayName: 'A', isMinor: false);
        final b = await storage.upsertProfile(displayName: 'B', isMinor: false);
        expect(a.localRev, 1);
        expect(b.localRev, 1);

        // A local edit lands on A while the "push was in flight": its
        // local_rev moves past the value the batch was assembled from.
        final edited = await storage.upsertProfile(
          id: a.id,
          displayName: 'A2',
          isMinor: false,
          updatedAt: t0.add(const Duration(hours: 1)),
        );
        expect(edited.localRev, 2);

        final cleared = await storage.markPushedBatch([
          (table: SyncTable.profiles, id: a.id, localRevAtPush: a.localRev),
          (table: SyncTable.profiles, id: b.id, localRevAtPush: b.localRev),
        ]);

        expect(cleared, 1, reason: 'only B matched its push-time local_rev');
        final byId = {
          for (final row in await storage.getProfiles(includeTombstones: true))
            row.id: row,
        };
        expect(
          byId[a.id]!.dirty,
          isTrue,
          reason: 'AE11: the concurrently-changed row is not marked pushed',
        );
        expect(byId[a.id]!.localRev, 2);
        expect(byId[b.id]!.dirty, isFalse);
      },
    );

    test('chunks past kSyncBatchChunkSize: 401 rows clear through two '
        'batched UPDATE statements, not 401 per-row ones', () async {
      final (storage, interceptor, close) = makeRig();
      addTearDown(close);
      const count = kSyncBatchChunkSize + 1;
      final rows = <Profile>[
        for (var i = 0; i < count; i++)
          await storage.upsertProfile(displayName: 'P$i', isMinor: false),
      ];

      interceptor.updates = 0;
      final cleared = await storage.markPushedBatch([
        for (final row in rows)
          (table: SyncTable.profiles, id: row.id, localRevAtPush: row.localRev),
      ]);

      expect(cleared, count);
      expect(
        interceptor.updates,
        2,
        reason: 'one batched UPDATE per kSyncBatchChunkSize chunk',
      );
      expect(
        (await storage.getProfiles(includeTombstones: true))
            .every((row) => !row.dirty),
        isTrue,
      );
    });

    test('covers every pushed table\'s key shape (id, and profile_id for '
        'profile modes) and no-ops the two pull-only tables', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
      final e = await storage.upsertDayEntry(
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        flow: FlowLevel.medium,
      );
      final o = await storage.upsertObservation(
        dayEntryId: e.id,
        profileId: p.id,
        localDate: '2026-01-15',
        tz: 'UTC',
        category: 'symptom',
      );
      final m = await storage.upsertProfileMode(
        profileId: p.id,
        mode: 'tracking',
      );
      final c = await storage.upsertCycleOverride(
        profileId: p.id,
        cycleStartDate: '2026-01-05',
      );
      final n = await storage.upsertCareNote(profileId: p.id, body: 'note');
      final i = await storage.addVisitPrepItem(profileId: p.id, body: 'item');
      // Issue #130's eighth pushed table: a locally-emitted disclosure
      // row (dirty, like every local write) rides the same batched clear.
      final ev =
          await storage.db.into(storage.db.dayEntryMergeEvents).insertReturning(
                DayEntryMergeEventsCompanion.insert(
                  id: '01JMERGEEVENT000000000000A',
                  profileId: p.id,
                  localDate: '2026-01-15',
                  winningRowId: '01JWINNER00000000000000000A',
                  losingRowId: '01JLOSER000000000000000000A',
                  field: 'note',
                  losingValueText: 'discarded',
                  createdAt: t0,
                  updatedAt: t0,
                  dirty: const Value(true),
                  localRev: const Value(1),
                ),
              );
      expect(await storage.dirtyCount(), 8);

      final cleared = await storage.markPushedBatch([
        (table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev),
        (table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev),
        (table: SyncTable.observations, id: o.id, localRevAtPush: o.localRev),
        (
          table: SyncTable.profileModes,
          id: m.profileId,
          localRevAtPush: m.localRev,
        ),
        (table: SyncTable.cycleOverrides, id: c.id, localRevAtPush: c.localRev),
        (table: SyncTable.careNotes, id: n.id, localRevAtPush: n.localRev),
        (table: SyncTable.visitPrepItems, id: i.id, localRevAtPush: i.localRev),
        (
          table: SyncTable.dayEntryMergeEvents,
          id: ev.id,
          localRevAtPush: ev.localRev,
        ),
        // Pull-only tables: harmless no-ops, matching markPushed.
        (table: SyncTable.profileGuardians, id: 'g1', localRevAtPush: 1),
        (table: SyncTable.deletedProfiles, id: 'd1', localRevAtPush: 1),
      ]);

      expect(cleared, 8);
      expect(await storage.dirtyCount(), 0);
    });

    test(
      'applyPushResult marks a whole batch through one batched UPDATE per '
      'table, keeping the rollback pairing with applyResolved intact',
      () async {
        final (storage, interceptor, close) = makeRig();
        addTearDown(close);
        final p = await storage.upsertProfile(displayName: 'A', isMinor: false);
        final e = await storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.medium,
        );

        interceptor.updates = 0;
        await storage.applyPushResult(
          accepted: [
            (table: SyncTable.profiles, id: p.id, localRevAtPush: p.localRev),
            (table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev),
          ],
          resolved: const [],
        );

        expect(
          interceptor.updates,
          2,
          reason:
              'the per-row markPushed loop this replaced issued one '
              'UPDATE per accepted row',
        );
        expect(
          (await storage.getProfiles(includeTombstones: true)).single.dirty,
          isFalse,
        );
        expect(
          (await storage.getDayEntries(
            profileId: p.id,
            includeTombstones: true,
          )).single.dirty,
          isFalse,
        );
      },
    );
  });

  group('batched page lookups (issue #42 finding 2)', () {
    test('a 500-row day-entries page with a new/updated/tombstoned mix '
        'applies correctly and advances the cursor', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      await storage.applyRemotePage(
        table: SyncTable.profiles,
        rows: [remoteProfile(profileId, updatedAt: t0)],
        newCursor: 1,
      );
      // 350 seeded entries (v2..), all live, all unique dates.
      final seeded = <RemoteDayEntryRow>[
        for (var i = 0; i < 350; i++)
          remoteEntry(
            'e${i.toString().padLeft(4, '0')}',
            profileId: profileId,
            localDate: isoDate(i),
            note: 'seed',
            updatedAt: t0,
          ),
      ];
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: seeded,
        newCursor: 351,
      );

      // Page 2: 500 rows — 250 updates of seeded rows, 150 brand-new rows,
      // 100 tombstones of the remaining seeded rows.
      final later = t0.add(const Duration(hours: 2));
      final page = <RemoteDayEntryRow>[
        for (var i = 0; i < 250; i++)
          remoteEntry(
            'e${i.toString().padLeft(4, '0')}',
            profileId: profileId,
            localDate: isoDate(i),
            note: 'updated',
            updatedAt: later,
          ),
        for (var i = 0; i < 150; i++)
          remoteEntry(
            'n${i.toString().padLeft(4, '0')}',
            profileId: profileId,
            localDate: isoDate(1000 + i),
            note: 'new',
            updatedAt: later,
          ),
        for (var i = 250; i < 350; i++)
          remoteEntry(
            'e${i.toString().padLeft(4, '0')}',
            profileId: profileId,
            localDate: isoDate(i),
            updatedAt: later,
            deletedAt: later,
          ),
      ];
      expect(page, hasLength(500));
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: page,
        newCursor: 851,
      );

      final live = await storage.getDayEntries(profileId: profileId);
      final tombstones = (await storage.getDayEntries(
        profileId: profileId,
        includeTombstones: true,
      )).where((row) => row.deletedAt != null);
      expect(live, hasLength(400), reason: '250 updated + 150 new');
      expect(tombstones, hasLength(100));
      final byId = {
        for (final row in await storage.getDayEntries(
          profileId: profileId,
          includeTombstones: true,
        ))
          row.id: row,
      };
      expect(byId['e0000']!.note, 'updated');
      expect(byId['e0000']!.dirty, isFalse);
      expect(byId['n0000']!.note, 'new');
      expect(byId['e0250']!.deletedAt, isNotNull);
      expect(
        byId['e0250']!.flow,
        FlowLevel.none,
        reason: 'tombstones carry no payload',
      );
      expect((await storage.readSyncState()).cursorDayEntries, 851);
    });

    test('the 500-row page resolves through batched lookups: SELECT count '
        'stays bounded by the prefetch, not by the row count', () async {
      final (storage, interceptor, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      await storage.applyRemotePage(
        table: SyncTable.profiles,
        rows: [remoteProfile(profileId, updatedAt: t0)],
        newCursor: 1,
      );
      final later = t0.add(const Duration(hours: 2));
      final page = <RemoteDayEntryRow>[
        for (var i = 0; i < 500; i++)
          remoteEntry(
            'e${i.toString().padLeft(4, '0')}',
            profileId: profileId,
            localDate: isoDate(i),
            updatedAt: later,
          ),
      ];
      interceptor.reads = 0;
      interceptor.updates = 0;
      interceptor.inserts = 0;
      interceptor.returningInserts = 0;
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: page,
        newCursor: 501,
      );

      // Prefetch: day_entries by id (500 ids / 400 per chunk = 2 selects),
      // profiles by id (1), live peers by profile (1); plus the sync-state
      // read behind the cursor write — a handful in total, where the
      // per-row lookups this replaces ran three SELECTs per row (~1500).
      expect(
        interceptor.reads,
        lessThan(20),
        reason: 'batched IN (...) lookups per page, not per row',
      );
      expect(interceptor.reads, greaterThan(0));
      expect(
        interceptor.returningInserts,
        500,
        reason: 'every new row still lands, via one RETURNING write each',
      );
      expect(interceptor.updates, 1, reason: 'the cursor write');
      expect(await storage.getDayEntries(profileId: profileId), hasLength(500));
    });

    test('same-date convergence inside one page: the later live row wins and '
        'the earlier one is tombstoned (write-through peer cache)', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      const date = '2026-01-15';
      await storage.applyRemotePage(
        table: SyncTable.profiles,
        rows: [remoteProfile(profileId, updatedAt: t0)],
        newCursor: 1,
      );
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: [
          remoteEntry(
            'early',
            profileId: profileId,
            localDate: date,
            note: 'early',
            updatedAt: t0,
          ),
          remoteEntry(
            'late',
            profileId: profileId,
            localDate: date,
            note: 'late',
            updatedAt: t0.add(const Duration(hours: 1)),
          ),
        ],
        newCursor: 3,
      );

      final live = await storage.getDayEntries(profileId: profileId);
      expect(live, hasLength(1), reason: 'at most one live row per date');
      expect(live.single.id, 'late');
      final tombstoned = (await storage.getDayEntries(
        profileId: profileId,
        includeTombstones: true,
      )).firstWhere((row) => row.id == 'early');
      expect(tombstoned.deletedAt, isNotNull);
      expect(
        tombstoned.dirty,
        isTrue,
        reason: 'the resolution is pushed back to the server',
      );
    });

    test('same-date convergence in the other arrival order reaches the same '
        'outcome', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      const date = '2026-01-15';
      await storage.applyRemotePage(
        table: SyncTable.profiles,
        rows: [remoteProfile(profileId, updatedAt: t0)],
        newCursor: 1,
      );
      await storage.applyRemotePage(
        table: SyncTable.dayEntries,
        rows: [
          remoteEntry(
            'late',
            profileId: profileId,
            localDate: date,
            note: 'late',
            updatedAt: t0.add(const Duration(hours: 1)),
          ),
          remoteEntry(
            'early',
            profileId: profileId,
            localDate: date,
            note: 'early',
            updatedAt: t0,
          ),
        ],
        newCursor: 3,
      );

      final live = await storage.getDayEntries(profileId: profileId);
      expect(live, hasLength(1));
      expect(
        live.single.id,
        'late',
        reason: 'the newer row wins regardless of arrival order',
      );
    });

    test('a heterogeneous reconcile page holding a new profile, its day '
        'entry, and an observation of that entry applies cleanly in one '
        'transaction (known-absent prefetch never re-runs a SELECT)', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      const entryId = 'e1';
      final later = t0.add(const Duration(hours: 1));
      await storage.applyRemoteRows([
        remoteProfile(profileId, updatedAt: t0),
        remoteEntry(entryId, profileId: profileId, updatedAt: t0),
        RemoteObservationRow(
          id: 'o1',
          dayEntryId: entryId,
          profileId: profileId,
          localDate: '2026-01-15',
          tz: 'UTC',
          category: 'symptom',
          code: 'cramps',
          updatedAt: later,
          deletedAt: null,
        ),
      ]);

      expect((await storage.getProfiles()).single.id, profileId);
      expect(await storage.getDayEntries(profileId: profileId), hasLength(1));
      final observation = (await storage.getObservationsForDayEntry(entryId))
          .single;
      expect(observation.code, 'cramps');
    });

    test('a guardian revocation mid-page evicts the profile from the page '
        'cache: later rows in the same page read live state', () async {
      final (storage, _, close) = makeRig();
      addTearDown(close);
      const profileId = 'p1';
      const boundUser = 'user-a';
      await storage.writeSyncState(
        kDefaultSyncState.copyWith(
          boundUserId: Value<String?>(boundUser),
          deviceId: 'device-1',
        ),
      );
      await storage.applyRemoteRows([
        remoteProfile(profileId, updatedAt: t0),
        remoteEntry(
          'stays-wiped',
          profileId: profileId,
          localDate: '2026-01-01',
          note: 'old',
          updatedAt: t0,
        ),
        remoteEntry(
          'reapplied',
          profileId: profileId,
          localDate: '2026-01-02',
          note: 'new',
          updatedAt: t0.add(const Duration(hours: 3)),
        ),
      ]);
      expect(await storage.getDayEntries(profileId: profileId), hasLength(2));

      // One page: the bound user's membership is revoked (cascading the
      // wipe over every live row of the profile), then a fresh remote
      // delivery of 'reapplied' — newer than anything stored — must apply
      // over the wiped copy exactly as a live read would.
      await storage.applyRemoteRows([
        RemoteProfileGuardianRow(
          id: 'g1',
          profileId: profileId,
          userId: boundUser,
          role: 'caregiver',
          status: 'revoked',
          createdAt: t0,
          updatedAt: t0.add(const Duration(hours: 1)),
          serverVersion: 9,
        ),
        remoteEntry(
          'reapplied',
          profileId: profileId,
          localDate: '2026-01-02',
          note: 'new',
          updatedAt: t0.add(const Duration(hours: 3)),
        ),
      ]);

      final live = await storage.getDayEntries(profileId: profileId);
      expect(
        live.map((row) => row.id),
        ['reapplied'],
        reason:
            'the wiped row the page re-delivers comes back; the row '
            'the page does not re-deliver stays wiped',
      );
      final wiped = (await storage.getDayEntries(
        profileId: profileId,
        includeTombstones: true,
      )).firstWhere((row) => row.id == 'stays-wiped');
      expect(wiped.deletedAt, isNotNull);
    });

    test(
      'an empty page still writes the cursor and issues no lookup',
      () async {
        final (storage, interceptor, close) = makeRig();
        addTearDown(close);
        await storage.applyRemotePage(
          table: SyncTable.profiles,
          rows: const [],
          newCursor: 7,
        );
        expect((await storage.readSyncState()).cursorProfiles, 7);
        expect(
          interceptor.reads,
          lessThan(3),
          reason: 'no rows to prefetch, only the sync-state read remains',
        );
      },
    );
  });
}
