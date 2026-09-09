/// Issue #153 P0 review fix: [SettingsKeys.healthStoreProfileId] must be
/// read (or written) only inside `lib/domain/health/` — [HealthSyncBinding]
/// is documented as its sole reader/writer, and every other call site must
/// go through [HealthSyncBinding.canBind]/[HealthSyncBinding.canWrite]
/// rather than constructing the check's inputs itself. Enforced the same
/// way `test/architecture/layering_test.dart` enforces its own import
/// discipline: walking the source tree with `dart:io`, no lint plugin, no
/// new dependency.
///
/// Doc-comment mentions (every dartdoc `[SettingsKeys.healthStoreProfileId]`
/// cross-reference outside `lib/domain/health/` is exactly that — a
/// pointer to the canonical definition, not a read) are stripped before
/// scanning, mirroring `layering_test.dart`'s own care that a prose
/// mention must not trip the guard. Only `///`-style doc comments are
/// stripped, since that is the only doc-comment style this codebase uses
/// (verified by the scan itself finding files that use it).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The qualified reference form every real read/write uses.
final _reference = RegExp(r'SettingsKeys\.healthStoreProfileId');

/// Strips `///` doc-comment lines (leading whitespace allowed) so a
/// dartdoc cross-reference to the constant doesn't count as a read.
String _stripDocComments(String contents) => contents
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('///'))
    .join('\n');

/// Whether [contents] of a file under `lib/` (not `lib/domain/health/`)
/// references the constant outside a doc comment.
bool _referencesOutsideDocComment(String contents) =>
    _reference.hasMatch(_stripDocComments(contents));

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('.g.dart'))
    .toList();

bool _isUnderHealthDomain(String path) =>
    path.replaceAll(r'\', '/').contains('lib/domain/health/');

void main() {
  test('SettingsKeys.healthStoreProfileId is referenced only inside '
      'lib/domain/health/', () {
    final files = _dartFilesUnder('lib');
    expect(files, isNotEmpty,
        reason: 'scanned zero files under lib — check the path');

    final offenders = [
      for (final file in files)
        if (!_isUnderHealthDomain(file.path) &&
            _referencesOutsideDocComment(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty,
        reason: 'SettingsKeys.healthStoreProfileId must be read only '
            'inside lib/domain/health/ (via HealthSyncBinding), but these '
            'files reference it directly:\n${offenders.join('\n')}');
  });

  test('the guard finds at least the real reads inside '
      'lib/domain/health/ (falsification coverage — a detector matching '
      'nothing everywhere is not proof of a clean tree)', () {
    final files = _dartFilesUnder('lib')
        .where((f) => _isUnderHealthDomain(f.path))
        .toList();
    final matches = files
        .where((f) => _referencesOutsideDocComment(f.readAsStringSync()))
        .toList();
    expect(matches, isNotEmpty,
        reason: 'expected at least health_sync_binding.dart to reference '
            'SettingsKeys.healthStoreProfileId in real code');
  });

  test('doc-comment mentions do not trip the guard', () {
    const source = '''
/// This screen only ever changes the device-local
/// [SettingsKeys.healthStoreProfileId] setting via HealthSyncBinding.
library;

class NotAReader {}
''';
    expect(_referencesOutsideDocComment(source), isFalse,
        reason: 'a doc-comment cross-reference must not count as a read');
  });

  test('a real (non-comment) reference is still detected', () {
    const source = '''
import 'package:lunarlog/domain/repositories/settings_store.dart';

void sneaky(SettingsStore s) => s.get(SettingsKeys.healthStoreProfileId);
''';
    expect(_referencesOutsideDocComment(source), isTrue,
        reason: 'a real reference outside a doc comment must be caught');
  });
}
