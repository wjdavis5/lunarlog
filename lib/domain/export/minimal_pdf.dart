/// A minimal, dependency-free PDF 1.4 writer (Issue #154).
///
/// Why hand-rolled rather than a package: the clinical export's acceptance
/// criteria require a test that asserts each required *section* is present
/// in the produced bytes. The `pdf` package (the de-facto pure-Dart choice)
/// deflate-compresses its content streams, so section text is not visible
/// in the output without a decompressor; this writer emits uncompressed
/// content streams, which makes the document's text searchable and
/// copy-pasteable for a clinician *and* directly assertable in a unit test.
/// It also keeps the export dependency-free and fully deterministic — the
/// same summary always yields byte-identical output.
///
/// Scope: positioned lines of base-14 text only (Helvetica, Helvetica-Bold,
/// Courier) on A4 portrait pages. No images, no vector graphics, no
/// embedding — exactly what the clinical summary layout needs. This file is
/// deliberately content-agnostic; the clinical document's own layout lives
/// in `clinical_pdf.dart`.
///
/// Pure Dart: no Flutter, no `dart:io`, no platform channels. Text is
/// encoded as WinAnsi (the base-14 fonts' declared `/Encoding`), so common
/// typographic punctuation (em/en dash, curly quotes, ellipsis) renders
/// correctly; an unmapped code unit degrades to `?` rather than emitting an
/// invalid byte.
library;

import 'dart:typed_data';

/// A base-14 font this writer can reference (never embedded).
enum PdfFont {
  helvetica,
  helveticaBold,
  courier;

  /// The `/BaseFont` name.
  String get baseFont => switch (this) {
    PdfFont.helvetica => 'Helvetica',
    PdfFont.helveticaBold => 'Helvetica-Bold',
    PdfFont.courier => 'Courier',
  };

  /// The resource key a page's content stream uses (`/F1`, `/F2`, ...).
  String get resourceName => switch (this) {
    PdfFont.helvetica => 'F1',
    PdfFont.helveticaBold => 'F2',
    PdfFont.courier => 'F3',
  };
}

/// One positioned line of text. [x]/[y] are in PDF user-space points with
/// the origin at the page's bottom-left corner.
class PdfTextLine {
  const PdfTextLine(
    this.text, {
    required this.x,
    required this.y,
    this.font = PdfFont.helvetica,
    this.size = 10,
  });

  final String text;
  final double x;
  final double y;
  final PdfFont font;
  final double size;
}

/// One page: its lines, in paint order.
class PdfPage {
  PdfPage(this.lines);

  final List<PdfTextLine> lines;
}

/// A4 portrait, in PDF points (1/72 inch).
const double kPdfPageWidth = 595;
const double kPdfPageHeight = 842;

const int _kCatalogObject = 1;
const int _kPagesObject = 2;
const int _kFirstFontObject = 3;

/// The object number of page [index]'s `/Page` dictionary.
int _pageObject(int index) => _kFirstFontObject + PdfFont.values.length + index * 2;

/// The object number of page [index]'s content stream.
int _contentObject(int index) => _pageObject(index) + 1;

/// Serializes [pages] to a complete PDF 1.4 byte stream.
///
/// An empty [pages] list produces a single blank page, so the result is
/// always a structurally valid document.
Uint8List buildPdfBytes(List<PdfPage> pages) {
  final effectivePages = pages.isEmpty ? [PdfPage(const [])] : pages;
  return _serialize(_buildBodies(effectivePages));
}

