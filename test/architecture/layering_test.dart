/// KTD2 layering guard (R4/R11): the full layer matrix — `lib/data` must
/// never depend on `lib/ui`; `lib/ui` must never depend on `lib/data`;
/// `lib/domain` must never depend on `lib/data`; and `lib/domain` must stay
/// pure Dart (no `package:flutter`). Enforced by walking the source tree
/// with `dart:io` — no lint plugin, no new dependency.
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
///   `lib/startup/gate/gate.dart` both use that idiom.
/// * Relative URIs are resolved against the importing file, so an escape
///   is caught at any depth (`../ui/x.dart` as well as `../../ui/x.dart`).
///
/// Anchoring directives at line start also keeps a doc comment that merely
/// *mentions* a forbidden path from tripping the guard.
///
/// Issue #551 (part 3) adds a second, reference-based guard beside the
/// directive one: `lib/app.dart` (a composition root that legitimately
/// imports `lib/data`) and every `lib/ui` file must not reach the raw local
/// store directly — no `LunarLogStorage` type name, no `.db.storage`
/// accessor. That detector strips comments first (see [_withoutComments]),
/// so it can be stricter about raw text without flagging prose.
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

/// Whether [contents] of [filePath] depends on the `lib/data` layer. Covers
/// the package URI and relative escapes resolved against the file's
/// directory (`../data/...`, `../../data/...`).
bool dependsOnDataLayer(String contents, String filePath) =>
    _referencedUris(contents, filePath).any((uri) =>
        uri.startsWith('package:lunarlog/data/') ||
        uri == 'lib/data' ||
        uri.startsWith('lib/data/'));

/// Whether [contents] of [filePath] depends on the composition
/// (`lib/composition/`) or bootstrap (`lib/startup/`) layer. R16: `lib/ui`
/// must never see the `AppDependencies` bundle the composition module
/// builds, nor the startup bootstrap that produces the Supabase client.
bool dependsOnCompositionOrStartup(String contents, String filePath) =>
    _referencedUris(contents, filePath).any((uri) =>
        uri.startsWith('package:lunarlog/composition/') ||
        uri == 'lib/composition' ||
        uri.startsWith('lib/composition/') ||
        uri.startsWith('package:lunarlog/startup/') ||
        uri == 'lib/startup' ||
        uri.startsWith('lib/startup/'));

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

/// The `.dart` files directly in `lib/` (non-recursive — `lib/data/`,
/// `lib/domain/`, `lib/ui/`, etc. are each already covered by their own
/// scan above). Issue #551: `lib/app.dart` and `lib/app_root.dart` sat
/// outside every scan in this file despite importing both `lib/data` and
/// `lib/ui` — 1800+ combined lines with no layering guard of any kind.
List<File> _bareLibDartFiles() => Directory('lib')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// The raw local-store references issue #551 (part 3) forbids in
/// `lib/app.dart` and `lib/ui`: the `LunarLogStorage` type name and the
/// `.db.storage` accessor. Deliberately narrow — Supabase's
/// `client.storage.from(...)` and a repository's own private `_storage`
/// field are not bypasses; the guard targets reaching the *local drift
/// store* outside the composition root.
final _rawStorageReference = RegExp(r'\bLunarLogStorage\b|\bdb\.storage\b');

