/// Native (mobile/desktop) database wiring: SQLCipher encryption at rest.
///
/// Expects the `sqlite3` package's native build hook to bundle SQLCipher
/// (pubspec: `hooks: user_defines: sqlite3: source: sqlcipher`). The factory
/// fail-closes via [EncryptionUnavailableError] if the loaded library lacks
/// cipher support — the app must never continue with an unencrypted file.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'db_factory.dart';
import 'errors.dart';
import 'key_store.dart';

/// Probes whether the SQLite library loaded into this process (isolate) has
/// SQLCipher support, using an in-memory database — before any real file is
/// opened or key material generated. Throws [EncryptionUnavailableError] if
/// not. Runs on the caller's isolate; the same native library is used by
/// drift's background isolate, and [_applyCipherKey] re-asserts there
/// (defense in depth).
void assertSqlcipherAvailable() {
  final memory = sqlite3.sqlite3.openInMemory();
  try {
    assertCipherActive(
        memory.select('PRAGMA cipher_version').map((row) => row.values.first));
  } finally {
    memory.close();
  }
}

void _applyCipherKey(sqlite3.Database rawDb, String dbKeyHex) {
  // Fail closed if this isolate's library somehow lacks cipher support.
  assertCipherActive(
      rawDb.select('PRAGMA cipher_version').map((row) => row.values.first));
  // Raw 32-byte key, hex form. Applied before drift reads anything.
  rawDb.execute("PRAGMA key = \"x'$dbKeyHex'\";");
}

/// Factory for native platforms.
///
/// * [requireEncryption] defaults to true — the app's supported mode. Host
///   logic tests may pass false to exercise plain in-memory/file databases
///   where the SQLCipher hook does not apply.
LunarLogDbFactory nativeDbFactory({
  required File file,
  required DbKeyStore keyStore,
  bool requireEncryption = true,
}) {
  return LunarLogDbFactory(
    databasePath: file.path,
    requireEncryption: requireEncryption,
    keyStore: keyStore,
    preflight: requireEncryption ? assertSqlcipherAvailable : null,
    existingFileCheck: file.exists,
    encryptedExecutorBuilder: requireEncryption
        ? (dbKeyHex) => NativeDatabase.createInBackground(
              file,
              setup: (rawDb) => _applyCipherKey(rawDb, dbKeyHex),
            )
        : null,
    plainExecutorBuilder: requireEncryption
        ? null
        : () => NativeDatabase.createInBackground(file),
  );
}
