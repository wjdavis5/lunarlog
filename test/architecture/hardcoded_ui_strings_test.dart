/// Guard: `lib/ui/` may not carry hardcoded UI copy (issues #460, #1004).
///
/// Issue #160 landed the localization scaffolding (delegates, ARB,
/// `AppLocalizations`) on the assumption that shipping English-only was
/// acceptable *for now* — but nothing stopped new screens from adding
/// `const Text('...')` literals, and by issue #460 roughly 150 had
/// accumulated (380 at the time this guard landed). Every literal is
/// untranslated-by-construction and becomes "the later rewrite" epic #179
/// set out to avoid. Issue #1004 then burned the backlog down directory by
/// directory until `lib/ui/` carried none, so the per-file allowlist and
/// its recorded size are gone and the guard is now zero-tolerance.
///
/// **What counts as hardcoded UI copy** (see the scanner library for the
/// implementation, `hardcoded_ui_strings_scanner.dart`):
///
/// * A first-positional string-literal argument to `Text(` or `Tooltip(`
///   — which subsumes `SnackBar(content: Text('...'))`, `AppBar(title:
///   Text('...'))`, and any other widget wrapping a literal-arg `Text`.
///   Const, non-const, raw, and triple-quoted literals all count.
/// * A string-literal value for any identifier in [_uiCopyNamedArgs]
///   written as a named argument or map entry (`labelText: 'Name'`,
///   `title: 'Edit'`, `{label: 'Note'}`) — named-argument copy the
///   positional scan never looks at.
/// * Interpolated literals count **when literal prose survives outside
///   the interpolation** (`'Hi $name'`, `'${count} days'`) — those need
///   an ARB message with a placeholder, not a literal.
/// * Excluded: literals with no ASCII letters outside interpolation —
///   pure symbols/digits/punctuation (`'…'`, `'·'`, `'-'`, `''`) and
///   pure interpolations (`'${date.day}'`, `'$count'`). Those are not
///   copy in any language.
/// * Excluded: anything that is not a literal first argument —
///   `Text(l10n.foo)`, `Text(model.note)`, `Text.rich(...)`,
///   `title: model.title` — and anything inside a comment or a plain
///   source string.
///
/// **The guard is directory-scoped and total.** Every subdirectory of
/// `lib/ui/` is checked in the strict mode (positional *and* named-argument
/// literals), enumerated at test time so a **new** directory cannot start
/// un-localized, and a top-level check holds the whole tree — including
/// `lib/ui/routes.dart` and any other file directly under `lib/ui/` — to
/// the same bar. Add copy to `lib/l10n/app_en.arb`, run `flutter gen-l10n`,
/// and read it via `AppLocalizations.of(context)` (or a `lib/ui/l10n/` copy
/// helper) instead; never a literal.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'hardcoded_ui_strings_scanner.dart';

/// The named-argument identifiers the guard treats as user-facing copy, so
/// `labelText:`, `hintText:`, `title:`, `subtitle:`, `label:`, `message:`,
/// `semanticLabel:` and friends cannot hide a literal the positional
/// `Text(`/`Tooltip(` scanner never looks at.
const Set<String> _uiCopyNamedArgs = {
  'labelText',
  'hintText',
  'helperText',
  'errorText',
  'semanticLabel',
  'semanticsLabel',
  'label',
  'title',
  'subtitle',
  'message',
  'tooltip',
  'header',
  'hint',
};

/// Scans every `.dart` file under [directory] in the strict mode and
/// returns one problem string per user-facing literal, or an empty list
/// when the directory is fully localized. Fails if [directory] holds no
/// files at all, which would otherwise let a typo'd path pass vacuously.
List<String> _hardcodedCopyIn(String directory) {
  final files = Directory(directory)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
  expect(files, isNotEmpty, reason: 'scanned zero files under $directory');

  final problems = <String>[];
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final found = scanHardcodedUiStrings(
      file.readAsStringSync(),
      namedArgs: _uiCopyNamedArgs,
    );
    problems.addAll(found.map((h) => '$path:${h.line}: ${h.value}'));
  }
  return problems;
}

/// Asserts [directory] has no user-facing literals left, under both the
/// positional `Text(`/`Tooltip(` scan and [_uiCopyNamedArgs].
void expectDirectoryFullyLocalized(String directory) {
  final problems = _hardcodedCopyIn(directory);
  expect(
    problems,
    isEmpty,
    reason: '$directory must read every user-facing literal from '
        'AppLocalizations (lib/l10n/app_en.arb + `flutter gen-l10n`). '
        'Problems:\n${problems.join('\n')}',
  );
}

