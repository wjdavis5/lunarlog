/// Bundled offline cycle-literacy content library (Issue #239, A2-25).
///
/// Science-backed, expert-reviewed educational articles on menstrual,
/// hormonal, and reproductive literacy. Fully offline with zero network
/// dependency.
///
/// **Constraints & Framing**:
/// - General biological literacy only: no individualized medical advice,
///   no diagnostic assertions, and no clinical prescriptions.
/// - Every article carries explicit provenance: named authoritative sources
///   (e.g. ACOG, NHS, peer-reviewed endocrine literature) and ISO review dates.
/// - Articles link contextually from active cycle subphases (Issue #236) and
///   are browsable in a standalone library index.
library;

import '../prediction/cycle_subphase.dart';

/// Content categories for cycle literacy articles.
enum CycleLiteracyCategory {
  phases,
  fertility,
  bodyAndSymptoms,
  variability;

  String get displayName => switch (this) {
        CycleLiteracyCategory.phases => 'Cycle Phases & Hormones',
        CycleLiteracyCategory.fertility => 'Fertility & Ovulation',
        CycleLiteracyCategory.bodyAndSymptoms => 'Body & Symptoms',
        CycleLiteracyCategory.variability => 'Cycle Patterns & Health',
      };
}

/// A structured section within a cycle literacy article.
class ArticleSection {
  const ArticleSection({
    required this.heading,
    required this.paragraphs,
  });

  final String heading;
  final List<String> paragraphs;
}

/// One bundled, expert-referenced cycle literacy article.
class CycleLiteracyArticle {
  const CycleLiteracyArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    required this.readingTimeMinutes,
    required this.source,
    required this.reviewDate,
    required this.sections,
    required this.relatedSubphases,
  });

  /// Unique stable identifier.
  final String id;

  /// Article title.
  final String title;

  /// Short 1-2 sentence takeaway summary.
  final String summary;

  /// Categorical topic.
  final CycleLiteracyCategory category;

  /// Estimated reading time in minutes.
  final int readingTimeMinutes;

  /// Named clinical or scientific source citation.
  final String source;

  /// ISO-8601 review date (`YYYY-MM-DD`).
  final String reviewDate;

  /// Structured content sections.
  final List<ArticleSection> sections;

  /// Cycle subphases that contextually link to this article.
  final List<CycleSubphase> relatedSubphases;

  /// Standard clinical education disclaimer.
  static const String kMedicalDisclaimer =
      'This article is provided for educational and cycle-literacy purposes only. '
      'It does not constitute medical advice, diagnosis, or treatment. Always consult '
      'a qualified healthcare professional regarding any medical questions or concerns.';
}

/// The bundled offline catalog of cycle literacy articles.
class CycleLiteracyLibrary {
  const CycleLiteracyLibrary._();

  static const String _currentReviewDate = '2026-09-12';

