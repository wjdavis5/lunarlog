/// Sentry symbol-upload workflow guard (U5; KTD10, KTD11; R15, R16, R17,
/// AE8, AE9). Mirrors `export_compliance_test.dart`'s shape: read the two
/// release workflow files as text and assert the invariants that make the
/// upload step safe to land before issue #19 provisions any secret.
///
/// The guard/download/checksum-verify logic itself lives in the shared
/// `.github/scripts/upload-sentry-symbols-setup.sh` (its own truth table is
/// `.github/scripts/tests/upload-sentry-symbols-setup.test.sh`, run in CI's
/// release-guards jobs) -- both workflow files call it identically, so this
/// file asserts the *delegation* shape: the script runs, the required env
/// vars reach it, and the platform's upload command only runs after the
/// script leaves `./sentry-cli` executable.
///
/// Comment lines are stripped before matching, the same trap
/// `export_compliance_test.dart` documents: a commented-out step must not
/// satisfy any assertion here.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _iosWorkflowPath = '.github/workflows/ios-release.yml';
const _androidWorkflowPath = '.github/workflows/play-store-release.yml';
const _gradlePath = 'android/app/build.gradle.kts';
const _sharedScriptPath = '.github/scripts/upload-sentry-symbols-setup.sh';

String _readRepoFile(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'expected to find $path at the repo root '
          '(flutter test runs with CWD at the repo root)');
  final contents = file.readAsStringSync();
  expect(contents, isNotEmpty, reason: '$path exists but is empty');
  return contents;
}

/// Strips full-line `#` comments (YAML) so a commented-out step cannot
/// satisfy any assertion below.
String _stripYamlComments(String yaml) => yaml
    .split('\n')
    .where((line) => !RegExp(r'^\s*#').hasMatch(line))
    .join('\n');

/// The whole Sentry symbol-upload step body, matched from its `name:` line
/// (case-insensitively naming "Sentry" and "symbol") up to (but not
/// including) the next `- name:` step at the same indentation, or end of
/// file.
String _sentrySymbolStepBody(String strippedYaml) {
  final stepStart = RegExp(
    r'-\s*name:\s*.*Sentry.*symbol.*',
    caseSensitive: false,
  );
  final match = stepStart.firstMatch(strippedYaml);
  expect(match, isNotNull,
      reason: 'expected a step whose name matches /Sentry.*symbol/i');
  final rest = strippedYaml.substring(match!.end);
  final nextStep = RegExp(r'\n\s*-\s*name:');
  final nextMatch = nextStep.firstMatch(rest);
  return nextMatch == null ? rest : rest.substring(0, nextMatch.start);
}

/// The `run:` block only (the shell body actually executed), excluding the
/// `env:` mapping above it -- `env: SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_
/// AUTH_TOKEN }}` is the correct, required idiom (KTD10's "secrets only
/// under env:" rule is about the *shell* body, not the env mapping itself).
String _runBlockOf(String stepBody) {
  final runIndex = stepBody.indexOf('run:');
  expect(runIndex, greaterThanOrEqualTo(0),
      reason: 'expected a run: block in the Sentry symbol upload step');
  return stepBody.substring(runIndex);
}

