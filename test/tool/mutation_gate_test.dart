import 'package:flutter_test/flutter_test.dart';

import '../../tool/mutation_gate.dart' show libDartFilesFromForTest, mirroredTestFilesForTest;

void main() {
  group('_libDartFilesFrom (via test-only export)', () {
    test('keeps only lib/**.dart paths, normalizes separators, sorts', () {
      final result = libDartFilesFromForTest([
        r'lib\domain\models\profile.dart',
        'lib/domain/tags.dart',
        'test/domain/tags_test.dart', // not lib/
        'README.md', // not .dart
        '  ', // blank
        'lib/data/db/db.g.dart', // excluded (generated)
      ]);
      expect(result, [
        'lib/domain/models/profile.dart',
        'lib/domain/tags.dart',
      ]);
    });

    test('drops the reviewed platform-adapter exclusions too', () {
      final result = libDartFilesFromForTest([
        'lib/data/auth/google_sign_in_client.dart',
        'lib/domain/tags.dart',
      ]);
      expect(result, ['lib/domain/tags.dart']);
    });
  });

  group('_mirroredTestFiles (via test-only export)', () {
    test('finds the real mirrored test for day_entry.dart', () {
      final result = mirroredTestFilesForTest(['lib/domain/models/day_entry.dart']);
      expect(result, ['test/domain/models/day_entry_test.dart']);
    });

    test('returns null when any file lacks a direct mirror', () {
      final result = mirroredTestFilesForTest([
        'lib/domain/models/day_entry.dart', // has one
        'lib/domain/util/list_equals.dart', // does not
      ]);
      expect(result, isNull);
    });

    test('dedupes and sorts when multiple files map cleanly', () {
      final result = mirroredTestFilesForTest([
        'lib/domain/models/profile.dart',
        'lib/domain/models/day_entry.dart',
      ]);
      expect(result, [
        'test/domain/models/day_entry_test.dart',
        'test/domain/models/profile_test.dart',
      ]);
    });
  });
}
