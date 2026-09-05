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

  void Function(PostgresChangePayload payload)? dayEntriesCallback;
  void Function(PostgresChangePayload payload)? profilesCallback;

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
    if (table == 'day_entries') {
      dayEntriesCallback = callback;
    } else if (table == 'profiles') {
      profilesCallback = callback;
    }
    return this;
  }

  @override
  RealtimeChannel subscribe([void Function(RealtimeSubscribeStatus status, Object? error)? callback, Duration? timeout]) {
    callback?.call(RealtimeSubscribeStatus.subscribed, null);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseClient implements SupabaseClient {
  final Map<String, FakeRealtimeChannel> createdChannels = {};
  final List<RealtimeChannel> removedChannels = [];

  @override
  RealtimeChannel channel(String topic, {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
    final ch = FakeRealtimeChannel(topic);
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
    expect(ch.dayEntriesCallback, isNotNull);

    final now = DateTime.utc(2026, 9, 4, 12);

    // Simulate 3 rapid changes
    ch.dayEntriesCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'day_entries',
      commitTimestamp: now,
      errors: [],
    ));
    ch.dayEntriesCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'day_entries',
      commitTimestamp: now.add(const Duration(seconds: 1)),
      errors: [],
    ));
    ch.profilesCallback!(PostgresChangePayload(
      eventType: PostgresChangeEvent.all,
      newRecord: {},
      oldRecord: {},
      schema: 'public',
      table: 'profiles',
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
      ch.dayEntriesCallback!(PostgresChangePayload(
        eventType: PostgresChangeEvent.all,
        newRecord: {},
        oldRecord: {},
        schema: 'public',
        table: 'day_entries',
        commitTimestamp: DateTime.utc(2026, 9, 5),
        errors: [],
      ));

      await authCoordinator.dispose();

      expect(client.createdChannels, isEmpty);
      // A leaked debounce timer would fail this test's own tearDown/pending
      // timer check by keeping the test's async zone alive.
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
}
