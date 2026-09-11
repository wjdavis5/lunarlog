/// Platform adapter for CSV exports (Issue #469; mirrors PlatformFhirBundleWriter).
///
/// Lives in `lib/data`, not `lib/domain`, because it touches `path_provider` and
/// `share_plus`. The platform call is pulled out into [CsvShareCollaborator]
/// so [PlatformCsvExportWriter.exportAndShare] can be unit-tested without
/// real device plugins.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:lunarlog/domain/export/csv_export.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';

/// Delivers a list of files to the platform (temp file write + share sheet).
typedef CsvShareCollaborator = Future<void> Function({
  required List<({String fileName, String content})> files,
});

class PlatformCsvExportWriter implements CsvExportWriter {
  const PlatformCsvExportWriter({CsvShareCollaborator? shareCollaborator})
      : _share = shareCollaborator ?? _platformShare;

  final CsvShareCollaborator _share;

  @override
  Future<void> exportAndShare({
    required String cyclesCsv,
    required String dailyLogCsv,
    required DateTime exportedAt,
  }) =>
      _share(
        files: [
          (fileName: csvCyclesFileName(exportedAt), content: cyclesCsv),
          (fileName: csvDailyLogFileName(exportedAt), content: dailyLogCsv),
        ],
      );

  static Future<void> _platformShare({
    required List<({String fileName, String content})> files,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFiles = <File>[];
    for (final f in files) {
      final file = File('${tempDir.path}${Platform.pathSeparator}${f.fileName}');
      await file.writeAsString(f.content);
      tempFiles.add(file);
    }
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            for (final f in tempFiles) XFile(f.path, mimeType: 'text/csv'),
          ],
          fileNameOverrides: [for (final f in files) f.fileName],
        ),
      );
    } finally {
      for (final f in tempFiles) {
        if (await f.exists()) {
          await f.delete();
        }
      }
    }
  }
}
