import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/quality/coverage_filter.dart';
import '../../../tool/quality/crap_gate.dart';

/// Writes [content] to a fixture `.dart` file under a temp `lib/`
/// directory and returns that directory, so `evaluateCrapGate` can scan it
/// exactly like the real `lib/`.
Directory _fixtureLibDir(String fileName, String content) {
  final tempDir = Directory.systemTemp.createTempSync('crap_gate_test_');
  final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
  file.writeAsStringSync(content);
  return tempDir;
}

Map<String, FileCoverage> _coverageFor(
  String libRelativePath,
  Map<int, int> daHits,
) {
  var lf = 0;
  var lh = 0;
  daHits.forEach((_, hits) {
    lf++;
    if (hits > 0) lh++;
  });
  return {
    libRelativePath: FileCoverage(libRelativePath, daHits, lf, lh),
  };
}

void main() {
  group('evaluateCrapGate', () {
    test('a trivial one-line method at 0% coverage is never a false positive', () {
      // complexity 1 (no decision points), 0% coverage:
      // CRAP = 1^2 * 1^3 + 1 = 2, well under the threshold of 10.
      final dir = _fixtureLibDir('trivial.dart', '''
class Trivial {
  int addOne(int x) {
    return x + 1;
  }
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final result = evaluateCrapGate(const {}, libDir: dir);
      expect(result.passed, isTrue);
      expect(result.offenders, isEmpty);
    });

    test('complexity 3 at 0% coverage scores 12 and is reported', () {
      // Two decision points (one `if`, one `&&` inside it) => complexity 3.
      final source = '''
class Risky {
  int classify(int x, int y) {
    if (x > 0 && y > 0) {
      return 1;
    }
    return 0;
  }
}
''';
      final dir = _fixtureLibDir('risky.dart', source);
      addTearDown(() => dir.deleteSync(recursive: true));

      // complexity = 1 (base) + 1 (if) + 1 (&&) = 3.
      // All method-body lines present but uncovered (hit count 0) so
      // cov(m) = 0%. Lines 3-6 are the method body/signature range.
      final daHits = {for (var line = 2; line <= 6; line++) line: 0};
      final coverage = _coverageFor('lib/risky.dart', daHits);

      final result = evaluateCrapGate(coverage, libDir: dir);
      expect(result.passed, isFalse);
      expect(result.offenders, hasLength(1));
      final offender = result.offenders.single;
      expect(offender.complexity, 3);
      expect(offender.coveragePercent, 0.0);
      // CRAP = 3^2 * 1^3 + 3 = 12.
      expect(offender.crapScore, closeTo(12.0, 0.01));
    });

    test('the same complexity-3 method at 100% coverage is not reported', () {
      final source = '''
class Risky {
  int classify(int x, int y) {
    if (x > 0 && y > 0) {
      return 1;
    }
    return 0;
  }
}
''';
      final dir = _fixtureLibDir('risky.dart', source);
      addTearDown(() => dir.deleteSync(recursive: true));

      final daHits = {for (var line = 2; line <= 6; line++) line: 1};
      final coverage = _coverageFor('lib/risky.dart', daHits);

      final result = evaluateCrapGate(coverage, libDir: dir);
      expect(result.passed, isTrue);
      expect(result.offenders, isEmpty);
    });

    test('an abstract method is skipped, not scored as 0% coverage', () {
      final dir = _fixtureLibDir('interface_only.dart', '''
abstract interface class Thing {
  void doSomething();
}
''');
      addTearDown(() => dir.deleteSync(recursive: true));
      final result = evaluateCrapGate(const {}, libDir: dir);
      expect(result.offenders, isEmpty);
    });

    test('two methods in the same file get independently attributed coverage', () {
      // Both methods have complexity 4 (base 1 + three sequential ifs), so
      // an incorrectly-blended coverage number (e.g. averaging both
      // methods' hits) would change which one(s) cross the threshold.
      final source = '''
class TwoMethods {
  int riskyA(int x) {
    if (x > 0) return 1;
    if (x > 1) return 2;
    if (x > 2) return 3;
    return 0;
  }

  int riskyB(int x) {
    if (x < 0) return -1;
    if (x < -1) return -2;
    if (x < -2) return -3;
    return 0;
  }
}
''';
      final dir = _fixtureLibDir('two_methods.dart', source);
      addTearDown(() => dir.deleteSync(recursive: true));

      // riskyA (lines 2-7) fully covered; riskyB (lines 9-14) fully
      // uncovered.
      final daHits = {
        for (var line = 2; line <= 7; line++) line: 1,
        for (var line = 9; line <= 14; line++) line: 0,
      };
      final coverage = _coverageFor('lib/two_methods.dart', daHits);

      final result = evaluateCrapGate(coverage, libDir: dir);
      // riskyA: comp=4, cov=100% -> CRAP = 16*0 + 4 = 4 (not reported).
      // riskyB: comp=4, cov=0%   -> CRAP = 16*1 + 4 = 20 (reported).
      // If coverage were blended across the file (e.g. averaged), riskyB
      // would show ~50% instead of 0%, and its score would drop to
      // 16*0.125+4=6 (not reported) — so this assertion also proves the
      // two methods aren't cross-contaminating each other's coverage.
      expect(result.offenders, hasLength(1));
      expect(result.offenders.single.methodName, 'TwoMethods.riskyB');
      expect(result.offenders.single.coveragePercent, 0.0);
    });
  });
}
