/// Local (non-CI) mutation-testing entrypoint (plan U6, R8/R9).
///
/// Default scope: files changed against the merge base with `origin/main`
/// (falling back to `HEAD~1` when that ref isn't available), including
/// uncommitted changes. `--full` mutates every non-excluded `lib/**.dart`
/// file instead; no time budget, run on demand. No CI gate reads this
/// script's exit code or report (R8) — it's local verification only.
///
/// `dart run tool/mutation_gate.dart`        (changed files, the default)
/// `dart run tool/mutation_gate.dart --full` (every lib/ file)
///
/// **Runtime note (R8's "a few minutes" target):** `mutation_test` re-runs
/// its test command once per mutant — the naive command, `flutter test`
/// (the whole ~480-test suite, ~2 minutes), would make even a handful of
/// mutants take many minutes. When every scoped source file has a
/// directly mirrored test file (`lib/a/b.dart` -> `test/a/b_test.dart` —
/// true for most of `lib/domain/`), this script scopes the test command
/// to just those files instead of the whole suite, which is what actually
/// keeps a typical run to a few minutes. When any scoped file lacks a
/// direct mirror (most `lib/ui/` and `lib/data/` files, which this repo
/// tests through broader per-feature suites like `test/ui/account_test.dart`
/// rather than 1:1), the command falls back to the full suite for
/// correctness — narrowing to a guessed, possibly-wrong test file would
/// produce false "mutant survived" results. A `--full` run, or a
/// changed-files run that includes any non-mirrored file, does not carry
/// the few-minutes guarantee; that is a real limitation of the test
/// command per mutant, not a bug in this script (see the plan's U6
/// Approach #4).
library;

import 'dart:io';

import 'quality/exclusions.dart';

Future<void> main(List<String> args) async {
  final full = args.contains('--full');
  final files = full ? await _allLibDartFiles() : await _changedLibDartFiles();

  if (files.isEmpty) {
    // ignore: avoid_print
    print('[mutation_gate] no ${full ? '' : 'changed '}lib/ files to mutate.');
    return;
  }

  // ignore: avoid_print
  print('[mutation_gate] ${full ? 'full run' : 'changed-files run'}: '
      '${files.length} file(s)');
  for (final f in files) {
    // ignore: avoid_print
    print('[mutation_gate]   $f');
  }

  final testTargets = _mirroredTestFiles(files);
  final testCommand = testTargets == null
      ? 'flutter test'
      : 'flutter test ${testTargets.join(' ')}';
  if (testTargets == null) {
    // ignore: avoid_print
    print('[mutation_gate] no direct test mirror for every scoped file -- '
        'running the full suite per mutant (see this file\'s doc comment '
        'on the few-minutes target).');
  } else {
    // ignore: avoid_print
    print('[mutation_gate] scoping the test command to: '
        '${testTargets.join(', ')}');
  }

  final rulesFile = await _writeScopedRulesXml(testCommand);
  try {
    // mutation_test.xml's <command> shells out to `flutter`; it must
    // already be resolvable on PATH in this shell (see README "Build /
    // run" for the one-time PATH setup on this desktop).
    final result = await Process.run(
      Platform.isWindows ? 'dart.bat' : 'dart',
      ['run', 'mutation_test', '--rules', rulesFile.path, '-b', ...files],
      runInShell: true,
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  } finally {
    if (rulesFile.existsSync()) rulesFile.deleteSync();
  }
}

Future<List<String>> _changedLibDartFiles() async {
  final base = await _diffBaseRef();
  final diff = await Process.run('git', ['diff', '--name-only', base]);
  final names = (diff.stdout as String).split('\n');
  return _libDartFilesFrom(names);
}

/// The merge base with `origin/main` when that ref exists locally (a
/// feature branch/worktree usually has it after a fetch); otherwise the
/// previous commit, so a run still works in a checkout with no `origin`.
Future<String> _diffBaseRef() async {
  final mergeBase =
      await Process.run('git', ['merge-base', 'HEAD', 'origin/main']);
  if (mergeBase.exitCode == 0) {
    return (mergeBase.stdout as String).trim();
  }
  return 'HEAD~1';
}

Future<List<String>> _allLibDartFiles() async {
  final names = <String>[];
  final libDir = Directory('lib');
  await for (final entity in libDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      names.add(entity.path);
    }
  }
  return _libDartFilesFrom(names);
}

/// Normalizes to forward slashes, keeps only non-excluded `lib/**.dart`
/// paths, and sorts for a stable, readable report.
List<String> _libDartFilesFrom(Iterable<String> rawPaths) {
  final result = <String>[];
  for (final raw in rawPaths) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final normalized = trimmed.replaceAll('\\', '/');
    if (!normalized.startsWith('lib/') || !normalized.endsWith('.dart')) {
      continue;
    }
    if (isExcluded(normalized)) continue;
    result.add(normalized);
  }
  result.sort();
  return result;
}

/// `lib/a/b.dart` -> `test/a/b_test.dart`. Returns the deduped, sorted set
/// of mirrored test files when EVERY entry in [libFiles] has one, or
/// `null` when any file lacks a direct mirror (the command then falls
/// back to the full suite for that file's sake too — never a partial,
/// possibly-wrong scope).
List<String>? _mirroredTestFiles(List<String> libFiles) {
  final mirrors = <String>{};
  for (final lib in libFiles) {
    final withoutPrefix = lib.substring('lib/'.length);
    final withoutExt =
        withoutPrefix.substring(0, withoutPrefix.length - '.dart'.length);
    final candidate = 'test/${withoutExt}_test.dart';
    if (!File(candidate).existsSync()) return null;
    mirrors.add(candidate);
  }
  final sorted = mirrors.toList()..sort();
  return sorted;
}

/// Test-only export of [_libDartFilesFrom] (private functions can't be
/// imported across files).
List<String> libDartFilesFromForTest(Iterable<String> rawPaths) =>
    _libDartFilesFrom(rawPaths);

/// Test-only export of [_mirroredTestFiles].
List<String>? mirroredTestFilesForTest(List<String> libFiles) =>
    _mirroredTestFiles(libFiles);

/// Writes a temporary `--rules` document carrying this repo's shared
/// exclusions (mirroring `tool/quality/exclusions.dart`, KTD4/KTD6) and
/// the resolved [testCommand]. Deleted by the caller after the run.
Future<File> _writeScopedRulesXml(String testCommand) async {
  final file = File(
      '${Directory.systemTemp.path}/lunarlog_mutation_rules_${DateTime.now().microsecondsSinceEpoch}.xml');
  await file.writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<mutations version="1.2">
  <exclude>
    <directory>**/*.g.dart</directory>
    <directory>lib/data/auth/google_sign_in_client.dart</directory>
    <directory>lib/data/auth/auth_gateway.dart</directory>
    <directory>lib/data/db/key_store.dart</directory>
    <directory>lib/data/notifications/notification_scheduler.dart</directory>
  </exclude>
  <commands>
    <command group="test" expected-return="0" working-directory=".">$testCommand</command>
  </commands>
</mutations>
''');
  return file;
}
