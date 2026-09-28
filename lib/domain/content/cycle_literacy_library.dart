/// Bundled offline cycle-literacy content library (Issue #239, A2-25).
///
/// Educational articles on menstrual, hormonal, and reproductive literacy,
/// sourced from named authoritative bodies. Fully offline with zero network
/// dependency.
///
/// **Constraints & Framing**:
/// - General biological literacy only: no individualized medical advice,
///   no diagnostic assertions, and no clinical prescriptions.
/// - Every article carries explicit provenance as structured, individually
///   linkable citations (Issue #1103). "Last reviewed" is the date the cited
///   sources were last checked against their publishers; it is **not** a
///   clinical review of the article, and nothing here claims one.
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

/// Target audience for cycle literacy articles (Issue #854).
enum CycleLiteracyAudience { all, teen, guardian }

/// The authoritative body (or style of source) behind a citation (Issue #1103).
///
/// Each publisher that serves its own content declares the host(s) that
/// content legitimately lives on, so a test can prove a cited URL points at
/// the publisher's own domain rather than a re-host. [peerReviewed] and
/// [textbook] describe a kind of source rather than a single body; [textbook]
/// has no host because a printed textbook cannot be linked.
enum SourcePublisher {
  acog('American College of Obstetricians and Gynecologists', {'acog.org'}),
  nhs('National Health Service (UK)', {'nhs.uk'}),
  who('World Health Organization', {'who.int'}),
  nichd(
    'Eunice Kennedy Shriver National Institute of Child Health and Human Development',
    {'nichd.nih.gov', 'nih.gov'},
  ),
  rcog('Royal College of Obstetricians and Gynaecologists', {'rcog.org.uk'}),
  mayoClinic('Mayo Clinic', {'mayoclinic.org'}),
  clevelandClinic('Cleveland Clinic', {'my.clevelandclinic.org'}),
  aap('American Academy of Pediatrics', {'aap.org', 'healthychildren.org'}),
  figo('International Federation of Gynecology and Obstetrics', {'figo.org'}),
  endocrineSociety('Endocrine Society', {'endocrine.org'}),
  peerReviewed(
    'Peer-reviewed literature',
    {'doi.org', 'pubmed.ncbi.nlm.nih.gov'},
  ),
  textbook('Textbook', {});

  const SourcePublisher(this.displayName, this.allowedHosts);

  /// Human-readable publisher name.
  final String displayName;

  /// Hosts on which this publisher's own content is served. Empty for
  /// [textbook], which has no linkable URL.
  final Set<String> allowedHosts;
}

/// One cited source behind a [CycleLiteracyArticle] (Issue #1103).
class ArticleSource {
  const ArticleSource({
    required this.publisher,
    required this.title,
    this.identifier,
    this.url,
    required this.retrieved,
  });

  /// The authoritative body (or source style) this citation points at.
  final SourcePublisher publisher;

  /// Title of the cited page or work.
  final String title;

  /// Optional document identifier, e.g. `'Committee Opinion No. 651'`.
  final String? identifier;

  /// https URL on [SourcePublisher.allowedHosts]. Null only for a
  /// [SourcePublisher.textbook] citation, which cannot be linked.
  final String? url;

  /// ISO-8601 date (`YYYY-MM-DD`) the source was last checked.
  final String retrieved;
}

/// An actionable crisis-resource contact method (Issue #1132).
class CrisisAction {
  const CrisisAction({
    required this.label,
    required this.uriString,
    required this.semanticsLabel,
  });

  /// Short button label displayed to the reader (e.g. `'Call 988'`).
  final String label;

  /// External URL string launched when activated (`'tel:988'` or `'sms:988'`).
  final String uriString;

  /// Parsed URI.
  Uri get uri => Uri.parse(uriString);

  /// Full accessibility announcement (e.g. `'Call 988, Suicide and Crisis Lifeline'`).
  final String semanticsLabel;
}

/// A structured crisis-support callout block within an [ArticleSection]
/// (Issue #1132).
///
/// Set apart in a calm, discreet tinted container with one-tap action
/// targets for urgent support.
class CrisisResources {
  const CrisisResources({
    required this.text,
    this.actions = kDefaultCrisisActions,
  });

  /// The crisis route guidance and context prose.
  final String text;

  /// Actionable contact routes.
  final List<CrisisAction> actions;

