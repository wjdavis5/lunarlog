/// U10 (KTD2, KTD3): [SupabaseSyncTransport] over a real `SupabaseClient`
/// whose HTTP layer is a `MockClient`, so the tests pin the actual request
/// paths, bodies and query strings PostgREST will see, plus the mapping of
/// every failure class to a typed [SyncTransportError] that carries no
/// provider text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/db/tables.dart';
import 'package:lunarlog/data/sync/remote_rows.dart';
import 'package:lunarlog/data/sync/supabase_sync_transport.dart';
import 'package:lunarlog/data/sync/sync_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const baseUrl = 'https://example.supabase.co';
const profileId = '01J0000000000000000000000A';
const entryId = '01J0000000000000000000000B';

Map<String, Object?> profileJson({int version = 1}) => {
      'id': profileId,
      'user_id': '00000000-0000-0000-0000-000000000000',
      'display_name': 'Kid',
      'is_minor': true,
      'sort_order': 0,
      'archived_at': null,
      'created_at': '2026-09-01T10:00:00.123+00:00',
      'updated_at': '2026-09-01T10:00:00.123+00:00',
      'deleted_at': null,
      'server_version': version,
    };

Map<String, Object?> entryJson({int version = 2, String flow = 'light'}) => {
      'id': entryId,
      'user_id': '00000000-0000-0000-0000-000000000000',
      'profile_id': profileId,
      'local_date': '2026-09-01',
      'tz': 'UTC',
      'flow': flow,
      'tags': ['cramps'],
      'note': null,
      'created_at': '2026-09-01T10:00:00+00:00',
      'updated_at': '2026-09-01T10:00:00.5+00:00',
      'deleted_at': null,
      'server_version': version,
    };

http.Response json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

typedef Handler = Future<http.Response> Function(http.Request request);

