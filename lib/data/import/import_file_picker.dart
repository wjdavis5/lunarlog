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
/// **Issue #626, LLA-089:** this used to call [PlatformFile.readAsBytes]
/// unconditionally — the package's own cross-platform "read the whole
/// file into memory" helper — which meant a hostile or corrupted file
/// with an enormous byte count was fully buffered before
/// `parseAccountImport`'s own `bytes.length` cap ever got a chance to
/// reject it. This now reads via [PlatformFile.readAsByteStream] instead,
/// capped chunk-by-chunk by `lib/domain/import/import_file_cap.dart`'s
/// `readCappedBytes` — see that file's own doc comment for the two-layer
/// guard (a declared-length preflight, then the stream itself capped
/// unconditionally). A rejection surfaces as `ImportFileTooLargeException`,
/// which `lib/ui/settings/import_screen.dart` catches distinctly to show
/// the same friendly copy `parseAccountImport` itself would have.
///
/// Excluded from the coverage/CRAP gate in `tool/quality/exclusions.dart`,
/// the same treatment as `AccountExportWriter`: its behaviour is proven by
/// the device checklist, not `flutter test` — the capping logic itself is
/// what `flutter test` actually exercises
/// (`test/domain/import/import_file_cap_test.dart`).
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:lunarlog/domain/import/import_file_cap.dart' show readCappedBytes;
import 'package:lunarlog/domain/import/import_file_reader.dart' as domain;

/// Opens the platform file picker scoped to `.json` files and returns the
/// picked file's bytes, stream-read with `readCappedBytes`'s cap (Issue
/// #626, LLA-089) rather than [PlatformFile.readAsBytes]'s unconditional
/// whole-file read. Throws `ImportFileTooLargeException` for a file over
/// the cap; the platform's declared length is consulted first
/// ([PlatformFile.lengthSync], falling back to the awaitable
/// [PlatformFile.length] when the platform didn't report it up front) so
/// an honestly-oversized file is rejected before a single chunk is read.
Future<Uint8List?> pickImportFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (file == null) return null;
  final declaredLength = file.lengthSync() ?? await file.length();
  return readCappedBytes(
    byteStream: file.readAsByteStream(),
    declaredLength: declaredLength,
  );
}

/// The domain `ImportFileReader` contract's production implementation,
/// backed by [pickImportFile]. The composition root provides this so `lib/ui`
/// can depend on the domain contract without naming the `file_picker` plugin.
class PickImportFileReader implements domain.ImportFileReader {
  const PickImportFileReader();

  @override
  Future<Uint8List?> read() => pickImportFile();
}
