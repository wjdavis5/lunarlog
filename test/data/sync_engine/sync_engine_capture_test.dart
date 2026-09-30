/// Issue #1171: the sync cycle's catch-all — previously a debugPrint of a
/// (minified on web) runtimeType and nothing else — reports the unexpected
/// error to Sentry under a `sync.phase: cycle` tag and an exception-type
/// fingerprint (so a failure repeating every 15-minute periodic cycle groups
/// into one issue, not one event per cycle), rate-limited per session the
/// way the network-backoff counter is, while `_fail` still records
/// `lastError: other`.
///
/// Issue #1181: the failure path's two sibling captures — `_fail`'s
/// state-write catch and `_safeDirtyCount`'s catch — previously fired
/// unconditionally every failing cycle (the audit's ~205-events-a-day
/// residual flood) and through the static capture, invisible to any stub
/// hub. They now ride the same streak gate and go through the same
/// hub-routed capture under their own `sync.phase` tags, so a test can
/// watch them the same way.
///
/// Captures are observed through a stubbed `Hub` — the real SDK over a
/// no-op transport with a `beforeSend` recorder, the
/// `test/observability/crash_smoke_test.dart` pattern — never a global
/// `Sentry.init`. Nothing here touches Supabase.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/supabase_sync_engine.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sync_engine_support.dart';

class _NoopTransport implements Transport {
  @override
  Future<SentryId?> send(SentryEnvelope envelope) async => null;
}

/// A real [Hub] over a no-op transport whose `beforeSend` records every
/// event it is offered — the crash_smoke_test stub pattern: no global Sentry
/// state, no network, and the event has been through the same scope-merge
/// the real capture path performs.
class _RecordingHub {
  _RecordingHub() {
    final options = SentryOptions(dsn: 'https://public@o0.ingest.sentry.io/1')
      ..transport = _NoopTransport();
    options.beforeSend = (event, hint) {
      events.add(event);
      return null;
    };
    hub = Hub(options);
  }

  late final Hub hub;
  final events = <SentryEvent>[];

  /// The catch-all's captures: tagged `sync.phase: cycle`, so a sibling
  /// capture from `_fail`'s own failing state write or `_safeDirtyCount`
  /// (issues #547/#1181 — a throwing `readSyncState` fails `_updateState`'s
  /// read first, and a throwing `dirtyCount` falls back to the stale
  /// count) can never be mistaken for one.
  List<SentryEvent> get cycleEvents => events
      .where((event) => event.tags?['sync.phase'] == 'cycle')
      .toList();

  /// `_fail`'s state-write sibling capture (issue #1181: gated and
  /// hub-routed, tagged `sync.phase: state_write`).
  List<SentryEvent> get stateWriteEvents => events
      .where((event) => event.tags?['sync.phase'] == 'state_write')
      .toList();

  /// `_safeDirtyCount`'s sibling capture (issue #1181: gated and
  /// hub-routed, tagged `sync.phase: dirty_count`).
  List<SentryEvent> get dirtyCountEvents => events
      .where((event) => event.tags?['sync.phase'] == 'dirty_count')
      .toList();
}

/// Storage whose sync-cursor reads fail like the long-idle web database the
/// issue reports: `readSyncState` (the cycle's very first storage call) and
/// `dirtyCount` (mid-cycle, after binding) can each be made to throw
/// independently, so a test controls whether `_fail`'s own state write
/// succeeds or fails too.
class FailureInjectingStorage extends LunarLogStorage {
  FailureInjectingStorage(super.db, {super.clock});

  Object? readSyncStateError;

  Object? dirtyCountError;

  /// The write half of `_updateState` (issue #1240): the streak-less routes
  /// into `_fail` (a transport error, an expired session) leave the cycle's
  /// own reads alone, so a test reaching those routes with a failing state
  /// write breaks this instead of [readSyncStateError].
  Object? writeSyncStateError;

  @override
  Future<SyncStateRow> readSyncState() async {
    final error = readSyncStateError;
    if (error != null) throw error;
    return super.readSyncState();
  }

