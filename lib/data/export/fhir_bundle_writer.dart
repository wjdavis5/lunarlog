/// Platform adapter for the FHIR clinical export (Issue #157; KTD5, KTD6 —
/// mirrors `lib/data/export/account_export_writer.dart`'s pattern, wrapping
/// the pure `lib/domain/export/fhir_bundle.dart` builder). Lives in
/// `lib/data`, not `lib/domain`, because it touches `path_provider` and
/// `share_plus`, which KTD6 keeps out of `lib/domain`.
///
/// Unlike `AccountExportWriter` (whose whole file is excluded from the
/// coverage/CRAP gate — see `tool/quality/exclusions.dart`), the platform
/// call here is pulled out into its own tiny [FhirBundleShareCollaborator]
/// seam so [FhirBundleWriter.exportAndShare] and the pure helpers
/// ([fhirBundleFileName], [encodeFhirBundle]) stay directly unit-testable
/// with a fake collaborator; only [FhirBundleWriter._platformShare] itself
/// — the actual temp-file write + share-sheet call — is untestable under
/// `flutter test` and is proven by the U7 device checklist instead, same
/// treatment as `AccountExportWriter`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// `application/fhir+json` — the FHIR JSON media type (FHIR R4 spec §1.8,
/// distinct from the plain `application/json` `AccountExportWriter` uses
/// for the internal export document).
const String kFhirBundleMimeType = 'application/fhir+json';

/// Builds `lunarlog-fhir-<yyyyMMdd>.json` for [exportedAt]'s UTC date
/// (Issue #157's filename spec — a date, not a full timestamp, unlike
/// `AccountExportWriter._fileTimestamp`).
String fhirBundleFileName(DateTime exportedAt) {
  final utcDate = exportedAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'lunarlog-fhir-${utcDate.year}${two(utcDate.month)}${two(utcDate.day)}'
      '.json';
}

/// Pretty-printed FHIR JSON, matching `AccountExportWriter`'s own
/// `JsonEncoder.withIndent` choice.
String encodeFhirBundle(Map<String, Object?> bundle) =>
    const JsonEncoder.withIndent('  ').convert(bundle);

/// Delivers [fileName]/[jsonContent] to the platform (temp file write +
/// share sheet). Injected so [FhirBundleWriter.exportAndShare] itself
/// never touches `path_provider`/`share_plus` directly — only the default
/// implementation, [FhirBundleWriter._platformShare], does.
typedef FhirBundleShareCollaborator = Future<void> Function({
  required String fileName,
  required String jsonContent,
  required String mimeType,
});

class FhirBundleWriter {
  const FhirBundleWriter({FhirBundleShareCollaborator? shareCollaborator})
      : _share = shareCollaborator ?? _platformShare;

  final FhirBundleShareCollaborator _share;

  /// Encodes [bundle] (see [encodeFhirBundle]), names the file (see
  /// [fhirBundleFileName]) from [exportedAt], and hands both to [_share] —
  /// the real platform delivery step by default.
  Future<void> exportAndShare({
    required Map<String, Object?> bundle,
    required DateTime exportedAt,
  }) =>
      _share(
        fileName: fhirBundleFileName(exportedAt),
        jsonContent: encodeFhirBundle(bundle),
        mimeType: kFhirBundleMimeType,
      );

  /// The real platform call: temp file (via `path_provider`) handed to the
  /// share sheet (via `share_plus`), deleted once sharing completes —
  /// successfully or not. Cannot run under `flutter test` (no plugin
  /// registration); see this file's doc comment.
  static Future<void> _platformShare({
    required String fileName,
    required String jsonContent,
    required String mimeType,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(jsonContent);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: mimeType)],
          fileNameOverrides: [fileName],
        ),
      );
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
