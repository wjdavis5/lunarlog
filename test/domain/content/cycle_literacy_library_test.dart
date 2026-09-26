import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/content/cycle_literacy_library.dart';
import 'package:lunarlog/domain/prediction/cycle_subphase.dart';

/// Whether [article] cites a source published by [publisher].
bool _hasPublisher(CycleLiteracyArticle article, SourcePublisher publisher) =>
    article.sources.any((source) => source.publisher == publisher);

/// The first source on [article] published by [publisher].
ArticleSource _sourceFor(
  CycleLiteracyArticle article,
  SourcePublisher publisher,
) => article.sources.firstWhere((source) => source.publisher == publisher);

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
            article.sources,
            isNotEmpty,
            reason: 'Must have at least one named source',
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

    test('follicular summary and body make no energy or mood claim', () {
      final article = CycleLiteracyLibrary.getArticleById(
        'understanding-follicular-phase',
      )!;
      expect(article.summary, isNot(contains('energy')));
      expect(article.summary, contains('follicle'));
      expect(
        paragraph('understanding-follicular-phase', 'Physical'),
        contains("doesn't show a consistent pattern"),
        reason: 'Issue #1119: the vitality/skin/mood overclaim is now hedged',
      );
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
      expect(body, contains('21 and 45 days'));
      expect(body, contains('3 months (90 days)'));
      expect(body, contains('more than 7 days'));
      expect(body, contains('every 1 to 2 hours'));
      expect(body, contains('quarter'));
      expect(body, contains('pregnancy test'));
      expect(_hasPublisher(article, SourcePublisher.acog), isTrue);
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
      expect(_hasPublisher(teen1, SourcePublisher.acog), isTrue);
      expect(
        teen1.sections.any((s) => s.heading.contains('Finding Your Rhythm')),
        isTrue,
      );

      final teen2 = CycleLiteracyLibrary.getArticleById(
        'what-irregular-means-at-13',
      );
      expect(teen2, isNotNull);
      expect(teen2!.audience, CycleLiteracyAudience.teen);
      expect(_hasPublisher(teen2, SourcePublisher.acog), isTrue);
      expect(
        teen2.sections.any((s) => s.heading.contains('Anovulatory Cycles')),
        isTrue,
      );

      final guardian1 = CycleLiteracyLibrary.getArticleById(
        'talking-about-cycles-teens-parents',
      );
      expect(guardian1, isNotNull);
      expect(guardian1!.audience, CycleLiteracyAudience.guardian);
      expect(_hasPublisher(guardian1, SourcePublisher.aap), isTrue);
      expect(
        guardian1.sections.any((s) => s.heading.contains('Dialogues')),
        isTrue,
      );

      final guardian2 = CycleLiteracyLibrary.getArticleById(
        'pms-vs-mood-when-to-ask-clinician',
      );
      expect(guardian2, isNotNull);
      expect(guardian2!.audience, CycleLiteracyAudience.all);
      expect(_hasPublisher(guardian2, SourcePublisher.acog), isTrue);
      expect(
        guardian2.sections.any((s) => s.heading.contains('Seek Clinical Care')),
        isTrue,
      );
    });
  });

  group('Issue #1086 clinical source consistency and accuracy', () {
    test('no article cites obsolete or incorrect bulletins', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        final citations = article.sources
            .map((s) => '${s.title} ${s.identifier ?? ''}')
            .join(' ');
        expect(
          citations,
          isNot(contains('Practice Bulletin No. 154')),
          reason:
              'PB 154 is Operative Vaginal Delivery; cannot be cited for PMS',
        );
        expect(
          citations,
          isNot(contains('Practice Bulletin No. 15;')),
          reason: 'PB 15 is obsolete (2000); PMS articles must cite CPG No. 7',
        );
        expect(
          citations,
          isNot(contains('Pediatrics 2015')),
          reason:
              'AAP/ACOG joint statement was Pediatrics 2006, updated as ACOG CO 651 in 2015',
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

      for (final article in [pms1!, pms2!]) {
        final acog = _sourceFor(article, SourcePublisher.acog);
        expect(acog.identifier, 'Clinical Practice Guideline No. 7');
        expect(acog.title, 'Management of Premenstrual Disorders');
      }
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

      for (final article in [teen1!, teen2!]) {
        final acog = _sourceFor(article, SourcePublisher.acog);
        expect(acog.identifier, 'Committee Opinion No. 651');
      }
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

  group('Issue #1103 structured, linkable sources', () {
    test('(a) every article has at least one linkable non-textbook source', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        final linkable = article.sources.where(
          (source) =>
              source.publisher != SourcePublisher.textbook &&
              source.url != null,
        );
        expect(
          linkable,
          isNotEmpty,
          reason:
              '${article.id} must cite at least one linkable approved source '
              '(non-textbook with a URL)',
        );
      }
    });

    test('(b) every URL is https and on the publisher\'s own domain', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        for (final source in article.sources) {
          final url = source.url;
          if (url == null) continue;

          final uri = Uri.parse(url);
          expect(
            uri.scheme,
            'https',
            reason: '${article.id}: ${source.title} must be https',
          );

          final host = uri.host.toLowerCase();
          final allowed = source.publisher.allowedHosts;
          final onOwnDomain = allowed.any(
            (domain) => host == domain || host.endsWith('.$domain'),
          );
          expect(
            onOwnDomain,
            isTrue,
            reason:
                '${article.id}: "$host" is not on ${source.publisher.name} '
                'allowed hosts $allowed',
          );
        }
      }
    });

    test('(c) every retrieved date is a valid ISO date on or before review', () {
      // Issue #1119 set the shared review date to the re-check date
      // (2026-09-26), so retrieved is now on or before reviewDate everywhere.
      final isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      for (final article in CycleLiteracyLibrary.allArticles) {
        for (final source in article.sources) {
          expect(
            source.retrieved,
            matches(isoDate),
            reason: '${article.id}: ${source.title}',
          );
          expect(
            source.retrieved.compareTo(article.reviewDate) <= 0,
            isTrue,
            reason:
                '${article.id}: ${source.title} retrieved ${source.retrieved} '
                'is after review ${article.reviewDate}',
          );
        }
      }
    });

    test('(d) no textbook source carries a URL', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        for (final source in article.sources) {
          if (source.publisher == SourcePublisher.textbook) {
            expect(
              source.url,
              isNull,
              reason: '${article.id}: ${source.title} cannot be linked',
            );
          }
        }
      }
    });

    test('(e) every non-textbook source carries a URL', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        for (final source in article.sources) {
          if (source.publisher != SourcePublisher.textbook) {
            expect(
              source.url,
              isNotNull,
              reason:
                  '${article.id}: a ${source.publisher.name} source '
                  '("${source.title}") must carry a URL',
            );
          }
        }
      }
    });

    test('only textbooks lack a publisher host declaration', () {
      for (final publisher in SourcePublisher.values) {
        if (publisher == SourcePublisher.textbook) {
          expect(publisher.allowedHosts, isEmpty);
        } else {
          expect(publisher.allowedHosts, isNotEmpty);
        }
      }
    });
  });

  group('Issue #1119 safety and provenance corrections', () {
    String body(String articleId) {
      final article = CycleLiteracyLibrary.getArticleById(articleId)!;
      return article.sections.expand((s) => s.paragraphs).join(' ');
    }

    test('teen amenorrhea rule drops the "once regular" qualifier', () {
      final article = CycleLiteracyLibrary.getArticleById(
        'cycle-length-variability',
      )!;
      final text = article.sections.expand((s) => s.paragraphs).join(' ');
      expect(text, contains('even if your cycles were never regular'));
      expect(text, contains('pregnancy test'));
      expect(text, contains('quarter'));
      expect(text, isNot(contains('once cycles had been regular')));
    });

    test('teen "right away" bleeding signs are present', () {
      expect(
        body('first-periods-first-two-years'),
        contains('right away if you feel dizzy or light-headed'),
      );
      expect(
        body('first-periods-first-two-years'),
        contains('heart is racing'),
      );
    });

    test('cramp article carries the urgent pain tier', () {
      expect(
        body('why-cramps-happen'),
        contains("pain relievers haven't helped"),
      );
    });

    test('crisis route is present wherever hopelessness is discussed', () {
      for (final id in [
        'pms-and-progesterone',
        'pms-vs-mood-when-to-ask-clinician',
      ]) {
        final text = body(id);
        expect(text, contains('hopeless'), reason: id);
        expect(text, contains('trusted adult'), reason: id);
        expect(text, contains('988'), reason: id);
        expect(text, contains('116 123'), reason: id);
        expect(text, contains('0800 1111'), reason: id);
        expect(text, contains('NHS 111'), reason: id);
        expect(text, contains('local emergency number'), reason: id);
      }
      expect(
        body('pms-vs-mood-when-to-ask-clinician'),
        contains('have treatments that can help'),
      );
      expect(
        body('pms-vs-mood-when-to-ask-clinician'),
        isNot(contains('highly treatable')),
      );
    });

    test('fertile window matches ACOG FAQ024 (5 days before to 1 day after)',
        () {
      final article = CycleLiteracyLibrary.getArticleById(
        'understanding-ovulation',
      )!;
      expect(article.sections.map((s) => s.heading), contains('The Fertile Window'));
      final text = article.sections.expand((s) => s.paragraphs).join(' ');
      expect(text, contains('the day after'));
      expect(text, isNot(contains('6-Day Fertile Window')));
    });

    test('PMS mechanism is stated as an unknown, not the "steep drop"', () {
      final text = body('pms-and-progesterone');
      expect(text, contains("the exact cause isn't known"));
      expect(text, isNot(contains('steep drop')));
    });

    test('superseded AAP 2006 report and generic Endocrine link are gone', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        final citations = article.sources
            .map(
              (s) =>
                  '${s.publisher.name} ${s.title} ${s.identifier ?? ''} '
                  '${s.url ?? ''}',
            )
            .join(' ');
        expect(citations, isNot(contains('Pediatrics 2006')));
        expect(citations, isNot(contains('publications.aap.org')));
        expect(citations, isNot(contains('Endocrine Library')));

        for (final source in article.sources) {
          if (source.publisher == SourcePublisher.textbook) {
            expect(
              source.title,
              contains('ed.'),
              reason: 'Issue #1119: every textbook needs an edition',
            );
          }
        }
      }
    });

    test('teen red-flag lists are complete and cite ACOG FAQ049', () {
      final a7 = CycleLiteracyLibrary.getArticleById(
        'cycle-length-variability',
      )!;
      expect(
        a7.sources.any((s) => s.identifier == 'FAQ049'),
        isTrue,
        reason: 'Issue #1119: A7 signs come from ACOG FAQ049',
      );
      final a7Text = a7.sections.expand((s) => s.paragraphs).join(' ');
      expect(a7Text, contains('every 1 to 2 hours'));
      expect(a7Text, contains('heart is racing'));
      expect(a7Text, contains('2.5 cm'));

      final a8 = CycleLiteracyLibrary.getArticleById(
        'first-periods-first-two-years',
      )!;
      expect(a8.sources.any((s) => s.identifier == 'FAQ049'), isTrue);
      expect(
        a8.sections.expand((s) => s.paragraphs).join(' '),
        contains('take a pregnancy test'),
      );

      final a9 = CycleLiteracyLibrary.getArticleById(
        'what-irregular-means-at-13',
      )!;
      expect(a9.sources.any((s) => s.identifier == 'FAQ049'), isTrue);
      expect(a9.sources.any((s) => s.publisher == SourcePublisher.aap), isTrue);
      final a9Text = a9.sections.expand((s) => s.paragraphs).join(' ');
      expect(a9Text, contains('become irregular for several months'));
      expect(a9Text, contains('bleeding lasts more than 7 days'));
      expect(a9Text, contains('every 1 to 2 hours'));
      expect(a9Text, contains('bleeding disorder'));
      expect(a9Text, contains('by age 15'));
      expect(a9Text, contains('breasts starting to develop'));
      expect(a9Text, contains('take a pregnancy test'));

      final a1 = CycleLiteracyLibrary.getArticleById(
        'menstrual-cycle-phases',
      )!;
      expect(_hasPublisher(a1, SourcePublisher.who), isTrue);
      expect(_hasPublisher(a1, SourcePublisher.acog), isTrue);
    });

    test('every article carries the re-checked review date', () {
      for (final article in CycleLiteracyLibrary.allArticles) {
        expect(article.reviewDate, '2026-09-26');
      }
    });
  });
}
