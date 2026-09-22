/// Guard: `lib/ui/` (and, since the #1046 follow-up, the app-shell copy in
/// `lib/app.dart`) may not carry hardcoded UI copy (issues #460, #1004).
///
/// Issue #160 landed the localization scaffolding (delegates, ARB,
/// `AppLocalizations`) on the assumption that shipping English-only was
/// acceptable *for now* — but nothing stopped new screens from adding
/// `const Text('...')` literals, and by issue #460 roughly 150 had
/// accumulated (380 at the time this guard landed; the backlog grew while
/// the issue was open). Every literal here is untranslated-by-construction
/// and becomes "the later rewrite" epic #179 set out to avoid. Issue #1004
/// then burned the whole backlog down directory by directory — including
/// the helper-built copy that lives outside a `Text(` argument (tranche 5)
/// — until the per-file allowlist was empty, so the allowlist and its
/// recorded-size ratchet are gone and the guard is zero-tolerance.
///
/// **What counts as hardcoded UI copy** (see the scanner library for the
/// implementation, `hardcoded_ui_strings_scanner.dart`):
///
/// * A first-positional string-literal argument to `Text(` or `Tooltip(`
///   — which subsumes `SnackBar(content: Text('...'))`, `AppBar(title:
///   Text('...'))`, and any other widget wrapping a literal-arg `Text`.
///   Const, non-const, raw, and triple-quoted literals all count.
/// * A string-literal value for any identifier in [_migratedNamedUiArgs]
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
/// `lib/ui/` is checked in the strict mode, enumerated at test time so a
/// new directory cannot start un-localized, and a top-level check holds the
/// whole tree — including `lib/ui/routes.dart` and `lib/app.dart` — to the
/// same bar. A second ratchet ([_helperCopyFileLiterals]) covers the
/// helper-built copy modules whose literals never reach a `Text(`
/// argument. Add copy to `lib/l10n/app_en.arb`, run `flutter gen-l10n`,
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
const Set<String> _migratedNamedUiArgs = {
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

/// Issue #1004 (tranche 5): the copy modules whose copy the positional
/// `Text(`/`Tooltip(` scan structurally cannot see — string consts and
/// copy tables resolved outside a `Text(` argument — are held to the
/// strictest bar in this suite: **every** string literal in the file
/// (comment-aware, interpolation-aware; directive URIs excluded) must be
/// one of the enumerated non-copy literals below, and every entry must
/// still occur (exact multiset match, so removing a literal requires
/// shrinking the entry too). The tranche migrated ~120 helper-built copy
/// strings out of these files; any new literal — copy or not — fails
/// until a reviewed entry explains it.
///
/// Non-copy categories found in these files: `ValueKey`/`ValueKey`
/// parameter names (test handles), `debugPrint`/`StateError`
/// observability strings that never render (`lunarlog …:`,
/// `unreachable: …`, `No … available`), `intl` date patterns in
/// `dates.dart` (`EEEE d MMM y` and friends — format codes, not copy),
/// the branded asset path and font name in `google_sign_in_button.dart`,
/// and the defensive `'start'`/`'end'` placeholder fallbacks for a
/// malformed custom PDF range the picker itself cannot produce.
const Map<String, List<String>> _helperCopyFileLiterals = {
  'lib/ui/account/sync_status_tile.dart': [
    'sync-status',
    'sync-status-glyph',
    'sync-status-snackbar',
  ],
  'lib/ui/account/account_section.dart': [
    r'unreachable: $failure is not a "nothing was deleted" kind',
    r'unreachable: $failure is not a "data already deleted" kind',
    r'unreachable: $failure is not an "other" kind',
    'passkey',
    'account-identity',
    'account-link-error',
    'account-add-apple',
    'account-add-google',
    'account-add-passkey',
    'account-sign-in',
    'account-sync-now',
    'account-sign-out',
    'account-sign-out-everywhere',
    'account-delete',
    'account-delete-error',
    r'account-remove-$provider',
    'lunarlog account: no gate to re-authenticate with',
    r'lunarlog account: link failed (${error.runtimeType})',
    'lunarlog account: no gate to re-authenticate with',
    'account-remove-confirm',
    r'lunarlog account: unlink failed (${error.runtimeType})',
    'lunarlog account: no device reset available',
    'account-sign-out-sync',
    'account-sign-out-discard',
    'account-sign-out-confirm',
    'account-sign-out-everywhere-confirm',
    'lunarlog account: no gate to re-authenticate with',
    'lunarlog account: no deletion service configured',
    r'lunarlog account: delete failed (${error.runtimeType})',
  ],
  'lib/ui/account/google_sign_in_button.dart': [
    'assets/branding/google_g_logo.png',
    'Roboto',
  ],
  'lib/ui/account/export_account_collaborator.dart': [],
  'lib/ui/settings/export_range_picker_sheet.dart': [
    'export-range-cancel',
    'export-range-confirm',
    r'export-range-preset-${preset.name}',
    'export-range-custom-start',
    'export-range-custom-end',
  ],
  'lib/ui/settings/csv_export_tile.dart': [
    r'lunarlog csv-export: profiles watch failed (${error.runtimeType})',
    'csv-export-tile',
    'csv-export-error',
    r'csv-export-profile-${profile.id}',
    'No CsvExportWriter or collaborator available',
    r'lunarlog csv-export: export failed (${error.runtimeType})',
  ],
  'lib/ui/settings/clinical_export_tile.dart': [
    r'lunarlog clinical-export: profiles watch failed (${error.runtimeType})',
    'clinical-export-fhir',
    'clinical-export-fhir-error',
    r'clinical-export-fhir-profile-${profile.id}',
    r'lunarlog clinical-export: export failed (${error.runtimeType})',
  ],
  'lib/ui/settings/clinical_pdf_export_tile.dart': [
    'lunarlog clinical-pdf: profiles watch failed ',
    'clinical-pdf-export',
    'clinical-pdf-export-error',
    r'clinical-pdf-export-profile-${profile.id}',
    r'lunarlog clinical-pdf: export failed (${error.runtimeType})',
    'No ClinicalPdfWriter or collaborator available',
    'start',
    'end',
  ],
  'lib/ui/settings/health_sync_screen.dart': [
    'health-sync-permission-status',
    'health-sync-open-settings',
    'health-sync-confirm-bind',
    'health-sync-confirm-unbind',
    'health-sync-import-summary',
    'health-sync-loading',
    'health-sync-load-error',
    'health-sync-forward-only-copy',
    'health-sync-flow-collapse-copy',
    'health-sync-symptoms-copy',
    'health-sync-revocation-copy',
    'health-sync-import-only-copy',
    'health-sync-symptoms-android-limitation',
    'health-sync-full-history-copy',
    'health-sync-import-tile',
    'health-sync-import-progress',
    'health-sync-unbind-tile',
    r'health-sync-profile-${profile.id}',
    'health-sync-bound-check',
  ],
  'lib/ui/settings/import_screen.dart': [
    r'lunarlog import: pick/parse failed (${error.runtimeType})',
    'lunarlog import: picked file exceeds the size cap',
    r'lunarlog import: clue read failed (${error.runtimeType})',
    r'lunarlog import: clue apply failed (${error.runtimeType})',
    r'lunarlog import: planning failed (${error.runtimeType})',
    'lunarlog import: apply aborted, stale plan',
    r'lunarlog import: apply failed (${error.runtimeType})',
    'import-pick-button',
    'import-pick-error',
    'clue-password-field',
    'clue-password-error',
    'clue-password-cancel',
    'clue-password-continue',
    'clue-new-profile-name',
    'clue-profile-dropdown',
    'clue-preview-summary',
    'clue-preview-policy',
    'clue-preview-summary-lines',
    'clue-preview-error',
    'clue-preview-cancel',
    'clue-preview-confirm',
    'clue-result-summary',
    'clue-result-done',
    'import-preview-summary',
    'import-preview-policy',
    'import-preview-plan',
    'import-preview-rejected',
    'import-preview-skipped',
    'import-preview-shared-guardian',
    'import-preview-error',
    'import-preview-cancel',
    'import-preview-confirm',
    'import-result-summary',
    'import-result-skipped',
    'import-result-done',
  ],
  'lib/ui/profiles/profile_dialogs.dart': [
    'irregular-framing-toggle',
    'irregular-framing-hint',
    'edit-minor-checkbox',
    'edit-minor-derived',
    'edit-due-date-field',
    'edit-due-date-value',
    'edit-due-date-hint',
    'edit-postpartum-birth-date-field',
    'edit-postpartum-birth-date-value',
    'edit-postpartum-birth-date-hint',
    'care-mode-label',
    'care-mode-dropdown',
    'care-mode-hint',
    'edit-birth-year-field',
    'edit-lifecycle-label',
    'edit-lifecycle-dropdown',
    'edit-birth-control-label',
    'edit-birth-control-dropdown',
  ],
  'lib/ui/care/guardian_notes_section.dart': [
    'guardian-notes-disclosure',
    'guardian-note-field',
    'guardian-note-remove',
    'guardian-note-save',
    r'guardian-note-${note.id}',
  ],
  'lib/ui/l10n/dates.dart': [
    'en',
    'MMMM d, y',
    'MMMM d',
    'd',
    'M',
    'EEE d MMM',
    'EEE MMM d',
    'EEE d MMM',
    'EEE MMM d',
    'EEE d MMM y',
    'EEE MMM d y',
    'EEE d MMM y',
    'EEE MMM d y',
    'd MMM',
    'MMM d',
    'd MMM',
    'MMM d',
    'MMMM',
    'MMM',
    'EEEE',
    'EEEE',
  ],
};

/// Scans every `.dart` file under [directory] (recursively), plus any
/// [extraFiles], in the strict mode — the positional `Text(`/`Tooltip(`
/// scan and [_migratedNamedUiArgs] — and returns one problem string per
/// user-facing literal, or an empty list when everything is localized.
/// Fails if it found no files at all, which would otherwise let a typo'd
/// path pass vacuously.
List<String> _hardcodedCopyIn(
  String directory, {
  List<File> extraFiles = const [],
}) {
  final files = <File>[
    ...Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
    ...extraFiles,
  ];
  expect(files, isNotEmpty, reason: 'scanned zero files under $directory');

  final problems = <String>[];
  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final found = scanHardcodedUiStrings(
      file.readAsStringSync(),
      namedArgs: _migratedNamedUiArgs,
    );
    problems.addAll(found.map((h) => '$path:${h.line}: ${h.value}'));
  }
  return problems;
}

