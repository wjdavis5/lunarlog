/// Platform adapter for restore-from-file import (Issue #140): the only
/// untestable-under-`flutter test` part of import, mirroring
/// `lib/data/export/account_export_writer.dart`'s split — everything
/// content-shaped lives in the pure `lib/domain/import/account_import.dart`
/// parser this wraps. Opens the platform file picker (`file_picker`,
/// scoped to `.json`) and returns the picked file's bytes, or null when
/// the operator cancels.
///
/// `file_picker` is a new platform dependency (Issue #140 design
/// constraints: "a file picker is a new dependency and a new platform
/// permission surface") — it reads a file the operator explicitly chose
/// through the OS picker UI, on-device only; nothing is uploaded anywhere
/// (see `PRIVACY.md`'s Change History entry for this issue).
///
/// Excluded from the coverage/CRAP gate in `tool/quality/exclusions.dart`,
/// the same treatment as `AccountExportWriter`: its behaviour is proven by
/// the device checklist, not `flutter test`.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Reads the operator-picked file's bytes, or null when they cancel the
/// picker. Production wiring is [pickImportFile]; tests inject a fake that
/// returns canned bytes without touching `file_picker`.
typedef ImportFileReader = Future<Uint8List?> Function();

/// Opens the platform file picker scoped to `.json` files and returns the
/// picked file's bytes. [PlatformFile.readAsBytes] is the package's own
/// cross-platform read (bytes in memory where the platform already
/// provides them, a path-backed read where it doesn't).
Future<Uint8List?> pickImportFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;
  return file.readAsBytes();
}
