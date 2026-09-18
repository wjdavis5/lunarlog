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
/// **Issue #626, LLA-090 — bounded-inflation rewrite.** This used to call
/// `ZipDecoder().decodeBytes(...)`, which has two unbounded-decompression
/// gaps `archive` 4.2.0's own source makes unavoidable through that entry
/// point:
/// - `ZipDecoder.decodeStream` eagerly calls `ArchiveFile.readBytes()` —
///   a full, uncapped inflate — for EVERY entry in the zip whose Unix
///   mode marks it a symlink (`zip_decoder.dart`'s own symlink-target
///   read), regardless of which entry was actually wanted. A hostile zip
///   could carry many such entries, each a small compressed blob that
///   inflates to something huge, and every one of them would be fully
///   decompressed before [extractClueZipEntry] ever got to look for
///   `measurements.json` at all.
/// - Even for the one entry actually requested, the pre-#626 declared-size
///   guard (`file.size > kClueZipEntrySizeCapBytes`, checked before
///   calling `readBytes()`) only bounds the header's OWN claimed
///   uncompressed size — a value the zip format never verifies against
///   the real inflate. A forged small declared size on a large deflate
///   payload sails through that check, and `readBytes()`'s actual inflate
///   work is then completely unbounded.
///
/// The fix bypasses `ZipDecoder` entirely: [ZipDirectory.read] (an
/// `archive` primitive `ZipDecoder` itself is built on) parses the
/// central directory and each entry's local header — bounded, safe work,
/// since neither step decompresses anything — after which this file finds
/// the ONE wanted [ZipFileHeader] by exact filename and calls its
/// [ZipFile.decompress] directly into [_CappedOutputStream], a small
/// `OutputMemoryStream` subclass that checks the running total against
/// [kClueZipEntrySizeCapBytes] on every write call DEFLATE's own decoder
/// makes (`writeByte`/`writeBytes`/`writeStream`/`writeBackReference` —
/// see that class's own doc comment) and throws the moment it would be
/// exceeded, regardless of what any header claimed. No entry other than
/// the one requested is ever decompressed, so the symlink-eager-read gap
/// above is structurally impossible here, not merely capped.
///
/// Pure Dart otherwise: bytes in, bytes out, no `dart:io`/network (R14).
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Why a Clue zip read failed (issue #795) — a typed reason the import UI
/// switches on for its user-facing copy, instead of substring-matching the
/// English [ClueZipException.message] (which broke under localization and
/// on any upstream wording change).
enum ClueZipFailureReason {
  /// The archive opened but simply does not contain `measurements.json` —
  /// "this ZIP is not a Clue export" rather than "the file is unreadable".
  entryNotFound,

  /// Everything else: wrong password, corrupt archive, an implausible
  /// entry count/size, or a bounded-inflation guard firing.
  unreadable,
}

/// Thrown when the zip cannot be opened at all (wrong password, corrupt
/// archive), does not contain the requested entry, that entry declares an
/// implausible size, or its actual decompressed content exceeds
/// [kClueZipEntrySizeCapBytes] regardless of what it declared (Issue
/// #626, LLA-090).
///
/// [message] is always a fixed, static string — never the raw exception
/// this was raised from. That underlying exception (an `ArchiveException`,
/// itself a `FormatException`) embeds a fragment of the archive's own
/// bytes, and the archive is the user's own Clue export; see
/// `ClueImportException`'s doc comment in `clue_export_parser.dart` for
/// the fuller rationale, which applies identically here. [offset] carries
/// only `FormatException.offset` when the underlying failure was one,
/// never any fragment of the bytes themselves. [reason] is the typed
/// failure (issue #795); it defaults to [ClueZipFailureReason.unreadable]
/// so the generic catch-all needs no extra branch.
class ClueZipException implements Exception {
  ClueZipException(
    this.message, {
    this.reason = ClueZipFailureReason.unreadable,
    this.offset,
  });

  final String message;
  final ClueZipFailureReason reason;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'ClueZipException: $message'
      : 'ClueZipException: $message (offset: $offset)';
}

/// Cap on an entry's ACTUAL decompressed byte count (Issue #626, LLA-090
/// — widened in scope, same value as before: 64 MiB is generous for a
/// `measurements.json` — even a multi-decade daily export is a few MB of
/// JSON at most). Before this issue this constant only bounded a header's
/// own DECLARED uncompressed size — a value nothing in the zip format
/// forces to be honest. It now bounds the real inflate: a hostile or
/// corrupt zip can declare an enormous uncompressed size for a tiny
/// compressed payload (a decompression bomb), or the reverse — a
/// deceptively small declared size on a payload that actually inflates
/// past this cap — and [_CappedOutputStream] enforces this value against
/// the running decompressed total DURING the inflate itself, checked on
/// every write DEFLATE's own decoder makes, not against anything the
/// header claims.
const int kClueZipEntrySizeCapBytes = 64 * 1024 * 1024;

/// Cap on the number of entries a Clue export zip's central directory may
/// declare (Issue #626, LLA-090 review: "a compression-ratio or
/// entry-count guard, regardless of declared sizes") — cheap defense in
/// depth alongside [kClueZipEntrySizeCapBytes]'s per-entry bound. Reading
/// the central directory itself never decompresses anything (see this
/// file's own doc comment), so an oversized entry COUNT is not a
/// decompression-bomb vector the way an oversized single entry is; this
/// guard exists so a zip claiming an absurd number of entries is rejected
/// outright rather than silently accepted. 10,000 is far beyond any real
/// Clue export (a handful of files).
const int kClueZipMaxEntries = 10000;

/// Whether [bytes] begin with the ZIP local-file-header signature
/// (`PK\x03\x04`, or one of the other two RFC-fixed `PK` signatures an
/// empty/spanned archive may open with) — the cheap, pure check the import
/// screen uses to route a picked file to the Clue path or the app's own
/// JSON path (Issue #452). The two formats are unambiguous: every ZIP
/// variant starts with `PK`, and a lunarlog account export is a JSON object
/// starting with `{` (a UTF-8 BOM aside). A file that begins with `PK` but
/// is not a readable archive still routes to the Clue path and surfaces a
/// typed [ClueZipException] there rather than being misparsed as JSON.
bool looksLikeZipArchive(List<int> bytes) {
  if (bytes.length < 4) return false;
  if (bytes[0] != 0x50 || bytes[1] != 0x4b) return false;
  // 0x03: local file header, 0x05: end of central directory (empty
  // archive), 0x07: spanned archive. Any other third byte is not a ZIP
  // signature.
  return bytes[2] == 0x03 || bytes[2] == 0x05 || bytes[2] == 0x07;
}

/// Extracts [entryName]'s raw bytes from a Clue export zip. [password] is
/// the one-time password from Clue's export email; a wrong password (or a
/// corrupt/unrecognised archive) throws [ClueZipException] rather than
/// returning garbage bytes.
///
/// [maxBytes]/[maxEntries] (Issue #626, LLA-090) override
/// [kClueZipEntrySizeCapBytes]/[kClueZipMaxEntries] — the production
/// defaults everywhere except this file's own regression tests, which
/// override them to small values so synthetic fixtures (a "declared size
/// lies small, real inflation is large" zip; a handful of entries against
/// a tiny entry-count cap) can prove each guard without needing an actual
/// multi-megabyte payload or thousands of entries.
Uint8List extractClueZipEntry(
  List<int> zipBytes, {
  required String password,
  String entryName = 'measurements.json',
  int maxBytes = kClueZipEntrySizeCapBytes,
  int maxEntries = kClueZipMaxEntries,
}) {
  // A wrong password doesn't always fail during directory parsing — for a
  // ZipCrypto- or AES-encrypted entry the failure surfaces lazily, only
  // once its bytes are actually decrypted/inflated during `decompress`
  // below — so the whole scan-and-decompress sequence is one try block,
  // not just the directory read. `on Exception` (not a bare `catch`) so a
  // programming error here surfaces as itself rather than being
  // misreported as "wrong password or corrupt archive".
  try {
    final directory = ZipDirectory()
      ..read(InputMemoryStream(Uint8List.fromList(zipBytes)), password: password);
    _rejectIfTooManyEntries(directory, maxEntries);
    final header = _requireHeader(directory, entryName);
    _rejectIfDeclaredTooLarge(header, entryName, maxBytes);
    return _decompressCapped(header, entryName, maxBytes);
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

/// Issue #626, LLA-090 review: the central-directory entry-count guard,
/// split out of [extractClueZipEntry] to keep that function's own
/// complexity low. See [kClueZipMaxEntries]'s own doc comment for why
/// this is defense in depth rather than the real decompression-bomb fix.
void _rejectIfTooManyEntries(ZipDirectory directory, int maxEntries) {
  if (directory.fileHeaders.length > maxEntries) {
    throw ClueZipException(
      'the Clue export zip declares an implausible number of entries',
    );
  }
}

/// The header for [entryName] among [directory]'s entries, by EXACT
/// filename match — throws [ClueZipException] when absent. A directory
/// entry sharing [entryName] is naturally excluded, not specially
/// detected: `archive`'s own `ZipEncoder` always stores a directory's
/// name with a trailing `/` (`zip_encoder.dart`), so
/// `'measurements.json/'` never exact-matches a request for
/// `'measurements.json'` — the same "treated as missing" outcome the
/// pre-#626 `Archive.findFile`-based lookup produced, reached here by the
/// lookup's own shape rather than a bespoke `isDirectory` check.
ZipFileHeader _requireHeader(ZipDirectory directory, String entryName) {
  for (final header in directory.fileHeaders) {
    if (header.filename == entryName) return header;
  }
  throw ClueZipException(
    '$entryName not found in the Clue export zip',
    reason: ClueZipFailureReason.entryNotFound,
  );
}

/// Cheap fast-path guard on [header]'s DECLARED sizes (Issue #626,
/// LLA-090 review), before any decode work starts at all — catches an
/// honestly-labeled oversized entry for free. This is deliberately NOT
/// the real bound (a lying declared size bypasses it trivially, which is
/// exactly LLA-090's point): [_decompressCapped]'s capped decompress is
/// what actually enforces [maxBytes] against what the entry really
/// inflates to, regardless of this check.
void _rejectIfDeclaredTooLarge(ZipFileHeader header, String entryName, int maxBytes) {
  if (header.compressedSize > maxBytes || header.uncompressedSize > maxBytes) {
    throw ClueZipException('$entryName declares an implausibly large size');
  }
}

/// Decompresses [header]'s entry into a [_CappedOutputStream] capped at
/// [maxBytes] (Issue #626, LLA-090 review, split out of
/// [extractClueZipEntry]) — the actual bound, independent of anything
/// [header] itself claims (see [_rejectIfDeclaredTooLarge]'s doc
/// comment). `header.file` is never null here: [ZipFileHeader.read] (via
/// [ZipDirectory.read], which [extractClueZipEntry] always calls with a
/// non-null `fileBytes`) unconditionally constructs and assigns it for
/// every header in the directory, so there is no null case for this
/// function to guard — the field's own type stays nullable only because
/// `archive`'s own class declares it that way.
Uint8List _decompressCapped(ZipFileHeader header, String entryName, int maxBytes) {
  final output = _CappedOutputStream(maxBytes);
  // Decompresses ONLY this one entry, never the whole archive — see this
  // file's own doc comment for why that alone closes the
  // decode-every-symlink gap `ZipDecoder.decodeStream` has. Throws
  // ClueZipException mid-inflate the moment the actual output would
  // exceed [maxBytes], independent of [header]'s own declared sizes.
  header.file!.decompress(output);
  if (output.length == 0) {
    throw ClueZipException('$entryName has no readable content');
  }
  return output.getBytes();
}

/// An in-memory decompress target that enforces [_maxBytes] as a hard cap
/// on the total bytes ever written to it (Issue #626, LLA-090), checked
/// BEFORE each write is applied so the running total can never actually
/// exceed the cap — not even by one write's own size. Overrides every
/// write path `archive`'s own [Inflate]/[BZip2Decoder] decoders use:
/// - `writeByte` — one literal byte at a time (the common DEFLATE case).
/// - `writeBytes` — an uncompressed (STORE) block, or a decoder's own
///   bulk write.
/// - `writeStream` — [ZipFile.decompress]'s own STORE-method path
///   (`output.writeStream(_rawContent!)`), bypassing `writeBytes`
///   entirely.
/// - `writeBackReference` — DEFLATE's LZ77 back-reference expansion (up
///   to 258 bytes per call, the format's own maximum match length);
///   [OutputMemoryStream] overrides this one directly with an in-buffer
///   copy rather than routing through `writeBytes`, so it needs its own
///   override here too, or a back-reference-heavy payload (exactly the
///   shape a real decompression bomb takes) would bypass every check
///   above it.
///
/// A legitimate small payload (every real Clue export) never comes close
/// to [_maxBytes] and pays only the cheap running-total comparison; an
/// oversized one is stopped mid-decompress, the moment its true size
/// becomes apparent, never after being fully materialized.
class _CappedOutputStream extends OutputMemoryStream {
  _CappedOutputStream(this._maxBytes);

  final int _maxBytes;

  void _checkCap(int incoming) {
    if (length + incoming > _maxBytes) {
      throw ClueZipException(
        'the Clue export zip entry decompressed past the allowed size',
      );
    }
  }

  @override
  void writeByte(int value) {
    _checkCap(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _checkCap(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _checkCap(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _checkCap(count);
    super.writeBackReference(distance, count);
  }
}
