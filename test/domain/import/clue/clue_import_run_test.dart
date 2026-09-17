/// Unit tests for `lib/domain/import/clue/clue_import_run.dart` (Issue
/// #199): checksum stability, checksum-derived `source_id` shape and
/// bounds, the planned summary (counts, cycle reconstruction, unmapped
/// split, notes heuristic, skipped rows), the not-carried-over lines, and
/// the unmapped-row display text (including its never-throw degradation).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/import/clue/clue_export_parser.dart';
import 'package:lunarlog/domain/import/clue/clue_import_run.dart';
import 'package:lunarlog/domain/limits.dart';

List<int> _fixtureBytes(String name) =>
    File('test/fixtures/clue/$name').readAsBytesSync();

void main() {
  group('clueFileChecksum', () {
    test('is stable and hex-shaped', () {
      final bytes = _fixtureBytes('unknown_type_and_option.json');
      final first = clueFileChecksum(bytes);
      expect(first, clueFileChecksum(bytes));
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(first), isTrue);
    });

    test('differs between files', () {
      expect(
        clueFileChecksum(_fixtureBytes('unknown_type_and_option.json')),
        isNot(
          clueFileChecksum(_fixtureBytes('mapping_table.json')),
        ),
      );
    });
  });

  group('source ids', () {
    test('day id embeds the checksum tag and date', () {
      const checksum =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
      final id =
          clueDaySourceId(fileChecksum: checksum, dateIso: '2026-04-01');
      expect(id, 'clue:abcdef12:2026-04-01');
      expect(id.length <= kMaxDayEntrySourceIdLength, isTrue);
    });

    test('observation ids disambiguate same-type ordinals', () {
      const checksum =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
      final first = clueObservationSourceId(
        fileChecksum: checksum,
        dateIso: '2026-04-01',
        type: 'pain',
        ordinal: 0,
      );
      final second = clueObservationSourceId(
        fileChecksum: checksum,
        dateIso: '2026-04-01',
        type: 'pain',
        ordinal: 1,
      );
      expect(first, isNot(second));
      expect(second.length <= kMaxObservationSourceIdLength, isTrue);
    });

    test('absurdly long types still fit the column bound', () {
      const checksum =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';
      final id = clueObservationSourceId(
        fileChecksum: checksum,
        dateIso: '2026-04-01',
        type: 'x' * 500,
        ordinal: 0,
      );
      expect(id.length <= kMaxObservationSourceIdLength, isTrue);
    });
  });

  group('summarizeClueImport', () {
    test('fixture with unmapped type and unmapped option', () {
      final result =
          parseClueDatapoints(_fixtureBytes('unknown_type_and_option.json'));
      final summary = summarizeClueImport(result);
      expect(summary.datapointCount, result.datapoints.length);
      expect(summary.unmappedTypeCount, 1);
      expect(summary.unmappedTypes, ['hot_flashes']);
      // bbt-with-bad-keys, feelings-with-scalar, period/extreme,
      // bbt-with-scalar: four unknown value shapes.
      expect(summary.unmappedValueCount, 4);
      expect(summary.cycleBoundariesReconstructed, 0);
      expect(summary.notesDetected, isFalse);
      expect(summary.daysWritten, 0);
      expect(summary.isNoop, isTrue);
    });

    test('multi-cycle bleeding reconstructs boundaries', () {
      final result =
          parseClueDatapoints(_fixtureBytes('multi_cycle_bleeding.json'));
      final summary = summarizeClueImport(result);
      expect(summary.cycleBoundariesReconstructed, greaterThan(0));
      expect(summary.unmappedTotal, 0);
    });

    test('malformed rows surface as skipped, never thrown', () {
      final result =
          parseClueDatapoints(_fixtureBytes('malformed_rows.json'));
      final summary = summarizeClueImport(result);
      expect(summary.skippedRows, result.skipped.length);
      expect(summary.skippedRows, greaterThan(0));
    });

    test('free-text values flag notesDetected', () {
      final bytes = utf8.encode(jsonEncode([
        {
          'date': '2026-04-01',
          'type': 'mystery_journal',
          'value': {'text': 'a fairly long free-text note about today'}
        }
      ]));
      final summary = summarizeClueImport(parseClueDatapoints(bytes));
      expect(summary.unmappedTypeCount, 1);
      expect(summary.notesDetected, isTrue);
    });

    test('short option strings do not flag notesDetected', () {
      final result =
          parseClueDatapoints(_fixtureBytes('unknown_type_and_option.json'));
      expect(summarizeClueImport(result).notesDetected, isFalse);
    });

    test('summary lines name every required section', () {
      final result =
          parseClueDatapoints(_fixtureBytes('unknown_type_and_option.json'));
      final lines = summarizeClueImport(result).summaryLines.join('\n');
      expect(lines, contains('Cycle boundaries reconstructed'));
      expect(lines, contains('Excluded-cycle flags are not carried over.'));
      expect(
          lines, contains('Pregnancy and birth-control state are not carried over.'));
      expect(lines, contains('No notes were detected.'));
      expect(lines, contains('Unrecognised type kept: hot_flashes.'));
    });

    test('clean file says nothing needed the fallback', () {
      final result =
          parseClueDatapoints(_fixtureBytes('mapping_table.json'));
      final summary = summarizeClueImport(result);
      expect(summary.unmappedTotal, 0);
      expect(
        summary.summaryLines.join('\n'),
        contains('nothing needed the unrecognised-data fallback'),
      );
    });
  });

  group('describeUnmappedRaw', () {
    test('renders type and option', () {
      expect(
        describeUnmappedRaw({
          'date': '2026-04-01',
          'type': 'hot_flashes',
          'value': {'option': 'moderate'},
        }),
        'hot_flashes: moderate',
      );
    });

    test('renders multi-select lists joined', () {
      expect(
        describeUnmappedRaw({
          'date': '2026-04-01',
          'type': 'pain',
          'value': [
            {'option': 'headache'},
            {'option': 'migraine'}
          ],
        }),
        'pain: headache, migraine',
      );
    });

    test('degrades to truncated JSON, never throws', () {
      expect(
        describeUnmappedRaw({
          'date': '2026-04-01',
          'type': 'bbt',
          'value': {'unrecognised_key': 36.5},
        }),
        'bbt: {"unrecognised_key":36.5}',
      );
      expect(describeUnmappedRaw({}), 'unrecognised data');
      expect(
        describeUnmappedRaw({'type': '', 'value': null}),
        'unrecognised data',
      );
      final long = describeUnmappedRaw({
        'type': 'journal',
        'value': {'text': 'x' * 500},
      });
      expect(long.length <= kMaxUnmappedDisplayLength + 1, isTrue);
    });
  });

  group('unmappedCategoryFor', () {
    test('known types keep their mapped category', () {
      expect(unmappedCategoryFor('pain'), 'pain');
      expect(unmappedCategoryFor('bbt'), 'bbt');
    });

    test('unknown types land on the unmapped category', () {
      expect(unmappedCategoryFor('hot_flashes'), kClueUnmappedCategory);
      expect(unmappedCategoryFor('period'), kClueUnmappedCategory);
    });
  });

  group('clueRawJson', () {
    test('round-trips small payloads and reduces oversized ones', () {
      final small = {'date': '2026-04-01', 'type': 'x', 'value': 'y'};
      expect(jsonDecode(clueRawJson(small)!) as Map, small);
      final huge = {
        'date': '2026-04-01',
        'type': 'x',
        'value': {'blob': 'z' * (kMaxObservationRawLength + 1)},
      };
      final reduced = clueRawJson(huge)!;
      expect(utf8.encode(reduced).length <= kMaxObservationRawLength, isTrue);
      expect((jsonDecode(reduced) as Map)['type'], 'x');
    });
  });
}
