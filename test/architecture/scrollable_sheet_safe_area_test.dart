/// #1232 guard: a `showModalBottomSheet` opened with `isScrollControlled:
/// true` removes the modal route's top view padding, so a tall sheet can
/// grow under the status bar / Dynamic Island and the body's own `SafeArea`
/// cannot help (top inset reads 0). PR #1226 fixed the 13 sheet calls that
/// had the height math but missed the 3 deep-link invite sheets in
/// `lib/app.dart` (`AcceptInviteSheet`, `ClaimProfileSheet`,
/// `AcceptPredictionConnectionSheet`) -- this source-scan (in the style of
/// `test/architecture/inline_error_text_color_test.dart`) fails the moment
/// any `showModalBottomSheet(...)` in `lib/` passes `isScrollControlled:
/// true` without also passing `useSafeArea: true`, so the next new sheet
/// cannot silently regress the way those 3 did.
///
/// Detection extracts each `showModalBottomSheet(...)` call's balanced
/// argument list (so a nested `(` -- a builder closure calling something --
/// doesn't truncate the scan at the first `)`), and `//` line comments are
/// stripped first so a doc comment merely mentioning the pattern -- like
/// this file's own header -- never trips the guard.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`-style line comments (including `///` doc comments) from
/// [contents]. Naive relative to a real lexer (a `//` inside a string
/// literal would also be treated as a comment start), but that only risks
/// under-scanning a line, never hiding a real `showModalBottomSheet(...)`
/// call.
String _stripLineComments(String contents) => contents
    .split('\n')
    .map((line) {
      final commentIndex = line.indexOf('//');
      return commentIndex == -1 ? line : line.substring(0, commentIndex);
    })
    .join('\n');

/// Matches a `showModalBottomSheet` call's opening paren, tolerating the
/// type argument every call site writes (`showModalBottomSheet<void>(`,
/// `showModalBottomSheet<(int, int)>(`) -- none contains a paren.
final _callStart = RegExp(r'\bshowModalBottomSheet\s*(?:<[^()]*?>)?\s*\(');

final _scrollControlledTrue = RegExp(r'\bisScrollControlled\s*:\s*true\b');

final _useSafeAreaTrue = RegExp(r'\buseSafeArea\s*:\s*true\b');

/// Every `showModalBottomSheet(...)` call's `(1-based line, argument-list
/// text)` in [contents], with balanced-paren extraction so a nested `(`
/// doesn't truncate the scan at the first `)`.
Iterable<(int, String)> _sheetArgLists(String contents) sync* {
  final code = _stripLineComments(contents);
  for (final match in _callStart.allMatches(code)) {
    var depth = 1;
    var i = match.end;
    final start = i;
    while (i < code.length && depth > 0) {
      if (code[i] == '(') depth++;
      if (code[i] == ')') depth--;
      i++;
    }
    final line =
        '\n'.allMatches(code.substring(0, match.start)).length + 1;
    yield (line, code.substring(start, depth == 0 ? i - 1 : i));
  }
}

/// Every scroll-controlled `showModalBottomSheet` call site in [contents]
/// that does not also pass `useSafeArea: true`, as `(1-based line, argument
/// list)`. `useSafeArea` is what keeps a tall, scroll-controlled sheet
/// below the status bar (issue #1232); there is no legitimate
/// scroll-controlled-without-safe-area shape, so there is no allowlist.
List<(int, String)> scrollControlledSheetsWithoutSafeArea(String contents) => [
      for (final (line, args) in _sheetArgLists(contents))
        if (_scrollControlledTrue.hasMatch(args) &&
            !_useSafeAreaTrue.hasMatch(args))
          (line, args),
    ];

/// How many `showModalBottomSheet` calls in [contents] are scroll-
/// controlled at all -- the vacuity guard for the scan in [main] (a
/// detector that silently stopped matching `isScrollControlled` would
/// otherwise leave that scan green forever).
int scrollControlledSheetCount(String contents) => _sheetArgLists(contents)
    .where((argList) => _scrollControlledTrue.hasMatch(argList.$2))
    .length;

void main() {
  group('Scroll-controlled sheet safe-area convention (#1232 guard)', () {
    test(
        'every isScrollControlled: true showModalBottomSheet in lib/ also '
        'passes useSafeArea: true', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(
        files,
        isNotEmpty,
        reason: 'scanned zero files under lib -- check the path',
      );

      final offenders = [
        for (final file in files)
          for (final (line, _) in scrollControlledSheetsWithoutSafeArea(
              file.readAsStringSync()))
            '${file.path.replaceAll('\\', '/')}:$line',
      ];

      expect(
        offenders,
        isEmpty,
        reason: 'a scroll-controlled bottom sheet removes the modal route\'s '
            'top view padding, so a tall sheet grows under the status '
            'bar/Dynamic Island and the body\'s SafeArea cannot help '
            '(#1217/#1226/#1232) -- pass useSafeArea: true on the offending '
            'call(s):\n'
            '${offenders.join('\n')}',
      );

      // Vacuity guard: the scan must still see scroll-controlled call sites
      // in the real tree (16 at the time of #1232). Zero means the walk
      // broke (wrong path, unreadable files) or the detector stopped
      // matching -- not that the convention became moot.
      final scrollControlledSites = [
        for (final file in files)
          scrollControlledSheetCount(file.readAsStringSync()),
      ].fold(0, (a, b) => a + b);
      expect(
        scrollControlledSites,
        greaterThanOrEqualTo(1),
        reason: 'the scan saw no isScrollControlled: true showModalBottomSheet '
            'in lib/ -- either the detector broke (see the falsification '
            'tests below) or the lib/ walk is wrong',
      );
    });

    // Gives the detector its own falsification coverage, same as
    // `inline_error_text_color_test.dart`'s -- without this, a detector
    // that silently stopped matching would leave the scan above vacuously
    // green.
    test('flags a scroll-controlled sheet without useSafeArea and passes '
        'the clean shapes', () {
      const missingSafeArea = '''
        showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => SomeSheet(),
        )
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(missingSafeArea),
        hasLength(1),
        reason: 'should flag isScrollControlled: true with no useSafeArea',
      );

      const withSafeArea = '''
        showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => SomeSheet(),
        )
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(withSafeArea),
        isEmpty,
        reason: 'the #1226/#1232 shape must pass',
      );

      const notScrollControlled = '''
        showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: false,
          showDragHandle: true,
          builder: (_) => SomeSheet(),
        )
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(notScrollControlled),
        isEmpty,
        reason: 'a non-scroll-controlled sheet keeps the default insets -- '
            'no useSafeArea requirement',
      );

      const explicitSafeAreaFalse = '''
        showModalBottomSheet<void>(
          context: ctx,
          isScrollControlled: true,
          useSafeArea: false,
          builder: (_) => SomeSheet(),
        )
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(explicitSafeAreaFalse),
        hasLength(1),
        reason: 'useSafeArea: false is exactly the regression this guards '
            'against',
      );

      const typedCall = '''
        final result = await showModalBottomSheet<(int, int)>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => SomeSheet(),
        );
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(typedCall),
        isEmpty,
        reason: 'a generic type argument must not break the call detection',
      );

      const prose = '''
        /// A sheet opened with isScrollControlled: true and no
        /// useSafeArea: true slides under the status bar.
        Widget build(BuildContext context) => const SizedBox.shrink();
      ''';
      expect(
        scrollControlledSheetsWithoutSafeArea(prose),
        isEmpty,
        reason: 'a doc comment mentioning the pattern must not trip this '
            'when no real call uses it',
      );
    });
  });
}
