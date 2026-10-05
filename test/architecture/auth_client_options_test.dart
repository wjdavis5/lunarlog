/// Seam pins for the Supabase auth client options.
///
/// `SupabaseAuthService` exchanges a PKCE `code` itself, from the app link
/// that carried it, because `detectSessionInUri` stays off by design. This
/// pins the code facts that make that safe:
///
/// * `buildAuthClientOptions` keeps PKCE-only + `detectSessionInUri: false`
///   and passes `SecureLocalStorage` (Keychain/Keystore) for both the
///   session and the PKCE verifier.
/// * `detectSessionInUri` is never set true anywhere in `lib/`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/auth/secure_local_storage.dart';
import 'package:lunarlog/startup/supabase_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthFlowType;

void main() {
  group('buildAuthClientOptions', () {
    test('PKCE-only, detectSessionInUri off, SecureLocalStorage for both the '
        'session and the PKCE verifier', () {
      final options = buildAuthClientOptions();
      expect(options.authFlowType, AuthFlowType.pkce);
      expect(options.detectSessionInUri, isFalse);
      expect(options.localStorage, isA<SecureLocalStorage>());
      expect(options.pkceAsyncStorage, isA<SecureLocalStorage>());
    });

    test('an injected storage backs both the session and the verifier', () {
      final storage = SecureLocalStorage();
      final options = buildAuthClientOptions(nativeStorage: storage);
      expect(options.localStorage, same(storage));
      expect(options.pkceAsyncStorage, same(storage));
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
            'any widget exists',
      );
    });
  });
}
