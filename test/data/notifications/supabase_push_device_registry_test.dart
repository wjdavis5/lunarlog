import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/notifications/supabase_push_device_registry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '01JABCDEF01234567890123456';
const _deviceId = 'device-uuid-1';

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
  SupabaseClient makeClient(Future<http.Response> Function(http.Request) handler) {
    return SupabaseClient(
      'https://example.supabase.co',
      'anon-key',
      httpClient: MockClient((request) async {
        final res = await handler(request);
        return http.Response(
          res.body,
          res.statusCode,
          headers: {'content-type': 'application/json; charset=utf-8', ...res.headers},
          request: request,
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
  }

  group('register', () {
    test('upserts id, user_id, token, and platform', () async {
      Map<String, dynamic>? capturedBody;
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/push_devices');
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 201);
      });
      await _signIn(client);
      final registry = SupabasePushDeviceRegistry(client: client);

      await registry.register(_deviceId, 'token-1', platform: 'ios');

      expect(capturedBody?['id'], _deviceId);
      expect(capturedBody?['user_id'], _uid);
      expect(capturedBody?['token'], 'token-1');
      expect(capturedBody?['platform'], 'ios');
      expect(capturedBody?['disabled_at'], isNull);
    });

    test('a signed-out client makes no network call', () async {
      final client = makeClient((req) async {
        fail('a signed-out register must never reach the network');
      });
      final registry = SupabasePushDeviceRegistry(client: client);

      await registry.register(_deviceId, 'token-1', platform: 'ios');
    });
  });

  group('remove', () {
    test('deletes by id', () async {
      String? capturedPath;
      final client = makeClient((req) async {
        capturedPath = req.url.path;
        expect(req.url.queryParameters['id'], 'eq.$_deviceId');
        return http.Response('', 204);
      });
      await _signIn(client);
      final registry = SupabasePushDeviceRegistry(client: client);

      await registry.remove(_deviceId);

      expect(capturedPath, '/rest/v1/push_devices');
    });
  });
}
