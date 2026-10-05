/// Guard: a snackbar with an action is built through `actionSnackBar`
/// (`lib/ui/components/action_snack_bar.dart`) and nowhere else.
///
/// On the pinned Flutter a `SnackBar` built with an `action` defaults to
/// `persist: true`, and a persistent snackbar never times out. Every such
/// snackbar in the app (the quick-log Undo, the day sheet's two Undos, the
/// sync glyph's Settings shortcut) therefore stayed on screen until swiped
/// away, with every later snackbar queued unseen behind it. The helper sets
/// a duration and keeps persistence only for assistive navigation; this
/// source scan (in the style of `inline_error_text_color_test.dart`) fails
/// the moment a file under `lib/` constructs a `SnackBarAction` itself, so a
/// new call site cannot quietly bring the never-leaving snackbar back.
///
/// `//` line comments are stripped first, so prose that names the class --
/// like this file's own -- never trips the guard.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to construct a `SnackBarAction`.
const String _helperPath = 'lib/ui/components/action_snack_bar.dart';

/// Strips `//`-style line comments (including `///` doc comments) from
/// [contents]. Naive relative to a real lexer (a `//` inside a string
/// literal would also be treated as a comment start), but that only risks
/// under-scanning the rest of that one line.
String _stripLineComments(String contents) => contents
    .split('\n')
    .map((line) {
      final commentIndex = line.indexOf('//');
      return commentIndex == -1 ? line : line.substring(0, commentIndex);
    })
    .join('\n');

/// A `SnackBarAction` construction: `SnackBarAction(`, with or without
/// `const`/whitespace, or the `SnackBarAction.new` tear-off. The leading
/// `\b` keeps a longer identifier that merely ends in the name from
/// matching, and requiring `(` or `.new` keeps a type annotation
/// (`SnackBarAction? action`) from matching.
final RegExp _snackBarActionConstruction =
    RegExp(r'\bSnackBarAction\s*(?:\(|\.\s*new\b)');

/// Whether [contents] constructs a `SnackBarAction` in code (not prose).
bool constructsSnackBarAction(String contents) =>
    _snackBarActionConstruction.hasMatch(_stripLineComments(contents));

/// Whether [contents] calls the shared helper in code (not prose).
bool callsActionSnackBar(String contents) =>
    RegExp(r'\bactionSnackBar\s*\(').hasMatch(_stripLineComments(contents));

String _normalized(File file) => file.path.replaceAll('\\', '/');

void main() {
  group('action snackbars go through actionSnackBar', () {
    test('no file under lib/ constructs a SnackBarAction except the shared '
        'helper', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(
        files,
        isNotEmpty,
        reason: 'scanned zero files under lib/ -- check the path',
      );

      final constructing = [
        for (final file in files)
          if (constructsSnackBarAction(file.readAsStringSync()))
            _normalized(file),
      ];

      // The scan must be able to see the one construction that is allowed:
      // if it cannot find the helper's own, it is not finding anything and
      // the offender check below would pass vacuously.
      expect(
        constructing.where((path) => path.endsWith(_helperPath)),
        hasLength(1),
        reason: '$_helperPath is where the SnackBarAction is built; the '
            'scan did not find it there (moved, renamed, or the detector '
            'stopped matching)',
      );

      final offenders = constructing
          .where((path) => !path.endsWith(_helperPath))
          .toList();
      expect(
        offenders,
        isEmpty,
        reason:
            'a SnackBar built with an action persists until swiped away '
            'and blocks every later snackbar. Build it with actionSnackBar '
            '($_helperPath) instead -- offending file(s):\n'
            '${offenders.join('\n')}',
      );
    });

    test('the helper is actually used by call sites under lib/', () {
      final callers = [
        for (final file in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')))
          if (!_normalized(file).endsWith(_helperPath) &&
              callsActionSnackBar(file.readAsStringSync()))
            _normalized(file),
      ];
      expect(
        callers,
        isNotEmpty,
        reason: 'nothing under lib/ calls actionSnackBar -- either the '
            'action snackbars are gone (delete the helper and this guard) '
            'or they are being built some other way',
      );
    });

    // The detector's own falsification coverage, same as
    // `inline_error_text_color_test.dart`'s: without it, a detector that
    // silently stopped matching would leave the scan above green.
    test('detects a SnackBarAction construction and ignores prose, type '
        'annotations, and the helper call', () {
      const direct = '''
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: label, onPressed: onPressed),
        )
      ''';
      expect(constructsSnackBarAction(direct), isTrue);

      const constAndSpaced = '''
        action: const SnackBarAction (
          label: 'Undo',
          onPressed: _noop,
        ),
      ''';
      expect(constructsSnackBarAction(constAndSpaced), isTrue,
          reason: 'const and whitespace before the paren still construct');

      const tearOff = 'final build = SnackBarAction.new;';
      expect(constructsSnackBarAction(tearOff), isTrue,
          reason: 'a constructor tear-off builds one just the same');

      const prose = '''
        /// Never build a SnackBarAction(label: ...) here.
        // action: SnackBarAction(label: label, onPressed: onPressed),
        Widget build(BuildContext context) => const SizedBox.shrink();
      ''';
      expect(constructsSnackBarAction(prose), isFalse,
          reason: 'a comment naming the class must not trip the guard');

      const typeOnly = '''
        final SnackBarAction? action = bar.action;
        void use(SnackBarAction action) {}
      ''';
      expect(constructsSnackBarAction(typeOnly), isFalse,
          reason: 'reading an existing action is not constructing one');

      const viaHelper = '''
        messenger.showSnackBar(
          actionSnackBar(
            content: Text(message),
            actionLabel: label,
            onAction: onAction,
            accessibleNavigation: MediaQuery.accessibleNavigationOf(context),
          ),
        );
      ''';
      expect(constructsSnackBarAction(viaHelper), isFalse);
      expect(callsActionSnackBar(viaHelper), isTrue);

      const longerName = 'final x = MySnackBarAction(label: label);';
      expect(constructsSnackBarAction(longerName), isFalse,
          reason: 'a different class whose name ends the same way');

      const helperProse = '/// Build it with actionSnackBar(...) instead.';
      expect(callsActionSnackBar(helperProse), isFalse);
    });
  });
}
