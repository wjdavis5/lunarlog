/// Pure, platform-independent database-relocation logic for issue #244's
/// one-time move off the pre-#244 `Documents/lunarlog.db` path — split out
/// of `lib/startup/startup_native.dart` (round 2 review) so it can be
/// tested directly and stays out of `tool/quality/exclusions.dart`: unlike
/// `protectDatabaseFile` (an iOS-only platform-channel call that cannot run
/// under `flutter test`), everything here is ordinary `dart:io`/`sqlite3`
/// logic over explicit [File] arguments with no `path_provider`
/// dependency. See `tool/quality/exclusions.dart` for why
/// `startup_native.dart` itself stays excluded while this file does not.
///
/// ## Crash safety
///
/// [relocateLegacyDatabase] never mutates [targetFile] or [legacyFile] in
/// place. It stages every sibling under a `.migrating`-marked name in the
/// target directory, verifies the staged copy against the legacy database
/// ([_verifyStagedDatabase] — a `PRAGMA quick_check` plus row/object-count
/// comparisons, not just "does sqlite3 open it"), and only then promotes
/// each staged file into place with an atomic [File.rename] (same
/// directory, same volume — Application Support always is here, so the
/// rename is atomic). A [kRelocationSentinelName] file is written *last*,
/// after every rename has succeeded; its presence is what "this target is
/// a genuinely complete relocation" means. A target directory that exists
/// but lacks the sentinel is treated as an interrupted previous attempt,
/// never as "already done" — the old idempotency check ("does the target
/// file exist") could not tell a fully-migrated target from one an earlier
/// crash left half-populated.
///
/// If anything throws at any point in the staging/verify/promote sequence,
/// every staging file and anything already promoted to the target is
/// deleted, and the legacy file is left untouched:
/// [relocateLegacyDatabase] returns [legacyFile] rather than rethrowing, so
/// the caller opens the pre-migration data instead of a corrupt or partial
/// copy. The next startup's call retries cleanly from the same state (no
/// sentinel, no partial target, legacy file still there).
///
/// Staging names are `<target-path>.migrating` for the main file and
/// `<target-path>.migrating<suffix>` for each sibling (e.g.
/// `lunarlog.db.migrating-wal`) — the marker goes *before* the sqlite
/// suffix, not after. This matters, not just for tidiness: sqlite
/// discovers a database's `-wal`/`-shm` sidecars by suffixing the main
/// file's own path, so opening the staged main file directly (as
/// [_verifyStagedDatabase] does, to replay a staged `-wal` the same way a
/// real reopen would) only finds its sidecars if they share that same
/// `<staged-main-path><suffix>` naming — `lunarlog.db-wal.migrating`
/// would not be discovered next to a staged main file named
/// `lunarlog.db.migrating`.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Sibling suffixes sqlite may leave beside a database file.
const List<String> kDatabaseSiblingSuffixes = ['', '-wal', '-shm', '-journal'];

/// Name of the sentinel file written (in [targetFile]'s parent directory)
/// once every staged sibling has been renamed into place — see the library
/// doc comment's "Crash safety" section.
const String kRelocationSentinelName = '.relocation-complete';

/// Marker inserted between a file's own path and its sqlite suffix while a
/// staged copy is in flight, before promotion — see the library doc
/// comment for why it goes before the suffix, not after.
const String _kStagingMarker = '.migrating';

/// Copies [from] to [to]. The seam [relocateLegacyDatabase] calls instead
/// of `File.copy` directly, so a test can substitute a copier that fails
/// partway through the sibling list and assert recovery on the next call.
typedef DatabaseFileCopier = Future<void> Function(File from, File to);

Future<void> _defaultCopier(File from, File to) async {
  await from.copy(to.path);
}

File _sentinelFileFor(File targetFile) => File(
    '${targetFile.parent.path}${Platform.pathSeparator}$kRelocationSentinelName');

/// The staging path for [targetFile]'s `[suffix]` sibling — see the
/// library doc comment for why the marker precedes the suffix.
File _stagingFileFor(File targetFile, String suffix) =>
    File('${targetFile.path}$_kStagingMarker$suffix');

