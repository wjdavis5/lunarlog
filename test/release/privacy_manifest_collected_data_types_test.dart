/// Collected-data-type declaration guard (issue #1065, extending the
/// issue #254 non-regression check that used to live only in
/// `privacy_manifest_required_reason_test.dart`).
///
/// Every category of data this app sends off-device must be declared in
/// `ios/Runner/PrivacyInfo.xcprivacy`'s `NSPrivacyCollectedDataTypes`
/// array: the account email, the synced cycle/symptom data, crash reports,
/// the push registration token, and the optional support-ticket content
/// (message, diagnostics, screenshot). Issue #1065 found the last two
/// groups missing even though `PRIVACY.md` already disclosed them, so
/// silence here is exactly the failure mode this test closes -- a future
/// omission fails CI instead of shipping an inconsistent privacy manifest.
///
/// Unlike `privacy_manifest_required_reason_test.dart`'s text scan, this
/// parses the manifest's dictionary structure for the relevant array --
/// enough to read each entry's data type, linked flag, tracking flag, and
/// purposes together, rather than matching loose substrings that a
/// commented-out or unrelated line could satisfy. It is still a focused
/// reader for the narrow plist subset this file uses (dict/array/string/
/// true/false), not a general plist parser; that tradeoff keeps the test
/// dependency-free, matching `export_compliance_test.dart`'s posture.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _manifestPath = 'ios/Runner/PrivacyInfo.xcprivacy';
const _widgetManifestPath = 'ios/LunarLogWidget/PrivacyInfo.xcprivacy';

/// One declared collected-data-type entry.
typedef _Entry = ({bool? linked, bool? tracking, List<String> purposes});

/// Returns the inner XML of the first balanced [open]...[close] block at or
/// after [from], or null. Handles nesting of the same pair (an array of
/// dicts, a dict's nested purpose array).
String? _balanced(String xml, String open, String close, int from) {
  final start = xml.indexOf(open, from);
  if (start < 0) return null;
  var depth = 0;
  var i = start;
  while (i < xml.length) {
    if (xml.startsWith(open, i)) {
      depth++;
      i += open.length;
    } else if (xml.startsWith(close, i)) {
      depth--;
      if (depth == 0) return xml.substring(start + open.length, i);
      i += close.length;
    } else {
      i++;
    }
  }
  return null;
}

/// Every top-level `<dict>...</dict>` block inside [arrayInner].
List<String> _topLevelDictBlocks(String arrayInner) {
  final blocks = <String>[];
  var cursor = 0;
  while (true) {
    final block = _balanced(arrayInner, '<dict>', '</dict>', cursor);
    if (block == null) break;
    blocks.add(block);
    final start = arrayInner.indexOf('<dict>', cursor);
    cursor = start + '<dict>'.length + block.length + '</dict>'.length;
  }
  return blocks;
}

String? _stringFor(String dict, String key) {
  final keyIndex = dict.indexOf('<key>$key</key>');
  if (keyIndex < 0) return null;
  final open = dict.indexOf('<string>', keyIndex);
  if (open < 0) return null;
  final close = dict.indexOf('</string>', open);
  if (close < 0) return null;
  return dict.substring(open + '<string>'.length, close).trim();
}

bool? _boolFor(String dict, String key) {
  final keyIndex = dict.indexOf('<key>$key</key>');
  if (keyIndex < 0) return null;
  final rest = dict.substring(keyIndex);
  final trueIndex = rest.indexOf('<true/>');
  final falseIndex = rest.indexOf('<false/>');
  if (trueIndex < 0 && falseIndex < 0) return null;
  if (falseIndex < 0) return true;
  if (trueIndex < 0) return false;
  return trueIndex < falseIndex;
}

List<String> _stringArrayFor(String dict, String key) {
  final keyIndex = dict.indexOf('<key>$key</key>');
  if (keyIndex < 0) return const [];
  final array = _balanced(dict, '<array>', '</array>', keyIndex);
  if (array == null) return const [];
  return RegExp(
    r'<string>(.*?)</string>',
    dotAll: true,
  ).allMatches(array).map((m) => m.group(1)!.trim()).toList();
}

/// Parses `NSPrivacyCollectedDataTypes` into a data-type -> entry map.
Map<String, _Entry> _parseCollectedDataTypes(String manifest) {
  final keyIndex = manifest.indexOf('<key>NSPrivacyCollectedDataTypes</key>');
  expect(
    keyIndex,
    greaterThanOrEqualTo(0),
    reason: 'the manifest has no NSPrivacyCollectedDataTypes key',
  );
  final array = _balanced(manifest, '<array>', '</array>', keyIndex);
  expect(
    array,
    isNotNull,
    reason:
        'NSPrivacyCollectedDataTypes is not followed by a balanced '
        '<array>...</array>',
  );

  final entries = <String, _Entry>{};
  for (final dict in _topLevelDictBlocks(array!)) {
    final type = _stringFor(dict, 'NSPrivacyCollectedDataType');
    if (type == null) continue;
    entries[type] = (
      linked: _boolFor(dict, 'NSPrivacyCollectedDataTypeLinked'),
      tracking: _boolFor(dict, 'NSPrivacyCollectedDataTypeTracking'),
      purposes: _stringArrayFor(dict, 'NSPrivacyCollectedDataTypePurposes'),
    );
  }
  return entries;
}