/// Writes the PDF header, each object body, then the cross-reference
/// table/trailer, returning the completed bytes. The object byte offsets
/// are counted from the first header byte, which is why the header is
/// written before the bodies are measured.
Uint8List _serialize(List<List<int>> bodies) {
  final output = BytesBuilder();
  // The `%âãÏÓ` comment marks the file as binary for transfer tools.
  output.add(const [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34, 0x0A]);
  output.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  final offsets = <int>[];
  for (var i = 0; i < bodies.length; i++) {
    offsets.add(output.length);
    output.add(_ascii('${i + 1} 0 obj\n'));
    output.add(bodies[i]);
    output.add(_ascii('\nendobj\n'));
  }
  final xrefOffset = output.length;
  output.add(_ascii('xref\n0 ${bodies.length + 1}\n'));
  output.add(_ascii('0000000000 65535 f \n'));
  for (final offset in offsets) {
    output.add(_ascii('${offset.toString().padLeft(10, '0')} 00000 n \n'));
  }
  output.add(
    _ascii(
      'trailer\n<< /Size ${bodies.length + 1} /Root $_kCatalogObject 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    ),
  );
  return output.takeBytes();
}

/// All object bodies, indexed by `objectNumber - 1`.
List<List<int>> _buildBodies(List<PdfPage> pages) => [
  _ascii(
    '<< /Type /Catalog /Pages $_kPagesObject 0 R >>',
  ),
  _ascii(
    '<< /Type /Pages /Kids ['
    '${[for (var i = 0; i < pages.length; i++) '${_pageObject(i)} 0 R'].join(' ')}'
    '] /Count ${pages.length} >>',
  ),
  for (final font in PdfFont.values)
    _ascii(
      '<< /Type /Font /Subtype /Type1 /BaseFont /${font.baseFont} '
      '/Encoding /WinAnsiEncoding >>',
    ),
  for (var i = 0; i < pages.length; i++) ...[
    _ascii(
      '<< /Type /Page /Parent $_kPagesObject 0 R '
      '/MediaBox [0 0 $kPdfPageWidth $kPdfPageHeight] '
      '/Resources << /Font << '
      '${[for (final f in PdfFont.values) '/${f.resourceName} ${_kFirstFontObject + f.index} 0 R'].join(' ')}'
      ' >> >> /Contents ${_contentObject(i)} 0 R >>',
    ),
    _contentStream(pages[i].lines),
  ],
];

/// `<< /Length N >>\nstream\n<uncompressed content>\nendstream` for [lines].
List<int> _contentStream(List<PdfTextLine> lines) {
  final content = <int>[];
  for (final line in lines) {
    content.addAll(
      _ascii(
        'BT /${line.font.resourceName} ${_number(line.size)} Tf '
        '${_number(line.x)} ${_number(line.y)} Td ',
      ),
    );
    content.addAll(_pdfString(line.text));
    content.addAll(_ascii(' Tj ET\n'));
  }
  final stream = <int>[
    ..._ascii('<< /Length ${content.length} >>\nstream\n'),
    ...content,
    ..._ascii('endstream'),
  ];
  return stream;
}

/// Formats [value] with up to two decimals, dropping a trailing `.00` so
/// generated coordinates stay compact.
String _number(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}

/// [text] as a complete PDF literal string — WinAnsi-encoded, escaped, and
/// wrapped in the `(`/`)` delimiters the syntax (and a `Tj` operand)
/// requires.
List<int> _pdfString(String text) {
  final bytes = <int>[0x28]; // opening `(`
  for (final unit in text.codeUnits) {
    final mapped = _winAnsiByte(unit);
    if (mapped == 0x28 || mapped == 0x29 || mapped == 0x5C) {
      bytes.add(0x5C); // backslash-escape `(`, `)` and `\`.
    }
    bytes.add(mapped);
  }
  bytes.add(0x29); // closing `)`
  return bytes;
}

/// WinAnsi punctuation outside Latin-1 (`0xA0`-`0xFF`), which WinAnsi shares
/// with ISO-8859-1.
const Map<int, int> _winAnsiPunctuation = {
  0x20AC: 0x80, // euro sign
  0x2026: 0x85, // horizontal ellipsis
  0x2018: 0x91, // left single quote
  0x2019: 0x92, // right single quote
  0x201C: 0x93, // left double quote
  0x201D: 0x94, // right double quote
  0x2022: 0x95, // bullet
  0x2013: 0x96, // en dash
  0x2014: 0x97, // em dash
  0x2122: 0x99, // trade mark sign
};

/// The WinAnsi byte for [unit] (a UTF-16 code unit). ASCII and Latin-1
/// printable characters map through unchanged; known typographic
/// punctuation maps via [_winAnsiPunctuation]; everything else (control
/// characters included) degrades to `?`.
int _winAnsiByte(int unit) {
  if (unit >= 0x20 && unit <= 0x7E) return unit;
  if (unit >= 0xA0 && unit <= 0xFF) return unit;
  return _winAnsiPunctuation[unit] ?? 0x3F;
}

/// ASCII bytes for a string this file authored (never user data).
List<int> _ascii(String value) => value.codeUnits;