  /// The standard crisis route contact actions across US, Canada, UK, and NI.
  static const List<CrisisAction> kDefaultCrisisActions = [
    CrisisAction(
      label: 'Call 988',
      uriString: 'tel:988',
      semanticsLabel: 'Call 988, Suicide and Crisis Lifeline',
    ),
    CrisisAction(
      label: 'Text 988',
      uriString: 'sms:988',
      semanticsLabel: 'Text 988, Suicide and Crisis Lifeline',
    ),
    CrisisAction(
      label: 'Samaritans 116 123',
      uriString: 'tel:116123',
      semanticsLabel: 'Call Samaritans on 116 123',
    ),
    CrisisAction(
      label: 'Childline 0800 1111',
      uriString: 'tel:08001111',
      semanticsLabel: 'Call Childline on 0800 1111',
    ),
    CrisisAction(
      label: 'NHS 111',
      uriString: 'tel:111',
      semanticsLabel: 'Call NHS 111',
    ),
    CrisisAction(
      label: 'Lifeline 0808 808 8000',
      uriString: 'tel:08088088000',
      semanticsLabel: 'Call Lifeline on 0808 808 8000',
    ),
    CrisisAction(
      label: '911',
      uriString: 'tel:911',
      semanticsLabel: 'Call 911, Emergency services',
    ),
    CrisisAction(
      label: '999',
      uriString: 'tel:999',
      semanticsLabel: 'Call 999, Emergency services',
    ),
  ];
}

/// A structured section within a cycle literacy article.
class ArticleSection {
  const ArticleSection({
    required this.heading,
    required this.paragraphs,
    this.callout,
  });

  final String heading;
  final List<String> paragraphs;

  /// Optional crisis or support callout displayed in a distinct container
  /// (Issue #1132).
  final CrisisResources? callout;

  /// Every paragraph of text in this section, including any [callout] text.
  Iterable<String> get allParagraphs sync* {
    yield* paragraphs;
    if (callout != null) {
      yield callout!.text;
    }
  }
}

/// One bundled, source-referenced cycle literacy article.
class CycleLiteracyArticle {
  const CycleLiteracyArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.category,
    this.audience = CycleLiteracyAudience.all,
    required this.readingTimeMinutes,
    required this.sources,
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

  /// Target audience for this article (Issue #854).
  final CycleLiteracyAudience audience;

  /// Estimated reading time in minutes.
  final int readingTimeMinutes;

  /// Structured, individually linkable citations behind this article.
  final List<ArticleSource> sources;

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

  static const String _currentReviewDate = '2026-09-26';

  /// ISO date the citations below were last checked against their publishers
  /// (Issue #1103).
  static const String _retrievedDate = '2026-09-26';

  /// Issue #1128 checked Article 3's citations (and added one) on this later
  /// date; every other article keeps the full-library [_retrievedDate].
  static const String _round3RetrievedDate = '2026-09-28';

  /// Tiered crisis route wording across US, Canada, UK, and NI (Issues #1111,
  /// #1119, #1128, #1132).
  static const String _crisisParagraphText =
      'If you ever feel hopeless, or have thoughts of hurting yourself or ending '
      'your life, please tell a trusted adult and get support now. In the US or '
      'Canada, call or text 988. In the UK, call Samaritans free on 116 123 '
      '(or Childline on 0800 1111 if you\'re under 19), or call NHS 111 and '
      'choose the mental health option (in Northern Ireland, call Lifeline '
      'free on 0808 808 8000). If you might not be able to keep yourself safe, '
      'or you have already hurt yourself, call your local emergency number '
      '(911 in the US and Canada, 999 in the UK) or go to the nearest emergency '
      'department (A&E) now.';

  // --- Verified, linkable citations (Issue #1103) ---
  //
  // How each URL below was verified (Issue #1119 corrects this comment: the
  // old claim that every URL "returned HTTP 200" was not true):
  // - ACOG, NHS, WHO and RCOG pages returned HTTP 200 to
  //   `curl -sIL -o /dev/null -w "%{http_code} %{url_effective}"` with a
  //   browser User-Agent. ACOG serves *missing* pages as HTTP 200 too, so
  //   each ACOG page's `og:title` was read as well; none is a soft 404.
  // - The two peer-reviewed DOI links (_wilcoxOvulationTiming,
  //   _figoMenstrualDisorders) return HTTP 403 to curl behind a publisher
  //   bot challenge. They were verified by following the doi.org redirect
  //   and confirming the title against Crossref and PubMed E-utilities.
  // - The AAP HealthyChildren page returned HTTP 200; its title was read
  //   from `og:title`.
  // Never add a URL that has not been verified this way; the domain is
  // enforced by test/domain/content/cycle_literacy_library_test.dart.

