/// Unit tests for [SupabaseConsentService] and [ConsentRecord] (Issue #845),
/// mirroring the mocked-`SupabaseClient` pattern proven in
/// `test/data/export/supabase_account_export_remote_source_test.dart`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/consent/supabase_consent_service.dart';
import 'package:lunarlog/domain/consent/consent_service.dart';
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

  group('fetchMinimumAgeAcknowledgement', () {
    test('a signed-out client makes no network call and returns null',
        () async {
      final client = makeClient((req) async {
        fail('a signed-out fetch must never reach the network');
      });
      final service = SupabaseConsentService(client: client);

      expect(await service.fetchMinimumAgeAcknowledgement(), isNull);
    });

    test('reads the caller\'s row and parses it', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/account_consents');
        return http.Response(
          jsonEncode({
            'consent_via': 'self_13_plus',
            'acknowledged_at': '2026-09-21T10:00:00Z',
            'app_version': '1.0.0+1',
            'policy_version': kMinimumAgePolicyVersion,
          }),
          200,
        );
      });
      await _signIn(client);
      final service = SupabaseConsentService(client: client);

      final record = await service.fetchMinimumAgeAcknowledgement();

      expect(record, isNotNull);
      expect(record!.consentVia, kConsentViaSelf13Plus);
      expect(record.policyVersion, kMinimumAgePolicyVersion);
      expect(record.appVersion, '1.0.0+1');
      expect(record.acknowledgedAt, DateTime.parse('2026-09-21T10:00:00Z'));
    });

    test('a malformed row (missing policy_version) resolves to null',
        () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({
            'consent_via': 'self_13_plus',
            'acknowledged_at': '2026-09-21T10:00:00Z',
            'app_version': '1.0.0+1',
          }),
          200,
        );
      });
      await _signIn(client);
      final service = SupabaseConsentService(client: client);

      expect(await service.fetchMinimumAgeAcknowledgement(), isNull);
    });

    test('a server error is swallowed into null rather than thrown', () async {
      final client = makeClient((req) async {
        return http.Response(
          jsonEncode({'code': '42501', 'message': 'insufficient_privilege'}),
          403,
        );
      });
      await _signIn(client);
      final service = SupabaseConsentService(client: client);

      expect(await service.fetchMinimumAgeAcknowledgement(), isNull);
    });
  });

  group('recordMinimumAgeAcknowledgement', () {
    test('a signed-out client makes no network call', () async {
      final client = makeClient((req) async {
        fail('a signed-out record must never reach the network');
      });
      final service = SupabaseConsentService(client: client);

      await service.recordMinimumAgeAcknowledgement(
        consentVia: kConsentViaSelf13Plus,
        appVersion: '1.0.0+1',
        policyVersion: kMinimumAgePolicyVersion,
      );
    });

    test('calls record_minimum_age_acknowledgement with the three parameters',
        () async {
      Map<String, dynamic>? capturedBody;
      final client = makeClient((req) async {
        expect(
          req.url.path,
          '/rest/v1/rpc/record_minimum_age_acknowledgement',
        );
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('', 200);
      });
      await _signIn(client);
      final service = SupabaseConsentService(client: client);

      await service.recordMinimumAgeAcknowledgement(
        consentVia: kConsentViaSelf13Plus,
        appVersion: '1.0.0+1',
        policyVersion: kMinimumAgePolicyVersion,
      );

      expect(capturedBody?['p_consent_via'], kConsentViaSelf13Plus);
      expect(capturedBody?['p_app_version'], '1.0.0+1');
      expect(capturedBody?['p_policy_version'], kMinimumAgePolicyVersion);
    });

    test('a server error propagates (the caller decides how best-effort)',
        () async {
      final client = makeClient((req) async {
        return http.Response(jsonEncode({'message': 'boom'}), 500);
      });
      await _signIn(client);
      final service = SupabaseConsentService(client: client);

      expect(
        () => service.recordMinimumAgeAcknowledgement(
          consentVia: kConsentViaSelf13Plus,
          appVersion: '1.0.0+1',
          policyVersion: kMinimumAgePolicyVersion,
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  group('ConsentRecord.fromJson', () {
    test('parses a complete row', () {
      final record = ConsentRecord.fromJson({
        'consent_via': 'parent_invite',
        'acknowledged_at': '2026-09-21T10:00:00Z',
        'app_version': '1.0.0+1',
        'policy_version': 'v1',
      });

      expect(record, isNotNull);
      expect(record!.consentVia, 'parent_invite');
    });

    test('returns null for an unparseable acknowledged_at', () {
      expect(
        ConsentRecord.fromJson({
          'consent_via': 'self_13_plus',
          'acknowledged_at': 'not-a-timestamp',
          'app_version': '1.0.0+1',
          'policy_version': 'v1',
        }),
        isNull,
      );
    });

    test('returns null when a required string is absent', () {
      expect(
        ConsentRecord.fromJson({
          'acknowledged_at': '2026-09-21T10:00:00Z',
          'app_version': '1.0.0+1',
          'policy_version': 'v1',
        }),
        isNull,
      );
    });
  });
}
