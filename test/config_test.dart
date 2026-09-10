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

  group('computeTracesSampleRate (issue #7 U4; KTD8)', () {
    test('empty is null', () {
      expect(computeTracesSampleRate(''), isNull);
    });

    test('unparseable is null', () {
      expect(computeTracesSampleRate('abc'), isNull);
    });

    test('a value inside [0, 1] passes through unchanged', () {
      expect(computeTracesSampleRate('0.2'), 0.2);
      expect(computeTracesSampleRate('1'), 1.0);
      expect(computeTracesSampleRate('0'), 0.0);
    });

    test('negative clamps to 0.0', () {
      expect(computeTracesSampleRate('-1'), 0.0);
    });

    test('greater than 1 clamps to 1.0', () {
      expect(computeTracesSampleRate('5'), 1.0);
    });

    // Code-review finding: double.tryParse accepts the literal tokens
    // "NaN"/"Infinity" as successfully parsed (not null), and num.clamp
    // maps NaN to the *upper* bound rather than rejecting it -- so a
    // non-finite value must be treated the same as unparseable (off), not
    // silently clamped into 100% tracing.
    test('non-finite values (NaN, Infinity, -Infinity) are null, not '
        'clamped to 1.0', () {
      expect(computeTracesSampleRate('NaN'), isNull);
      expect(computeTracesSampleRate('Infinity'), isNull);
      expect(computeTracesSampleRate('-Infinity'), isNull);
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

  group('computeHasPasskeys', () {
    test('is false when the relying-party id is empty', () {
      expect(
        computeHasPasskeys(
          hasSupabase: true,
          isWeb: false,
          relyingPartyId: '',
        ),
        isFalse,
      );
    });

    test('is false when Supabase is unconfigured', () {
      expect(
        computeHasPasskeys(
          hasSupabase: false,
          isWeb: false,
          relyingPartyId: 'example.com',
        ),
        isFalse,
      );
    });

    test('is false on web even when the id is set', () {
      expect(
        computeHasPasskeys(
          hasSupabase: true,
          isWeb: true,
          relyingPartyId: 'example.com',
        ),
        isFalse,
      );
    });

    test('is true when Supabase is configured, not web, and id is set', () {
      expect(
        computeHasPasskeys(
          hasSupabase: true,
          isWeb: false,
          relyingPartyId: 'example.com',
        ),
        isTrue,
      );
    });
  });

  group('computeHasUniversalLinks (issue #129)', () {
    test('is false for an empty link domain', () {
      expect(computeHasUniversalLinks(''), isFalse);
    });

    test('is true for any non-empty link domain', () {
      expect(computeHasUniversalLinks('links.example.com'), isTrue);
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
      expect(AppConfig.passkeyRelyingPartyId, isEmpty);
      expect(AppConfig.hasPasskeys, isFalse);
      // Issue #129: no LUNARLOG_LINK_DOMAIN in this test run, so the build
      // stays custom-scheme-only (AC5).
      expect(AppConfig.linkDomain, isEmpty);
      expect(AppConfig.hasUniversalLinks, isFalse);
      expect(AppConfig.fcmProjectId, isEmpty);
      expect(AppConfig.fcmSenderId, isEmpty);
      expect(AppConfig.fcmAndroidApiKey, isEmpty);
      expect(AppConfig.fcmAndroidAppId, isEmpty);
      expect(AppConfig.fcmIosApiKey, isEmpty);
      expect(AppConfig.fcmIosAppId, isEmpty);
      expect(AppConfig.hasPush, isFalse);
      // Issue #193 flipped this when the one-way, opt-in, forward-only
      // menstrual-flow write path landed (iOS only via that path's own
      // platform gates).
      expect(AppConfig.hasHealthSync, isTrue);
      // Issue #296: pinned here (like hasHealthSync above) so flipping
      // the minor-binding flag is a deliberate, reviewed code change that
      // must update this pin — the transferred-minor binding path stays
      // categorically closed until #295 (what "minor" means) and #188
      // (server-side consent) land and the guard's remaining gap is
      // closed. Denies-by-default is the safe direction.
      expect(AppConfig.healthSyncMinorBindingAllowed, isFalse);
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

    test('hasPasskeys agrees with the pure function for this platform', () {
      expect(
        AppConfig.hasPasskeys,
        computeHasPasskeys(
          hasSupabase: AppConfig.hasSupabase,
          isWeb: kIsWeb,
          relyingPartyId: AppConfig.passkeyRelyingPartyId,
        ),
      );
    });

    test('sentryTracesSampleRate agrees with the pure function applied to '
        'an empty raw define -- this test run passes none (issue #7 U4)',
        () {
      expect(AppConfig.sentryTracesSampleRate, isNull);
      expect(AppConfig.sentryTracesSampleRate, computeTracesSampleRate(''));
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

    test('hasUniversalLinks agrees with the pure function', () {
      expect(
        AppConfig.hasUniversalLinks,
        computeHasUniversalLinks(AppConfig.linkDomain),
      );
    });
  });
}
