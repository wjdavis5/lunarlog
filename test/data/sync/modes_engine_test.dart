/// Issue #188: the sync engine's profile_modes/cycle_overrides wiring —
/// dirty rows of both new tables ride the push keyset chain in
/// `p_profile_modes`/`p_cycle_overrides`, pulls advance each table's own
/// cursor, a rejected row stays dirty and is retried after a local edit,
/// and a `resolved` row (a declined older push) is applied not-dirty. A
/// compact mirror of `sync_engine_test.dart`'s Rig.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';

import '../../support/fake_auth_service.dart';
import '../../support/fake_sync_transport.dart';

final t0 = DateTime.utc(2026, 9, 2, 10);

/// Valid Crockford ULIDs (the codec rejects anything else).
const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';
const overrideId = '01J8ZQ9K7MC2X3V4B5N6P7Q8S0';
const ghostId = '01J8ZQ9K7MC2X3V4B5N6P7Q8T1';
const uid = 'user-a';

class FixedClock {
  FixedClock(this.now);

  DateTime now;

  DateTime call() => now;
}

class FakeGateSignal extends ChangeNotifier {
  bool unlocked = true;
}

class FakeTimers {
  Timer oneShot(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  Timer periodic(Duration delay, void Function() callback) =>
      Timer.periodic(delay, (_) => callback());
}

class Rig {
  Rig() {
    db = LunarLogDatabase(NativeDatabase.memory());
    clock = FixedClock(t0);
    storage = LunarLogStorage(db, clock: clock.call);
    transport = FakeSyncTransport(serverClock: () => clock.now);
    auth = FakeAuthService();
    auth.emit(AuthSessionState.signedIn, user: AuthUser(id: uid));
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
      writeDebounce: Duration.zero,
    );
  }

  late final LunarLogDatabase db;
  late final FixedClock clock;
  late final LunarLogStorage storage;
  late final FakeSyncTransport transport;
  late final FakeAuthService auth;
  late final SupabaseSyncEngine engine;
  final FakeGateSignal gate = FakeGateSignal();
  final FakeTimers timers = FakeTimers();

  Future<void> start() async {
    await storage.writeSyncState(
      kDefaultSyncState.copyWith(
        boundUserId: const Value(uid),
        deviceId: 'device-1',
        lastFullPullAt: Value(t0),
      ),
    );
    engine.start();
    await engine.flush();
  }

  Future<void> sync() async {
    engine.requestSync();
    await engine.flush();
  }

  Future<SyncStateRow> state() => storage.readSyncState();

  Future<void> dispose() async {
    await engine.dispose();
    await auth.dispose();
    await db.close();
  }
}

RemoteProfileModeRow remoteMode(
  String profileId, {
  String mode = 'perimenopause',
  required DateTime updatedAt,
  int serverVersion = 0,
}) => RemoteProfileModeRow(
  profileId: profileId,
  mode: mode,
  updatedAt: updatedAt,
  serverVersion: serverVersion,
);