/// Deletes [dbFile] and every existing [kDatabaseSiblingSuffixes] sibling.
/// Missing files are skipped.
Future<void> deleteDatabaseFiles(File dbFile) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    final sibling = File('${dbFile.path}$suffix');
    if (await sibling.exists()) {
      await sibling.delete();
    }
  }
}

/// Deletes every staging file an interrupted [relocateLegacyDatabase] call
/// could have left beside [targetFile]. Missing files are skipped.
Future<void> _deleteStagingFiles(File targetFile) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    final staging = _stagingFileFor(targetFile, suffix);
    if (await staging.exists()) {
      await staging.delete();
    }
  }
}

/// Deletes everything [relocateLegacyDatabase] could ever have left behind
/// for this [legacyFile]/[targetFile] pair: both files' siblings, any
/// leftover staging files, and the sentinel.
///
/// Used by `deleteLocalDatabase` (issue #244 round 2, KTD16) so a device
/// reset cannot resurrect wiped data on its immediate reopen: deleting only
/// the target's siblings (the pre-round-2 behavior) would leave the legacy
/// `Documents/` copy in place for the very next [relocateLegacyDatabase]
/// call to "recover" right back, undoing the wipe.
Future<void> deleteRelocationArtifacts({
  required File legacyFile,
  required File targetFile,
}) async {
  await deleteDatabaseFiles(legacyFile);
  await deleteDatabaseFiles(targetFile);
  await _deleteStagingFiles(targetFile);
  final sentinel = _sentinelFileFor(targetFile);
  if (await sentinel.exists()) {
    await sentinel.delete();
  }
}

/// `SELECT COUNT(*) FROM "$table"` reduced to a nullable count: `null`
/// means [table] does not exist in [db] (e.g. a legacy install predating a
/// schema addition). [_verifyStagedDatabase] treats that as a match only
/// when *both* sides are missing the same table — a table present on one
/// side and missing on the other is exactly the silent-drop this check
/// exists to catch, not something to wave through as "both fine".
int? _tryCount(sqlite3.Database db, String table) {
  try {
    final rows = db.select('SELECT COUNT(*) AS c FROM "$table"');
    return rows.first['c'] as int;
  } catch (_) {
    return null;
  }
}