void main() {
  group('PrivacyInfo.xcprivacy collected-data-type declarations (issue '
      '#1065)', () {
    late String manifest;
    late Map<String, _Entry> declared;

    setUpAll(() {
      manifest = readRepoFile(_manifestPath);
      declared = _parseCollectedDataTypes(manifest);
    });

    // The complete set of categories the codebase sends off-device. When a
    // new off-device data type or recipient ships, add it here (and to the
    // manifest, PRIVACY.md Section 9, and docs/ops/ios-privacy-manifest.md)
    // in the same change -- that review-forcing is the point of the exact-set
    // assertion below.
    const expectedTypes = <String, bool>{
      // Issue #254: synced account/cycle data and anonymized crash reports.
      'NSPrivacyCollectedDataTypeEmailAddress': true,
      'NSPrivacyCollectedDataTypeHealth': true,
      'NSPrivacyCollectedDataTypeCrashData': false,
      // Issue #1065: the push registration token (register_push_device ->
      // push_devices; FCM/APNs deliver it) and the optional support ticket.
      'NSPrivacyCollectedDataTypeDeviceID': true,
      'NSPrivacyCollectedDataTypeCustomerSupport': true,
      'NSPrivacyCollectedDataTypePhotosorVideos': true,
      'NSPrivacyCollectedDataTypeOtherDiagnosticData': true,
    };

    test('declares exactly the off-device data types the app sends', () {
      expect(
        declared.keys.toSet(),
        expectedTypes.keys.toSet(),
        reason:
            '$_manifestPath\'s collected-data-types set changed. If a '
            'data type was added, confirm it is genuinely collected '
            'off-device, declare the matching PRIVACY.md Section 9 entry, '
            'and add it to expectedTypes; if one was removed, update the '
            'manifest and this test together.',
      );
    });

    for (final entry in expectedTypes.entries) {
      test('${entry.key} is linked=${entry.value}, not tracking, and used '
          'for App Functionality', () {
        final value = declared[entry.key];
        expect(value, isNotNull, reason: 'missing ${entry.key}');
        expect(value!.linked, entry.value, reason: '${entry.key} linked flag');
        expect(
          value.tracking,
          isFalse,
          reason: '${entry.key} must never be used for tracking',
        );
        expect(
          value.purposes,
          contains('NSPrivacyCollectedDataTypePurposeAppFunctionality'),
          reason: '${entry.key} purposes',
        );
      });
    }

    test('NSPrivacyTracking is false', () {
      final keyIndex = manifest.indexOf('<key>NSPrivacyTracking</key>');
      expect(keyIndex, greaterThanOrEqualTo(0));
      expect(
        manifest.substring(keyIndex).indexOf('<false/>'),
        lessThan(manifest.substring(keyIndex).indexOf('<true/>')),
        reason: 'the manifest must stay tracking-free (PRIVACY.md Section 9)',
      );
    });

    test('the home-screen widget extension still collects nothing '
        '(issue #141 / issue #1065)', () {
      final widgetManifest = readRepoFile(_widgetManifestPath);
      final keyIndex = widgetManifest.indexOf(
        '<key>NSPrivacyCollectedDataTypes</key>',
      );
      expect(
        keyIndex,
        greaterThanOrEqualTo(0),
        reason:
            'the widget manifest must keep declaring its (empty) '
            'collected-data-types array',
      );
      expect(
        RegExp(r'<array\s*/>|<array>\s*</array>')
            .firstMatch(widgetManifest.substring(keyIndex)),
        isNotNull,
        reason:
            'the widget renders on-device data and transmits nothing, so '
            'its collected-data-types array must stay empty -- if it is not, '
            'the widget grew an off-device path that needs declaring here and '
            'in PRIVACY.md',
      );
    });

    // Falsification coverage for the reader itself, mirroring
    // export_compliance_test.dart's "detects the forms a disagreement can
    // take" test.
    test('detects a wrong tracking flag', () {
      const tracking = '''
<key>NSPrivacyCollectedDataTypes</key>
<array>
	<dict>
		<key>NSPrivacyCollectedDataType</key>
		<string>NSPrivacyCollectedDataTypeDeviceID</string>
		<key>NSPrivacyCollectedDataTypeLinked</key>
		<true/>
		<key>NSPrivacyCollectedDataTypeTracking</key>
		<true/>
		<key>NSPrivacyCollectedDataTypePurposes</key>
		<array>
			<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
		</array>
	</dict>
</array>''';
      final parsed = _parseCollectedDataTypes(tracking);
      expect(parsed['NSPrivacyCollectedDataTypeDeviceID']!.tracking, isTrue);
      expect(parsed['NSPrivacyCollectedDataTypeDeviceID']!.linked, isTrue);
      expect(parsed['NSPrivacyCollectedDataTypeDeviceID']!.purposes, [
        'NSPrivacyCollectedDataTypePurposeAppFunctionality',
      ]);
    });

    test('the reader sees nothing when a dict omits the data-type key', () {
      expect(_parseCollectedDataTypes(_dictMissingDataType), isEmpty);
    });
  });
}

const _dictMissingDataType = '''
<key>NSPrivacyCollectedDataTypes</key>
<array>
	<dict>
		<key>NSPrivacyCollectedDataTypeLinked</key>
		<true/>
	</dict>
</array>''';
