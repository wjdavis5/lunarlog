/// gate locking (KTD10), the write debounce, and the periodic timer — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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
      expect(rig.transport.pullCount, 8);
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
      expect(rig.transport.pullCount, pulls + 8);
    });
  });
}
