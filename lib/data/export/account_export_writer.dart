/// Platform adapter for account export (Issue #17, Unit U5; KTD5, KTD6).
/// The only untestable-under-`flutter test` part of export: everything
/// content-shaped lives in the pure `lib/domain/export/account_export.dart`
/// builder this wraps. Writes the built document to a temp file (via
/// `path_provider`) and hands it to the platform share sheet (via
/// `share_plus`), then deletes the temp file once sharing completes -
/// successfully or not.
///
/// Excluded from the coverage/CRAP gate in `tool/quality/exclusions.dart`,
/// the same treatment as `lib/data/auth/google_sign_in_client.dart`; its
/// behaviour is proven by the U7 device checklist, not `flutter test`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/export/account_export.dart';
import '../../domain/models/day_entry.dart';
import '../../domain/models/profile.dart';

class AccountExportWriter {
  const AccountExportWriter();

  /// Builds the export (see [buildAccountExport]), writes it to
  /// `lunarlog-export-<yyyyMMdd-HHmmss>.json` under the temp directory, and
  /// hands that file to the platform share sheet.
  Future<void> exportAndShare({
    required List<Profile> profiles,
    required Map<String, List<DayEntry>> entriesByProfile,
    required String appVersion,
  }) async {
    final exportedAt = DateTime.now().toUtc();
    final document = buildAccountExport(
      profiles: profiles,
      entriesByProfile: entriesByProfile,
      exportedAt: exportedAt,
      appVersion: appVersion,
    );
    final encoded = const JsonEncoder.withIndent('  ').convert(document);

    final tempDir = await getTemporaryDirectory();
    final fileName = 'lunarlog-export-${_fileTimestamp(exportedAt)}.json';
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(encoded);
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          fileNameOverrides: [fileName],
        ),
      );
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  static String _fileTimestamp(DateTime utcInstant) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utcInstant.year}${two(utcInstant.month)}${two(utcInstant.day)}-'
        '${two(utcInstant.hour)}${two(utcInstant.minute)}${two(utcInstant.second)}';
  }
}
