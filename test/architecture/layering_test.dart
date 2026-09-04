/// KTD2 layering guard (R4): `lib/data` must never depend on `lib/ui`, and
/// `lib/domain` must stay pure Dart (no `package:flutter`). Enforced by
/// walking the source tree with `dart:io` — no lint plugin, no new
/// dependency.
///
/// Detection matches whole `import`/`export` **directives** and inspects
/// every quoted URI inside each one, rather than regex-matching raw file
/// text. That matters three ways, all of which a simpler
/// `import '...'`-prefixed pattern gets wrong:
///
/// * `export 'package:lunarlog/ui/...';` creates the same dependency edge
///   as an import, and `lib/data` already uses `export` today (see
///   `lib/data/db/storage.dart`).
/// * A conditional directive puts its URI after `if (...)`, not directly
///   after the keyword — `lib/data/db/platform_factory.dart` and
///   `lib/data/gate/gate.dart` both use that idiom.
/// * Relative URIs are resolved against the importing file, so an escape
///   is caught at any depth (`../ui/x.dart` as well as `../../ui/x.dart`).
///
/// Anchoring directives at line start also keeps a doc comment that merely
/// *mentions* a forbidden path from tripping the guard.
///
/// The scan cases assert a non-zero scanned-file count so a wrong path
/// cannot make them vacuously pass, and `detects the forms a layering
/// violation can take` gives the detector its own falsification coverage.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A whole `import`/`export` directive, from the keyword to its `;`.
/// Anchored at line start so prose mentioning a directive is not matched.
final _directive = RegExp(
  r'''^\s*(?:import|export)\s+[^;]*;''',
  multiLine: true,
);

/// Every quoted URI inside one directive — covers each conditional branch.
final _quotedUri = RegExp(r'''['"]([^'"]+)['"]''');

/// URIs a directive in [filePath] refers to, relative ones resolved to a
/// repo-relative posix path.
Iterable<String> _referencedUris(String contents, String filePath) sync* {
  for (final directive in _directive.allMatches(contents)) {
    for (final uri in _quotedUri.allMatches(directive.group(0)!)) {
      final target = uri.group(1)!;
      yield target.startsWith('.') ? _resolve(filePath, target) : target;
    }
  }
}

/// Resolves [uri] against [fromFile]'s directory, collapsing `.` and `..`.
String _resolve(String fromFile, String uri) {
  final parts = fromFile.replaceAll(r'\', '/').split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment.isEmpty || segment == '.') continue;
    if (segment == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

/// Whether [contents] of [filePath] depends on the `lib/ui` layer.
bool dependsOnUiLayer(String contents, String filePath) =>
    _referencedUris(contents, filePath).any((uri) =>
        uri.startsWith('package:lunarlog/ui/') ||
        uri == 'lib/ui' ||
        uri.startsWith('lib/ui/'));

/// Whether [contents] depends on Flutter.
bool dependsOnFlutter(String contents, String filePath) =>
    _referencedUris(contents, filePath)
        .any((uri) => uri.startsWith('package:flutter'));

List<File> _dartFilesUnder(String path, {bool excludeGenerated = false}) =>
    Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !excludeGenerated || !f.path.endsWith('.g.dart'))
        .toList();

void _expectNoOffenders(
  String root,
  bool Function(String contents, String path) violates,
  String rule, {
  bool excludeGenerated = false,
}) {
  final files = _dartFilesUnder(root, excludeGenerated: excludeGenerated);
  expect(files, isNotEmpty,
      reason: 'scanned zero files under $root — check the path');

  final offenders = [
    for (final file in files)
      if (violates(file.readAsStringSync(), file.path)) file.path,
  ];
  expect(offenders, isEmpty,
      reason: '$rule, but these files do:\n${offenders.join('\n')}');
}

void main() {
  group('layering (KTD2)', () {
    test('no lib/data file depends on lib/ui', () {
      _expectNoOffenders('lib/data', dependsOnUiLayer,
          'lib/data must not depend on lib/ui',
          excludeGenerated: true);
    });

    test('no lib/domain file depends on package:flutter', () {
      _expectNoOffenders(
          'lib/domain', dependsOnFlutter, 'lib/domain must stay pure Dart');
    });

    // Gives the guard above its own teeth: without this, a detector that
    // silently stopped matching would leave both scans passing on a clean
    // tree and catch nothing on a dirty one.
    test('detects the forms a layering violation can take', () {
      const path = 'lib/data/notifications/reminder_coordinator.dart';
      // Relative escapes are depth-sensitive, which is the point of
      // resolving them: `../ui/` reaches lib/ui only from a file sitting
      // directly in lib/data, while a file one level deeper needs
      // `../../ui/`. A regex on the literal text cannot tell those apart.
      const violations = {
        'package import':
            "import 'package:lunarlog/ui/overview/state.dart';",
        'package export':
            "export 'package:lunarlog/ui/overview/state.dart';",
        'nested relative': "import '../../ui/overview/state.dart';",
        'conditional import branch':
            "import 'stub.dart'\n    if (dart.library.ffi) "
                "'package:lunarlog/ui/overview/state.dart';",
        'conditional export branch':
            "export 'stub.dart'\n    if (dart.library.ffi) "
                "'../../ui/overview/state.dart';",
      };
      violations.forEach((form, source) {
        expect(dependsOnUiLayer(source, path), isTrue,
            reason: 'should flag a $form');
      });

      // The shortest escape, from a file directly under lib/data.
      expect(
          dependsOnUiLayer(
              "import '../ui/overview/state.dart';", 'lib/data/probe.dart'),
          isTrue,
          reason: 'should flag a sibling-level relative escape');
      expect(
          dependsOnUiLayer(
              "import '../ui/overview/state.dart';", path),
          isFalse,
          reason: 'the same text one level deeper resolves inside lib/data');

      const allowed = {
        'a sibling directory that merely starts with "ui"':
            "import '../ui_helpers/format.dart';",
        'a domain import': "import 'package:lunarlog/domain/tags.dart';",
        'a prose mention inside a doc comment':
            "/// Was `import 'package:lunarlog/ui/overview/state.dart';`\n"
                "/// before #44 moved the enum into lib/domain.",
      };
      allowed.forEach((form, source) {
        expect(dependsOnUiLayer(source, path), isFalse,
            reason: 'should not flag $form');
      });

      expect(
          dependsOnFlutter(
              "export 'stub.dart'\n    if (dart.library.ui) "
                  "'package:flutter/widgets.dart';",
              'lib/domain/models/profile.dart'),
          isTrue,
          reason: 'the domain guard must cover conditional branches too');
    });
  });
}
