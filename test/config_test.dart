import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/config.dart';

void main() {
  group('parseWebSyncEnabled', () {
    test('is true only for the literal "true"', () {
      expect(parseWebSyncEnabled('true'), isTrue);
    });

    test('is false for empty, "false", and "TRUE"', () {
      expect(parseWebSyncEnabled(''), isFalse);
      expect(parseWebSyncEnabled('false'), isFalse);
      expect(parseWebSyncEnabled('TRUE'), isFalse);
      expect(parseWebSyncEnabled(' true'), isFalse);
      expect(parseWebSyncEnabled('1'), isFalse);
    });
  });

  group('computeHasSupabase (native)', () {
    test('is false when the URL is empty', () {
      expect(
        computeHasSupabase(
          url: '',
          publishableKey: 'sb_publishable_x',
          isWeb: false,
          webSyncEnabled: false,
        ),
        isFalse,
      );
    });

    test('is false when the key is empty', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: '',
          isWeb: false,
          webSyncEnabled: false,
        ),
        isFalse,
      );
    });

    test('is false when both are empty', () {
      expect(
        computeHasSupabase(
          url: '',
          publishableKey: '',
          isWeb: false,
          webSyncEnabled: false,
        ),
        isFalse,
      );
    });

    test('is true when both are set', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_x',
          isWeb: false,
          webSyncEnabled: false,
        ),
        isTrue,
      );
    });
  });

  group('computeHasSupabase (web)', () {
    test('is false on web unless webSyncEnabled, even when both are set', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_x',
          isWeb: true,
          webSyncEnabled: false,
        ),
        isFalse,
      );
    });

    test('is true on web when webSyncEnabled and both are set', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_x',
          isWeb: true,
          webSyncEnabled: true,
        ),
        isTrue,
      );
    });

    test('webSyncEnabled alone does not configure Supabase on web', () {
      expect(
        computeHasSupabase(
          url: '',
          publishableKey: '',
          isWeb: true,
          webSyncEnabled: true,
        ),
        isFalse,
      );
    });
  });

  group('computeHasSentry', () {
    test('is false for an empty DSN', () {
      expect(computeHasSentry(''), isFalse);
    });

    test('is true for a non-empty DSN', () {
      expect(computeHasSentry('https://key@o0.ingest.sentry.io/0'), isTrue);
    });
  });

  group('computeHasGoogle', () {
    test('is false when the iOS client id is empty', () {
      expect(
        computeHasGoogle(
          hasSupabase: true,
          isWeb: false,
          iosClientId: '',
          webClientId: 'web-id.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });

    test('is false when the web client id is empty', () {
      expect(
        computeHasGoogle(
          hasSupabase: true,
          isWeb: false,
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: '',
        ),
        isFalse,
      );
    });

    test('is false on web even when both ids are set', () {
      expect(
        computeHasGoogle(
          hasSupabase: true,
          isWeb: true,
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: 'web-id.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });

    test('is false when Supabase is unconfigured', () {
      expect(
        computeHasGoogle(
          hasSupabase: false,
          isWeb: false,
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: 'web-id.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });

    test('is true natively when Supabase and both ids are set', () {
      expect(
        computeHasGoogle(
          hasSupabase: true,
          isWeb: false,
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: 'web-id.apps.googleusercontent.com',
        ),
        isTrue,
      );
    });
  });

  group('computeHasPush', () {
    Map<String, String> fullSet() => {
          'projectId': 'proj-1',
          'senderId': '1234567890',
          'androidApiKey': 'android-key',
          'androidAppId': '1:1234567890:android:abc',
          'iosApiKey': 'ios-key',
          'iosAppId': '1:1234567890:ios:abc',
        };

    bool call(Map<String, String> fields, {bool hasSupabase = true, bool isWeb = false}) =>
        computeHasPush(
          hasSupabase: hasSupabase,
          isWeb: isWeb,
          projectId: fields['projectId']!,
          senderId: fields['senderId']!,
          androidApiKey: fields['androidApiKey']!,
          androidAppId: fields['androidAppId']!,
          iosApiKey: fields['iosApiKey']!,
          iosAppId: fields['iosAppId']!,
        );

    test('is false with any single FCM_* define empty', () {
      for (final key in fullSet().keys) {
        final fields = fullSet()..[key] = '';
        expect(call(fields), isFalse, reason: 'empty $key must disable push');
      }
    });

    test('is false on web even with every define set', () {
      expect(call(fullSet(), isWeb: true), isFalse);
    });

    test('is false without hasSupabase', () {
      expect(call(fullSet(), hasSupabase: false), isFalse);
    });

    test('is true only with the full set, natively, with Supabase configured', () {
      expect(call(fullSet()), isTrue);
    });
  });

  group('AppConfig (compile-time values in this test run)', () {
    // The test runner passes no dart-defines, so every value is unconfigured.
    test('is unconfigured without dart-defines', () {
      expect(AppConfig.supabaseUrl, isEmpty);
      expect(AppConfig.supabasePublishableKey, isEmpty);
      expect(AppConfig.sentryDsn, isEmpty);
      expect(AppConfig.webSyncEnabled, isFalse);
      expect(AppConfig.hasSupabase, isFalse);
      expect(AppConfig.hasSentry, isFalse);
      expect(AppConfig.googleIosClientId, isEmpty);
      expect(AppConfig.googleWebClientId, isEmpty);
      expect(AppConfig.hasGoogle, isFalse);
      expect(AppConfig.fcmProjectId, isEmpty);
      expect(AppConfig.fcmSenderId, isEmpty);
      expect(AppConfig.fcmAndroidApiKey, isEmpty);
      expect(AppConfig.fcmAndroidAppId, isEmpty);
      expect(AppConfig.fcmIosApiKey, isEmpty);
      expect(AppConfig.fcmIosAppId, isEmpty);
      expect(AppConfig.hasPush, isFalse);
    });

    test('hasSupabase agrees with the pure function for this platform', () {
      expect(
        AppConfig.hasSupabase,
        computeHasSupabase(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabasePublishableKey,
          isWeb: kIsWeb,
          webSyncEnabled: AppConfig.webSyncEnabled,
        ),
      );
    });

    test('hasGoogle agrees with the pure function for this platform', () {
      expect(
        AppConfig.hasGoogle,
        computeHasGoogle(
          hasSupabase: AppConfig.hasSupabase,
          isWeb: kIsWeb,
          iosClientId: AppConfig.googleIosClientId,
          webClientId: AppConfig.googleWebClientId,
        ),
      );
    });

    test('hasPush agrees with the pure function for this platform', () {
      expect(
        AppConfig.hasPush,
        computeHasPush(
          hasSupabase: AppConfig.hasSupabase,
          isWeb: kIsWeb,
          projectId: AppConfig.fcmProjectId,
          senderId: AppConfig.fcmSenderId,
          androidApiKey: AppConfig.fcmAndroidApiKey,
          androidAppId: AppConfig.fcmAndroidAppId,
          iosApiKey: AppConfig.fcmIosApiKey,
          iosAppId: AppConfig.fcmIosAppId,
        ),
      );
    });
  });
}
