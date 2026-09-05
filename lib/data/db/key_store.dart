/// Per-install database key management.
///
/// One random 32-byte key per install (hex-encoded, 64 lowercase chars),
/// persisted with flutter_secure_storage and reused on every open. A
/// malformed existing key is never overwritten — a regenerated key would
/// make the existing encrypted database permanently unreadable.
///
/// [SecureDbKeyStore.getOrCreateDbKey] also migrates a key stored under an
/// earlier Keychain accessibility (see [SecureDbKeyStore.legacyIOSOptions])
/// forward to the current one. `flutter_secure_storage_darwin`'s read query
/// includes `kSecAttrAccessible`, which makes it a *matching constraint*,
/// not merely a write-time attribute — a key written under a different
/// accessibility value is invisible to a read under the current one.
/// Without this migration, changing the accessibility would make an
/// existing install's key look "missing", mint a fresh key over the
/// existing encrypted database, and leave that database permanently
/// unopenable (`DatabaseQuarantineError` on the next open in
/// db_factory.dart).
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  /// Explicit Keychain accessibility for the database key (rather than
  /// relying on flutter_secure_storage's `unlocked` default): the key must
  /// not migrate to a different device on a backup restore (the encrypted
  /// database file itself never migrates that way either, so a synced key
  /// would only be dead weight sitting in a new device's Keychain), while
  /// keeping the *lock-state* requirement exactly as strict as the library
  /// default — unreadable whenever the device is locked at all.
  ///
  /// This is [KeychainAccessibility.unlocked_this_device], **not**
  /// `first_unlock_this_device`. An earlier commit set this field to
  /// `first_unlock_this_device`, reasoning it was "strictly more
  /// conservative than the library default in both axes". That reasoning
  /// had the lock-state axis backwards: `unlocked` (the library default) is
  /// the *more* restrictive choice on that axis — unreadable the instant
  /// the device locks, with no post-boot floor — while
  /// `first_unlock_this_device` stays readable through the rest of the boot
  /// cycle after any single unlock, including while the device is
  /// subsequently locked again. `unlocked_this_device` keeps `unlocked`'s
  /// lock-state requirement exactly (readable only while the device is
  /// actually unlocked) and adds only the device-pinning axis
  /// (non-migratable, no iCloud/backup sync) that the earlier commit was
  /// actually after — the correct choice for a minors'-data health app's
  /// SQLCipher key. See docs/ops/ios-export-compliance.md.
  SecureDbKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const String storageKey = 'lunarlog.db.key';

  /// Keychain accessibility values this store has used in the past,
  /// most-recently-used first. [getOrCreateDbKey] checks these, in order,
  /// only when the key is not found under the current accessibility (see
  /// the library doc comment for why a plain read cannot see them).
  ///
  /// * `first_unlock_this_device` — set by a fix commit earlier in the same
  ///   pull request that added this migration, on the strength of the
  ///   inverted reasoning corrected in the [SecureDbKeyStore] doc comment;
  ///   briefly live in this branch only.
  /// * `unlocked` — the flutter_secure_storage default this store relied on
  ///   implicitly before any accessibility was set explicitly here at all;
  ///   the value any install that predates this pull request actually
  ///   carries.
  @visibleForTesting
  static const List<IOSOptions> legacyIOSOptions = [
    IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    IOSOptions(accessibility: KeychainAccessibility.unlocked),
  ];

  final FlutterSecureStorage _storage;

  /// Exposes the configured storage so a test can assert on [iOptions]
  /// (e.g. the Keychain accessibility) without exercising the platform
  /// channel, which constructing a [FlutterSecureStorage] does not touch.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  @override
  Future<String> getOrCreateDbKey() async {
    final existing = await _storage.read(key: storageKey);
    if (existing != null) {
      if (!isValidDbKeyHex(existing)) {
        throw const CorruptDatabaseKeyError();
      }
      return existing;
    }

    for (final legacyOptions in legacyIOSOptions) {
      final legacy = await _storage.read(
        key: storageKey,
        iOptions: legacyOptions,
      );
      if (legacy == null) continue;
      if (!isValidDbKeyHex(legacy)) {
        throw const CorruptDatabaseKeyError();
      }
      // Re-persist under the current accessibility so every subsequent
      // read (which uses _storage's own configured options) finds it
      // directly, without this fallback ever running again.
      await _storage.write(key: storageKey, value: legacy);
      // Best-effort cleanup of the old item: whether the write above
      // updated the existing Keychain entry in place or added a new one
      // is a platform-implementation detail; deleting under the old
      // accessibility removes a leftover duplicate if one exists, and is
      // a harmless no-op if it doesn't.
      await _storage.delete(key: storageKey, iOptions: legacyOptions);
      return legacy;
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
