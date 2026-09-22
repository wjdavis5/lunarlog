/// #460 guard: `lib/ui/` (and, since the #1046 follow-up, the app-shell
/// copy in `lib/app.dart`) may not gain **new** hardcoded UI copy.
///
/// Issue #160 landed the localization scaffolding (delegates, ARB,
/// `AppLocalizations`) on the assumption that shipping English-only was
/// acceptable *for now* — but nothing stopped new screens from adding
/// `const Text('...')` literals, and by issue #460 roughly 150 had
/// accumulated (380 at the time this guard landed; the backlog grew while
/// the issue was open). Every literal here is untranslated-by-construction
/// and becomes "the later rewrite" epic #179 set out to avoid.
///
/// **What counts as hardcoded UI copy** (see the scanner library for the
/// implementation, `hardcoded_ui_strings_scanner.dart`):
///
/// * A first-positional string-literal argument to `Text(` or `Tooltip(`
///   — which subsumes `SnackBar(content: Text('...'))`, `AppBar(title:
///   Text('...'))`, and any other widget wrapping a literal-arg `Text`.
///   Const, non-const, raw, and triple-quoted literals all count.
/// * Interpolated literals count **when literal prose survives outside
///   the interpolation** (`'Hi $name'`, `'${count} days'`) — those need
///   an ARB message with a placeholder, not a literal.
/// * Excluded: literals with no ASCII letters outside interpolation —
///   pure symbols/digits/punctuation (`'…'`, `'·'`, `'-'`, `''`) and
///   pure interpolations (`'${date.day}'`, `'$count'`). Those are not
///   copy in any language, and excluding them keeps this allowlist an
///   honest measure of translatable strings.
/// * Excluded: anything that is not a literal first argument —
///   `Text(l10n.foo)`, `Text(model.note)`, `Text.rich(...)` — and
///   anything inside a comment or a plain source string.
///
/// **The allowlist** below is the current backlog, one entry per file
/// with its exact literal count, so the burn-down (issue #460's
/// follow-on, splittable per screen) is measurable: replace a literal
/// with an `AppLocalizations` getter (add it to `lib/l10n/app_en.arb`,
/// run `flutter gen-l10n`), then shrink or remove the file's entry and
/// decrement [_initialAllowlistSize]. The counts are asserted exactly —
/// growing a file's count fails (a new hardcoded string), and shrinking
/// one without updating the entry also fails (the ratchet: the recorded
/// size must always be the true remaining backlog, so a stale entry
/// cannot hide movement elsewhere).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'hardcoded_ui_strings_scanner.dart';

/// The named-argument identifiers every fully-migrated directory check
/// (issue #1004) treats as user-facing copy. The global backlog scan leaves
/// this empty; the directory-specific tests opt in so `labelText:`,
/// `hintText:`, `title:`, `subtitle:`, `label:`, `message:`,
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

/// The backlog this guard landed with (issue #460). Decrement it with
/// every burn-down PR; the assertion below keeps it equal to the sum of
/// the per-file entries so both stay honest.
///
/// Issue #1004 burned `lib/ui/sharing/` (tranche 1), `lib/ui/account/` and
/// `lib/ui/settings/` (tranche 2), `lib/ui/profiles/`, `lib/ui/feedback/`,
/// `lib/ui/gate/`, `lib/ui/care/` (tranche 3), `lib/ui/logging/`,
/// `lib/ui/help/`, `lib/ui/content/`, `lib/ui/startup/`, `lib/ui/web/`
/// (tranche 4b), and `lib/ui/components/`, `lib/ui/overview/`,
/// `lib/ui/insights/` (tranche 4a) down to zero, so every entry is gone and
/// the recorded size dropped to 0: 355 (main, after the widget/health/#1003
/// work) - 134 (tranche 1) - 113 (tranche 2) - 56 (tranche 3) - 8 (epic #831
/// moved `lib/ui/web/dev_banner.dart` onto `AppLocalizations`) - 13
/// (tranche 4b) - 31 (tranche 4a) = 0. The allowlist is now empty — any new
/// hardcoded literal under `lib/ui/` fails this guard.
const int _initialAllowlistSize = 0;

