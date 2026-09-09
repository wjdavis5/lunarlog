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
  ];

  test('taxonomy has exactly 45 codes across 15 categories', () {
    expect(kTagTaxonomy, hasLength(45));
    // Codes exist for the 10 attested categories; the 5 unverified ones
    // (kUnverifiedTagCategories) deliberately carry none — see their own
    // test below.
    expect(kTagTaxonomy.map((t) => t.category).toSet(), hasLength(10));
    expect(TagCategory.values, hasLength(15));
    expect(kTagTaxonomy.map((t) => t.code).toSet(), hasLength(45),
        reason: 'codes must be unique');
  });

  test('every pre-#249 code survives unchanged (code stability rule)', () {
    final codes = kTagTaxonomy.map((t) => t.code).toSet();
    for (final code in legacyCodes) {
      expect(codes.contains(code), isTrue,
          reason: 'legacy code "$code" must never be renamed away');
    }
  });

  test('categories carry the issue #249 code sets', () {
    Iterable<String> codes(TagCategory c) =>
        kTagTaxonomy.where((t) => t.category == c).map((t) => t.code);

    expect(
      codes(TagCategory.pain).toSet(),
      {
        'cramps',
        'headache',
        'back_pain',
        'breast_tenderness',
        'ovulation',
        'migraine',
        'migraine_with_aura',
        'pain_free',
      },
    );
    expect(codes(TagCategory.energy).toSet(),
        {'energetic', 'fully_energized', 'tired', 'exhausted', 'fatigue'});
    expect(codes(TagCategory.sleep).toSet(),
        {'sleep_trouble', '0_to_3_hours', '3_to_6_hours', '6_to_9_hours', '9_or_more_hours'});
    expect(codes(TagCategory.skin).toSet(),
        {'acne', 'good_skin', 'oily_skin', 'dry_skin'});
    expect(codes(TagCategory.hair).toSet(),
        {'good_hair', 'bad_hair', 'oily_hair', 'dry_hair'});
    expect(codes(TagCategory.digestion).toSet(),
        {'bloating', 'nausea', 'gassy', 'great_digestion'});
    expect(codes(TagCategory.stool).toSet(),
        {'normal', 'constipated', 'great_stool', 'diarrhea'});
    expect(codes(TagCategory.cravings).toSet(),
        {'cravings', 'sweet', 'salty', 'carbs', 'chocolate'});
    expect(codes(TagCategory.body).toSet(), {'dizziness'});
    expect(
      codes(TagCategory.mood).toSet(),
      {'irritable', 'sad', 'anxious', 'calm', 'sensitive'},
    );
  });

  test('re-parenting moves categories, never code strings', () {
    expect(tagByCode('energetic')!.category, TagCategory.energy,
        reason: 'energetic was misfiled under mood');
    expect(tagByCode('fatigue')!.category, TagCategory.energy,
        reason: 'fatigue was misfiled under body');
    expect(tagByCode('bloating')!.category, TagCategory.digestion);
    expect(tagByCode('nausea')!.category, TagCategory.digestion);
    expect(tagByCode('acne')!.category, TagCategory.skin);
    expect(tagByCode('sleep_trouble')!.category, TagCategory.sleep,
        reason: 'sleep_trouble stays as a lunarlog extra alongside the '
            'duration buckets, not replaced by them');
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
    expect(() => validateTagCodes(['cravings', 'chocolate']),
        returnsNormally);
  });

  test('unverified categories exist in the enum but carry no codes', () {
    expect(kUnverifiedTagCategories, hasLength(5));
    expect(
      kUnverifiedTagCategories.toSet(),
      {
        TagCategory.sleepQuality,
        TagCategory.breastsChest,
        TagCategory.hotFlashes,
        TagCategory.urine,
        TagCategory.vulvaVagina,
      },
    );
    for (final category in kUnverifiedTagCategories) {
      expect(
        kTagTaxonomy.where((t) => t.category == category),
        isEmpty,
        reason: '$category is unverified — do not invent codes for it',
      );
    }
  });

  test('every tag has a non-empty default display string', () {
    for (final tag in kTagTaxonomy) {
      expect(tag.display.trim(), isNotEmpty, reason: tag.code);
    }
    expect(tagByCode('back_pain')!.display, 'Back pain');
    expect(tagByCode('sleep_trouble')!.display, 'Sleep trouble');
    expect(tagByCode('cravings')!.display, 'Cravings (unspecified)');
  });

  test('displays are unique across the taxonomy (no ambiguous chips)', () {
    final displays = kTagTaxonomy.map((t) => t.display).toList();
    expect(displays.toSet(), hasLength(displays.length),
        reason: 'a duplicated display renders two indistinguishable chips');
  });

  test('lookup and validation', () {
    expect(tagByCode('cramps')!.category, TagCategory.pain);
    expect(tagByCode('nope'), isNull);
    expect(isValidTagCode('cramps'), isTrue);
    expect(isValidTagCode('Cramps'), isFalse, reason: 'codes are case-sensitive');
    expect(isValidTagCode('ovulation'), isTrue,
        reason: 'ovulation pain is an attested pain option (issue #249)');
    expect(() => validateTagCodes(['cramps', 'not-a-tag']), throwsArgumentError);
    expect(() => validateTagCodes(['cramps', 'calm', 'cravings']),
        returnsNormally);
    expect(() => validateTagCodes(const []), returnsNormally);
  });

  group('pain_free is a positive assertion, never a symptom (issue #249)', () {
    test('it is a real, valid pain-category code that round-trips', () {
      expect(kPainFreeCode, 'pain_free');
      expect(tagByCode(kPainFreeCode)!.category, TagCategory.pain);
      expect(() => validateTagCodes([kPainFreeCode]), returnsNormally);
    });

    test('hasSymptomTags ignores it', () {
      expect(hasSymptomTags(['pain_free']), isFalse);
      expect(hasSymptomTags(['pain_free', 'headache']), isTrue);
      expect(hasSymptomTags(['cramps']), isTrue);
      expect(hasSymptomTags(const <String>[]), isFalse);
    });
  });

  test('taxonomy vocabulary guard: no fertility terms in any code or display, '
      'except the attested ovulation pain symptom (issue #249 — a pain '
      'option, not a fertility-status claim)', () {
    const stems = ['fertili', 'luteal', 'follicular', 'concei'];
    for (final tag in kTagTaxonomy) {
      for (final stem in stems) {
        expect(
          '${tag.code} ${tag.display}'.toLowerCase().contains(stem),
          isFalse,
          reason: 'tag "${tag.code}" leaks forbidden vocabulary "$stem"',
        );
      }
    }
    // Exactly one exemption, and it is the documented one: `ovulation` the
    // *pain* option. No other tag may carry the stem.
    final ovulationStemTags = [
      for (final tag in kTagTaxonomy)
        if ('${tag.code} ${tag.display}'.toLowerCase().contains('ovulat'))
          tag.code,
    ];
    expect(ovulationStemTags, ['ovulation']);
  });
}