  // --- Article 1: Menstrual Cycle Phases ---
  static const CycleLiteracyArticle menstrualCyclePhases = CycleLiteracyArticle(
    id: 'menstrual-cycle-phases',
    title: 'The Four Key Phases of the Menstrual Cycle',
    summary:
        'A comprehensive guide to how menstruation, the follicular phase, ovulation, and the luteal phase interact each cycle.',
    category: CycleLiteracyCategory.phases,
    readingTimeMinutes: 3,
    source:
        'American College of Obstetricians and Gynecologists (ACOG) FAQ049; Endocrine Society Clinical Resources',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.earlyFollicular,
      CycleSubphase.lateFollicular,
    ],
    sections: [
      ArticleSection(
        heading: 'How Your Cycle Operates',
        paragraphs: [
          'The menstrual cycle is a synchronized hormonal feedback loop directed by the brain (hypothalamus and pituitary gland) and the ovaries. A typical cycle is counted from the first day of menstrual bleeding (Cycle Day 1) until the day before the next period starts.',
          'While the classic textbook example describes a 28-day cycle, healthy cycles naturally range anywhere from 21 to 35 days in adults, and up to 45 days in adolescents.',
        ],
      ),
      ArticleSection(
        heading: 'The Four Main Phases',
        paragraphs: [
          '1. Menstruation (Early Follicular): The shedding of the endometrial lining when pregnancy has not occurred. Estrogen and progesterone sit at baseline levels.',
          '2. Follicular Phase: Under follicle-stimulating hormone (FSH), follicles develop in the ovaries. One dominant follicle emerges and pumps out estradiol (estrogen), rebuilding the uterine lining.',
          '3. Ovulation: A surge of luteinizing hormone (LH) triggers the release of a mature ovum into the fallopian tube.',
          '4. Luteal Phase: The empty ovarian follicle transforms into the corpus luteum, producing progesterone to prepare the uterus. If the egg is not fertilized, the corpus luteum dissolves, hormone levels plunge, and menstruation begins anew.',
        ],
      ),
    ],
  );

  // --- Article 2: Understanding the Follicular Phase ---
  static const CycleLiteracyArticle understandingFollicularPhase = CycleLiteracyArticle(
    id: 'understanding-follicular-phase',
    title: 'The Follicular Phase & The Power of Estrogen',
    summary:
        'How rising estradiol stimulates follicle development and thickens the endometrium — and why energy often feels higher.',
    category: CycleLiteracyCategory.phases,
    readingTimeMinutes: 2,
    source:
        'Speroff\'s Clinical Gynecologic Endocrinology and Infertility (9th ed.); Guyton and Hall Textbook of Medical Physiology',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.lateFollicular,
    ],
    sections: [
      ArticleSection(
        heading: 'Rising Estrogen and Follicle Growth',
        paragraphs: [
          'Following menstruation, the pituitary gland releases Follicle-Stimulating Hormone (FSH). In response, fluid-filled sacs in the ovaries called follicles begin growing. Each follicle holds an immature egg.',
          'As follicles grow, they secrete estradiol—the most potent form of estrogen. Estradiol stimulates cell division in the endometrium, causing the uterine lining to thicken and develop blood vessels in preparation for possible pregnancy.',
        ],
      ),
      ArticleSection(
        heading: 'Physical & Emotional Impacts',
        paragraphs: [
          'Rising estrogen during the late follicular phase often correlates with increased physical vitality, clearer skin, and improved mood. Estrogen also interacts with cervical crypts, transitioning cervical fluid from dry or creamy to slippery, fertile fluid as ovulation approaches.',
        ],
      ),
    ],
  );

  // --- Article 3: Understanding Ovulation ---
  static const CycleLiteracyArticle understandingOvulation = CycleLiteracyArticle(
    id: 'understanding-ovulation',
    title: 'Understanding Ovulation & The Fertile Window',
    summary:
        'The science behind the LH surge, egg release, and the biological window of fertility.',
    category: CycleLiteracyCategory.fertility,
    readingTimeMinutes: 3,
    source:
        'ACOG Clinical Practice Guideline on Infertility; Wilcox et al., New England Journal of Medicine',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.ovulation,
    ],
    sections: [
      ArticleSection(
        heading: 'The Ovulatory Surge',
        paragraphs: [
          'When estrogen levels reach a critical peak, they trigger a rapid surge of Luteinizing Hormone (LH) from the pituitary. Within 24 to 36 hours of this surge, the dominant ovarian follicle ruptures, releasing a mature egg.',
          'Once released, the egg survives in the fallopian tube for only 12 to 24 hours. If it is not fertilized within this timeframe, it naturally dissolves.',
        ],
      ),
      ArticleSection(
        heading: 'The 6-Day Fertile Window',
        paragraphs: [
          'Although the egg lives for only one day, sperm can survive inside the reproductive tract for up to 5 days under the nourishment of fertile cervical mucus. Consequently, the biological fertile window spans the 5 days before ovulation plus the day of ovulation itself.',
          'Important note: Calendar calculations provide statistical approximations based on past cycle lengths. They are helpful for understanding your cycle rhythms, but should never be used as a standalone contraceptive technique.',
        ],
      ),
    ],
  );

  // --- Article 4: Luteal Phase & Progesterone ---
  static const CycleLiteracyArticle lutealPhaseAndProgesterone = CycleLiteracyArticle(
    id: 'luteal-phase-and-progesterone',
    title: 'The Luteal Phase: Progesterone and Body Temperature',
    summary:
        'The role of the corpus luteum in producing progesterone, stabilizing the endometrium, and raising basal temperature.',
    category: CycleLiteracyCategory.phases,
    readingTimeMinutes: 2,
    source:
        'Williams Obstetrics (26th ed.); Yen & Jaffe\'s Reproductive Endocrinology',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.earlyLuteal,
      CycleSubphase.midLuteal,
    ],
    sections: [
      ArticleSection(
        heading: 'The Corpus Luteum at Work',
        paragraphs: [
          'After releasing an egg, the remnants of the ovarian follicle collapse and transform into a temporary endocrine gland called the corpus luteum. The corpus luteum begins pumping out progesterone.',
          'Progesterone converts the estrogen-built endometrium into a secretory structure, halting lining growth and making it receptive to embryo implantation.',
        ],
      ),
      ArticleSection(
        heading: 'Thermal and Body Changes',
        paragraphs: [
          'Progesterone acts directly on the hypothalamic thermoregulatory center, causing resting basal body temperature (BBT) to shift upward by approximately 0.5°F to 1.0°F (0.3°C to 0.6°C). This thermal shift persists until progesterone levels decline at the end of the luteal phase.',
        ],
      ),
    ],
  );

  // --- Article 5: PMS & Progesterone ---
  static const CycleLiteracyArticle pmsAndProgesterone = CycleLiteracyArticle(
    id: 'pms-and-progesterone',
    title: 'Premenstrual Changes: Why Hormones Shift Your Mood and Body',
    summary:
        'The biological basis of PMS: how the abrupt withdrawal of progesterone and estrogen influences neurotransmitters.',
    category: CycleLiteracyCategory.bodyAndSymptoms,
    readingTimeMinutes: 3,
    source:
        'ACOG Practice Bulletin No. 154: Premenstrual Syndrome; Royal College of Obstetricians and Gynaecologists (RCOG)',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.midLuteal,
      CycleSubphase.lateLuteal,
    ],
    sections: [
      ArticleSection(
        heading: 'What Causes Premenstrual Symptoms?',
        paragraphs: [
          'Premenstrual syndrome (PMS) refers to a collection of physical, cognitive, and emotional symptoms that occur during the late luteal phase and resolve shortly after menses begins.',
          'Rather than an abnormal level of hormones, research indicates PMS is triggered by an increased sensitivity to normal hormonal fluctuations—specifically the steep drop in progesterone and estrogen that occurs when the corpus luteum regresses.',
        ],
      ),
      ArticleSection(
        heading: 'Serotonin and GABA Interactions',
        paragraphs: [
          'Progesterone metabolites (such as allopregnanolone) interact directly with GABA receptors in the brain, which regulate calm and anxiety. As progesterone plunges, researchers think this shifts GABA and serotonin signaling, which may contribute to premenstrual mood sensitivity, sleep disruptions, and sugar cravings.',
          'Tracking premenstrual symptoms over several cycles helps identify personal patterns and supports productive discussions with your healthcare provider if symptoms become disruptive.',
        ],
      ),
    ],
  );

  // --- Article 6: Why Do Cramps Happen ---
  static const CycleLiteracyArticle whyCrampsHappen = CycleLiteracyArticle(
    id: 'why-cramps-happen',
    title: 'Why Do Cramps Happen? Prostaglandins and Menstrual Pain',
    summary:
        'The biological mechanism of dysmenorrhea: uterine muscle contractions driven by prostaglandins, and when to speak with a doctor.',
    category: CycleLiteracyCategory.bodyAndSymptoms,
    readingTimeMinutes: 3,
    source:
        'ACOG Clinical Consensus: Dysmenorrhea in Adolescents; NHS Women\'s Health Guidelines',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.lateLuteal,
      CycleSubphase.earlyFollicular,
    ],
    sections: [
      ArticleSection(
        heading: 'Prostaglandins: The Body\'s Messengers',
        paragraphs: [
          'Primary dysmenorrhea (menstrual cramping without an underlying pelvic disease) is primarily caused by natural chemical messengers called prostaglandins.',
          'As the uterine lining begins to break down before menstruation, cells release prostaglandins. These compounds stimulate the smooth muscles of the myometrium (uterine wall) to contract, helping shed the endometrial tissue.',
        ],
      ),
      ArticleSection(
        heading: 'Why Cramping Peaks Early',
        paragraphs: [
          'Prostaglandin levels are highest during the first 24 to 48 hours of heavy bleeding, which is why cramping is typically most intense on Cycle Days 1 and 2.',
          'When prostaglandins enter the bloodstream, they can also cause neighboring smooth muscles to contract, leading to common accompanying symptoms such as loose stools, nausea, or lower back pain.',
          'While mild to moderate cramps are very common, pain that interferes with school, work, or daily activities warrants an evaluation by a healthcare professional.',
        ],
      ),
    ],
  );

  // --- Article 7: Cycle Length & Variability ---
  static const CycleLiteracyArticle cycleLengthVariability = CycleLiteracyArticle(
    id: 'cycle-length-variability',
    title: 'Cycle Length & Natural Variation: What Is "Normal"?',
    summary:
        'Why cycles fluctuate naturally, how adolescent and adult variations differ, and what variation means for health.',
    category: CycleLiteracyCategory.variability,
    readingTimeMinutes: 3,
    source:
        'FIGO Menstrual Disorders Committee (FIGO Systems 1 & 2); World Health Organization (WHO); ACOG FAQ049',
    reviewDate: _currentReviewDate,
    relatedSubphases: [
      CycleSubphase.earlyFollicular,
      CycleSubphase.lateLuteal,
    ],
    sections: [
      ArticleSection(
        heading: 'The Myth of the 28-Day Clockwork Cycle',
        paragraphs: [
          'Only a small fraction of individuals have exactly 28-day cycles every month. In healthy adults, cycle lengths naturally vary by 2 to 7 days from month to month without indicating any medical problem.',
          'Factors such as psychological stress, travel, illness, shifts in sleep schedule, and vigorous exercise can transiently delay follicular development and shift ovulation date, extending that month\'s cycle.',
        ],
      ),
      ArticleSection(
        heading: 'The First Few Years',
        paragraphs: [
          'For the first two to three years after a first period, cycles are often longer and less predictable than they will later become — commonly ranging from about 21 to 45 days, with some months skipped entirely. That is a normal part of the hormonal feedback loop maturing, not automatically a sign of a problem.',
          'Once cycles have settled, an adult cycle generally falls between about 21 and 35 days, and a few days of month-to-month variation remains normal.',
        ],
      ),
      ArticleSection(
        heading: 'When to Ask a Doctor',
        paragraphs: [
          'A few patterns are worth raising with a healthcare professional: no period for three months once cycles had been regular, bleeding that lasts longer than about a week, or soaking through a pad or tampon every hour for several hours.',
        ],
      ),
    ],
  );

  /// All bundled cycle literacy articles in reading order.
  static const List<CycleLiteracyArticle> allArticles = [
    menstrualCyclePhases,
    understandingFollicularPhase,
    understandingOvulation,
    lutealPhaseAndProgesterone,
    pmsAndProgesterone,
    whyCrampsHappen,
    cycleLengthVariability,
  ];

  /// Look up an article by its unique [id].
  static CycleLiteracyArticle? getArticleById(String id) {
    for (final article in allArticles) {
      if (article.id == id) return article;
    }
    return null;
  }

  /// Retrieve articles that contextually relate to [subphase].
  static List<CycleLiteracyArticle> getArticlesForSubphase(CycleSubphase subphase) {
    return allArticles
        .where((article) => article.relatedSubphases.contains(subphase))
        .toList();
  }

  /// Retrieve articles categorized under [category].
  static List<CycleLiteracyArticle> getArticlesByCategory(
      CycleLiteracyCategory category) {
    return allArticles.where((article) => article.category == category).toList();
  }
}
