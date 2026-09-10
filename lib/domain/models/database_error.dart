/// Typed fail-closed database-open error, owned by the domain so the UI can
/// pattern-match it without importing `lib/data`.
///
/// Deliberately a standalone type (not an [Exception] subclass of a common
/// base) so callers cannot accidentally catch-and-continue: it means "stop;
/// do not use the database".
library;

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
