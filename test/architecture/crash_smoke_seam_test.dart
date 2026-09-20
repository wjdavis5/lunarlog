/// Issue #973's single-seam pin: `LUNARLOG_CRASH_SMOKE` is read exactly
/// once — `AppConfig.crashSmokeEnabled` in `lib/config.dart` — and that
/// constant is consumed only by the Settings → About injection seam
/// (`AboutSection.crashSmoke`, defaulting to the constant), never by a
/// second read of the define. The constant is `define && kDebugMode`, so
/// the second half of the pin is the store-build guarantee: a profile or
/// release build folds it to `false` at compile time and the trigger
/// tree-shakes away (see `test/config_test.dart`'s rule test and
/// `test/ui/crash_smoke_trigger_test.dart`'s absent/present widget test).
///
/// Mirrors `qa_flag_seam_test.dart` (#739) exactly: walk the source tree
/// with `dart:io`, no lint plugin, no new dependency. Comment lines are
/// stripped before matching, so a doc comment that merely *mentions* the
/// flag or the seam is not a read of either.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compile-time define name (#973): `bool.fromEnvironment`'s argument
/// is the one and only read of the flag.
final _defineLiteral = RegExp(r'LUNARLOG_CRASH_SMOKE');

/// A code reference to the resolved constant, whitespace-tolerant.
final _seamReference = RegExp(r'\bAppConfig\s*\.\s*crashSmokeEnabled\b');

/// Strips `//`-comment lines (doc comments included) so prose mentioning
/// the flag or the seam is not matched.
String stripComments(String contents) => contents
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// Posix-normalised paths of [files] whose code (comments stripped)
/// matches [pattern].
List<String> _codeMatches(List<File> files, RegExp pattern) => [
      for (final file in files)
        if (pattern.hasMatch(stripComments(file.readAsStringSync())))
          file.path.replaceAll(r'\', '/'),
    ];

void main() {
  final files = _libDartFiles();

  test('the lib/ tree was actually scanned', () {
    expect(files, isNotEmpty, reason: 'scanned zero files — check the path');
  });

  test('LUNARLOG_CRASH_SMOKE appears in code only in lib/config.dart', () {
    expect(_codeMatches(files, _defineLiteral), ['lib/config.dart'],
        reason: 'the define must be read once, through '
            'AppConfig.crashSmokeEnabled — a second read belongs in that '
            'seam, not beside it');
  });

  test('AppConfig.crashSmokeEnabled is consumed only by the About seam',
      () {
    final consumers = _codeMatches(files, _seamReference)
      ..remove('lib/config.dart');
    expect(
      consumers,
      unorderedEquals(['lib/ui/settings/about_section.dart']),
      reason: 'the dev-only trigger must resolve the flag through '
          'AboutSection.crashSmoke, the injection idiom the QA-build flag '
          'uses — never by branching on the constant elsewhere',
    );
  });

  // Gives the guard its own teeth, in layering_test's falsification style:
  // a detector that silently stopped matching would leave both scans above
  // passing on a clean tree and catch nothing on a dirty one.
  test('detects the violations the scans exist to catch', () {
    expect(
      _defineLiteral.hasMatch(stripComments('''
/// Docs mention LUNARLOG_CRASH_SMOKE harmlessly.
static const bool x = bool.fromEnvironment('LUNARLOG_CRASH_SMOKE');
''')),
      isTrue,
      reason: 'a code read of the define must be flaggable wherever it sits',
    );
    expect(
      _seamReference.hasMatch(
          stripComments('final bool on = AppConfig.crashSmokeEnabled;')),
      isTrue,
      reason: 'a direct code reference to the constant must be flaggable',
    );
    expect(
      _defineLiteral.hasMatch(stripComments(
          '/// Set LUNARLOG_CRASH_SMOKE=true to cut a debug smoke build (#973).')),
      isFalse,
      reason: 'a doc comment mentioning the define is not a read of it',
    );
    expect(
      _seamReference.hasMatch(stripComments(
          '/// Docs say AppConfig.crashSmokeEnabled is the seam.')),
      isFalse,
      reason: 'a doc comment mentioning the constant is not a reference',
    );
  });
}
