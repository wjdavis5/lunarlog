/// #555 guard: `lib/ui/README.md` states the rule -- a retryable, in-place
/// failure renders `InlineError` (`lib/ui/components/inline_error.dart`),
/// never a bare `Text` styled red, because only `InlineError` wraps its
/// message in the `Semantics(liveRegion: true, container: true)` a
/// screen-reader user needs to hear the failure. This source-scan (in the
/// style of `test/architecture/theme_wiring_test.dart`) fails the moment a
/// new `Text(...)` call outside `inline_error.dart` colors itself with
/// `colorScheme.error`, so a future failure-message site can't silently
/// regress back to a bare red `Text` the way the 10+ sites #555 fixed did.
///
/// Detection extracts each `Text(...)` call's balanced argument list
/// (rather than matching `colorScheme.error` anywhere in the file) so a
/// doc comment merely mentioning it -- like this file's own -- never trips
/// the guard, and a `//` line comment is stripped first so it can't hide a
/// real violation either.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`-style line comments (including `///` doc comments) from
/// [contents]. Naive relative to a real lexer (a `//` inside a string
/// literal would also be treated as a comment start), but that only risks
/// under-scanning a line, never hiding a real `Text(...)` call.
String _stripLineComments(String contents) => contents
    .split('\n')
    .map((line) {
      final commentIndex = line.indexOf('//');
      return commentIndex == -1 ? line : line.substring(0, commentIndex);
    })
    .join('\n');

/// Every `Text(...)` call's argument-list text in [contents], with
/// balanced-paren extraction so a nested `(` (a `copyWith(...)`, a ternary
/// calling another function) doesn't truncate the scan at the first `)`.
Iterable<String> _textArgLists(String contents) sync* {
  final code = _stripLineComments(contents);
  for (final match in RegExp(r'\bText\s*\(').allMatches(code)) {
    var depth = 1;
    var i = match.end;
    final start = i;
    while (i < code.length && depth > 0) {
      if (code[i] == '(') depth++;
      if (code[i] == ')') depth--;
      i++;
    }
    yield code.substring(start, depth == 0 ? i - 1 : i);
  }
}

/// Matches `color: ...colorScheme.error` (not `errorContainer`,
/// `backgroundColor:`/`foregroundColor:` are excluded by requiring `color:`
/// to be a whole word immediately before the value). `[^,]*?` (rather than
/// an identifier-only character class) spans a `Theme.of(context).` prefix
/// or a ternary's ` ? a : ` -- anything up to the next comma, non-greedy so
/// it cannot cross into an unrelated later argument.
final _colorSchemeError =
    RegExp(r'(?<![A-Za-z])color:[^,]*?colorScheme\.error\b');

/// Whether any `Text(...)` call in [contents] colors itself with
/// `colorScheme.error`.
bool hasRedErrorText(String contents) =>
    _textArgLists(contents).any((args) => _colorSchemeError.hasMatch(args));

/// Files with a `Text(...)` that legitimately colors itself with
/// `colorScheme.error` for a reason other than "this is a retryable
/// operation failure" -- each documented at its own call site.
const Set<String> _allowedExceptions = {
  // Destructive-action red label on the "Delete account" tile itself (the
  // convention destructive menu/list items use), not a failure message --
  // the tile's own failure (`_deleteError`) already renders through
  // InlineError right below it.
  'lib/ui/account/account_section.dart',
  // The age-acknowledgement checkbox's required-field validation hint,
  // conditionally red when unchecked -- a form-validation cue (the same
  // role a TextFormField's own `errorText` plays), not an operation
  // failure with anything to retry.
  'lib/ui/profiles/first_run_screen.dart',
  // Issue #472: the "Danger zone" section heading above "Delete profile
  // permanently" -- the same destructive-action red label convention as
  // account_section.dart's "Delete account" tile above, not a failure
  // message; the delete's own failure renders through InlineError right
  // below the button.
  'lib/ui/sharing/manage_guardians_screen.dart',
};

void main() {
  group('InlineError convention (#555 guard)', () {
    test(
        'no Text(...) outside inline_error.dart colors itself with '
        'colorScheme.error, except the documented exceptions', () {
      final files = Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('inline_error.dart'))
          .toList();
      expect(
        files,
        isNotEmpty,
        reason: 'scanned zero files under lib/ui -- check the path',
      );

      final offenders = [
        for (final file in files)
          if (hasRedErrorText(file.readAsStringSync()))
            file.path.replaceAll('\\', '/'),
      ];
      final unexpected = offenders
          .where((path) => !_allowedExceptions
              .any((allowed) => path.endsWith(allowed.replaceAll('\\', '/'))))
          .toList();

      expect(
        unexpected,
        isEmpty,
        reason:
            'lib/ui/README.md: a retryable in-place failure renders '
            'InlineError, never a bare red Text (it is the only one that '
            'announces itself to a screen reader) -- offending file(s):\n'
            '${unexpected.join('\n')}',
      );

      // The allowlist itself must stay honest: if a listed file no longer
      // contains the pattern (e.g. it was rewritten to use InlineError
      // too), the exception is dead weight -- shrink the list.
      final staleExceptions = _allowedExceptions.where(
        (allowed) => !offenders.any((path) => path.endsWith(allowed)),
      );
      expect(
        staleExceptions,
        isEmpty,
        reason: 'these allowlisted files no longer match the pattern -- '
            'remove them from _allowedExceptions:\n'
            '${staleExceptions.join('\n')}',
      );
    });

    // Gives the detector its own falsification coverage, same as
    // `theme_wiring_test.dart`'s -- without this, a detector that silently
    // stopped matching would leave the scan above vacuously green.
    test('detects a red error Text and ignores prose mentions/non-color '
        'uses of colorScheme.error', () {
      const withRedText = '''
        Text(
          _error!,
          style: TextStyle(color: theme.colorScheme.error),
        )
      ''';
      expect(hasRedErrorText(withRedText), isTrue,
          reason: 'should flag a Text styled with colorScheme.error');

      const withCopyWith = '''
        Text(
          message,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        )
      ''';
      expect(hasRedErrorText(withCopyWith), isTrue,
          reason: 'should flag copyWith(color: ...) too, not just TextStyle');

      const clean = '''
        Text(
          message,
          style: theme.textTheme.bodySmall,
        )
      ''';
      expect(hasRedErrorText(clean), isFalse,
          reason: 'a Text with no error-colored style must not be flagged');

      const errorContainerBackground = '''
        Container(
          color: theme.colorScheme.errorContainer,
          child: Text('banner'),
        )
      ''';
      expect(hasRedErrorText(errorContainerBackground), isFalse,
          reason: 'errorContainer (a background, and outside the Text '
              'call entirely) must not be mistaken for colorScheme.error');

      const buttonBackground = '''
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
          child: Text('Delete'),
        )
      ''';
      expect(hasRedErrorText(buttonBackground), isFalse,
          reason: 'backgroundColor: on a button (outside the Text call) '
              'is a destructive-button convention, not this rule\'s target');

      const prose = '''
        /// Renders InlineError, never colorScheme.error, for a Text(...).
        Widget build(BuildContext context) => const Text('fine');
      ''';
      expect(hasRedErrorText(prose), isFalse,
          reason: 'a comment mentioning colorScheme.error must not trip '
              'this when no real Text(...) call uses it');
    });
  });
}
