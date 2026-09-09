/// Native (mobile/desktop) startup wiring for the database factory: a file
/// in Application Support (issue #244 — moved off `Documents/`, which is
/// included in iOS device/iCloud backup by default; Application Support
/// **is included by default too** — only `tmp/` and `Library/Caches/` are
/// excluded automatically. The directory move is hygiene, not the control:
/// `protectDatabaseFile` below applying `NSURLIsExcludedFromBackupKey`
/// (`AppDelegate.swift`) is what actually keeps the file out of backup on
/// iOS. Android's equivalent is declarative (`android:dataExtractionRules`,
/// `data_extraction_rules.xml`) rather than a runtime call. Opened by U2's
/// factory (fail-closed on an existing file that won't open). Also the
/// native half of the device-reset primitives (KTD16).
library;

import 'dart:async' show unawaited;
import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:lunarlog/app_lifecycle.dart' show kPrivacyChannel;
import 'package:lunarlog/data/db/db_factory.dart';
import 'package:lunarlog/data/db/native_db.dart';
import 'package:lunarlog/observability/breadcrumbs.dart';
import 'package:lunarlog/startup/database_relocation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;

/// The one database file this install uses.
Future<File> localDatabaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// Where this install's database lived before issue #244 — `Documents/`.
/// Only consulted by [relocateLegacyDatabase] (via [buildDbFactory]) and
/// [deleteLocalDatabase]; never opened directly.
Future<File> _legacyDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}lunarlog.db');
}

/// Runs the one-time relocation (issue #244; crash-safety hardened in
/// round 2 — see `lib/startup/database_relocation.dart`) before wiring the
/// factory to whichever file the relocation says to open. Callers apply
/// [protectDatabaseFile] themselves after `.open()` succeeds (see
/// `main.dart`) — the file is only guaranteed to exist on disk once
/// `LunarLogDbFactory.open()`'s own `SELECT 1` probe has run, which this
/// function cannot see from in here.
Future<LunarLogDbFactory> buildDbFactory() async {
  final target = await localDatabaseFile();
  final legacy = await _legacyDatabaseFile();
  final fileToOpen =
      await relocateLegacyDatabase(legacyFile: legacy, targetFile: target);
  if (fileToOpen.path == legacy.path) {
    // Round 2: relocation was attempted and failed verification (or a
    // staging copy/rename threw) — report it (type-only; never a path or
    // content) so a systematic failure is visible, then fall back to
    // opening the legacy file rather than a possibly-corrupt copy, same
    // as `_openDatabase`'s own U7 catch in `app_lifecycle.dart`.
    defaultBreadcrumbLog.record(
        'startup', 'relocateLegacyDatabase fell back to the legacy file');
    unawaited(Sentry.captureException(
        StateError('relocateLegacyDatabase fell back to the legacy file')));
  }
  return nativeDbFactory(file: fileToOpen);
}

/// Deletes this install's database file and its `-wal`, `-shm` and
/// `-journal` siblings, **and** whatever the issue #244 relocation could
/// have left behind: the legacy `Documents/lunarlog.db` (and its own
/// siblings) and the relocation sentinel. Without also clearing the legacy
/// copy, a device reset (`resetDevice`, KTD16) that only wiped the current
/// (Application Support) file would leave the legacy file in place for the
/// very next [buildDbFactory] call to "recover" right back — resurrecting
/// the wiped data on the immediate reopen that follows a reset.
///
/// A device-reset primitive only: the caller must have closed the database
/// first. Nothing else is touched.
Future<void> deleteLocalDatabase() async => deleteRelocationArtifacts(
      legacyFile: await _legacyDatabaseFile(),
      targetFile: await localDatabaseFile(),
    );

/// iOS-only, best-effort file hardening for the database (issue #244):
/// excludes it (and its `-wal`/`-shm`/`-journal` siblings, plus the
/// containing directory itself — round 2) from iCloud/device backup
/// (`NSURLIsExcludedFromBackupKey`) and marks them `NSFileProtectionComplete`
/// (unreadable while the device is locked), via a tiny platform channel to
/// `AppDelegate.swift` — the same shape as Android's `setFlagSecure`
/// channel in `MainActivity.kt`. Called after every successful database
/// open (`main.dart`'s `dbOpener`, including a device-reset reopen — KTD16
/// — which creates a fresh file that needs the same protection reapplied).
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
/// Best effort in the sense that a failure here never stops the app from
/// running — the caller gets no exception either way — but it is no
/// longer *silent*: a channel error or `FileManager` failure is reported
/// (round 2) via a type-only breadcrumb and `Sentry.captureException` (no
/// path or content), so a permanently failing exclusion is visible instead
/// of disappearing into an empty catch block forever. The Application
/// Support directory move is hygiene; `NSURLIsExcludedFromBackupKey` here
/// is the actual control (see the module doc comment above) — which is
/// exactly why a failure here needs to be seen, not swallowed.
Future<void> protectDatabaseFile() async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  try {
    final file = await localDatabaseFile();
    await const MethodChannel(kPrivacyChannel).invokeMethod<void>(
      'protectDatabaseFile',
      <String, String>{'path': file.path},
    );
  } catch (error, stackTrace) {
    // U7-style (KTD12): never log the path or content, only the type.
    defaultBreadcrumbLog
        .record('startup', 'protectDatabaseFile failed: ${error.runtimeType}');
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}
