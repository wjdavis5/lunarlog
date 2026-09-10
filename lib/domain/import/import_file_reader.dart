/// Contract for the operator-picked restore file (Issue #140; R4).
///
/// The UI needs the picked file's bytes, or null when the operator cancels,
/// but must not depend on the `file_picker` plugin adapter in
/// `lib/data/import/`. This contract is the domain-facing shape of that
/// seam; the production adapter lives in `lib/data/import/`.
library;

import 'dart:typed_data';

abstract interface class ImportFileReader {
  /// Returns the picked file's bytes, or null when the operator cancels the
  /// picker.
  Future<Uint8List?> read();
}
