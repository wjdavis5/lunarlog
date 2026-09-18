/// Unit tests for PlatformClinicalPdfWriter (Issue #154). Uses a fake
/// [ClinicalPdfShareCollaborator] throughout — never touches
/// `path_provider`/`share_plus`; only `_platformShare` itself is untested
/// here, the same treatment as the FHIR/CSV writers.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/export/clinical_pdf_writer.dart';

void main() {
  group('clinicalPdfFileName', () {
    test('formats as lunarlog-clinical-summary-<yyyy-MM-dd>.pdf in UTC', () {
      expect(
        clinicalPdfFileName(DateTime.utc(2026, 4, 5, 23, 59)),
        'lunarlog-clinical-summary-2026-04-05.pdf',
      );
    });

    test('pads single-digit month/day', () {
      expect(
        clinicalPdfFileName(DateTime.utc(2026, 1, 2)),
        'lunarlog-clinical-summary-2026-01-02.pdf',
      );
    });

    test('converts a non-UTC instant to its UTC date first', () {
      final local = DateTime.utc(2026, 4, 5, 21, 30);
      expect(
        clinicalPdfFileName(local),
        'lunarlog-clinical-summary-2026-04-05.pdf',
      );
    });
  });

  group('PlatformClinicalPdfWriter.exportAndShare', () {
    test('names the file and hands the bytes to the collaborator with the '
        'PDF mime type', () async {
      String? capturedFileName;
      Uint8List? capturedBytes;
      String? capturedMimeType;
      final writer = PlatformClinicalPdfWriter(
        shareCollaborator: ({
          required fileName,
          required bytes,
          required mimeType,
        }) async {
          capturedFileName = fileName;
          capturedBytes = bytes;
          capturedMimeType = mimeType;
        },
      );

      await writer.exportAndShare(
        pdfBytes: Uint8List.fromList(const [1, 2, 3]),
        exportedAt: DateTime.utc(2026, 4, 5),
      );

      expect(capturedFileName, 'lunarlog-clinical-summary-2026-04-05.pdf');
      expect(capturedBytes, isNotNull);
      expect(capturedBytes, hasLength(3));
      expect(capturedMimeType, kClinicalPdfMimeType);
    });

    test('propagates a collaborator failure rather than swallowing it', () {
      final writer = PlatformClinicalPdfWriter(
        shareCollaborator: ({
          required fileName,
          required bytes,
          required mimeType,
        }) async {
          throw StateError('share sheet unavailable');
        },
      );

      expect(
        () => writer.exportAndShare(
          pdfBytes: Uint8List(0),
          exportedAt: DateTime.utc(2026, 4, 5),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the default collaborator is only used when none is injected '
        '(constructed here but never invoked)', () {
      const writer = PlatformClinicalPdfWriter();
      expect(writer, isA<PlatformClinicalPdfWriter>());
    });
  });
}
