/// Stream-capped read for the picked import file (Issue #626, LLA-089).
///
/// Before this file existed, the platform picker
/// (`lib/data/import/import_file_picker.dart`) called `PlatformFile
/// .readAsBytes()` unconditionally — reading the ENTIRE file into memory
/// before `parseAccountImport`'s own `bytes.length > kMaxImportFileBytes`
/// check ever ran, so a hostile or corrupted file with an enormous byte
/// count could exhaust memory before the friendly rejection message was
/// ever produced. [readCappedBytes] fixes that at the source: it enforces
/// the cap DURING the read — checked chunk-by-chunk against the running
/// total, not only once every byte is already buffered — and, when the
/// platform reports a declared length up front, rejects an obviously
/// oversized file before requesting a single chunk at all.
///
/// Pure Dart (`dart:async`/`dart:typed_data` only, no `file_picker`/
/// `dart:io`) so the capping logic itself is testable under `flutter
/// test` (`test/domain/import/import_file_cap_test.dart`) even though the
/// platform picker that calls it is not (see that file's own doc comment
/// for why).
library;

import 'dart:async';
import 'dart:typed_data';

import 'account_import.dart' show kMaxImportFileBytes, importFileTooLargeMessage;

/// Thrown when a picked file's declared or actual byte length exceeds
/// [maxBytes] ([kMaxImportFileBytes] by default) — caught before the file
/// is fully read into memory, unlike `account_import.dart`'s own post-hoc
/// `bytes.length` check (`parseAccountImport`'s `AccountImportParseFailed`
/// result), which stays in place as a defense-in-depth backstop for any
/// caller that hands it already-loaded bytes some other way. [message] is
/// the identical sentence that backstop shows, via
/// [importFileTooLargeMessage] — the operator sees the same copy
/// regardless of which guard actually caught the oversized file.
class ImportFileTooLargeException implements Exception {
  const ImportFileTooLargeException();

  String get message => importFileTooLargeMessage();

  @override
  String toString() => 'ImportFileTooLargeException: $message';
}

/// Reads [byteStream] into memory, capped at [maxBytes] total
/// ([kMaxImportFileBytes] by default).
///
/// [declaredLength] — when the platform already knows the file's size
/// without doing I/O (`PlatformFile.lengthSync()`) or can cheaply find out
/// (`PlatformFile.length()`) — is checked FIRST, before [byteStream] is
/// ever listened to: an honestly-labeled oversized file is rejected
/// without reading a single chunk of it. [byteStream] itself is still
/// capped independently and unconditionally, so a caller never has to
/// trust [declaredLength] alone — a forged/stale value, or a file that
/// grows between the length check and the read, is caught exactly the
/// same way: the running total is compared against [maxBytes] after every
/// chunk, and the read throws (implicitly cancelling the stream
/// subscription, per `await for`'s own semantics) the moment the total
/// would exceed it, never after the whole stream has already been
/// buffered.
Future<Uint8List> readCappedBytes({
  required Stream<List<int>> byteStream,
  int? declaredLength,
  int maxBytes = kMaxImportFileBytes,
}) async {
  if (declaredLength != null && declaredLength > maxBytes) {
    throw const ImportFileTooLargeException();
  }
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in byteStream) {
    total += chunk.length;
    if (total > maxBytes) {
      throw const ImportFileTooLargeException();
    }
    builder.add(chunk);
  }
  return builder.toBytes();
}
