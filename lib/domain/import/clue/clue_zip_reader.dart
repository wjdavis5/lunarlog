/// Encrypted-zip reading for a Clue export (Issue #190's dependency
/// decision).
///
/// Clue exports are AES/ZipCrypto-encrypted zips (Clue Help Center; the
/// one-time password from the export email unlocks it). `archive` 4.2.0
/// (`pubspec.yaml`) is pure Dart — no network, no FFI/native code — and
/// its `ZipDecoder.decodeBytes` accepts a `password` for both legacy
/// ZipCrypto and AES-256 entries (`archive`'s own CHANGELOG: "Add Zip
/// AES-256 decryption", "Fix ZIP decryption for ZipCrypto format"), so no
/// native dependency was needed here — see `docs/import/clue-mapping.md`
/// "Zip decryption" for the full evaluation this file's choice is based
/// on.
///
/// Pure Dart otherwise: bytes in, bytes out, no `dart:io`/network (R14).
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Thrown when the zip cannot be opened at all (wrong password, corrupt
/// archive), does not contain the requested entry, or that entry's
/// declared uncompressed size exceeds [kClueZipEntrySizeCapBytes].
///
/// [message] is always a fixed, static string — never the raw exception
/// this was raised from. That underlying exception (an `ArchiveException`,
/// itself a `FormatException`) embeds a fragment of the archive's own
/// bytes, and the archive is the user's own Clue export; see
/// `ClueImportException`'s doc comment in `clue_export_parser.dart` for
/// the fuller rationale, which applies identically here. [offset] carries
/// only `FormatException.offset` when the underlying failure was one,
/// never any fragment of the bytes themselves.
class ClueZipException implements Exception {
  ClueZipException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'ClueZipException: $message'
      : 'ClueZipException: $message (offset: $offset)';
}

/// Sanity cap on a requested entry's declared uncompressed size (Issue
/// #190 review): a hostile or corrupt zip can declare an enormous
/// uncompressed size for a tiny compressed payload (a decompression
/// bomb), and `ArchiveFile.readBytes()` allocates the full declared size
/// up front. 64 MiB is generous for a `measurements.json` — even a
/// multi-decade daily export is a few MB of JSON at most.
const int kClueZipEntrySizeCapBytes = 64 * 1024 * 1024;

/// Extracts [entryName]'s raw bytes from a Clue export zip. [password] is
/// the one-time password from Clue's export email; a wrong password (or a
/// corrupt/unrecognised archive) throws [ClueZipException] rather than
/// returning garbage bytes.
Uint8List extractClueZipEntry(
  List<int> zipBytes, {
  required String password,
  String entryName = 'measurements.json',
}) {
  // A wrong password doesn't always fail at `decodeBytes` itself — for an
  // AES-encrypted entry the failure surfaces lazily, only once the entry's
  // bytes are actually decrypted below — so the whole decode-and-read
  // sequence is one try block, not just the decode call. `on Exception`
  // (not a bare `catch`) so a programming error here surfaces as itself
  // rather than being misreported as "wrong password or corrupt archive".
  try {
    final archive = ZipDecoder().decodeBytes(
      Uint8List.fromList(zipBytes),
      password: password,
      verify: true,
    );
    final file = archive.findFile(entryName);
    if (file == null) {
      throw ClueZipException('$entryName not found in the Clue export zip');
    }
    if (file.size > kClueZipEntrySizeCapBytes) {
      throw ClueZipException(
        '$entryName declares an implausibly large uncompressed size',
      );
    }
    final bytes = file.readBytes();
    if (bytes == null) {
      throw ClueZipException('$entryName has no readable content');
    }
    return bytes;
  } on ClueZipException {
    rethrow;
  } on Exception catch (e) {
    throw ClueZipException(
      'could not open the Clue export zip (wrong password or corrupt '
      'archive)',
      offset: e is FormatException ? e.offset : null,
    );
  }
}
