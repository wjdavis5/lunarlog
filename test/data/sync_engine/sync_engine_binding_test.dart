/// account binding, upload consent, and mismatch (R14, R15) — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/db/ulid.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
            SyncTable.profileGuardians => const [],
            SyncTable.dayEntries => const [],
            SyncTable.observations => const [],
            SyncTable.profileModes => const [],
            SyncTable.cycleOverrides => const [],
            SyncTable.careNotes => const [],
            SyncTable.visitPrepItems => const [],
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
}
