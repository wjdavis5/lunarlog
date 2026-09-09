/// Parses a Clue export's `measurements.json` bytes into a typed
/// [ClueDatapoint] stream (Issue #190).
///
/// `measurements.json`'s root is a bare JSON array, one element per
/// `(day, category)` — never one element per day. This parser does not
/// group by date itself; `clue_cycle_reconstruction.dart` (and any later
/// per-day grouping the bulk-write step needs) works directly off the
/// flat [ClueExportParseResult.datapoints] list, each of which already
/// carries its own `date`.
///
/// Pure Dart, no drift/Flutter/`dart:io` imports (R14/R16); no `type` or
/// `option` value is ever fatal to the rest of the import — an
/// unrecognised `type` or `value` shape escapes to [ClueUnknownDatapoint]
/// (Issue #199's `observations.raw` hatch), and a row too malformed to
/// even carry a usable `date`/`type` is recorded in
/// [ClueExportParseResult.skipped] rather than aborting the parse. The one
/// case that *does* throw is the root JSON itself not being the expected
/// shape at all (not valid JSON, or not an array) — there is nothing
/// sensible to iterate in that case.
library;

import 'dart:convert';

import '../../models/local_date.dart';
import 'clue_datapoint.dart';
import 'clue_option_map.dart';

/// Thrown only when `measurements.json`'s bytes are not the expected shape
/// at all — see this library's doc comment for why every other malformed
/// row degrades instead of throwing.
///
/// [message] is always a fixed, static string — never the interpolated
/// `FormatException` this was raised from. `FormatException.toString()`
/// embeds a ~78-character excerpt of the source around the failure point,
/// and here the source is the user's own Clue export; `apikey`/exception
/// scrubbing in `lib/observability/scrub.dart` does not reduce exceptions
/// raised from `lib/domain/import/`, so that excerpt would reach Sentry
/// verbatim. [offset] carries only the byte offset
/// (`FormatException.offset`) where the failure was detected, never any
/// fragment of the bytes themselves.
class ClueImportException implements Exception {
  ClueImportException(this.message, {this.offset});

  final String message;
  final int? offset;

  @override
  String toString() => offset == null
      ? 'ClueImportException: $message'
      : 'ClueImportException: $message (offset: $offset)';
}

/// One `measurements.json` array element that could not be parsed at all:
/// a non-object element, a missing/non-string `date` or `type`, or a
/// `date` matching neither documented format. Recorded rather than
/// thrown, so one bad row never aborts the rest of the import.
///
/// **[raw] carries health content verbatim** — the entire original
/// (decoded-JSON) array element, whatever shape it was. Never log it, put
/// it in a Sentry breadcrumb, or otherwise interpolate it into a
/// diagnostic message; see [ClueUnknownDatapoint.raw]'s doc comment for
/// the same warning on the escape-hatch payload.
class ClueSkippedRow {
  ClueSkippedRow(this.index, this.reason, this.raw);

  final int index;
  final String reason;
  final Object? raw;
}

/// The full result of parsing one `measurements.json`: successfully
/// mapped (or escape-hatched — see [ClueUnknownDatapoint]) datapoints,
/// plus any rows too malformed to carry a `date`/`type` at all.
class ClueExportParseResult {
  ClueExportParseResult(this.datapoints, this.skipped);

  final List<ClueDatapoint> datapoints;
  final List<ClueSkippedRow> skipped;
}

/// Parses `measurements.json` bytes (already extracted from the export
/// zip — see `clue_zip_reader.dart`) into [ClueExportParseResult].
ClueExportParseResult parseClueDatapoints(List<int> jsonBytes) {
  final rows = _decodeRoot(jsonBytes);
  final datapoints = <ClueDatapoint>[];
  final skipped = <ClueSkippedRow>[];
  for (var i = 0; i < rows.length; i++) {
    final result = _parseRow(rows[i]);
    if (result.skipReason != null) {
      skipped.add(ClueSkippedRow(i, result.skipReason!, rows[i]));
    } else {
      datapoints.addAll(result.datapoints);
    }
  }
  return ClueExportParseResult(datapoints, skipped);
}

List<Object?> _decodeRoot(List<int> jsonBytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(_decodeClueJson(jsonBytes));
  } on FormatException catch (e) {
    throw ClueImportException(
      'measurements.json is not valid JSON',
      offset: e.offset,
    );
  }
  if (decoded is! List) {
    throw ClueImportException('measurements.json root must be a JSON array');
  }
  return decoded;
}

/// UTF-8 leading byte-order mark (`EF BB BF`) — some exporters prepend
/// one; `jsonDecode` treats it as invalid leading whitespace rather than
/// stripping it, which would otherwise fail an entire multi-year export
/// over three bytes.
const List<int> _utf8Bom = [0xEF, 0xBB, 0xBF];

/// Decodes [bytes] as UTF-8 for JSON parsing (Issue #190 review):
/// malformed sequences are replaced rather than thrown on
/// (`allowMalformed: true`) so a single bad byte anywhere in a
/// multi-year export never fails the whole decode, and a leading BOM is
/// stripped first so it never surfaces as a stray character before `[`.
String _decodeClueJson(List<int> bytes) {
  final hasBom = bytes.length >= _utf8Bom.length &&
      bytes[0] == _utf8Bom[0] &&
      bytes[1] == _utf8Bom[1] &&
      bytes[2] == _utf8Bom[2];
  final body = hasBom ? bytes.sublist(_utf8Bom.length) : bytes;
  return utf8.decode(body, allowMalformed: true);
}

