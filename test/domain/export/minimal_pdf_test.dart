/// Unit tests for the dependency-free minimal PDF writer (Issue #154).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/export/minimal_pdf.dart';

String _decode(Uint8List bytes) => latin1.decode(bytes);

/// The `(offset, generation, type)` rows of the xref table.
List<({int offset, String type})> _xrefEntries(Uint8List bytes) {
  final text = _decode(bytes);
  final start = text.lastIndexOf('startxref\n');
  final xrefOffset = int.parse(
    text.substring(start + 'startxref\n'.length).split('\n').first,
  );
  final xref = text.substring(xrefOffset);
  final lines = xref.split('\n');
  final count = int.parse(lines[1].split(' ').last);
  return [
    for (var i = 0; i < count; i++)
      (
        offset: int.parse(lines[2 + i].substring(0, 10)),
        type: lines[2 + i].substring(17, 18),
      ),
  ];
}

void main() {
  group('buildPdfBytes', () {
    test('emits a PDF header and trailer', () {
      final bytes = buildPdfBytes([
        PdfPage([const PdfTextLine('Hello', x: 50, y: 800)]),
      ]);
      final text = _decode(bytes);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text.endsWith('%%EOF\n'), isTrue);
      expect(text, contains('Hello'));
    });

    test('every xref offset points at its object header', () {
      final bytes = buildPdfBytes([
        PdfPage([const PdfTextLine('One', x: 50, y: 800)]),
        PdfPage([const PdfTextLine('Two', x: 50, y: 800)]),
      ]);
      final text = _decode(bytes);
      final entries = _xrefEntries(bytes);
      expect(entries, hasLength(10)); // object 0 + catalog, pages, 3 fonts, 2 pages, 2 streams
      expect(entries.first.type, 'f'); // object 0 is the free head
      for (var i = 1; i < entries.length; i++) {
        expect(
          text.substring(entries[i].offset).startsWith('$i 0 obj'),
          isTrue,
          reason: 'object $i should start at its xref offset',
        );
        expect(entries[i].type, 'n');
      }
    });

    test('pages are counted and referenced', () {
      final bytes = buildPdfBytes([
        PdfPage([const PdfTextLine('One', x: 50, y: 800)]),
        PdfPage([const PdfTextLine('Two', x: 50, y: 800)]),
      ]);
      final text = _decode(bytes);
      expect(text, contains('/Count 2'));
      expect(text, contains('/Type /Page '));
    });

    test('an empty page list still produces one blank page', () {
      final text = _decode(buildPdfBytes(const []));
      expect(text, contains('/Count 1'));
      expect(text, contains('/Type /Page '));
    });

    test('escapes parentheses and backslashes', () {
      final text = _decode(
        buildPdfBytes([
          PdfPage([const PdfTextLine(r'a (b) \ c', x: 50, y: 800)]),
        ]),
      );
      expect(text, contains(r'a \(b\) \\ c'));
    });

    test('maps the em dash to its WinAnsi byte rather than a fallback', () {
      final bytes = buildPdfBytes([
        PdfPage([const PdfTextLine('a — b', x: 50, y: 800)]),
      ]);
      expect(bytes.contains(0x97), isTrue);
      expect(_decode(bytes), isNot(contains('a ? b')));
    });

    test('drops coordinates trailing .00 but keeps real decimals', () {
      final text = _decode(
        buildPdfBytes([
          PdfPage([
            const PdfTextLine('x', x: 50, y: 800),
            const PdfTextLine('y', x: 50.5, y: 799.25),
          ]),
        ]),
      );
      expect(text, contains('50 800 Td'));
      expect(text, contains('50.50 799.25 Td'));
    });

    test('is deterministic for identical input', () {
      List<int> build() => buildPdfBytes([
        PdfPage([const PdfTextLine('same', x: 10, y: 20)]),
      ]);
      expect(build(), build());
    });
  });

  group('PdfFont', () {
    test('exposes distinct base fonts and resource names', () {
      expect(PdfFont.helvetica.baseFont, 'Helvetica');
      expect(PdfFont.helveticaBold.baseFont, 'Helvetica-Bold');
      expect(PdfFont.courier.baseFont, 'Courier');
      expect(
        PdfFont.values.map((font) => font.resourceName).toSet(),
        hasLength(PdfFont.values.length),
      );
    });
  });
}