/// Issue #244 round 2: the strengthened "is this staged copy actually
/// intact" check, replacing the original "does sqlite3 open it" probe
/// (which passed for a copy that opened fine but had silently dropped
/// rows). Runs `PRAGMA quick_check` on [stagedFile] (must report exactly
/// `ok`) and then compares row/object counts between [legacyFile] and
/// [stagedFile] across `sqlite_master` (schema-level: the same
/// tables/indexes exist), `profiles`, and `day_entries` (the two content
/// tables this migration must never silently lose a row from).
///
/// Opening [stagedFile] with sqlite3 replays any staged `-wal` sibling
/// next to it (see the library doc comment on staging-name ordering), so a
/// row committed only to the legacy `-wal` — never checkpointed into the
/// main file — is included in the staged count exactly as it would be for
/// any other WAL-mode reopen.
bool _verifyStagedDatabase({
  required File legacyFile,
  required File stagedFile,
}) {
  sqlite3.Database? legacyDb;
  sqlite3.Database? stagedDb;
  try {
    legacyDb = sqlite3.sqlite3.open(legacyFile.path);
    stagedDb = sqlite3.sqlite3.open(stagedFile.path);

    final quickCheck = stagedDb.select('PRAGMA quick_check');
    if (quickCheck.isEmpty || quickCheck.first.values.first != 'ok') {
      return false;
    }

    for (final table in ['sqlite_master', 'profiles', 'day_entries']) {
      if (_tryCount(legacyDb, table) != _tryCount(stagedDb, table)) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  } finally {
    legacyDb?.close();
    stagedDb?.close();
  }
}

/// One-time startup migration (issue #244): moves a pre-#244 install's
/// [legacyFile] (`Documents/lunarlog.db`, plus whichever of its
/// [kDatabaseSiblingSuffixes] siblings exist) to [targetFile]'s directory
/// (Application Support). See the library doc comment for the full
/// crash-safety design (staging + verify + atomic rename + sentinel).
///
/// Returns the [File] the caller should actually open:
/// * [targetFile] once relocation has completed (this call or a previous
///   one — [kRelocationSentinelName] marks that), or when there was
///   nothing to migrate (no legacy file: a fresh install creates the
///   database at [targetFile] itself, same as before this migration
///   existed).
/// * [legacyFile] if this call's relocation attempt failed for any reason
///   (a copy threw, verification failed, a rename failed) — the caller
///   opens the pre-migration data rather than a corrupt or partial copy.
///   Nothing was promoted and no sentinel was written, so the *next*
///   startup's call sees the same "target absent or cleaned up, legacy
///   present" state and retries from scratch.
///
/// Called by production code (`startup_native.dart`'s `buildDbFactory`, in
/// a different file/library — hence no `@visibleForTesting` here) as well
/// as directly by this file's own tests.
Future<File> relocateLegacyDatabase({
  required File legacyFile,
  required File targetFile,
  DatabaseFileCopier copier = _defaultCopier,
}) async {
  final sentinel = _sentinelFileFor(targetFile);

  if (await targetFile.exists()) {
    if (await sentinel.exists()) {
      // A prior call completed the whole sequence, sentinel included.
      return targetFile;
    }
    // No sentinel: an interrupted previous attempt left this target
    // behind (or, in principle, only the sentinel write itself was
    // interrupted after a fully successful promotion — indistinguishable
    // from here, and safe to treat the same way: clear it and retry).
    await deleteDatabaseFiles(targetFile);
    await _deleteStagingFiles(targetFile);
  }

  if (!await legacyFile.exists()) {
    // Nothing to migrate: a fresh install, or a previous run already
    // completed and removed the legacy file (the sentinel branch above
    // would have already returned in that case).
    return targetFile;
  }

  final targetDir = targetFile.parent;
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  final stagedBySuffix = <String, File>{};
  try {
    for (final suffix in kDatabaseSiblingSuffixes) {
      final source = File('${legacyFile.path}$suffix');
      if (!await source.exists()) continue;
      final stagingFile = _stagingFileFor(targetFile, suffix);
      await copier(source, stagingFile);
      stagedBySuffix[suffix] = stagingFile;
    }

    final stagedMain = stagedBySuffix[''];
    if (stagedMain == null ||
        !_verifyStagedDatabase(legacyFile: legacyFile, stagedFile: stagedMain)) {
      throw StateError('relocated database failed verification');
    }

    for (final entry in stagedBySuffix.entries) {
      if (!await entry.value.exists()) {
        // Verification's own sqlite3 open of the staged main file (above)
        // can itself consume this sidecar — e.g. a real `-wal` gets
        // checkpointed into the main file and removed as an ordinary
        // consequence of SQLite opening a WAL-mode database, or an
        // invalid one gets discarded during WAL-index recovery. Either
        // way its content (if any was real) is already reflected in the
        // staged main file that just passed verification, so there is
        // nothing left here to promote.
        continue;
      }
      final promotedPath = '${targetFile.path}${entry.key}';
      await entry.value.rename(promotedPath);
    }
    stagedBySuffix.clear(); // promoted — the catch block must not re-delete these.

    // Sentinel last, only once every rename above has succeeded. Once this
    // write succeeds, the relocation itself is complete and durable — a
    // failure past this point must never roll it back (see below).
    await sentinel.writeAsString(DateTime.now().toUtc().toIso8601String());
  } catch (_) {
    // Crash-safety: remove every remaining staging file plus anything
    // already promoted to the target, and leave the legacy file
    // untouched — see the return-value doc above.
    for (final stagingFile in stagedBySuffix.values) {
      if (await stagingFile.exists()) await stagingFile.delete();
    }
    await deleteDatabaseFiles(targetFile);
    if (await sentinel.exists()) await sentinel.delete();
    return legacyFile;
  }

  // The relocation is complete and durable (sentinel written above).
  // Deleting the legacy file from here on is tidying, not safety, so it
  // gets its own try/catch that never undoes the promotion: a failure here
  // (the file still open elsewhere, a permission error, …) leaves a
  // harmless leftover — the *next* call sees the sentinel and returns
  // immediately without touching legacyFile again (the no-op branch at the
  // top of this function).
  try {
    await deleteDatabaseFiles(legacyFile);
  } catch (_) {
    // Best effort only — see above.
  }
  return targetFile;
}