/// Exact per-file counts of allowed hardcoded UI string literals under
/// `lib/ui/`, derived by scanning `main` at accd0ee2 (2026-09-14, issue
/// #460). Keys are repo-relative POSIX-style paths. Empty as of issue #1004
/// tranche 4a: every directory is fully localized.
const Map<String, int> _allowedHardcodedUiLiterals = {};

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

/// Asserts [directory] has no user-facing literals left, under both the
/// positional `Text(`/`Tooltip(` scan and [\_migratedNamedUiArgs], and that
/// none of its files reappeared in the allowlist.
void expectDirectoryFullyLocalized(String directory, String label) {
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
      namedArgs: _migratedNamedUiArgs,
    );
    problems.addAll(found.map((h) => '$path:${h.line}: ${h.value}'));
  }

  final allowlistEntries =
      _allowedHardcodedUiLiterals.keys.where((k) => k.startsWith('$directory/'));
  expect(
    problems,
    isEmpty,
    reason: '$directory must read every user-facing literal from '
        'AppLocalizations (lib/l10n/app_en.arb + `flutter gen-l10n`). '
        'Problems:\n${problems.join('\n')}',
  );
  expect(
    allowlistEntries,
    isEmpty,
    reason: '$directory is fully migrated — do not re-allowlist a $label '
        'file; add an ARB key instead. Entries:\n'
        '${allowlistEntries.join('\n')}',
  );
}

