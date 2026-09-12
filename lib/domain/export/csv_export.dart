/// Pure RFC 4180 CSV serialization helpers and builders for cycles and daily logs (Issue #469).
/// Pure Dart with zero Flutter or database imports (R14/R16).
library;

import '../episodes/episodes.dart';
import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/local_date.dart';
import '../models/observation.dart';
import '../prediction/prediction.dart' show kMinCycleDays, kMaxCycleDays;

/// Field-content prefixes (Issue #563; OWASP CSV/formula injection) that a
/// spreadsheet application (Excel, Google Sheets, LibreOffice) treats as
/// the start of a formula rather than literal text — `=`, `+`, `-`, `@`, a
/// tab, and a bare CR. All six are otherwise unremarkable, unquoted RFC
/// 4180 field content, which is exactly why RFC 4180 escaping alone does
/// not defend against them.
const String _csvFormulaTriggerChars = '=+-@\t\r';

/// True when [field] would be interpreted as a formula by a spreadsheet
/// application reading it verbatim from a CSV cell.
bool _startsWithCsvFormulaTrigger(String field) =>
    field.isNotEmpty && _csvFormulaTriggerChars.contains(field[0]);

/// Escapes a single field according to RFC 4180 §2.5-2.7, plus the
/// spreadsheet formula-injection guard issue #563 asks for: a field
/// starting with one of [_csvFormulaTriggerChars] is prefixed with `'` —
/// the "force text" marker Excel/Sheets/LibreOffice strip on display — and
/// force-quoted, whether or not RFC 4180 alone would have quoted it.
///
/// If the field contains a comma, double-quote, CR (`\r`), or LF (`\n`), it must
/// be enclosed in double-quotes, and any embedded double-quotes must be escaped as `""`.
///
/// Applied unconditionally, to every field this file exports — not only
/// the obviously free-text ones (a day entry's `note`, its `tags`,
/// an observation's `code`). In a multi-guardian household the note's
/// author and the person opening the export are routinely different
/// people (issue #563's own example: a caregiver's `=HYPERLINK(...)` note,
/// opened by the owner or a clinician it is forwarded to), so nothing
/// reaching this function is trusted.
///
/// This is safe for lunarlog's numeric columns specifically, which is why
/// the guard lives here rather than only on the free-text columns: `bbt`
/// and `weight` are physical measurements that are always positive, and
/// every other numeric field this file emits (`cycle_number`,
/// `*_length_days`) is a non-negative count or an ISO date
/// (`yyyy-MM-dd`, which starts with a digit) — none of them can
/// legitimately start with `-` or `+`. A column that genuinely can be
/// negative would need to bypass this guard rather than rely on it.
String escapeCsvField(String field) {
  final triggered = _startsWithCsvFormulaTrigger(field);
  final guarded = triggered ? "'$field" : field;
  final needsQuoting = triggered ||
      guarded.contains(',') ||
      guarded.contains('"') ||
      guarded.contains('\n') ||
      guarded.contains('\r');
  if (!needsQuoting) return guarded;
  return '"${guarded.replaceAll('"', '""')}"';
}

/// Formats a single CSV record row using RFC 4180 escaping.
String formatCsvRow(List<String> fields) =>
    fields.map(escapeCsvField).join(',');

