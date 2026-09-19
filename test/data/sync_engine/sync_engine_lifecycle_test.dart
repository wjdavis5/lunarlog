/// request coalescing, disposal, and start() idempotence — issue #437 split of `test/data/sync_engine_test.dart`.
/// Shared fixtures live in `sync_engine_support.dart`. Nothing here
/// touches Supabase.
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/widgets.dart' show AppLifecycleState;
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

      expect(rig.transport.pullCount, 26,
          reason: 'two cycles of thirteen pulls (Issue #240 adds '
              'observations, Issue #188 adds profile_modes/'
              'cycle_overrides, Issue #128 adds care_notes/'
              'visit_prep_items, Issue #801 adds guardian_notes, '
              'Issue #522 adds deleted_profiles, '
              'Issue #130 adds day_entry_merge_events, Issue #257 adds '
              'profile_tag_registry, Issue #170 adds day_entry_history): '
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

  group('lifecycle rate-limit and timer pause (issue #842)', () {
    test(
        'a resume within the threshold, with a clean store and Realtime '
        'subscribed, makes no request', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      final pulls = rig.transport.pullCount;
      rig.engine.attachRealtimeSubscribedProbe(() => true);

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.paused);
      rig.engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await rig.engine.flush();

      expect(rig.transport.pullCount, pulls,
          reason: 'clean, recent, Realtime-subscribed resume is redundant');
    });

    test('a resume within the threshold but with dirty rows does sync',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      final pulls = rig.transport.pullCount;
      rig.engine.attachRealtimeSubscribedProbe(() => true);
      await rig.storage.upsertProfile(displayName: 'A', isMinor: false);

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await rig.engine.flush();

      expect(rig.transport.pullCount, greaterThan(pulls),
          reason: 'a dirty row must never be skipped');
      expect(rig.transport.pushes, isNotEmpty);
    });

    test('a resume with Realtime down does sync even within the threshold',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      final pulls = rig.transport.pullCount;
      // No probe attached: the safe "not subscribed" default.

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await rig.engine.flush();

      expect(rig.transport.pullCount, greaterThan(pulls),
          reason: 'with Realtime down the pull is the only change signal');
    });

    test('a user-initiated requestSync is never skipped', () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      final pulls = rig.transport.pullCount;
      rig.engine.attachRealtimeSubscribedProbe(() => true);

      // Clean store, within the threshold, Realtime subscribed — the exact
      // shape a lifecycle trigger would skip. A user-initiated sync must
      // still run.
      rig.engine.requestSync();
      await rig.engine.flush();

      expect(rig.transport.pullCount, greaterThan(pulls));
    });

    test('the periodic timer pauses on paused/hidden and resumes on resumed',
        () async {
      final rig = Rig();
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      await rig.start();
      expect(rig.timers.periodics.where((t) => t.active), hasLength(1));

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(rig.timers.periodics.where((t) => t.active), isEmpty,
          reason: 'backgrounding cancels the 15-minute timer');

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(rig.timers.periodics.where((t) => t.active), hasLength(1),
          reason: 'foregrounding restores it');
      expect(rig.timers.periodics, hasLength(2),
          reason: 'a fresh timer, not the cancelled one');

      rig.engine.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(rig.timers.periodics.where((t) => t.active), isEmpty);
    });
  });
}