void main() {
  late List<http.Request> requests;
  SupabaseClient? client;

  /// A client whose every request goes to [handler]; retries and token
  /// refresh are off so failures surface immediately. The response is
  /// re-issued with its `request` attached, as a real client would.
  SupabaseClient makeClient(Handler handler) => SupabaseClient(
        baseUrl,
        'anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final response = await handler(request);
          return http.Response(
            response.body,
            response.statusCode,
            headers: response.headers,
            reasonPhrase: response.reasonPhrase,
            request: request,
          );
        }),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );

  setUp(() {
    requests = [];
  });

  tearDown(() async {
    await client?.dispose();
    client = null;
  });

  group('push', () {
    test('POSTs the batch to /rpc/sync_push and decodes the result', () async {
      client = makeClient((_) async => json({
            'resolved': [
              {...profileJson(version: 7), 'table': 'profiles'},
              {...entryJson(version: 8), 'table': 'day_entries'},
            ],
            'rejected': [
              {'id': '01J0000000000000000000000C', 'rejected': true},
              {'id': null, 'rejected': true},
            ],
            'server_now': '2026-09-02T12:00:00.654321+00:00',
          }));
      final transport = SupabaseSyncTransport(client!);
      final batch = PushBatch(
        profiles: [
          {'id': profileId, 'display_name': 'Kid', 'updated_at': 'x'}
        ],
        dayEntries: [
          {'id': entryId, 'profile_id': profileId}
        ],
      );

      final result = await transport.push(batch);

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'POST');
      expect(request.url.toString(), '$baseUrl/rest/v1/rpc/sync_push');
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(request.headers['apikey'], 'anon-key');
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(jsonDecode(request.body), {
        'p_profiles': [
          {'id': profileId, 'display_name': 'Kid', 'updated_at': 'x'}
        ],
        'p_day_entries': [
          {'id': entryId, 'profile_id': profileId}
        ],
      });

      expect(result.resolved, hasLength(2));
      final p = result.resolved[0] as RemoteProfileRow;
      expect(p.id, profileId);
      expect(p.serverVersion, 7);
      expect(p.updatedAt, DateTime.parse('2026-09-01T10:00:00.123000Z'));
      final d = result.resolved[1] as RemoteDayEntryRow;
      expect(d.id, entryId);
      expect(d.flow, FlowLevel.light);
      expect(d.serverVersion, 8);
      expect(result.rejectedIds, ['01J0000000000000000000000C']);
      expect(result.serverNow, DateTime.utc(2026, 9, 2, 12, 0, 0, 654, 321));
      expect(result.serverNow.isUtc, isTrue);
    });

    test('an empty batch is still a valid round-trip', () async {
      client = makeClient((_) async => json({
            'resolved': [],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      final result = await SupabaseSyncTransport(client!).push(PushBatch());
      expect(result.resolved, isEmpty);
      expect(result.rejectedIds, isEmpty);
      expect(jsonDecode(requests.single.body),
          {'p_profiles': [], 'p_day_entries': []});
    });

    test('sends at most 500 rows per array', () async {
      client = makeClient((_) async => json({
            'resolved': [],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      final rows = List.generate(500, (i) => <String, Object?>{'id': '$i'});
      final batch = PushBatch(profiles: rows, dayEntries: rows);
      expect(batch.rowCount, 1000);
      await SupabaseSyncTransport(client!).push(batch);
      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body['p_profiles'], hasLength(500));
      expect(body['p_day_entries'], hasLength(500));

      final tooMany = List.generate(501, (i) => <String, Object?>{'id': '$i'});
      expect(() => PushBatch(profiles: tooMany), throwsArgumentError);
      expect(() => PushBatch(dayEntries: tooMany), throwsArgumentError);
      expect(PushBatch.maxRows, 500);
    });

    test('a malformed resolved row is `other`, never a codec exception',
        () async {
      client = makeClient((_) async => json({
            'resolved': [
              {...entryJson(flow: 'torrential'), 'table': 'day_entries'},
            ],
            'rejected': [],
            'server_now': '2026-09-02T12:00:00+00:00',
          }));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });

    test('a response that is not the RPC shape is `other`', () async {
      client = makeClient((_) async => json([1, 2, 3]));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });
  });

  group('pullPage', () {
    test('GETs the table with after_version, order and limit', () async {
      client = makeClient((_) async => json([
            profileJson(version: 43),
            profileJson(version: 44),
          ]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profiles,
        afterVersion: 42,
        limit: 500,
      );

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/rest/v1/profiles');
      expect(request.url.queryParameters, {
        'select': '*',
        'server_version': 'gt.42',
        // postgrest appends the default null ordering; the column is NOT
        // NULL so it never applies.
        'order': 'server_version.asc.nullslast',
        'limit': '500',
      });
      expect(request.headers['Authorization'], 'Bearer anon-key');
      expect(rows, hasLength(2));
      expect(rows.every((r) => r is RemoteProfileRow), isTrue);
      expect(rows.map((r) => r.serverVersion), [43, 44]);
    });

    test('day entries use the day_entries table', () async {
      client = makeClient((_) async => json([entryJson(version: 9)]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.dayEntries,
        afterVersion: 0,
        limit: 100,
      );
      final request = requests.single;
      expect(request.url.path, '/rest/v1/day_entries');
      expect(request.url.queryParameters['server_version'], 'gt.0');
      expect(request.url.queryParameters['limit'], '100');
      final row = rows.single as RemoteDayEntryRow;
      expect(row.id, entryId);
      expect(row.tags, ['cramps']);
      expect(row.serverVersion, 9);
      expect(row.updatedAt, DateTime.utc(2026, 9, 1, 10, 0, 0, 500));
    });

    test('an empty page decodes to an empty list', () async {
      client = makeClient((_) async => json([]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.profiles,
        afterVersion: 10,
        limit: 500,
      );
      expect(rows, isEmpty);
    });

    test('rejects a non-positive limit before any request', () async {
      client = makeClient((_) async => json([]));
      expect(
        () => SupabaseSyncTransport(client!).pullPage(
          table: SyncTable.profiles,
          afterVersion: 0,
          limit: 0,
        ),
        throwsArgumentError,
      );
      expect(requests, isEmpty);
    });

    test('a malformed row is quarantined so the pull cursor can advance (Issue #40)', () async {
      client = makeClient((_) async => json([
            {...entryJson(version: 45), 'tags': [1, 2]},
            entryJson(version: 46),
          ]));
      final rows = await SupabaseSyncTransport(client!).pullPage(
        table: SyncTable.dayEntries,
        afterVersion: 0,
        limit: 500,
      );
      expect(rows, hasLength(2));
      final quarantined = rows.first as QuarantinedRemoteRow;
      expect(quarantined.serverVersion, 45);
      expect(quarantined.id, entryId);
      expect(quarantined.table, SyncTable.dayEntries);
      expect(quarantined.reason, contains('invalidTags'));

      final valid = rows.last as RemoteDayEntryRow;
      expect(valid.serverVersion, 46);
      expect(valid.tags, ['cramps']);
    });
  });

  group('error mapping over HTTP', () {
    test('401 maps to auth on push and pull', () async {
      client = makeClient((_) async => json(
            {'message': 'JWT expired', 'code': 'PGRST301'},
            status: 401,
          ));
      final transport = SupabaseSyncTransport(client!);
      expect(
        () => transport.push(PushBatch()),
        throwsA(isA<SyncTransportAuthError>()),
      );
      expect(
        () => transport.pullPage(
            table: SyncTable.profiles, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportAuthError>()),
      );
    });

    test('AuthException maps to auth', () async {
      client = makeClient((_) async => throw const AuthException('refresh'));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportAuthError>()),
      );
    });

    test('5xx maps to network', () async {
      client = makeClient(
          (_) async => http.Response('<html>bad gateway</html>', 502));
      final transport = SupabaseSyncTransport(client!);
      expect(
        () => transport.push(PushBatch()),
        throwsA(isA<SyncTransportNetworkError>()),
      );
      expect(
        () => transport.pullPage(
            table: SyncTable.dayEntries, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportNetworkError>()),
      );
    });

    test('socket and client exceptions map to network', () async {
      client = makeClient((_) async => throw const SocketException('down'));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportNetworkError>()),
      );
      await client!.dispose();

      client = makeClient(
          (_) async => throw http.ClientException('connection closed'));
      expect(
        () => SupabaseSyncTransport(client!).pullPage(
            table: SyncTable.profiles, afterVersion: 0, limit: 10),
        throwsA(isA<SyncTransportNetworkError>()),
      );
    });

    test('a 400 with the batch-size SQLSTATE is `other`', () async {
      client = makeClient((_) async => json(
            {'message': 'p_profiles exceeds 500 rows', 'code': '22023'},
            status: 400,
          ));
      expect(
        () => SupabaseSyncTransport(client!).push(PushBatch()),
        throwsA(isA<SyncTransportOtherError>()),
      );
    });

    test('typed errors never expose provider text', () async {
      client = makeClient((_) async => json(
            {'message': 'secret provider detail', 'code': 'PGRST301'},
            status: 401,
          ));
      try {
        await SupabaseSyncTransport(client!).push(PushBatch());
        fail('expected a transport error');
      } on SyncTransportError catch (e) {
        expect(e.toString(), isNot(contains('secret')));
        expect(e.toString(), isNot(contains('PGRST')));
      }
    });
  });

  group('mapSyncTransportError', () {
    test('classifies every known failure', () {
      expect(
          mapSyncTransportError(AuthRetryableFetchException()),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(const AuthException('x')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '401')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '403')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: 'PGRST303')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '42501')),
          isA<SyncTransportAuthError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '500')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '503')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '429')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(const SocketException('x')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(TimeoutException('x')),
          isA<SyncTransportNetworkError>());
      expect(mapSyncTransportError(http.ClientException('x')),
          isA<SyncTransportNetworkError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '22023')),
          isA<SyncTransportOtherError>());
      expect(
          mapSyncTransportError(
              const PostgrestException(message: 'x', code: '400')),
          isA<SyncTransportOtherError>());
      expect(mapSyncTransportError(StateError('x')),
          isA<SyncTransportOtherError>());
    });

    test('an already-typed error passes through unchanged', () {
      const rejected = SyncTransportError.rejected(['a']);
      expect(identical(mapSyncTransportError(rejected), rejected), isTrue);
    });
  });

  group('SyncTransportError', () {
    test('fieldless kinds are value-equal; rejected carries only ids', () {
      expect(const SyncTransportError.auth(), const SyncTransportError.auth());
      expect(const SyncTransportError.network(),
          isNot(const SyncTransportError.other()));
      const rejected = SyncTransportError.rejected(['a', 'b']);
      expect(rejected, const SyncTransportError.rejected(['a', 'b']));
      expect((rejected as SyncTransportRejectedError).ids, ['a', 'b']);
      expect(rejected.toString(), contains('2'));
    });
  });
}
