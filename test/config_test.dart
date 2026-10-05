import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/config.dart';

void main() {
  group('computeHasSupabase', () {
    test('is false when the URL is empty', () {
      expect(
        computeHasSupabase(
          url: '',
          publishableKey: 'sb_publishable_x',
        ),
        isFalse,
      );
    });

    test('is false when the key is empty', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: '',
        ),
        isFalse,
      );
    });

    test('is false when both are empty', () {
      expect(
        computeHasSupabase(
          url: '',
          publishableKey: '',
        ),
        isFalse,
      );
    });

    test('is true when both are set', () {
      expect(
        computeHasSupabase(
          url: 'https://example.supabase.co',
          publishableKey: 'sb_publishable_x',
        ),
        isTrue,
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
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: '',
        ),
        isFalse,
      );
    });

    test('is false when Supabase is unconfigured', () {
      expect(
        computeHasGoogle(
          hasSupabase: false,
          iosClientId: 'ios-id.apps.googleusercontent.com',
          webClientId: 'web-id.apps.googleusercontent.com',
        ),
        isFalse,
      );
    });

    test('is true when Supabase and both ids are set', () {
      expect(
        computeHasGoogle(
          hasSupabase: true,
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
          relyingPartyId: '',
        ),
        isFalse,
      );
    });

    test('is false when Supabase is unconfigured', () {
      expect(
        computeHasPasskeys(
          hasSupabase: false,
          relyingPartyId: 'example.com',
        ),
        isFalse,
      );
    });

    test('is true when Supabase is configured and the id is set', () {
      expect(
        computeHasPasskeys(
          hasSupabase: true,
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

    bool call(Map<String, String> fields, {bool hasSupabase = true}) =>
        computeHasPush(
          hasSupabase: hasSupabase,
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

    test('is false without hasSupabase', () {
      expect(call(fullSet(), hasSupabase: false), isFalse);
    });

    test('is true only with the full set, with Supabase configured', () {
      expect(call(fullSet()), isTrue);
    });
  });

  group('AppConfig (compile-time values in this test run)', () {
    // The test runner passes no dart-defines, so every value is unconfigured.
    test('is unconfigured without dart-defines', () {
      expect(AppConfig.supabaseUrl, isEmpty);
      expect(AppConfig.supabasePublishableKey, isEmpty);
      expect(AppConfig.sentryDsn, isEmpty);
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
      // Issue #296 pinned this while the flag was false; Issue #882 flipped
      // it to true so a minor profile binds on the same terms as an adult
      // (the production configuration). Flipping the default in config.dart
      // must update this pin consciously.
      expect(AppConfig.healthSyncMinorBindingAllowed, isTrue);
      // Issue #738: this test run passes no dart-defines, so the MFA
      // client surface is off — the compile-time default every
      // CI/workflow build ships. Turning it on is a deliberate
      // `--dart-define=LUNARLOG_ENABLE_MFA=true` release action (plus the
      // #730 dashboard TOTP toggle); flipping the default in config.dart
      // must update this pin consciously.
      expect(AppConfig.mfaEnabled, isFalse);
    });

    test('hasSupabase agrees with the pure function', () {
      expect(
        AppConfig.hasSupabase,
        computeHasSupabase(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabasePublishableKey,
        ),
      );
    });

    test('hasGoogle agrees with the pure function', () {
      expect(
        AppConfig.hasGoogle,
        computeHasGoogle(
          hasSupabase: AppConfig.hasSupabase,
          iosClientId: AppConfig.googleIosClientId,
          webClientId: AppConfig.googleWebClientId,
        ),
      );
    });

    test('hasPasskeys agrees with the pure function', () {
      expect(
        AppConfig.hasPasskeys,
        computeHasPasskeys(
          hasSupabase: AppConfig.hasSupabase,
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

    test('hasPush agrees with the pure function', () {
      expect(
        AppConfig.hasPush,
        computeHasPush(
          hasSupabase: AppConfig.hasSupabase,
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

    test('crashSmokeEnabled is false here (no define) and agrees with the '
        'pure rule: the empty define is the only reason, since flutter test '
        'is a debug run (issue #973)', () {
      expect(AppConfig.crashSmokeEnabled, isFalse);
      expect(
        AppConfig.crashSmokeEnabled,
        computeCrashSmokeEnabled(define: false, debugMode: true),
      );
    });
  });

  group('computeCrashSmokeEnabled (issue #973)', () {
    test('requires both the define and a debug build — a release build can '
        'never carry the trigger, whatever the define says', () {
      expect(computeCrashSmokeEnabled(define: true, debugMode: true), isTrue);
      expect(computeCrashSmokeEnabled(define: false, debugMode: true), isFalse);
      expect(computeCrashSmokeEnabled(define: true, debugMode: false), isFalse);
      expect(
        computeCrashSmokeEnabled(define: false, debugMode: false),
        isFalse,
      );
    });
  });
}
