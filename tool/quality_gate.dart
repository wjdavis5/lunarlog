/// Local + CI entrypoint for the coverage-floor and CRAP gates (plan U4).
///
/// `dart run tool/quality_gate.dart` — runs `flutter test --coverage`,
/// filters `coverage/lcov.info` through the shared exclusion list, then
/// evaluates both gates and prints both reports. Exits 0 only if both pass.
/// `flutter test` (no `--coverage`) is unaffected and stays fast for quick
/// local iteration (R11) — this script is the only thing that runs the
/// gates.
///
/// `dart run tool/quality_gate.dart --lcov a.info --lcov b.info ...` skips
/// the test run and evaluates the gates over the given lcov files merged
/// (see quality/lcov_merge.dart). CI uses this: the suite runs as N
/// sharded `flutter test --coverage` jobs in parallel and the gate job
/// merges their artifacts, so the suite runs once, split across runners,
/// instead of once for `flutter test` and again for coverage.
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
import 'quality/lcov_merge.dart';

/// Issue #574: `Process.run` buffers all child output until the process
/// exits, so this ~13-minute run printed nothing the whole time —
/// indistinguishable from a hang locally. `Process.start` with the child's
/// stdout/stderr piped straight through lets output appear live, the same
/// as running `flutter test --coverage` directly.
Future<int> _runFlutterTestWithCoverage() async {
  final isCi = Platform.environment['CI'] == 'true';
  final Process process;
  if (Platform.isWindows && !isCi) {
    process = await Process.start('pwsh', [
      '-NoProfile',
      '-File',
      'tool/dart_concurrency_guard.ps1',
      '-Command',
      'flutter.bat',
      '-Arguments',
      'test,--coverage,--concurrency=1',
    ], runInShell: true);
  } else {
    process = await Process.start(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['test', '--coverage'],
      runInShell: true,
    );
  }
  final stdoutDone = stdout.addStream(process.stdout);
  final stderrDone = stderr.addStream(process.stderr);
  final exitCode = await process.exitCode;
  // Drain both streams fully before returning, so no trailing output is
  // lost/interleaved with what main() prints next.
  await Future.wait([stdoutDone, stderrDone]);
  return exitCode;
}

/// Paths passed as `--lcov <path>` (repeatable). Empty when the caller
/// wants this script to run the suite itself.
List<String> _lcovArgs(List<String> args) {
  final paths = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--lcov') {
      if (i + 1 >= args.length) {
        // ignore: avoid_print
        print('[quality_gate] --lcov requires a path.');
        exit(64);
      }
      paths.add(args[++i]);
    } else if (args[i].startsWith('--lcov=')) {
      paths.add(args[i].substring('--lcov='.length));
    } else {
      // ignore: avoid_print
      print('[quality_gate] unknown argument: ${args[i]}');
      exit(64);
    }
  }
  return paths;
}

Future<void> main(List<String> args) async {
  final lcovFile = File('coverage/lcov.info');
  final lcovInputs = _lcovArgs(args);
  if (lcovInputs.isNotEmpty) {
    // ignore: avoid_print
    print('[quality_gate] merging ${lcovInputs.length} lcov file(s) ...');
    final contents = <String>[];
    for (final path in lcovInputs) {
      final f = File(path);
      if (!f.existsSync()) {
        // ignore: avoid_print
        print('[quality_gate] lcov file not found: $path');
        exit(1);
      }
      contents.add(f.readAsStringSync());
    }
    lcovFile.parent.createSync(recursive: true);
    lcovFile.writeAsStringSync(mergeLcovContents(contents));
  } else {
    // ignore: avoid_print
    print('[quality_gate] running flutter test --coverage ...');
    final testExitCode = await _runFlutterTestWithCoverage();
    if (testExitCode != 0) {
      // A gate run never masks a genuine test failure.
      // ignore: avoid_print
      print('[quality_gate] flutter test failed — quality gates did not run.');
      exit(testExitCode);
    }
  }

  if (!lcovFile.existsSync()) {
    // ignore: avoid_print
    print(
      '[quality_gate] coverage/lcov.info not found after flutter test '
      '--coverage.',
    );
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
