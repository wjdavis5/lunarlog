/// Symptom tag taxonomy (KTD6): 45 codes in 15 categories, expanded from
/// the original 17-code cycle/flow-only set by Issue #249 (the physical
/// categories of Clue's attested taxonomy — pain, energy, sleep, skin,
/// hair, digestion, stool, cravings, plus the option-set-unverified
/// categories).
///
/// Codes are stable identifiers (stored on day entries); [TagCode.display]
/// is the default UI string. **The code-stability rule (Issue #249): an
/// existing code is never renamed or recoded.** Re-parenting changes only
/// the code's [TagCode.category]; the code string itself is untouched, so
/// historical rows referencing it stay valid without any data migration.
/// The 11 pre-#249 physical codes (`cramps`, `headache`, `back_pain`,
/// `breast_tenderness`, `bloating`, `nausea`, `acne`, `energetic`,
/// `fatigue`, `cravings`, `sleep_trouble`) all keep their exact strings.
///
/// Category-scoped option strings that would collide across categories in
/// this flat, day-entry-tag namespace are qualified with a suffix —
/// following the export-string shape Clue itself uses for skin
/// (`good_skin`/`oily_skin`/`dry_skin`) — rather than renamed away from
/// their attested option: `good_hair`/`bad_hair`/`oily_hair`/`dry_hair`,
/// `great_digestion`, `great_stool`. Everything else keeps the raw Clue
/// option string, which is also what the Clue importer's pass-through
/// (`clue_option_map.dart`) writes into `observations.code`, so the two
/// vocabularies line up option-for-option.
///
/// The taxonomy is still not a fertility-status model — see the
/// vocabulary-guard test in test/domain/tags_test.dart. The one apparent
/// exception, pain's `ovulation` option, is an attested *pain* symptom
/// (mittelschmerz, Issue #249's pain row), not a fertility claim; the
/// guard test exempts exactly that code and nothing else.
library;

enum TagCategory {
  pain,
  energy,
  sleep,
  sleepQuality,
  skin,
  hair,
  digestion,
  stool,
  cravings,
  breastsChest,
  hotFlashes,
  urine,
  vulvaVagina,
  body,
  mood,
}

/// The stable snake_case wire name for each category (Issue #259): the key
/// a synced `tracking_preferences` document uses for the category
/// (`sleep_quality`, `breasts_chest`, `vulva_vagina`, ...). Codes are
/// stable identifiers (see the library doc comment); category wire names
/// follow the same rule — never renamed, so a stored preference document
/// outlives client refactors. A table, not a switch: the mapping is data,
/// and a table lookup keeps the getter trivially simple.
const Map<TagCategory, String> _kCategoryWireNames = {
  TagCategory.pain: 'pain',
  TagCategory.energy: 'energy',
  TagCategory.sleep: 'sleep',
  TagCategory.sleepQuality: 'sleep_quality',
  TagCategory.skin: 'skin',
  TagCategory.hair: 'hair',
  TagCategory.digestion: 'digestion',
  TagCategory.stool: 'stool',
  TagCategory.cravings: 'cravings',
  TagCategory.breastsChest: 'breasts_chest',
  TagCategory.hotFlashes: 'hot_flashes',
  TagCategory.urine: 'urine',
  TagCategory.vulvaVagina: 'vulva_vagina',
  TagCategory.body: 'body',
  TagCategory.mood: 'mood',
};

extension TagCategoryWireName on TagCategory {
  String get wireName => _kCategoryWireNames[this]!;
}

final Map<String, TagCategory> _categoryByWireName = {
  for (final entry in _kCategoryWireNames.entries) entry.value: entry.key,
};

