/// Unit tests for the Clue export zip reader (Issue #190's dependency
/// decision — `archive` 4.2.0). Builds a small in-memory password
/// -protected zip with `ZipEncoder` (the same package's own encoder) and
/// proves this module's own wiring — finding `measurements.json` by name,
/// surfacing a wrong password, surfacing a missing entry — behaves
/// correctly; it is not a test of `archive`'s cryptography itself.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_zip_reader.dart';

Uint8List _buildEncryptedZip({
  required String password,
  required Map<String, String> files,
}) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile.bytes(entry.key, bytes));
  }
  final encoded = ZipEncoder(password: password).encode(archive);
  return Uint8List.fromList(encoded);
}

/// Local file header signature (`PK\x03\x04`) and central directory file
/// header signature (`PK\x01\x02`), RFC-fixed byte sequences — used by
/// [_lieAboutUncompressedSize] to find both of a real `ZipEncoder`
/// output's own copies of `uncompressedSize` without hand-parsing the
/// rest of the zip structure.
const _localHeaderSig = [0x50, 0x4b, 0x03, 0x04];
const _centralHeaderSig = [0x50, 0x4b, 0x01, 0x02];

bool _matchesAt(Uint8List bytes, int pos, List<int> sig) {
  if (pos + sig.length > bytes.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (bytes[pos + i] != sig[i]) return false;
  }
  return true;
}

void _patchUint32LEAt(Uint8List bytes, int pos, int value) {
  bytes[pos] = value & 0xff;
  bytes[pos + 1] = (value >> 8) & 0xff;
  bytes[pos + 2] = (value >> 16) & 0xff;
  bytes[pos + 3] = (value >> 24) & 0xff;
}

/// Rewrites the DECLARED `uncompressedSize` field to [claimedSize] in
/// BOTH the local file header (offset 22 from its signature) and the
/// central directory header (offset 24 from its signature) of every
/// entry in [zipBytes], while leaving the actual deflate stream (and
/// therefore what it really inflates to) untouched — exactly LLA-090's
/// own repro shape: "forge small declared size for large deflate
/// payload". `compressedSize` is deliberately left alone: a real
/// `ZipEncoder` already writes an honestly tiny value there for
/// highly-compressible test content, so the fast declared-size guard's
/// OTHER half stays passed too, and only the actual-inflated-bytes cap
/// is left to catch the lie.
Uint8List _lieAboutUncompressedSize(Uint8List zipBytes, int claimedSize) {
  final patched = Uint8List.fromList(zipBytes);
  for (var i = 0; i <= patched.length - 4; i++) {
    if (_matchesAt(patched, i, _localHeaderSig)) {
      _patchUint32LEAt(patched, i + 22, claimedSize);
    } else if (_matchesAt(patched, i, _centralHeaderSig)) {
      _patchUint32LEAt(patched, i + 24, claimedSize);
    }
  }
  return patched;
}