RemoteCycleOverrideRow remoteOverride(
  String id, {
  String profileId = profileId,
  String cycleStartDate = '2026-08-14',
  bool excludedFromAverage = true,
  bool manualStart = true,
  required DateTime updatedAt,
  DateTime? deletedAt,
  int serverVersion = 0,
}) => RemoteCycleOverrideRow(
  id: id,
  profileId: profileId,
  cycleStartDate: cycleStartDate,
  excludedFromAverage: excludedFromAverage,
  manualStart: manualStart,
  updatedAt: updatedAt,
  deletedAt: deletedAt,
  serverVersion: serverVersion,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('dirty profile_modes and cycle_overrides rows push in their own '
      'arrays and clear dirty', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    await rig.storage.upsertProfileMode(
      profileId: profileId,
      mode: 'conceive',
      modeStartedOn: '2026-09-02',
    );
    await rig.storage.upsertCycleOverride(
      id: overrideId,
      profileId: profileId,
      cycleStartDate: '2026-08-14',
      excludedFromAverage: true,
    );

    await rig.start();

    final batch = rig.transport.pushes.single;
    expect(batch.profileModes, hasLength(1));
    expect(batch.profileModes.single['mode'], 'conceive');
    expect(batch.profileModes.single['profile_id'], profileId);
    expect(batch.cycleOverrides, hasLength(1));
    expect(batch.cycleOverrides.single['id'], overrideId);
    expect(batch.cycleOverrides.single['excluded_from_average'], isTrue);
    expect(
      batch.profiles,
      isNotEmpty,
      reason: 'the profile itself still rides the same batch',
    );

    expect(await rig.storage.dirtyCount(), 0);
    expect((await rig.storage.getProfileMode(profileId))!.dirty, isFalse);
    expect(
      (await rig.storage.getCycleOverridesForProfile(
        profileId,
        includeTombstones: true,
      )).single.dirty,
      isFalse,
    );
  });

  test(
    'pull pages apply per table and advance each table cursor alone',
    () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.storage.upsertProfile(
        id: profileId,
        displayName: 'Riley',
        isMinor: true,
        updatedAt: t0,
      );
      await rig.start();

      rig.transport.scriptPage(SyncTable.profileModes, [
        remoteMode(
          profileId,
          mode: 'pregnancy',
          updatedAt: t0,
          serverVersion: 30,
        ),
      ]);
      rig.transport.scriptPage(SyncTable.cycleOverrides, [
        remoteOverride(overrideId, updatedAt: t0, serverVersion: 31),
      ]);
      await rig.sync();

      final mode = await rig.storage.getProfileMode(profileId);
      expect(mode!.mode, 'pregnancy');
      expect(mode.dirty, isFalse);

      final overrides = await rig.storage.getCycleOverridesForProfile(
        profileId,
        includeTombstones: true,
      );
      expect(overrides, hasLength(1));
      expect(overrides.single.id, overrideId);

      final state = await rig.state();
      expect(state.cursorProfileModes, 30);
      expect(state.cursorCycleOverrides, 31);
      expect(state.cursorProfiles, 0,
          reason: 'no profiles page was scripted, so that cursor alone '
              'stays put');
      expect(state.cursorDayEntries, 0);

      // A second cycle with no new pages pulls nothing new and keeps cursors.
      final pullsBefore = rig.transport.pullCount;
      await rig.sync();
      expect(rig.transport.pullCount, pullsBefore + 8,
          reason: 'a full cycle pulls all eight tables (Issue #128 adds '
              'care_notes/visit_prep_items)');
      expect((await rig.state()).cursorProfileModes, 30);
    },
  );

  test('a rejected profile_modes row stays dirty and is retried after a '
      'local edit bumps local_rev', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    // The mode row's push identity is the profile id, so rejecting it keys
    // the rejection exactly like a rejected profile would be.
    await rig.storage.upsertProfileMode(profileId: profileId, mode: 'conceive');
    rig.transport.scriptPushResult(rejectedIds: [profileId]);
    await rig.start();

    expect((await rig.storage.getProfileMode(profileId))!.dirty, isTrue);

    // A local edit bumps local_rev past the rejected one and frees the row;
    // the next push carries the edited mode (exact push counts are not
    // asserted — the zero-debounce write timer may coalesce cycles).
    rig.transport.pushResults.clear();
    await rig.storage.upsertProfileMode(
      profileId: profileId,
      mode: 'pregnancy',
      modeStartedOn: '2026-09-03',
    );
    await rig.sync();
    expect(
      rig.transport.pushes.any(
          (b) => b.profileModes.any((r) => r['mode'] == 'pregnancy')),
      isTrue,
      reason: 'the bumped mode row is retried after the local edit',
    );
    expect((await rig.storage.getProfileMode(profileId))!.dirty, isFalse);
  });

  test('a declined older push (a resolved row) is applied not-dirty and '
      'a tombstone pull clears the override payload', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.storage.upsertProfile(
      id: profileId,
      displayName: 'Riley',
      isMinor: true,
      updatedAt: t0,
    );
    await rig.storage.upsertCycleOverride(
      id: overrideId,
      profileId: profileId,
      cycleStartDate: '2026-08-14',
      excludedFromAverage: true,
      noteId: 'note-1',
    );
    rig.transport.scriptPushResult(
      resolved: [
        RemoteCycleOverrideRow(
          id: overrideId,
          profileId: profileId,
          cycleStartDate: '2026-08-14',
          excludedFromAverage: false,
          manualStart: false,
          updatedAt: t0.subtract(const Duration(hours: 1)),
          deletedAt: null,
          serverVersion: 5,
        ),
      ],
    );
    await rig.start();

    // The server copy (older) was declined, handed back, and applied
    // without dirtying — but the local row was the newer one, so LWW keeps
    // the local values; dirty cleared because the push was processed.
    final row = (await rig.storage.getCycleOverridesForProfile(
      profileId,
      includeTombstones: true,
    )).single;
    expect(
      row.excludedFromAverage,
      isTrue,
      reason: 'the newer local row wins the declined resolution',
    );
    expect(row.dirty, isFalse);

    // A pulled tombstone clears the payload locally, mirroring the server.
    rig.transport.scriptPage(SyncTable.cycleOverrides, [
      remoteOverride(
        overrideId,
        excludedFromAverage: false,
        manualStart: false,
        updatedAt: t0.add(const Duration(hours: 1)),
        deletedAt: t0.add(const Duration(hours: 1)),
        serverVersion: 9,
      ),
    ]);
    await rig.sync();
    final tombstoned = (await rig.storage.getCycleOverridesForProfile(
      profileId,
      includeTombstones: true,
    )).single;
    expect(tombstoned.deletedAt, isNotNull);
    expect(tombstoned.noteId, isNull);
    expect(tombstoned.cycleStartDate, '2026-08-14');
    expect(await rig.storage.getCycleOverridesForProfile(profileId), isEmpty);
  });

  test('a pull page for an unheld profile retries next cycle '
      '(RetryableSyncApplyError keeps the cursor)', () async {
    final rig = Rig();
    addTearDown(rig.dispose);
    await rig.start();

    rig.transport.scriptPage(SyncTable.profileModes, [
      remoteMode(ghostId, updatedAt: t0, serverVersion: 12),
    ]);
    await rig.sync();

    expect(
      (await rig.state()).cursorProfileModes,
      0,
      reason: 'the throwing page rolled the cursor back',
    );
    expect(await rig.storage.getProfileMode(ghostId), isNull);

    // Once the profile arrives, the same page applies cleanly.
    await rig.storage.upsertProfile(
      id: ghostId,
      displayName: 'Ghost',
      isMinor: false,
      updatedAt: t0,
    );
    rig.transport.scriptPage(SyncTable.profileModes, [
      remoteMode(ghostId, updatedAt: t0, serverVersion: 12),
    ]);
    await rig.sync();
    expect((await rig.state()).cursorProfileModes, 12);
    expect((await rig.storage.getProfileMode(ghostId))!.mode, 'perimenopause');
  });
}
