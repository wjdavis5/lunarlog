/// Sentry symbol-upload workflow guard (U5; KTD10, KTD11; R15, R16, R17,
/// AE8, AE9). Mirrors `export_compliance_test.dart`'s shape: read the two
/// release workflow files as text and assert the invariants that make the
/// upload steps safe to land before issue #19 provisions any secret.
///
/// The guard/download/checksum-verify logic itself lives in the shared
/// `.github/scripts/upload-sentry-symbols-setup.sh` (its own truth table is
/// `.github/scripts/tests/upload-sentry-symbols-setup.test.sh`, run in CI's
/// release-guards jobs) -- both workflow files call it identically, so this
/// file asserts the *delegation* shape: the setup step runs the script and
/// receives its env, and the platform's upload command (a separate step,
/// since round 2 of issue #7's review split them so `continue-on-error`
/// stops covering the checksum verification -- see the shared script's own
/// doc comment) only runs after the script leaves `./sentry-cli` executable.
///
/// Comment lines are stripped before matching, the same trap
/// `export_compliance_test.dart` documents: a commented-out step must not
/// satisfy any assertion here.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _iosWorkflowPath = '.github/workflows/ios-release.yml';
const _androidWorkflowPath = '.github/workflows/play-store-release.yml';
const _gradlePath = 'android/app/build.gradle.kts';
const _sharedScriptPath = '.github/scripts/upload-sentry-symbols-setup.sh';

/// Matches a step body from its `name:` line up to (but not including) the
/// next `- name:` step at the same indentation, or end of file.
String _stepBodyNamed(String strippedYaml, RegExp stepStart, String reason) {
  final match = stepStart.firstMatch(strippedYaml);
  expect(match, isNotNull, reason: reason);
  final rest = strippedYaml.substring(match!.end);
  final nextStep = RegExp(r'\n\s*-\s*name:');
  final nextMatch = nextStep.firstMatch(rest);
  return nextMatch == null ? rest : rest.substring(0, nextMatch.start);
}

/// The sentry-cli setup step -- downloads and checksum-verifies the pinned
/// binary via the shared script. Split from the upload step below (round 2
/// of issue #7's review) precisely so it carries no `continue-on-error`: a
/// checksum mismatch here must fail the job loudly.
String _sentrySetupStepBody(String strippedYaml) => _stepBodyNamed(
      strippedYaml,
      RegExp(r'-\s*name:\s*.*Set up sentry-cli.*', caseSensitive: false),
      'expected a step whose name matches /Set up sentry-cli/i',
    );

