/// Unit tests for [SupabaseAccountExportRemoteSource] (Issue #248), mirroring
/// the mocked-`SupabaseClient` pattern already proven in
/// `test/data/notifications/supabase_push_device_registry_test.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/export/supabase_account_export_remote_source.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '01JABCDEF01234567890123456';

Future<void> _signIn(SupabaseClient client) async {
  await client.auth.recoverSession(jsonEncode({
    'access_token': 'test-access-token',
    'token_type': 'bearer',
    'user': {
      'id': _uid,
      'aud': 'authenticated',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-09-05T00:00:00.000Z',
    },
  }));
}

void main() {
  SupabaseClient makeClient(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        final res = await handler(request);
        return http.Response(
          res.body,
          res.statusCode,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            ...res.headers,
          },
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
  }

  group('fetchServerExport', () {
    test('a signed-out client makes no network call and returns null',
        () async {
      final client = makeClient((req) async {
        fail('a signed-out fetchServerExport must never reach the network');
      });
      final source = SupabaseAccountExportRemoteSource(client: client);

      final result = await source.fetchServerExport();

      expect(result, isNull);
    });

    test('calls export_account_data and returns its decoded document',
        () async {
      final serverDoc = <String, Object?>{
        'schema_version': 1,
        'profiles': <Object?>[],
      };
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/rpc/export_account_data');
        return http.Response(jsonEncode(serverDoc), 200);
      });
      await _signIn(client);
      final source = SupabaseAccountExportRemoteSource(client: client);

      final result = await source.fetchServerExport();

      expect(result, serverDoc);
    });

    test('a server error (e.g. the RPC refusing the caller) is swallowed '
        'into null rather than thrown', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'code': '42501', 'message': 'insufficient_privilege'}),
          403,
        );
      });
      await _signIn(client);
      final source = SupabaseAccountExportRemoteSource(client: client);

      final result = await source.fetchServerExport();

      expect(result, isNull);
    });

    test('a non-object response body (unexpected shape) resolves to null',
        () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode('not-an-object'), 200);
      });
      await _signIn(client);
      final source = SupabaseAccountExportRemoteSource(client: client);

      final result = await source.fetchServerExport();

      expect(result, isNull);
    });

    test('a network failure is swallowed into null rather than thrown',
        () async {
      final client = makeClient((req) async {
        throw const SocketException('no route to host');
      });
      await _signIn(client);
      final source = SupabaseAccountExportRemoteSource(client: client);

      final result = await source.fetchServerExport();

      expect(result, isNull);
    });
  });
}
