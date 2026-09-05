/// U1 (R13): seeded-profile export yields CSV rows matching the on-screen
/// entries (codes, notes, timezones), JSON carrying the entry array plus
/// profile meta in the codec shape, and a one-page PDF summary with the
/// disclaimer. Tombstones are excluded from every format.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' as db;
import 'package:lunarlog/data/db/tables.dart' as tables;
import 'package:lunarlog/data/export/profile_export.dart';
import 'package:lunarlog/data/sync/row_codec.dart';
import 'package:lunarlog/domain/models/day_entry.dart';
import 'package:lunarlog/domain/models/flow_level.dart' as domain;
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';

Profile _profile() => Profile(
      id: '01J0000000000000000000000A',
      displayName: 'Alex',
      isMinor: false,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

DayEntry _entry({
  required String id,
  required String date,
  required String tz,
  required domain.FlowLevel flow,
  List<String> tags = const [],
  String? note,
  DateTime? deletedAt,
}) =>
    DayEntry(
      id: id,
      profileId: '01J0000000000000000000000A',
      localDate: LocalDate.fromIso(date),
      tz: tz,
      flow: flow,
      tags: tags,
      note: note,
      updatedAt: DateTime.utc(2026, 9, 1, 12),
      deletedAt: deletedAt,
    );

List<DayEntry> _seeded() => [
      _entry(
        id: '01J0000000000000000000000B',
        date: '2026-07-01',
        tz: 'America/New_York',
        flow: domain.FlowLevel.medium,
        tags: const ['cramps'],
        note: 'first note',
      ),
      _entry(
        id: '01J0000000000000000000000C',
        date: '2026-07-29',
        tz: 'Europe/Berlin',
        flow: domain.FlowLevel.light,
        tags: const ['headache', 'cramps'],
      ),
      _entry(
        id: '01J0000000000000000000000D',
        date: '2026-08-26',
        tz: 'America/New_York',
        flow: domain.FlowLevel.heavy,
        note: 'late note',
      ),
      _entry(
        id: '01J0000000000000000000000E',
        date: '2026-06-01',
        tz: 'America/New_York',
        flow: domain.FlowLevel.spotting,
        deletedAt: DateTime.utc(2026, 9, 1),
      ),
    ];

void main() {
  group('CSV export', () {
    test('rows match the on-screen entries; tombstones excluded', () {
      final csv = buildExportCsv(_profile(), _seeded());
      final lines = const LineSplitter().convert(csv);
      expect(lines.first, 'date,timezone,flow,tags,note');
      expect(lines.length, 4,
          reason: 'header plus the three live entries, not the tombstone');
      expect(lines[1], contains('2026-07-01'));
      expect(lines[1], contains('America/New_York'));
      expect(lines[1], contains('medium'));
      expect(lines[1], contains('cramps'));
      expect(lines[1], contains('first note'));
      expect(lines[2], contains('Europe/Berlin'));
      expect(lines[2], contains('headache;cramps'));
      expect(lines[3], contains('late note'));
      expect(csv, isNot(contains('2026-06-01')));
    });

    test('commas and quotes in notes are escaped', () {
      final csv = buildExportCsv(
        _profile(),
        [
          _entry(
            id: '01J0000000000000000000000B',
            date: '2026-07-01',
            tz: 'UTC',
            flow: domain.FlowLevel.none,
            note: 'a, "quoted" note',
          ),
        ],
      );
      expect(csv, contains('"a, ""quoted"" note"'));
    });
  });

  group('JSON export', () {
    test('carries the entry array plus profile meta', () {
      final json = buildExportJson(_profile(), _seeded());
      final profile = json['profile'] as Map<String, Object?>;
      expect(profile['display_name'], 'Alex');
      final entries = json['entries'] as List<Object?>;
      expect(entries.length, 3,
          reason: 'live entries only; the tombstone is excluded');
      final first = entries.first as Map<String, Object?>;
      expect(first['local_date'], '2026-07-01');
      expect(first['tz'], 'America/New_York');
      expect(first['note'], 'first note');
    });

    test('entry objects reuse the sync codec shape', () {
      final json = buildExportJson(_profile(), _seeded());
      final entries = json['entries'] as List<Object?>;
      final codecKeys = encodeDayEntry(
        db.DayEntry(
          id: '01J0000000000000000000000B',
          profileId: '01J0000000000000000000000A',
          localDate: '2026-07-01',
          tz: 'America/New_York',
          flow: tables.FlowLevel.medium,
          tags: const ['cramps'],
          note: 'first note',
          updatedAt: DateTime.utc(2026, 9, 1, 12),
          deletedAt: null,
          dirty: true,
          localRev: 1,
        ),
      ).keys.toSet();
      for (final entry in entries) {
        final keys = (entry as Map<String, Object?>).keys.toSet();
        expect(keys, codecKeys);
      }
    });
  });

  group('PDF summary', () {
    test('summary counts the interval average and last starts', () {
      final summary = buildExportSummary(_profile(), _seeded());
      expect(summary.entryCount, 3);
      expect(summary.averageIntervalDays, 28);
      expect(summary.lastStartDates,
          ['2026-07-01', '2026-07-29', '2026-08-26']);
      expect(summary.disclaimer, isNotEmpty);
    });

    test('renders one page carrying counts, average, starts, disclaimer',
        () async {
      final Uint8List bytes =
          await buildExportPdf(_profile(), _seeded(), compress: false);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.startsWith('%PDF-'), isTrue);
      expect(_pageCount(text), 1, reason: 'the summary is one page');
      // Page text is emitted as TJ runs split at word boundaries, so assert
      // on single tokens rather than whole sentences.
      expect(text, contains('Tracked'));
      expect(text, contains('Average'));
      expect(text, contains('2026-08-26'));
      expect(text, contains('medical'));
      expect(exportDisclaimer, contains('medical'));
    });

    test('empty profile still renders one page with zero counts', () async {
      final Uint8List bytes =
          await buildExportPdf(_profile(), const [], compress: false);
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(_pageCount(text), 1);
      final summary = buildExportSummary(_profile(), const []);
      expect(summary.entryCount, 0);
      expect(summary.averageIntervalDays, isNull);
    });
  });
}

/// Counts page objects (`/Type /Page`, not the `/Type /Pages` parent) in a
/// raw PDF rendering.
int _pageCount(String rawPdf) =>
    RegExp(r'/Type\s*/Page[^s]').allMatches(rawPdf).length;
