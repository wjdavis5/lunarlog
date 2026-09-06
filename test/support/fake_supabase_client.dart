/// A minimal in-memory [SupabaseClient] double for wiring tests that need a
/// real client *instance* to flow through production constructors
/// ([SupabaseSharingService], [SupabaseAccountDeletionService],
/// `RealtimeSyncCoordinator`) without touching the network. Mirrors the fake
/// already proven in `test/data/sync/realtime_sync_coordinator_test.dart`:
/// every unused member falls through `noSuchMethod`, so only the members a
/// production constructor actually calls are implemented.
library;

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signature of [FakeFunctionsClient.invoke]'s backing callback (#17 U4).
typedef FakeFunctionsInvoke = Future<FunctionResponse> Function(
  String functionName, {
  Map<String, String>? headers,
  Object? body,
});

/// [FunctionsClient] double: every call is recorded and answered by an
/// injected callback, so a test can return a canned [FunctionResponse] or
/// throw a [FunctionException] without any network I/O (#17 U4, for
/// `SupabaseAccountDeletionService`).
class FakeFunctionsClient implements FunctionsClient {
  FakeFunctionsClient(this._invoke);

  final FakeFunctionsInvoke _invoke;

  final List<String> invokedFunctionNames = [];
  final List<Object?> invokedBodies = [];

  @override
  Future<FunctionResponse> invoke(
    String functionName, {
    Map<String, String>? headers,
    Object? body,
    Iterable<http.MultipartFile>? files,
    Map<String, dynamic>? queryParameters,
    HttpMethod method = HttpMethod.post,
    String? region,
    Future<void>? abortSignal,
  }) {
    invokedFunctionNames.add(functionName);
    invokedBodies.add(body);
    return _invoke(functionName, headers: headers, body: body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRealtimeChannel implements RealtimeChannel {
  FakeRealtimeChannel(this.topic);

  @override
  final String topic;

  /// How many times [subscribe] was actually called on this channel (PR #92
  /// review round 2, carried over from round 1): nothing in the test suite
  /// previously asserted this, so deleting the production `.subscribe()`
  /// call in `RealtimeSyncCoordinator` would still leave every test green —
  /// a channel is created and torn down correctly either way, and only
  /// `subscribeCalls` distinguishes "actually subscribed" from "just built
  /// the channel object". See the gate_test.dart assertion that reads this.
  int subscribeCalls = 0;

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload payload) callback,
  }) =>
      this;

  @override
  RealtimeChannel subscribe(
      [void Function(RealtimeSubscribeStatus status, Object? error)? callback,
      Duration? timeout]) {
    subscribeCalls++;
    callback?.call(RealtimeSubscribeStatus.subscribed, null);
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSupabaseClient implements SupabaseClient {
  FakeSupabaseClient({FakeFunctionsInvoke? functionsInvoke})
      : functions = FakeFunctionsClient(
          functionsInvoke ??
              (name, {headers, body}) async =>
                  const FunctionResponse(data: <String, Object?>{'ok': true}, status: 200),
        );

  final Map<String, FakeRealtimeChannel> createdChannels = {};
  final List<RealtimeChannel> removedChannels = [];

  @override
  final FakeFunctionsClient functions;

  @override
  RealtimeChannel channel(String topic,
      {RealtimeChannelConfig opts = const RealtimeChannelConfig()}) {
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
