/// Sentry symbol-upload workflow guard (U5; KTD10, KTD11; R15, R16, R17,
/// AE8, AE9). Mirrors `export_compliance_test.dart`'s shape: read the two
/// release workflow files as text and assert the invariants that make the
/// upload step safe to land before issue #19 provisions any secret --
/// guarded (never fails the release), checksum-verified before invoking
/// `sentry-cli`, never `curl | bash`, and never echoing a secret.
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

        setUpAll(() {
          final contents = _stripYamlComments(_readRepoFile(path));
          stepBody = _sentrySymbolStepBody(contents);
        });

        test('the guard checks all three secrets before any sentry-cli '
            'invocation appears', () {
          final guardIndex = stepBody.indexOf('SENTRY_AUTH_TOKEN');
          final cliIndex = stepBody.indexOf('sentry-cli');
          expect(guardIndex, greaterThanOrEqualTo(0));
          expect(cliIndex, greaterThan(guardIndex));

          for (final secret in [
            'SENTRY_AUTH_TOKEN',
            'SENTRY_ORG',
            'SENTRY_PROJECT',
          ]) {
            expect(stepBody, contains(secret), reason: secret);
            final secretIndex = stepBody.indexOf(secret);
            expect(secretIndex, lessThan(cliIndex),
                reason: '$secret must be checked before sentry-cli runs');
          }
        });

        test("the guard's early exit is exit 0, not exit 1", () {
          final guardBlock = stepBody.substring(
            0,
            stepBody.indexOf('sentry-cli'),
          );
          expect(guardBlock, contains('exit 0'));
          expect(guardBlock, isNot(contains('exit 1')));
        });

        test('no bare secrets.SENTRY_ interpolation appears in the run '
            'body -- secrets reach the shell only via env:', () {
          expect(_runBlockOf(stepBody), isNot(contains(r'${{ secrets.SENTRY_')));
        });

        test('no TOKEN-named variable is ever echoed', () {
          final echoTokenPattern =
              RegExp(r'echo[^\n]*TOKEN', caseSensitive: false);
          // The only permitted mention is the warning line naming the
          // secret keys by name, not their values -- assert no `echo`
          // interpolates a shell variable containing "TOKEN".
          for (final match in echoTokenPattern.allMatches(stepBody)) {
            final line = match.group(0)!;
            expect(line, isNot(contains(r'$SENTRY_AUTH_TOKEN')),
                reason: 'a line must never echo the token value: $line');
            expect(line, isNot(contains(r'${SENTRY_AUTH_TOKEN')),
                reason: 'a line must never echo the token value: $line');
          }
        });

        test('sentry-cli is installed as a pinned, checksum-verified '
            'download, never curl | bash', () {
          expect(stepBody, isNot(contains(RegExp(r'curl[^\n]*\|\s*(ba)?sh'))));
          expect(stepBody, isNot(contains(RegExp(r'wget[^\n]*\|\s*(ba)?sh'))));
          expect(
            stepBody,
            anyOf(contains('sha256sum -c'), contains('shasum -a 256 -c')),
            reason: 'expected a checksum-verification step before invoking '
                'the downloaded binary',
          );
        });

        test('the checksum verification runs before sentry-cli --version',
            () {
          final checksumIndex = stepBody.contains('sha256sum -c')
              ? stepBody.indexOf('sha256sum -c')
              : stepBody.indexOf('shasum -a 256 -c');
          final versionIndex = stepBody.indexOf('--version');
          expect(checksumIndex, greaterThanOrEqualTo(0));
          expect(versionIndex, greaterThan(checksumIndex));
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
  });
}
