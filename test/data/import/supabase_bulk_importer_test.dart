/// Issue #167: [SupabaseBulkImporter] over a real `SupabaseClient` whose
/// HTTP layer is a `MockClient`, mirroring
/// `test/data/supabase_sync_transport_test.dart`'s pattern — the tests pin
/// the actual request paths/bodies PostgREST will see, plus the mapping of
/// every failure class to a typed [BulkImportError] that carries no
/// provider text.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/import/supabase_bulk_importer.dart';
import 'package:lunarlog/domain/import/bulk_importer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const baseUrl = 'https://example.supabase.co';
const profileId = '01J0000000000000000000000A';
const testUid = '00000000-0000-0000-0000-0000000000aa';
const jobId = '11111111-1111-1111-1111-111111111111';

http.Response json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

http.Response empty({int status = 204}) => http.Response('', status);

BulkImportRow row(int n, {String? sourceId}) => BulkImportRow(
      id: '01J000000000000000000${n.toString().padLeft(4, '0')}',
      profileId: profileId,
      localDate: '2015-01-01',
      sourceId: sourceId ?? 'src-$n',
      updatedAt: DateTime.utc(2026, 9, 9),
    );

/// A base64url JWT-shaped string (header.payload.signature) whose payload
/// decodes to `{sub, exp, iat}` — enough for `GoTrueClient.recoverSession`
/// to accept it as a live, non-expired session with **no** network call
/// (it only hits `/token` when the decoded `exp` has already passed), so
/// `_client.auth.currentUser?.id` resolves to [sub] purely locally.
String _fakeJwt({required String sub, required DateTime exp}) {
  String segment(Map<String, Object?> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  final header = segment({'alg': 'HS256', 'typ': 'JWT'});
  final payload = segment({
    'sub': sub,
    'exp': exp.millisecondsSinceEpoch ~/ 1000,
    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  });
  return '$header.$payload.fake-signature';
}

Future<void> signIn(SupabaseClient client, String uid) async {
  final jwt = _fakeJwt(sub: uid, exp: DateTime.now().add(const Duration(hours: 1)));
  await client.auth.recoverSession(jsonEncode({
    'access_token': jwt,
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'a-refresh-token',
    'user': {
      'id': uid,
      'aud': 'authenticated',
      'app_metadata': <String, Object?>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  }));
}

typedef Handler = Future<http.Response> Function(http.Request request);

void main() {
  late List<http.Request> requests;
  SupabaseClient? client;

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

  group('importEntries', () {
    test('creates the job, chunks >2000 rows, and reports progress',
        () async {
      var rpcCalls = 0;
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        if (request.url.path == '/rest/v1/rpc/bulk_import_entries') {
          rpcCalls++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final rows = body['p_rows'] as List;
          return json({
            'inserted': rows.length,
            'updated': 0,
            'revived': 0,
            'rejected': rpcCalls == 1
                ? [
                    {'row_index': 3, 'reason': 'flow is not a known level'}
                  ]
                : [],
          });
        }
        return empty();
      });
      await signIn(client!, testUid);
      requests.clear();

      final rows = [for (var i = 0; i < 2001; i++) row(i)];
      final progress = <List<int>>[];
      final result = await SupabaseBulkImporter(client!).importEntries(
        profileId: profileId,
        source: 'clue_import',
        rows: rows,
        onProgress: (processed, total) => progress.add([processed, total]),
      );

      // job creation, a running-status PATCH, then 2 RPC chunks each
      // followed by a processed_rows PATCH, then a final completed PATCH.
      expect(requests, hasLength(7));
      expect(requests[0].method, 'POST');
      expect(requests[0].url.path, '/rest/v1/import_jobs');
      expect(jsonDecode(requests[0].body), {
        'profile_id': profileId,
        'source': 'clue_import',
        'status': 'pending',
        'total_rows': 2001,
        'created_by': testUid,
      });
      expect(requests[0].url.queryParameters['select'], 'id');

      expect(requests[1].method, 'PATCH');
      expect(requests[1].url.path, '/rest/v1/import_jobs');
      expect(requests[1].url.queryParameters['id'], 'eq.$jobId');
      expect(jsonDecode(requests[1].body), {'status': 'running'});

      expect(requests[2].url.path, '/rest/v1/rpc/bulk_import_entries');
      final firstChunk = jsonDecode(requests[2].body) as Map<String, dynamic>;
      expect(firstChunk['p_import_id'], jobId);
      expect((firstChunk['p_rows'] as List), hasLength(kBulkImportMaxRowsPerChunk));

      expect(requests[3].method, 'PATCH');
      expect(requests[3].url.path, '/rest/v1/import_jobs');
      expect(requests[3].url.queryParameters['id'], 'eq.$jobId');
      expect(jsonDecode(requests[3].body), {'processed_rows': kBulkImportMaxRowsPerChunk});

      final secondChunk = jsonDecode(requests[4].body) as Map<String, dynamic>;
      expect((secondChunk['p_rows'] as List), hasLength(1));

      expect(jsonDecode(requests[5].body), {'processed_rows': 2001});

      expect(requests[6].method, 'PATCH');
      expect(jsonDecode(requests[6].body)['status'], 'completed');
      expect(jsonDecode(requests[6].body)['error_kind'], isNull);

      expect(progress, [
        [kBulkImportMaxRowsPerChunk, 2001],
        [2001, 2001],
      ]);
      expect(result.jobId, jobId);
      expect(result.inserted, 2001);
      expect(result.updated, 0);
      expect(result.revived, 0);
      expect(result.written, 2001);
      expect(result.rejected, [
        const BulkImportRejectedRow(rowIndex: 3, reason: 'flow is not a known level'),
      ]);
    });

    test('an empty row list still creates and completes the job', () async {
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        return empty();
      });
      await signIn(client!, testUid);
      requests.clear();

      final result = await SupabaseBulkImporter(client!).importEntries(
        profileId: profileId,
        source: 'manual',
        rows: const [],
      );

      // job creation, the running-status PATCH, then straight to the
      // completed PATCH -- no RPC call.
      expect(requests, hasLength(3));
      expect(requests.any((r) => r.url.path.contains('rpc')), isFalse);
      expect(result.written, 0);
      expect(result.rejected, isEmpty);
    });

    test('no session throws auth before any HTTP call', () async {
      client = makeClient((_) async => json({'id': jobId}));
      await expectLater(
        SupabaseBulkImporter(client!).importEntries(
          profileId: profileId,
          source: 'manual',
          rows: [row(1)],
        ),
        throwsA(const BulkImportError.auth()),
      );
      expect(requests, isEmpty);
    });

    test('a chunk failure marks the job failed with error_kind and rethrows',
        () async {
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        if (request.url.path == '/rest/v1/rpc/bulk_import_entries') {
          return http.Response('<html>bad gateway</html>', 502);
        }
        return empty();
      });
      await signIn(client!, testUid);
      requests.clear();

      await expectLater(
        SupabaseBulkImporter(client!).importEntries(
          profileId: profileId,
          source: 'clue_import',
          rows: [row(1)],
        ),
        throwsA(const BulkImportError.network()),
      );

      expect(requests, hasLength(4));
      expect(requests[3].method, 'PATCH');
      final failedBody = jsonDecode(requests[3].body) as Map<String, dynamic>;
      expect(failedBody['status'], 'failed');
      expect(failedBody['error_kind'], 'network');
      expect(failedBody['completed_at'], isA<String>());
    });

    test('a malformed RPC response marks the job failed as other', () async {
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        if (request.url.path == '/rest/v1/rpc/bulk_import_entries') {
          return json([1, 2, 3]);
        }
        return empty();
      });
      await signIn(client!, testUid);
      requests.clear();

      await expectLater(
        SupabaseBulkImporter(client!).importEntries(
          profileId: profileId,
          source: 'clue_import',
          rows: [row(1)],
        ),
        throwsA(const BulkImportError.other()),
      );
      expect(jsonDecode(requests.last.body)['error_kind'], 'other');
    });

    test('a failure marking the job failed does not mask the real error',
        () async {
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        // Both the chunk RPC and the failed-status PATCH fail.
        return http.Response('down', 503);
      });
      await signIn(client!, testUid);
      requests.clear();

      await expectLater(
        SupabaseBulkImporter(client!).importEntries(
          profileId: profileId,
          source: 'clue_import',
          rows: [row(1)],
        ),
        throwsA(const BulkImportError.network()),
      );
    });

    test(
        'a failed final completed PATCH surfaces a typed failure and '
        'leaves the job running, not failed', () async {
      client = makeClient((request) async {
        if (request.method == 'POST' && request.url.path == '/rest/v1/import_jobs') {
          return json({'id': jobId});
        }
        if (request.url.path == '/rest/v1/rpc/bulk_import_entries') {
          return json({'inserted': 1, 'updated': 0, 'revived': 0, 'rejected': []});
        }
        if (request.method == 'PATCH' && request.url.path == '/rest/v1/import_jobs') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          // The running-status and processed_rows PATCHes succeed; only
          // the final completed PATCH fails.
          if (body['status'] == 'completed') {
            return http.Response('down', 503);
          }
          return empty();
        }
        return empty();
      });
      await signIn(client!, testUid);
      requests.clear();

      // Review fix (round 2, Issue #167): the whole batch's data write
      // already succeeded -- every row is durably in day_entries -- so a
      // failed final status write must surface a typed error without
      // marking the job 'failed' (that would misreport rows that are
      // actually in). The job is left 'running': a later completed PATCH,
      // or a fresh bulk_import_entries re-import of the same rows, is
      // safe either way (re-import is idempotent by (source, source_id)
      // regardless of import_id -- see the migration's review-fix header).
      await expectLater(
        SupabaseBulkImporter(client!).importEntries(
          profileId: profileId,
          source: 'clue_import',
          rows: [row(1)],
        ),
        throwsA(const BulkImportError.network()),
      );

      expect(
        requests.any((r) =>
            r.method == 'PATCH' && jsonDecode(r.body)['status'] == 'failed'),
        isFalse,
        reason: 'the job must never be marked failed when only the '
            'completed PATCH fails',
      );
      final attemptedCompletedPatch = requests.lastWhere((r) =>
          r.method == 'PATCH' && jsonDecode(r.body)['status'] == 'completed');
      expect(attemptedCompletedPatch.method, 'PATCH');
    });
  });

  group('mapBulkImportError', () {
    test('classifies every known failure', () {
      expect(mapBulkImportError(AuthRetryableFetchException()),
          isA<BulkImportNetworkError>());
      expect(mapBulkImportError(const AuthException('x')),
          isA<BulkImportAuthError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '401')),
          isA<BulkImportAuthError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '403')),
          isA<BulkImportAuthError>());
      expect(
          mapBulkImportError(
              const PostgrestException(message: 'x', code: 'PGRST303')),
          isA<BulkImportAuthError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '42501')),
          isA<BulkImportAuthError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '500')),
          isA<BulkImportNetworkError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '503')),
          isA<BulkImportNetworkError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '429')),
          isA<BulkImportNetworkError>());
      expect(mapBulkImportError(const SocketException('x')),
          isA<BulkImportNetworkError>());
      expect(mapBulkImportError(TimeoutException('x')),
          isA<BulkImportNetworkError>());
      expect(mapBulkImportError(http.ClientException('x')),
          isA<BulkImportNetworkError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '22023')),
          isA<BulkImportOtherError>());
      expect(
          mapBulkImportError(const PostgrestException(message: 'x', code: '400')),
          isA<BulkImportOtherError>());
      expect(mapBulkImportError(StateError('x')), isA<BulkImportOtherError>());
    });

    test('an already-typed error passes through unchanged', () {
      const other = BulkImportError.other();
      expect(identical(mapBulkImportError(other), other), isTrue);
    });
  });

  group('BulkImportError', () {
    test('fieldless kinds are value-equal', () {
      expect(const BulkImportError.auth(), const BulkImportError.auth());
      expect(const BulkImportError.network(),
          isNot(const BulkImportError.other()));
      expect(const BulkImportError.auth().toString(), 'BulkImportError.auth');
      expect(const BulkImportError.network().toString(), 'BulkImportError.network');
      expect(const BulkImportError.other().toString(), 'BulkImportError.other');
    });
  });

  group('BulkImportRow', () {
    test('toJson omits absent optional fields but always includes source_id',
        () {
      final r = BulkImportRow(
        id: '01J0000000000000000000000B',
        profileId: profileId,
        localDate: '2020-05-01',
        sourceId: 'clue-1',
        updatedAt: DateTime.utc(2026, 9, 9, 12),
      );
      final j = r.toJson();
      expect(j.containsKey('note'), isFalse);
      expect(j.containsKey('deleted_at'), isFalse);
      // Review fix (Issue #167): source_id is required, not optional --
      // bulk_import_entries rejects a row with neither an existing id
      // match nor a source_id, so it is always present, never omitted.
      expect(j['source_id'], 'clue-1');
      expect(j['tz'], 'UTC');
      expect(j['flow'], 'none');
      expect(j['tags'], <String>[]);
      expect(j['updated_at'], '2026-09-09T12:00:00.000Z');
    });

    test('toJson includes note/deleted_at when present', () {
      final r = BulkImportRow(
        id: '01J0000000000000000000000B',
        profileId: profileId,
        localDate: '2020-05-01',
        note: 'a note',
        sourceId: 'clue-1',
        updatedAt: DateTime.utc(2026, 9, 9),
        deletedAt: DateTime.utc(2026, 9, 10),
      );
      final j = r.toJson();
      expect(j['note'], 'a note');
      expect(j['source_id'], 'clue-1');
      expect(j['deleted_at'], '2026-09-10T00:00:00.000Z');
    });
  });

  group('BulkImportRejectedRow', () {
    test('value-equal and toString carries both fields', () {
      const a = BulkImportRejectedRow(rowIndex: 2, reason: 'bad');
      const b = BulkImportRejectedRow(rowIndex: 2, reason: 'bad');
      const c = BulkImportRejectedRow(rowIndex: 3, reason: 'bad');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('2'));
      expect(a.toString(), contains('bad'));
    });
  });

  group('BulkImportRunResult', () {
    test('written sums inserted/updated/revived', () {
      final result = BulkImportRunResult(
        jobId: jobId,
        inserted: 1,
        updated: 2,
        revived: 3,
        rejected: const [],
      );
      expect(result.written, 6);
      expect(result.toString(), contains('written: 6'));
    });
  });
}
