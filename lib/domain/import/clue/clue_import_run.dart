/// Post-import summary and idempotency helpers for a Clue file import
/// (Issue #199, epic: Import).
///
/// The Clue export parser (`clue_export_parser.dart`) already escapes an
/// unrecognised `type` or `value` shape to [ClueUnknownDatapoint] instead of
/// rejecting it; this module is what makes that escape hatch *accounted
/// for*: it derives the stable per-row provenance ids a re-import
/// collapses onto, and it builds the explicit "what did not come across"
/// summary an import run returns.
///
/// Pure Dart, no drift/Flutter/`dart:io` imports (R14/R16). The effectful
/// half — writing datapoints to the store — lives in
/// `lib/data/import/clue_importer.dart`, which calls [summarizeClueImport]
/// and the `clue*SourceId` builders below.
///
/// Scope notes (see the issue's explicit boundaries):
/// * Only what already has a home on main is mapped here: [kClueTypeMap]
///   categories/options (Issue #190) and `flowLevelFromClue` (Issue #247).
///   Nothing in this file invents a Clue→category mapping (#190, owned
///   elsewhere) or a custom-tag registry (#257) — an unrecognised type or
///   value shape is stored in `observations.raw` and counted, never mapped.
/// * `raw` is payload, not provenance: tombstoning clears it (mirroring
///   the server's `observations_tombstone_payload_check`), while `source`/
///   `source_id`/`import_id` survive (Issue #159).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../limits.dart';
import 'clue_cycle_reconstruction.dart';
import 'clue_datapoint.dart';
import 'clue_export_parser.dart';
import 'clue_option_map.dart';

/// The `source` stamped on every row a Clue file import writes (Issue
/// #159's `day_entries`/`observations` closed sets both carry it).
const String kClueImportSource = 'clue_import';

/// `observations.category` for an unrecognised Clue `type` (Issue #199):
/// the original type string rides `code` (truncated to the column bound
/// when absurdly long) and the full datapoint rides `raw`, so the row is
/// queryable as a group without inventing a mapping (#190 owns mappings).
const String kClueUnmappedCategory = 'unmapped';

/// Display cap for one rendered unmapped row
/// ([describeUnmappedRaw]): a readable line, never a full JSON dump.
const int kMaxUnmappedDisplayLength = 160;

/// A free-text/notes heuristic bound ([_looksLikeFreeText]): Clue option
/// strings are short snake_case codes, so a string past this length inside
/// an unrecognised value is almost certainly user-entered text (a note)
/// rather than another enum the mapping table missed.
const int kFreeTextHeuristicLength = 32;

/// Cap on stored per-row skip details ([ClueImportSummary.skippedDetails]):
/// the count is always exact, but only the first N messages are kept so
/// one pathological file cannot bloat the summary object itself.
const int kMaxSkippedDetails = 20;

/// SHA-256 hex of the original export file's bytes — the idempotency
/// anchor for a Clue import run. The per-row `source_id`s below all embed
/// its 8-character tag, so importing the same file twice addresses the
/// same rows (a no-op on content equality) instead of duplicating them.
/// Computed over the raw bytes (not the decoded JSON) so byte-identical
/// files always agree regardless of parse normalisation.
String clueFileChecksum(List<int> bytes) => sha256.convert(bytes).toString();

/// Short tag embedded in every Clue `source_id` for one file.
String _checksumTag(String fileChecksum) =>
    fileChecksum.length >= 8 ? fileChecksum.substring(0, 8) : fileChecksum;

/// Stable day-entry `source_id` for one Clue date in one file: one row per
/// (file, date), so a re-import finds the same row via
/// `findDayEntryBySource` instead of inserting a duplicate.
String clueDaySourceId({
  required String fileChecksum,
  required String dateIso,
}) =>
    'clue:${_checksumTag(fileChecksum)}:$dateIso';

