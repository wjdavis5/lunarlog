/// Native (mobile/desktop) startup wiring for the database factory: a file
/// in Application Support (issue #244 — moved off `Documents/`, which is
/// included in iOS device/iCloud backup by default; Application Support is
/// not), opened by U2's factory (fail-closed on an existing file that won't
/// open). Also the native half of the device-reset primitives (KTD16).
library;

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The one database file this install uses.
Future<File> localDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// Where this install's database lived before issue #244 — `Documents/`.
/// Only consulted by [relocateLegacyDatabase]; never opened directly.
Future<File> _legacyDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// Runs the one-time relocation (issue #244) before wiring the factory to
/// [localDatabaseFile]. Callers apply [protectDatabaseFile] themselves after
/// `.open()` succeeds (see `main.dart`) — the file is only guaranteed to
/// exist on disk once `LunarLogDbFactory.open()`'s own `SELECT 1` probe has
/// run, which this function cannot see from in here.
Future<LunarLogDbFactory> buildDbFactory() async {
  final target = await localDatabaseFile();
  await relocateLegacyDatabase(
    legacyFile: await _legacyDatabaseFile(),
    targetFile: target,
  );
  return nativeDbFactory(file: target);
}

/// Deletes this install's database file and its `-wal`, `-shm` and
/// `-journal` siblings. A device-reset primitive only: the caller
/// (`resetDevice`, KTD16) must have closed the database first. Nothing else
/// is touched.
Future<void> deleteLocalDatabase() async =>
    deleteDatabaseFiles(await localDatabaseFile());

/// Sibling suffixes sqlite may leave beside a database file.
const List<String> kDatabaseSiblingSuffixes = ['', '-wal', '-shm', '-journal'];

/// [deleteLocalDatabase] for an explicit [dbFile] (testable without the
/// platform's documents directory). Missing files are skipped.
Future<void> deleteDatabaseFiles(File dbFile) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    final sibling = File('${dbFile.path}$suffix');
    if (await sibling.exists()) {
      await sibling.delete();
    }
  }
}

/// One-time startup migration (issue #244): moves a pre-#244 install's
/// `Documents/lunarlog.db` (and whichever of its `-wal`/`-shm`/`-journal`
/// siblings exist) to [targetFile]'s directory (Application Support).
/// Idempotent and safe to call on every startup:
///
/// * No-op when [targetFile] already exists — a prior run already migrated
///   (or this is a fresh install that never had a legacy file), and this
///   run must never clobber a target a previous run already verified
///   openable.
/// * No-op when there is nothing at [legacyFile].
/// * Otherwise: copies every existing sibling to the target directory
///   (creating it if needed), opens the copied main file with a raw sqlite3
///   handle to verify it is actually a readable database, and only *then*
///   deletes the legacy siblings — "never delete the old file until the new
///   one is verified openable". A copy or verify failure rolls back the
///   partial copy at the target and leaves the legacy file untouched, so a
///   later startup retries from a clean slate instead of being stuck behind
///   a half-populated target that would make the first bullet above
///   short-circuit every future attempt.
///
/// This only moves files; it never opens [targetFile] through drift, so it
/// cannot itself trigger [LunarLogDbFactory]'s quarantine path — a
/// corrupt-but-openable-by-sqlite3 legacy file would still migrate and then
/// surface as a normal quarantine on the next real open, exactly as it
/// would have at the old path.
@visibleForTesting
Future<void> relocateLegacyDatabase({
  required File legacyFile,
  required File targetFile,
}) async {
  if (await targetFile.exists()) return;
  if (!await legacyFile.exists()) return;

  final targetDir = targetFile.parent;
  if (!await targetDir.exists()) {
    await targetDir.create(recursive: true);
  }

  await _copyDatabaseSiblings(from: legacyFile, to: targetFile);

  if (await _isOpenableDatabase(targetFile)) {
    // Never delete the old file until the new one is verified openable.
    await deleteDatabaseFiles(legacyFile);
  } else {
    // Roll back the partial copy — reusing [deleteDatabaseFiles] deletes
    // exactly whichever siblings [_copyDatabaseSiblings] managed to create
    // at the target before the failure, so a later startup sees a clean
    // slate at both ends and retries from scratch instead of being stuck
    // behind a half-populated target (which would make the first bullet
    // above short-circuit every future attempt).
    await deleteDatabaseFiles(targetFile);
  }
}

