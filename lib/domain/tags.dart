/// Symptom tag taxonomy (KTD6, settled): 17 codes in 4 categories.
///
/// Codes are stable identifiers (stored on day entries); [TagCode.display]
/// is the default UI string. No fertility-related vocabulary exists in this
/// taxonomy (R13).
library;

enum TagCategory { pain, body, mood, other }

class TagCode {
  const TagCode(this.code, this.category, this.display);

  /// Stable snake_case identifier persisted on day entries.
  final String code;

  final TagCategory category;

  /// Default display string; the UI may override per locale later.
  final String display;

  @override
  bool operator ==(Object other) => other is TagCode && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// The full taxonomy, grouped by category in settled order.
const List<TagCode> kTagTaxonomy = [
  // pain
  TagCode('cramps', TagCategory.pain, 'Cramps'),
  TagCode('headache', TagCategory.pain, 'Headache'),
  TagCode('back_pain', TagCategory.pain, 'Back pain'),
  TagCode('breast_tenderness', TagCategory.pain, 'Breast tenderness'),
  // body
  TagCode('bloating', TagCategory.body, 'Bloating'),
  TagCode('acne', TagCategory.body, 'Acne'),
  TagCode('nausea', TagCategory.body, 'Nausea'),
  TagCode('fatigue', TagCategory.body, 'Fatigue'),
  TagCode('dizziness', TagCategory.body, 'Dizziness'),
  // mood
  TagCode('irritable', TagCategory.mood, 'Irritable'),
  TagCode('sad', TagCategory.mood, 'Sad'),
  TagCode('anxious', TagCategory.mood, 'Anxious'),
  TagCode('calm', TagCategory.mood, 'Calm'),
  TagCode('energetic', TagCategory.mood, 'Energetic'),
  TagCode('sensitive', TagCategory.mood, 'Sensitive'),
  // other
  TagCode('sleep_trouble', TagCategory.other, 'Sleep trouble'),
  TagCode('cravings', TagCategory.other, 'Cravings'),
];

final Map<String, TagCode> _tagsByCode = {
  for (final tag in kTagTaxonomy) tag.code: tag,
};

/// The taxonomy entry for [code], or null when unknown.
TagCode? tagByCode(String code) => _tagsByCode[code];

bool isValidTagCode(String code) => _tagsByCode.containsKey(code);

/// Throws [ArgumentError] naming the first tag not in the taxonomy.
void validateTagCodes(Iterable<String> tags) {
  for (final tag in tags) {
    if (!_tagsByCode.containsKey(tag)) {
      throw ArgumentError.value(tag, 'tags', 'not a known tag code');
    }
  }
}
