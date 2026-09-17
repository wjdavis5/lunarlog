/// #137 wiring guard (issue #176 review): every `MaterialApp` in `lib/`
/// must set **both** `darkTheme:` and `themeMode:`. Before #137 landed,
/// this same source scan asserted the exact opposite — that no
/// `MaterialApp` set either — so the flip to dark-following could only
/// happen when #137 did it deliberately. Now that it has, the invariant
/// inverts: a light-only `MaterialApp` (someone adding a new self-
/// constructing surface, or reverting one of the #137 wirings) must fail
/// this scan, because a surface without `darkTheme:`/`themeMode:` is by
/// definition hardcoding the light theme against the app's appearance
/// override (issue #137's last acceptance criterion).
///
/// Detection extracts each `MaterialApp(...)` call's balanced argument list
/// (rather than matching `darkTheme:`/`themeMode:` anywhere in the file) so
/// a doc comment merely mentioning either name -- like this file's own --
/// never satisfies or trips the guard, and a `//` line comment is stripped
/// first so it can't hide a real gap either.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`-style line comments (including `///` doc comments) from
/// [contents]. Naive relative to a real lexer (a `//` inside a string
/// literal would also be treated as a comment start), but that only risks
/// under-scanning a line, never hiding a real `MaterialApp(...)` call --
/// this file's own two names are what it must not be fooled by, and this
/// keeps the detector dependency-free like `layering_test.dart`'s.
String _stripLineComments(String contents) => contents
    .split('\n')
    .map((line) {
      final commentIndex = line.indexOf('//');
      return commentIndex == -1 ? line : line.substring(0, commentIndex);
    })
    .join('\n');

/// Every `MaterialApp(...)` call's argument-list text in [contents], with
/// balanced-paren extraction so a nested `(` (a builder callback, a nested
/// widget constructor) doesn't truncate the scan at the first `)`.
Iterable<String> _materialAppArgLists(String contents) sync* {
  final code = _stripLineComments(contents);
  for (final match in RegExp(r'MaterialApp\s*\(').allMatches(code)) {
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

final _darkThemeKey = RegExp(r'\bdarkTheme\s*:');
final _themeModeKey = RegExp(r'\bthemeMode\s*:');

/// The `MaterialApp(...)` argument lists in [contents] that are missing
/// `darkTheme:` or `themeMode:` (issue #137's wiring, both required).
Iterable<String> argListsMissingDarkWiring(String contents) =>
    _materialAppArgLists(contents).where(
      (args) =>
          !_darkThemeKey.hasMatch(args) || !_themeModeKey.hasMatch(args),
    );

void main() {
  group('theme wiring (#137 guard)', () {
    test('every MaterialApp in lib/ sets both darkTheme: and themeMode:',
        () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('.g.dart'))
          .toList();
      expect(
        files,
        isNotEmpty,
        reason: 'scanned zero files under lib -- check the path',
      );

      final offenders = <String>[
        for (final file in files)
          if (argListsMissingDarkWiring(file.readAsStringSync()).isNotEmpty)
            file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'every MaterialApp must wire darkTheme: + themeMode: so no '
            'surface can render light-only against the appearance override '
            '(issue #137), but these do not:\n${offenders.join('\n')}',
      );
    });

    // Gives the detector its own falsification coverage, same as
    // `layering_test.dart`'s "detects the forms a layering violation can
    // take" -- without this, a detector that silently stopped matching
    // would leave the scan above vacuously green.
    test('detects a missing darkTheme:/themeMode: and ignores prose mentions',
        () {
      const missingDarkTheme = '''
        MaterialApp(
          theme: AppTheme.lightTheme,
          themeMode: ThemeMode.system,
        )
      ''';
      expect(
          argListsMissingDarkWiring(missingDarkTheme).isNotEmpty, isTrue,
          reason: 'should flag themeMode: without darkTheme:');

      const missingThemeMode = '''
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
        )
      ''';
      expect(
          argListsMissingDarkWiring(missingThemeMode).isNotEmpty, isTrue,
          reason: 'should flag darkTheme: without themeMode:');

      const fullyWired = '''
        MaterialApp(
          title: 'lunarlog',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: Scaffold(body: SizedBox()),
        )
      ''';
      expect(argListsMissingDarkWiring(fullyWired), isEmpty,
          reason: 'a MaterialApp with both keys is fully wired');

      const prose = '''
        /// Mentions darkTheme: or themeMode: in a doc comment only.
        MaterialApp(
          theme: AppTheme.lightTheme,
        )
      ''';
      expect(argListsMissingDarkWiring(prose).isNotEmpty, isTrue,
          reason: 'prose names must not satisfy the detector: the '
              'MaterialApp behind this comment has neither key and is a '
              'real offender');

      const noMaterialApp = '''
        final themeMode = ThemeMode.system;
        Widget build(BuildContext context) => Scaffold();
      ''';
      expect(argListsMissingDarkWiring(noMaterialApp), isEmpty,
          reason: 'themeMode used outside any MaterialApp(...) call');
    });
  });
}
