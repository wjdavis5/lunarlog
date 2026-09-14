/// LLA-026 (issue #608) guard: the legacy pre-#244 database lives at
/// `Context.getDir("flutter", MODE_PRIVATE)` -- Android names that directory
/// `app_flutter` and creates it as a sibling of `getFilesDir()`, at the
/// app's private-data root (`lib/startup/startup_native.dart`'s
/// `_legacyDatabaseFile()`, via `getApplicationDocumentsDirectory()`). That
/// root is the `domain="root"` scope in both the API 31+
/// `data_extraction_rules.xml` schema and the pre-31 `full-backup-content`
/// schema (`backup_rules.xml`) -- *not* `domain="file"`, which only reaches
/// `getFilesDir()` itself (where the live `lunarlog.db` lives, already
/// excluded). Without a `root`-domain exclude for `app_flutter/...`, a
/// manufacturer device-to-device transfer can still copy the household's
/// pre-migration cycle history even though `android:allowBackup="false"` and
/// the live database's own exclusion are both in place. Read as text
/// (mirrors `health_connect_manifest_test.dart`'s shape) since none of this
/// compiles or runs under `flutter test`; a real API 31+ device/emulator D2D
/// run is the only way to exercise the framework's actual path resolution --
/// see this PR's manual test plan.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _dataExtractionRulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';
const _backupRulesPath = 'android/app/src/main/res/xml/backup_rules.xml';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _startupNativePath = 'lib/startup/startup_native.dart';

/// The legacy database and its SQLite sidecars, relative to the `root`
/// domain (the app's private-data directory, containing `app_flutter/` as a
/// sibling of `files/`) -- not the `file` domain (`getFilesDir()`), which is
/// where the live, already-excluded `lunarlog.db` lives instead.
const _legacyRootPaths = [
  'app_flutter/lunarlog.db',
  'app_flutter/lunarlog.db-wal',
  'app_flutter/lunarlog.db-shm',
  'app_flutter/lunarlog.db-journal',
];

/// Extracts the substring between a section's opening and closing tag, or
/// fails with an actionable reason if the section is missing.
String _section(String xml, String tag) {
  final open = '<$tag>';
  final close = '</$tag>';
  final start = xml.indexOf(open);
  final end = xml.indexOf(close);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing <$tag> section');
  expect(end, greaterThan(start), reason: 'missing </$tag> for <$tag>');
  return xml.substring(start + open.length, end);
}

void main() {
  group(
      'Android legacy (app_flutter) database transfer-exclusion guard '
      '(issue #608, LLA-026)', () {
    late String dataExtractionRules;
    late String backupRules;
    late String manifest;
    late String startupNative;

    setUpAll(() {
      dataExtractionRules = readRepoFile(_dataExtractionRulesPath);
      backupRules = readRepoFile(_backupRulesPath);
      manifest = readRepoFile(_manifestPath);
      startupNative = readRepoFile(_startupNativePath);
    });

    test(
        'the live database is still excluded under the file domain -- this '
        'guard adds the legacy exclusion, it does not replace the existing '
        'one', () {
      for (final xml in [dataExtractionRules]) {
        for (final section in ['cloud-backup', 'device-transfer']) {
          final body = _section(xml, section);
          expect(body, contains('<exclude domain="file" path="lunarlog.db"/>'),
              reason: section);
        }
      }
    });

    test(
        '<cloud-backup> excludes the legacy app_flutter database and every '
        '-wal/-shm/-journal sidecar under the root domain (API 31+)', () {
      final body = _section(dataExtractionRules, 'cloud-backup');
      for (final path in _legacyRootPaths) {
        expect(body, contains('<exclude domain="root" path="$path"/>'),
            reason: path);
      }
    });

    test(
        '<device-transfer> excludes the legacy app_flutter database and '
        'every -wal/-shm/-journal sidecar under the root domain (API 31+) -- '
        'this is the section manufacturer D2D transfer actually reads, '
        'independent of allowBackup', () {
      final body = _section(dataExtractionRules, 'device-transfer');
      for (final path in _legacyRootPaths) {
        expect(body, contains('<exclude domain="root" path="$path"/>'),
            reason: path);
      }
    });

    test(
        'the legacy exclude is scoped to the root domain, never mistakenly '
        'declared under the file domain -- app_flutter is a sibling of '
        'getFilesDir(), not inside it, so a file-domain rule for this path '
        'would silently match nothing', () {
      for (final path in _legacyRootPaths) {
        expect(dataExtractionRules,
            isNot(contains('<exclude domain="file" path="$path"/>')),
            reason: path);
      }
    });

    test(
        'the pre-API-31 full-backup-content file (backup_rules.xml, wired '
        'via android:fullBackupContent) declares the same four legacy '
        'root-domain excludes, kept consistent with data_extraction_rules.xml '
        'per this issue\'s "make both consistent" guidance', () {
      for (final path in _legacyRootPaths) {
        expect(backupRules, contains('<exclude domain="root" path="$path"/>'),
            reason: path);
      }
    });

    test(
        'the manifest still wires both android:fullBackupContent and '
        'android:dataExtractionRules to these two files', () {
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test(
        'startup_native.dart still names the legacy directory app_flutter '
        'gets resolved from -- getApplicationDocumentsDirectory() -- so the '
        'hard-coded "app_flutter/" prefix above stays tied to the actual '
        'code path it is guarding', () {
      expect(startupNative, contains('getApplicationDocumentsDirectory()'));
    });
  });
}
