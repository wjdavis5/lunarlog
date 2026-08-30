/// Typed fail-closed errors for the encrypted data layer.
///
/// These are deliberately separate types (not [Exception] subclasses of a
/// common base) so callers cannot accidentally catch-and-continue: every one
/// of these means "stop; do not use the database".
library;

/// The active SQLite library has no encryption support (the
/// `source: sqlcipher` build hook did not take effect), so the database would
/// be stored unencrypted. Thrown before any database file is opened.
class EncryptionUnavailableError implements Exception {
  const EncryptionUnavailableError([this.message]);

  final String? message;

  @override
  String toString() =>
      'EncryptionUnavailableError${message == null ? '' : ': $message'}: '
      'the SQLite library in use has no SQLCipher support; refusing to open '
      'or create an unencrypted database (check the sqlite3 hook config)';
}

/// Opening or migrating an *existing* database file failed. The file is left
/// exactly as it was — never wiped, never recreated. The operator must decide
/// what to do with it (quarantine/restore/recover).
class DatabaseQuarantineError implements Exception {
  DatabaseQuarantineError(this.path, this.cause);

  /// Path (or label) of the database that failed to open.
  final String path;

  /// The underlying failure.
  final Object cause;

  @override
  String toString() =>
      'DatabaseQuarantineError: refusing to open existing database "$path" '
      '($cause); the file was left untouched';
}

/// The persisted database key exists but is malformed. Never regenerated or
/// overwritten: a new key would make the existing encrypted database
/// permanently unreadable.
class CorruptDatabaseKeyError implements Exception {
  const CorruptDatabaseKeyError();

  @override
  String toString() => 'CorruptDatabaseKeyError: the persisted database key '
      'is malformed; refusing to overwrite it';
}
