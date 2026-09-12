import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/tags.dart';

void main() {
  // Issue #249's code-stability rule: these pre-existing codes are never
  // renamed or recoded. Their category grouping may change (and did —
  // see the per-category sets below); the strings themselves may not.
  const legacyCodes = [
    'cramps',
    'headache',
    'back_pain',
    'breast_tenderness',
    'bloating',
    'nausea',
    'acne',
    'energetic',
    'fatigue',
    'cravings',
    'sleep_trouble',
    // Issue #251: the five pre-#251 mood codes keep their exact strings
    // too — only their category grouping changes (see the re-parenting
    // test below).
    'irritable',
    'sad',
    'anxious',
    'calm',
    'sensitive',
  ];

  test('taxonomy has exactly 108 codes across 31 categories', () {
    expect(kTagTaxonomy, hasLength(108));
    // Codes exist for the 21 attested categories; the 10 unverified ones
    // (kUnverifiedTagCategories) deliberately carry none — see their own
    // test below.
    expect(kTagTaxonomy.map((t) => t.category).toSet(), hasLength(21));
    expect(TagCategory.values, hasLength(31));
    expect(
      kTagTaxonomy.map((t) => t.code).toSet(),
      hasLength(108),
      reason: 'codes must be unique',
    );
  });

  test('every pre-#249 code survives unchanged (code stability rule)', () {
    final codes = kTagTaxonomy.map((t) => t.code).toSet();
    for (final code in legacyCodes) {
      expect(
        codes.contains(code),
        isTrue,
        reason: 'legacy code "$code" must never be renamed away',
      );
    }
  });

  test('categories carry the issue #249 code sets', () {
    Iterable<String> codes(TagCategory c) =>
        kTagTaxonomy.where((t) => t.category == c).map((t) => t.code);

    expect(codes(TagCategory.pain).toSet(), {
      'cramps',
      'headache',
      'back_pain',
      'breast_tenderness',
      'ovulation',
      'migraine',
      'migraine_with_aura',
      'pain_free',
    });
    expect(codes(TagCategory.energy).toSet(), {
      'energetic',
      'fully_energized',
      'tired',
      'exhausted',
      'fatigue',
    });
    expect(codes(TagCategory.sleep).toSet(), {
      'sleep_trouble',
      '0_to_3_hours',
      '3_to_6_hours',
      '6_to_9_hours',
      '9_or_more_hours',
    });
    expect(codes(TagCategory.skin).toSet(), {
      'acne',
      'good_skin',
      'oily_skin',
      'dry_skin',
    });
    expect(codes(TagCategory.hair).toSet(), {
      'good_hair',
      'bad_hair',
      'oily_hair',
      'dry_hair',
    });
    expect(codes(TagCategory.digestion).toSet(), {
      'bloating',
      'nausea',
      'gassy',
      'great_digestion',
    });
    expect(codes(TagCategory.stool).toSet(), {
      'normal',
      'constipated',
      'great_stool',
      'diarrhea',
    });
    expect(codes(TagCategory.cravings).toSet(), {
      'cravings',
      'sweet',
      'salty',
      'carbs',
      'chocolate',
    });
    expect(codes(TagCategory.body).toSet(), {'dizziness'});
    // Issue #251: the old `mood` grouping is rebuilt as feelings/mind —
    // its codes re-parented with their exact strings, and the `mood`
    // enum value itself removed (a zero-code category that is not
    // option-set-unverified would render the unverified caption
    // dishonestly).
    expect(codes(TagCategory.feelings).toSet(), {
      'irritable',
      'happy',
      'sad',
      'angry',
      'anxious',
      'indifferent',
      'sensitive',
      'mood_swings',
      'excited',
      'insecure',
      'grateful',
    });
    expect(codes(TagCategory.mind).toSet(), {
      'calm',
      'distracted',
      'focused',
      'stressed',
    });
    expect(codes(TagCategory.motivation).toSet(), {
      'motivated',
      'unmotivated',
      'productive',
      'unproductive',
    });
    expect(codes(TagCategory.socialLife).toSet(), {
      'sociable',
      'withdrawn',
      'supportive',
      'conflict',
    });
    expect(codes(TagCategory.partying).toSet(), {
      'drinks',
      'cigarettes',
      'big_night',
      'hangover',
    });
    // Issue #252: the events-and-care categories carry their attested
    // option sets exactly.
    expect(codes(TagCategory.collectionMethod).toSet(), {
      'pad',
      'tampon',
      'panty_liner',
      'menstrual_cup',
    });
    expect(codes(TagCategory.exercise).toSet(), {
      'running',
      'yoga',
      'biking',
      'swimming',
      'walking',
      'pilates',
      'rest_day',
    });
    expect(codes(TagCategory.medication).toSet(), {
      'pain',
      'cold_flu_medication',
      'antihistamine',
      'antibiotic',
    });
    expect(codes(TagCategory.ailments).toSet(), {
      'cold_flu_ailments',
      'allergy',
      'injury',
      'fever',
    });
    // Issue #253: the sensitive and fertility categories carry their
    // attested/designed option sets exactly.
    expect(codes(TagCategory.sexLife).toSet(), {
      'no_sex_today',
      'low_sex_drive',
      'high_sex_drive',
      'masturbation',
      'withdrawal',
      'protected_sex',
      'unprotected_sex',
      'sex_toys',
      'orgasm',
      'no_orgasm',
      'fantasies',
      'painful_intercourse',
    });
    expect(codes(TagCategory.discharge).toSet(), {
      'none',
      'sticky',
      'creamy',
      'egg_white',
      'atypical',
    });
    expect(codes(TagCategory.tests).toSet(), {
      'ovulation_negative',
      'ovulation_positive',
      'ovulation_peak',
      'pregnancy_negative',
      'pregnancy_positive',
    });
  });

  test('issue #251 re-parenting moves categories, never code strings', () {
    expect(
      tagByCode('sad')!.category,
      TagCategory.feelings,
      reason: 'sad keeps its exact code; only the grouping changes',
    );
    expect(tagByCode('anxious')!.category, TagCategory.feelings);
    expect(tagByCode('sensitive')!.category, TagCategory.feelings);
    expect(
      tagByCode('irritable')!.category,
      TagCategory.feelings,
      reason:
          'irritable is preserved as the lunarlog-specific extra '
          'under feelings — no Clue equivalent, never dropped',
    );
    expect(
      tagByCode('calm')!.category,
      TagCategory.mind,
      reason: 'calm was misfiled under mood; Clue files it under Mind',
    );
    // And the pre-#249 re-parents are untouched.
    expect(tagByCode('energetic')!.category, TagCategory.energy);
  });

  test('re-parenting moves categories, never code strings', () {
    expect(
      tagByCode('energetic')!.category,
      TagCategory.energy,
      reason: 'energetic was misfiled under mood',
    );
    expect(
      tagByCode('fatigue')!.category,
      TagCategory.energy,
      reason: 'fatigue was misfiled under body',
    );
    expect(tagByCode('bloating')!.category, TagCategory.digestion);
    expect(tagByCode('nausea')!.category, TagCategory.digestion);
    expect(tagByCode('acne')!.category, TagCategory.skin);
    expect(
      tagByCode('sleep_trouble')!.category,
      TagCategory.sleep,
      reason:
          'sleep_trouble stays as a lunarlog extra alongside the '
          'duration buckets, not replaced by them',
    );
  });

  test('breast_tenderness stays under pain, distinct from breasts_chest', () {
    expect(tagByCode('breast_tenderness')!.category, TagCategory.pain);
    // The separate breasts_chest category exists but ships no codes yet
    // (option set unverified) — the two are never merged.
    expect(
      kTagTaxonomy.where((t) => t.category == TagCategory.breastsChest),
      isEmpty,
    );
    expect(
      kTagTaxonomy
          .where((t) => t.category == TagCategory.pain)
          .map((t) => t.code),
      contains('breast_tenderness'),
    );
  });

  test('the legacy cravings boolean code remains a cravings-category member '
      'alongside the four attested options (unspecified craving)', () {
    final cravings = tagByCode('cravings')!;
    expect(cravings.category, TagCategory.cravings);
    for (final option in ['sweet', 'salty', 'carbs', 'chocolate']) {
      expect(tagByCode(option)!.category, TagCategory.cravings);
    }
    // Readable and writable: validation still accepts it.
    expect(() => validateTagCodes(['cravings', 'chocolate']), returnsNormally);
  });

  test('unverified categories exist in the enum but carry no codes', () {
    expect(kUnverifiedTagCategories, hasLength(10));
    expect(kUnverifiedTagCategories.toSet(), {
      TagCategory.sleepQuality,
      TagCategory.breastsChest,
      TagCategory.hotFlashes,
      TagCategory.urine,
      TagCategory.vulvaVagina,
      // Issue #251's three: pms (presence-based; the presence marker
      // itself rides day_entries.pms per issue #220, outside this
      // taxonomy), meditation, and leisure (option sets undocumented).
      TagCategory.pms,
      TagCategory.meditation,
      TagCategory.leisure,
      // Issue #252's two: appointments (category confirmed single-event
      // data, exact option strings not publicly enumerated) and
      // supplements (Clue Plus-only, nothing enumerated).
      TagCategory.appointments,
      TagCategory.supplements,
    });
    for (final category in kUnverifiedTagCategories) {
      expect(
        kTagTaxonomy.where((t) => t.category == category),
        isEmpty,
        reason: '$category is unverified — do not invent codes for it',
      );
    }
  });

  test('issue #252: cold/flu is category-qualified, never a bare shared '
      'code; the medication pain display never reads as the Pain category', () {
    // The attested `cold/flu` option exists under both medication and
    // ailments; in this flat day-entry tag namespace each instance is
    // category-qualified (the great_digestion/great_stool pattern).
    expect(tagByCode('cold_flu_medication')!.category, TagCategory.medication);
    expect(tagByCode('cold_flu_ailments')!.category, TagCategory.ailments);
    expect(
      tagByCode('cold_flu'),
      isNull,
      reason:
          'a bare cold_flu code would be ambiguous across the two '
          'categories',
    );
    // The medication `pain` option keeps the attested code; its display
    // is qualified so it can never be mistaken for the Pain category
    // heading ("Cravings (unspecified)" precedent).
    expect(tagByCode('pain')!.category, TagCategory.medication);
    expect(tagByCode('pain')!.display, 'Pain (medication)');
    expect(tagByCode('cold_flu_medication')!.display, 'Cold/flu (medication)');
    expect(tagByCode('cold_flu_ailments')!.display, 'Cold/flu (ailments)');
  });

  test('issue #252: collection method carries the four attested options; '
      'period underwear is deliberately absent (unverified) and extensible '
      'without a schema change', () {
    for (final option in ['pad', 'tampon', 'panty_liner', 'menstrual_cup']) {
      expect(tagByCode(option)!.category, TagCategory.collectionMethod);
      expect(() => validateTagCodes([option]), returnsNormally);
    }
    expect(
      tagByCode('period_underwear'),
      isNull,
      reason:
          'widely reported but unverified — no invented code; adding '
          'it later is a one-line data addition (observations.code is '
          'free text, so no schema change is ever needed)',
    );
  });

  test('issue #252: the single-event categories are exactly appointments, '
      'medication, and ailments', () {
    expect(kSingleEventTagCategories, hasLength(3));
    expect(kSingleEventTagCategories, {
      TagCategory.appointments,
      TagCategory.medication,
      TagCategory.ailments,
    });
    // Birth control, the issue's fourth single-event example, is absent:
    // issue #260 ships it as its own model outside this taxonomy.
    expect(
      kSingleEventTagCategories.contains(TagCategory.collectionMethod),
      isFalse,
    );
  });

  test('every tag has a non-empty default display string', () {
    for (final tag in kTagTaxonomy) {
      expect(tag.display.trim(), isNotEmpty, reason: tag.code);
    }
    expect(tagByCode('back_pain')!.display, 'Back pain');
    expect(tagByCode('sleep_trouble')!.display, 'Sleep trouble');
    expect(tagByCode('cravings')!.display, 'Cravings (unspecified)');
    // Issue #251: Clue's attested "big night" option is snake_cased for
    // the flat code namespace, display keeps the attested phrasing.
    expect(tagByCode('big_night')!.display, 'Big night');
    // Issue #252: multi-word attested options read as their phrases.
    expect(tagByCode('panty_liner')!.display, 'Panty liner');
    expect(tagByCode('rest_day')!.display, 'Rest day');
  });

  test('displays are unique across the taxonomy (no ambiguous chips)', () {
    final displays = kTagTaxonomy.map((t) => t.display).toList();
    expect(
      displays.toSet(),
      hasLength(displays.length),
      reason: 'a duplicated display renders two indistinguishable chips',
    );
  });

  test('lookup and validation', () {
    expect(tagByCode('cramps')!.category, TagCategory.pain);
    expect(tagByCode('nope'), isNull);
    expect(isValidTagCode('cramps'), isTrue);
    expect(
      isValidTagCode('Cramps'),
      isFalse,
      reason: 'codes are case-sensitive',
    );
    expect(
      isValidTagCode('ovulation'),
      isTrue,
      reason: 'ovulation pain is an attested pain option (issue #249)',
    );
    expect(
      () => validateTagCodes(['cramps', 'not-a-tag']),
      throwsArgumentError,
    );
    expect(
      () => validateTagCodes(['cramps', 'calm', 'cravings']),
      returnsNormally,
    );
    // Issue #251 codes validate like any other.
    expect(
      () => validateTagCodes(['happy', 'stressed', 'big_night']),
      returnsNormally,
    );
    // Issue #252 codes validate like any other (multi-select per day is
    // inherent to the tags list).
    expect(
      () => validateTagCodes([
        'tampon',
        'menstrual_cup',
        'running',
        'antihistamine',
        'fever',
      ]),
      returnsNormally,
    );
    expect(() => validateTagCodes(const []), returnsNormally);
  });

  group('positive assertions are never counted or rendered as symptoms', () {
    test('pain_free is a real, valid pain-category code that round-trips '
        '(issue #249)', () {
      expect(kPainFreeCode, 'pain_free');
      expect(tagByCode(kPainFreeCode)!.category, TagCategory.pain);
      expect(() => validateTagCodes([kPainFreeCode]), returnsNormally);
    });

    test('no_sex_today is a real sex_life code and a positive assertion, '
        'never absence of data (issue #253)', () {
      expect(kNoSexTodayCode, 'no_sex_today');
      expect(tagByCode(kNoSexTodayCode)!.category, TagCategory.sexLife);
      // Validates and round-trips like any other code.
      expect(() => validateTagCodes([kNoSexTodayCode]), returnsNormally);
      // It is a positive "did not have sex" assertion, not "no data": it
      // never counts or renders as a symptom and never reads as a missing
      // log.
      expect(kPositiveAssertionCodes, contains(kNoSexTodayCode));
      expect(hasSymptomTags([kNoSexTodayCode]), isFalse);
    });

    test("discharge 'none' is a real discharge code and a positive "
        "'no discharge today' assertion (issue #253)", () {
      expect(kDischargeNoneCode, 'none');
      expect(tagByCode(kDischargeNoneCode)!.category, TagCategory.discharge);
      expect(() => validateTagCodes([kDischargeNoneCode]), returnsNormally);
      expect(kPositiveAssertionCodes, contains(kDischargeNoneCode));
      expect(hasSymptomTags([kDischargeNoneCode]), isFalse);
    });

    test('hasSymptomTags ignores all positive assertions but keeps real '
        'symptoms', () {
      expect(hasSymptomTags(['pain_free']), isFalse);
      expect(hasSymptomTags([kNoSexTodayCode, kDischargeNoneCode]), isFalse);
      expect(
        hasSymptomTags([kNoSexTodayCode, 'headache']),
        isTrue,
        reason: 'a real symptom alongside a positive assertion is a symptom',
      );
      expect(hasSymptomTags(['cramps']), isTrue);
      expect(hasSymptomTags(const <String>[]), isFalse);
    });
  });

  group('discharge is single-select (issue #253)', () {
    test('kSingleSelectTagCategories contains exactly discharge', () {
      expect(kSingleSelectTagCategories, {TagCategory.discharge});
      expect(kSingleSelectTagCategories.contains(TagCategory.sexLife), isFalse);
      expect(kSingleSelectTagCategories.contains(TagCategory.tests), isFalse);
    });
  });
}
