/// System share-sheet delivery for the export files (U1; R13).
///
/// The one `share_plus` call in the app, kept behind the [ShareFiles]
/// typedef so the export service and widget tests never touch a platform
/// channel. This file is a platform adapter: excluded from the coverage
/// gate's denominator (see `tool/quality/exclusions.dart`), like the other
/// plugin wrappers.
library;

import 'package:share_plus/share_plus.dart';

/// Shares [files] through the system share sheet. Throws the plugin's error
/// unchanged; the export service maps it to a kinds-only [ExportError].
typedef ShareFiles = Future<void> Function(
  List<XFile> files, {
  String? subject,
});

/// The production [ShareFiles]: shares downloaded/copyable files with the
/// export subject line.
Future<void> shareExportFiles(
  List<XFile> files, {
  String? subject,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: files,
      subject: subject ?? 'LunarLog data export',
    ),
  );
}
