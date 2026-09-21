/// Epic #831 (slice 1) single-seam pin for the web-sync flag: the
/// `LUNARLOG_WEB_SYNC` define is read exactly once — `AppConfig.webSyncEnabled`
/// in `lib/config.dart` — and the resolved constant is consumed through the
/// existing injection seams (`WebDevBanner`/`WebGuardrails.webSyncEnabled`,
/// `SyncStatusTile.webSyncOff`), never re-derived from the environment.
///
/// Mirrors `qa_flag_seam_test.dart` (#739) and `mfa_flag_seam_test.dart`
/// (#738) in structure: walk `lib/` with `dart:io`, strip comment lines, and
/// assert the define literal and the resolved constant appear where they are
/// supposed to. A second `String.fromEnvironment('LUNARLOG_WEB_SYNC')`
/// anywhere else would bypass the one seam that `hasSupabase` and the web
/// disclosures both read from.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The compile-time define name; `String.fromEnvironment`'s argument is the
/// one and only read of it, in `lib/config.dart`.
final _defineLiteral = RegExp(r'LUNARLOG_WEB_SYNC');

/// A code reference to the resolved constant, whitespace-tolerant.
final _seamReference = RegExp(r'\bAppConfig\s*\.\s*webSyncEnabled\b');

/// Strips `//`-comment lines (doc comments included) so prose that mentions
/// the flag or the seam is not matched — the same intent as
/// `qa_flag_seam_test.dart`.
String stripComments(String contents) => contents
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

List<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

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

  test('LUNARLOG_WEB_SYNC appears in code only in lib/config.dart', () {
    expect(_codeMatches(files, _defineLiteral), ['lib/config.dart'],
        reason: 'the define must be read once, through '
            'AppConfig.webSyncEnabled — a second read belongs in that seam');
  });

  test('AppConfig.webSyncEnabled is consumed through injection seams', () {
    // The deliberate consumer set: the web banner's two widgets resolve it as
    // a nullable-parameter default, and the sync tile as `kIsWeb &&
    // !AppConfig.webSyncEnabled`. Extending the set is fine; do it by adding
    // a new injection seam in the same idiom, not by branching on the define
    // elsewhere.
    const expectedConsumers = [
      'lib/ui/account/sync_status_tile.dart',
      'lib/ui/web/dev_banner.dart',
    ];
    final consumers = _codeMatches(files, _seamReference)
      ..remove('lib/config.dart');
    expect(consumers, unorderedEquals(expectedConsumers),
        reason: 'AppConfig.webSyncEnabled must be resolved through the '
            'injection seams above — a new consumer needs its own seam, '
            'added here deliberately');
  });

  // Gives the guard its own teeth, in qa_flag_seam_test's falsification
  // style: a detector that silently stopped matching would leave both scans
  // above passing on a clean tree and catch nothing on a dirty one.
  test('detects the violations the scans exist to catch', () {
    expect(
      _defineLiteral.hasMatch(stripComments('''
/// Docs mention LUNARLOG_WEB_SYNC harmlessly.
static const bool x = String.fromEnvironment('LUNARLOG_WEB_SYNC') == 'true';
''')),
      isTrue,
      reason: 'a code read of the define must be flaggable wherever it sits',
    );
    expect(
      _seamReference.hasMatch(
          stripComments('final bool on = AppConfig.webSyncEnabled;')),
      isTrue,
      reason: 'a direct code reference to the constant must be flaggable',
    );
    expect(
      _defineLiteral.hasMatch(stripComments(
          '/// Set LUNARLOG_WEB_SYNC=true to opt a web build into sync (#831).')),
      isFalse,
      reason: 'a doc comment mentioning the define is not a read of it',
    );
    expect(
      _seamReference.hasMatch(stripComments(
          '/// Docs say AppConfig.webSyncEnabled is the seam.')),
      isFalse,
      reason: 'a doc comment mentioning the constant is not a reference',
    );
  });
}
