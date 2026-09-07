/// Export-compliance guard (KTD1/KTD2, issue #48; reversed by the SQLCipher
/// removal / US-Canada-only chore): the app no longer compiles a
/// third-party at-rest cipher into the binary (`pubspec.yaml` carries no
/// `sqlite3` build hook), so `ios/Runner/Info.plist` must declare
/// `ITSAppUsesNonExemptEncryption = false`, and `fastlane/Fastfile`'s
/// submission lane must agree rather than contradict it. This test fails if
/// the declaration and the sqlcipher-hook fact ever disagree, in either
/// direction: the hook comes back while the declaration stays false
/// (under-declaration -- the App Store Connect submission fact goes false),
/// or the declaration flips back to true with no hook present
/// (over-declaration -- still a lie about the binary).
///
/// Detection avoids two known false-positive/false-negative traps:
/// * The sqlcipher hook is detected structurally by its nested
///   `hooks: user_defines: sqlite3: source: sqlcipher` key path, with
///   `#`-comment lines stripped first, so a mention inside a comment
///   cannot satisfy the guard. A full YAML parser was judged unwarranted
///   for one test (see docs/ops/ios-export-compliance.md).
/// * The Info.plist key is matched together with its following `<true/>`
///   or `<false/>` value element, not the bare key name, so a `<true/>`
///   value cannot pass by having the right key nearby. XML comments are
///   stripped first, so a commented-out declaration -- or a commented
///   `<false/>` sitting above a live `<true/>` -- cannot be mistaken for a
///   live `false`.
///
/// R7 (no compliance code without one in hand): both files are also
/// scanned for `ITSEncryptionExportComplianceCode`, which must never
/// appear until the operator has actually obtained a code.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

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
/// so the bare key name alone cannot satisfy a "declares false" check.
final _exportComplianceKeyPattern = RegExp(
  r'<key>\s*ITSAppUsesNonExemptEncryption\s*</key>\s*<(true|false)\s*/>',
);

/// Matches an XML comment (`<!-- ... -->`), including multi-line ones, so it
/// can be stripped before the key/value pattern runs. Without this, a
/// commented-out declaration -- or worse, a commented `<false/>` sitting
/// directly above a live `<true/>` -- would satisfy
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

bool _fastfileDeclaresEncryptionFalse(String fastfileContents) {
  final stripped = fastfileContents
      .split('\n')
      .where((line) => !RegExp(r'^\s*#').hasMatch(line))
      .join('\n');
  return _fastfileUsesEncryptionFalse.hasMatch(stripped) &&
      !_fastfileUsesEncryptionTrue.hasMatch(stripped);
}

bool _assertsComplianceCode(String contents) =>
    contents.contains('ITSEncryptionExportComplianceCode');

void main() {
  group('export compliance (KTD1/KTD2, issue #48, reversed)', () {
    test('no sqlcipher hook, and Info.plist/Fastfile agree it uses no '
        'non-exempt encryption', () {
      final pubspec = readRepoFile(_pubspecPath);
      final infoPlist = readRepoFile(_infoPlistPath);
      final fastfile = readRepoFile(_fastfilePath);

      expect(_declaresSqlcipherHook(pubspec), isFalse,
          reason: '$_pubspecPath declares the sqlcipher build hook again -- '
              'if a third-party at-rest cipher was intentionally '
              're-added, also flip the ITSAppUsesNonExemptEncryption '
              'declaration in $_infoPlistPath back to true and update the '
              'matching Fastfile answer instead of leaving a stale "false" '
              'declaration; if this is unexpected, remove the hook');

      final declared = _declaredNonExemptEncryption(infoPlist);
      expect(declared, isNotNull,
          reason: '$_infoPlistPath is missing the '
              'ITSAppUsesNonExemptEncryption key -- the answer must be '
              'explicit, not omitted (see docs/ops/ios-export-compliance.md)');
      expect(declared, isFalse,
          reason: '$_infoPlistPath declares ITSAppUsesNonExemptEncryption '
              'as true, but the app compiles no sqlcipher hook -- flip it '
              'to false rather than leave a stale non-exempt declaration');

      expect(_fastfileDeclaresEncryptionFalse(fastfile), isTrue,
          reason: '$_fastfilePath must set '
              'export_compliance_uses_encryption: false to agree with '
              '$_infoPlistPath (KTD2) -- it must not contain the true '
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
              '<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>'),
          isFalse);

      expect(
          _declaredNonExemptEncryption(
              '<key>ITSAppUsesNonExemptEncryption</key>\n\t<true/>'),
          isTrue,
          reason: 'a true value must be read as true, not matched by '
              'key name alone');

      expect(
          _declaredNonExemptEncryption('''
<!--
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
-->
'''),
          isNull,
          reason: 'a commented-out false declaration must not be read as a '
              'live false -- the key must report absent, not false');

      expect(
          _declaredNonExemptEncryption('''
<!-- <key>ITSAppUsesNonExemptEncryption</key> <false/> -->
<key>ITSAppUsesNonExemptEncryption</key>
<true/>
'''),
          isTrue,
          reason: 'a commented-out false sitting above a live true must not '
              'mask the live true');

      expect(
          _fastfileDeclaresEncryptionFalse(
              'export_compliance_uses_encryption: false,'),
          isTrue);
      expect(
          _fastfileDeclaresEncryptionFalse(
              'export_compliance_uses_encryption: true,'),
          isFalse);
      expect(
          _fastfileDeclaresEncryptionFalse(
              '# export_compliance_uses_encryption: false,\n'
              'export_compliance_uses_encryption: true,'),
          isFalse,
          reason: 'a stray commented-out false must not mask a live true');

      expect(_assertsComplianceCode('ITSEncryptionExportComplianceCode'),
          isTrue);
      expect(_assertsComplianceCode('no code mentioned here'), isFalse);
    });
  });
}
