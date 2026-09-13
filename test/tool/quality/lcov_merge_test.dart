import 'package:flutter_test/flutter_test.dart';

import '../../../tool/quality/coverage_filter.dart';
import '../../../tool/quality/lcov_merge.dart';

const _shardA = '''
SF:lib/a.dart
DA:1,1
DA:2,0
DA:3,0
LF:3
LH:1
end_of_record
SF:lib/b.dart
DA:10,2
LF:1
LH:1
end_of_record
''';

const _shardB = '''
SF:lib/a.dart
DA:1,0
DA:2,3
DA:3,0
LF:3
LH:1
end_of_record
SF:lib/c.dart
DA:5,0
LF:1
LH:0
end_of_record
''';

void main() {
  group('mergeLcovContents', () {
    test('sums hit counts per (file, line) across shards', () {
      final merged = parseLcov(mergeLcovContents([_shardA, _shardB]));
      expect(merged['lib/a.dart']!.daHits, {1: 1, 2: 3, 3: 0});
    });

    test('recomputes LF/LH from the merged hits, not from the inputs', () {
      final merged = parseLcov(mergeLcovContents([_shardA, _shardB]));
      final a = merged['lib/a.dart']!;
      // Each shard alone covered 1 of 3 lines; together they cover 2.
      expect(a.lf, 3);
      expect(a.lh, 2);
    });

    test('keeps files that appear in only one shard', () {
      final merged = parseLcov(mergeLcovContents([_shardA, _shardB]));
      expect(merged.keys, containsAll(['lib/b.dart', 'lib/c.dart']));
      expect(merged['lib/b.dart']!.daHits, {10: 2});
      expect(merged['lib/c.dart']!.lh, 0);
    });

    test('is order-independent and deterministic', () {
      expect(
        mergeLcovContents([_shardA, _shardB]),
        mergeLcovContents([_shardB, _shardA]),
      );
    });

    test('a single input round-trips through the parser unchanged', () {
      final once = parseLcov(_shardA);
      final merged = parseLcov(mergeLcovContents([_shardA]));
      for (final path in once.keys) {
        expect(merged[path]!.daHits, once[path]!.daHits);
        expect(merged[path]!.lf, once[path]!.lf);
        expect(merged[path]!.lh, once[path]!.lh);
      }
    });

    test('empty input produces an empty document', () {
      expect(mergeLcovContents(const []), isEmpty);
    });
  });
}
