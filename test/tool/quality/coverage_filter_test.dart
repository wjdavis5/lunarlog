import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/quality/coverage_filter.dart';
import '../../../tool/quality/exclusions.dart';

const _fixtureLcov = '''
SF:lib/data/db/db.g.dart
DA:1,4
DA:2,0
LF:2
LH:1
end_of_record
SF:lib/domain/models/profile.dart
DA:1,3
DA:2,0
DA:3,1
LF:3
LH:2
end_of_record
''';

void main() {
  group('exclusion patterns', () {
    test('match every KTD4 entry against its real repo path', () {
      const realExcludedPaths = [
        'lib/data/db/db.g.dart',
        'lib/data/auth/google_sign_in_client.dart',
        'lib/data/auth/auth_gateway.dart',
        'lib/data/db/key_store.dart',
        'lib/data/notifications/notification_scheduler.dart',
      ];
      for (final path in realExcludedPaths) {
        expect(isExcluded(path), isTrue, reason: '$path should be excluded');
      }
    });

    test('do not over-match near-miss paths', () {
      const nearMisses = [
        'lib/data/db/tables.dart', // not db.g.dart
        'lib/data/db/key_store_test.dart', // test file, not the adapter
        'lib/data/auth/auth_gateway_test.dart',
        'lib/data/auth/supabase_auth_service.dart', // different auth file
        'lib/data/notifications/scheduling.dart', // not notification_scheduler.dart
      ];
      for (final path in nearMisses) {
        expect(
          isExcluded(path),
          isFalse,
          reason: '$path should NOT be excluded',
        );
      }
    });

    test('matches on Windows-native backslash SF paths too', () {
      expect(isExcluded(r'lib\data\db\db.g.dart'), isTrue);
      expect(isExcluded(r'lib\data\db\tables.dart'), isFalse);
    });
  });

  group('parseLcov', () {
    test('parses SF/DA/LF/LH into per-file records', () {
      final files = parseLcov(_fixtureLcov);
      expect(files.keys, unorderedEquals(<String>[
        'lib/data/db/db.g.dart',
        'lib/domain/models/profile.dart',
      ]));
      final profile = files['lib/domain/models/profile.dart']!;
      expect(profile.lf, 3);
      expect(profile.lh, 2);
      expect(profile.daHits, {1: 3, 2: 0, 3: 1});
    });

    test('empty content yields no files, no crash', () {
      expect(parseLcov(''), isEmpty);
    });
  });

  group('applyExclusions', () {
    test('drops excluded files, keeps everything else unchanged', () {
      final raw = parseLcov(_fixtureLcov);
      final filtered = applyExclusions(raw);
      expect(filtered.keys, ['lib/domain/models/profile.dart']);
      expect(filtered['lib/domain/models/profile.dart'], raw['lib/domain/models/profile.dart']);
    });

    test('no matching entries leaves the structure unchanged', () {
      const noMatchLcov = '''
SF:lib/domain/models/profile.dart
DA:1,1
LF:1
LH:1
end_of_record
''';
      final raw = parseLcov(noMatchLcov);
      expect(applyExclusions(raw), raw);
    });
  });

  group('filteredCoverageFromFile', () {
    test('reads a real lcov file from disk end-to-end via a fixture', () {
      // Not asserted against this repo's live coverage/lcov.info: that file
      // is only written *after* `flutter test --coverage` finishes, so
      // reading it *during* a run of that same command (as this test file
      // does when invoked by tool/quality_gate.dart or CI) sees a stale or
      // absent file — a self-referential race, not a real assertion. The
      // baseline itself is measured and verified separately by running
      // `dart run tool/quality_gate.dart` directly and reading its printed
      // report (see the plan's KTD1/U1 and the PR description).
      final dir = Directory.systemTemp.createTempSync('coverage_filter_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final lcovFile = File('${dir.path}${Platform.pathSeparator}lcov.info')
        ..writeAsStringSync(_fixtureLcov);
      final filtered = filteredCoverageFromFile(lcovFile);
      expect(filtered.keys, ['lib/domain/models/profile.dart']);
      expect(filtered['lib/domain/models/profile.dart']!.percent,
          closeTo(66.7, 0.1));
    });
  });
}
