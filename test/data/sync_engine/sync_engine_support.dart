/// U5 engine tests (KTD2, KTD4, KTD10, KTD11; AE4, AE5, AE6, AE9): push
/// batching and `markPushed` revisions, resolved/declined rows, the clock
/// offset, per-table cursors, full reconciliation cadence, gating, binding,
/// mismatch, errors, coalescing and disposal — all against
/// `FakeSyncTransport`, `FakeAuthService`, an in-memory drift database, a
/// fake gate `Listenable` and fake timers. Nothing here touches Supabase.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import '../../support/fake_auth_service.dart';
import '../../support/fake_sync_transport.dart';

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

RemoteProfileGuardianRow remoteGuardian(
  String id, {
  required String profileId,
  required String userId,
  String role = 'caregiver',
  required String status,
  required DateTime updatedAt,
  DateTime? createdAt,
  int serverVersion = 0,
}) =>
    RemoteProfileGuardianRow(
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

/// Storage with test seams in front of two writes: `isEmpty` runs
/// [beforeIsEmpty] first, so a test can change the session in the middle of
/// the engine's bind decision, and `markPushed` runs [beforeMarkPushed]
/// first, so a test can fail a storage apply between two push batches.
class HookedStorage extends LunarLogStorage {
  HookedStorage(super.db, {super.clock});

  Future<void> Function()? beforeIsEmpty;

  Future<void> Function(SyncTable table, String id)? beforeMarkPushed;

  @override
  Future<bool> isEmpty() async {
    await beforeIsEmpty?.call();
    return super.isEmpty();
  }

  @override
  Future<bool> markPushed({
    required SyncTable table,
    required String id,
    required int localRevAtPush,
  }) async {
    await beforeMarkPushed?.call(table, id);
    return super.markPushed(
        table: table, id: id, localRevAtPush: localRevAtPush);
  }
}

/// Storage decorator (KTD6 pattern, like [HookedStorage]) recording the
/// returned page length of every `readDirtyProfiles`/`readDirtyDayEntries`
/// call, so a test can pin the bounded-read property (finding #3): no such
/// call may return more rows than the engine's batch size, however large
/// the dirty set, and regardless of what else is happening mid-push (e.g.
/// un-rejecting a day entry). This fails against the old single-shot
/// `_chunk` (an unbounded read of the whole dirty set) and against the
/// pre-fix `_unrejectEntriesOf` (an unbounded `readDirtyDayEntries()` call
/// with no `limit`).
class CountingStorage extends LunarLogStorage {
  CountingStorage(super.db, {super.clock});

  final List<int> profilePageLengths = [];
  final List<int> dayEntryPageLengths = [];

  @override
  Future<List<Profile>> readDirtyProfiles({int? limit, String? afterId}) async {
    final page = await super.readDirtyProfiles(limit: limit, afterId: afterId);
    profilePageLengths.add(page.length);
    return page;
  }

  @override
  Future<List<DayEntry>> readDirtyDayEntries({
    int? limit,
    String? afterId,
  }) async {
    final page =
        await super.readDirtyDayEntries(limit: limit, afterId: afterId);
    dayEntryPageLengths.add(page.length);
    return page;
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

