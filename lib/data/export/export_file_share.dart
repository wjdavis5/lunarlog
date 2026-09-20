/// Shared "write export → share sheet → clean up" sequence for every platform
/// export writer (issue #843): account JSON, CSV, clinical PDF, and FHIR.
///
/// Before #843 each writer wrote to `getTemporaryDirectory()` and deleted only
/// its own file in a `finally` — which left two plaintext copies behind:
/// `share_plus`'s own cache copy (Android copies every shared `XFile` into
/// `<cache>/share_plus/`, cleared only at the start of the next share) and the
/// looser-protected temp location itself. This helper writes under the
/// protected Application Support directory
/// (`lib/data/privacy/ephemeral_files.dart`'s [protectedExportDirectory]),
/// then deletes the written originals **and** sweeps the plugin caches once
/// the share returns. Everything here is best-effort except the share itself:
/// a cleanup failure must never fail an export that otherwise succeeded, and
/// the `finally` still runs (and still propagates the share error) when the
/// share sheet throws.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../privacy/ephemeral_files.dart';

/// One export file: its name, bytes, and media type.
class ExportShareFile {
  const ExportShareFile({
    required this.fileName,
    required this.bytes,
    required this.mimeType,
  });

  final String fileName;
  final Uint8List bytes;
  final String mimeType;
}

/// The platform share call, injected so [writeShareExportAndCleanup] runs
/// under `flutter test` without `share_plus`.
typedef ShareExportFiles = Future<void> Function(
  List<XFile> files,
  List<String> fileNameOverrides,
);

/// Deletes one written export file. Injectable so a test can force a cleanup
/// failure and prove it does not surface.
typedef DeleteExportFile = Future<void> Function(File file);

/// Sweeps the plugin cache copies. Injectable for the same reason.
typedef SweepEphemeralCache = Future<void> Function(Directory? cacheDirectory);

/// Writes [files] under [directory], hands them to [share], then deletes the
/// written originals and sweeps the plugin caches ([cacheDirectory]) in a
/// `finally` — covering a thrown share as well. Cleanup is best-effort by
/// contract: [deleteFile] and [sweepCache] are each wrapped so their failure
/// never masks a successful share or a share error.
Future<void> writeShareExportAndCleanup({
  required Directory directory,
  required List<ExportShareFile> files,
  required ShareExportFiles share,
  Directory? cacheDirectory,
  DeleteExportFile deleteFile = deleteFileBestEffort,
  SweepEphemeralCache sweepCache = sweepEphemeralCachesBestEffort,
}) async {
  // Record each file before writing it, so a partial write is still cleaned
  // up if the write throws.
  final written = <({File file, ExportShareFile source})>[];
  try {
    for (final source in files) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}${source.fileName}',
      );
      written.add((file: file, source: source));
      await file.writeAsBytes(source.bytes, flush: true);
    }
    await share(
      [
        for (final w in written)
          XFile(w.file.path, mimeType: w.source.mimeType),
      ],
      [for (final w in written) w.source.fileName],
    );
  } finally {
    for (final w in written) {
      await _bestEffort(() => deleteFile(w.file));
    }
    await _bestEffort(() => sweepCache(cacheDirectory));
  }
}

/// Runs [action], swallowing every failure. Keeps a cleanup error from
/// surfacing to the caller or masking a share error.
Future<void> _bestEffort(Future<void> Function() action) async {
  try {
    await action();
  } catch (_) {
    // Best effort: never surface a cleanup failure.
  }
}
