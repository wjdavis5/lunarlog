/// request coalescing, disposal, and start() idempotence — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';

import 'sync_engine_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

      expect(rig.transport.pullCount, 16,
          reason: 'two cycles of eight pulls (Issue #240 adds observations, '
              'Issue #188 adds profile_modes/cycle_overrides, Issue #128 '
              'adds care_notes/visit_prep_items): '
              'the running one plus one queued');
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
