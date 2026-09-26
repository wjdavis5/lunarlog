import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

Future<void> pumpSheet(
  WidgetTester tester,
  CycleLiteracyArticle article,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.lightTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: CycleLiteracyArticleSheet(article: article),
    ),
  ));
}

/// Scrolls the sheet far enough to reveal the provenance footer.
Future<void> scrollToFooter(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.textContaining('Last reviewed:'),
    find.byType(ListView),
    const Offset(0, -300),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Issue #1006: provenance footer says "Last reviewed", not '
      '"Last clinical review"', (tester) async {
    final article = CycleLiteracyLibrary.menstrualCyclePhases;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(
      find.textContaining('Last reviewed: ${article.reviewDate}'),
      findsOneWidget,
    );
    expect(find.textContaining('Last clinical review'), findsNothing);
  });

  testWidgets('Issue #1103: one line per source, publisher — title',
      (tester) async {
    final article = CycleLiteracyLibrary.menstrualCyclePhases;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(article.sources, isNotEmpty);
    for (final source in article.sources) {
      final expected = source.identifier == null
          ? '${source.publisher.displayName} — ${source.title}'
          : '${source.publisher.displayName} — ${source.title} '
              '(${source.identifier})';
      expect(find.text(expected), findsOneWidget);
    }

    // The old single free-text "Source: …" line is gone.
    expect(find.textContaining('Source: '), findsNothing);
  });

  testWidgets('Issue #1103: identifier-bearing sources render in parentheses',
      (tester) async {
    final article = CycleLiteracyLibrary.firstPeriodsFirstTwoYears;

    await pumpSheet(tester, article);
    await scrollToFooter(tester);

    expect(
      find.textContaining('(Committee Opinion No. 651)'),
      findsOneWidget,
    );
  });
}
