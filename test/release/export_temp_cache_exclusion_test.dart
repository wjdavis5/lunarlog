/// Issue #843 release guard: the plaintext copies an export, a share, or a
/// pick can leave in an Android cache or in the protected export directory
/// must be excluded from cloud backup and device-to-device transfer, and the
/// export writers must not regress to `getTemporaryDirectory()` (the
/// weaker-protected location the issue moved them off). Read as text since
/// none of the XML compiles under `flutter test`; the actual framework path
/// resolution is a device/emulator exercise (see the PR's manual test plan).
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

const _dataExtractionRulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';
const _backupRulesPath = 'android/app/src/main/res/xml/backup_rules.xml';

/// The export temp directory, relative to `getFilesDir()` (`domain="file"`).
const _exportTempPath = 'export-tmp';

/// The plugin cache directories, relative to `getCacheDir()` (`domain="cache"`).
const _cachePaths = ['share_plus', 'image_picker', 'file_picker'];

/// The platform export writers that must never write to the unprotected temp
/// directory again (they all route through
/// `lib/data/export/export_file_share.dart`).
const _exportWriterPaths = [
  'lib/data/export/account_export_writer.dart',
  'lib/data/export/csv_export_writer.dart',
  'lib/data/export/clinical_pdf_writer.dart',
  'lib/data/export/fhir_bundle_writer.dart',
];

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
  late String dataExtractionRules;
  late String backupRules;

  setUpAll(() {
    dataExtractionRules = readRepoFile(_dataExtractionRulesPath);
    backupRules = readRepoFile(_backupRulesPath);
  });

  group('Android export/share/picker cache exclusions (issue #843)', () {
    for (final section in ['cloud-backup', 'device-transfer']) {
      test('<$section> excludes the export temp directory (file domain)', () {
        final body = _section(dataExtractionRules, section);
        expect(
          body,
          contains('<exclude domain="file" path="$_exportTempPath"/>'),
        );
      });

      test(
        '<$section> excludes each plugin cache directory (cache domain)',
        () {
          final body = _section(dataExtractionRules, section);
          for (final path in _cachePaths) {
            expect(
              body,
              contains('<exclude domain="cache" path="$path"/>'),
              reason: path,
            );
          }
        },
      );
    }

    test('the pre-API-31 backup_rules.xml carries the same exclusions', () {
      for (final path in _cachePaths) {
        expect(
          backupRules,
          contains('<exclude domain="cache" path="$path"/>'),
          reason: path,
        );
      }
      expect(
        backupRules,
        contains('<exclude domain="file" path="$_exportTempPath"/>'),
      );
    });
  });

  group('export writers use the protected directory (issue #843)', () {
    for (final path in _exportWriterPaths) {
      test('$path no longer writes to getTemporaryDirectory()', () {
        expect(
          readRepoFile(path),
          isNot(contains('getTemporaryDirectory')),
          reason:
              'export temps must live under the protected Application '
              'Support directory',
        );
      });
    }
  });
}
