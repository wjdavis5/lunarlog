/// Issue #1171: the sync cycle's catch-all — previously a debugPrint of a
/// (minified on web) runtimeType and nothing else — reports the unexpected
/// error to Sentry under a `sync.phase: cycle` tag and an exception-type
/// fingerprint (so a failure repeating every 15-minute periodic cycle groups
/// into one issue, not one event per cycle), rate-limited per session the
/// way the network-backoff counter is, while `_fail` still records
/// `lastError: other`.
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
  /// capture from `_fail`'s own failing state write (issue #547 — a
  /// throwing `readSyncState` fails `_updateState`'s read first) can never
  /// be mistaken for one.
  List<SentryEvent> get cycleEvents => events
      .where((event) => event.tags?['sync.phase'] == 'cycle')
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

  @override
  Future<SyncStateRow> readSyncState() async {
    final error = readSyncStateError;
    if (error != null) throw error;
    return super.readSyncState();
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

    test('a mid-cycle storage failure with a working state write produces '
        'exactly one event — the catch-all capture is the only one',
        () async {
      final sentry = _RecordingHub();
      final (:rig, storage: _) = _failingRig(
        sentry,
        dirtyCountError: StateError('read-only database'),
      );
      addTearDown(rig.dispose);
      await rig.bind(uidA);

      await rig.start();

      expect(sentry.cycleEvents, hasLength(1));
      expect(sentry.events, sentry.cycleEvents,
          reason: "_fail's own state write succeeds here, so nothing else "
              'is captured');
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
}