/// Stable observation `source_id` for one datapoint in one file. [ordinal]
/// disambiguates several datapoints sharing a (date, type) — e.g. two
/// `pain` options on one day. [type] is truncated so the id always fits
/// `kMaxObservationSourceIdLength` even for an absurdly long unrecognised
/// type string (the full string survives in `raw` regardless).
String clueObservationSourceId({
  required String fileChecksum,
  required String dateIso,
  required String type,
  required int ordinal,
}) {
  final safeType = type.length > 48 ? type.substring(0, 48) : type;
  return 'clue:${_checksumTag(fileChecksum)}:$dateIso:$safeType:$ordinal';
}

/// The stored `raw` JSON text for an unrecognised datapoint: the entire
/// original `{date, type, value}` map. Returns null only when the payload
/// cannot fit `kMaxObservationRawLength` even reduced to its identifying
/// `{date, type}` subset — the row is still written (category/code carry
/// the type), and the caller records the reduction in the summary rather
/// than dropping the row silently.
String? clueRawJson(Map<String, Object?> raw) {
  final full = jsonEncode(raw);
  if (_utf8Length(full) <= kMaxObservationRawLength) return full;
  final reduced = jsonEncode({'date': raw['date'], 'type': raw['type']});
  if (_utf8Length(reduced) <= kMaxObservationRawLength) return reduced;
  return null;
}

int _utf8Length(String value) => utf8.encode(value).length;

/// Readable one-line text for a stored unmapped row (Issue #199 AC6): the
/// day sheet renders this, never the raw JSON and never nothing. [raw] is
/// the decoded `observations.raw` map. Unknown structures degrade to a
/// truncated JSON excerpt rather than throwing — rendering must never fail
/// on the very rows it exists to make visible.
String describeUnmappedRaw(Map<String, Object?> raw) {
  final type = raw['type'];
  final valueText = _compactValue(raw['value']);
  final label = type is String && type.isNotEmpty ? type : 'unrecognised data';
  if (valueText.isEmpty || label == valueText) return _truncateDisplay(label);
  return _truncateDisplay('$label: $valueText');
}

/// Compacts one Clue `value` payload to display text: a lone option string
/// reads as itself, a list of `{option}` maps joins with commas, and
/// anything else degrades to compact JSON.
String _compactValue(Object? value) {
  if (value is String) return value;
  if (value is Map) {
    final option = value['option'];
    if (option is String) return option;
  }
  if (value is List) {
    final options = <String>[];
    for (final entry in value) {
      if (entry is Map && entry['option'] is String) {
        options.add(entry['option'] as String);
      } else {
        return _compactJson(value);
      }
    }
    return options.join(', ');
  }
  return _compactJson(value);
}

