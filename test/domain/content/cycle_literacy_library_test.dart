import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';

void main() {
  group('CycleLiteracyLibrary catalog integrity', () {
    test('contains bundled articles with complete clinical citations and dates', () {
      expect(CycleLiteracyLibrary.allArticles.length, greaterThanOrEqualTo(7));

      for (final article in CycleLiteracyLibrary.allArticles) {
        expect(article.id, isNotEmpty);
        expect(article.title, isNotEmpty);
        expect(article.summary, isNotEmpty);
        expect(article.readingTimeMinutes, greaterThan(0));
        expect(article.source, isNotEmpty, reason: 'Must have authoritative clinical source');
        expect(article.reviewDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: 'Review date must be ISO-8601 YYYY-MM-DD');
        expect(article.sections, isNotEmpty);
        expect(article.relatedSubphases, isNotEmpty);

        for (final section in article.sections) {
          expect(section.heading, isNotEmpty);
          expect(section.paragraphs, isNotEmpty);
          for (final paragraph in section.paragraphs) {
            expect(paragraph.trim(), isNotEmpty);
          }
        }
      }
    });

    test('all article IDs are unique', () {
      final ids = CycleLiteracyLibrary.allArticles.map((a) => a.id).toList();
      final uniqueIds = ids.toSet();
      expect(ids.length, uniqueIds.length);
    });

    test('medical disclaimer is standard across articles', () {
      expect(CycleLiteracyArticle.kMedicalDisclaimer, contains('educational'));
      expect(CycleLiteracyArticle.kMedicalDisclaimer, contains('does not constitute medical advice'));
    });
  });

  group('CycleLiteracyLibrary query methods', () {
    test('getArticleById returns matching article or null', () {
      final phases = CycleLiteracyLibrary.getArticleById('menstrual-cycle-phases');
      expect(phases, isNotNull);
      expect(phases!.title, contains('Phases'));

      final nonExistent = CycleLiteracyLibrary.getArticleById('unknown-article-xyz');
      expect(nonExistent, isNull);
    });

    test('getArticlesForSubphase covers every subphase', () {
      for (final subphase in CycleSubphase.values) {
        final articles = CycleLiteracyLibrary.getArticlesForSubphase(subphase);
        expect(articles, isNotEmpty,
            reason: 'Subphase ${subphase.displayName} should have at least 1 related article');
      }
    });

    test('getArticlesByCategory returns relevant articles', () {
      for (final category in CycleLiteracyCategory.values) {
        final articles = CycleLiteracyLibrary.getArticlesByCategory(category);
        expect(articles, isNotEmpty,
            reason: 'Category ${category.displayName} should have articles');
        for (final article in articles) {
          expect(article.category, category);
        }
      }
    });
  });
}