/// The whole Sentry symbol-upload step body, matched from its `name:` line
/// (case-insensitively naming "Sentry" and "symbol") up to (but not
/// including) the next `- name:` step at the same indentation, or end of
/// file. This is the step that makes the actual Sentry upload network
/// call(s) and is the only one of the two carrying `continue-on-error`.
String _sentrySymbolStepBody(String strippedYaml) => _stepBodyNamed(
      strippedYaml,
      RegExp(r'-\s*name:\s*.*Sentry.*symbol.*', caseSensitive: false),
      'expected a step whose name matches /Sentry.*symbol/i',
    );

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
        late String contents;
        late String setupStepBody;
        late String setupRunBlock;
        late String stepBody;
        late String runBlock;

        setUpAll(() {
          contents = stripHashComments(readRepoFile(path));
          setupStepBody = _sentrySetupStepBody(contents);
          setupRunBlock = _runBlockOf(setupStepBody);
          stepBody = _sentrySymbolStepBody(contents);
          runBlock = _runBlockOf(stepBody);
        });

        test('all three upload secrets reach both steps via env:, not '
            'interpolated into either run body', () {
          for (final body in [setupStepBody, stepBody]) {
            for (final secret in [
              'SENTRY_AUTH_TOKEN',
              'SENTRY_ORG',
              'SENTRY_PROJECT',
            ]) {
              expect(body, contains(secret), reason: secret);
            }
          }
          for (final block in [setupRunBlock, runBlock]) {
            expect(block, isNot(contains(r'${{ secrets.SENTRY_')));
          }
        });

        test('the setup step delegates the guard/download/checksum-verify '
            'logic to the shared script, and runs before the upload step '
            'in the workflow file', () {
          expect(setupRunBlock, contains('bash $_sharedScriptPath'));
          final setupIndex = contents.indexOf(_sentrySetupStepBody(contents));
          final uploadIndex = contents.indexOf(_sentrySymbolStepBody(contents));
          expect(setupIndex, lessThan(uploadIndex),
              reason: 'the setup step must appear before the upload step, '
                  'so the checksum-verified binary already exists when the '
                  'upload step\'s sentry-cli invocation runs');
        });

        test('the setup step never invokes sentry-cli directly -- only the '
            'shared script (round 2 of issue #7\'s review: setup and '
            'upload are separate steps)', () {
          expect(setupRunBlock, isNot(contains('sentry-cli')));
        });

        test('the setup step carries no continue-on-error, so a checksum '
            'mismatch fails the job loudly (round 2 of issue #7\'s '
            'review)', () {
          expect(setupStepBody, isNot(contains('continue-on-error')));
        });

        test('the upload step carries continue-on-error, scoped to just '
            'the Sentry upload network call', () {
          expect(stepBody, contains('continue-on-error: true'));
        });

        test('the upload command only runs when the shared script left '
            './sentry-cli executable', () {
          expect(runBlock, contains(RegExp(r'if\s*\[\s*-x\s*\.?/?sentry-cli')));
        });

        test('passes the download URL, checksum, and checksum tool as env '
            'to the setup step, not hard-coded inside the shared script', () {
          for (final key in [
            'SENTRY_CLI_DOWNLOAD_URL',
            'SENTRY_CLI_SHA256',
            'SENTRY_CLI_CHECKSUM_TOOL',
          ]) {
            expect(setupStepBody, contains(key), reason: key);
          }
        });

        test('neither step inlines a curl | shell pipeline (that logic is '
            'the shared script\'s alone)', () {
          for (final block in [setupRunBlock, runBlock]) {
            expect(block, isNot(contains(RegExp(r'curl[^\n]*\|\s*(ba)?sh'))));
            expect(block, isNot(contains(RegExp(r'wget[^\n]*\|\s*(ba)?sh'))));
          }
        });

        test('no TOKEN-named variable is ever echoed', () {
          final echoTokenPattern =
              RegExp(r'echo[^\n]*TOKEN', caseSensitive: false);
          for (final body in [setupStepBody, stepBody]) {
            for (final match in echoTokenPattern.allMatches(body)) {
              final line = match.group(0)!;
              expect(line, isNot(contains(r'$SENTRY_AUTH_TOKEN')),
                  reason: 'a line must never echo the token value: $line');
              expect(line, isNot(contains(r'${SENTRY_AUTH_TOKEN')),
                  reason: 'a line must never echo the token value: $line');
            }
          }
        });
      });
    }

    test('the iOS step references the archive dSYMs directory', () {
      final contents = stripHashComments(readRepoFile(_iosWorkflowPath));
      final stepBody = _sentrySymbolStepBody(contents);
      expect(stepBody, contains('build/ios/archive/Runner.xcarchive/dSYMs'));
      expect(stepBody, isNot(contains('--include-sources')));
    });

    test("the Android step's ProGuard upload is inside a mapping.txt "
        'existence conditional', () {
      final contents =
          stripHashComments(readRepoFile(_androidWorkflowPath));
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
      final gradle = readRepoFile(_gradlePath);
      expect(gradle, contains('io.sentry:sentry-native-ndk'));
      expect(gradle, contains('prefab = true'));
    });

    test('the shared script exists and is referenced from both workflows',
        () {
      readRepoFile(_sharedScriptPath); // asserts existence/non-empty
      for (final path in [_iosWorkflowPath, _androidWorkflowPath]) {
        expect(readRepoFile(path), contains(_sharedScriptPath),
            reason: path);
      }
    });
  });
}
