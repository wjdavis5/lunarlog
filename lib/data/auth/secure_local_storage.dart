/// Supabase session + PKCE verifier storage over flutter_secure_storage
/// (U4; KTD7, R5). Native only: the bootstrap passes this to
/// `Supabase.initialize` on iOS/Android and leaves the package default on
/// web.
///
/// iOS: `first_unlock_this_device` — the Keychain items are usable once the
/// device has been unlocked after boot and never migrate in a backup or
/// device transfer. `synchronizable` stays false (no iCloud Keychain).
/// Android: the package default (AES-GCM encrypted preferences under a
/// Keystore-wrapped key); `allowBackup="false"` in the manifest already
/// keeps them out of backups.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SecureLocalStorage extends LocalStorage implements GotrueAsyncStorage {
  SecureLocalStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _sessionKey = 'lunarlog.supabase.session';
  static const String _pkcePrefix = 'lunarlog.supabase.pkce.';

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
    synchronizable: false,
  );
  static const AndroidOptions _androidOptions = AndroidOptions();

  /// The Apple Keychain options every call carries (asserted by tests).
  IOSOptions get iosOptions => _iosOptions;

  AndroidOptions get androidOptions => _androidOptions;

  // --- LocalStorage (session) ---

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _storage.containsKey(
        key: _sessionKey,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  @override
  Future<String?> accessToken() => _read(_sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _write(_sessionKey, persistSessionString);

  @override
  Future<void> removePersistedSession() => _delete(_sessionKey);

  // --- GotrueAsyncStorage (PKCE code verifier) ---

  @override
  Future<String?> getItem({required String key}) => _read('$_pkcePrefix$key');

  @override
  Future<void> setItem({required String key, required String value}) =>
      _write('$_pkcePrefix$key', value);

  @override
  Future<void> removeItem({required String key}) =>
      _delete('$_pkcePrefix$key');

  // --- helpers ---

  Future<String?> _read(String key) => _storage.read(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  Future<void> _write(String key, String value) => _storage.write(
        key: key,
        value: value,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );

  Future<void> _delete(String key) => _storage.delete(
        key: key,
        iOptions: _iosOptions,
        aOptions: _androidOptions,
        mOptions: _iosOptions,
      );
}