  static const ArticleSource _acogMenstrualCycle = ArticleSource(
    publisher: SourcePublisher.acog,
    title:
        'The Menstrual Cycle: Menstruation, Ovulation, and How Pregnancy Occurs',
    url: 'https://www.acog.org/womens-health/infographics/the-menstrual-cycle',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _acogFertilityAwareness = ArticleSource(
    publisher: SourcePublisher.acog,
    title: 'Fertility Awareness-Based Methods of Family Planning',
    url:
        'https://www.acog.org/womens-health/faqs/fertility-awareness-based-methods-of-family-planning',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _acogPainfulPeriods = ArticleSource(
    publisher: SourcePublisher.acog,
    title: 'Painful Periods',
    url: 'https://www.acog.org/womens-health/faqs/painful-periods',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _acogYourFirstPeriod = ArticleSource(
    publisher: SourcePublisher.acog,
    title: 'Your First Period',
    identifier: 'FAQ049',
    url: 'https://www.acog.org/womens-health/faqs/your-first-period',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _acogCommitteeOpinion651 = ArticleSource(
    publisher: SourcePublisher.acog,
    title:
        'Menstruation in Girls and Adolescents: Using the Menstrual Cycle as a Vital Sign',
    identifier: 'Committee Opinion No. 651',
    url:
        'https://www.acog.org/clinical/clinical-guidance/committee-opinion/articles/2015/12/menstruation-in-girls-and-adolescents-using-the-menstrual-cycle-as-a-vital-sign',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _acogCpgNo7 = ArticleSource(
    publisher: SourcePublisher.acog,
    title: 'Management of Premenstrual Disorders',
    identifier: 'Clinical Practice Guideline No. 7',
    url:
        'https://www.acog.org/clinical/clinical-guidance/clinical-practice-guideline/articles/2023/12/management-of-premenstrual-disorders',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _nhsPeriodPain = ArticleSource(
    publisher: SourcePublisher.nhs,
    title: 'Period pain',
    url: 'https://www.nhs.uk/symptoms/period-pain/',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _nhsPms = ArticleSource(
    publisher: SourcePublisher.nhs,
    title: 'Premenstrual syndrome (PMS)',
    url: 'https://www.nhs.uk/conditions/pre-menstrual-syndrome/',
    retrieved: _retrievedDate,
  );

  /// Verified 2026-09-28 (issue #1128, round-2 row R6): HTTP 200 via
  /// `curl -sIL` with a browser User-Agent, and the page states "Sperm can
  /// survive in the fallopian tubes for up to 7 days after sex."
  static const ArticleSource _nhsFertility = ArticleSource(
    publisher: SourcePublisher.nhs,
    title: 'Periods and fertility in the menstrual cycle',
    url: 'https://www.nhs.uk/conditions/periods/fertility-in-the-menstrual-cycle/',
    retrieved: _round3RetrievedDate,
  );

  static const ArticleSource _whoMenstrualHealth = ArticleSource(
    publisher: SourcePublisher.who,
    title: 'Menstrual health',
    url: 'https://www.who.int/news-room/fact-sheets/detail/menstrual-health',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _aapHealthyChildrenMenstrualDisorders =
      ArticleSource(
        publisher: SourcePublisher.aap,
        title: 'Menstrual Disorders in Teens: Causes, Diagnosis & Treatment',
        url:
            'https://www.healthychildren.org/English/health-issues/conditions/genitourinary-tract/Pages/Menstrual-Disorders.aspx',
        retrieved: _retrievedDate,
      );

  static const ArticleSource _rcogPremenstrualSyndrome = ArticleSource(
    publisher: SourcePublisher.rcog,
    title: 'Premenstrual Syndrome: Management',
    identifier: 'Green-top Guideline No. 48',
    url:
        'https://www.rcog.org.uk/guidance/browse-all-guidance/green-top-guidelines/premenstrual-syndrome-management-green-top-guideline-no-48/',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _wilcoxOvulationTiming = ArticleSource(
    publisher: SourcePublisher.peerReviewed,
    title:
        'Timing of sexual intercourse in relation to ovulation. Effects on the probability of conception, survival of the pregnancy, and sex of the baby',
    identifier: 'N Engl J Med 1995;333:1517-21',
    url: 'https://doi.org/10.1056/NEJM199512073332301',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _figoMenstrualDisorders = ArticleSource(
    publisher: SourcePublisher.peerReviewed,
    title:
        'The two FIGO systems for normal and abnormal uterine bleeding symptoms and classification of causes of abnormal uterine bleeding in the reproductive years: 2018 revisions',
    identifier:
        'FIGO Menstrual Disorders Committee; Int J Gynaecol Obstet 2018;143(3):393-408',
    url: 'https://doi.org/10.1002/ijgo.12666',
    retrieved: _retrievedDate,
  );

  // Textbooks cannot be linked or link-checked; each stays as a secondary
  // citation with no URL (Issue #1103).
  static const ArticleSource _speroffs = ArticleSource(
    publisher: SourcePublisher.textbook,
    title:
        'Speroff\'s Clinical Gynecologic Endocrinology and Infertility (10th ed.)',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _guytonAndHall = ArticleSource(
    publisher: SourcePublisher.textbook,
    title: 'Guyton and Hall Textbook of Medical Physiology (15th ed.)',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _williamsObstetrics = ArticleSource(
    publisher: SourcePublisher.textbook,
    title: 'Williams Obstetrics (26th ed.)',
    retrieved: _retrievedDate,
  );

  static const ArticleSource _yenAndJaffe = ArticleSource(
    publisher: SourcePublisher.textbook,
    title: 'Yen & Jaffe\'s Reproductive Endocrinology (9th ed.)',
    retrieved: _retrievedDate,
  );

  // --- Article 1: Menstrual Cycle Phases ---
  static const CycleLiteracyArticle menstrualCyclePhases = CycleLiteracyArticle(
    id: 'menstrual-cycle-phases',
    title: 'The Four Key Phases of the Menstrual Cycle',
    summary: 'A comprehensive guide to how menstruation, the follicular phase, ovulation, and the luteal phase interact each cycle.',
    category: CycleLiteracyCategory.phases,
    readingTimeMinutes: 3,
    sources: [_acogMenstrualCycle, _whoMenstrualHealth, _acogCommitteeOpinion651],
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
  static const CycleLiteracyArticle understandingFollicularPhase =
      CycleLiteracyArticle(
        id: 'understanding-follicular-phase',
        title: 'The Follicular Phase & The Power of Estrogen',
        summary: 'How FSH and rising estradiol grow a follicle and rebuild the uterine lining.',
        category: CycleLiteracyCategory.phases,
        readingTimeMinutes: 2,
        sources: [
          _speroffs,
          _guytonAndHall,
          _acogMenstrualCycle,
          _acogFertilityAwareness,
        ],
        reviewDate: _currentReviewDate,
        relatedSubphases: [CycleSubphase.lateFollicular],
        sections: [
          ArticleSection(
            heading: 'Rising Estrogen and Follicle Growth',
            paragraphs: [
              'Around the start of a period, the pituitary gland releases more Follicle-Stimulating Hormone (FSH). In response, fluid-filled sacs in the ovaries called follicles begin growing. Each follicle holds an immature egg.',
              'As follicles grow, they secrete estradiol—the most potent form of estrogen. Estradiol stimulates cell division in the endometrium, causing the uterine lining to thicken and develop blood vessels in preparation for possible pregnancy.',
            ],
          ),
          ArticleSection(
            heading: 'Physical & Emotional Impacts',
            paragraphs: [
              'Some people notice changes in energy, mood, or skin around this time, but research doesn\'t show a consistent pattern, and many people notice no difference. Estrogen also interacts with cervical crypts, transitioning cervical fluid from dry or creamy to slippery, fertile fluid as ovulation approaches.',
            ],
          ),
        ],
      );

  // --- Article 3: Understanding Ovulation ---
  static const CycleLiteracyArticle understandingOvulation =
      CycleLiteracyArticle(
        id: 'understanding-ovulation',
        title: 'Understanding Ovulation & The Fertile Window',
        summary: 'The science behind the LH surge, egg release, and the biological window of fertility.',
        category: CycleLiteracyCategory.fertility,
        readingTimeMinutes: 3,
        sources: [_acogFertilityAwareness, _wilcoxOvulationTiming, _nhsFertility],
        reviewDate: _round3RetrievedDate,
        relatedSubphases: [CycleSubphase.ovulation],
        sections: [
          ArticleSection(
            heading: 'The Ovulatory Surge',
            paragraphs: [
              'When estrogen levels reach a critical peak, they trigger a rapid surge of Luteinizing Hormone (LH) from the pituitary. Usually about 24 to 36 hours after this surge begins (sometimes up to about two days), the dominant follicle ruptures, releasing a mature egg.',
              'Once released, the egg survives in the fallopian tube for only 12 to 24 hours. If it is not fertilized within this timeframe, it naturally dissolves.',
            ],
          ),
          ArticleSection(
            heading: 'The Fertile Window',
            paragraphs: [
              'Although the egg lives for only about a day, sperm can survive for up to 5 days — and the NHS notes that sperm can survive in the fallopian tubes for up to 7 days after sex. So pregnancy can happen from sex in the 5 days before ovulation, on the day of ovulation, and — by ACOG\'s count — the day after.',
              'Important note: the dates in this app are estimates from past cycle lengths. They are not a birth control method and must not be used to prevent pregnancy.',
            ],
          ),
        ],
      );

  // --- Article 4: Luteal Phase & Progesterone ---
  static const CycleLiteracyArticle lutealPhaseAndProgesterone =
      CycleLiteracyArticle(
        id: 'luteal-phase-and-progesterone',
        title: 'The Luteal Phase: Progesterone and Body Temperature',
        summary: 'The role of the corpus luteum in producing progesterone, stabilizing the endometrium, and raising basal temperature.',
        category: CycleLiteracyCategory.phases,
        readingTimeMinutes: 2,
        sources: [
          _williamsObstetrics,
          _yenAndJaffe,
          _acogMenstrualCycle,
          _acogFertilityAwareness,
        ],
        reviewDate: _currentReviewDate,
        relatedSubphases: [CycleSubphase.earlyLuteal, CycleSubphase.midLuteal],
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
    summary: 'What researchers think happens in PMS: hormone levels are usually normal, but the brain may be extra sensitive to their rise and fall.',
    category: CycleLiteracyCategory.bodyAndSymptoms,
    readingTimeMinutes: 3,
    sources: [_acogCpgNo7, _rcogPremenstrualSyndrome, _nhsPms],
    reviewDate: _currentReviewDate,
    relatedSubphases: [CycleSubphase.midLuteal, CycleSubphase.lateLuteal],
    sections: [
      ArticleSection(
        heading: 'What Causes Premenstrual Symptoms?',
        paragraphs: [
          'Premenstrual syndrome (PMS) refers to a collection of physical, cognitive, and emotional symptoms that occur during the late luteal phase and resolve shortly after menses begins.',
          'Hormone levels in people with PMS are usually normal. Researchers think some people are more sensitive to the normal rise and fall of estrogen and progesterone after ovulation, but the exact cause isn\'t known.',
        ],
      ),
      ArticleSection(
        heading: 'Serotonin and GABA Interactions',
        paragraphs: [
          'Progesterone metabolites (such as allopregnanolone) interact directly with GABA receptors in the brain, which regulate calm and anxiety. As progesterone rises and then falls after ovulation, researchers think this shifts GABA and serotonin signaling, which may contribute to premenstrual mood sensitivity, sleep disruptions, and sugar cravings.',
          'Tracking premenstrual symptoms over several cycles helps identify personal patterns and supports productive discussions with your healthcare provider if symptoms become disruptive.',
        ],
      ),
      ArticleSection(
        heading: 'If You Feel Hopeless or Need Help Now',
        paragraphs: [],
        callout: CrisisResources(text: _crisisParagraphText),
      ),
    ],
  );

  // --- Article 6: Why Do Cramps Happen ---
  static const CycleLiteracyArticle whyCrampsHappen = CycleLiteracyArticle(
    id: 'why-cramps-happen',
    title: 'Why Do Cramps Happen? Prostaglandins and Menstrual Pain',
    summary: 'The biological mechanism of dysmenorrhea: uterine muscle contractions driven by prostaglandins, and when to speak with a doctor.',
    category: CycleLiteracyCategory.bodyAndSymptoms,
    readingTimeMinutes: 3,
    sources: [_acogPainfulPeriods, _nhsPeriodPain],
    reviewDate: _currentReviewDate,
    relatedSubphases: [CycleSubphase.lateLuteal, CycleSubphase.earlyFollicular],
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
              'Prostaglandin levels are highest on the first day or two of a period, which is why cramps are usually worst on Cycle Days 1 and 2.',
              'Prostaglandins can also affect the gut, causing loose stools or nausea, and period pain often spreads to the lower back and thighs.',
              'While mild to moderate cramps are very common, pain that interferes with school, work, or daily activities warrants an evaluation by a healthcare professional. Get help urgently if pain is severe and pain relievers haven\'t helped, or if it\'s much worse than usual — in the UK, ask for an urgent GP appointment or contact NHS 111. Pain that keeps getting worse over months is also worth checking.',
        ],
      ),
    ],
  );

  // --- Article 7: Cycle Length & Variability ---
  static const CycleLiteracyArticle cycleLengthVariability =
      CycleLiteracyArticle(
        id: 'cycle-length-variability',
        title: 'Cycle Length & Natural Variation: What Is "Normal"?',
        summary: 'Why cycles fluctuate naturally, how adolescent and adult variations differ, and what variation means for health.',
        category: CycleLiteracyCategory.variability,
        readingTimeMinutes: 3,
        sources: [
          _figoMenstrualDisorders,
          _whoMenstrualHealth,
          _acogCommitteeOpinion651,
          _acogYourFirstPeriod,
          _aapHealthyChildrenMenstrualDisorders,
        ],
        reviewDate: _currentReviewDate,
        relatedSubphases: [
          CycleSubphase.earlyFollicular,
          CycleSubphase.lateLuteal,
        ],
        sections: [
          ArticleSection(
            heading: 'The Myth of the 28-Day Clockwork Cycle',
            paragraphs: [
              'Only a small fraction of individuals have exactly 28-day cycles every month. In healthy adults, the gap between the shortest and longest cycle is usually up to about 7 to 9 days, depending on age.',
              'Factors such as psychological stress, travel, illness, shifts in sleep schedule, and vigorous exercise can transiently delay follicular development and shift ovulation date, extending that month\'s cycle.',
            ],
          ),
          ArticleSection(
            heading: 'The First Few Years',
            paragraphs: [
              'For the first two to three years after a first period, cycles are often longer and less predictable — most fall between about 21 and 45 days. An occasional longer cycle can happen, but if periods come more than 45 days apart, or you go 3 months (90 days) without one, check in with a doctor.',
              'Once cycles have settled, an adult cycle generally falls between about 21 and 35 days, and a few days of month-to-month variation remains normal.',
            ],
          ),
          ArticleSection(
            heading: 'When to Ask a Doctor',
            paragraphs: [
              'Check in with a healthcare professional if: you go 3 months (90 days) without a period — even if your cycles were never regular; bleeding lasts more than 7 days; you need to change a soaked pad or tampon every 1 to 2 hours; or you pass clots the size of a quarter (about 2.5 cm) or bigger. If you\'ve had sex and your period is late, take a pregnancy test. Get help right away if you feel dizzy or light-headed, or your heart is racing, while you\'re bleeding.',
            ],
          ),
        ],
      );

  // --- Article 8: First Periods: First Two Years (Issue #854) ---
  static const CycleLiteracyArticle firstPeriodsFirstTwoYears =
      CycleLiteracyArticle(
        id: 'first-periods-first-two-years',
        title: 'First Periods: What to Expect in the First Two Years',
        summary: 'Why early cycles take time to find a rhythm, how the body adjusts, and what is completely normal when starting out.',
        category: CycleLiteracyCategory.variability,
        audience: CycleLiteracyAudience.teen,
        readingTimeMinutes: 3,
        sources: [_acogCommitteeOpinion651, _acogYourFirstPeriod],
        reviewDate: _currentReviewDate,
        relatedSubphases: [
          CycleSubphase.earlyFollicular,
          CycleSubphase.lateFollicular,
        ],
        sections: [
          ArticleSection(
            heading: 'Finding Your Rhythm',
            paragraphs: [
              'It often takes two to three years after menarche (your first period) for cycles to settle — and for some people it takes six years or more. In these early years, the reproductive system is still practicing and maturing.',
              'It is very common for cycles to vary widely at first. Some cycles may be 24 days long and the next 40 days — cycles between about 21 and 45 days are normal at this stage. If a period comes more than 45 days after the last one, or you go 3 months without one, talk with a parent or doctor. If you\'ve had sex and your period is late, take a pregnancy test.',
            ],
          ),
          ArticleSection(
            heading: 'What a Normal Early Cycle Looks Like',
            paragraphs: [
              'Bleeding typically lasts between 2 and 7 days. Flow may be light and brownish on some days, or brighter red with occasional small clots on others.',
              'Mild cramps are common: before and during a period the uterus makes prostaglandins, which make its muscles tighten to shed the lining. Some people also get sore breasts before a period, from normal hormone changes.',
            ],
          ),
          ArticleSection(
            heading: 'Tracking and Self-Advocacy',
            paragraphs: [
              'Logging your bleeding days helps you discover your own unique rhythm rather than comparing yourself to a textbook schedule. If bleeding lasts more than 7 days, if you need to change pads or tampons every 1 to 2 hours, or if severe pain disrupts school, talk with a parent or doctor. Get help right away if you feel dizzy or light-headed, or your heart is racing, while you\'re bleeding.',
            ],
          ),
        ],
      );

  // --- Article 9: What Irregular Means at 13 (Issue #854) ---
  static const CycleLiteracyArticle whatIrregularMeansAt13 =
      CycleLiteracyArticle(
        id: 'what-irregular-means-at-13',
        title: "What 'Irregular' Really Means at 13",
        summary: 'Why an unpredictable cycle during puberty is typical biology, not an illness or defect.',
        category: CycleLiteracyCategory.variability,
        audience: CycleLiteracyAudience.teen,
        readingTimeMinutes: 3,
        sources: [
          _acogCommitteeOpinion651,
          _acogYourFirstPeriod,
          _aapHealthyChildrenMenstrualDisorders,
        ],
        reviewDate: _currentReviewDate,
        relatedSubphases: [
          CycleSubphase.earlyFollicular,
          CycleSubphase.lateLuteal,
        ],
        sections: [
          ArticleSection(
            heading: 'Anovulatory Cycles and Maturation',
            paragraphs: [
              'During the first few years after starting menstruation, many cycles are anovulatory—meaning an egg is not released every single month. Without ovulation, there is no consistent luteal phase to set a regular cycle length.',
              'Because the uterine lining continues to build up until estrogen levels shift, the timing and flow of bleeding naturally fluctuate. This irregularity is a standard developmental stage, not a sign of hormone failure.',
            ],
          ),
          ArticleSection(
            heading: 'How Long Does It Take to Become Regular?',
            paragraphs: [
              'Most adolescents begin experiencing more predictable, ovulatory cycles within two to three years after their first period — and for some it takes six years or more. Slight variation from month to month can remain normal throughout life.',
              'Stress, illness, changes in nutrition, and intense sports training can also temporarily shift cycle timing by pausing ovulation.',
            ],
          ),
          ArticleSection(
            heading: 'When to Speak with a Doctor',
            paragraphs: [
              'While cycle length variation is normal, medical guidelines say to see a healthcare professional if: periods come more often than every 21 days or less often than every 45 days; 90 days go by without a period — even once; periods that had been coming regularly become irregular for several months; bleeding lasts more than 7 days; you need to change a soaked pad or tampon every 1 to 2 hours; or your periods are heavy and you bruise or bleed easily, or someone in your family has a bleeding disorder. If you\'ve had sex and your period is late, take a pregnancy test.',
              'If you haven\'t had a first period by age 15, or within 3 years of your breasts starting to develop, that\'s worth a check-up too. So is having no breast development by 13, or no period by 14 with excess hair growth, or with extreme exercise or an eating disorder.',
            ],
          ),
        ],
      );

  // --- Article 10: Talking About Cycles: Teens & Parents (Issue #854) ---
  static const CycleLiteracyArticle talkingAboutCyclesTeensParents =
      CycleLiteracyArticle(
        id: 'talking-about-cycles-teens-parents',
        title: 'Cycle Conversations: Talking Between Teens and Parents',
        summary: 'How guardians and teens can discuss cycle changes, privacy boundaries, and practical support with confidence.',
        category: CycleLiteracyCategory.bodyAndSymptoms,
        audience: CycleLiteracyAudience.guardian,
        readingTimeMinutes: 3,
        sources: [
          _aapHealthyChildrenMenstrualDisorders,
          _acogYourFirstPeriod,
        ],
        reviewDate: _currentReviewDate,
        relatedSubphases: [
          CycleSubphase.earlyFollicular,
          CycleSubphase.lateLuteal,
        ],
        sections: [
          ArticleSection(
            heading: 'Opening Low-Pressure Dialogues',
            paragraphs: [
              'Conversations about menstrual cycles are most helpful when treated as routine, practical health topics rather than urgent or emotional events. Demystifying bodily changes early builds confidence.',
              'Focus on preparedness: ensuring menstrual supplies are readily accessible at home and in backpacks, discussing what cramps feel like, and planning ahead for school days.',
            ],
          ),
          ArticleSection(
            heading: 'Respecting Autonomy and Privacy',
            paragraphs: [
              'As adolescents grow, privacy boundaries naturally shift. Providing support does not require examining every symptom or reading personal reflections.',
              'Encourage your teen to track their own symptoms and cycle timing. Offer to review patterns together if concerns arise, while respecting their personal health diary space.',
            ],
          ),
          ArticleSection(
            heading: 'Partnering for Clinical Care',
            paragraphs: [
              'Involve your teen directly in their healthcare visits. Encourage them to ask their pediatrician questions about pain management, flow, or irregularities, establishing strong self-advocacy skills for the future.',
            ],
          ),
        ],
      );

  // --- Article 11: PMS vs Mood Shifts (Issue #854) ---
  static const CycleLiteracyArticle pmsVsMoodWhenToAskClinician =
      CycleLiteracyArticle(
        id: 'pms-vs-mood-when-to-ask-clinician',
        title: 'PMS vs. Mood Shifts: When to Ask a Clinician',
        summary: 'Distinguishing normal hormonal mood fluctuations from persistent symptoms that deserve medical support.',
        category: CycleLiteracyCategory.bodyAndSymptoms,
        audience: CycleLiteracyAudience.all,
        readingTimeMinutes: 3,
        sources: [_acogCpgNo7, _nhsPms],
        reviewDate: _currentReviewDate,
        relatedSubphases: [CycleSubphase.earlyLuteal, CycleSubphase.lateLuteal],
        sections: [
          ArticleSection(
            heading: 'Hormones and Emotions',
            paragraphs: [
              'In the second half of the cycle (the luteal phase), progesterone rises and then drops before menstruation. These hormonal shifts interact with brain chemicals such as serotonin, which can trigger temporary changes in mood, energy, sleep, or irritability.',
              'Mild premenstrual symptoms affect most menstruating individuals and generally begin a few days before bleeding starts.',
            ],
          ),
          ArticleSection(
            heading: 'Tracking the Cyclical Pattern',
            paragraphs: [
              'The defining hallmark of Premenstrual Syndrome (PMS) is its timing: symptoms appear consistently during the luteal phase and clear up within a few days of your period starting, followed by a symptom-free follicular phase.',
              'If mood changes or tiredness last all month, no matter the cycle day, it may be something other than PMS — like depression or anxiety, which can also get worse before a period. That\'s worth checking with a doctor.',
            ],
          ),
          ArticleSection(
            heading: 'When to Seek Clinical Care',
            paragraphs: [
              'Reach out to a doctor if mood symptoms significantly interfere with daily life, school, work, or relationships, or if you feel overwhelmed or anxious. More severe premenstrual conditions, such as Premenstrual Dysphoric Disorder (PMDD), have treatments that can help, so it\'s worth asking.',
            ],
            callout: CrisisResources(text: _crisisParagraphText),
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
    firstPeriodsFirstTwoYears,
    whatIrregularMeansAt13,
    talkingAboutCyclesTeensParents,
    pmsVsMoodWhenToAskClinician,
  ];

  /// Look up an article by its unique [id].
  static CycleLiteracyArticle? getArticleById(String id) {
    for (final article in allArticles) {
      if (article.id == id) return article;
    }
    return null;
  }

  /// Retrieve articles that contextually relate to [subphase].
  static List<CycleLiteracyArticle> getArticlesForSubphase(
    CycleSubphase subphase,
  ) {
    return allArticles
        .where((article) => article.relatedSubphases.contains(subphase))
        .toList();
  }

  /// Retrieve articles categorized under [category].
  static List<CycleLiteracyArticle> getArticlesByCategory(
    CycleLiteracyCategory category,
  ) {
    return allArticles
        .where((article) => article.category == category)
        .toList();
  }

  /// Retrieve articles intended for [audience], including articles for all audiences.
  static List<CycleLiteracyArticle> getArticlesForAudience(
    CycleLiteracyAudience audience,
  ) {
    if (audience == CycleLiteracyAudience.all) return allArticles;
    return allArticles
        .where(
          (article) =>
              article.audience == audience ||
              article.audience == CycleLiteracyAudience.all,
        )
        .toList();
  }

  /// Retrieve articles targeted specifically to [audience] (excluding general [CycleLiteracyAudience.all]).
  static List<CycleLiteracyArticle> getArticlesForExactAudience(
    CycleLiteracyAudience audience,
  ) {
    return allArticles
        .where((article) => article.audience == audience)
        .toList();
  }
}
