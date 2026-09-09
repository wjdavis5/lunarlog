/// Unit tests for the Clue export zip reader (Issue #190's dependency
/// decision — `archive` 4.2.0). Builds a small in-memory password
/// -protected zip with `ZipEncoder` (the same package's own encoder) and
/// proves this module's own wiring — finding `measurements.json` by name,
/// surfacing a wrong password, surfacing a missing entry — behaves
/// correctly; it is not a test of `archive`'s cryptography itself.
library;

import 'dart:convert';
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
}