void main() {
  group('extractClueZipEntry', () {
    test('extracts measurements.json from a password-protected zip', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': '[{"date":"2026-01-01"}]'},
      );
      final bytes = extractClueZipEntry(zip, password: 'correct horse');
      expect(utf8.decode(bytes), '[{"date":"2026-01-01"}]');
    });

    test('a wrong password throws ClueZipException', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': '[]'},
      );
      expect(
        () => extractClueZipEntry(zip, password: 'wrong password'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('a directory entry of the same name is treated as missing', () {
      final archive = Archive()
        ..addFile(ArchiveFile.directory('measurements.json'));
      final zip = Uint8List.fromList(
        ZipEncoder(password: 'correct horse').encode(archive),
      );
      expect(
        () => extractClueZipEntry(zip, password: 'correct horse'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('a missing entry throws ClueZipException', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'settings.json': '{}'},
      );
      expect(
        () => extractClueZipEntry(zip, password: 'correct horse'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('toString carries the message', () {
      expect(ClueZipException('boom').toString(), contains('boom'));
    });

    test('toString with an offset appends it', () {
      final message = ClueZipException('boom', offset: 7).toString();
      expect(message, contains('boom'));
      expect(message, contains('7'));
    });

    test('a custom entry name is honored', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'other.json': '[1,2,3]'},
      );
      final bytes = extractClueZipEntry(
        zip,
        password: 'correct horse',
        entryName: 'other.json',
      );
      expect(utf8.decode(bytes), '[1,2,3]');
    });

    test('non-zip garbage bytes throw a typed ClueZipException, never an '
        'uncaught ArchiveException/FormatException (Issue #190 review)',
        () {
      final garbage =
          Uint8List.fromList(List<int>.generate(64, (i) => i * 7 % 256));
      expect(
        () => extractClueZipEntry(garbage, password: 'whatever'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('the fixed message never embeds the underlying decode failure\'s '
        'own text (Issue #190 review: mirrors ClueImportException — see '
        'clue_export_parser.dart)', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': '[]'},
      );
      try {
        extractClueZipEntry(zip, password: 'wrong password');
        fail('expected ClueZipException');
      } on ClueZipException catch (e) {
        expect(e.message, isNot(contains('Exception')));
        expect(e.message, contains('wrong password or corrupt archive'));
      }
    });

    test('an entry whose declared uncompressed size exceeds the cap throws '
        'a typed ClueZipException before readBytes() would allocate it '
        '(Issue #190 review — decompression-bomb guard)', () {
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(
            'measurements.json',
            Uint8List(kClueZipEntrySizeCapBytes + 1),
          ),
        );
      final zip = Uint8List.fromList(
        ZipEncoder(password: 'correct horse').encode(archive),
      );
      expect(
        () => extractClueZipEntry(zip, password: 'correct horse'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('an entry at or under the size cap still reads normally', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': '[]'},
      );
      expect(
        extractClueZipEntry(zip, password: 'correct horse'),
        isNotNull,
      );
    });
  });

  group('bounded-inflation guard (Issue #626, LLA-090)', () {
    test('a forged small DECLARED uncompressed size does not bypass the '
        'real cap — the ACTUAL inflated content is what is checked, '
        'caught during decompress, not trusted from the header', () {
      // Highly compressible content: real size 5000 bytes, but deflates
      // to a tiny compressed blob (well under maxBytes on its own), so
      // ONLY the uncompressedSize lie is what could let it slip past a
      // header-only guard.
      final trueContent = 'x' * 5000;
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': trueContent},
      );
      final lied = _lieAboutUncompressedSize(zip, 10);

      expect(
        () => extractClueZipEntry(
          lied,
          password: 'correct horse',
          maxBytes: 2000, // small test cap; the real content (5000) exceeds it
        ),
        throwsA(isA<ClueZipException>()),
        reason: 'the lied declared size (10) is comfortably under '
            'maxBytes (2000) and must not be trusted — the real 5000 '
            'bytes of inflated content is what exceeds the cap',
      );
    });

    test('the SAME lied file, with the real cap generous enough for the '
        'real content, still extracts successfully — a lie about the '
        'declared size is not itself a reason to reject a file that '
        'genuinely fits', () {
      final trueContent = 'y' * 5000;
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': trueContent},
      );
      final lied = _lieAboutUncompressedSize(zip, 10);

      final bytes = extractClueZipEntry(
        lied,
        password: 'correct horse',
        maxBytes: 10000, // comfortably above the real 5000-byte content
      );
      expect(utf8.decode(bytes), trueContent);
    });

    test('actual decompressed content exactly at maxBytes is accepted; '
        'one byte over throws — the cap is enforced precisely against '
        'the real output, not the declared size', () {
      final atCap = 'z' * 1000;
      final overCap = 'z' * 1001;

      final zipAtCap = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': atCap},
      );
      expect(
        extractClueZipEntry(zipAtCap, password: 'correct horse', maxBytes: 1000),
        isNotNull,
      );

      final zipOverCap = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': overCap},
      );
      expect(
        () => extractClueZipEntry(zipOverCap, password: 'correct horse', maxBytes: 1000),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('an implausible entry count is rejected outright (defense in '
        'depth alongside the per-entry byte cap)', () {
      final archive = Archive();
      for (var i = 0; i < 3; i++) {
        archive.addFile(ArchiveFile.bytes('file$i.json', utf8.encode('{}')));
      }
      final zip = Uint8List.fromList(
        ZipEncoder(password: 'correct horse').encode(archive),
      );

      expect(
        () => extractClueZipEntry(
          zip,
          password: 'correct horse',
          entryName: 'file0.json',
          maxEntries: 2,
        ),
        throwsA(isA<ClueZipException>()),
      );
      // The same zip, under a generous entry cap, extracts normally.
      expect(
        extractClueZipEntry(
          zip,
          password: 'correct horse',
          entryName: 'file0.json',
          maxEntries: 10,
        ),
        isNotNull,
      );
    });

    test('only the requested entry is ever decompressed: a second, '
        'oversized entry sharing the archive never trips the cap', () {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('measurements.json', utf8.encode('[]')))
        ..addFile(ArchiveFile.bytes('huge_unrelated.bin',
            Uint8List.fromList(List.filled(50000, 0))));
      final zip = Uint8List.fromList(
        ZipEncoder(password: 'correct horse').encode(archive),
      );

      // maxBytes (1000) is far smaller than the unrelated entry's real
      // size (50000) — if that entry were ever touched, this would
      // throw. It must not be: only measurements.json is requested.
      final bytes = extractClueZipEntry(
        zip,
        password: 'correct horse',
        maxBytes: 1000,
      );
      expect(utf8.decode(bytes), '[]');
    });

    test('an entry with genuinely empty content throws "no readable '
        'content" — the true branch of the empty-output guard', () {
      final zip = _buildEncryptedZip(
        password: 'correct horse',
        files: {'measurements.json': ''},
      );
      expect(
        () => extractClueZipEntry(zip, password: 'correct horse'),
        throwsA(isA<ClueZipException>()),
      );
    });

    test('the declared-size guard trips on compressedSize alone, '
        'independently of uncompressedSize: incompressible (random) '
        'content declares a compressed size a few bytes ABOVE its own '
        'uncompressed size (deflate/encryption overhead on data that '
        'cannot shrink) — a maxBytes snugly between the two is exceeded '
        'only by the compressed figure', () {
      final random = Random(42);
      final incompressible =
          Uint8List.fromList(List<int>.generate(1000, (_) => random.nextInt(256)));
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('measurements.json', incompressible));
      final zip = Uint8List.fromList(
        ZipEncoder(password: 'correct horse').encode(archive),
      );

      // Confirms the fixture's own premise before asserting on it: real
      // uncompressedSize (1000) comfortably under maxBytes, but
      // compressedSize (measured: 1033 — deflate/encryption overhead on
      // data that cannot shrink) over it.
      expect(
        () => extractClueZipEntry(zip, password: 'correct horse', maxBytes: 1010),
        throwsA(isA<ClueZipException>()),
      );
      // The same content, under a cap wide enough for the compressed
      // figure too, extracts normally — proving the throw above was
      // genuinely the declared-size guard, not some unrelated failure.
      expect(
        extractClueZipEntry(zip, password: 'correct horse', maxBytes: 1100),
        isNotNull,
      );
    });
  });
}