  @override
  Future<void> writeSyncState(SyncStateRow state) async {
    final error = writeSyncStateError;
    if (error != null) throw error;
    return super.writeSyncState(state);
  }

  @override
  Future<int> dirtyCount() async {
    final error = dirtyCountError;
    if (error != null) throw error;
    return super.dirtyCount();
  }
}

/// A rig whose storage fails on demand, plus the handle to keep failing (or
/// stop failing) it mid-test.
({Rig rig, FailureInjectingStorage storage}) _failingRig(
  _RecordingHub sentry, {
  String? uid = uidA,
  Object? readSyncStateError,
  Object? dirtyCountError,
}) {
  late final FailureInjectingStorage storage;
  final rig = Rig(
    uid: uid,
    storageFactory: (db, clock) {
      storage = FailureInjectingStorage(db, clock: clock)
        ..readSyncStateError = readSyncStateError
        ..dirtyCountError = dirtyCountError;
      return storage;
    },
    sentryHub: sentry.hub,
  );
  return (rig: rig, storage: storage);
}

/// The engine's captures are deliberately fire-and-forget (`unawaited`), so
/// after a cycle returns the hub's async `beforeSend` hop still needs a few
/// event-loop turns before every recorded event is visible. One turn
/// suffices for the catch-all's capture (initiated first — the existing
/// #1171 tests rely on that); the sibling captures trail it by a couple of
/// hops (issue #1181), so tests asserting on them drain a generous,
/// deterministic number of turns.
Future<void> settleCaptures() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('cycle catch-all capture (#1171)', () {
    test('a failing readSyncState is captured once, fingerprinted on the '
        'exception type, tagged sync.phase: cycle, and lands as lastError: '
        'other', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('idle web database closed'),
      );
      addTearDown(rig.dispose);

      await rig.start();

      final mine = sentry.cycleEvents;
      expect(mine, hasLength(1));
      final event = mine.single;
      expect(event.tags?['sync.phase'], 'cycle');
      expect(event.fingerprint, ['lunarlog-sync-cycle', 'StateError']);
      final exception = event.exceptions!.single;
      expect(exception.type, 'StateError');
      expect(exception.stackTrace, isNotNull);
      expect(rig.engine.snapshot.phase, SyncPhase.error);
      expect(rig.engine.snapshot.lastError, SyncErrorKind.other);
    });

    test('a signed-out profile with a failing store still captures before '
        'its quiet idle exit (the reported long-idle web scenario)',
        () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        uid: null,
        readSyncStateError: StateError('idle web database closed'),
      );
      addTearDown(rig.dispose);

      await rig.start();

      expect(sentry.cycleEvents, hasLength(1));
      expect(rig.engine.snapshot.lastError, SyncErrorKind.other);
    });

    test('repeats are rate-limited: the first failure of a streak reports, '
        'the next ${kSyncCycleCaptureEveryNthFailure - 1} stay quiet, then '
        'the ${kSyncCycleCaptureEveryNthFailure}th reports again', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('still down'),
      );
      addTearDown(rig.dispose);

      await rig.start();
      expect(sentry.cycleEvents, hasLength(1),
          reason: 'the first failure of the streak reports');

      for (var i = 0; i < kSyncCycleCaptureEveryNthFailure - 2; i++) {
        await rig.sync();
      }
      expect(sentry.cycleEvents, hasLength(1),
          reason: 'failures 2..${kSyncCycleCaptureEveryNthFailure - 1} stay '
              'quiet');

      await rig.sync();
      expect(sentry.cycleEvents, hasLength(2),
          reason: 'the every-${kSyncCycleCaptureEveryNthFailure}th report '
              'proves the failure is still ongoing');
    });

    test('the sibling storage-failure captures ride the same streak gate '
        '(#1181): a closed-database day reports from every site only on '
        'the reported cycles', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('closed web database'),
        dirtyCountError: StateError('closed web database'),
      );
      addTearDown(rig.dispose);

      await rig.start();
      await settleCaptures();
      expect(sentry.cycleEvents, hasLength(1));
      expect(sentry.stateWriteEvents, hasLength(1),
          reason: "_fail's state-write capture is no longer unconditional "
              '(issue #1181)');
      expect(sentry.dirtyCountEvents, hasLength(1),
          reason: '_safeDirtyCount is no longer unconditional '
              '(issue #1181)');
      expect(sentry.events, hasLength(3));

      for (var i = 0; i < kSyncCycleCaptureEveryNthFailure - 2; i++) {
        await rig.sync();
      }
      await settleCaptures();
      expect(sentry.events, hasLength(3),
          reason: 'streaks 2..${kSyncCycleCaptureEveryNthFailure - 1} stay '
              "quiet at every capture site, not just the catch-all's");

      await rig.sync();
      await settleCaptures();
      expect(sentry.cycleEvents, hasLength(2));
      expect(sentry.stateWriteEvents, hasLength(2));
      expect(sentry.dirtyCountEvents, hasLength(2));
      expect(sentry.events, hasLength(6),
          reason: 'the every-${kSyncCycleCaptureEveryNthFailure}th cycle '
              'reports from all three sites — 6 events grouped into one '
              'issue per streak, not the 18 an unguarded run would flood');
    });

    test('the sibling captures carry their own sync.phase tag on the shared '
        'cycle fingerprint: one issue per exception type, never mistaken '
        'for the catch-all capture', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('closed web database'),
        dirtyCountError: StateError('closed web database'),
      );
      addTearDown(rig.dispose);

      await rig.start();
      await settleCaptures();

      final stateWrite = sentry.stateWriteEvents.single;
      expect(stateWrite.tags?['sync.phase'], 'state_write');
      expect(stateWrite.fingerprint, ['lunarlog-sync-cycle', 'StateError'],
          reason: 'same fingerprint as the catch-all capture, so every '
              'reporting site groups into one issue');
      expect(stateWrite.exceptions!.single.type, 'StateError');

      final dirtyCount = sentry.dirtyCountEvents.single;
      expect(dirtyCount.tags?['sync.phase'], 'dirty_count');
      expect(dirtyCount.fingerprint, ['lunarlog-sync-cycle', 'StateError']);
    });

    test('a successful cycle resets the streak: the next failure reports '
        'again', () async {
      final sentry = _RecordingHub();
      final (:rig, :storage) = _failingRig(
        sentry,
        readSyncStateError: StateError('down'),
      );
      addTearDown(rig.dispose);

      await rig.start();
      await rig.sync();
      expect(sentry.cycleEvents, hasLength(1),
          reason: 'streak of 2: only the first reports');

      storage.readSyncStateError = null;
      await rig.sync();
      expect(rig.engine.snapshot.lastError, SyncErrorKind.none);
      expect(sentry.cycleEvents, hasLength(1));

      storage.readSyncStateError = StateError('down again');
      await rig.sync();
      expect(sentry.cycleEvents, hasLength(2),
          reason: 'the streak restarted, so this first failure reports');
    });

    test('a mid-cycle storage failure with a working state write reports '
        'from the catch-all and the dirty-count fallback only — the '
        'state-write sibling has nothing to report', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        dirtyCountError: StateError('read-only database'),
      );
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      await rig.start();
      await settleCaptures();

      expect(sentry.cycleEvents, hasLength(1));
      expect(sentry.dirtyCountEvents, hasLength(1),
          reason: 'the stale-count fallback capture fires on the streak '
              'gate like every other site (issue #1181), here on the '
              'first failure of the streak');
      expect(sentry.stateWriteEvents, isEmpty,
          reason: "_fail's own state write succeeds here");
      expect(sentry.events, hasLength(2),
          reason: 'nothing else is captured');
      expect(rig.engine.snapshot.lastError, SyncErrorKind.other);
    });

    test('transport errors keep their own branch: no capture', () async {
      final sentry = _RecordingHub();
      final rig = Rig(sentryHub: sentry.hub);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      rig.transport.persistentError = const SyncTransportError.network();

      await rig.start();

      expect(sentry.cycleEvents, isEmpty,
          reason: 'expected transport failures are backoff territory, not '
              'crash reports');
      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
    });

    test('debug builds log the full error beside the runtimeType line',
        () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('idle web database closed'),
      );
      addTearDown(rig.dispose);

      final printed = <String?>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message);
      try {
        await rig.start();
      } finally {
        debugPrint = previous;
      }

      expect(printed, containsAll(<Matcher>[
        contains('lunarlog sync: cycle failed (StateError)'),
        contains(
            'lunarlog sync: cycle error: Bad state: idle web database closed'),
      ]));
    });
  });

  group('the sibling gate stays closed at streak 0 (#1240)', () {
    // Every sibling test above arms the streak first: rig.start() fails
    // through the catch-all, which increments _consecutiveCycleFailures
    // before either sibling is consulted. The two routes into _fail that
    // never touch the streak — a transport error and an expired session —
    // used to find the gate open anyway, because 0 % 8 == 0, and fired the
    // state_write/dirty_count captures on every failing cycle. The doc
    // comment on _captureGatedSiblingFailure already promised these
    // compound failures stay quiet; these tests pin that promise.
    test('a streak-less expired-session _fail with a failing state write '
        'and failing dirty count captures nothing', () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        readSyncStateError: StateError('closed web database'),
        dirtyCountError: StateError('closed web database'),
      );
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      // The expired check is _cycle's second early-out, before its first
      // storage read — so the session expiry alone routes the whole cycle
      // into _fail at a streak of 0.
      rig.auth.emit(AuthSessionState.expired);

      await rig.start();
      await settleCaptures();

      expect(rig.engine.snapshot.lastError, SyncErrorKind.auth);
      expect(sentry.cycleEvents, isEmpty,
          reason: 'the expired-session route never arms the streak, so the '
              'catch-all has nothing to report either');
      expect(sentry.stateWriteEvents, isEmpty,
          reason: '_fail threw all the way through its state write, but the '
              'gate must be closed at streak 0 — 0 % 8 == 0 must not open '
              'it (issue #1240)');
      expect(sentry.dirtyCountEvents, isEmpty,
          reason: 'the dirty-count fallback is gated the same way');
      expect(sentry.events, isEmpty,
          reason: 'a streak-less compound failure stays quiet, full stop');
    });

    test('a streak-less transport failure with a failing state write '
        'captures nothing, and the next unexpected failure re-arms the '
        'siblings', () async {
      final sentry = _RecordingHub();
      final (:rig, :storage) = _failingRig(sentry);
      addTearDown(rig.dispose);
      await rig.bind(uidA);
      // After the bind: bind itself writes the sync state row, and the
      // break must start only once the cycle runs.
      storage.writeSyncStateError = StateError('read-only database');
      rig.transport.persistentError = const SyncTransportError.network();

      await rig.start();
      await settleCaptures();

      expect(rig.engine.snapshot.lastError, SyncErrorKind.network);
      expect(sentry.cycleEvents, isEmpty,
          reason: 'expected transport failures are backoff territory, not '
              'crash reports');
      expect(sentry.stateWriteEvents, isEmpty,
          reason: "the cycle's own reads succeeded and _fail's state write "
              'threw — at streak 0 that compound failure stays quiet '
              '(issue #1240)');
      expect(sentry.dirtyCountEvents, isEmpty);
      expect(sentry.events, isEmpty);

      // The next UNEXPECTED failure re-arms the streak: the catch-all
      // reports from a fresh streak and the siblings ride it again, exactly
      // as _captureGatedSiblingFailure's doc comment promises.
      storage.readSyncStateError = StateError('closed web database');
      storage.dirtyCountError = StateError('closed web database');
      await rig.sync();
      await settleCaptures();

      expect(sentry.cycleEvents, hasLength(1),
          reason: 'the unexpected failure reports from a fresh streak');
      expect(sentry.stateWriteEvents, hasLength(1),
          reason: "re-armed: _fail's state-write sibling reports on the "
              "catch-all's streak again");
      expect(sentry.dirtyCountEvents, hasLength(1),
          reason: 'the dirty-count sibling rides the same streak');
      expect(sentry.events, hasLength(3),
          reason: 'one reported cycle, three sites — not a second '
              'streak-less flood');
    });
  });
}
