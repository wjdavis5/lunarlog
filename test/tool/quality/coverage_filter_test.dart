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

  group('filteredCoverageFromFile against this repo\'s real lcov.info', () {
    test('parses cleanly end-to-end and matches the measured baseline', () {
      final lcovFile = File('coverage/lcov.info');
      if (!lcovFile.existsSync()) {
        markTestSkipped(
          'coverage/lcov.info not present — run `flutter test --coverage` first',
        );
        return;
      }
      final filtered = filteredCoverageFromFile(lcovFile);
      expect(filtered, isNotEmpty);
      // None of the five reviewed exclusions should survive filtering.
      for (final path in filtered.keys) {
        expect(isExcluded(path), isFalse);
      }
      var totalLf = 0;
      var totalLh = 0;
      for (final f in filtered.values) {
        totalLf += f.lf;
        totalLh += f.lh;
      }
      // Sanity band around the ~91.8% baseline measured during planning —
      // this will move as U5 adds tests, so the assertion is a wide band,
      // not an exact pin.
      final percent = totalLh / totalLf * 100;
      expect(percent, greaterThan(85));
    });
  });
}
