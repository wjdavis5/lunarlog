/// Required-reason API declaration guard (issue #265). SQLite is bundled via
/// `package:sqlite3`'s Dart native-build hook (a precompiled `libsqlite3`
/// dynamic library downloaded from the package's GitHub releases, per
/// `hook/build.dart`'s default `source: null` branch -- see the audit
/// recorded in `ios/Runner/PrivacyInfo.xcprivacy`'s own comment and
/// docs/ops/ios-privacy-manifest.md) with no privacy manifest of its own, so
/// the required-reason APIs it and the app's own Swift code call must be
/// declared in Runner's manifest instead of assumed covered by a plugin's
/// CocoaPod. This is a structural/text guard, not a full plist parser --
/// same tradeoff `export_compliance_test.dart`'s header documents for its
/// own detectors, justified here because this only needs to prove specific
/// category/reason-code pairs are present in the live XML text, not
/// round-trip the whole plist.
///
/// Also guards against regressing issue #254's landed Health/Email
/// Address/Crash Data collected-data-type declarations, since this file is
/// the same one #254 touched.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _manifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';

/// Matches an `NSPrivacyAccessedAPIType`/`NSPrivacyAccessedAPITypeReasons`
/// dict pair for [category], capturing the reasons array's raw contents, so
/// a category declared with the wrong reason code (or no reasons at all)
/// fails distinctly from the category being entirely absent.
RegExp _accessedApiTypeBlock(String category) => RegExp(
      '<key>NSPrivacyAccessedAPIType</key>\\s*'
      '<string>$category</string>\\s*'
      '<key>NSPrivacyAccessedAPITypeReasons</key>\\s*'
      '<array>(.*?)</array>',
      dotAll: true,
    );

bool _declaresReason(String manifest, String category, String reasonCode) {
  final match = _accessedApiTypeBlock(category).firstMatch(manifest);
  if (match == null) return false;
  final reasonsBlock = match.group(1)!;
  return RegExp('<string>\\s*$reasonCode\\s*</string>')
      .hasMatch(reasonsBlock);
}

void main() {
  group('PrivacyInfo.xcprivacy required-reason API declarations (issue '
      '#265)', () {
    late String manifest;

    setUpAll(() {
      manifest = readRepoFile(_manifestPath);
    });

    test('declares File Timestamp with reason C617.1 (SQLite\'s bundled '
        'libsqlite3 dylib calls fstat() via its unix VFS)', () {
      expect(
        _declaresReason(
            manifest, 'NSPrivacyAccessedAPICategoryFileTimestamp', 'C617.1'),
        isTrue,
        reason: '$_manifestPath is missing the File Timestamp / C617.1 '
            'declaration -- see the manifest\'s own comment and '
            'docs/ops/ios-privacy-manifest.md for the SQLite audit this '
            'covers',
      );
    });

    test('declares User Defaults with reason CA92.1 (AppDelegate.swift\'s '
        'HealthKitChannelHandler reads/writes UserDefaults.standard '
        'directly)', () {
      expect(
        _declaresReason(
            manifest, 'NSPrivacyAccessedAPICategoryUserDefaults', 'CA92.1'),
        isTrue,
        reason: '$_manifestPath is missing the User Defaults / CA92.1 '
            'declaration -- see the manifest\'s own comment and '
            'docs/ops/ios-privacy-manifest.md for the AppDelegate.swift '
            'audit this covers',
      );
    });

    test(
        'declares no other required-reason category -- audited and found '
        'not applicable (System Boot Time, Disk Space, Active Keyboards); '
        'a new category appearing here without updating the manifest\'s '
        'own comment and docs/ops/ios-privacy-manifest.md is exactly the '
        'kind of silent drift issue #265 closed', () {
      for (final category in [
        'NSPrivacyAccessedAPICategorySystemBootTime',
        'NSPrivacyAccessedAPICategoryDiskSpace',
        'NSPrivacyAccessedAPICategoryActiveKeyboards',
      ]) {
        expect(manifest, isNot(contains(category)), reason: category);
      }
    });

    test('exactly two NSPrivacyAccessedAPITypes entries are declared', () {
      final count = RegExp('<key>NSPrivacyAccessedAPIType</key>')
          .allMatches(manifest)
          .length;
      expect(count, 2,
          reason: 'expected exactly the File Timestamp and User Defaults '
              'entries this test names above; a third entry needs a test '
              'here too, not just a manifest edit');
    });

    // Non-regression coverage for issue #254's landed collected-data-type
    // declarations -- this file is the same one that work touched, and
    // nothing about issue #265's required-reason audit should have moved
    // it.
    test(
        'still declares Email Address, Health, and Crash Data as collected '
        '(issue #254 non-regression)', () {
      for (final dataType in [
        'NSPrivacyCollectedDataTypeEmailAddress',
        'NSPrivacyCollectedDataTypeHealth',
        'NSPrivacyCollectedDataTypeCrashData',
      ]) {
        expect(manifest, contains('<string>$dataType</string>'),
            reason: dataType);
      }
    });

    // Falsification coverage for the detector itself, mirroring
    // export_compliance_test.dart's own "detects the forms a disagreement
    // can take" test.
    test('detects a category present with the wrong reason code', () {
      const withWrongReason = '''
<key>NSPrivacyAccessedAPIType</key>
<string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
<key>NSPrivacyAccessedAPITypeReasons</key>
<array>
	<string>0A2A.1</string>
</array>
''';
      expect(
        _declaresReason(withWrongReason,
            'NSPrivacyAccessedAPICategoryFileTimestamp', 'C617.1'),
        isFalse,
        reason: 'a different reason code for the same category must not '
            'satisfy the check',
      );
    });

    test('detects a category entirely absent', () {
      expect(
        _declaresReason(
            '<dict></dict>', 'NSPrivacyAccessedAPICategoryUserDefaults',
            'CA92.1'),
        isFalse,
      );
    });
  });
}
