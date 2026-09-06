/// Export-compliance guard (KTD1/KTD2, issue #48): the app compiles
/// SQLCipher into the iOS binary (`pubspec.yaml`'s `sqlite3` build hook) and
/// therefore must declare `ITSAppUsesNonExemptEncryption = true` in
/// `ios/Runner/Info.plist`, and `fastlane/Fastfile`'s submission lane must
/// agree rather than contradict it. This test fails if the declaration and
/// the SQLCipher fact ever disagree, in either direction: the hook dropped
/// while the declaration stays (over-declaration -- still a lie about the
/// binary), or the declaration weakened/removed while the hook stays
/// (under-declaration -- the App Store Connect submission fact goes false).
///
/// Detection avoids two known false-positive/false-negative traps:
/// * The SQLCipher hook is detected structurally by its nested
///   `hooks: user_defines: sqlite3: source: sqlcipher` key path, with
///   `#`-comment lines stripped first, so a mention inside a comment
///   cannot satisfy the guard. A full YAML parser was judged unwarranted
///   for one test (see docs/ops/ios-export-compliance.md).
/// * The Info.plist key is matched together with its following `<true/>`
///   or `<false/>` value element, not the bare key name, so a `<false/>`
///   value cannot pass by having the right key nearby. XML comments are
///   stripped first, so a commented-out declaration -- or a commented
///   `<true/>` sitting above a live `<false/>` -- cannot be mistaken for a
///   live `true`.
///
/// R7 (no compliance code without one in hand): both files are also
/// scanned for `ITSEncryptionExportComplianceCode`, which must never
/// appear until the operator has actually obtained a code.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _pubspecPath = 'pubspec.yaml';
const _infoPlistPath = 'ios/Runner/Info.plist';
const _fastfilePath = 'fastlane/Fastfile';

/// The nested `hooks: user_defines: sqlite3: source: sqlcipher` key path,
/// matched in sequence after stripping `#`-comment lines so a commented-out
/// mention cannot satisfy the guard.
final _sqlcipherHookPattern = RegExp(
  r'hooks:\s*[\r\n]+\s*user_defines:\s*[\r\n]+\s*sqlite3:\s*[\r\n]+\s*source:\s*sqlcipher',
);

bool _declaresSqlcipherHook(String pubspecContents) {
  final stripped = pubspecContents
      .split('\n')
      .where((line) => !RegExp(r'^\s*#').hasMatch(line))
      .join('\n');
  return _sqlcipherHookPattern.hasMatch(stripped);
}

/// Matches the `ITSAppUsesNonExemptEncryption` key together with its
/// immediately following boolean value element, capturing `true`/`false`,
/// so the bare key name alone cannot satisfy a "declares true" check.
final _exportComplianceKeyPattern = RegExp(
  r'<key>\s*ITSAppUsesNonExemptEncryption\s*</key>\s*<(true|false)\s*/>',
);

/// Matches an XML comment (`<!-- ... -->`), including multi-line ones, so it
/// can be stripped before the key/value pattern runs. Without this, a
/// commented-out declaration -- or worse, a commented `<true/>` sitting
/// directly above a live `<false/>` -- would satisfy
/// [_exportComplianceKeyPattern], because plain regex matching has no notion
/// of XML comments.
final _xmlCommentPattern = RegExp(r'<!--.*?-->', dotAll: true);

String _stripXmlComments(String xml) =>
    xml.replaceAll(_xmlCommentPattern, '');

/// `true`, `false`, or `null` if the key is absent from [infoPlistContents]
/// once XML comments are stripped.
bool? _declaredNonExemptEncryption(String infoPlistContents) {
  final stripped = _stripXmlComments(infoPlistContents);
  final match = _exportComplianceKeyPattern.firstMatch(stripped);
  if (match == null) return null;
  return match.group(1) == 'true';
}

final _fastfileUsesEncryptionTrue =
    RegExp(r'export_compliance_uses_encryption:\s*true\b');
final _fastfileUsesEncryptionFalse =
    RegExp(r'export_compliance_uses_encryption:\s*false\b');

bool _fastfileDeclaresEncryptionTrue(String fastfileContents) {
  final stripped = fastfileContents
      .split('\n')
      .where((line) => !RegExp(r'^\s*#').hasMatch(line))
      .join('\n');
  return _fastfileUsesEncryptionTrue.hasMatch(stripped) &&
      !_fastfileUsesEncryptionFalse.hasMatch(stripped);
}

bool _assertsComplianceCode(String contents) =>
    contents.contains('ITSEncryptionExportComplianceCode');

String _readRepoFile(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue,
      reason: 'expected to find $path at the repo root '
          '(flutter test runs with CWD at the repo root)');
  final contents = file.readAsStringSync();
  expect(contents, isNotEmpty, reason: '$path exists but is empty');
  return contents;
}