String _compactJson(Object? value) {
  if (value == null) return '';
  try {
    return jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}

String _truncateDisplay(String text) => text.length <= kMaxUnmappedDisplayLength
    ? text
    : '${text.substring(0, kMaxUnmappedDisplayLength)}…';

/// Whether an unrecognised `value` looks like user-entered free text (a
/// note) rather than another missed enum: any string past
/// [kFreeTextHeuristicLength] anywhere inside it. Clue option strings are
/// short codes, so this only fires on genuinely text-shaped content.
bool looksLikeFreeText(Object? value) {
  if (value is String) return value.length > kFreeTextHeuristicLength;
  if (value is Map) return value.values.any(looksLikeFreeText);
  if (value is List) return value.any(looksLikeFreeText);
  return false;
}

/// The outcome of one Clue file import run: what the file carried
/// (planned counts, derived even without writing anything) plus what the
/// run actually wrote. [summarizeClueImport] fills the planned half with
/// zeroes for the applied half; the data-layer importer fills in the
/// applied half after writing.
class ClueImportSummary {
  const ClueImportSummary({
    required this.dayCount,
    required this.datapointCount,
    required this.unmappedTypeCount,
    required this.unmappedTypes,
    required this.unmappedValueCount,
    required this.cycleBoundariesReconstructed,
    required this.skippedRows,
    required this.notesDetected,
    this.daysWritten = 0,
    this.daysUnchanged = 0,
    this.observationsWritten = 0,
    this.observationsUnchanged = 0,
    this.rowsSkipped = 0,
    this.skippedDetails = const [],
  });

  /// Distinct dates carrying at least one datapoint.
  final int dayCount;

  /// Total datapoints parsed (mapped and unmapped alike).
  final int datapointCount;

  /// Datapoints with an unrecognised `type` ([ClueUnknownReason.unknownType]).
  final int unmappedTypeCount;

  /// Distinct unrecognised `type` strings, sorted — the "what" behind
  /// [unmappedTypeCount].
  final List<String> unmappedTypes;

  /// Datapoints whose `type` is known but whose `value` shape was not
  /// ([ClueUnknownReason.unknownValueShape]).
  final int unmappedValueCount;

  /// Period-episode boundaries derived from bleed days
  /// ([reconstructClueEpisodes]): reported, not stored — Clue's export
  /// carries no cycle-boundary field at all, so these are reconstructed
  /// the same way the app derives its own episodes.
  final int cycleBoundariesReconstructed;

  /// Rows too malformed to carry a usable date/type
  /// ([ClueExportParseResult.skipped]).
  final int skippedRows;

  /// Whether any unrecognised value looked like free-text notes
  /// ([looksLikeFreeText]) — kept in `raw`, flagged here.
  final bool notesDetected;

  /// Day-entry rows actually written by the run.
  final int daysWritten;

  /// Day-entry rows already holding identical content (re-import no-ops).
  final int daysUnchanged;

  /// Observation rows actually written by the run.
  final int observationsWritten;

  /// Observation rows already holding identical content.
  final int observationsUnchanged;

  /// Rows that could not be written at all (e.g. past a storage bound),
  /// with the first [kMaxSkippedDetails] reasons in [skippedDetails].
  /// Never silent: every one is counted here.
  final int rowsSkipped;

  /// Human-readable reasons for [rowsSkipped], capped at
  /// [kMaxSkippedDetails] entries (the count stays exact past the cap).
  /// Carries shapes and bounds, never health content.
  final List<String> skippedDetails;

  /// Every unmapped datapoint in the file.
  int get unmappedTotal => unmappedTypeCount + unmappedValueCount;

  /// A re-import is a no-op when nothing was written and nothing was
  /// skipped: every addressed row already held identical content.
  bool get isNoop =>
      daysWritten == 0 && observationsWritten == 0 && rowsSkipped == 0;

  ClueImportSummary withApplied({
    required int daysWritten,
    required int daysUnchanged,
    required int observationsWritten,
    required int observationsUnchanged,
    required int rowsSkipped,
    required List<String> skippedDetails,
  }) =>
      ClueImportSummary(
        dayCount: dayCount,
        datapointCount: datapointCount,
        unmappedTypeCount: unmappedTypeCount,
        unmappedTypes: unmappedTypes,
        unmappedValueCount: unmappedValueCount,
        cycleBoundariesReconstructed: cycleBoundariesReconstructed,
        skippedRows: skippedRows,
        notesDetected: notesDetected,
        daysWritten: daysWritten,
        daysUnchanged: daysUnchanged,
        observationsWritten: observationsWritten,
        observationsUnchanged: observationsUnchanged,
        rowsSkipped: rowsSkipped,
        skippedDetails: skippedDetails,
      );

  /// The explicit "what did not come across" summary (Issue #199 AC4):
  /// reconstructed-boundary count, the statically-not-carried-over cycle
  /// state, the notes flag, and every unmapped/skipped count. Rendered by
  /// the import UI; every line is fixed copy except the interpolated
  /// counts and type names.
  List<String> get summaryLines => [
        'Imported $dayCount ${dayCount == 1 ? 'day' : 'days'} '
            '($datapointCount ${datapointCount == 1 ? 'datapoint' : 'datapoints'}).',
        'Cycle boundaries reconstructed: $cycleBoundariesReconstructed.',
        if (unmappedTotal > 0)
          'Unrecognised data kept as-is: $unmappedTotal '
              '($unmappedTypeCount unknown ${_plural(unmappedTypeCount, 'type', 'types')}, '
              '$unmappedValueCount unknown ${_plural(unmappedValueCount, 'value', 'values')}).'
        else
          'Everything in the file had a home — nothing needed the unrecognised-data fallback.',
        for (final type in unmappedTypes) 'Unrecognised type kept: $type.',
        if (notesDetected)
          'Notes were detected and kept with the unrecognised data.'
        else
          'No notes were detected.',
        if (skippedRows > 0)
          '$skippedRows ${_plural(skippedRows, 'row', 'rows')} could not be read at all and were skipped.'
        else
          'Every row in the file was readable.',
        if (rowsSkipped > 0)
          '$rowsSkipped ${_plural(rowsSkipped, 'row', 'rows')} could not be stored.',
        ...notCarriedOver,
      ];

  static String _plural(int n, String singular, String plural) =>
      n == 1 ? singular : plural;

  /// Cycle-level state Clue's export does not expose at all, so no import
  /// can carry it over (Issue #199): stated explicitly rather than
  /// silently lost. Static copy — independent of any file's content.
  static const List<String> notCarriedOver = [
    'Cycle boundaries are reconstructed from bleeding days, not imported.',
    'Excluded-cycle flags are not carried over.',
    'Pregnancy and birth-control state are not carried over.',
    'Manually edited cycle averages and modes are not carried over.',
    'Manually started cycles are not carried over.',
  ];
}

/// Builds the planned half of a [ClueImportSummary] from one parse result
/// — pure, writing nothing. Cycle boundaries come from
/// [reconstructClueEpisodes] (bleed-day runs, spotting excluded); unknown
/// counts split by [ClueUnknownReason]; notes detection scans only the
/// unrecognised values (mapped options are known-shaped by construction).
ClueImportSummary summarizeClueImport(ClueExportParseResult result) {
  final datapoints = result.datapoints;
  var unmappedTypeCount = 0;
  var unmappedValueCount = 0;
  final unmappedTypes = <String>{};
  var notesDetected = false;
  final dates = <String>{};
  for (final datapoint in datapoints) {
    dates.add(datapoint.date.iso);
    if (datapoint is ClueUnknownDatapoint) {
      switch (datapoint.reason) {
        case ClueUnknownReason.unknownType:
          unmappedTypeCount++;
          unmappedTypes.add(datapoint.clueType);
        case ClueUnknownReason.unknownValueShape:
          unmappedValueCount++;
      }
      if (!notesDetected && looksLikeFreeText(datapoint.raw['value'])) {
        notesDetected = true;
      }
    }
  }
  final boundaries = reconstructClueEpisodes(datapoints).length;
  final sortedTypes = unmappedTypes.toList()..sort();
  return ClueImportSummary(
    dayCount: dates.length,
    datapointCount: datapoints.length,
    unmappedTypeCount: unmappedTypeCount,
    unmappedTypes: sortedTypes,
    unmappedValueCount: unmappedValueCount,
    cycleBoundariesReconstructed: boundaries,
    skippedRows: result.skipped.length,
    notesDetected: notesDetected,
  );
}

/// The `observations.category` for an unrecognised datapoint: the mapped
/// category when the `type` itself is known (only its `value` shape was
/// not), else [kClueUnmappedCategory]. Never invents a mapping — a `type`
/// absent from [kClueTypeMap] (and not numeric/`period`) has no home.
/// [numericCategory] covers the `bbt`/`temperature` family, whose mapped
/// category is `bbt` regardless of the value shape.
String unmappedCategoryFor(String clueType) {
  if (kClueTypeMap[clueType] != null) return kClueTypeMap[clueType]!.category;
  if (kClueNumericTypes.contains(clueType)) return 'bbt';
  if (clueType == 'period') return kClueUnmappedCategory;
  return kClueUnmappedCategory;
}