/// Asserts [directory] has no user-facing literals left, under both the
/// positional `Text(`/`Tooltip(` scan and [_migratedNamedUiArgs].
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
  test('lib/ carries zero hardcoded UI strings', () {
    // Issue #1046 follow-up: `lib/app.dart` holds app-shell UI copy (the
    // pending-invite banner) just outside `lib/ui/`, so the #460 guard
    // scans it too. The scanner takes source text, not a path, so adding
    // the file to this list is the clean extension -- nothing in the
    // scanner changes.
    final problems = _hardcodedCopyIn(
      'lib/ui',
      extraFiles: [File('lib/app.dart')],
    );
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

  // Issue #1004 (tranche 5): the copy modules whose copy was built
  // OUTSIDE a `Text(` argument — string consts, copy tables, validators —
  // are held to an exact all-literals ratchet: every string literal the
  // file contains must be one of the enumerated non-copy entries, and
  // every entry must still occur. A new literal (copy or not) fails; a
  // removed one fails too, so the lists cannot rot.
  test('helper copy modules contain only enumerated non-copy literals',
      () {
    final problems = <String>[];
    for (final entry in _helperCopyFileLiterals.entries) {
      final file = File(entry.key.replaceAll('/', Platform.pathSeparator));
      if (!file.existsSync()) {
        problems.add('${entry.key}: file no longer exists - drop the entry');
        continue;
      }
      final found = allSourceStringLiterals(file.readAsStringSync())
          .map((h) => h.value)
          .toList();
      final remainingFound = found.toList();
      final remainingAllowed = entry.value.toList();
      for (final v in entry.value) {
        remainingFound.remove(v);
      }
      for (final v in found) {
        remainingAllowed.remove(v);
      }
      if (remainingFound.isNotEmpty || remainingAllowed.isNotEmpty) {
        problems.add(
          '${entry.key} drifts from its allowlist:',
        );
        problems
            .addAll(remainingFound.map((v) => '  + not allowlisted: "$v"'));
        problems.addAll(
            remainingAllowed.map((v) => '  - allowlisted but gone: "$v"'));
      }
    }
    expect(
      problems,
      isEmpty,
      reason: 'issue #1004 tranche 5: these copy modules were fully '
          'migrated to the arb; a new string literal here (copy OR '
          'non-copy) must get a reviewed allowlist entry - or better, an '
          'ARB key via `flutter gen-l10n`. Problems:\n'
          '${problems.join('\n')}',
    );
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

    test('allSourceStringLiterals sees copy outside Text( position and '
        'skips comments, directive URIs, and symbol-only literals',
        () {
      const source = '''
import 'package:flutter/material.dart';
export 'src/thing.dart';
part 'thing.g.dart';

/// A doc comment mentioning Text('not really') and kThing = 'not copy'.
const String kThingCopy = 'Hardcoded helper copy';
String f() => 'returned copy';
final map = {'key': 'map copy'};
Widget w() => Text(l10n.localized);
var x = 'https://example.com/a//b';
var y = 42;
''';
      final values =
          allSourceStringLiterals(source).map((h) => h.value).toList();
      expect(values, contains('Hardcoded helper copy'),
          reason: 'a const initializer is exactly the tranche-5 target');
      expect(values, contains('returned copy'),
          reason: 'a returned literal is exactly the tranche-5 target');
      expect(values, contains('key'),
          reason: 'the strict scan cannot tell a map key from copy - '
              'both are enumerated in the per-file allowlists');
      expect(values, contains('map copy'),
          reason: 'map-entry literals count too');
      expect(values, contains('https://example.com/a//b'),
          reason: 'a // inside a literal is not a comment');
      expect(
        values.where((v) => v.startsWith('package:') || v.startsWith('src/')),
        isEmpty,
        reason: 'directive URIs are not literals at all');
      expect(values.where((v) => v.contains('not really')), isEmpty,
          reason: 'comment mentions never count');
      expect(values, hasLength(5));
    });
  });
}
