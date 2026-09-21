/// Epic #831 slice 2 seam pins for web auth.
///
/// The browser cannot open the native `lunarlog://auth-callback` scheme, so
/// the web build (a) redirects its auth emails to `<origin>/auth/callback`
/// and (b) exchanges the returned `?code=` from the initial `Uri.base`
/// through `SupabaseAuthService` itself, because `detectSessionInUri` stays
/// off by design. This pins the two code facts that make that safe:
///
/// * `buildAuthClientOptions` keeps PKCE-only + `detectSessionInUri: false`
///   on both platforms, and on web passes **no** custom storage — so the
///   session and PKCE verifier live in gotrue's own browser storage
///   (`localStorage`), which gotrue's `signOut` clears with the session.
///   Native still passes `SecureLocalStorage` (Keychain/Keystore).
/// * `resolveAuthRedirectUrl` sends web mail to the origin callback rather
///   than the un-openable custom scheme.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/secure_local_storage.dart';
import 'package:lunarlog/data/auth/supabase_auth_service.dart';
import 'package:lunarlog/startup/supabase_bootstrap.dart';

void main() {
  group('buildAuthClientOptions', () {
    test('native: PKCE-only, detectSessionInUri off, SecureLocalStorage for '
        'both the session and the PKCE verifier', () {
      final options = buildAuthClientOptions(isWeb: false);
      expect(options.detectSessionInUri, isFalse);
      expect(options.localStorage, isA<SecureLocalStorage>());
      expect(options.pkceAsyncStorage, isA<SecureLocalStorage>());
    });

    test('web: PKCE-only, detectSessionInUri off, and no custom storage — '
        'the session lives in gotrue\'s own browser storage, which its own '
        'signOut clears', () {
      final options = buildAuthClientOptions(isWeb: true);
      expect(options.detectSessionInUri, isFalse);
      expect(options.localStorage, isNull,
          reason: 'a web session must use gotrue\'s browser default, not '
              'flutter_secure_storage');
      expect(options.pkceAsyncStorage, isNull);
    });

    test('detectSessionInUri is never set true anywhere in lib/', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (RegExp(r'detectSessionInUri\s*:\s*true').hasMatch(source)) {
          offenders.add(entity.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'detectSessionInUri must stay false: the app exchanges PKCE '
            'codes itself so a cold-start recovery link is latched before '
            'any widget exists (#831 slice 2)',
      );
    });
  });

  group('resolveAuthRedirectUrl', () {
    test('native keeps the custom scheme; web uses the origin callback path',
        () {
      expect(
        resolveAuthRedirectUrl(isWeb: false, base: Uri.parse('https://x.y/z')),
        kAuthCallbackUrl,
      );
      expect(
        resolveAuthRedirectUrl(
          isWeb: true,
          base: Uri.parse('https://app.lunarlog.app/'),
        ),
        'https://app.lunarlog.app$kWebAuthCallbackPath',
      );
    });

    test('the web redirect preserves the page origin only (no subpath)', () {
      expect(
        resolveAuthRedirectUrl(
          isWeb: true,
          base: Uri.parse('https://app.lunarlog.app/app/?a=1'),
        ),
        'https://app.lunarlog.app/auth/callback',
      );
    });
  });
}