/// Copies every existing `[legacyFile-suffix]` sibling (main file plus
/// whichever of [kDatabaseSiblingSuffixes] exist) to the matching path under
/// [to]. A missing sibling is simply skipped.
Future<void> _copyDatabaseSiblings({required File from, required File to}) async {
  for (final suffix in kDatabaseSiblingSuffixes) {
    final source = File('${from.path}$suffix');
    if (!await source.exists()) continue;
    await source.copy('${to.path}$suffix');
  }
}

/// Whether [file] is a real, readable sqlite database — the "never delete
/// the old file until the new one is verified openable" check for
/// [relocateLegacyDatabase]. `sqlite3.open` alone does not validate the file
/// format (that happens lazily, on first access), so this runs a cheap read
/// to force it.
Future<bool> _isOpenableDatabase(File file) async {
  try {
    final raw = sqlite3.sqlite3.open(file.path);
    try {
      raw.select('PRAGMA schema_version');
    } finally {
      raw.close();
    }
    return true;
  } catch (_) {
    return false;
  }
}

/// Platform channel shared with Android's FLAG_SECURE hardening
/// (`app_lifecycle.dart`'s `applyPlatformPrivacyProtections` /
/// `MainActivity.kt`'s `setFlagSecure`) — same channel name, an additional
/// iOS-only method.
const String _kPrivacyChannel = 'lunarlog/privacy';

/// iOS-only, best-effort file hardening for the database (issue #244):
/// excludes it (and its `-wal`/`-shm`/`-journal` siblings) from iCloud/device
/// backup (`NSURLIsExcludedFromBackupKey`) and marks them
/// `NSFileProtectionComplete` (unreadable while the device is locked), via a
/// tiny platform channel to `AppDelegate.swift` — the same shape as
/// Android's `setFlagSecure` channel in `MainActivity.kt`. Called after every
/// successful database open (`main.dart`'s `dbOpener`, including a
/// device-reset reopen — KTD16 — which creates a fresh file that needs the
/// same protection reapplied).
///
/// **Why `Complete`, not `CompleteUntilFirstUserAuthentication`:** the gate
/// (`lib/data/gate/`) already keeps the database closed until the operator
/// unlocks the app (AE4) — nothing opens or writes to this file before that
/// happens on any code path today, including sync (`SupabaseSyncEngine`
/// only starts once the database is open). So there is no existing path
/// that expects to write to this file while the device is locked, and
/// `Complete`'s stricter class (inaccessible until the *next* unlock, not
/// just the first one since boot) costs nothing on top of that invariant.
/// If a future change adds a write path that must run before the operator
/// has unlocked the app at all this boot (e.g. a background push handler
/// that touches the database directly, bypassing the gate), that path would
/// start failing under `Complete` and this choice should be revisited
/// then — `CompleteUntilFirstUserAuthentication` plus the backup exclusion
/// above would be the safer pick for that case, since it only weakens
/// at-rest protection for the stretch between boot and the device's own
/// first unlock (a window this app's gate never operates in anyway, since
/// the app's own credential prompt requires the device to already be
/// unlocked).
///
/// Best effort: a failure here (channel missing, `FileManager` error) is
/// swallowed exactly like `applyPlatformPrivacyProtections` swallows a
/// FLAG_SECURE failure — the Application Support directory move (not backed
/// up by default) is the primary control; this is belt-and-suspenders on
/// top of it, not the only thing standing between the file and a backup.
Future<void> protectDatabaseFile() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    final file = await localDatabaseFile();
    await const MethodChannel(_kPrivacyChannel).invokeMethod<void>(
      'protectDatabaseFile',
      <String, String>{'path': file.path},
    );
  } catch (_) {
    // Best effort only.
  }
}
