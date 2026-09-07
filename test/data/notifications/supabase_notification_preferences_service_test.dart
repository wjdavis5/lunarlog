import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lunarlog/data/notifications/supabase_notification_preferences_service.dart';
import 'package:lunarlog/domain/notifications/notification_preferences.dart';
import 'package:lunarlog/domain/notifications/notification_preferences_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = '01JABCDEF01234567890123456';
const _profileId = '01JPROFILE00000000000000000';

/// Puts [client] into a signed-in state with no network round trip, mirroring
/// test/data/feedback/supabase_feedback_service_test.dart's `_signIn`.
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

  group('watchFor', () {
    test('emits the stored preferences', () async {
      final client = makeClient((req) async {
        expect(req.url.path, '/rest/v1/notification_preferences');
        return http.Response(
          jsonEncode({
            'user_id': _uid,
            'profile_id': _profileId,
            'alert_on_log': true,
            'alert_on_cycle_start_only': false,
            'alert_on_high_severity': false,
            'missed_entry_days': 2,
            'quiet_hours_start': '22:00:00',
            'quiet_hours_end': '07:00:00',
            'time_zone': 'America/New_York',
          }),
          200,
        );
      });
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      final prefs = await service.watchFor(_profileId).first;

      expect(prefs.alertOnLog, isTrue);
      expect(prefs.missedEntryThreshold, MissedEntryThreshold.twoDays);
      expect(prefs.quietHours,
          const QuietHours(startMinutes: 22 * 60, endMinutes: 7 * 60));
      expect(prefs.timeZone, 'America/New_York');
    });

    test('emits the all-off default when no row exists (R4)', () async {
      final client = makeClient((req) async => http.Response('null', 200));
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      final prefs = await service.watchFor(_profileId).first;

      expect(prefs, CaregiverAlertPreferences.off);
    });
  });

  group('save', () {
    test('writes and the watch stream re-emits the saved value', () async {
      var loaded = false;
      final client = makeClient((req) async {
        if (req.method == 'GET') {
          loaded = true;
          return http.Response('null', 200);
        }
        expect(req.method, 'POST');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['user_id'], _uid);
        expect(body['profile_id'], _profileId);
        expect(body['alert_on_log'], true);
        return http.Response('', 201);
      });
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      final emissions = <CaregiverAlertPreferences>[];
      final sub = service.watchFor(_profileId).listen(emissions.add);
      await pumpEventQueue();
      expect(loaded, isTrue);

      const saved = CaregiverAlertPreferences(alertOnLog: true);
      await service.save(_profileId, saved);
      await pumpEventQueue();

      expect(emissions.last, saved);
      await sub.cancel();
    });

    test('a PostgREST permission error maps to the unauthorized failure with a non-raw message', () async {
      final client = makeClient((req) async =>
          http.Response(jsonEncode({'message': 'permission denied for table', 'code': '42501'}), 403));
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      await expectLater(
        service.save(_profileId, CaregiverAlertPreferences.off),
        throwsA(isA<NotificationPreferencesUnauthorizedFailure>()
            .having((f) => f.userFacingMessage, 'userFacingMessage', isNot(contains('permission denied for table')))),
      );
    });

    test('a PostgREST 5xx status maps to the network failure', () async {
      final client = makeClient((req) async =>
          http.Response(jsonEncode({'message': 'internal error', 'code': '500'}), 500));
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      await expectLater(
        service.save(_profileId, CaregiverAlertPreferences.off),
        throwsA(isA<NotificationPreferencesNetworkFailure>()),
      );
    });

    test('an http.ClientException maps to the network failure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async => throw http.ClientException('connection reset')),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      await expectLater(
        service.save(_profileId, CaregiverAlertPreferences.off),
        throwsA(isA<NotificationPreferencesNetworkFailure>()),
      );
    });

    test('a socket error maps to the network failure', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'anon-key',
        httpClient: MockClient((request) async => throw const SocketException('offline')),
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      );
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      await expectLater(
        service.save(_profileId, CaregiverAlertPreferences.off),
        throwsA(isA<NotificationPreferencesNetworkFailure>()),
      );
    });

    test('an unknown error maps to the generic failure and the raw text appears in neither', () async {
      final client = makeClient((req) async =>
          http.Response(jsonEncode({'message': 'super secret detail', 'code': 'XXXXX'}), 400));
      await _signIn(client);
      final service = SupabaseNotificationPreferencesService(client: client);

      try {
        await service.save(_profileId, CaregiverAlertPreferences.off);
        fail('expected a NotificationPreferencesFailure');
      } on NotificationPreferencesFailure catch (failure) {
        expect(failure, isA<NotificationPreferencesOtherFailure>());
        expect(failure.toString(), isNot(contains('super secret detail')));
        expect(failure.userFacingMessage, isNot(contains('super secret detail')));
      }
    });

    test('a signed-out client rejects locally with the unauthorized failure', () async {
      final client = makeClient((req) async {
        fail('a signed-out save must never reach the network: ${req.method} ${req.url}');
      });
      final service = SupabaseNotificationPreferencesService(client: client);

      await expectLater(
        service.save(_profileId, CaregiverAlertPreferences.off),
        throwsA(isA<NotificationPreferencesUnauthorizedFailure>()),
      );
    });
  });
}
