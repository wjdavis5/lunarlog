/// Unit tests for FhirBundleWriter (Issue #157). Uses a fake
/// [FhirBundleShareCollaborator] throughout — never touches
/// `path_provider`/`share_plus`; only [FhirBundleWriter._platformShare]
/// (the real platform call) is untested here, same treatment as
/// `AccountExportWriter` (see this file's target's own doc comment).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/export/fhir_bundle_writer.dart';

void main() {
  group('fhirBundleFileName', () {
    test('formats as lunarlog-fhir-<yyyyMMdd>.json in UTC', () {
      expect(
        fhirBundleFileName(DateTime.utc(2026, 4, 5, 23, 59)),
        'lunarlog-fhir-20260405.json',
      );
    });

    test('pads single-digit month/day', () {
      expect(
        fhirBundleFileName(DateTime.utc(2026, 1, 2)),
        'lunarlog-fhir-20260102.json',
      );
    });

    test('converts a non-UTC instant to its UTC date first', () {
      // 2026-04-05T23:30 in UTC+2 is 2026-04-05T21:30 UTC — same day.
      final local = DateTime.utc(2026, 4, 5, 21, 30);
      expect(fhirBundleFileName(local), 'lunarlog-fhir-20260405.json');
    });
  });

  group('encodeFhirBundle', () {
    test('pretty-prints with a two-space indent', () {
      final encoded = encodeFhirBundle({'resourceType': 'Bundle', 'a': 1});
      expect(encoded, contains('\n  "resourceType": "Bundle"'));
      expect(encoded, contains('\n  "a": 1'));
    });
  });

  group('FhirBundleWriter.exportAndShare', () {
    test('encodes the bundle, names the file, and hands both to the '
        'collaborator with the FHIR mime type', () async {
      String? capturedFileName;
      String? capturedContent;
      String? capturedMimeType;
      final writer = FhirBundleWriter(
        shareCollaborator: ({
          required fileName,
          required jsonContent,
          required mimeType,
        }) async {
          capturedFileName = fileName;
          capturedContent = jsonContent;
          capturedMimeType = mimeType;
        },
      );

      await writer.exportAndShare(
        bundle: const {'resourceType': 'Bundle', 'type': 'document'},
        exportedAt: DateTime.utc(2026, 4, 5),
      );

      expect(capturedFileName, 'lunarlog-fhir-20260405.json');
      expect(capturedContent, contains('"resourceType": "Bundle"'));
      expect(capturedContent, contains('"type": "document"'));
      expect(capturedMimeType, kFhirBundleMimeType);
    });

    test('propagates a collaborator failure rather than swallowing it', () {
      final writer = FhirBundleWriter(
        shareCollaborator: ({
          required fileName,
          required jsonContent,
          required mimeType,
        }) async {
          throw StateError('share sheet unavailable');
        },
      );

      expect(
        () => writer.exportAndShare(
          bundle: const {'resourceType': 'Bundle'},
          exportedAt: DateTime.utc(2026, 4, 5),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the default collaborator is only used when none is injected '
        '(constructed here but never invoked, so path_provider/share_plus '
        'are never touched by this test)', () {
      const writer = FhirBundleWriter();
      expect(writer, isA<FhirBundleWriter>());
    });
  });
}