/// Formats a table of rows into an RFC 4180 compliant CSV string using CRLF (`\r\n`) line endings.
String formatCsvTable(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final buffer = StringBuffer();
  for (final row in rows) {
    buffer.write(formatCsvRow(row));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

/// Generates `cycles.csv` matching Issue #469 spec:
/// `cycle_number,start_date,end_date,cycle_length_days,period_length_days,is_irregular,omitted_from_averages`
///
/// Derives bleeding episodes from [entries] using [deriveEpisodes]. Episodes are ordered
/// chronologically ascending. For each completed cycle (from episode start to the next
/// episode's start):
/// - `end_date` is the day before the next episode's start.
/// - `cycle_length_days` is the whole-day span from start to next start.
/// - `is_irregular` is true if cycle length is outside the [kMinCycleDays]..[kMaxCycleDays] range.
/// - The newest (open) cycle has no next episode, so `end_date` and `cycle_length_days` are empty,
///   and `is_irregular` is false.
String buildCyclesCsv({
  required Iterable<DayEntry> entries,
  Set<LocalDate> omittedCycleStarts = const {},
}) {
  final header = [
    'cycle_number',
    'start_date',
    'end_date',
    'cycle_length_days',
    'period_length_days',
    'is_irregular',
    'omitted_from_averages',
  ];

  final bleedDates = bleedDatesOf(entries);
  final episodes = deriveEpisodes(bleedDates);
  final rows = <List<String>>[header];

  for (var i = 0; i < episodes.length; i++) {
    final episode = episodes[i];
    final cycleNumber = (i + 1).toString();
    final startDate = episode.start.iso;
    final periodLengthDays = episode.lengthDays.toString();
    final isLast = i == episodes.length - 1;
    final omitted = omittedCycleStarts.contains(episode.start).toString();

    if (isLast) {
      rows.add([
        cycleNumber,
        startDate,
        '',
        '',
        periodLengthDays,
        'false',
        omitted,
      ]);
    } else {
      final nextStart = episodes[i + 1].start;
      final endDate = nextStart.addDays(-1).iso;
      final cycleLength = nextStart.difference(episode.start);
      final isIrregular =
          (cycleLength < kMinCycleDays || cycleLength > kMaxCycleDays).toString();

      rows.add([
        cycleNumber,
        startDate,
        endDate,
        cycleLength.toString(),
        periodLengthDays,
        isIrregular,
        omitted,
      ]);
    }
  }

  return formatCsvTable(rows);
}

Map<LocalDate, DayEntry> _mapLiveEntries(Iterable<DayEntry> entries) {
  final result = <LocalDate, DayEntry>{};
  for (final entry in entries) {
    if (entry.deletedAt == null) {
      result[entry.localDate] = entry;
    }
  }
  return result;
}

Map<LocalDate, List<Observation>> _mapLiveObservations(
  Iterable<Observation> observations,
) {
  final result = <LocalDate, List<Observation>>{};
  for (final obs in observations) {
    if (obs.deletedAt == null) {
      result.putIfAbsent(obs.localDate, () => []).add(obs);
    }
  }
  return result;
}

bool _hasSpotting(DayEntry? entry, List<Observation> observations) {
  if (entry != null && entry.flow == FlowLevel.spotting) return true;
  return observations.any((o) => o.category == 'spotting');
}

String _formatPainIntensity(List<Observation> observations) {
  final painRows = [
    for (final o in observations)
      if (o.category == 'pain' && o.intensity != null) o,
  ];
  if (painRows.isEmpty) return '';
  return painRows
      .map((o) => o.code != null ? '${o.code}:${o.intensity}' : '${o.intensity}')
      .join(';');
}

String _formatCategoryNum(List<Observation> observations, String category) {
  for (final o in observations) {
    if (o.category == category && o.valueNum != null) {
      return o.valueNum.toString();
    }
  }
  return '';
}

List<String> _buildDailyLogRow(
  LocalDate date,
  DayEntry? entry,
  List<Observation> observations,
) {
  final flowStr = entry != null ? entry.flow.toDb() : 'none';
  final pmsStr = (entry != null && entry.pms) ? 'true' : 'false';
  final tagsStr = (entry != null && entry.tags.isNotEmpty) ? entry.tags.join(';') : '';
  final notesStr = entry?.note ?? '';
  final spottingStr = _hasSpotting(entry, observations) ? 'true' : 'false';
  final painStr = _formatPainIntensity(observations);
  final bbtStr = _formatCategoryNum(observations, 'bbt');
  final weightStr = _formatCategoryNum(observations, 'weight');

  return [
    date.iso,
    flowStr,
    pmsStr,
    tagsStr,
    painStr,
    spottingStr,
    notesStr,
    bbtStr,
    weightStr,
  ];
}

/// Generates `daily_log.csv` matching Issue #469 spec:
/// `date,flow,pms,tags,pain_intensity,spotting,notes,bbt,weight`
///
/// Combines [entries] and [observations], grouping by civil date and ordering
/// chronologically ascending. Excludes internal database/sync metadata.
String buildDailyLogCsv({
  required Iterable<DayEntry> entries,
  Iterable<Observation> observations = const [],
}) {
  final header = [
    'date',
    'flow',
    'pms',
    'tags',
    'pain_intensity',
    'spotting',
    'notes',
    'bbt',
    'weight',
  ];

  final entriesByDate = _mapLiveEntries(entries);
  final observationsByDate = _mapLiveObservations(observations);
  final allDates = {...entriesByDate.keys, ...observationsByDate.keys}.toList()
    ..sort();

  final rows = <List<String>>[
    header,
    for (final date in allDates)
      _buildDailyLogRow(
        date,
        entriesByDate[date],
        observationsByDate[date] ?? const [],
      ),
  ];

  return formatCsvTable(rows);
}

/// Filename helper for `lunarlog-cycles-YYYY-MM-DD.csv` in UTC.
String csvCyclesFileName(DateTime exportedAt) {
  final u = exportedAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'lunarlog-cycles-${u.year}-${two(u.month)}-${two(u.day)}.csv';
}

/// Filename helper for `lunarlog-daily-log-YYYY-MM-DD.csv` in UTC.
String csvDailyLogFileName(DateTime exportedAt) {
  final u = exportedAt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'lunarlog-daily-log-${u.year}-${two(u.month)}-${two(u.day)}.csv';
}
