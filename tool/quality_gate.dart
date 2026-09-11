/// Local + CI entrypoint for the coverage-floor and CRAP gates (plan U4).
///
/// `dart run tool/quality_gate.dart` — runs `flutter test --coverage`,
/// filters `coverage/lcov.info` through the shared exclusion list, then
/// evaluates both gates and prints both reports. Exits 0 only if both pass.
/// `flutter test` (no `--coverage`) is unaffected and stays fast for quick
/// local iteration (R11) — this script is the only thing that runs the
/// gates.
///
/// Locally on Windows (not CI), this routes through
/// `tool/dart_concurrency_guard.ps1`, capped at 3 concurrent dart.exe/
/// flutter_tester.exe processes (see `docs/dart-concurrency.md`) — several
/// OpenCode coder subagents can be verifying their own work in parallel, and
/// without a cap that multiplies fast enough to exhaust this desktop's
/// memory. CI runs one isolated job per runner, so the guard would be
/// pointless overhead there; CI's own `flutter test --coverage` call is
/// unchanged.
library;

import 'dart:io';

import 'quality/coverage_filter.dart';
import 'quality/coverage_gate.dart';
import 'quality/crap_gate.dart';

Future<ProcessResult> _runFlutterTestWithCoverage() {
  final isCi = Platform.environment['CI'] == 'true';
  if (Platform.isWindows && !isCi) {
    return Process.run(
      'pwsh',
      [
        '-NoProfile',
        '-File',
        'tool/dart_concurrency_guard.ps1',
        '-Command',
        'flutter.bat',
        '-Arguments',
        'test,--coverage,--concurrency=1',
      ],
      runInShell: true,
    );
  }
  return Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    ['test', '--coverage'],
    runInShell: true,
  );
}

Future<void> main(List<String> args) async {
  // ignore: avoid_print
  print('[quality_gate] running flutter test --coverage ...');
  final testResult = await _runFlutterTestWithCoverage();
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