/// [contents] with Dart line/block comments removed, so the doc comments
/// that *describe* the eliminated bypass (and the historical notes beside
/// them) do not trip [referencesRawStorage]. String literals are copied
/// verbatim so a `//` inside a URL is not mistaken for a comment.
String _withoutComments(String contents) {
  final out = StringBuffer();
  var i = 0;
  final n = contents.length;
  while (i < n) {
    final c = contents[i];
    if (c == "'" || c == '"') {
      final raw = i > 0 && contents[i - 1] == 'r';
      final quote = c;
      out.write(c);
      i++;
      final triple =
          i + 1 < n && contents[i] == quote && contents[i + 1] == quote;
      if (triple) {
        out.write(quote);
        out.write(quote);
        i += 2;
      }
      while (i < n) {
        if (!raw && contents[i] == r'\') {
          out.write(contents[i]);
          if (i + 1 < n) out.write(contents[i + 1]);
          i += 2;
          continue;
        }
        if (triple) {
          if (contents[i] == quote &&
              i + 2 < n &&
              contents[i + 1] == quote &&
              contents[i + 2] == quote) {
            out.write(quote);
            out.write(quote);
            out.write(quote);
            i += 3;
            break;
          }
        } else if (contents[i] == quote) {
          out.write(quote);
          i++;
          break;
        }
        out.write(contents[i]);
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < n && contents[i + 1] == '/') {
      final eol = contents.indexOf('\n', i);
      i = eol == -1 ? n : eol; // keep the newline for line numbering sanity
      continue;
    }
    if (c == '/' && i + 1 < n && contents[i + 1] == '*') {
      final end = contents.indexOf('*/', i + 2);
      i = end == -1 ? n : end + 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Whether [contents] of [filePath] reaches the raw local drift store
/// directly (issue #551 part 3), ignoring comments.
bool referencesRawStorage(String contents, String filePath) =>
    _rawStorageReference.hasMatch(_withoutComments(contents));

void _expectNoOffendersAmong(
  List<File> files,
  bool Function(String contents, String path) violates,
  String rule,
) {
  expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

  // Issue #658: normalise to posix separators for reporting too, so an
  // offender list printed on Windows reads the same (`lib/data/x.dart`) as
  // it does in CI, rather than `lib\data\x.dart`.
  final offenders = [
    for (final file in files)
      if (violates(file.readAsStringSync(), file.path))
        file.path.replaceAll(r'\', '/'),
  ];
  expect(offenders, isEmpty,
      reason: '$rule, but these files do:\n${offenders.join('\n')}');
}

void _expectNoOffenders(
  String root,
  bool Function(String contents, String path) violates,
  String rule, {
  bool excludeGenerated = false,
}) =>
    _expectNoOffendersAmong(
        _dartFilesUnder(root, excludeGenerated: excludeGenerated),
        violates,
        rule);

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

    // R11: the two edges the guard never enforced before issue #100's
    // follow-up. `_expectNoOffenders` asserts a non-zero scanned-file count
    // on each, so a wrong path cannot make them pass vacuously.
    test('no lib/ui file depends on lib/data', () {
      _expectNoOffenders('lib/ui', dependsOnDataLayer,
          'lib/ui must not depend on lib/data',
          excludeGenerated: true);
    });

    // R16: `lib/ui` must never see the composition bundle (`AppDependencies`)
    // or the startup bootstrap. `_expectNoOffenders` asserts a non-zero
    // scanned-file count, so a wrong path cannot make it pass vacuously.
    test('no lib/ui file depends on lib/composition or lib/startup', () {
      _expectNoOffenders('lib/ui', dependsOnCompositionOrStartup,
          'lib/ui must not depend on lib/composition or lib/startup',
          excludeGenerated: true);
    });

    test('no lib/domain file depends on lib/data', () {
      _expectNoOffenders(
          'lib/domain', dependsOnDataLayer, 'lib/domain must not depend on lib/data');
    });

    // Issue #551: `lib/app.dart` and `lib/app_root.dart` are the
    // composition-root widgets — they legitimately import both `lib/data`
    // and `lib/ui` to assemble the provider tree, so neither the
    // `lib/data -/-> lib/ui` nor the `lib/ui -/-> lib/data` rule above can
    // apply to them (and previously didn't, since neither scan reaches a
    // bare `lib/*.dart` file at all). Every *other* bare `lib/*.dart` file
    // (`main.dart`, `config.dart`, `gate_controller.dart`,
    // `app_lifecycle.dart`) has no such reason to import `lib/ui` directly
    // — this scan gives them the same guard `lib/data` already has, and
    // catches a future bare `lib/*.dart` file drifting into a UI import
    // without earning the same documented exception these two have.
    test(
        'no lib/*.dart file depends on lib/ui, except the two documented '
        'composition-root widgets', () {
      const composesTheUiTreeItself = {'lib/app.dart', 'lib/app_root.dart'};
      // Issue #658: `File.path` from `Directory.listSync()` is
      // backslash-separated on Windows (`lib\app.dart`), so comparing it
      // directly against the posix-style allowlist above never matched and
      // both composition-root widgets were reported as offenders on every
      // Windows run. Normalise to posix separators first, same as
      // `_resolve` already does for relative-import targets.
      final files = _bareLibDartFiles()
          .where((f) =>
              !composesTheUiTreeItself.contains(f.path.replaceAll(r'\', '/')))
          .toList();
      _expectNoOffendersAmong(files, dependsOnUiLayer,
          'a bare lib/*.dart file must not depend on lib/ui');
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

      // Falsification coverage for the `lib/ui -/-> lib/data` scan: a
      // synthetic lib/ui file importing the data layer is flagged in both
      // package-URI and resolved-relative form, while a domain import and a
      // sibling directory that merely starts with "data" are not.
      const uiPath = 'lib/ui/overview/overview_panel.dart';
      expect(
          dependsOnDataLayer(
              "import 'package:lunarlog/data/repositories/"
                  "drift_profiles_repository.dart';",
              uiPath),
          isTrue,
          reason: 'a lib/ui file importing package:lunarlog/data/... must flag');
      expect(
          dependsOnDataLayer(
              "import '../../data/repositories/drift_profiles_repository.dart';",
              uiPath),
          isTrue,
          reason: 'a relative escape into lib/data must flag');
      expect(
          dependsOnDataLayer(
              "import 'package:lunarlog/domain/models/profile.dart';", uiPath),
          isFalse,
          reason: 'a domain import is not a data-layer dependency');
      expect(
          dependsOnDataLayer(
              "import '../data_helpers/format.dart';", 'lib/ui/probe.dart'),
          isFalse,
          reason: 'a sibling directory that merely starts with "data" is fine');

      // Falsification coverage for the `lib/ui -/-> lib/composition` and
      // `lib/ui -/-> lib/startup` scans: a synthetic lib/ui file importing
      // either layer is flagged in package-URI and resolved-relative form,
      // while a domain import and a sibling directory that merely starts
      // with "composition" are not.
      const compositionUiPath = 'lib/ui/settings/settings_screen.dart';
      expect(
          dependsOnCompositionOrStartup(
              "import 'package:lunarlog/composition/app_dependencies.dart';",
              compositionUiPath),
          isTrue,
          reason: 'a lib/ui file importing the composition bundle must flag');
      expect(
          dependsOnCompositionOrStartup(
              "import '../../startup/startup.dart';", compositionUiPath),
          isTrue,
          reason: 'a relative escape into lib/startup must flag');
      expect(
          dependsOnCompositionOrStartup(
              "import 'package:lunarlog/domain/notifications/"
                  "reminder_scheduler.dart';",
              compositionUiPath),
          isFalse,
          reason: 'a domain import is not a composition/startup dependency');
      expect(
          dependsOnCompositionOrStartup(
              "import '../composition_helpers/format.dart';",
              'lib/ui/probe.dart'),
          isFalse,
          reason: 'a sibling directory that merely starts with "composition" '
              'is fine');
    });

    // Issue #551 (part 3): the storage bypass itself. `lib/app.dart` is a
    // composition root that legitimately imports `lib/data` to assemble the
    // provider tree, so the `lib/ui -/-> lib/data` scan above cannot apply
    // to it — this reference guard is what keeps its own storage access
    // routed through `AppDependencies` rather than `widget.db.storage`.
    test('lib/app.dart reaches the local store only through repositories',
        () {
      final app = _bareLibDartFiles()
          .where((f) => f.path.replaceAll(r'\', '/') == 'lib/app.dart')
          .toList();
      expect(app, hasLength(1), reason: 'lib/app.dart not found');
      _expectNoOffendersAmong(app, referencesRawStorage,
          'lib/app.dart must not reference LunarLogStorage or .db.storage');
    });

    test('no lib/ui file reaches the local store directly', () {
      _expectNoOffenders('lib/ui', referencesRawStorage,
          'lib/ui must not reference LunarLogStorage or .db.storage',
          excludeGenerated: true);
    });

    // Gives the two guards above their own teeth, exactly as the
    // directive-based detector has: the bypass is flagged in each form it
    // can take, while the comments that *describe* the eliminated bypass
    // and unrelated domain reads are not.
    test('detects the forms a raw-storage bypass can take', () {
      expect(
          referencesRawStorage(
              'value: widget.db.storage.countAllRows,', 'lib/app.dart'),
          isTrue,
          reason: 'a `.db.storage` tear-off is the bypass');
      expect(
          referencesRawStorage('db.storage.watchProfileMode(id)', 'lib/app.dart'),
          isTrue,
          reason: 'a bare `db.storage` access is the bypass');
      expect(
          referencesRawStorage(
              'final LunarLogStorage storage;', 'lib/ui/probe.dart'),
          isTrue,
          reason: 'the raw storage type name is the bypass');
      expect(
          referencesRawStorage(
              "/// was `widget.db.storage.watchProfileMode` before #551",
              'lib/app.dart'),
          isFalse,
          reason: 'a doc comment describing the old bypass is not code');
      expect(
          referencesRawStorage(
              '// LunarLogStorage has left the tree', 'lib/app.dart'),
          isFalse,
          reason: 'a line comment is not code');
      expect(
          referencesRawStorage('/* LunarLogStorage */', 'lib/app.dart'),
          isFalse,
          reason: 'a block comment is not code');
      expect(
          referencesRawStorage(
              "final url = 'https://example.com/a'; "
                  'final c = db.storage.countAllRows;',
              'lib/app.dart'),
          isTrue,
          reason: "a URL's `//` inside a string must not swallow the rest "
              'of the line');
      expect(
          referencesRawStorage(
              'context.read<ProfileModesRepository>()', 'lib/ui/probe.dart'),
          isFalse,
          reason: 'a domain repository read is not a raw-storage reference');
    });
  });
}
