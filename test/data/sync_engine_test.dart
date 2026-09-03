/// U5 engine tests (KTD2, KTD4, KTD10, KTD11; AE4, AE5, AE6, AE9): push
/// batching and `markPushed` revisions, resolved/declined rows, the clock
/// offset, per-table cursors, full reconciliation cadence, gating, binding,
/// mismatch, errors, coalescing and disposal — all against
/// `FakeSyncTransport`, `FakeAuthService`, an in-memory drift database, a
/// fake gate `Listenable` and fake timers. Nothing here touches Supabase.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import '../support/fake_auth_service.dart';
import '../support/fake_sync_transport.dart';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

/// Stand-in for `GateController`: a `Listenable` plus an unlocked flag.
class FakeGateSignal extends ChangeNotifier {
  bool unlocked = true;

  void lock() {
    unlocked = false;
    notifyListeners();
  }

  void unlock() {
    unlocked = true;
    notifyListeners();
  }
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this._callback, {this.periodic = false});

  final Duration delay;
  final void Function() _callback;
  final bool periodic;
  bool active = true;

  @override
  bool get isActive => active;

  @override
  int get tick => 0;

  @override
  void cancel() => active = false;

  void fire() {
    if (!active) return;
    if (!periodic) active = false;
    _callback();
  }
}

class FakeTimers {
  final oneShots = <FakeTimer>[];
  final periodics = <FakeTimer>[];

  Timer oneShot(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback);
    oneShots.add(timer);
    return timer;
  }

  Timer periodic(Duration delay, void Function() callback) {
    final timer = FakeTimer(delay, callback, periodic: true);
    periodics.add(timer);
    return timer;
  }

  List<FakeTimer> get active =>
      [...oneShots, ...periodics].where((t) => t.active).toList();
}

final t0 = DateTime.utc(2026, 3, 1, 12);
const uidA = 'user-a';
const uidB = 'user-b';

String ulidN(int n) => '01J${n.toString().padLeft(23, '0')}';

RemoteProfileRow remoteProfile(
  String id, {
  String displayName = 'Remote',
  required DateTime updatedAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) =>
    RemoteProfileRow(
      id: id,
      displayName: displayName,
      isMinor: false,
      sortOrder: 0,
      archivedAt: null,
      createdAt: updatedAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      serverVersion: serverVersion,
    );

RemoteDayEntryRow remoteEntry(
  String id, {
  required String profileId,
  String localDate = '2026-01-15',
  FlowLevel flow = FlowLevel.medium,
  String? note = 'from remote',
  required DateTime updatedAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) =>
    RemoteDayEntryRow(
      id: id,
      profileId: profileId,
      localDate: localDate,
      tz: 'UTC',
      flow: flow,
      tags: const ['remote'],
      note: note,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      serverVersion: serverVersion,
    );

/// Storage whose `isEmpty` runs [beforeIsEmpty] first, so a test can change
/// the session in the middle of the engine's bind decision.
class HookedStorage extends LunarLogStorage {
  HookedStorage(super.db, {super.clock});

  Future<void> Function()? beforeIsEmpty;

  @override
  Future<bool> isEmpty() async {
    await beforeIsEmpty?.call();
    return super.isEmpty();
  }
}

class Rig {
  Rig({
    AuthSessionState authState = AuthSessionState.signedIn,
    String? uid = uidA,
    int batchSize = PushBatch.maxRows,
    int pageSize = 500,
    LunarLogStorage Function(LunarLogDatabase db, DateTime Function() clock)?
        storageFactory,
  }) {
    db = LunarLogDatabase(NativeDatabase.memory());
    clock = FixedClock(t0);
    storage = storageFactory?.call(db, clock.call) ??
        LunarLogStorage(db, clock: clock.call);
    transport = FakeSyncTransport(serverClock: () => clock.now);
    auth = FakeAuthService();
    if (uid != null) {
      auth.emit(authState, user: AuthUser(id: uid));
    } else {
      auth.emit(authState);
    }
    engine = SupabaseSyncEngine(
      storage: storage,
      transport: transport,
      auth: auth,
      gate: gate,
      gateUnlocked: () => gate.unlocked,
      clock: clock.call,
      timerFactory: timers.oneShot,
      periodicTimerFactory: timers.periodic,
      backoff: (failures) => Duration(seconds: failures),
      batchSize: batchSize,
      pageSize: pageSize,
      writeDebounce: Duration.zero,
    );
    engine.snapshots.listen(seen.add);
  }

  late final LunarLogDatabase db;
  late final FixedClock clock;
  late final LunarLogStorage storage;
  late final FakeSyncTransport transport;
  late final FakeAuthService auth;
  late final SupabaseSyncEngine engine;
  final FakeGateSignal gate = FakeGateSignal();
  final FakeTimers timers = FakeTimers();
  final seen = <SyncSnapshot>[];

  /// Binds the database to [uid] before the engine starts, with a recent
  /// full pull so no reconcile is due unless a test makes it due.
  Future<void> bind(String uid, {DateTime? lastFullPullAt}) =>
      storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: Value(uid),
        deviceId: 'device-1',
        lastFullPullAt: Value(lastFullPullAt ?? t0),
      ));

  Future<void> start() async {
    engine.start();
    await engine.flush();
  }

  Future<void> sync() async {
    engine.requestSync();
    await engine.flush();
  }

  Future<SyncStateRow> state() => storage.readSyncState();

  Future<Profile> profile(String id) async =>
      (await storage.getProfiles(includeTombstones: true))
          .firstWhere((p) => p.id == id);

  Future<DayEntry> entry(String profileId, String id) async =>
      (await storage.getDayEntries(
              profileId: profileId, includeTombstones: true))
          .firstWhere((e) => e.id == id);

  Future<void> dispose() async {
    await engine.dispose();
    await auth.dispose();
    await db.close();
  }
}

