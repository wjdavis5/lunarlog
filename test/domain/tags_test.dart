import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/tags.dart';

void main() {
  test('taxonomy has exactly 17 codes across 4 categories', () {
    expect(kTagTaxonomy, hasLength(17));
    expect(kTagTaxonomy.map((t) => t.category).toSet(),
        {TagCategory.pain, TagCategory.body, TagCategory.mood, TagCategory.other});
    expect(kTagTaxonomy.map((t) => t.code).toSet(), hasLength(17),
        reason: 'codes must be unique');
  });

  test('categories carry the settled code sets (KTD6)', () {
    Iterable<String> codes(TagCategory c) =>
        kTagTaxonomy.where((t) => t.category == c).map((t) => t.code);

    expect(codes(TagCategory.pain).toSet(),
        {'cramps', 'headache', 'back_pain', 'breast_tenderness'});
    expect(codes(TagCategory.body).toSet(),
        {'bloating', 'acne', 'nausea', 'fatigue', 'dizziness'});
    expect(codes(TagCategory.mood).toSet(),
        {'irritable', 'sad', 'anxious', 'calm', 'energetic', 'sensitive'});
    expect(codes(TagCategory.other).toSet(), {'sleep_trouble', 'cravings'});
  });

  test('every tag has a non-empty default display string', () {
    for (final tag in kTagTaxonomy) {
      expect(tag.display.trim(), isNotEmpty, reason: tag.code);
    }
    expect(tagByCode('back_pain')!.display, 'Back pain');
    expect(tagByCode('sleep_trouble')!.display, 'Sleep trouble');
  });

  test('lookup and validation', () {
    expect(tagByCode('cramps')!.category, TagCategory.pain);
    expect(tagByCode('nope'), isNull);
    expect(isValidTagCode('cramps'), isTrue);
    expect(isValidTagCode('Cramps'), isFalse, reason: 'codes are case-sensitive');
    expect(isValidTagCode('ovulation'), isFalse,
        reason: 'no fertility vocabulary in the taxonomy (R13)');
    expect(() => validateTagCodes(['cramps', 'not-a-tag']), throwsArgumentError);
    expect(() => validateTagCodes(['cramps', 'calm', 'cravings']),
        returnsNormally);
    expect(() => validateTagCodes(const []), returnsNormally);
  });

  test('taxonomy vocabulary guard: no fertility terms in any code or display',
      () {
    const stems = ['ovulat', 'fertili', 'luteal', 'follicular', 'concei'];
    for (final tag in kTagTaxonomy) {
      for (final stem in stems) {
        expect(
          '${tag.code} ${tag.display}'.toLowerCase().contains(stem),
          isFalse,
          reason: 'tag "${tag.code}" leaks forbidden vocabulary "$stem"',
        );
      }
    }
  });
}
