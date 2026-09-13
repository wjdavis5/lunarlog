/// Issue #545 guard: `lib/domain` sealed failure families used to carry
/// `String get userFacingMessage` getters that hardcoded English copy
/// directly inside the pure-Dart domain layer — the "50 `userFacingMessage`
/// getters hardcode English inside `lib/domain`" finding. Every one of
/// those getters (`SharingFailure`, `InviteCancellation`, `TransferFailure`,
/// `PredictionConnectionFailure`, `FeedbackFailure`,
/// `NotificationPreferencesFailure`) moved to a `…FailureCopy` mapper under
/// `lib/ui/l10n/`, and `GuardianRole.label`/`.readOnlyReason` moved to
/// `guardianRoleLabel`/`guardianRoleReadOnlyReason` in
/// `lib/ui/l10n/guardian_role_copy.dart`. This is a source scan (in the
/// style of `test/architecture/layering_test.dart` and
/// `theme_wiring_test.dart`) so a future failure family cannot reintroduce
/// the getter without this test failing first.
///
/// `readOnlyReason` is banned outright: nothing under `lib/domain` has a
/// legitimate reason to define a getter by that name (it exists purely to
/// carry the `GuardianRole` copy the issue moved out). `label` cannot be
/// banned the same blanket way — `CycleConfidence.label`/`.summary` are a
/// deliberate exception documented in `lib/ui/l10n/tiers.dart` (they stay
/// as the enum's own debug/`toString` vocabulary, with all *user-facing*
/// rendering routed through `tierLabel`/`tierSummary` instead) — so `label`
/// is checked only on `GuardianRole` specifically, by name-scoping the scan
/// to `profile_guardian.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('.g.dart'))
    .toList();

/// Matches `get $name` at the start of a getter declaration (an arrow body
/// `=> ...;` or a block body `{ ... }`). Every real getter this test bans
/// was written arrow-bodied (`String get userFacingMessage => '...';`,
/// `String? get readOnlyReason => switch (this) { ... };`), but a block
/// body is still detected below via balanced-brace scanning rather than
/// assumed away, so a future rewrite to `{ return ...; }` can't slip past
/// this guard. Matching just the bare identifier `$name` would also flag
/// prose that merely mentions it (this file's own doc comment, or another
/// file's `[userFacingMessage]` doc reference), which the tests below pin
/// as intentionally allowed — anchoring on `get $name` excludes those.
RegExp _getterStart(String name) => RegExp(r'get\s+' + name + r'\s*(=>|\{)');

/// Whether [contents] declares a getter named [name]: an arrow body up to
/// its terminating `;` (character classes match across newlines
/// regardless of line breaks in the body), or a block body with its own
/// braces balanced (so a nested block — an if, a switch statement — can't
/// truncate the scan at the first `}`).
bool _declaresGetter(String contents, String name) {
  for (final match in _getterStart(name).allMatches(contents)) {
    if (match.group(1) == '=>') {
      final semicolon = contents.indexOf(';', match.end);
      if (semicolon != -1) return true;
      continue;
    }
    // Block body: match.end sits just after the opening '{'.
    var depth = 1;
    var i = match.end;
    while (i < contents.length && depth > 0) {
      if (contents[i] == '{') depth++;
      if (contents[i] == '}') depth--;
      i++;
    }
    if (depth == 0) return true;
  }
  return false;
}

void main() {
  group('domain copy (#545 guard)', () {
    test('no lib/domain file declares a userFacingMessage getter', () {
      final files = _dartFilesUnder('lib/domain');
      expect(files, isNotEmpty,
          reason: 'scanned zero files under lib/domain -- check the path');

      final offenders = [
        for (final file in files)
          if (_declaresGetter(file.readAsStringSync(), 'userFacingMessage'))
            file.path,
      ];
      expect(offenders, isEmpty,
          reason: 'user-facing copy belongs in a …FailureCopy mapper under '
              'lib/ui/l10n/ (Issue #545), not a userFacingMessage getter in '
              'lib/domain, but these files still declare one:\n'
              '${offenders.join('\n')}');
    });

    test('no lib/domain file declares a readOnlyReason getter', () {
      final files = _dartFilesUnder('lib/domain');
      final offenders = [
        for (final file in files)
          if (_declaresGetter(file.readAsStringSync(), 'readOnlyReason'))
            file.path,
      ];
      expect(offenders, isEmpty,
          reason: 'read-only-reason copy belongs in '
              'guardianRoleReadOnlyReason (lib/ui/l10n/guardian_role_copy.dart), '
              'not a readOnlyReason getter in lib/domain, but these files '
              'still declare one:\n${offenders.join('\n')}');
    });

    test('GuardianRole (lib/domain/models/profile_guardian.dart) declares '
        'no label getter', () {
      const path = 'lib/domain/models/profile_guardian.dart';
      final contents = File(path).readAsStringSync();
      expect(_declaresGetter(contents, 'label'), isFalse,
          reason: 'GuardianRole.label moved to guardianRoleLabel '
              '(lib/ui/l10n/guardian_role_copy.dart); a label getter here '
              'would reintroduce hardcoded English in the domain layer');
    });

    // Falsification coverage, same shape as layering_test.dart's own: a
    // detector that silently stopped matching would leave the scans above
    // vacuously green.
    test('detects a declared getter and ignores a prose mention', () {
      const declaredArrow = '''
        sealed class FooFailure {
          String get userFacingMessage => 'Something went wrong.';
        }
      ''';
      expect(_declaresGetter(declaredArrow, 'userFacingMessage'), isTrue,
          reason: 'should flag an arrow-bodied getter declaration');

      const declaredBlock = '''
        sealed class FooFailure {
          String get userFacingMessage {
            return switch (this) {
              FooFailure.a => 'a',
              FooFailure.b => 'b',
            };
          }
        }
      ''';
      expect(_declaresGetter(declaredBlock, 'userFacingMessage'), isTrue,
          reason: 'should flag a block-bodied getter declaration');

      const proseOnly = '''
        /// Mirrors [SharingFailure.userFacingMessage]'s shape.
        sealed class FooFailure {}
      ''';
      expect(_declaresGetter(proseOnly, 'userFacingMessage'), isFalse,
          reason: 'a doc comment mentioning the name must not trip this');

      const unrelatedGetter = '''
        class Foo {
          String get label => 'Foo';
        }
      ''';
      expect(_declaresGetter(unrelatedGetter, 'userFacingMessage'), isFalse,
          reason: 'a getter with a different name must not trip this');
    });
  });
}