void main() {
  test('allowlist size is recorded and matches its entries', () {
    expect(
      _allowedHardcodedUiLiterals.values.fold<int>(0, (a, b) => a + b),
      _initialAllowlistSize,
      reason: '_initialAllowlistSize must equal the sum of the per-file '
          'entries so the recorded backlog size cannot drift from the '
          'allowlist itself',
    );
  });

  test('lib/ carries no hardcoded UI strings beyond the allowlist', () {
    // Issue #1046 follow-up: `lib/app.dart` holds app-shell UI copy (the
    // pending-invite banner) just outside `lib/ui/`, so the #460 guard
    // scans it too. The scanner takes source text, not a path, so adding
    // the file to this list is the clean extension -- nothing in the
    // scanner changes.
    final files = [
      ...Directory('lib/ui')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart')),
      File('lib/app.dart'),
    ]..sort((a, b) => a.path.compareTo(b.path));
    expect(
      files,
      isNotEmpty,
      reason: 'scanned zero files under lib/ui -- check the path',
    );

    final actual = <String, List<HardcodedUiString>>{};
    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      final found = scanHardcodedUiStrings(file.readAsStringSync());
      if (found.isNotEmpty) actual[path] = found;
    }

    final problems = <String>[];
    for (final entry in actual.entries) {
      final allowed = _allowedHardcodedUiLiterals[entry.key];
      if (allowed == null) {
        problems.add(
          '${entry.key}: ${entry.value.length} hardcoded literal(s), but '
          'the file is not in the allowlist at all',
        );
      } else if (entry.value.length > allowed) {
        problems.add(
          '${entry.key}: ${entry.value.length} hardcoded literals, '
          'allowlist says $allowed — new hardcoded UI copy:\n'
          '  ${entry.value.join('\n  ')}',
        );
      } else if (entry.value.length < allowed) {
        problems.add(
          '${entry.key}: ${entry.value.length} hardcoded literals remain, '
          'allowlist says $allowed — burn-down detected; shrink the entry '
          '(and _initialAllowlistSize) to match',
        );
      }
    }
    for (final path in _allowedHardcodedUiLiterals.keys) {
      if (!actual.containsKey(path)) {
        problems.add(
          '$path: allowlisted with '
          '${_allowedHardcodedUiLiterals[path]} literal(s) but the file '
          'now has none (or no longer exists) — remove the entry and '
          'decrement _initialAllowlistSize',
        );
      }
    }

    expect(
      problems,
      isEmpty,
      reason: 'issue #460: new user-facing copy must come from '
          'AppLocalizations (add the string to lib/l10n/app_en.arb, run '
          '`flutter gen-l10n`, and read it via AppLocalizations.of(context) '
          'or a lib/ui/l10n/ copy helper), never a string literal. '
          'Problems:\n${problems.join('\n')}',
    );
  });

  // Issue #1004: each fully-migrated directory is held to a stricter bar
  // than the rest of `lib/ui/`. The global scan above only sees positional
  // `Text(`/`Tooltip(` literals; this one also catches named-argument copy
  // the scanner's default mode ignores (`labelText:`, `hintText:`, `title:`,
  // `subtitle:`, `label:`, `message:`, `semanticLabel:`), and it forbids the
  // directory from reappearing in the allowlist at all — so a new literal
  // fails even if someone tries to re-allowlist the file instead of adding
  // an ARB key. Tranche 1 did `lib/ui/sharing/`; tranche 2 did `account/`
  // and `settings/`; tranche 3 did `profiles/`, `feedback/`, `gate/`, and
  // `care/`; tranche 4b did `logging/`, `help/`, `content/`, `startup/`, and
  // `web/`; tranche 4a did `components/`, `overview/`, and `insights/`.
  test('lib/ui/sharing stays fully localized (issue #1004 tranche 1)',
      () => expectDirectoryFullyLocalized('lib/ui/sharing', 'sharing'));

  test('lib/ui/account stays fully localized (issue #1004 tranche 2)',
      () => expectDirectoryFullyLocalized('lib/ui/account', 'account'));

  test('lib/ui/settings stays fully localized (issue #1004 tranche 2)',
      () => expectDirectoryFullyLocalized('lib/ui/settings', 'settings'));

  test('lib/ui/profiles stays fully localized (issue #1004 tranche 3)',
      () => expectDirectoryFullyLocalized('lib/ui/profiles', 'profiles'));

  test('lib/ui/feedback stays fully localized (issue #1004 tranche 3)',
      () => expectDirectoryFullyLocalized('lib/ui/feedback', 'feedback'));

  test('lib/ui/gate stays fully localized (issue #1004 tranche 3)',
      () => expectDirectoryFullyLocalized('lib/ui/gate', 'gate'));

  test('lib/ui/care stays fully localized (issue #1004 tranche 3)',
      () => expectDirectoryFullyLocalized('lib/ui/care', 'care'));

  test('lib/ui/logging stays fully localized (issue #1004 tranche 4b)',
      () => expectDirectoryFullyLocalized('lib/ui/logging', 'logging'));

  test('lib/ui/help stays fully localized (issue #1004 tranche 4b)',
      () => expectDirectoryFullyLocalized('lib/ui/help', 'help'));

  test('lib/ui/content stays fully localized (issue #1004 tranche 4b)',
      () => expectDirectoryFullyLocalized('lib/ui/content', 'content'));

  test('lib/ui/startup stays fully localized (issue #1004 tranche 4b)',
      () => expectDirectoryFullyLocalized('lib/ui/startup', 'startup'));

  test('lib/ui/web stays fully localized (issue #1004 tranche 4b)',
      () => expectDirectoryFullyLocalized('lib/ui/web', 'web'));

  test('lib/ui/components stays fully localized (issue #1004 tranche 4a)',
      () => expectDirectoryFullyLocalized('lib/ui/components', 'components'));

  test('lib/ui/overview stays fully localized (issue #1004 tranche 4a)',
      () => expectDirectoryFullyLocalized('lib/ui/overview', 'overview'));

  test('lib/ui/insights stays fully localized (issue #1004 tranche 4a)',
      () => expectDirectoryFullyLocalized('lib/ui/insights', 'insights'));

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
        reason: 'the global backlog scan must not start seeing named args',
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