List<String> ids(Iterable<Map<String, Object?>> rows) =>
    [for (final r in rows) r['id']! as String];

int profilePulls(FakeSyncTransport t) =>
    t.pulls.where((c) => c.table == SyncTable.profiles).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('push', () {
    test('sends every dirty row including tombstones, profiles before day '
        'entries, in batches of at most the batch size, and markPushed uses '
        'the local_rev captured before the request (AE11)', () async {
      final rig = Rig(batchSize: 4);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final s = rig.storage;
      final p1 = await s.upsertProfile(displayName: 'A', isMinor: false);
      final p2 = await s.upsertProfile(displayName: 'B', isMinor: true);
      final p3 = await s.upsertProfile(displayName: 'C', isMinor: false);
      final entries = <DayEntry>[];
      for (var d = 1; d <= 6; d++) {
        entries.add(await s.upsertDayEntry(
            profileId: p1.id,
            localDate: '2026-01-0$d',
            tz: 'UTC',
            flow: FlowLevel.light));
      }
      await s.softDeleteDayEntry(profileId: p1.id, localDate: '2026-01-06');
      final tombstoneId = entries[5].id;
      final edited = entries[0];

      // A local edit lands while the first batch is in flight.
      rig.transport.onPush = (batch) async {
        if (rig.transport.pushes.length == 1) {
          await s.upsertDayEntry(
              profileId: p1.id,
              localDate: '2026-01-01',
              tz: 'UTC',
              flow: FlowLevel.heavy);
        }
      };

      await rig.start();

      final pushes = rig.transport.pushes;
      expect(pushes.length, greaterThanOrEqualTo(2));
      expect(ids(pushes[0].profiles), [p1.id, p2.id, p3.id]..sort(),
          reason: 'profiles ride in the earliest batch');
      expect(pushes[0].dayEntries, hasLength(4));
      expect(pushes[1].profiles, isEmpty);
      expect(pushes[1].dayEntries, hasLength(2));
      for (final batch in pushes) {
        expect(batch.rowCount, lessThanOrEqualTo(8));
        expect(batch.profiles.length, lessThanOrEqualTo(4));
        expect(batch.dayEntries.length, lessThanOrEqualTo(4));
      }
      final allEntryIds = pushes.expand((b) => ids(b.dayEntries)).toSet();
      expect(allEntryIds, containsAll(entries.map((e) => e.id)));
      final tombstone = pushes
          .expand((b) => b.dayEntries)
          .firstWhere((r) => r['id'] == tombstoneId);
      expect(tombstone['deleted_at'], isNotNull,
          reason: 'tombstones are pushed');

      // The edited row was pushed twice: once in batch 1 (old rev, whose
      // markPushed must not clear the newer local_rev) and again later.
      final editedPushes = pushes
          .where((b) => ids(b.dayEntries).contains(edited.id))
          .length;
      expect(editedPushes, 2,
          reason: 'markPushed with the pre-request rev leaves the row dirty');
      expect(await s.dirtyCount(), 0);
      expect((await rig.entry(p1.id, edited.id)).flow, FlowLevel.heavy);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.dirtyCount, 0);
    });

    test('a batch is never larger than 500 rows per table by default',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final start = DateTime.utc(2024, 1, 1);
      for (var i = 0; i < 501; i++) {
        final d = start.add(Duration(days: i));
        final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
        await rig.storage.upsertDayEntry(
            profileId: p.id, localDate: date, tz: 'UTC', flow: FlowLevel.light);
      }
      await rig.start();
      expect(rig.transport.pushes, hasLength(2));
      expect(rig.transport.pushes[0].dayEntries, hasLength(500));
      expect(rig.transport.pushes[1].dayEntries, hasLength(1));
      expect(await rig.storage.dirtyCount(), 0);
    });

    test('AE6: a transport that throws after the server accepted leaves rows '
        'dirty; the next cycle re-pushes an identical payload', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.nextPushError = const SyncTransportError.network();

      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect(await rig.storage.dirtyCount(), 2, reason: 'nothing cleared');
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
      expect(rig.transport.pulls, isEmpty, reason: 'a failed push ends the cycle');

      await rig.sync();
      expect(rig.transport.pushes, hasLength(2));
      expect(rig.transport.pushes[1].profiles, rig.transport.pushes[0].profiles);
      expect(rig.transport.pushes[1].dayEntries,
          rig.transport.pushes[0].dayEntries);
      expect(await rig.storage.dirtyCount(), 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('resolved rows (losers and declined) are applied dirty = false '
        'before the pull; a declined edit is reverted in the same cycle',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      // The server holds a newer copy: the local edit is declined.
      final serverCopy = remoteEntry(e.id,
          profileId: p.id,
          flow: FlowLevel.heavy,
          updatedAt: t0.add(const Duration(hours: 1)),
          serverVersion: 5);
      rig.transport.scriptPushResult(resolved: [serverCopy]);
      DayEntry? atPull;
      rig.transport.onPull = (call) async {
        atPull ??= await rig.entry(p.id, e.id);
      };

      await rig.start();

      expect(atPull, isNotNull, reason: 'the pull ran after the push');
      expect(atPull!.flow, FlowLevel.heavy,
          reason: 'server copy applied before the first pull');
      expect(atPull!.dirty, isFalse);
      final after = await rig.entry(p.id, e.id);
      expect(after.flow, FlowLevel.heavy);
      expect(after.dirty, isFalse);
      expect(await rig.storage.dirtyCount(), 0);
    });

    test('the clock offset from server_now is stored and applied to '
        'subsequent local writes', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      rig.transport.scriptPushResult(
          serverNow: t0.add(const Duration(minutes: 5)));

      await rig.start();

      expect(rig.storage.clockOffset, const Duration(minutes: 5));
      expect((await rig.state()).serverClockOffsetMs, 5 * 60 * 1000);
      rig.clock.now = t0.add(const Duration(seconds: 1));
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      expect(e.updatedAt, t0.add(const Duration(minutes: 5, seconds: 1)));
    });

    test('a rejected row stays dirty, is not retried until edited again, and '
        'is counted in the snapshot', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.scriptPushResult(rejectedIds: [e.id]);

      await rig.start();
      expect(rig.transport.pushes, hasLength(1));
      expect((await rig.entry(p.id, e.id)).dirty, isTrue);
      expect((await rig.profile(p.id)).dirty, isFalse);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a rejection is not a cycle failure');
      expect(rig.engine.snapshot.rejectedCount, 1);
      expect(rig.engine.snapshot.dirtyCount, 1);

      await rig.sync();
      await rig.sync();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'the rejected row is not re-pushed in a tight loop');
      expect(rig.engine.snapshot.rejectedCount, 1);

      // A later local edit bumps local_rev: pushed again, accepted.
      await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.heavy);
      await rig.sync();
      expect(rig.transport.pushes, hasLength(2));
      expect(ids(rig.transport.pushes[1].dayEntries), [e.id]);
      expect((await rig.entry(p.id, e.id)).dirty, isFalse);
      expect(rig.engine.snapshot.rejectedCount, 0);
    });

    test('SyncTransportError.rejected (a transport with no per-row results) '
        'marks the whole batch rejected, not a cycle failure, and is not '
        're-pushed until edited again', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      rig.transport.nextPushError = SyncTransportError.rejected([p.id, e.id]);

      await rig.start();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'the batch is recorded before the transport throws');
      expect((await rig.profile(p.id)).dirty, isTrue);
      expect((await rig.entry(p.id, e.id)).dirty, isTrue);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a whole-batch rejection is not a cycle failure');
      expect(rig.engine.snapshot.rejectedCount, 2);

      await rig.sync();
      expect(rig.transport.pushes, hasLength(1),
          reason: 'both rejected rows are excluded from the next push');
    });
  });

  group('pull', () {
    test('per-table incremental pull applies pages in order and advances '
        'only that table\'s cursor; a throwing page leaves the cursor at the '
        'previous page', () async {
      final rig = Rig(pageSize: 2);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      final pB = ulidN(2);
      final pC = ulidN(3);
      rig.transport.scriptPages(SyncTable.profiles, [
        [
          remoteProfile(pA, updatedAt: t0, serverVersion: 1),
          remoteProfile(pB, updatedAt: t0, serverVersion: 2),
        ],
        [remoteProfile(pC, updatedAt: t0, serverVersion: 3)],
      ]);
      rig.transport.scriptPages(SyncTable.dayEntries, [
        [
          remoteEntry(ulidN(10),
              profileId: pA, localDate: '2026-01-01', updatedAt: t0,
              serverVersion: 10),
          remoteEntry(ulidN(11),
              profileId: pA, localDate: '2026-01-02', updatedAt: t0,
              serverVersion: 11),
        ],
      ]);
      // The second day-entries page throws.
      rig.transport.onPull = (call) {
        if (call.table == SyncTable.dayEntries && call.afterVersion == 11) {
          rig.transport.nextPullError = const SyncTransportError.network();
        }
      };

      await rig.start();

      final calls = rig.transport.pulls;
      expect(calls.map((c) => (c.table, c.afterVersion)).toList(), [
        (SyncTable.profiles, 0),
        (SyncTable.profiles, 2),
        (SyncTable.dayEntries, 0),
        (SyncTable.dayEntries, 11),
      ]);
      final state = await rig.state();
      expect(state.cursorProfiles, 3);
      expect(state.cursorDayEntries, 11);
      expect((await rig.storage.getProfiles()).map((p) => p.id),
          containsAll([pA, pB, pC]));
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(2));
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
    });

    test('a profiles page ending at 900 does not move cursor_day_entries; '
        'day entries 501 to 899 are still pulled', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 0,
        cursorDayEntries: 500,
        lastFullPullAt: Value(t0),
      ));
      final pA = ulidN(1);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => after < 900
                ? [remoteProfile(pA, updatedAt: t0, serverVersion: 900)]
                : const [],
            SyncTable.dayEntries => after < 899
                ? [
                    remoteEntry(ulidN(600),
                        profileId: pA,
                        localDate: '2026-01-01',
                        updatedAt: t0,
                        serverVersion: 600),
                    remoteEntry(ulidN(899),
                        profileId: pA,
                        localDate: '2026-01-02',
                        updatedAt: t0,
                        serverVersion: 899),
                  ]
                : const [],
          };

      await rig.start();

      final entryCalls =
          rig.transport.pulls.where((c) => c.table == SyncTable.dayEntries);
      expect(entryCalls.first.afterVersion, 500,
          reason: 'the profiles page did not touch the day-entries cursor');
      final state = await rig.state();
      expect(state.cursorProfiles, 900);
      expect(state.cursorDayEntries, 899);
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(2));
    });

    test('a full-reconcile row with server_version below the cursor is still '
        'applied under LWW and both cursors stay unchanged', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 100,
        cursorDayEntries: 100,
        lastFullPullAt: Value(t0.subtract(const Duration(hours: 25))),
      ));
      final pA = ulidN(1);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => after == 0
                ? [remoteProfile(pA, updatedAt: t0, serverVersion: 50)]
                : const [],
            SyncTable.dayEntries => const [],
          };

      await rig.start();

      expect((await rig.storage.getProfiles()).map((p) => p.id), [pA]);
      final state = await rig.state();
      expect(state.cursorProfiles, 100);
      expect(state.cursorDayEntries, 100);
      expect(state.lastFullPullAt, isNotNull);
      expect(state.lastFullPullAt!.toUtc(), t0);
    });

    test('full reconcile runs on bind, after a push that returned resolved '
        'rows, and when the last full pull is older than 24h; not otherwise',
        () async {
      // (a) Bind on an empty database: reconcile stamps last_full_pull_at.
      final bindRig = Rig();
      addTearDown(bindRig.dispose);
      await bindRig.start();
      expect((await bindRig.state()).lastFullPullAt?.toUtc(), t0);

      // (b) Bound, recent full pull, cursors at 100: incremental only.
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.writeSyncState(kDefaultSyncState.copyWith(
        boundUserId: const Value(uidA),
        deviceId: 'device-1',
        cursorProfiles: 100,
        cursorDayEntries: 100,
        lastFullPullAt: Value(t0),
      ));
      await rig.start();
      expect(rig.transport.pulls.map((c) => c.afterVersion), [100, 100]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), t0);

      // (c) A push with resolved rows makes a reconcile due.
      rig.clock.now = t0.add(const Duration(hours: 1));
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      rig.transport.scriptPushResult(resolved: [
        remoteProfile(p.id,
            displayName: 'Server',
            updatedAt: t0.add(const Duration(hours: 2)),
            serverVersion: 101),
      ]);
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion), [100, 100, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), rig.clock.now);

      // (d) Not otherwise: the next cycle is incremental only.
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion), [100, 100]);

      // (e) Older than 24h: due again.
      rig.clock.now = rig.clock.now.add(const Duration(hours: 25));
      rig.transport.pulls.clear();
      await rig.sync();
      expect(rig.transport.pulls.map((c) => c.afterVersion), [100, 100, 0, 0]);
      expect((await rig.state()).lastFullPullAt?.toUtc(), rig.clock.now);
    });

    test('a retryable apply failure on pull leaves the cursor and is retried '
        'next cycle once the profile is held', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final pA = ulidN(1);
      final orphan = remoteEntry(ulidN(10),
          profileId: pA, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 10);
      // Cycle 1: the day entry arrives before its profile.
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);
      await rig.start();
      expect((await rig.state()).cursorDayEntries, 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'retryable, not fatal');

      // Cycle 2: the profile is there now; the entry applies.
      rig.transport.scriptPage(SyncTable.profiles,
          [remoteProfile(pA, updatedAt: t0, serverVersion: 1)]);
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);
      await rig.sync();
      expect((await rig.state()).cursorDayEntries, 10);
      expect(await rig.storage.getDayEntries(profileId: pA), hasLength(1));
    });

    test('a full-reconcile page that fails as a batch falls back to '
        'per-row application, and a row still left orphaned defers the '
        'next full-pull stamp (retried next cycle)', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final staleFullPull = t0.subtract(const Duration(hours: 25));
      await rig.bind(uidA, lastFullPullAt: staleFullPull);
      final pA = ulidN(1);
      final orphan = remoteEntry(ulidN(10),
          profileId: pA, localDate: '2026-01-01', updatedAt: t0,
          serverVersion: 10);
      // Incremental dayEntries gets nothing; the reconcile dayEntries call
      // (which starts over from version 0, same as incremental here) gets
      // the orphan — `applyRemoteRows` fails the whole page as one
      // transaction, `_applyReconcilePage` falls back to applying rows one
      // by one, and the entry alone still fails (its profile page was
      // never supplied), so it is left for the next cycle.
      rig.transport.scriptPage(SyncTable.dayEntries, const []);
      rig.transport.scriptPage(SyncTable.dayEntries, [orphan]);

      await rig.start();

      expect(rig.engine.snapshot.phase, SyncPhase.idle,
          reason: 'a retryable apply failure is not a cycle failure');
      expect(await rig.storage.getDayEntries(profileId: pA), isEmpty);
      expect((await rig.state()).lastFullPullAt?.toUtc(), staleFullPull,
          reason: 'reconcile is retried, so the full-pull stamp does not '
              'advance yet');
    });
  });

  group('gating (KTD10)', () {
    test('AE4: lock() during a multi-page pull finishes the current page, '
        'sets paused, starts no further page; unlock resumes from the '
        'persisted cursor', () async {
      final rig = Rig(pageSize: 1);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.scriptPages(SyncTable.profiles, [
        [remoteProfile(ulidN(1), updatedAt: t0, serverVersion: 1)],
        [remoteProfile(ulidN(2), updatedAt: t0, serverVersion: 2)],
        [remoteProfile(ulidN(3), updatedAt: t0, serverVersion: 3)],
      ]);
      rig.transport.onPull = (call) {
        if (call.table == SyncTable.profiles && call.afterVersion == 1) {
          rig.gate.lock();
        }
      };

      await rig.start();

      expect(rig.transport.pulls, hasLength(2),
          reason: 'the page in flight completes, no further page starts');
      expect(rig.engine.snapshot.phase, SyncPhase.paused);
      expect((await rig.state()).cursorProfiles, 2,
          reason: 'the in-flight page committed with its cursor');
      expect((await rig.storage.getProfiles()).length, 2);

      rig.transport.onPull = null;
      rig.gate.unlock();
      await rig.engine.flush();

      expect(rig.transport.pulls[2].afterVersion, 2,
          reason: 'resumed from the persisted cursor');
      expect((await rig.state()).cursorProfiles, 3);
      expect((await rig.storage.getProfiles()).length, 3);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('a locked gate at trigger time yields paused without any transport '
        'call', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.gate.unlocked = false;
      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.paused);
      expect(rig.transport.pullCount, 0);
      rig.gate.unlock();
      await rig.engine.flush();
      expect(rig.transport.pullCount, 2);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('a local write outside a cycle requests a sync after the debounce',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      expect(rig.transport.pushes, isEmpty);
      final before = rig.timers.oneShots.length;

      await rig.storage.upsertProfile(displayName: 'A', isMinor: false);
      // The table-update stream delivers asynchronously.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(rig.timers.oneShots.length, greaterThan(before),
          reason: 'a debounce timer was armed');
      rig.timers.oneShots.last.fire();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await rig.engine.flush();
      expect(rig.transport.pushes, hasLength(1));
      expect(await rig.storage.dirtyCount(), 0);
    });

    test('the periodic timer requests a sync', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      expect(rig.timers.periodics, hasLength(1));
      expect(rig.timers.periodics.single.delay, const Duration(minutes: 15));
      final pulls = rig.transport.pullCount;
      rig.timers.periodics.single.fire();
      await rig.engine.flush();
      expect(rig.transport.pullCount, pulls + 2);
    });
  });

  group('binding (R14, R15)', () {
    test('AE5: bound to A with session B yields accountMismatch, zero '
        'transport calls, an unchanged binding; signedOut returns to idle '
        'with the binding still A', () async {
      final rig = Rig(uid: uidB);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.storage.upsertProfile(displayName: 'A', isMinor: false);

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.accountMismatch);
      expect(rig.engine.snapshot.boundUserId, uidA);
      expect(rig.transport.pushCount, 0);
      expect(rig.transport.pullCount, 0);
      expect((await rig.state()).boundUserId, uidA);

      rig.auth.emit(AuthSessionState.signedOut);
      await Future<void>.delayed(Duration.zero);
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.boundUserId, uidA);
      expect((await rig.state()).boundUserId, uidA);
      expect(rig.transport.pushCount, 0);
      expect(rig.transport.pullCount, 0);
    });

    test('non-empty unbound database yields awaitingUploadConsent with zero '
        'transport calls; confirmUpload marks all dirty, binds and syncs',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      final e = await rig.storage.upsertDayEntry(
          profileId: p.id,
          localDate: '2026-01-15',
          tz: 'UTC',
          flow: FlowLevel.light);
      // Simulate a row that had been marked clean before any account.
      await rig.storage.markPushed(
          table: SyncTable.dayEntries, id: e.id, localRevAtPush: e.localRev);
      expect(await rig.storage.dirtyCount(), 1);

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.awaitingUploadConsent);
      expect(rig.engine.snapshot.boundUserId, isNull);
      expect(rig.transport.pushCount, 0);
      expect(rig.transport.pullCount, 0);
      expect((await rig.state()).boundUserId, isNull);

      await rig.engine.confirmUpload();
      await rig.engine.flush();

      final state = await rig.state();
      expect(state.boundUserId, uidA);
      expect(isValidUlid(state.deviceId), isTrue, reason: 'device id minted');
      expect(rig.transport.pushes, hasLength(1));
      expect(ids(rig.transport.pushes.single.profiles), [p.id]);
      expect(ids(rig.transport.pushes.single.dayEntries), [e.id],
          reason: 'markAllDirty re-flagged the clean row');
      expect(await rig.storage.dirtyCount(), 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.boundUserId, uidA);
    });

    test('confirmUpload is a no-op outside awaitingUploadConsent', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      final pushes = rig.transport.pushCount;
      await rig.engine.confirmUpload();
      await rig.engine.flush();
      expect(rig.transport.pushCount, pushes);
    });

    test('empty database with a confirmed session binds silently and pulls; '
        'the snapshot shows restoring until the bind-time full pull completes',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      final pA = ulidN(1);
      rig.transport.pageResolver = (table, after, limit) => switch (table) {
            SyncTable.profiles => after == 0
                ? [remoteProfile(pA, updatedAt: t0, serverVersion: 1)]
                : const [],
            SyncTable.dayEntries => const [],
          };
      SyncPhase? phaseDuringPull;
      rig.transport.onPull = (_) {
        phaseDuringPull ??= rig.engine.snapshot.phase;
      };

      await rig.start();

      final state = await rig.state();
      expect(state.boundUserId, uidA);
      expect(isValidUlid(state.deviceId), isTrue);
      expect(state.lastFullPullAt, isNotNull);
      expect(phaseDuringPull, SyncPhase.restoring);
      expect(rig.seen.map((s) => s.phase), contains(SyncPhase.restoring));
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.seen.last.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.boundUserId, uidA);
      expect((await rig.storage.getProfiles()).map((p) => p.id), [pA]);
      expect(rig.transport.pushCount, 0, reason: 'nothing dirty to push');

      // A later cycle is a plain one, not restoring.
      rig.seen.clear();
      await rig.sync();
      expect(rig.seen.map((s) => s.phase),
          isNot(contains(SyncPhase.restoring)));
    });

    test('a session that vanishes while the bind decision is pending never '
        'binds the empty database', () async {
      final rig = Rig(
          storageFactory: (db, clock) => HookedStorage(db, clock: clock));
      addTearDown(rig.dispose);
      (rig.storage as HookedStorage).beforeIsEmpty = () async {
        // The device reset signs out while the fresh database opens.
        rig.auth.emit(AuthSessionState.signedOut);
      };

      await rig.start();

      expect((await rig.state()).boundUserId, isNull);
      expect(rig.transport.pullCount, 0);
      expect(rig.transport.pushCount, 0);
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.engine.snapshot.boundUserId, isNull);
      expect(rig.seen.map((s) => s.phase),
          isNot(contains(SyncPhase.restoring)));
    });

    test('a signed-out session and a password-recovery session never sync',
        () async {
      final rig = Rig(authState: AuthSessionState.signedOut, uid: null);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.transport.pullCount, 0);

      rig.auth.emit(AuthSessionState.passwordRecovery,
          user: const AuthUser(id: uidA));
      await Future<void>.delayed(Duration.zero);
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.transport.pullCount, 0);
    });
  });

  group('errors', () {
    test('AE9: expired yields error(auth); local writes stay dirty; a later '
        'signedIn for the same uid resumes without consent', () async {
      final rig = Rig(authState: AuthSessionState.expired, uid: null);
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.auth);
      expect(rig.transport.pullCount, 0);
      expect((await rig.state()).lastError, 'auth');

      final p = await rig.storage.upsertProfile(
          displayName: 'A', isMinor: false);
      expect(p.dirty, isTrue);
      await rig.engine.flush();
      expect(rig.transport.pushCount, 0);

      rig.auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: uidA));
      await Future<void>.delayed(Duration.zero);
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.transport.pushes, hasLength(1));
      expect(await rig.storage.dirtyCount(), 0);
      expect((await rig.state()).lastError, isNull);
    });

    test('an auth transport error yields error(auth) and no backoff timer',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.persistentError = const SyncTransportError.auth();
      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.auth);
      expect(rig.timers.oneShots.where((t) => t.active), isEmpty);
    });

    test('network errors back off with the injected schedule and recover',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.persistentError = const SyncTransportError.network();

      await rig.start();
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
      expect((await rig.state()).lastError, 'network');
      var backoffs = rig.timers.oneShots.where((t) => t.active).toList();
      expect(backoffs, hasLength(1));
      expect(backoffs.single.delay, const Duration(seconds: 1));

      backoffs.single.fire();
      await rig.engine.flush();
      backoffs = rig.timers.oneShots.where((t) => t.active).toList();
      expect(backoffs, hasLength(1));
      expect(backoffs.single.delay, const Duration(seconds: 2),
          reason: 'second consecutive failure');

      rig.transport.persistentError = null;
      backoffs.single.fire();
      await rig.engine.flush();
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
      expect(rig.timers.oneShots.where((t) => t.active), isEmpty);
    });

    test('the default backoff is exponential with jitter and capped at 10 '
        'minutes', () {
      expect(defaultSyncBackoff(1), greaterThanOrEqualTo(const Duration(seconds: 30)));
      expect(defaultSyncBackoff(1), lessThan(const Duration(seconds: 40)));
      expect(defaultSyncBackoff(3), greaterThanOrEqualTo(const Duration(minutes: 2)));
      expect(defaultSyncBackoff(20), lessThanOrEqualTo(const Duration(minutes: 10)));
      expect(defaultSyncBackoff(20), greaterThan(const Duration(minutes: 8)));
    });
  });

  group('lifecycle', () {
    test('two requestSync() calls during a running cycle produce exactly one '
        'follow-up cycle', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final hold = Completer<void>();
      rig.transport.gate = hold;

      rig.engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rig.transport.pullCount, 1, reason: 'held on the first pull');
      rig.engine.requestSync();
      rig.engine.requestSync();
      rig.transport.gate = null;
      hold.complete();
      await rig.engine.flush();

      expect(rig.transport.pullCount, 4,
          reason: 'two cycles of two pulls: the running one plus one queued');
      expect(rig.engine.snapshot.phase, SyncPhase.idle);
    });

    test('dispose() during a running cycle lets the page finish and leaves '
        'no pending timers or subscriptions', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      final hold = Completer<void>();
      rig.transport.gate = hold;

      rig.engine.start();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(rig.transport.pullCount, 1);
      final disposal = rig.engine.dispose();
      expect(rig.timers.active, isEmpty, reason: 'timers cancelled at once');
      rig.transport.gate = null;
      hold.complete();
      await disposal;

      expect(rig.transport.pullCount, 1,
          reason: 'the in-flight page finished, no further page started');
      expect(rig.timers.active, isEmpty);
      rig.engine.requestSync();
      await rig.engine.flush();
      expect(rig.transport.pullCount, 1, reason: 'disposed engines are inert');
      // A second dispose is harmless (the rig's tearDown calls it again).
      await rig.engine.dispose();
    });

    test('start() is idempotent and snapshot getter mirrors the stream',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      expect(rig.engine.snapshot, SyncSnapshot.initial);
      await rig.start();
      rig.engine.start();
      expect(rig.timers.periodics, hasLength(1));
      expect(rig.seen.last, rig.engine.snapshot);
      expect(rig.engine.snapshot.lastSyncAt, t0);
      expect((await rig.state()).lastSyncAt?.toUtc(), t0);
    });
  });
}
