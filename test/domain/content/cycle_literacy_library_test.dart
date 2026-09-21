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

  group('Issue #1006 accuracy and coverage', () {
    String paragraph(String articleId, String headingSubstring) {
      final article = CycleLiteracyLibrary.getArticleById(articleId)!;
      return article.sections
          .firstWhere((s) => s.heading.contains(headingSubstring))
          .paragraphs
          .join(' ');
    }

    test('BBT conversion uses the correct Celsius range', () {
      final luteal = paragraph('luteal-phase-and-progesterone', 'Thermal');
      expect(luteal, contains('0.3°C to 0.6°C'),
          reason: '0.5–1.0 °F converts to ~0.3–0.6 °C, not 0.2–0.5 °C');
      expect(luteal, isNot(contains('0.2°C to 0.5°C')));
    });

    test('follicular summary hedges the energy claim', () {
      final article =
          CycleLiteracyLibrary.getArticleById('understanding-follicular-phase')!;
      expect(article.summary, isNot(contains('elevates energy levels')));
      expect(article.summary, contains('often'));
    });

    test('PMS mechanism is stated as a hypothesis, not settled fact', () {
      final pms = paragraph('pms-and-progesterone', 'Serotonin');
      expect(pms, contains('may contribute'));
      expect(pms, contains('researchers think'));
      expect(pms, isNot(contains('explaining premenstrual')));
    });

    test('cycle-length article covers first cycles and red flags', () {
      final article =
          CycleLiteracyLibrary.getArticleById('cycle-length-variability')!;
      final headings = article.sections.map((s) => s.heading).toList();
      expect(headings, contains('The First Few Years'));
      expect(headings, contains('When to Ask a Doctor'));

      final body = article.sections.expand((s) => s.paragraphs).join(' ');
      expect(body, contains('21 to 45 days'));
      expect(body, contains('three months'));
      expect(body, contains('longer than about a week'));
      expect(body, contains('every hour'));
      expect(article.source, contains('ACOG'));
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
