/// Storage-abstraction boundary guard (issue #551 problem 1): a production
/// type outside `lib/data/db/` — the storage implementation itself — and
/// the composition root (`lib/composition/`) must not name the concrete
/// `LunarLogStorage`. Consumers depend on the role interfaces in
/// `lib/data/db/storage_roles.dart` instead, so a fake can stand in for
/// storage and the god class can keep being split without a ripple.
///
/// Enforced by walking `lib/` with `dart:io`, stripping comments first so a
/// doc comment that merely *mentions* `LunarLogStorage` is not a violation
/// (several already do, e.g. `remote_rows.dart`). No lint plugin, no new
/// dependency.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Literal directories/files that are allowed to name the concrete class:
/// the storage implementation itself (`lib/data/db/`) and the composition
/// root that constructs it (`lib/composition/`).
const List<String> _allowedPrefixes = <String>[
  'lib/data/db/',
  'lib/composition/',
];

final RegExp _identifier = RegExp(r'\bLunarLogStorage\b');

/// Strips `//` line comments and `/* ... */` block comments, preserving
/// newlines so a line index stays meaningful. Deliberately does not try to
/// understand string literals: in `lib/` the only occurrences of the bare
/// identifier are type references or prose, never string payloads.
String stripComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (char == '/' && next == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      continue;
    }
    if (char == '/' && next == '*') {
      i += 2;
      while (i < source.length &&
          !(source[i] == '*' && i + 1 < source.length && source[i + 1] == '/')) {
        if (source[i] == '\n') out.write('\n');
        i++;
      }
      i += 2;
      continue;
    }
    out.write(char);
    i++;
  }
  return out.toString();
}

/// Whether [contents] of [filePath] names the concrete `LunarLogStorage`
/// and [filePath] is not one of the allowed implementation/root files.
bool namesConcreteStorage(String contents, String filePath) {
  final posix = filePath.replaceAll(r'\', '/');
  if (_allowedPrefixes.any(posix.startsWith)) return false;
  return _identifier.hasMatch(stripComments(contents));
}

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('storage abstraction boundary (#551)', () {
    test('only lib/data/db and lib/composition name LunarLogStorage', () {
      final files = _dartFilesUnder('lib');
      expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

      final offenders = [
        for (final file in files)
          if (namesConcreteStorage(
              file.readAsStringSync(), file.path.replaceAll(r'\', '/')))
            file.path.replaceAll(r'\', '/'),
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'only lib/data/db (the implementation) and lib/composition '
            '(the root that builds it) may name LunarLogStorage; consumers '
            'must use the role interfaces in storage_roles.dart, but these '
            'files do not:\n${offenders.join('\n')}',
      );
    });

    // Gives the guard teeth: a detector that silently stopped matching
    // would leave the scan passing on a clean tree and catching nothing on
    // a dirty one.
    test('detects the forms a concrete-storage reference can take', () {
      const consumer = 'lib/data/repositories/drift_profiles_repository.dart';
      expect(
          namesConcreteStorage(
              'final LunarLogStorage _storage;', consumer),
          isTrue,
          reason: 'a field typed against the concrete class must flag');
      expect(
          namesConcreteStorage(
              'required LunarLogStorage storage,', consumer),
          isTrue,
          reason: 'a constructor parameter typed against it must flag');
      expect(
          namesConcreteStorage(
              '// ignore: avoid_LunarLogStorage\nfinal LunarLogStorage s;',
              consumer),
          isTrue,
          reason: 'a reference after a line comment must still flag');

      // Allowed locations.
      expect(
          namesConcreteStorage('final LunarLogStorage _storage;',
              'lib/data/db/storage.dart'),
          isFalse,
          reason: 'the implementation file may name it');
      expect(
          namesConcreteStorage('required LunarLogStorage storage,',
              'lib/composition/app_dependencies.dart'),
          isFalse,
          reason: 'the composition root may name it');

      // Prose is not a dependency.
      expect(
          namesConcreteStorage(
              '/// Moved verbatim from `LunarLogStorage` (#434).', consumer),
          isFalse,
          reason: 'a line-comment mention must not flag');
      expect(
          namesConcreteStorage(
              '/* LunarLogStorage used to live here. */\nfinal int x = 1;',
              consumer),
          isFalse,
          reason: 'a block-comment mention must not flag');
      expect(
          namesConcreteStorage('final LunarLogStorageX x;', consumer),
          isFalse,
          reason: 'a longer identifier that merely starts with it must not flag');
    });
  });
}
