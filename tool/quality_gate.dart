/// Local + CI entrypoint for the coverage-floor and CRAP gates (plan U4).
///
/// `dart run tool/quality_gate.dart` — runs `flutter test --coverage`,
/// filters `coverage/lcov.info` through the shared exclusion list, then
/// evaluates both gates and prints both reports. Exits 0 only if both pass.
/// `flutter test` (no `--coverage`) is unaffected and stays fast for quick
/// local iteration (R11) — this script is the only thing that runs the
/// gates.
library;

import 'dart:io';

import 'quality/coverage_filter.dart';
import 'quality/coverage_gate.dart';
import 'quality/crap_gate.dart';

Future<void> main(List<String> args) async {
  // ignore: avoid_print
  print('[quality_gate] running flutter test --coverage ...');
  final testResult = await Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    ['test', '--coverage'],
    runInShell: true,
  );
  stdout.write(testResult.stdout);
  stderr.write(testResult.stderr);
  if (testResult.exitCode != 0) {
    // A gate run never masks a genuine test failure.
    // ignore: avoid_print
    print('[quality_gate] flutter test failed — quality gates did not run.');
    exit(testResult.exitCode);
  }

  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    // ignore: avoid_print
    print('[quality_gate] coverage/lcov.info not found after flutter test '
        '--coverage.');
    exit(1);
  }

  final filtered = filteredCoverageFromFile(lcovFile);

  final coverageResult = evaluateCoverageGate(filtered);
  printCoverageReport(coverageResult);

  final crapResult = evaluateCrapGate(filtered);
  printCrapReport(crapResult);

  final passed = coverageResult.passed && crapResult.passed;
  // ignore: avoid_print
  print('[quality_gate] ${passed ? "PASS" : "FAIL"}');
  exit(passed ? 0 : 1);
}