void main() {
  test('lib/ui carries zero hardcoded UI strings', () {
    final problems = _hardcodedCopyIn('lib/ui');
    expect(
      problems,
      isEmpty,
      reason: 'issues #460/#1004: new user-facing copy must come from '
          'AppLocalizations (add the string to lib/l10n/app_en.arb, run '
          '`flutter gen-l10n`, and read it via AppLocalizations.of(context) '
          'or a lib/ui/l10n/ copy helper), never a string literal. '
          'Problems:\n${problems.join('\n')}',
    );
  });

  // Issue #1004: every subdirectory of `lib/ui/` is held to the strict bar
  // individually. The directory list is discovered at test time rather than
  // hand-maintained, so a brand-new `lib/ui/<x>/` directory cannot start
  // un-localized, and a failure names the offending directory.
  test('every directory under lib/ui/ stays fully localized', () {
    final directories = Directory('lib/ui')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.replaceAll('\\', '/'))
        .toList()
      ..sort();
    expect(
      directories,
      isNotEmpty,
      reason: 'scanned zero subdirectories under lib/ui -- check the path',
    );
    for (final directory in directories) {
      expectDirectoryFullyLocalized(directory);
    }
  });

  // Falsification coverage for the detector itself, same posture as
  // `theme_wiring_test.dart`'s "detects the forms a layering violation
  // can take": without this, a scanner that silently stopped matching
  // would leave the scan above vacuously green while the backlog grew.
  group('detector detects the forms hardcoded copy can take', () {
    test('flags literal arguments to Text/Tooltip in all quote styles', () {
      const source = '''
Widget build(BuildContext context) => Column(
  children: [
    const Text('Plain'),
    Text("Double quoted"),
    Text(r'Raw digits'),
    Text(\'\'\'Triple
quoted\'\'\'),
    Tooltip('Adds a layer'),
    SnackBar(content: Text('Saved')),
    Text('Hi \$name'),
    Text('\${count} days'),
    Text('https://example.com/a//b'),
    Text('\${f('nested')} done'),
  ],
);
''';
      final values = scanHardcodedUiStrings(source).map((h) => h.value);
      expect(values, contains('Plain'));
      expect(values, contains('Double quoted'));
      expect(values, contains('Raw digits'));
      expect(values, contains('Triple\nquoted'));
      expect(values, contains('Adds a layer'));
      expect(values, contains('Saved'), reason: 'SnackBar content is a '
          'Text( call and is covered by the same rule');
      expect(values, contains('Hi \$name'));
      expect(values, contains('\${count} days'));
      expect(values, contains('https://example.com/a//b'), reason: 'a // '
          'inside a string literal must not be read as a comment');
      expect(values, contains('''\${f('nested')} done'''));
      expect(values, hasLength(10));
    });

    test('ignores dynamic arguments, symbols, comments, and prose', () {
      const source = '''
/// A doc comment mentioning Text('not really') and Tooltip('nope').
/* Block comment with Text('also not real'). */
Widget build(BuildContext context) {
  final notACopy = "a plain string containing Text('x') itself";
  return Column(
    children: [
      Text(l10n.somethingLocalized),
      Text(controller.text),
      Text.rich(TextSpan(text: 'rich content')),
      const SelectableText('editable'),
      Text(''),
      Text(' '),
      Text('…'),
      Text('·'),
      Text('-'),
      Text('7'),
      Text('\$count'),
      Text('\${date.day}'),
    ],
  );
}
''';
      expect(scanHardcodedUiStrings(source), isEmpty,
          reason: 'localized/dynamic/symbol-only arguments and comment '
              'mentions are not hardcoded UI copy');
    });

    test('flags a multiline literal at its opening quote line', () {
      const source = 'Text(\'\'\'line one\nline two\'\'\');';
      final found = scanHardcodedUiStrings(source);
      expect(found, hasLength(1));
      expect(found.single.line, 1);
      expect(found.single.value, 'line one\nline two');
    });

    test('namedArgs records named-argument and map-entry literals', () {
      const source = '''
TextField(decoration: InputDecoration(labelText: 'Name', hintText: 'e.g. Sam'));
Column(children: [Text('already covered')]);
final map = {label: 'Note'};
''';
      final found = scanHardcodedUiStrings(
        source,
        namedArgs: {'labelText', 'hintText', 'label', 'title'},
      );
      final values = found.map((h) => h.value).toList();
      expect(values, contains('Name'));
      expect(values, contains('e.g. Sam'));
      expect(values, contains('Note'));
      expect(values, contains('already covered'));
      expect(values, hasLength(4));
    });

    test('namedArgs is off by default and ignores dynamic values', () {
      const source = '''
InputDecoration(labelText: 'Name', hintText: someVariable);
ListTile(title: l10n.somethingLocalized, subtitle: 'literal');
''';
      expect(
        scanHardcodedUiStrings(source),
        isEmpty,
        reason: 'the default positional scan must not start seeing named '
            'args on its own',
      );
      final found = scanHardcodedUiStrings(
        source,
        namedArgs: {'labelText', 'hintText', 'title', 'subtitle'},
      );
      final values = found.map((h) => h.value).toList();
      expect(values, contains('Name'));
      expect(values, contains('literal'));
      expect(values, hasLength(2),
          reason: 'a dynamic value is not copy; only literals count');
    });
  });
}
