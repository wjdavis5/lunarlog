/// Unit tests for PlatformCsvExportWriter (Issue #469). Uses a fake
/// [CsvShareCollaborator] throughout — never touches `path_provider`/`share_plus`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/export/csv_export_writer.dart';

void main() {
  group('PlatformCsvExportWriter.exportAndShare', () {
    test('passes formatted cycle and daily log files to the collaborator', () async {
      List<({String fileName, String content})>? capturedFiles;

      final writer = PlatformCsvExportWriter(
        shareCollaborator: ({required files}) async {
          capturedFiles = files;
        },
      );

      final exportedAt = DateTime.utc(2026, 3, 10, 12, 0);
      const cycles = 'cycle_number,start_date\r\n1,2026-03-01\r\n';
      const dailyLog = 'date,flow\r\n2026-03-01,heavy\r\n';

      await writer.exportAndShare(
        cyclesCsv: cycles,
        dailyLogCsv: dailyLog,
        exportedAt: exportedAt,
      );

      expect(capturedFiles, isNotNull);
      expect(capturedFiles!.length, 2);

      expect(capturedFiles![0].fileName, 'lunarlog-cycles-2026-03-10.csv');
      expect(capturedFiles![0].content, cycles);

      expect(capturedFiles![1].fileName, 'lunarlog-daily-log-2026-03-10.csv');
      expect(capturedFiles![1].content, dailyLog);
    });

    test('propagates collaborator error rather than swallowing it', () {
      final writer = PlatformCsvExportWriter(
        shareCollaborator: ({required files}) async {
          throw StateError('share sheet failed');
        },
      );

      expect(
        () => writer.exportAndShare(
          cyclesCsv: '',
          dailyLogCsv: '',
          exportedAt: DateTime.utc(2026, 3, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('constructs default instance without invoking platform collaborator', () {
      const writer = PlatformCsvExportWriter();
      expect(writer, isA<PlatformCsvExportWriter>());
    });
  });
}
