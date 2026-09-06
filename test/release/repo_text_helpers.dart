/// Shared helpers for release-guard tests that read a repo file as text and
/// assert an invariant on its content (`export_compliance_test.dart`,
/// `sentry_symbols_test.dart`). Extracted rather than copy-pasted so a fix
/// to either helper (a CRLF edge case, a nested-comment case) lands once.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reads [path] (relative to the repo root, where `flutter test` runs) and
/// fails with an actionable reason if it is missing or empty.
String readRepoFile(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'expected to find $path at the repo root '
          '(flutter test runs with CWD at the repo root)');
  final contents = file.readAsStringSync();
  expect(contents, isNotEmpty, reason: '$path exists but is empty');
  return contents;
}

/// Strips full-line `#`/YAML-style comments so a commented-out declaration
/// cannot satisfy a text-matching assertion.
String stripHashComments(String text) => text
    .split('\n')
    .where((line) => !RegExp(r'^\s*#').hasMatch(line))
    .join('\n');
