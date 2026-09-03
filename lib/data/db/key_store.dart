/// Per-install database key management.
///
/// One random 32-byte key per install (hex-encoded, 64 lowercase chars),
/// persisted with flutter_secure_storage and reused on every open. A
/// malformed existing key is never overwritten — a regenerated key would
/// make the existing encrypted database permanently unreadable.
library;

import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'errors.dart';

abstract interface class DbKeyStore {
  /// Returns the install's database key, creating it on first run.
  ///
  /// Throws [CorruptDatabaseKeyError] if a persisted key exists but is
  /// malformed.
  Future<String> getOrCreateDbKey();

  /// Forgets the persisted key so the next [getOrCreateDbKey] mints a fresh
  /// one. A device-reset primitive (KTD16): the caller must delete the
  /// database file *before* this, because a keyed file left behind would
  /// quarantine on the next open. Does nothing when no key is stored.
  Future<void> deleteKey();
}

class SecureDbKeyStore implements DbKeyStore {
  SecureDbKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String storageKey = 'lunarlog.db.key';

  final FlutterSecureStorage _storage;

  @override
  Future<String> getOrCreateDbKey() async {
    final existing = await _storage.read(key: storageKey);
    if (existing != null) {
      if (!isValidDbKeyHex(existing)) {
        throw const CorruptDatabaseKeyError();
      }
      return existing;
    }
    final key = generateKey();
    await _storage.write(key: storageKey, value: key);
    return key;
  }

  @override
  Future<void> deleteKey() => _storage.delete(key: storageKey);

  /// Random 32 bytes as 64 lowercase hex characters (SQLCipher raw key
  /// material, applied via `PRAGMA key = "x'…'"`).
  static String generateKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Whether [key] is a well-formed database key: 32 bytes hex-encoded.
/// Enforced at the factory seam so no key-store implementation can slip a
/// malformed key through to SQLCipher.
bool isValidDbKeyHex(String key) => _validKey.hasMatch(key);

final RegExp _validKey = RegExp(r'^[0-9a-f]{64}$');
