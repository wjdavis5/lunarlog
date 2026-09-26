import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';

void main() {
  group('CycleLiteracyLibrary catalog integrity', () {
    test(
      'contains bundled articles with complete clinical citations and dates',
      () {
        expect(
          CycleLiteracyLibrary.allArticles.length,
          greaterThanOrEqualTo(7),
        );

        for (final article in CycleLiteracyLibrary.allArticles) {
          expect(article.id, isNotEmpty);
          expect(article.title, isNotEmpty);
          expect(article.summary, isNotEmpty);
          expect(article.readingTimeMinutes, greaterThan(0));
          expect(
            article.source,
            isNotEmpty,
            reason: 'Must have authoritative clinical source',
          );
          expect(
            article.reviewDate,
            matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: 'Review date must be ISO-8601 YYYY-MM-DD',
          );
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
      },
    );

    test('all article IDs are unique', () {
      final ids = CycleLiteracyLibrary.allArticles.map((a) => a.id).toList();
      final uniqueIds = ids.toSet();
      expect(ids.length, uniqueIds.length);
    });

    test('medical disclaimer is standard across articles', () {
      expect(CycleLiteracyArticle.kMedicalDisclaimer, contains('educational'));
      expect(
        CycleLiteracyArticle.kMedicalDisclaimer,
        contains('does not constitute medical advice'),
      );
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
      expect(
        luteal,
        contains('0.3°C to 0.6°C'),
        reason: '0.5–1.0 °F converts to ~0.3–0.6 °C, not 0.2–0.5 °C',
      );
      expect(luteal, isNot(contains('0.2°C to 0.5°C')));
    });

    test('follicular summary hedges the energy claim', () {
      final article = CycleLiteracyLibrary.getArticleById(
        'understanding-follicular-phase',
      )!;
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
      final article = CycleLiteracyLibrary.getArticleById(
        'cycle-length-variability',
      )!;
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
      final phases = CycleLiteracyLibrary.getArticleById(
        'menstrual-cycle-phases',
      );
      expect(phases, isNotNull);
      expect(phases!.title, contains('Phases'));

      final nonExistent = CycleLiteracyLibrary.getArticleById(
        'unknown-article-xyz',
      );
      expect(nonExistent, isNull);
    });

    test('getArticlesForSubphase covers every subphase', () {
      for (final subphase in CycleSubphase.values) {
        final articles = CycleLiteracyLibrary.getArticlesForSubphase(subphase);
        expect(
          articles,
          isNotEmpty,
          reason:
              'Subphase ${subphase.displayName} should have at least 1 related article',
        );
      }
    });

    test('getArticlesByCategory returns relevant articles', () {
      for (final category in CycleLiteracyCategory.values) {
        final articles = CycleLiteracyLibrary.getArticlesByCategory(category);
        expect(
          articles,
          isNotEmpty,
          reason: 'Category ${category.displayName} should have articles',
        );
        for (final article in articles) {
          expect(article.category, category);
        }
      }
    });

    test('getArticlesForAudience filters appropriately', () {
      final all = CycleLiteracyLibrary.getArticlesForAudience(
        CycleLiteracyAudience.all,
      );
      expect(all.length, 11);

      final teens = CycleLiteracyLibrary.getArticlesForAudience(
        CycleLiteracyAudience.teen,
      );
      expect(teens.length, 10);
      for (final a in teens) {
        expect(
          a.audience == CycleLiteracyAudience.all ||
              a.audience == CycleLiteracyAudience.teen,
          isTrue,
        );
      }

      final guardians = CycleLiteracyLibrary.getArticlesForAudience(
        CycleLiteracyAudience.guardian,
      );
      expect(guardians.length, 9);
      for (final a in guardians) {
        expect(
          a.audience == CycleLiteracyAudience.all ||
              a.audience == CycleLiteracyAudience.guardian,
          isTrue,
        );
      }
    });
  });

  group('Issue #854 teen and guardian cycle education', () {
    test('catalog contains the four required teen and guardian articles', () {
      final teen1 = CycleLiteracyLibrary.getArticleById(
        'first-periods-first-two-years',
      );
      expect(teen1, isNotNull);
      expect(teen1!.audience, CycleLiteracyAudience.teen);
      expect(teen1.source, contains('ACOG'));
      expect(
        teen1.sections.any((s) => s.heading.contains('Finding Your Rhythm')),
        isTrue,
      );

      final teen2 = CycleLiteracyLibrary.getArticleById(
        'what-irregular-means-at-13',
      );
      expect(teen2, isNotNull);
      expect(teen2!.audience, CycleLiteracyAudience.teen);
      expect(teen2.source, contains('AAP'));
      expect(
        teen2.sections.any((s) => s.heading.contains('Anovulatory Cycles')),
        isTrue,
      );

      final guardian1 = CycleLiteracyLibrary.getArticleById(
        'talking-about-cycles-teens-parents',
      );
      expect(guardian1, isNotNull);
      expect(guardian1!.audience, CycleLiteracyAudience.guardian);
      expect(guardian1.source, contains('AAP'));
      expect(
        guardian1.sections.any((s) => s.heading.contains('Dialogues')),
        isTrue,
      );

      final guardian2 = CycleLiteracyLibrary.getArticleById(
        'pms-vs-mood-when-to-ask-clinician',
      );
      expect(guardian2, isNotNull);
      expect(guardian2!.audience, CycleLiteracyAudience.all);
      expect(guardian2.source, contains('ACOG'));
      expect(
        guardian2.sections.any((s) => s.heading.contains('Seek Clinical Care')),
        isTrue,
      );
    });
  });

  group('Issue #1086 clinical source consistency and accuracy', () {
    test('no article cites obsolete or incorrect bulletins', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        expect(
          article.source,
          isNot(contains('Practice Bulletin No. 154')),
          reason:
              'PB 154 is Operative Vaginal Delivery; cannot be cited for PMS',
        );
        expect(
          article.source,
          isNot(contains('Practice Bulletin No. 15;')),
          reason: 'PB 15 is obsolete (2000); PMS articles must cite CPG No. 7',
        );
        expect(
          article.source,
          isNot(contains('Pediatrics 2015')),
          reason: 'AAP/ACOG joint statement was Pediatrics 2006, updated as ACOG CO 651 in 2015',
        );
      }
    });

    test('both PMS articles cite ACOG Clinical Practice Guideline No. 7 (2023)', () {
      final pms1 = CycleLiteracyLibrary.getArticleById('pms-and-progesterone');
      final pms2 = CycleLiteracyLibrary.getArticleById(
        'pms-vs-mood-when-to-ask-clinician',
      );

      expect(pms1, isNotNull);
      expect(pms2, isNotNull);

      const expectedACOG =
          'ACOG Clinical Practice Guideline No. 7, Management of Premenstrual Disorders (2023)';
      expect(pms1!.source, contains(expectedACOG));
      expect(pms2!.source, contains(expectedACOG));
    });

    test('teen cycle variability articles cite ACOG Committee Opinion No. 651 (2015)', () {
      final teen1 = CycleLiteracyLibrary.getArticleById(
        'first-periods-first-two-years',
      );
      final teen2 = CycleLiteracyLibrary.getArticleById(
        'what-irregular-means-at-13',
      );

      expect(teen1, isNotNull);
      expect(teen2, isNotNull);

      const expectedCO = 'ACOG) Committee Opinion No. 651 (2015)';
      expect(teen1!.source, contains(expectedCO));
      expect(teen2!.source, contains(expectedCO));
    });

    test('getArticlesForExactAudience isolates audience-specific articles', () {
      final teens = CycleLiteracyLibrary.getArticlesForExactAudience(
        CycleLiteracyAudience.teen,
      );
      expect(teens.length, 2);
      expect(
        teens.every((a) => a.audience == CycleLiteracyAudience.teen),
        isTrue,
      );

      final guardians = CycleLiteracyLibrary.getArticlesForExactAudience(
        CycleLiteracyAudience.guardian,
      );
      expect(guardians.length, 1);
      expect(
        guardians.every((a) => a.audience == CycleLiteracyAudience.guardian),
        isTrue,
      );

      final all = CycleLiteracyLibrary.getArticlesForExactAudience(
        CycleLiteracyAudience.all,
      );
      expect(all.length, 8);
      expect(all.every((a) => a.audience == CycleLiteracyAudience.all), isTrue);
    });
  });
}
