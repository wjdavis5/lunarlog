import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/content/cycle_literacy_article_sheet.dart';
import 'package:lunarlog/ui/theme/app_theme.dart';

void main() {
  testWidgets(
      'Issue #1006: provenance footer says "Last reviewed", not '
      '"Last clinical review"', (tester) async {
    final article = CycleLiteracyLibrary.menstrualCyclePhases;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: CycleLiteracyArticleSheet(article: article),
      ),
    ));

    await tester.dragUntilVisible(
      find.textContaining('Last reviewed:'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Last reviewed: ${article.reviewDate}'),
      findsOneWidget,
    );
    expect(find.textContaining('Last clinical review'), findsNothing);
  });
}
