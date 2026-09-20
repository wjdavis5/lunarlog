/// Best-effort cleanup of the *loose plaintext copies* the app leaves in
/// plugin cache directories (issue #843).
///
/// The local database is protected (`lib/startup/startup_native.dart`'s
/// `protectDatabaseFile`, issue #244), but an export, a shared file, or a
/// picked screenshot/backup can sit as loose plaintext in a cache the
/// database's protection never reaches:
///
/// * `share_plus` copies every shared `XFile` into `<cache>/share_plus/` on
///   Android and only clears that folder at the *start* of the next share,
///   so the most recent export (every note, flow, and tag for every profile)
///   lingers indefinitely after the app's own delete.
/// * `image_picker` leaves a re-encoded copy in the Android cache / iOS
///   `NSTemporaryDirectory()`.
/// * `file_picker` copies a picked backup into its own cache.
/// * The app's own export temp files used to live in `getTemporaryDirectory()`
///   (today they live under the protected Application Support directory — see
///   [protectedExportDirectory]).
///
/// Every function here is **best-effort by contract**: it never throws, never
/// surfaces a cleanup failure to the user, and never fails an otherwise
/// successful export. The startup sweep ([sweepPluginCachesAtStartup]) in
/// particular must never block or fail a launch.
///
/// On iOS export temps in Application Support ([exportDirectoryIn]) inherit the
/// parent directory's protection class and backup exclusion, set by
/// `AppDelegate.protectDatabaseFile` (issue #244, issue #906). On Android
/// `android/app/src/main/res/xml/data_extraction_rules.xml` lists these paths
/// so they are never copied by backup or device-to-device transfer.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Plugin-owned cache subdirectory names a sweep deletes. `share_plus` is the
/// one the export path relies on (it is also swept immediately after every
/// share — see `lib/data/export/export_file_share.dart`); `image_picker` and
/// `file_picker` are included because both leave a copy of the picked file in
/// a cache directory after a read.
const List<String> kEphemeralCacheDirNames = [
  'share_plus',
  'image_picker',
  'file_picker',
];

/// File-name prefixes the Android plugins use for direct cache entries
/// (`File.createTempFile('image_picker', ...)`), as opposed to a subdirectory.
/// Swept as well so a copy that isn't inside one of
/// [kEphemeralCacheDirNames] is still removed.
const List<String> kEphemeralCacheFilePrefixes = [
  'image_picker',
  'file_picker',
  'share_plus',
];

/// The subdirectory of the protected Application Support directory that holds
/// export temp files (issue #843). A child of Application Support inherits
/// its file-protection class and backup exclusion on iOS; on
/// Android it lives under `getFilesDir()` and is listed in
/// `data_extraction_rules.xml`.
const String kExportTempDirectoryName = 'export-tmp';

/// Deletes [file] if it exists, swallowing every failure.
Future<void> deleteFileBestEffort(File file) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (_) {
    // Best effort: a failed unlink must never surface.
  }
}

/// Deletes [directory] and everything under it, swallowing every failure.
Future<void> deleteDirectoryBestEffort(Directory directory) async {
  try {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  } catch (_) {
    // Best effort: a failed unlink must never surface.
  }
}

/// Deletes the plugin cache copies under [cacheDirectory]: every subdirectory
/// named in [kEphemeralCacheDirNames] plus any direct entry whose name starts
/// with a prefix in [kEphemeralCacheFilePrefixes].
///
/// On iOS, or when [sweepRootFiles] is true (Issue #943), deletes every direct
/// regular file at the root of [cacheDirectory] because iOS `file_picker`
/// copies picked backups directly to `NSTemporaryDirectory()/<original name>`
/// with no prefix and no subdirectory.
///
/// Tolerates a null (the platform had no cache directory) or missing
/// directory, and never throws.
Future<void> sweepEphemeralCachesBestEffort(
  Directory? cacheDirectory, {
  bool sweepRootFiles = false,
}) async {
  if (cacheDirectory == null) return;
  for (final name in kEphemeralCacheDirNames) {
    await deleteDirectoryBestEffort(
      Directory('${cacheDirectory.path}${Platform.pathSeparator}$name'),
    );
  }
  try {
    if (!await cacheDirectory.exists()) return;
    final isIos = sweepRootFiles || Platform.isIOS;
    await for (final entity in cacheDirectory.list()) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (isIos || kEphemeralCacheFilePrefixes.any(name.startsWith)) {
        await deleteFileBestEffort(File(entity.path));
      }
    }
  } catch (_) {
    // Best effort: a listing failure (permissions, a race) is not fatal.
  }
}

/// The platform cache directory, or null when the platform provides none (a
/// test host, web) or the lookup fails. Never throws.
Future<Directory?> temporaryCacheDirectory() async {
  try {
    return await getTemporaryDirectory();
  } catch (_) {
    return null;
  }
}

/// Resolves the platform cache directory and sweeps it (issue #843, issue #943).
/// Also invokes [clearFilePicker] (defaults to [FilePicker.clearTemporaryFiles])
/// to purge native temporary picker files. Called fire-and-forget at startup
/// to cover a process kill mid-share or mid-pick; never throws and never blocks.
Future<void> sweepPluginCachesAtStartup({
  Future<void> Function()? clearFilePicker,
}) async {
  try {
    if (clearFilePicker != null) {
      await clearFilePicker();
    } else {
      try {
        await FilePicker.clearTemporaryFiles();
      } catch (_) {
        // Best effort: ignored when unsupported or plugin is unbound in tests.
      }
    }
  } catch (_) {
    // Best effort: clear failure must never fail a launch.
  }
  try {
    await sweepEphemeralCachesBestEffort(
      await temporaryCacheDirectory(),
      sweepRootFiles: Platform.isIOS,
    );
  } catch (_) {
    // A sweep failure must never fail a launch.
  }
}

/// The protected directory export temp files are written to: a child of the
/// Application Support directory, which on iOS carries the database directory's
/// file-protection class and backup exclusion (issue #843, issue #906).
Future<Directory> protectedExportDirectory() async =>
    exportDirectoryIn(await getApplicationSupportDirectory());

/// Creates (if needed) and returns the export temp subdirectory of
/// [applicationSupportDirectory]. Split out from [protectedExportDirectory] so
/// the path/creation logic is testable against a real temp directory.
Future<Directory> exportDirectoryIn(
  Directory applicationSupportDirectory,
) async {
  final directory = Directory(
    '${applicationSupportDirectory.path}${Platform.pathSeparator}'
    '$kExportTempDirectoryName',
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}
