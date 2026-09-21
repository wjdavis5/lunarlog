/// #460 guard: `lib/ui/` may not gain **new** hardcoded UI copy.
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

/// The named-argument identifiers the `lib/ui/sharing` tranche check
/// (issue #1004) treats as user-facing copy. The global backlog scan leaves
/// this empty; the directory-specific test opts in so `labelText:`,
/// `hintText:`, `title:`, `subtitle:`, `label:`, `message:`,
/// `semanticLabel:` and friends cannot hide a literal the positional
/// `Text(`/`Tooltip(` scanner never looks at.
const Set<String> _sharingNamedUiArgs = {
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
/// Issue #1004 (tranche 1) burned `lib/ui/sharing/` down to zero (142
/// literals), so those entries are gone and the recorded size dropped by
/// the same amount (367 - 142 = 225, where 367 is the current main
/// backlog after the widget/health work landed). Every remaining entry is
/// another directory's backlog, owned by a different tranche.
const int _initialAllowlistSize = 225;

/// Exact per-file counts of allowed hardcoded UI string literals under
/// `lib/ui/`, derived by scanning `main` at accd0ee2 (2026-09-14, issue
/// #460). Keys are repo-relative POSIX-style paths.
const Map<String, int> _allowedHardcodedUiLiterals = {
  'lib/ui/account/account_mismatch_screen.dart': 9,
  'lib/ui/account/account_section.dart': 29,
  'lib/ui/account/delete_account_dialog.dart': 8,
  'lib/ui/account/mfa_settings_section.dart': 1,
  'lib/ui/account/mfa_step_up_dialog.dart': 1,
  'lib/ui/account/password_recovery_screen.dart': 4,
  'lib/ui/account/restore_error_screen.dart': 4,
  'lib/ui/account/restoring_screen.dart': 1,
  'lib/ui/account/sign_in_screen.dart': 9,
  'lib/ui/account/upload_consent_screen.dart': 6,
  'lib/ui/account/sync_status_tile.dart': 1,
  'lib/ui/care/care_notes_screen.dart': 14,
  'lib/ui/components/app_shell.dart': 2,
  'lib/ui/components/inline_error.dart': 1,
  'lib/ui/components/today_log_fab.dart': 1,
  'lib/ui/content/cycle_literacy_article_sheet.dart': 4,
  'lib/ui/content/cycle_literacy_library_screen.dart': 2,
  'lib/ui/feedback/attachment_field.dart': 5,
  'lib/ui/feedback/feedback_screen.dart': 6,
  'lib/ui/feedback/support_history_screen.dart': 5,
  'lib/ui/gate/lock_screen.dart': 5,
  'lib/ui/gate/pin_authorization_dialog.dart': 2,
  'lib/ui/gate/pin_settings_screen.dart': 1,
  'lib/ui/help/help_card_view.dart': 2,
  'lib/ui/help/help_library_screen.dart': 1,
  'lib/ui/insights/analysis_tab.dart': 3,
  'lib/ui/insights/phase_insights_card.dart': 3,
  'lib/ui/insights/symptom_trends_section.dart': 12,
  'lib/ui/logging/day_sheet.dart': 1,
  'lib/ui/logging/month_calendar.dart': 1,
  'lib/ui/overview/cycle_history_section.dart': 7,
  'lib/ui/overview/late_resolver.dart': 2,
  'lib/ui/profiles/profile_detail_screen.dart': 4,
  'lib/ui/profiles/profile_dialogs.dart': 9,
  'lib/ui/profiles/profile_picker_screen.dart': 5,
  'lib/ui/settings/clinical_export_tile.dart': 2,
  'lib/ui/settings/csv_export_tile.dart': 2,
  'lib/ui/settings/export_range_picker_sheet.dart': 3,
  'lib/ui/settings/health_sync_screen.dart': 11,
  'lib/ui/settings/import_screen.dart': 4,
  'lib/ui/settings/reminder_settings_screen.dart': 10,
  'lib/ui/settings/your_data_section.dart': 12,
  'lib/ui/startup/fail_closed_screen.dart': 2,
  'lib/ui/web/dev_banner.dart': 8,
};

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

  test('lib/ui carries no hardcoded UI strings beyond the allowlist', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
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

  // Issue #1004 (tranche 1): `lib/ui/sharing/` is fully migrated, so it is
  // held to a stricter bar than the rest of `lib/ui/`. The global scan
  // above only sees positional `Text(`/`Tooltip(` literals; this one also
  // catches named-argument copy the scanner's default mode ignores
  // (`labelText:`, `hintText:`, `title:`, `subtitle:`, `label:`,
  // `message:`, `semanticLabel:`), and it forbids the directory from
  // reappearing in the allowlist at all — so a new literal fails even if
  // someone tries to re-allowlist the file instead of adding an ARB key.
  test('lib/ui/sharing stays fully localized (issue #1004 tranche 1)', () {
    final files = Directory('lib/ui/sharing')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'scanned zero files under lib/ui/sharing');

    final problems = <String>[];
    for (final file in files) {
      final path = file.path.replaceAll('\\', '/');
      final found = scanHardcodedUiStrings(
        file.readAsStringSync(),
        namedArgs: _sharingNamedUiArgs,
      );
      problems.addAll(found.map((h) => '$path:${h.line}: ${h.value}'));
    }

    final sharingAllowlistEntries = _allowedHardcodedUiLiterals.keys
        .where((k) => k.startsWith('lib/ui/sharing/'))
        .toList();
    expect(
      problems,
      isEmpty,
      reason: 'lib/ui/sharing must read every user-facing literal from '
          'AppLocalizations (lib/l10n/app_en.arb + `flutter gen-l10n`). '
          'Problems:\n${problems.join('\n')}',
    );
    expect(
      sharingAllowlistEntries,
      isEmpty,
      reason: 'lib/ui/sharing is fully migrated — do not re-allowlist a '
          'sharing file; add an ARB key instead. Entries:\n'
          '${sharingAllowlistEntries.join('\n')}',
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
  });
}
