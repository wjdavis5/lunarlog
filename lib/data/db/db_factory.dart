/// The one database factory seam.
///
/// [LunarLogDbFactory] is platform-agnostic: it owns key handling, the
/// fail-closed cipher assertion, and the quarantine-on-failed-open policy.
/// Platform wiring is injected:
///
/// * `native_db.dart` (mobile/desktop): SQLCipher-encrypted [QueryExecutor]
///   over a file, fed by a [DbKeyStore].
/// * `web_db.dart` (web): unencrypted [QueryExecutor] over WASM/IndexedDB —
///   no key store is ever provided or consulted there.
library;

import 'dart:async';

import 'package:drift/drift.dart';

import 'db.dart';
import 'errors.dart';
import 'key_store.dart';

/// Builds the encrypted executor given the install's database key (hex).
typedef EncryptedExecutorBuilder = FutureOr<QueryExecutor> Function(
    String dbKeyHex);

/// Builds an unencrypted executor (web, tests).
typedef PlainExecutorBuilder = FutureOr<QueryExecutor> Function();

/// Pure, testable core of the startup cipher assertion: fails closed with
/// [EncryptionUnavailableError] unless the first-column result of
/// `PRAGMA cipher_version` (or equivalent probe) reports an active cipher.
///
/// An empty/null probe means the running SQLite library has no encryption
/// support — the database would be written unencrypted, which is never
/// acceptable for this app.
void assertCipherActive(Iterable<Object?> cipherVersionFirstColumn) {
  final active = cipherVersionFirstColumn
      .any((value) => value != null && value.toString().isNotEmpty);
  if (!active) {
    throw const EncryptionUnavailableError();
  }
}

class LunarLogDbFactory {
  const LunarLogDbFactory({
    required this.databasePath,
    required this.requireEncryption,
    this.keyStore,
    this.encryptedExecutorBuilder,
    this.plainExecutorBuilder,
    this.existingFileCheck,
    this.preflight,
  })  : assert(
          !requireEncryption ||
              (keyStore != null && encryptedExecutorBuilder != null),
          'encrypted opens need a key store and an executor builder',
        ),
        assert(!requireEncryption || plainExecutorBuilder == null,
            'unencrypted executor builder must not be set in encrypted mode'),
        assert(requireEncryption || plainExecutorBuilder != null,
            'unencrypted opens need a plain executor builder');

  /// Path or label of the database (used in error messages).
  final String databasePath;

  /// Whether the open must produce an encrypted database. True on mobile;
  /// always false on web (browser storage is the platform's responsibility
  /// and key material is never touched there).
  final bool requireEncryption;

  /// Key storage. Only ever consulted when [requireEncryption] is true.
  final DbKeyStore? keyStore;

  final EncryptedExecutorBuilder? encryptedExecutorBuilder;
  final PlainExecutorBuilder? plainExecutorBuilder;

  /// Whether the database file already exists before this open. When an
  /// existing file fails to open/migrate, the failure becomes a typed
  /// [DatabaseQuarantineError] (fail-closed: never wiped or recreated).
  /// Null means "cannot tell / not file-backed" (web), treated as
  /// first-run.
  final Future<bool> Function()? existingFileCheck;

  /// Optional platform preflight run before touching key storage or the
  /// database (used for the native SQLCipher library probe).
  final FutureOr<void> Function()? preflight;

  /// Opens the database. Throws:
  /// * [EncryptionUnavailableError] — no cipher support in the SQLite build
  ///   (encrypted mode only). Thrown before any file is created or key
  ///   generated.
  /// * [CorruptDatabaseKeyError] — persisted key malformed (never rewritten).
  /// * [DatabaseQuarantineError] — an existing database file failed to open
  ///   or migrate; the file is left untouched.
  Future<LunarLogDatabase> open() async {
    if (preflight != null) {
      await preflight!();
    }
    final String? key;
    if (requireEncryption) {
      final fetched = await keyStore!.getOrCreateDbKey();
      if (!isValidDbKeyHex(fetched)) {
        // Fail closed regardless of the key-store implementation; never
        // fall back to generating a new key over an existing store.
        throw const CorruptDatabaseKeyError();
      }
      key = fetched;
    } else {
      key = null;
    }
    final existingFile =
        existingFileCheck == null ? false : await existingFileCheck!();

    final QueryExecutor executor;
    if (requireEncryption) {
      executor = await encryptedExecutorBuilder!(key!);
    } else {
      executor = await plainExecutorBuilder!();
    }
    final db = LunarLogDatabase(executor);
    try {
      // Forces drift to open the executor, apply the setup PRAGMAs, run
      // migrations and verify the file is readable. For an encrypted
      // database over an existing file, a wrong key or corruption surfaces
      // here as a SqliteException.
      await db.customSelect('SELECT 1').get();
    } on EncryptionUnavailableError {
      await db.close();
      rethrow;
    } catch (cause) {
      await db.close();
      if (existingFile) {
        throw DatabaseQuarantineError(databasePath, cause);
      }
      rethrow;
    }
    return db;
  }
}
