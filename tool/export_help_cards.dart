/// Exports the bundled help cards to JSON for the marketing site
/// (Issue #1106).
///
/// The how-to guides (#1106) reuse the in-app help cards
/// (`lib/domain/help/help_cards.dart`, issue #139) instead of retyping them:
/// the site's `HelpCard` component renders a card straight from this export,
/// so each explanation of app mechanics has exactly one home. The file is
/// committed, and `test/tool/export_help_cards_test.dart` fails whenever it
/// drifts from the library — the same freshness discipline CI applies to
/// `db.g.dart` and to the #1103 literacy export.
///
/// Run from the repository root:
///
/// ```
/// dart run tool/export_help_cards.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:lunarlog/domain/help/help_cards.dart';

/// Repository-relative path of the generated export.
const String kHelpCardsExportPath = 'site/src/content/help-cards/cards.json';

/// Builds the stable, diff-friendly JSON export of every bundled card.
///
/// Pure — it reads only the const card set and returns a string, so the
/// freshness test can compare the committed file against it in memory.
///
/// Output is a JSON array in library order, 2-space indented with a trailing
/// newline.
String buildHelpCardsExportJson() {
  final cards = [
    for (final card in HelpCards.all)
      {
        'id': card.id,
        'title': card.title,
        'summary': card.summary,
        'body': card.body,
        'source': card.source,
        'reviewDate': card.reviewDate,
        'screens': card.screens,
      },
  ];
  return '${const JsonEncoder.withIndent('  ').convert(cards)}\n';
}

void main() {
  final json = buildHelpCardsExportJson();
  final file = File(kHelpCardsExportPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(json);
  stdout.writeln('Wrote ${file.path} (${json.length} bytes)');
}