void main() {
  group('Sentry symbol upload workflow guard (U5)', () {
    for (final entry in {
      'iOS': _iosWorkflowPath,
      'Android': _androidWorkflowPath,
    }.entries) {
      final platform = entry.key;
      final path = entry.value;

      group(platform, () {
        late String stepBody;
        late String runBlock;

        setUpAll(() {
          final contents = _stripYamlComments(_readRepoFile(path));
          stepBody = _sentrySymbolStepBody(contents);
          runBlock = _runBlockOf(stepBody);
        });

        test('all three upload secrets reach the step via env:, not '
            'interpolated into the run body', () {
          for (final secret in [
            'SENTRY_AUTH_TOKEN',
            'SENTRY_ORG',
            'SENTRY_PROJECT',
          ]) {
            expect(stepBody, contains(secret), reason: secret);
          }
          expect(runBlock, isNot(contains(r'${{ secrets.SENTRY_')));
        });

        test('delegates the guard/download/checksum-verify logic to the '
            'shared script, before any sentry-cli invocation', () {
          expect(runBlock, contains('bash $_sharedScriptPath'));
          final scriptIndex = runBlock.indexOf(_sharedScriptPath);
          final cliIndex = runBlock.indexOf('sentry-cli');
          expect(cliIndex, greaterThan(scriptIndex),
              reason: 'the shared script must run before sentry-cli is '
                  'invoked directly');
        });

        test('the upload command only runs when the shared script left '
            './sentry-cli executable', () {
          expect(runBlock, contains(RegExp(r'if\s*\[\s*-x\s*\.?/?sentry-cli')));
        });

        test('passes the download URL, checksum, and checksum tool as env, '
            'not hard-coded inside the shared script', () {
          for (final key in [
            'SENTRY_CLI_DOWNLOAD_URL',
            'SENTRY_CLI_SHA256',
            'SENTRY_CLI_CHECKSUM_TOOL',
          ]) {
            expect(stepBody, contains(key), reason: key);
          }
        });

        test('the step itself never inlines a curl | shell pipeline (that '
            'logic is the shared script\'s alone)', () {
          expect(runBlock, isNot(contains(RegExp(r'curl[^\n]*\|\s*(ba)?sh'))));
          expect(runBlock, isNot(contains(RegExp(r'wget[^\n]*\|\s*(ba)?sh'))));
        });

        test('no TOKEN-named variable is ever echoed', () {
          final echoTokenPattern =
              RegExp(r'echo[^\n]*TOKEN', caseSensitive: false);
          for (final match in echoTokenPattern.allMatches(stepBody)) {
            final line = match.group(0)!;
            expect(line, isNot(contains(r'$SENTRY_AUTH_TOKEN')),
                reason: 'a line must never echo the token value: $line');
            expect(line, isNot(contains(r'${SENTRY_AUTH_TOKEN')),
                reason: 'a line must never echo the token value: $line');
          }
        });
      });
    }

    test('the iOS step references the archive dSYMs directory', () {
      final contents = _stripYamlComments(_readRepoFile(_iosWorkflowPath));
      final stepBody = _sentrySymbolStepBody(contents);
      expect(stepBody, contains('build/ios/archive/Runner.xcarchive/dSYMs'));
      expect(stepBody, isNot(contains('--include-sources')));
    });

    test("the Android step's ProGuard upload is inside a mapping.txt "
        'existence conditional', () {
      final contents =
          _stripYamlComments(_readRepoFile(_androidWorkflowPath));
      final stepBody = _sentrySymbolStepBody(contents);
      expect(stepBody, contains('upload-proguard'));
      final guardIndex = stepBody.indexOf('mapping.txt');
      final uploadIndex = stepBody.indexOf('upload-proguard');
      expect(guardIndex, greaterThanOrEqualTo(0));
      expect(guardIndex, lessThan(uploadIndex));
      // The conditional form -- `[ -f ... mapping.txt ]` -- gates the
      // upload-proguard invocation, not just mentions the filename nearby.
      expect(stepBody, contains(RegExp(r'-f\s+"?\$?\{?mapping')));
    });

    test('AE9: build.gradle.kts declares sentry-native-ndk and enables '
        'Prefab', () {
      final gradle = _readRepoFile(_gradlePath);
      expect(gradle, contains('io.sentry:sentry-native-ndk'));
      expect(gradle, contains('prefab = true'));
    });

    test('the shared script exists and is referenced from both workflows',
        () {
      _readRepoFile(_sharedScriptPath); // asserts existence/non-empty
      for (final path in [_iosWorkflowPath, _androidWorkflowPath]) {
        expect(_readRepoFile(path), contains(_sharedScriptPath),
            reason: path);
      }
    });
  });
}
