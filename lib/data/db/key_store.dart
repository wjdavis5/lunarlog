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
///
/// The migration is journaled through a second Keychain account
/// ([SecureDbKeyStore.migratingStorageKey]) rather than deleting the old
/// copy and then writing the new one directly: a bare delete-then-write can
/// be interrupted (process kill, a throwing write, a locked-device write —
/// see the [SecureDbKeyStore] doc comment) between the two steps, and
/// because the delete already removed the only copy, that interruption
/// loses the key permanently. Journaling guarantees at least one readable
/// copy exists at every step, and [SecureDbKeyStore.getOrCreateDbKey]
/// checks for and resumes an interrupted journal on every call, so a crash
/// mid-migration is recovered on the next launch instead of quarantining
/// the database.
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
  /// Explicit Keychain accessibility for the database key: pinned to
  /// [KeychainAccessibility.unlocked] — the flutter_secure_storage default,
  /// and the accessibility every install that predates this pull request
  /// actually carries. Set explicitly (rather than left implicit) so the
  /// choice is documented and doesn't silently drift if the library's own
  /// default ever changes.
  ///
  /// Two earlier commits on this same pull request tried to pin this key to
  /// the physical device instead — first `first_unlock_this_device`, then
  /// (after correcting that choice's inverted lock-state reasoning)
  /// `unlocked_this_device`. Both were reverted here. Device-pinning a
  /// Keychain item only makes sense when the file it protects has matching
  /// backup behavior, and the SQLCipher database file does not: it lives in
  /// `getApplicationDocumentsDirectory()` with no backup exclusion set
  /// anywhere in this repo (see README.md's "not explicitly excluded from
  /// iCloud backups" note), so the file *does* ride an iCloud backup/restore
  /// to a new device while a device-pinned key never would. Restoring to a
  /// new phone would then leave the file in place with no key that can ever
  /// be found for it — a permanent `DatabaseQuarantineError`, which is worse
  /// than this pull request's starting point (no backup, no restore, so the
  /// question never arose). Excluding the database file from backups would
  /// resolve the mismatch and let the key go back to being device-pinned,
  /// but that needs native iOS AppDelegate work (`NSURLIsExcludedFromBackupKey`
  /// on the file) that is out of scope here — it's the same work already
  /// tracked as deferred in README.md and, together with the
  /// `unlocked` → `unlocked_this_device` key-class migration this reverts,
  /// in docs/ops/supabase-go-live.md's Deferred follow-ups.
  SecureDbKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked),
          );

  static const String storageKey = 'lunarlog.db.key';

  /// A second Keychain account used only as a migration journal (see the
  /// library doc comment). Never read by normal (non-migrating) opens.
  @visibleForTesting
  static const String migratingStorageKey = 'lunarlog.db.key.migrating';

  /// Keychain accessibility values this store has used in the past,
  /// most-recently-used first. [getOrCreateDbKey] checks these, in order,
  /// only when the key is not found under the current accessibility (see
  /// the library doc comment for why a plain read cannot see them).
  ///
  /// Both entries are accessibility values this pull request itself tried
  /// and reverted (see the [SecureDbKeyStore] doc comment) — an install
  /// that predates this pull request already carries the current
  /// accessibility (`unlocked`) and needs no migration at all.
  ///
  /// * `first_unlock_this_device` — set by a fix commit earlier in this
  ///   pull request, on the strength of the inverted lock-state reasoning
  ///   corrected in the [SecureDbKeyStore] doc comment.
  /// * `unlocked_this_device` — set by the next fix commit in this pull
  ///   request, correcting that lock-state reasoning but pinning the key to
  ///   the device without matching backup-exclusion on the database file
  ///   itself; reverted by the [SecureDbKeyStore] doc comment's fix.
  @visibleForTesting
  static const List<IOSOptions> legacyIOSOptions = [
    IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
  ];

  final FlutterSecureStorage _storage;

  /// Exposes the configured storage so a test can assert on [iOptions]
  /// (e.g. the Keychain accessibility) without exercising the platform
  /// channel, which constructing a [FlutterSecureStorage] does not touch.
  @visibleForTesting
  FlutterSecureStorage get storage => _storage;

  @override
  Future<String> getOrCreateDbKey() async {
    final resumed = await _resumeInterruptedMigration();
    if (resumed != null) return resumed;

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
      return _migrate(legacy, legacyOptions);
    }

    final key = generateKey();
    await _storage.write(key: storageKey, value: key);
    return key;
  }

  /// Moves [legacy] (found under [legacyOptions]) to the current
  /// accessibility, journaled through [migratingStorageKey] so a copy is
  /// always recoverable if this is interrupted partway through. Order:
  ///
  /// 1. Write [legacy] to the journal account, under the *current*
  ///    accessibility. A distinct account name, so step 3's delete (which
  ///    is account-wide on [storageKey] — see below) cannot touch it.
  /// 2. Delete the old item. `flutter_secure_storage_darwin`'s
  ///    `performDelete` clears `accessibilityLevel` off the query before
  ///    calling `SecItemDelete` (see `FlutterSecureStorage.swift`), so
  ///    `iOptions`/`accessibilityLevel` is *not* a matching constraint on
  ///    delete the way it is on read/write — a delete call is account-wide
  ///    and removes whichever item is currently stored for [storageKey],
  ///    regardless of which `iOptions` accessibility was passed. That is
  ///    exactly why the journal in step 1 has to live under a *different*
  ///    account name: writing the final copy to [storageKey] before this
  ///    delete would just have this delete wipe it out again.
  /// 3. Write [legacy] to [storageKey] under the current accessibility —
  ///    now safe, since the account-wide delete already ran.
  /// 4. Delete the journal entry.
  ///
  /// If the process is killed, a write throws, or a write fails because the
  /// device is locked (deterministic when migrating from
  /// `first_unlock_this_device`, since a locked-device write to a
  /// `ThisDeviceOnly`-after-first-unlock item can fail) at any point in
  /// this sequence, at least one of {the legacy item, the journal, the
  /// final item} still holds the key. [_resumeInterruptedMigration] cleans
  /// up and recovers from every one of those partial states on the next
  /// call.
  Future<String> _migrate(String legacy, IOSOptions legacyOptions) async {
    await _storage.write(key: migratingStorageKey, value: legacy);
    await _storage.delete(key: storageKey, iOptions: legacyOptions);
    await _storage.write(key: storageKey, value: legacy);
    await _storage.delete(key: migratingStorageKey);
    return legacy;
  }

  /// Checks for a journal entry left behind by a [_migrate] call that did
  /// not finish, and finishes it. Returns the recovered key, or `null` when
  /// there was nothing to resume (the common case, checked on every call).
  ///
  /// Safe to call unconditionally: if the final write already landed (the
  /// process died between steps 3 and 4 above), this just finishes the
  /// leftover cleanup — the journal and any still-present legacy copies —
  /// and returns the key that was already there. If the final write never
  /// landed (died between steps 1 and 3), this recovers the key from the
  /// journal into [storageKey] before cleaning up.
  Future<String?> _resumeInterruptedMigration() async {
    final journaled = await _storage.read(key: migratingStorageKey);
    if (journaled == null) return null;
    if (!isValidDbKeyHex(journaled)) {
      throw const CorruptDatabaseKeyError();
    }

    final current = await _storage.read(key: storageKey);
    if (current != null && !isValidDbKeyHex(current)) {
      throw const CorruptDatabaseKeyError();
    }

    if (current == null) {
      // The final write (step 3) never landed. A legacy copy may or may not
      // still exist depending on exactly where the interruption happened
      // (deleting an already-absent item is a no-op on the real plugin),
      // but it must be cleared *before* writing the recovered value to
      // [storageKey] — delete there is account-wide (see [_migrate]'s doc
      // comment), so running it after this write would erase the write.
      for (final legacyOptions in legacyIOSOptions) {
        await _storage.delete(key: storageKey, iOptions: legacyOptions);
      }
      await _storage.write(key: storageKey, value: journaled);
    }
    // else: the final write already landed (only step 4's journal cleanup
    // was missed). The legacy copy is already gone by construction — the
    // `_migrate` sequence deletes it strictly before writing the final
    // value — so touching [storageKey] again here would only risk wiping
    // the good value that is already in place.

    await _storage.delete(key: migratingStorageKey);
    return current ?? journaled;
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
