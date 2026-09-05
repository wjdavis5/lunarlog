/// Selected-profile data export (U1; R13): CSV rows, a one-page PDF summary,
/// and JSON through the system share sheet.
///
/// The builders below are pure Dart over the domain models so they run under
/// `flutter test` and stay out of the coverage exclusions. The share-sheet
/// delivery and temp-file ownership live in `export_service.dart`; the thin
/// `share_plus` adapter in `share_client.dart`.
///
/// Vocabulary is date-based only; errors and logs carry kinds, never content
/// (R18). Tombstoned rows are excluded from every format: export covers live
/// entries for the selected profile.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/day_entry.dart' as domain;
import '../../domain/models/profile.dart' as domain;
import '../sync/row_codec.dart';

/// Disclaimer printed on the PDF summary and carried in the JSON envelope.
/// Generic wording; no medical claims.
const String exportDisclaimer =
    'Summary only - not medical advice. Data as recorded on this device.';

/// Live entries for [entries], oldest first. Tombstones are excluded.
List<domain.DayEntry> liveExportEntries(List<domain.DayEntry> entries) {
  final live = entries.where((e) => e.deletedAt == null).toList();
  live.sort((a, b) => a.localDate.compareTo(b.localDate));
  return live;
}

/// One entry as a JSON object reusing the sync codec's key shape
/// ([encodeDayEntry]): `id`, `profile_id`, `local_date`, `tz`, `flow`,
/// `tags`, `note`, `updated_at`, `deleted_at`.
JsonRow exportEntryJson(domain.DayEntry entry) => {
      'id': entry.id,
      'profile_id': entry.profileId,
      'local_date': entry.localDate.iso,
      'tz': entry.tz,
      'flow': entry.flow.name,
      'tags': List<String>.of(entry.tags),
      'note': entry.note,
      'updated_at': encodeTimestamp(entry.updatedAt),
      'deleted_at':
          entry.deletedAt == null ? null : encodeTimestamp(entry.deletedAt!),
    };

/// The JSON envelope: the entry array plus profile meta, for the selected
/// profile. Tombstones excluded.
JsonRow buildExportJson(
    domain.Profile profile, List<domain.DayEntry> entries) {
  String? stamp(DateTime? value) =>
      value == null ? null : encodeTimestamp(value);
  return {
    'profile': {
      'id': profile.id,
      'display_name': profile.displayName,
      'is_minor': profile.isMinor,
      'sort_order': profile.sortOrder,
      'archived_at': stamp(profile.archivedAt),
      'created_at': encodeTimestamp(profile.createdAt),
      'updated_at': encodeTimestamp(profile.updatedAt),
    },
    'entries': [
      for (final entry in liveExportEntries(entries)) exportEntryJson(entry),
    ],
    'exported_at': encodeTimestamp(DateTime.now().toUtc()),
    'disclaimer': exportDisclaimer,
  };
}

/// CSV rows matching the on-screen entries: date, timezone, flow name, tags,
/// note. Tombstones excluded; fields with commas, quotes, or newlines are
/// quoted per RFC 4180.
String buildExportCsv(domain.Profile profile, List<domain.DayEntry> entries) {
  // The CSV carries one row per tracked date; the profile envelope lives in
  // the JSON. The parameter stays so every format shares one call shape.
  assert(profile.id.isNotEmpty);
  final buffer = StringBuffer('date,timezone,flow,tags,note');
  for (final entry in liveExportEntries(entries)) {
    buffer
      ..write('\n')
      ..write(_csvField(entry.localDate.iso))
      ..write(',')
      ..write(_csvField(entry.tz))
      ..write(',')
      ..write(_csvField(entry.flow.name))
      ..write(',')
      ..write(_csvField(entry.tags.join(';')))
      ..write(',')
      ..write(_csvField(entry.note ?? ''));
  }
  return buffer.toString();
}

String _csvField(String value) {
  if (value.contains(RegExp(r'[",\n\r]')) || value.contains(';')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// The one-page PDF summary's data: entry count, the mean gap in days
/// between consecutive start dates (null below two entries), and the last
/// (at most six) start dates, oldest first.
@immutable
class ExportSummary {
  const ExportSummary({
    required this.profileName,
    required this.entryCount,
    required this.averageIntervalDays,
    required this.lastStartDates,
    required this.disclaimer,
  });

  final String profileName;
  final int entryCount;
  final int? averageIntervalDays;
  final List<String> lastStartDates;
  final String disclaimer;
}

ExportSummary buildExportSummary(
    domain.Profile profile, List<domain.DayEntry> entries) {
  final live = liveExportEntries(entries);
  final dates = live.map((e) => e.localDate).toList();
  int? average;
  if (dates.length >= 2) {
    var total = 0;
    for (var i = 1; i < dates.length; i++) {
      total += dates[i].difference(dates[i - 1]);
    }
    average = (total / (dates.length - 1)).round();
  }
  final last = dates.length <= 6
      ? dates
      : dates.sublist(dates.length - 6);
  return ExportSummary(
    profileName: profile.displayName,
    entryCount: live.length,
    averageIntervalDays: average,
    lastStartDates: [for (final d in last) d.iso],
    disclaimer: exportDisclaimer,
  );
}

/// Renders the summary onto exactly one PDF page. [compress] is a test seam:
/// tests render uncompressed and assert the page count and copy from the raw
/// bytes; production shares the compressed rendering.
Future<Uint8List> buildExportPdf(
  domain.Profile profile,
  List<domain.DayEntry> entries, {
  bool compress = true,
}) async {
  final summary = buildExportSummary(profile, entries);
  final doc = pw.Document(compress: compress);
  doc.addPage(
    pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('LunarLog summary',
              style: pw.TextStyle(
                  fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Profile: ${summary.profileName}'),
          pw.Text('Tracked dates: ${summary.entryCount}'),
          pw.Text('Average interval (days): '
              '${summary.averageIntervalDays?.toString() ?? 'n/a'}'),
          pw.SizedBox(height: 8),
          pw.Text('Recent start dates:',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          if (summary.lastStartDates.isEmpty)
            pw.Text('none yet')
          else
            for (final date in summary.lastStartDates) pw.Text(date),
          pw.Spacer(),
          pw.Text(summary.disclaimer,
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
  return doc.save();
}
