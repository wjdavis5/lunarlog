/// Renders a [ClinicalPdfSummary] to an uncompressed PDF byte stream
/// (Issue #154).
///
/// Pure Dart and content-only: the summary model is built in
/// `clinical_pdf_summary.dart`, and the temp-file + share-sheet delivery
/// lives in `lib/data/export/clinical_pdf_writer.dart`. This file does the
/// page layout (A4 portrait, paginated) and hands each page's positioned
/// lines to `minimal_pdf.dart`.
///
/// The document is deliberately text-only and uncompressed, so it is
/// searchable, copy-pasteable, and directly assertable by the test suite.
/// Every derived figure is paired with the caller-injected disclaimer copy
/// the summary carries; nothing here computes or adds a prediction.
library;

import 'dart:typed_data';

import 'clinical_pdf_summary.dart';
import 'minimal_pdf.dart';

const double _kMargin = 50;

/// The symptom grid's fixed label-column width, in monospace characters.
///
/// Grid labels are not all short: a custom tag may be up to 40 characters
/// and an unmapped import option code renders verbatim (issue #1204), so
/// anything longer is truncated to `width - 1` characters plus an ellipsis
/// (via [_gridRowLabel]) rather than silently cut, and its full text is
/// listed below the grid.
const int _kGridLabelWidth = 22;

/// Renders [summary] to a complete PDF document.
Uint8List buildClinicalPdfDocument(ClinicalPdfSummary summary) {
  final layout = _PdfLayout();
  _addHeader(layout, summary);
  _addNotDiagnosis(layout, summary);
  _addMethodNote(layout, summary);
  _addStatistics(layout, summary);
  _addCycleTable(layout, summary);
  _addSymptomGrid(layout, summary);
  _addMedications(layout, summary);
  return layout.finish();
}

void _addHeader(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.line(
    'lunarlog clinical cycle summary',
    font: PdfFont.helveticaBold,
    size: 18,
  );
  layout.line(
    'Profile: ${summary.profileDisplayName}',
    size: 12,
    before: 8,
  );
  layout.line('Cycle window: ${summary.rangeLabel}', size: 11, before: 2);
  layout.line(
    'Generated: ${_formatUtc(summary.generatedAt)}',
    size: 10,
    before: 2,
  );
}

void _addNotDiagnosis(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.paragraph(
    kClinicalSummaryNotDiagnosisLine,
    size: 10,
    before: 12,
  );
}

void _addMethodNote(_PdfLayout layout, ClinicalPdfSummary summary) {
  final notebook = StringBuffer(
    'This summary reports data logged by the profile\'s operator or '
    'guardian. It covers the ${summary.cyclesInRange} completed cycle(s) '
    'whose start falls in the selected window. ',
  );
  if (summary.excludedCycleCount > 0) {
    notebook.write(
      '${summary.excludedCycleCount} cycle(s) excluded from averages are '
      'omitted from the statistics and the symptom grid. ',
    );
  }
  notebook.write(
    'Cycles shorter than 15 days are omitted from cycle length statistics '
    'and the symptom grid, and flagged as irregular. '
    'Cycles longer than 60 days are omitted from the symptom grid but '
    'retained in the statistics and the cycle table. No fertility, '
    'ovulation, or conception estimate is included. '
    '$kClinicalSummaryPainScaleNote',
  );
  layout.paragraph(notebook.toString(), size: 9, before: 10);
}

void _addStatistics(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.line('Cycle statistics', font: PdfFont.helveticaBold, size: 13, before: 14);
  final cycleStat = summary.cycleLengthStat;
  if (cycleStat == null) {
    layout.line('No completed cycles in the selected range.', size: 10);
    return;
  }
  layout.line(
    _statLine('Cycle length (days)', cycleStat),
    font: PdfFont.courier,
    size: 8.5,
    before: 4,
  );
  final periodStat = summary.periodLengthStat;
  if (periodStat != null) {
    layout.line(
      _statLine('Period length (days)', periodStat),
      font: PdfFont.courier,
      size: 8.5,
    );
  }
  for (final disclaimer in summary.derivedValueDisclaimers) {
    layout.paragraph(disclaimer, size: 8, before: 5);
  }
}