/// Inverse of [TagCategoryWireName.wireName]: null for anything this build
/// does not know (a document written by a newer client with a category
/// this build has not adopted yet round-trips but never resolves — see
/// `TrackingPreferences` in `lib/domain/logging/tracking_preferences.dart`).
TagCategory? categoryFromWireName(String name) => _categoryByWireName[name];

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
///
/// Enum order = the default surfacing order for modes that don't override
/// it (`care_modes.dart`'s `categoriesInOrder`), pain first per Issue #249.
/// Categories whose Clue option set is not yet attested ([kUnverifiedTagCategories])
/// deliberately carry no codes at all — never an invented placeholder.
const List<TagCode> kTagTaxonomy = [
  // pain — Issue #249: cramps/headache/back_pain/breast_tenderness keep
  // their codes (Clue's period_cramps/lower_back map onto the first and
  // third at import); breast_tenderness stays here, distinct from the
  // separate breasts_chest category below.
  TagCode('cramps', TagCategory.pain, 'Cramps'),
  TagCode('headache', TagCategory.pain, 'Headache'),
  TagCode('back_pain', TagCategory.pain, 'Back pain'),
  TagCode('breast_tenderness', TagCategory.pain, 'Breast tenderness'),
  TagCode('ovulation', TagCategory.pain, 'Ovulation pain'),
  TagCode('migraine', TagCategory.pain, 'Migraine'),
  TagCode('migraine_with_aura', TagCategory.pain, 'Migraine with aura'),
  TagCode(kPainFreeCode, TagCategory.pain, 'Pain free'),
  // energy — energetic re-parented from mood, fatigue from body (both
  // keep their codes); both remain valid alongside the new graduated set.
  TagCode('energetic', TagCategory.energy, 'Energetic'),
  TagCode('fully_energized', TagCategory.energy, 'Fully energized'),
  TagCode('tired', TagCategory.energy, 'Tired'),
  TagCode('exhausted', TagCategory.energy, 'Exhausted'),
  TagCode('fatigue', TagCategory.energy, 'Fatigue'),
  // sleep — duration buckets; sleep_trouble (quality/problem flag)
  // re-parented from `other` and kept alongside them, not replaced.
  TagCode('sleep_trouble', TagCategory.sleep, 'Sleep trouble'),
  TagCode('0_to_3_hours', TagCategory.sleep, '0-3 hours'),
  TagCode('3_to_6_hours', TagCategory.sleep, '3-6 hours'),
  TagCode('6_to_9_hours', TagCategory.sleep, '6-9 hours'),
  TagCode('9_or_more_hours', TagCategory.sleep, '9+ hours'),
  // skin — acne re-parented from body; good/oily/dry use Clue's own
  // export-string spellings (good_skin/oily_skin/dry_skin).
  TagCode('acne', TagCategory.skin, 'Acne'),
  TagCode('good_skin', TagCategory.skin, 'Good skin'),
  TagCode('oily_skin', TagCategory.skin, 'Oily skin'),
  TagCode('dry_skin', TagCategory.skin, 'Dry skin'),
  // hair
  TagCode('good_hair', TagCategory.hair, 'Good hair'),
  TagCode('bad_hair', TagCategory.hair, 'Bad hair'),
  TagCode('oily_hair', TagCategory.hair, 'Oily hair'),
  TagCode('dry_hair', TagCategory.hair, 'Dry hair'),
  // digestion — bloating/nausea re-parented from body; Clue's `great`
  // option is suffix-qualified (see the library doc comment) because
  // stool's `great` collides with it in this flat namespace.
  TagCode('bloating', TagCategory.digestion, 'Bloating'),
  TagCode('nausea', TagCategory.digestion, 'Nausea'),
  TagCode('gassy', TagCategory.digestion, 'Gassy'),
  TagCode('great_digestion', TagCategory.digestion, 'Great digestion'),
  // stool
  TagCode('normal', TagCategory.stool, 'Normal'),
  TagCode('constipated', TagCategory.stool, 'Constipated'),
  TagCode('great_stool', TagCategory.stool, 'Great stool'),
  TagCode('diarrhea', TagCategory.stool, 'Diarrhea'),
  // cravings — the legacy boolean code stays readable and writable as the
  // "unspecified craving" member alongside the four attested options.
  TagCode('cravings', TagCategory.cravings, 'Cravings (unspecified)'),
  TagCode('sweet', TagCategory.cravings, 'Sweet'),
  TagCode('salty', TagCategory.cravings, 'Salty'),
  TagCode('carbs', TagCategory.cravings, 'Carbs'),
  TagCode('chocolate', TagCategory.cravings, 'Chocolate'),
  // body — dizziness is the one pre-existing physical code Issue #249
  // does not re-parent; it keeps its category and code.
  TagCode('dizziness', TagCategory.body, 'Dizziness'),
  // mood — #251 (feelings/mind/lifestyle) owns any further growth here.
  TagCode('irritable', TagCategory.mood, 'Irritable'),
  TagCode('sad', TagCategory.mood, 'Sad'),
  TagCode('anxious', TagCategory.mood, 'Anxious'),
  TagCode('calm', TagCategory.mood, 'Calm'),
  TagCode('sensitive', TagCategory.mood, 'Sensitive'),
];

/// Issue #249 categories whose Clue option set is not publicly attested
/// (Clue Plus-only or undocumented; `hotFlashes`' category itself is
/// attested, its perimenopause option cluster is not). Each exists in the
/// enum so the schema and picker framework are real, but carries **no
/// codes** in [kTagTaxonomy] — the picker marks them
/// "unverified — pin before shipping" instead of inventing options, until
/// a real Clue export pins each set.
const List<TagCategory> kUnverifiedTagCategories = [
  TagCategory.sleepQuality,
  TagCategory.breastsChest,
  TagCategory.hotFlashes,
  TagCategory.urine,
  TagCategory.vulvaVagina,
];

/// The `pain_free` code (Issue #249): a positive per-category "none today"
/// assertion — an affirmative statement that the day had no pain, never a
/// symptom in its own right.
const String kPainFreeCode = 'pain_free';

/// Codes that are positive "none today" assertions rather than symptoms.
/// Counting or rendering any of these as a symptom (calendar symptom dot,
/// symptom-layer ranking, semantic labels) misstates the day; use
/// [hasSymptomTags] at every site that asks "does this entry carry
/// symptoms?".
const Set<String> kPositiveAssertionCodes = {kPainFreeCode};

/// Whether [tags] carries at least one actual symptom — i.e. any code that
/// is not one of [kPositiveAssertionCodes]' positive "none today"
/// assertions (Issue #249: `pain_free` is a positive statement, never
/// counted or rendered as a symptom).
bool hasSymptomTags(Iterable<String> tags) =>
    tags.any((code) => !kPositiveAssertionCodes.contains(code));

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