class _RowResult {
  _RowResult.skip(this.skipReason) : datapoints = const [];
  _RowResult.ok(this.datapoints) : skipReason = null;

  final String? skipReason;
  final List<ClueDatapoint> datapoints;
}

_RowResult _parseRow(Object? rawRow) {
  if (rawRow is! Map) {
    return _RowResult.skip('row is not a JSON object');
  }
  final row = Map<String, Object?>.from(rawRow);
  final rawDate = row['date'];
  final rawType = row['type'];
  if (rawDate is! String || rawType is! String) {
    return _RowResult.skip('missing or non-string date/type');
  }
  final date = _tryParseClueDate(rawDate);
  if (date == null) {
    return _RowResult.skip('unrecognised date format: $rawDate');
  }
  return _mapRow(date, rawType, row['value'], row);
}

/// Bare `YYYY-MM-DD` or an ISO datetime (any offset, `Z` included) —
/// always via `slice(0, 10)` semantics, never a timezone conversion
/// (Issue #190: a `Z`-suffixed value is a serialised local calendar date,
/// not an instant to convert).
LocalDate? _tryParseClueDate(String raw) {
  if (raw.length < 10) return null;
  try {
    return LocalDate.fromIso(raw.substring(0, 10));
  } on ArgumentError {
    return null;
  }
}

/// Maps one row's `{type, value}` to its outcome. `"value": []` (a
/// multi-select category with nothing selected) is neither an unknown
/// value shape nor a zero-datapoint success — it is recorded as a
/// skipped row (`emptySelection`, Issue #190 review) so a caller
/// reconciling rows in vs. rows out can see it, rather than the row
/// silently disappearing.
_RowResult _mapRow(
  LocalDate date,
  String type,
  Object? value,
  Map<String, Object?> row,
) {
  if (type == 'period') {
    return _RowResult.ok([_mapPeriod(date, value, row)]);
  }
  if (kClueNumericTypes.contains(type)) {
    return _RowResult.ok([_mapNumeric(date, type, value, row)]);
  }
  final spec = kClueTypeMap[type];
  if (spec == null) {
    return _RowResult.ok(
      [_unknown(date, type, row, ClueUnknownReason.unknownType)],
    );
  }
  final options = _normalizeOptionEntries(value);
  if (options == null) {
    return _RowResult.ok(
      [_unknown(date, type, row, ClueUnknownReason.unknownValueShape)],
    );
  }
  if (options.isEmpty) {
    return _RowResult.skip('emptySelection');
  }
  return _RowResult.ok(
    [for (final option in options) _mapOption(date, type, option, spec)],
  );
}

ClueDatapoint _mapPeriod(LocalDate date, Object? value, Map<String, Object?> row) {
  final option = _singleOption(value);
  final level = option == null ? null : kCluePeriodLevels[option];
  if (level == null) {
    return _unknown(date, 'period', row, ClueUnknownReason.unknownValueShape);
  }
  return CluePeriodDatapoint(date, level);
}

ClueDatapoint _mapOption(
  LocalDate date,
  String type,
  String rawOption,
  ClueTypeSpec spec,
) {
  final override = spec.options[rawOption];
  return ClueObservationDatapoint(
    date,
    type,
    category: spec.category,
    code: override?.code ?? rawOption,
    isNegativeAssertion: override?.negative ?? false,
  );
}

ClueDatapoint _unknown(
  LocalDate date,
  String type,
  Map<String, Object?> row,
  ClueUnknownReason reason,
) =>
    ClueUnknownDatapoint(
      date,
      type,
      reason: reason,
      raw: Map<String, Object?>.from(row),
    );

/// `value` for a single-select category is `{"option": "..."}`; multi-select
/// is a list of such maps. Both normalise to a flat list of raw option
/// strings; anything else (a missing `option` key, a bare scalar, a
/// non-string `option`, ...) is an unrecognised value shape and returns
/// null.
List<String>? _normalizeOptionEntries(Object? value) {
  if (value is Map) {
    final option = value['option'];
    return option is String ? [option] : null;
  }
  if (value is List) {
    final options = <String>[];
    for (final entry in value) {
      if (entry is! Map || entry['option'] is! String) return null;
      options.add(entry['option'] as String);
    }
    return options;
  }
  return null;
}

/// `period`'s value is always single-select; a well-formed row normalises
/// to exactly one option.
String? _singleOption(Object? value) {
  final options = _normalizeOptionEntries(value);
  return options != null && options.length == 1 ? options.first : null;
}

ClueDatapoint _mapNumeric(
  LocalDate date,
  String type,
  Object? value,
  Map<String, Object?> row,
) {
  if (value is! Map) {
    return _unknown(date, type, row, ClueUnknownReason.unknownValueShape);
  }
  for (final key in kClueBbtValueKeys) {
    final parsed = _tryNum(value[key]);
    if (parsed != null) {
      return ClueNumericDatapoint(
        date,
        type,
        category: 'bbt',
        valueNum: parsed.toDouble(),
        unit: key,
        excluded: value['excluded'] == true,
      );
    }
  }
  return _unknown(date, type, row, ClueUnknownReason.unknownValueShape);
}

/// Defensive numeric parsing (Issue #190): accepts a JSON number as-is, or
/// a numeric string, tolerating either encoding an export might use.
num? _tryNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}