String _statLine(String label, ClinicalRangeStat stat) =>
    '${_pad(label, 22)} mean ${stat.mean.toStringAsFixed(1).padLeft(5)}  '
    'median ${_pad(_trimDouble(stat.median), 5)}  '
    'range ${stat.min}-${stat.max}  (n=${stat.count})';

void _addCycleTable(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.line('Completed cycles', font: PdfFont.helveticaBold, size: 13, before: 14);
  if (summary.cycles.isEmpty) {
    layout.line('No completed cycles in the selected range.', size: 10);
    return;
  }
  layout.line(
    '${_pad('#', 3)}${_pad('start', 12)}${_pad('end', 12)}'
    '${_pad('cycle', 7)}${_pad('period', 8)}'
    '${_pad('irregular', 11)}omitted',
    font: PdfFont.courier,
    size: 8,
    before: 4,
  );
  for (final row in summary.cycles) {
    layout.line(
      '${_pad('${row.number}', 3)}${_pad(row.startIso, 12)}'
      '${_pad(row.endIso, 12)}${_pad('${row.cycleLengthDays}', 7)}'
      '${_pad('${row.periodLengthDays}', 8)}'
      '${_pad(row.isIrregular ? 'yes' : 'no', 11)}'
      '${row.excludedFromAverages ? 'yes' : 'no'}',
      font: PdfFont.courier,
      size: 8,
    );
  }
}

void _addSymptomGrid(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.line(
    'Symptom frequency by cycle day',
    font: PdfFont.helveticaBold,
    size: 13,
    before: 14,
  );
  final maxDay = summary.maxCycleDay;
  if (summary.symptomGrid.isEmpty || maxDay == 0) {
    layout.line(
      'No symptoms were logged in the cycles shown in this grid.',
      size: 10,
    );
    return;
  }
  final size = maxDay <= 35 ? 7.0 : 5.0;
  layout.line(
    'Across the ${summary.graphCycleCount} cycle(s) shown; each column is a '
    'cycle day. `.` means no cycles logged that symptom on that day.',
    size: 8,
    before: 4,
  );
  layout.line(
    '${_pad('symptom', _kGridLabelWidth)}${_gridHeader(maxDay)}',
    font: PdfFont.courier,
    size: size,
  );
  final shortenedLabels = <({String truncated, String full})>[];
  for (final row in summary.symptomGrid) {
    final (:display, :shortened) = _gridRowLabel(row.label);
    if (shortened) shortenedLabels.add((truncated: display, full: row.label));
    layout.line(
      '$display${_gridCounts(row.counts)}',
      font: PdfFont.courier,
      size: size,
    );
  }
  if (shortenedLabels.isNotEmpty) {
    // Issue #1204: the truncated column must never leave a count
    // unexplained — every shortened label is mapped back to its full text.
    // One mapping per paragraph, so a mapping wraps as a whole rather than
    // ever breaking inside the full label at realistic label lengths (a
    // 40-character tag maps to a 65-character line, well under one line
    // at this size).
    layout.line('Labels shortened in the grid:', size: 8, before: 4);
    for (final (:truncated, :full) in shortenedLabels) {
      layout.paragraph('$truncated = $full', size: 8);
    }
  }
}

String _gridHeader(int maxDay) => [
  for (var day = 1; day <= maxDay; day++) _pad('$day', 2),
].join();

String _gridCounts(List<int> counts) => [
  for (final count in counts) count == 0 ? ' .' : _pad('$count', 2),
].join();

