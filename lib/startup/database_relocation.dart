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
/// after re-verifying the promoted target itself, only once every rename
/// has succeeded; its presence is what "this target is a genuinely
/// complete relocation" means.
///
/// If anything throws at any point in the staging/verify/promote/re-verify
/// sequence, every staging file and anything already promoted to the
/// target is deleted, and the legacy file is left untouched:
/// [relocateLegacyDatabase] returns [legacyFile] rather than rethrowing, so
/// the caller opens the pre-migration data instead of a corrupt or partial
/// copy. The next startup's call retries cleanly from the same state (no
/// sentinel, no partial target, legacy file still there).
///
/// ## The sentinel is a shortcut, not a lock (round 3)
///
/// A target that exists without the sentinel is **not** automatically
/// "an interrupted previous attempt" — a target-first guard used to
/// assume so and `deleteDatabaseFiles` any such target unconditionally,
/// which silently wiped a fresh install's database on its *second*
/// launch (a fresh install creates its database directly at the target
/// and never goes through this function at all, so it never earns a
/// sentinel). The rule, checked legacy-file-first:
///
/// * No legacy file: there is nothing to migrate from, so a target that
///   independently opens and passes `PRAGMA quick_check` is left
///   untouched (and gets the sentinel written retroactively, so the next
///   launch short-circuits immediately) — this covers both a fresh
///   install and a device whose migration already fully completed. Only
///   a target that isn't even an openable database — genuine residue, not
///   live data — is cleared.
/// * Legacy file present and the target carries the sentinel: the target
///   is authoritative and is never rewritten; only a best-effort legacy
///   cleanup happens (a killed process between the sentinel write and the
///   legacy delete below can otherwise leave a plaintext copy in the
///   iCloud-backed `Documents/` directory forever).
/// * Legacy file present, target exists, no sentinel: adopt the target in
///   place (write the sentinel, skip re-copying, clean up the legacy
///   file) if it independently verifies against the legacy database —
///   most likely a completed relocation whose sentinel write itself got
///   interrupted. Otherwise it really is residue from an interrupted
///   attempt: it is cleared and the staging/verify/promote sequence below
///   runs fresh from the legacy file.
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

/// Every user-defined table name in [db]'s `sqlite_master` (`sqlite_%`
/// internal tables excluded — those are covered by the `sqlite_master`
/// count itself). Returns an empty list if the query fails for any reason
/// (e.g. [db] is not actually a valid database) rather than throwing —
/// callers already fold that into "does not verify".
List<String> _tableNames(sqlite3.Database db) {
  try {
    final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite\\_%' ESCAPE '\\'",
    );
    return [for (final row in rows) row['name'] as String];
  } catch (_) {
    return const [];
  }
}

