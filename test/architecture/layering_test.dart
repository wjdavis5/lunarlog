/// KTD2 layering guard (R4): `lib/data` must never import `lib/ui`, and
/// `lib/domain` must stay pure Dart (no `package:flutter`). Enforced by
/// walking the source tree with `dart:io` and regex-matching import lines —
/// no lint plugin, no new dependency. Both cases assert a non-zero scanned
/// file count so a wrong path or bad glob cannot make the test vacuously
/// pass.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Matches the package-form import of the ui layer, e.g.
/// `import 'package:lunarlog/ui/overview/overview_panel.dart';`.
final _packageUiImport = RegExp(r"""import\s+['"]package:lunarlog/ui/""");

/// Matches a relative import that escapes `lib/data` into `lib/ui`, e.g.
/// `import '../../ui/overview/notification_availability.dart';`. This form
/// matters because the repo already mixes import styles (see
/// `lib/data/repositories/drift_profiles_repository.dart`'s
/// `import 'mappers.dart';`), so a package-prefix-only check would let the
/// exact cycle R1 removes come back green.
final _relativeUiImport = RegExp(r"""import\s+['"]\.\./[^'"]*/ui/""");

final _flutterImport = RegExp(r"""import\s+['"]package:flutter""");

List<File> _dartFilesUnder(String path, {bool excludeGenerated = false}) {
  final files = Directory(path)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !excludeGenerated || !f.path.endsWith('.g.dart'))
      .toList();
  return files;
}

void main() {
  group('layering (KTD2)', () {
    test('no lib/data file imports lib/ui', () {
      final files = _dartFilesUnder('lib/data', excludeGenerated: true);
      expect(files, isNotEmpty, reason: 'scanned zero files under lib/data — check the path/glob');

      final offenders = <String>[];
      for (final file in files) {
        final contents = file.readAsStringSync();
        if (_packageUiImport.hasMatch(contents) || _relativeUiImport.hasMatch(contents)) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'lib/data must not import lib/ui, but these files do:\n${offenders.join('\n')}',
      );
    });

    test('no lib/domain file imports package:flutter', () {
      final files = _dartFilesUnder('lib/domain');
      expect(files, isNotEmpty, reason: 'scanned zero files under lib/domain — check the path/glob');

      final offenders = <String>[];
      for (final file in files) {
        final contents = file.readAsStringSync();
        if (_flutterImport.hasMatch(contents)) {
          offenders.add(file.path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'lib/domain must stay pure Dart, but these files import package:flutter:\n${offenders.join('\n')}',
      );
    });
  });
}
