/// The one database factory seam.
///
/// [LunarLogDbFactory] is platform-agnostic: it owns the
/// quarantine-on-failed-open policy. Platform wiring is injected:
///
/// * `native_db.dart` (mobile/desktop): a [QueryExecutor] over a file.
/// * `web_db.dart` (web): a [QueryExecutor] over WASM/IndexedDB.
///
/// Neither platform encrypts the database file itself at the app layer —
/// at-rest protection is the OS's (iOS Data Protection / Android's platform
/// encryption); see docs/ops/ios-export-compliance.md. The device-credential
/// gate (`lib/data/gate/`) is a separate, independent control: it blocks the
/// UI from showing any data until the device owner authenticates, regardless
/// of how the underlying file is stored.
library;

import 'dart:async';

import 'package:drift/drift.dart';

import 'db.dart';
import 'errors.dart';

/// Builds the database's [QueryExecutor].
typedef ExecutorBuilder = FutureOr<QueryExecutor> Function();

class LunarLogDbFactory {
  const LunarLogDbFactory({
    required this.databasePath,
    required this.executorBuilder,
    this.existingFileCheck,
  });

  /// Path or label of the database (used in error messages).
  final String databasePath;

  final ExecutorBuilder executorBuilder;

  /// Whether the database file already exists before this open. When an
  /// existing file fails to open/migrate, the failure becomes a typed
  /// [DatabaseQuarantineError] (fail-closed: never wiped or recreated).
  /// Null means "cannot tell / not file-backed" (web), treated as
  /// first-run.
  final Future<bool> Function()? existingFileCheck;

  /// Opens the database. Throws [DatabaseQuarantineError] if an existing
  /// database file failed to open or migrate; the file is left untouched.
  Future<LunarLogDatabase> open() async {
    final existingFile =
        existingFileCheck == null ? false : await existingFileCheck!();

    final executor = await executorBuilder();
    final db = LunarLogDatabase(executor);
    try {
      // Forces drift to open the executor, run migrations and verify the
      // file is readable. For an existing file, corruption surfaces here as
      // a SqliteException.
      await db.customSelect('SELECT 1').get();
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
