import 'package:flutter_test/flutter_test.dart';

import '../../../tool/quality/coverage_filter.dart';
import '../../../tool/quality/coverage_gate.dart';

Map<String, FileCoverage> _filesWith(Map<String, (int lh, int lf)> spec) {
  final result = <String, FileCoverage>{};
  spec.forEach((path, counts) {
    final (lh, lf) = counts;
    // Synthesize DA records: first `lh` lines hit, rest uncovered.
    final da = <int, int>{
      for (var i = 1; i <= lf; i++) i: i <= lh ? 1 : 0,
    };
    result[path] = FileCoverage(path, da, lf, lh);
  });
  return result;
}

void main() {
  group('evaluateCoverageGate', () {
    test('exactly at the 90% floor passes (boundary, not "below")', () {
      final files = _filesWith({'a.dart': (90, 100)});
      final result = evaluateCoverageGate(files);
      expect(result.totalPercent, 90.0);
      expect(result.passed, isTrue);
    });

    test('89.99% fails', () {
      final files = _filesWith({'a.dart': (8999, 10000)});
      final result = evaluateCoverageGate(files);
      expect(result.totalPercent, closeTo(89.99, 0.001));
      expect(result.passed, isFalse);
    });

    test('top-uncovered report is ascending by percent and capped', () {
      final files = _filesWith({
        for (var i = 0; i < 15; i++) 'file_$i.dart': (i, 100),
      });
      final result = evaluateCoverageGate(files);
      expect(result.topUncovered, hasLength(maxTopUncoveredReported));
      for (var i = 1; i < result.topUncovered.length; i++) {
        expect(
          result.topUncovered[i - 1].percent,
          lessThanOrEqualTo(result.topUncovered[i].percent),
        );
      }
      // The lowest-coverage file (file_0.dart, 0%) must be first.
      expect(result.topUncovered.first.path, 'file_0.dart');
    });

    test('fully-covered files are excluded from the uncovered report', () {
      final files = _filesWith({'a.dart': (10, 10), 'b.dart': (5, 10)});
      final result = evaluateCoverageGate(files);
      expect(result.topUncovered, hasLength(1));
      expect(result.topUncovered.single.path, 'b.dart');
    });

    test('degenerate empty input does not divide by zero', () {
      final result = evaluateCoverageGate(<String, FileCoverage>{});
      expect(result.totalPercent, 100.0);
      expect(result.passed, isTrue);
      expect(result.topUncovered, isEmpty);
    });
  });
}