/// Issue #244 round 2 (broadened round 3): the strengthened "is this
/// staged copy actually intact" check, replacing the original "does
/// sqlite3 open it" probe (which passed for a copy that opened fine but
/// had silently dropped rows). Runs `PRAGMA quick_check` on [stagedFile]
/// (must report exactly `ok`) and then compares row/object counts between
/// [legacyFile] and [stagedFile] across `sqlite_master` (schema-level: the
/// same tables/indexes exist) plus **every** user-defined table
/// [legacyFile] itself lists in its `sqlite_master` — round 2 checked only
/// `profiles`/`day_entries` by name, which silently waved through a
/// dropped row in any other table (e.g. `cycle_notes`).
///
/// Also used, unchanged, to check whether an un-sentineled target found
/// beside a still-present legacy file (see the library doc comment's
/// "round 3" section) is actually a match worth adopting in place rather
/// than residue to discard — [stagedFile] need not literally be a
/// `.migrating`-named staging file for this check to apply.
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

    final tables = {'sqlite_master', ..._tableNames(legacyDb)};
    for (final table in tables) {
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

/// Standalone `PRAGMA quick_check` probe with no legacy database to
/// compare against — used only for the no-legacy branch of
/// [relocateLegacyDatabase] (round 3's fix for finding #1), where the
/// question is just "is this target itself an intact, openable database",
/// not "does it match some other file".
bool _passesQuickCheck(File dbFile) {
  sqlite3.Database? db;
  try {
    db = sqlite3.sqlite3.open(dbFile.path);
    final quickCheck = db.select('PRAGMA quick_check');
    return quickCheck.isNotEmpty && quickCheck.first.values.first == 'ok';
  } catch (_) {
    return false;
  } finally {
    db?.close();
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

  if (!await legacyFile.exists()) {
    return _handleNoLegacy(targetFile: targetFile, sentinel: sentinel);
  }

  if (await sentinel.exists()) {
    return _handleAlreadyMigrated(legacyFile: legacyFile, targetFile: targetFile);
  }

  if (await targetFile.exists()) {
    // Legacy present, target present, no sentinel: this is either residue
    // from an interrupted previous attempt, or a completed relocation
    // whose sentinel write itself got interrupted (indistinguishable
    // except by actually checking the data). Adopt it in place if it
    // verifies; otherwise clear it and re-migrate from legacy below.
    final adopted = await _tryAdoptUnsentinelledTarget(
      legacyFile: legacyFile,
      targetFile: targetFile,
      sentinel: sentinel,
    );
    if (adopted != null) return adopted;
  }

  return _migrateFromLegacy(
    legacyFile: legacyFile,
    targetFile: targetFile,
    sentinel: sentinel,
    copier: copier,
  );
}

/// No legacy file: nothing to migrate from. Only cleans up
/// interrupted-attempt staging leftovers — never deletes a promoted target
/// just because it lacks the sentinel: this is the normal state for both a
/// fresh install (which creates its database directly at the target and
/// never earns a sentinel) and a device whose migration already fully
/// completed. See the library doc comment's "round 3" section.
Future<File> _handleNoLegacy({
  required File targetFile,
  required File sentinel,
}) async {
  await _deleteStagingFiles(targetFile);
  if (await targetFile.exists()) {
    if (_passesQuickCheck(targetFile)) {
      if (!await sentinel.exists()) {
        // Retroactively mark this target as done so the next launch
        // short-circuits immediately instead of re-running this check.
        await sentinel.writeAsString(DateTime.now().toUtc().toIso8601String());
      }
    } else {
      // Not even an openable database, and there is no legacy copy to
      // fall back to — genuine residue from a broken previous attempt.
      // Clear it so ordinary DB-open machinery creates a fresh, empty
      // database here, same as any other fresh install.
      await deleteDatabaseFiles(targetFile);
      if (await sentinel.exists()) await sentinel.delete();
    }
  }
  return targetFile;
}

/// A prior call completed the whole sequence; the target is authoritative
/// and is never rewritten. Best-effort clean up a legacy copy that might
/// have survived a process killed between the sentinel write and this
/// delete (finding #2) — otherwise it lingers forever, in plaintext, in
/// the iCloud-backed `Documents/` directory.
Future<File> _handleAlreadyMigrated({
  required File legacyFile,
  required File targetFile,
}) async {
  try {
    await deleteDatabaseFiles(legacyFile);
  } catch (_) {
    // Best effort only — see the promotion path's own comment.
  }
  return targetFile;
}

/// Verifies an un-sentinelled target found beside a still-present legacy
/// file against that legacy database and, if it matches, adopts it in
/// place (sentinel written, legacy best-effort cleaned up) — returning the
/// adopted [targetFile]. Otherwise the target is residue from an
/// interrupted attempt: it (and any leftover staging files) is cleared and
/// `null` is returned so the caller re-migrates from legacy.
Future<File?> _tryAdoptUnsentinelledTarget({
  required File legacyFile,
  required File targetFile,
  required File sentinel,
}) async {
  if (_verifyStagedDatabase(legacyFile: legacyFile, stagedFile: targetFile)) {
    await sentinel.writeAsString(DateTime.now().toUtc().toIso8601String());
    try {
      await deleteDatabaseFiles(legacyFile);
    } catch (_) {
      // Best effort only — see above.
    }
    return targetFile;
  }
  await deleteDatabaseFiles(targetFile);
  await _deleteStagingFiles(targetFile);
  return null;
}

/// The staging/verify/promote/re-verify/sentinel sequence — see the
/// library doc comment's "Crash safety" section. Returns [targetFile] once
/// the sentinel has been durably written, or [legacyFile] if anything in
/// the sequence threw (staging, promotion, and the sentinel are all rolled
/// back by [_rollbackFailedMigration] in that case).
Future<File> _migrateFromLegacy({
  required File legacyFile,
  required File targetFile,
  required File sentinel,
  required DatabaseFileCopier copier,
}) async {
  final targetDir = targetFile.parent;
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  final stagedBySuffix = <String, File>{};
  try {
    await _stageLegacySiblings(
      legacyFile: legacyFile,
      targetFile: targetFile,
      copier: copier,
      stagedBySuffix: stagedBySuffix,
    );

    final stagedMain = stagedBySuffix[''];
    if (stagedMain == null ||
        !_verifyStagedDatabase(legacyFile: legacyFile, stagedFile: stagedMain)) {
      throw StateError('relocated database failed verification');
    }

    await _promoteStagedFiles(stagedBySuffix, targetFile);
    stagedBySuffix.clear(); // promoted — the catch block must not re-delete these.

    // Finding #4: re-verify the promoted file itself (both verification
    // connections above are already closed by _verifyStagedDatabase's own
    // `finally`) before considering the relocation durable. This catches
    // anything a rename-time filesystem inconsistency could have
    // introduced that verifying the pre-promotion staged copy couldn't. A
    // failure here throws into the catch block below exactly like any
    // other failure in this sequence — it rolls the promotion back
    // (deletes what was just promoted to the target) and falls back to
    // the still-untouched legacy file, it does **not** leave a half-valid
    // target in place.
    await _verifyPromotedDatabase(targetFile);

    // Sentinel last, only once every rename above and the re-verification
    // above have succeeded. Once this write succeeds, the relocation
    // itself is complete and durable.
    await sentinel.writeAsString(DateTime.now().toUtc().toIso8601String());
  } catch (_) {
    await _rollbackFailedMigration(stagedBySuffix, targetFile, sentinel);
    return legacyFile;
  }

  return _finishMigration(legacyFile, targetFile);
}

/// Copies each existing sibling of [legacyFile] into a `.migrating`-marked
/// staging file beside [targetFile], recording each in [stagedBySuffix]
/// (mutated in place so the caller's `catch` block still sees whatever was
/// staged before a failure).
Future<void> _stageLegacySiblings({
  required File legacyFile,
  required File targetFile,
  required DatabaseFileCopier copier,
  required Map<String, File> stagedBySuffix,
}) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    if (suffix == '-shm') {
      // The -shm file is a memory-mapped WAL index, process-local and not
      // portable by copying — sqlite rebuilds it from the -wal file on
      // next open, so any content that matters is already reflected
      // there. Copying it could hand the target a stale/foreign
      // shared-memory image instead. Just make sure no stale -shm
      // survives at the target from an earlier run.
      final staleTargetShm = File('${targetFile.path}$suffix');
      if (await staleTargetShm.exists()) {
        await staleTargetShm.delete();
      }
      continue;
    }
    final source = File('${legacyFile.path}$suffix');
    if (!await source.exists()) continue;
    final stagingFile = _stagingFileFor(targetFile, suffix);
    await copier(source, stagingFile);
    stagedBySuffix[suffix] = stagingFile;
  }
}