void main() {
  group('export compliance (KTD1/KTD2, issue #48)', () {
    test('SQLCipher hook, Info.plist, and Fastfile agree', () {
      final pubspec = _readRepoFile(_pubspecPath);
      final infoPlist = _readRepoFile(_infoPlistPath);
      final fastfile = _readRepoFile(_fastfilePath);

      expect(_declaresSqlcipherHook(pubspec), isTrue,
          reason: '$_pubspecPath no longer declares the sqlcipher build '
              'hook -- if encryption was intentionally removed, also '
              'remove the ITSAppUsesNonExemptEncryption declaration from '
              '$_infoPlistPath and the matching Fastfile answer instead of '
              'leaving a stale "true" declaration; if this is unexpected, '
              're-add the hook');

      final declared = _declaredNonExemptEncryption(infoPlist);
      expect(declared, isNotNull,
          reason: '$_infoPlistPath is missing the '
              'ITSAppUsesNonExemptEncryption key -- the app compiles in '
              'SQLCipher (AES-256 at rest) and must declare non-exempt '
              'encryption usage (see docs/ops/ios-export-compliance.md)');
      expect(declared, isTrue,
          reason: '$_infoPlistPath declares ITSAppUsesNonExemptEncryption '
              'as false, but the app compiles in SQLCipher -- flip it to '
              'true rather than make the declaration match a false '
              'convenience');

      expect(_fastfileDeclaresEncryptionTrue(fastfile), isTrue,
          reason: '$_fastfilePath must set '
              'export_compliance_uses_encryption: true to agree with '
              '$_infoPlistPath (KTD2) -- it must not contain the false '
              'form');

      expect(_assertsComplianceCode(infoPlist), isFalse,
          reason: '$_infoPlistPath asserts '
              'ITSEncryptionExportComplianceCode -- R7 forbids this until '
              'the operator has actually obtained a real code');
      expect(_assertsComplianceCode(fastfile), isFalse,
          reason: '$_fastfilePath asserts '
              'ITSEncryptionExportComplianceCode -- R7 forbids this until '
              'the operator has actually obtained a real code');
    });

    // Falsification coverage for the detectors themselves: without this, a
    // detector that silently stopped matching would leave the guard above
    // passing on a clean tree and catching nothing on a broken one.
    test('detects the forms a disagreement can take', () {
      expect(
          _declaresSqlcipherHook('''
hooks:
  user_defines:
    sqlite3:
      source: sqlcipher
'''),
          isTrue,
          reason: 'should detect the real hook shape');

      expect(
          _declaresSqlcipherHook('''
# hooks:
#   user_defines:
#     sqlite3:
#       source: sqlcipher
'''),
          isFalse,
          reason: 'a fully commented-out hook must not satisfy the guard');

      expect(
          _declaresSqlcipherHook('''
hooks:
  user_defines:
    sqlite3:
      source: sqlite3
'''),
          isFalse,
          reason: 'plain sqlite3 (no cipher) must not satisfy the guard');

      expect(_declaredNonExemptEncryption('<dict></dict>'), isNull,
          reason: 'a missing key must report null, not a false negative');

      expect(
          _declaredNonExemptEncryption(
              '<key>ITSAppUsesNonExemptEncryption</key>\n\t<true/>'),
          isTrue);

      expect(
          _declaredNonExemptEncryption(
              '<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
          isFalse,
          reason: 'a false value must be read as false, not matched by '
              'key name alone');

      expect(
          _declaredNonExemptEncryption('''
<!--
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
-->
'''),
          isNull,
          reason: 'a commented-out true declaration must not be read as a '
              'live true -- the key must report absent, not true');

      expect(
          _declaredNonExemptEncryption('''
<!-- <key>ITSAppUsesNonExemptEncryption</key> <true/> -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
'''),
          isFalse,
          reason: 'a commented-out true sitting above a live false must not '
              'mask the live false');

      expect(
          _fastfileDeclaresEncryptionTrue(
              'export_compliance_uses_encryption: true,'),
          isTrue);
      expect(
          _fastfileDeclaresEncryptionTrue(
              'export_compliance_uses_encryption: false,'),
          isFalse);
      expect(
          _fastfileDeclaresEncryptionTrue(
              '# export_compliance_uses_encryption: true,\n'
              'export_compliance_uses_encryption: false,'),
          isFalse,
          reason: 'a stray commented-out true must not mask a live false');

      expect(_assertsComplianceCode('ITSEncryptionExportComplianceCode'),
          isTrue);
      expect(_assertsComplianceCode('no code mentioned here'), isFalse);
    });
  });
}
