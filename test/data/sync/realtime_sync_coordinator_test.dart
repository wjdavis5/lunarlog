import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart';
import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/data/sync/realtime_sync_coordinator.dart';
import 'package:lunarlog/domain/auth/auth_service.dart';
import 'package:lunarlog/domain/sync/sync_engine.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../support/fake_auth_service.dart';

class FakeSyncEngine implements SyncEngine {
  int syncRequestCount = 0;

  @override
  void requestSync() {
    syncRequestCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRealtimeChannel implements RealtimeChannel {
  FakeRealtimeChannel(this.topic);

  @override
  final String topic;

  /// The coordinator listens on `sync_signals` only (Issue #77 PR #92
  /// review revision of KTD2) — see realtime_sync_coordinator.dart's
  /// top-of-file doc comment for why `day_entries`/`profiles` are never
  /// subscribed to directly.
  void Function(PostgresChangePayload payload)? syncSignalsCallback;

  /// Issue #98: the status callback the coordinator passes to `subscribe`,
  /// kept so tests can drive terminal statuses on demand.
  void Function(RealtimeSubscribeStatus status, Object? error)? statusCallback;

  /// Status reported synchronously on `subscribe`; tests set it before the
  /// coordinator subscribes to simulate a first-attempt failure.
  RealtimeSubscribeStatus statusToReport = RealtimeSubscribeStatus.subscribed;

  /// Times `subscribe` was called on this channel instance.
  int subscribeCount = 0;

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload payload) callback,
  }) {
    if (table == 'sync_signals') {
      syncSignalsCallback = callback;
    }
    return this;
  }

  @override
  RealtimeChannel subscribe([void Function(RealtimeSubscribeStatus status, Object? error)? callback, Duration? timeout]) {
    subscribeCount++;
    statusCallback = callback;
    callback?.call(statusToReport, null);
    return this;
  }

  /// Drives a later status through the stored callback (a failed join that
  /// reports after the initial `subscribed`, or any subsequent transition).
  void emitStatus(RealtimeSubscribeStatus status) {
    statusToReport = status;
    statusCallback?.call(status, null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controllable one-shot timer factory for retry tests (issue #98, AC5):
/// records every requested delay and keeps the pending timers so tests can
/// fire them on demand instead of waiting on real time.
class FakeRetryTimerFactory {
  final List<Duration> delays = [];
  final List<FakeRetryTimer> timers = [];

  Timer call(Duration delay, void Function() callback) {
    delays.add(delay);
    final timer = FakeRetryTimer(callback);
    timers.add(timer);
    return timer;
  }

  List<FakeRetryTimer> get pending =>
      timers.where((t) => !t.cancelled && t.isActive).toList();

  void fireNext() {
    final next = pending.first;
    next.fire();
  }
}

class FakeRetryTimer implements Timer {
  FakeRetryTimer(this._callback);

  final void Function() _callback;
  bool cancelled = false;
  @override
  bool isActive = true;

  @override
  void cancel() {
    cancelled = true;
    isActive = false;
  }

  void fire() {
    if (cancelled || !isActive) return;
    isActive = false;
    _callback();
  }

  @override
  int get tick => 0;
}

class FakeSupabaseClient implements SupabaseClient {
  final Map<String, FakeRealtimeChannel> createdChannels = {};
  final List<RealtimeChannel> removedChannels = [];

  /// Times `channel(topic)` was called per topic name — a re-subscribe
  /// creates a new channel instance (overwriting `createdChannels`), so
  /// per-instance `subscribeCount` alone cannot prove a retry happened.
  final Map<String, int> channelCalls = {};

  /// Status the *next* created channel reports synchronously on subscribe.
  RealtimeSubscribeStatus nextStatus = RealtimeSubscribeStatus.subscribed;

  @override
  RealtimeChannel channel(String topic, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    channelCalls[topic] = (channelCalls[topic] ?? 0) + 1;
    final ch = FakeRealtimeChannel(topic)..statusToReport = nextStatus;
    createdChannels[topic] = ch;
    return ch;
  }

  @override
  Future<String> removeChannel(RealtimeChannel channel) async {
    removedChannels.add(channel);
    if (channel is FakeRealtimeChannel) {
      createdChannels.remove(channel.topic);
    }
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LunarLogDatabase db;
  late LunarLogStorage storage;
  late FakeSyncEngine syncEngine;
  late FakeSupabaseClient client;
  late RealtimeSyncCoordinator coordinator;

  setUp(() {
    db = LunarLogDatabase(NativeDatabase.memory());
    storage = LunarLogStorage(db);
    syncEngine = FakeSyncEngine();
    client = FakeSupabaseClient();
    coordinator = RealtimeSyncCoordinator(
      client: client,
      syncEngine: syncEngine,
      storage: storage,
      debounceDuration: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await coordinator.dispose();
    await db.close();
  });

  test('subscribes to channels for newly created profiles', () async {
    coordinator.start();

    // Create a profile
    final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.createdChannels.containsKey('profile:${p1.id}'), isTrue);

    // Create a second profile
    final p2 = await storage.upsertProfile(displayName: 'Child 2', isMinor: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.createdChannels.containsKey('profile:${p2.id}'), isTrue);
  });

  test('incoming remote change debounces and triggers syncEngine.requestSync()', () async {
    coordinator.start();

    final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final ch = client.createdChannels['profile:${p1.id}']!;
    expect(ch.syncSignalsCallback, isNotNull);

    final now = DateTime.utc(2026, 9, 4, 12);

    // Simulate 3 rapid changes
    ch.syncSignalsCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'sync_signals',
      commitTimestamp: now,
      errors: [],
    ));
    ch.syncSignalsCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'sync_signals',
      commitTimestamp: now.add(const Duration(seconds: 1)),
      errors: [],
    ));
    ch.syncSignalsCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'sync_signals',
      commitTimestamp: now.add(const Duration(seconds: 2)),
      errors: [],
    ));

    // Debounce is 50ms, so right now 0 requests
    expect(syncEngine.syncRequestCount, 0);

    // After waiting debounce duration
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(syncEngine.syncRequestCount, 1);
  });

  test('disposing coordinator removes all channels', () async {
    coordinator.start();

    await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(client.createdChannels, hasLength(1));

    await coordinator.dispose();
    expect(client.removedChannels, hasLength(1));
  });

  group('sign-in identity rebuild (issue #77 U3; KTD3, R4)', () {
    late FakeAuthService auth;
    late RealtimeSyncCoordinator authCoordinator;

    setUp(() {
      auth = FakeAuthService();
      authCoordinator = RealtimeSyncCoordinator(
        client: client,
        syncEngine: syncEngine,
        storage: storage,
        auth: auth,
        debounceDuration: const Duration(milliseconds: 50),
      );
    });

    tearDown(() async {
      await authCoordinator.dispose();
      await auth.dispose();
    });

    test(
        'a device that opened its database signed out gets live channels '
        'after sign-in, without a restart', () async {
      authCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.createdChannels, hasLength(1));
      expect(client.removedChannels, isEmpty);

      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await Future<void>.delayed(Duration.zero);

      expect(client.removedChannels, hasLength(1),
          reason: 'the pre-sign-in channel is torn down');
      expect(client.createdChannels.containsKey('profile:${p1.id}'), isTrue,
          reason: 'and re-created under the signed-in identity');
    });

    test('a second session event for the same user id does not churn channels',
        () async {
      authCoordinator.start();
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final removedBefore = client.removedChannels.length;

      // A token refresh re-emits the same signed-in state for the same user.
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await Future<void>.delayed(Duration.zero);

      expect(client.removedChannels.length, removedBefore,
          reason: 'no churn when the identity is unchanged');
    });

    test('sign-out removes all channels', () async {
      authCoordinator.start();
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.createdChannels, hasLength(1));

      await auth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(client.createdChannels, isEmpty);
    });

    test(
        'sign-in as a different user id rebuilds channels for the current '
        'local profile set', () async {
      authCoordinator.start();
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.createdChannels, hasLength(1));

      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-b'));
      await Future<void>.delayed(Duration.zero);

      expect(client.createdChannels.containsKey('profile:${p1.id}'), isTrue,
          reason: 'the same local profile set is re-subscribed under the '
              'new identity');
    });

    test('dispose after a sign-in rebuild leaves no channel and no pending '
        'debounce timer', () async {
      authCoordinator.start();
      await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await Future<void>.delayed(Duration.zero);

      final ch = client.createdChannels.values.first;
      ch.syncSignalsCallback!(PostgresChangePayload(
        eventType: PostgresChangeEvent.all,
        newRecord: {},
        oldRecord: {},
        schema: 'public',
        table: 'sync_signals',
        commitTimestamp: DateTime.utc(2026, 9, 5),
        errors: [],
      ));

      await authCoordinator.dispose();

      expect(client.createdChannels, isEmpty);
      // A leaked debounce timer would fail this test's own tearDown/pending
      // timer check by keeping the test's async zone alive.
    });

    test(
        'an auth event that arrives after dispose is a no-op: no rebuild, '
        'no channel churn', () async {
      authCoordinator.start();
      await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await authCoordinator.dispose();
      expect(client.createdChannels, isEmpty);
      final removedBefore = client.removedChannels.length;

      // The auth stream's subscription cancellation in dispose() is
      // deliberately fire-and-forget, so a late in-flight event on it is a
      // real scenario, not a hypothetical -- this proves the `_disposed`
      // guard, not the cancellation, is what makes it safe.
      auth.emit(AuthSessionState.signedIn, user: const AuthUser(id: 'guardian-a'));
      await Future<void>.delayed(Duration.zero);

      expect(client.createdChannels, isEmpty);
      expect(client.removedChannels.length, removedBefore);
    });

    test('constructing the coordinator without an auth source behaves '
        'exactly as today', () async {
      final noAuthCoordinator = RealtimeSyncCoordinator(
        client: client,
        syncEngine: syncEngine,
        storage: storage,
        debounceDuration: const Duration(milliseconds: 50),
      );
      addTearDown(noAuthCoordinator.dispose);

      noAuthCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(client.createdChannels.containsKey('profile:${p1.id}'), isTrue);
    });
  });

  group('subscription status and retry (issue #98)', () {
    late FakeRetryTimerFactory retries;
    late RealtimeSyncCoordinator retryCoordinator;

    setUp(() {
      retries = FakeRetryTimerFactory();
      retryCoordinator = RealtimeSyncCoordinator(
        client: client,
        syncEngine: syncEngine,
        storage: storage,
        debounceDuration: const Duration(milliseconds: 50),
        retryTimerFactory: retries.call,
      );
    });

    tearDown(() async {
      await retryCoordinator.dispose();
    });

    test('a successful subscribe records the subscribed status', () async {
      retryCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(retryCoordinator.channelStatuses[p1.id],
          RealtimeSubscribeStatus.subscribed);
      expect(retryCoordinator.isLive, isTrue);
      expect(retries.timers, isEmpty,
          reason: 'no retry scheduled after success');
    });

    test('each terminal status schedules a retry that re-subscribes',
        () async {
      for (final terminal in const [
        RealtimeSubscribeStatus.channelError,
        RealtimeSubscribeStatus.timedOut,
        RealtimeSubscribeStatus.closed,
      ]) {
        // Fresh database state per status: dispose and rebuild.
        await retryCoordinator.dispose();
        await db.close();
        db = LunarLogDatabase(NativeDatabase.memory());
        storage = LunarLogStorage(db);
        retries = FakeRetryTimerFactory();
        retryCoordinator = RealtimeSyncCoordinator(
          client: client,
          syncEngine: syncEngine,
          storage: storage,
          debounceDuration: const Duration(milliseconds: 50),
          retryTimerFactory: retries.call,
        );
        client.createdChannels.clear();
        client.channelCalls.clear();
        client.removedChannels.clear();

        retryCoordinator.start();
        final profile =
            await storage.upsertProfile(displayName: 'Child', isMinor: true);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final topic = 'profile:${profile.id}';

        client.createdChannels[topic]!.emitStatus(terminal);
        expect(retryCoordinator.channelStatuses[profile.id], terminal);
        expect(retryCoordinator.isLive, isFalse);
        expect(retries.pending, hasLength(1),
            reason: '$terminal schedules exactly one retry');

        client.nextStatus = RealtimeSubscribeStatus.subscribed;
        retries.fireNext();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(client.channelCalls[topic], 2,
            reason: '$terminal retry re-subscribes');
        expect(retryCoordinator.channelStatuses[profile.id],
            RealtimeSubscribeStatus.subscribed);
        expect(retryCoordinator.isLive, isTrue);
        expect(retries.pending, isEmpty);
      }
    });

    test('retries back off with a cap and stop after success', () async {
      retryCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final topic = 'profile:${p1.id}';

      // Fail three times in a row, keeping each replacement failing too:
      // the first failure is driven explicitly, then each fired retry
      // re-subscribes onto a channel that reports channelError synchronously
      // (via client.nextStatus), scheduling the next attempt by itself.
      client.nextStatus = RealtimeSubscribeStatus.channelError;
      client.createdChannels[topic]!
          .emitStatus(RealtimeSubscribeStatus.channelError);
      expect(retries.pending, hasLength(1));
      retries.fireNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(retries.pending, hasLength(1));
      retries.fireNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(retries.delays, hasLength(3));
      expect(retries.delays[0], kRealtimeRetryBase);
      expect(retries.delays[1], kRealtimeRetryBase * 2);
      expect(retries.delays[2], kRealtimeRetryBase * 4);
      expect(
        retries.delays.every((d) => d <= kRealtimeRetryCap),
        isTrue,
        reason: 'backoff never exceeds the cap',
      );

      // A success clears the backoff: the next failure starts over at base.
      client.nextStatus = RealtimeSubscribeStatus.subscribed;
      retries.fireNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(retryCoordinator.channelStatuses[p1.id],
          RealtimeSubscribeStatus.subscribed);
      expect(retries.pending, isEmpty);

      client.createdChannels[topic]!
          .emitStatus(RealtimeSubscribeStatus.timedOut);
      expect(retries.delays.last, kRealtimeRetryBase,
          reason: 'attempt counter resets after a success');
    });

    test('dispose cancels a pending retry: no re-subscribe after', () async {
      retryCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final topic = 'profile:${p1.id}';

      client.createdChannels[topic]!
          .emitStatus(RealtimeSubscribeStatus.closed);
      expect(retries.pending, hasLength(1));
      final callsBefore = client.channelCalls[topic];

      await retryCoordinator.dispose();
      expect(retries.pending, isEmpty,
          reason: 'dispose cancels the pending retry timer');

      // Firing the (now-cancelled) timer must not re-subscribe.
      for (final timer in retries.timers) {
        timer.fire();
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.channelCalls[topic], callsBefore);
    });

    test('a rebuilt channel after sign-in reports failures with retries',
        () async {
      final auth = FakeAuthService();
      addTearDown(auth.dispose);
      final authRetryCoordinator = RealtimeSyncCoordinator(
        client: client,
        syncEngine: syncEngine,
        storage: storage,
        auth: auth,
        debounceDuration: const Duration(milliseconds: 50),
        retryTimerFactory: retries.call,
      );
      addTearDown(authRetryCoordinator.dispose);

      authRetryCoordinator.start();
      final p1 = await storage.upsertProfile(displayName: 'Child 1', isMinor: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final topic = 'profile:${p1.id}';

      // Rebuild under a new identity, then fail the rebuilt channel.
      client.nextStatus = RealtimeSubscribeStatus.subscribed;
      auth.emit(AuthSessionState.signedIn,
          user: const AuthUser(id: 'guardian-a'));
      await Future<void>.delayed(Duration.zero);
      expect(client.createdChannels.containsKey(topic), isTrue);

      client.createdChannels[topic]!
          .emitStatus(RealtimeSubscribeStatus.channelError);
      expect(retries.pending, hasLength(1),
          reason: 'a rebuilt channel failure is also retried');

      final callsBefore = client.channelCalls[topic];
      retries.fireNext();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(client.channelCalls[topic], (callsBefore ?? 1) + 1);
    });
  });
}
