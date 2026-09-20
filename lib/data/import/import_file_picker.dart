/// Platform adapter for restore-from-file import (Issue #140): the only
/// untestable-under-`flutter test` part of import, mirroring
/// `lib/data/export/account_export_writer.dart`'s split — everything
/// content-shaped lives in the pure `lib/domain/import/account_import.dart`
/// parser this wraps. Opens the platform file picker (`file_picker`,
/// scoped to `.json` and, since Issue #452, `.zip`) and returns the picked
/// file's bytes, or null when the operator cancels. The import screen
/// routes a ZIP to the Clue path and a JSON file to the app's own export
/// path by inspecting the bytes, so the picker itself stays type-agnostic.
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
/// **Issue #843:** the plugin copies the picked backup into its own cache;
/// both that copy and file_picker's temp cache are deleted (best-effort) once
/// the bytes are read, so a household's full backup does not sit as loose
/// plaintext in a cache after the import.
///
/// Excluded from the coverage/CRAP gate in `tool/quality/exclusions.dart`,
/// the same treatment as `AccountExportWriter`: the plugin call itself is
/// proven by the device checklist, not `flutter test` — the read/cleanup
/// sequence around an injected [PickedImportFile] is what
/// `test/data/import/import_file_picker_test.dart` actually exercises, along
/// with the capping logic (`test/domain/import/import_file_cap_test.dart`).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:lunarlog/domain/import/import_file_cap.dart' show readCappedBytes;
import 'package:lunarlog/domain/import/import_file_reader.dart' as domain;

import '../privacy/ephemeral_files.dart';

/// A picked file, adapted away from `file_picker`'s own `PlatformFile` so the
/// read-and-clean-up sequence is testable without the plugin. The production
/// adapter ([PickImportFileReader._pickWithPlugin]) is the only thing that
/// touches `PlatformFile`.
class PickedImportFile {
  const PickedImportFile({
    required this.path,
    required this.declaredLength,
    required this.bytesStream,
  });

  /// The on-disk path the plugin copied the pick to, or null when the
  /// platform reports no path (e.g. web).
  final String? path;

  /// The platform's declared byte length, checked before any chunk is read.
  final int? declaredLength;

  /// The file's bytes, streamed so the cap is enforced during the read.
  final Stream<List<int>> bytesStream;
}

/// Seam over the `file_picker` pick call; tests inject a fake.
typedef PickPlatformImportFile = Future<PickedImportFile?> Function();

/// Seam over `FilePicker.clearTemporaryFiles`; tests inject a fake so a
/// cleanup failure can be proven not to surface.
typedef ClearFilePickerTemporaryFiles = Future<void> Function();

/// The domain `ImportFileReader` contract's production implementation. The
/// composition root provides this so `lib/ui` can depend on the domain
/// contract without naming the `file_picker` plugin.
class PickImportFileReader implements domain.ImportFileReader {
  PickImportFileReader({
    PickPlatformImportFile? pickFile,
    ClearFilePickerTemporaryFiles? clearTemporaryFiles,
  })  : _pickFile = pickFile ?? _pickWithPlugin,
        _clearTemporaryFiles =
            clearTemporaryFiles ?? _clearPluginTemporaryFiles;

  final PickPlatformImportFile _pickFile;
  final ClearFilePickerTemporaryFiles _clearTemporaryFiles;

  /// The real plugin path. Never executed under `flutter test`.
  static Future<PickedImportFile?> _pickWithPlugin() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json', 'zip'],
    );
    if (file == null) return null;
    return PickedImportFile(
      path: file.path,
      declaredLength: file.lengthSync() ?? await file.length(),
      bytesStream: file.readAsByteStream(),
    );
  }

  /// The real cache clear. Never executed under `flutter test`.
  static Future<void> _clearPluginTemporaryFiles() =>
      FilePicker.clearTemporaryFiles();

  @override
  Future<Uint8List?> read() async {
    final file = await _pickFile();
    if (file == null) return null;
    try {
      return await readCappedBytes(
        byteStream: file.bytesStream,
        declaredLength: file.declaredLength,
      );
    } finally {
      // Issue #843: delete the plugin's copy of the backup and its temp cache
      // once the bytes are in hand — best-effort, never surfaced.
      final path = file.path;
      if (path != null) {
        try {
          await deleteFileBestEffort(File(path));
        } catch (_) {
          // Best effort only.
        }
      }
      try {
        await _clearTemporaryFiles();
      } catch (_) {
        // Best effort only.
      }
    }
  }
}

/// Back-compat shim for callers that used the old top-level function; the
/// composition root passes a [PickImportFileReader] directly.
Future<Uint8List?> pickImportFile() => PickImportFileReader().read();