/// Renames each staged file in [stagedBySuffix] into place beside
/// [targetFile] (same directory/volume, so the rename is atomic).
Future<void> _promoteStagedFiles(
  Map<String, File> stagedBySuffix,
  File targetFile,
) async {
  for (final entry in stagedBySuffix.entries) {
    if (!await entry.value.exists()) {
      // Verification's own sqlite3 open of the staged main file (in
      // [_migrateFromLegacy]) can itself consume this sidecar — e.g. a
      // real `-wal` gets checkpointed into the main file and removed as
      // an ordinary consequence of SQLite opening a WAL-mode database, or
      // an invalid one gets discarded during WAL-index recovery. Either
      // way its content (if any was real) is already reflected in the
      // staged main file that just passed verification, so there is
      // nothing left here to promote.
      continue;
    }
    final promotedPath = '${targetFile.path}${entry.key}';
    await entry.value.rename(promotedPath);
  }
}

/// Standalone `PRAGMA quick_check` re-verification of the just-promoted
/// [targetFile], throwing if it fails — see the "Finding #4" comment at
/// the call site in [_migrateFromLegacy].
Future<void> _verifyPromotedDatabase(File targetFile) async {
  sqlite3.Database? promotedDb;
  try {
    promotedDb = sqlite3.sqlite3.open(targetFile.path);
    final quickCheck = promotedDb.select('PRAGMA quick_check');
    if (quickCheck.isEmpty || quickCheck.first.values.first != 'ok') {
      throw StateError('promoted database failed post-promotion verification');
    }
  } finally {
    promotedDb?.close();
  }
}

/// Crash-safety rollback for a failed [_migrateFromLegacy] attempt:
/// removes every remaining staging file plus anything already promoted to
/// [targetFile], and drops the sentinel if one was somehow written — the
/// legacy file itself is left untouched, per [relocateLegacyDatabase]'s
/// return-value doc.
Future<void> _rollbackFailedMigration(
  Map<String, File> stagedBySuffix,
  File targetFile,
  File sentinel,
) async {
  for (final stagingFile in stagedBySuffix.values) {
    if (await stagingFile.exists()) await stagingFile.delete();
  }
  await deleteDatabaseFiles(targetFile);
  if (await sentinel.exists()) await sentinel.delete();
}

/// The relocation is complete and durable (sentinel already written by the
/// caller). Deleting the legacy file from here on is tidying, not safety,
/// so it gets its own try/catch that never undoes the promotion: a
/// failure here (the file still open elsewhere, a permission error, …)
/// leaves a harmless leftover — the *next* call sees the sentinel and
/// returns immediately without touching legacyFile again (the no-op
/// branch at the top of [relocateLegacyDatabase]).
Future<File> _finishMigration(File legacyFile, File targetFile) async {
  try {
    await deleteDatabaseFiles(legacyFile);
  } catch (_) {
    // Best effort only — see above.
  }
  return targetFile;
}
