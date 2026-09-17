import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/quality/coverage_filter.dart';
import '../../../tool/quality/coverage_inventory.dart';

/// Writes each entry in [files] (a lib-relative path -> content map) under a
/// temp `lib/`-shaped directory and returns that directory, so
/// `missingCoverageEvidence` can scan it exactly like the real `lib/`.
Directory _fixtureLibDir(Map<String, String> files) {
  final tempDir = Directory.systemTemp.createTempSync('coverage_inventory_test_');
  files.forEach((relativePath, content) {
    // relativePath is given relative to lib/, e.g. "bootstrap.dart" or
    // "sub/thing.dart".
    final file = File('${tempDir.path}${Platform.pathSeparator}$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  return tempDir;
}

void main() {
  group('missingCoverageEvidence', () {
    test(
      'a file with executable code missing from lcov is reported (LLA-106 '
      'remove-record fixture)',
      () {
        final dir = _fixtureLibDir({
          'bootstrap.dart': '''
void run() {
  print('hello');
}
''',
        });
        addTearDown(() => dir.deleteSync(recursive: true));

        // No entry for lib/bootstrap.dart at all -- as if its SF: record
        // was dropped from coverage/lcov.info.
        final missing = missingCoverageEvidence(
          const <String, FileCoverage>{},
          libDir: dir,
        );

        expect(missing, ['lib/bootstrap.dart']);
      },
    );

    test('a file present in the coverage map is not reported as missing', () {
      final dir = _fixtureLibDir({
        'present.dart': '''
void run() {
  print('hello');
}
''',
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      final filtered = <String, FileCoverage>{
        'lib/present.dart': FileCoverage('lib/present.dart', {1: 1}, 1, 1),
      };

      expect(missingCoverageEvidence(filtered, libDir: dir), isEmpty);
    });

    test(
      'a file with no executable code at all needs no evidence '
      '(distinguishes unmeasured from nonexecutable)',
      () {
        final dir = _fixtureLibDir({
          'pure_interface.dart': '''
abstract interface class Thing {
  void doSomething();
}
''',
        });
        addTearDown(() => dir.deleteSync(recursive: true));

        expect(
          missingCoverageEvidence(const <String, FileCoverage>{}, libDir: dir),
          isEmpty,
        );
      },
    );

    test('an empty lcov (nothing parsed at all) reports every real file', () {
      final dir = _fixtureLibDir({
        'a.dart': 'void a() { print(1); }',
        'b.dart': 'void b() { print(2); }',
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      final missing = missingCoverageEvidence(
        const <String, FileCoverage>{},
        libDir: dir,
      );

      expect(missing, ['lib/a.dart', 'lib/b.dart']);
    });

    test('matches Windows-native backslash SF paths against the lib walk', () {
      final dir = _fixtureLibDir({
        'sub/nested.dart': 'void run() { print(1); }',
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      final filtered = <String, FileCoverage>{
        r'lib\sub\nested.dart':
            FileCoverage(r'lib\sub\nested.dart', {1: 1}, 1, 1),
      };

      expect(missingCoverageEvidence(filtered, libDir: dir), isEmpty);
    });
  });
}
