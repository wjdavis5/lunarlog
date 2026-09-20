/// Platform adapter for the PDF clinician cycle summary (Issue #154).
/// Mirrors `lib/data/export/fhir_bundle_writer.dart`: the platform call is
/// pulled out into an injected [ClinicalPdfShareCollaborator] seam so
/// [PlatformClinicalPdfWriter.exportAndShare] and the pure helpers
/// ([clinicalPdfFileName]) stay unit-testable; only
/// [PlatformClinicalPdfWriter._platformShare] — the temp-file write and
/// share-sheet call — cannot run under `flutter test` and is proven by the
/// device checklist instead.
///
/// Lives in `lib/data`, not `lib/domain`, because it touches `path_provider`
/// and `share_plus` (the same boundary `FhirBundleWriter` documents).
library;

import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'package:lunarlog/domain/export/clinical_pdf_writer.dart';

import '../privacy/ephemeral_files.dart';
import 'export_file_share.dart';

/// The PDF media type.
const String kClinicalPdfMimeType = 'application/pdf';

/// `lunarlog-clinical-summary-<yyyy-MM-dd>.pdf` in UTC.
String clinicalPdfFileName(DateTime exportedAt) {
  final utc = exportedAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'lunarlog-clinical-summary-${utc.year}-${two(utc.month)}-'
      '${two(utc.day)}.pdf';
}

/// Delivers [fileName]/[bytes] to the platform (temp file + share sheet).
/// Injected so tests never touch `path_provider`/`share_plus`.
typedef ClinicalPdfShareCollaborator = Future<void> Function({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
});

class PlatformClinicalPdfWriter implements ClinicalPdfWriter {
  const PlatformClinicalPdfWriter({ClinicalPdfShareCollaborator? shareCollaborator})
    : _share = shareCollaborator ?? _platformShare;

  final ClinicalPdfShareCollaborator _share;

  @override
  Future<void> exportAndShare({
    required Uint8List pdfBytes,
    required DateTime exportedAt,
  }) => _share(
    fileName: clinicalPdfFileName(exportedAt),
    bytes: pdfBytes,
    mimeType: kClinicalPdfMimeType,
  );

  /// The real platform call: protected export temp file handed to the share
  /// sheet (via `share_plus`), cleaned up (original + share cache) once
  /// sharing completes — successfully or not (issue #843). Cannot run under
  /// `flutter test`.
  static Future<void> _platformShare({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await writeShareExportAndCleanup(
      directory: await protectedExportDirectory(),
      files: [
        ExportShareFile(fileName: fileName, bytes: bytes, mimeType: mimeType),
      ],
      cacheDirectory: await temporaryCacheDirectory(),
      share: (files, names) => SharePlus.instance.share(
        ShareParams(files: files, fileNameOverrides: names),
      ),
    );
  }
}
