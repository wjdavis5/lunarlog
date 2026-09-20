/// Platform adapter for CSV exports (Issue #469; mirrors PlatformFhirBundleWriter).
///
/// Lives in `lib/data`, not `lib/domain`, because it touches `path_provider` and
/// `share_plus`. The platform call is pulled out into [CsvShareCollaborator]
/// so [PlatformCsvExportWriter.exportAndShare] can be unit-tested without
/// real device plugins.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'package:lunarlog/domain/export/csv_export.dart';
import 'package:lunarlog/domain/export/csv_export_writer.dart';

import '../privacy/ephemeral_files.dart';
import 'export_file_share.dart';

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
    // Issue #843: write under the protected export directory, then clean the
    // originals and the share-cache copy once sharing completes.
    await writeShareExportAndCleanup(
      directory: await protectedExportDirectory(),
      files: [
        for (final f in files)
          ExportShareFile(
            fileName: f.fileName,
            bytes: Uint8List.fromList(utf8.encode(f.content)),
            mimeType: 'text/csv',
          ),
      ],
      cacheDirectory: await temporaryCacheDirectory(),
      share: (shared, names) => SharePlus.instance.share(
        ShareParams(files: shared, fileNameOverrides: names),
      ),
    );
  }
}
