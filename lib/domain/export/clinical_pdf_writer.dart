/// Contract for writing and sharing the PDF clinician cycle summary
/// (Issue #154; mirrors `FhirBundleWriter`/`CsvExportWriter`).
///
/// The UI builds the PDF bytes through the pure domain layer
/// (`lib/domain/export/clinical_pdf.dart`) but must not depend on the
/// `path_provider`/`share_plus` adapter in `lib/data/export/`; this contract
/// takes the already-built bytes and the export instant.
library;

import 'dart:typed_data';

abstract interface class ClinicalPdfWriter {
  /// Writes [pdfBytes] to a temp file, names it from [exportedAt], and hands
  /// it to the platform share sheet.
  Future<void> exportAndShare({
    required Uint8List pdfBytes,
    required DateTime exportedAt,
  });
}
