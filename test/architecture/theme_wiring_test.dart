/// #137 guard (issue #176 review): `AppTheme.darkTheme` exists and is
/// unit-tested (`test/ui/theme_test.dart`), but no `MaterialApp` in `lib/`
/// wires it in yet -- flipping the app to follow system brightness is
/// issue #137's own job. This source-scan (in the style of
/// `test/architecture/layering_test.dart`) fails the moment any
/// `MaterialApp` sets `darkTheme:` or `themeMode:`, so that only happens
/// when #137 does it deliberately rather than as a drive-by side effect of
/// some unrelated change.
///
/// Detection extracts each `MaterialApp(...)` call's balanced argument list
/// (rather than matching `darkTheme:`/`themeMode:` anywhere in the file) so
/// a doc comment merely mentioning either name -- like this file's own --
/// never trips the guard, and a `//` line comment is stripped first so it
/// can't hide a real violation either.
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

/// Whether any `MaterialApp(...)` call in [contents] sets `darkTheme:` or
/// `themeMode:`.
bool setsDarkThemeOrThemeMode(String contents) => _materialAppArgLists(
      contents,
    ).any((args) => _darkThemeKey.hasMatch(args) || _themeModeKey.hasMatch(args));

void main() {
  group('theme wiring (#137 guard)', () {
    test('no MaterialApp in lib/ sets darkTheme: or themeMode:', () {
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

      final offenders = [
        for (final file in files)
          if (setsDarkThemeOrThemeMode(file.readAsStringSync())) file.path,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'no MaterialApp may set darkTheme:/themeMode: until #137 '
            'wires system-brightness following deliberately, but these do:\n'
            '${offenders.join('\n')}',
      );
    });

    // Gives the detector its own falsification coverage, same as
    // `layering_test.dart`'s "detects the forms a layering violation can
    // take" -- without this, a detector that silently stopped matching
    // would leave the scan above vacuously green.
    test('detects darkTheme:/themeMode: and ignores prose mentions', () {
      const withDarkTheme = '''
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
        )
      ''';
      expect(setsDarkThemeOrThemeMode(withDarkTheme), isTrue,
          reason: 'should flag darkTheme:');

      const withThemeMode = '''
        MaterialApp(
          themeMode: ThemeMode.system,
        )
      ''';
      expect(setsDarkThemeOrThemeMode(withThemeMode), isTrue,
          reason: 'should flag themeMode:');

      const clean = '''
        MaterialApp(
          title: 'lunarlog',
          theme: AppTheme.lightTheme,
          home: Scaffold(body: SizedBox()),
        )
      ''';
      expect(setsDarkThemeOrThemeMode(clean), isFalse,
          reason: 'should not flag a MaterialApp without either key');

      const prose = '''
        /// Doesn't wire darkTheme: or themeMode: yet -- #137's job.
        MaterialApp(
          theme: AppTheme.lightTheme,
        )
      ''';
      expect(setsDarkThemeOrThemeMode(prose), isFalse,
          reason: 'a doc comment mentioning either name must not trip this');

      const noMaterialApp = '''
        final themeMode = ThemeMode.system;
        Widget build(BuildContext context) => Scaffold();
      ''';
      expect(setsDarkThemeOrThemeMode(noMaterialApp), isFalse,
          reason: 'themeMode used outside any MaterialApp(...) call');
    });
  });
}
