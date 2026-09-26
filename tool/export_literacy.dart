/// Exports the bundled cycle-literacy library to JSON for the marketing site
/// (Issue #1103).
///
/// The site (#1099) reads `site/src/content/literacy/articles.json` directly
/// as its content collection, which makes the in-app library the single
/// source of truth for both surfaces. The file is committed, and
/// `test/tool/export_literacy_test.dart` fails whenever it drifts from the
/// library — the same freshness discipline CI applies to `db.g.dart`.
///
/// Run from the repository root:
///
/// ```
/// dart run tool/export_literacy.dart
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:lunarlog/domain/content/cycle_literacy_library.dart';

/// Repository-relative path of the generated export.
const String kLiteracyExportPath = 'site/src/content/literacy/articles.json';

/// Builds the stable, diff-friendly JSON export of every bundled article.
///
/// Pure — it reads only the const library and returns a string, so the
/// freshness test can compare the committed file against it in memory.
///
/// Output is a JSON array in library order, 2-space indented with a trailing
/// newline.
String buildLiteracyExportJson() {
  final articles = [
    for (final article in CycleLiteracyLibrary.allArticles)
      _articleToJson(article),
  ];
  return '${const JsonEncoder.withIndent('  ').convert(articles)}\n';
}

Map<String, Object?> _articleToJson(CycleLiteracyArticle article) => {
  'id': article.id,
  'title': article.title,
  'summary': article.summary,
  'category': {
    'name': article.category.name,
    'displayName': article.category.displayName,
  },
  'audience': article.audience.name,
  'readingTimeMinutes': article.readingTimeMinutes,
  'sections': [
    for (final section in article.sections)
      {'heading': section.heading, 'paragraphs': section.paragraphs},
  ],
  'sources': [
    for (final source in article.sources) _sourceToJson(source),
  ],
  'reviewDate': article.reviewDate,
  'relatedSubphases': [
    for (final subphase in article.relatedSubphases) subphase.name,
  ],
  'disclaimer': CycleLiteracyArticle.kMedicalDisclaimer,
};

Map<String, Object?> _sourceToJson(ArticleSource source) => {
  'publisher': source.publisher.name,
  'publisherName': source.publisher.displayName,
  'title': source.title,
  'identifier': source.identifier,
  'url': source.url,
  'retrieved': source.retrieved,
};

void main() {
  final json = buildLiteracyExportJson();
  final file = File(kLiteracyExportPath)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(json);
  stdout.writeln('Wrote ${file.path} (${json.length} bytes)');
}