void _addMedications(_PdfLayout layout, ClinicalPdfSummary summary) {
  layout.line(
    'Medications and birth control',
    font: PdfFont.helveticaBold,
    size: 13,
    before: 16,
  );
  if (summary.medications.isEmpty && summary.birthControlMethod == null) {
    layout.line('None recorded.', size: 10);
  } else {
    for (final medication in summary.medications) {
      layout.line('• $medication', size: 10);
    }
    final method = summary.birthControlMethod;
    if (method != null) layout.line('Birth control: $method', size: 10);
  }
  layout.line('Conditions', font: PdfFont.helveticaBold, size: 13, before: 12);
  if (summary.conditions.isEmpty) {
    layout.line('None recorded.', size: 10);
  } else {
    for (final condition in summary.conditions) {
      layout.line('• $condition', size: 10);
    }
  }
}

/// Accumulates positioned lines into pages, inserting a new page whenever
/// the next line would fall below the bottom margin. All layout state is
/// private to this file.
class _PdfLayout {
  final List<PdfPage> _pages = [];
  List<PdfTextLine> _lines = [];
  double _y = kPdfPageHeight - _kMargin;

  /// Appends one (already wrapped) line [text] at [indent] from the left
  /// margin, preceded by a [before]-point vertical gap.
  void line(
    String text, {
    PdfFont font = PdfFont.helvetica,
    double size = 10,
    double indent = 0,
    double before = 0,
  }) {
    _y -= before;
    if (_y < _kMargin) _startPage();
    _lines.add(
      PdfTextLine(
        text,
        x: _kMargin + indent,
        y: _y,
        font: font,
        size: size,
      ),
    );
    _y -= size * 1.35;
  }

  /// Wraps [text] to the printable width and appends each resulting line.
  void paragraph(
    String text, {
    double size = 10,
    double before = 0,
  }) {
    final maxChars = _maxCharsFor(size);
    var hasText = false;
    final buffer = StringBuffer();
    for (final word in text.split(' ')) {
      if (buffer.isEmpty) {
        buffer.write(word);
        continue;
      }
      if (buffer.length + 1 + word.length <= maxChars) {
        buffer.write(' $word');
        continue;
      }
      line(
        buffer.toString(),
        size: size,
        before: hasText ? 0 : before,
      );
      hasText = true;
      buffer
        ..clear()
        ..write(word);
    }
    if (buffer.isNotEmpty) {
      line(buffer.toString(), size: size, before: hasText ? 0 : before);
    }
  }

  int _maxCharsFor(double size) =>
      ((kPdfPageWidth - _kMargin * 2) / (size * 0.5)).floor();

  void _startPage() {
    _pages.add(PdfPage(List.unmodifiable(_lines)));
    _lines = [];
    _y = kPdfPageHeight - _kMargin;
  }

  Uint8List finish() {
    if (_lines.isNotEmpty) _pages.add(PdfPage(List.unmodifiable(_lines)));
    return buildPdfBytes(_pages);
  }
}

String _formatUtc(DateTime instant) {
  final utc = instant.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
      '${two(utc.hour)}:${two(utc.minute)} UTC';
}

/// Right-pads [value] to [width], truncating anything longer so a
/// monospace column never shifts. The symptom grid's row labels use
/// [_gridRowLabel] instead, so a cut is always marked (issue #1204).
String _pad(String value, int width) => value.length >= width
    ? value.substring(0, width)
    : value.padRight(width);

/// The grid's rendering of a row label: right-padded to [_kGridLabelWidth]
/// so the monospace column never shifts, with anything longer truncated to
/// `_kGridLabelWidth - 1` characters plus an ellipsis (issue #1204) so a
/// cut is visible even mid-word. [shortened] reports whether the label was
/// cut, so the caller can list its full text below the grid.
({String display, bool shortened}) _gridRowLabel(String label) =>
    label.length > _kGridLabelWidth
        ? (
            display: '${label.substring(0, _kGridLabelWidth - 1)}…',
            shortened: true,
          )
        : (display: label.padRight(_kGridLabelWidth), shortened: false);

String _trimDouble(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
