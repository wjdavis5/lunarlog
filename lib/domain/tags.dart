/// Symptom tag taxonomy (KTD6): 86 codes in 28 categories, grown from the
/// original 17-code cycle/flow-only set by Issue #249 (the physical
/// categories of Clue's attested taxonomy — pain, energy, sleep, skin,
/// hair, digestion, stool, cravings, plus the option-set-unverified
/// categories), Issue #251 (the feelings/mind/lifestyle categories —
/// `feelings`, `mind`, `motivation`, `social_life`, `partying`, plus the
/// option-set-unverified `pms`, `meditation`, `leisure`), and Issue #252
/// (the events-and-care categories — `collection_method`, `exercise`,
/// `medication`, `ailments`, plus the option-set-unverified
/// `appointments` and `supplements`).
///
/// Codes are stable identifiers (stored on day entries); [TagCode.display]
/// is the default UI string. **The code-stability rule (Issues #249,
/// #251, and #252): an existing code is never renamed or recoded.**
/// Re-parenting changes only the code's [TagCode.category]; the code
/// string itself is untouched, so historical rows referencing it stay
/// valid without any data migration. The 11 pre-#249 physical codes
/// (`cramps`, `headache`, `back_pain`, `breast_tenderness`, `bloating`,
/// `nausea`, `acne`, `energetic`, `fatigue`, `cravings`, `sleep_trouble`)
/// and the 5 pre-#251 mood codes (`irritable`, `sad`, `anxious`, `calm`,
/// `sensitive`) all keep their exact strings.
///
/// Category-scoped option strings that would collide across categories in
/// this flat, day-entry-tag namespace are qualified with a suffix —
/// following the export-string shape Clue itself uses for skin
/// (`good_skin`/`oily_skin`/`dry_skin`) — rather than renamed away from
/// their attested option: `good_hair`/`bad_hair`/`oily_hair`/`dry_hair`,
/// `great_digestion`, `great_stool`, and — Issue #252 — `cold/flu`, which
/// is an attested option of BOTH `medication` and `ailments`, so each
/// instance is category-qualified (`cold_flu_medication`/
/// `cold_flu_ailments`). Everything else keeps the raw Clue option
/// string, which is also what the Clue importer's pass-through
/// (`clue_option_map.dart`) writes into `observations.code`, so the two
/// vocabularies line up option-for-option. A display string is likewise
/// qualified only where the bare option would collide with another
/// display or a category heading ("Pain (medication)", the
/// "Cravings (unspecified)" precedent).
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
  feelings,
  mind,
  motivation,
  socialLife,
  leisure,
  meditation,
  pms,
  partying,
  // Issue #252's events-and-care categories, appended after #251's
  // lifestyle cluster (enum order = default surfacing order).
  collectionMethod,
  exercise,
  appointments,
  medication,
  ailments,
  supplements,
}

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
  // feelings — Issue #251 rebuilds the old `mood` grouping as `feelings`:
  // irritable/sad/anxious/sensitive re-parent in place (same codes, new
  // category); irritable stays as the lunarlog-specific extra (no Clue
  // equivalent, never dropped); happy/angry/indifferent are the attested
  // export set, mood_swings the medium-confidence addition, and
  // excited/insecure/grateful the redesign additions.
  TagCode('irritable', TagCategory.feelings, 'Irritable'),
  TagCode('happy', TagCategory.feelings, 'Happy'),
  TagCode('sad', TagCategory.feelings, 'Sad'),
  TagCode('angry', TagCategory.feelings, 'Angry'),
  TagCode('anxious', TagCategory.feelings, 'Anxious'),
  TagCode('indifferent', TagCategory.feelings, 'Indifferent'),
  TagCode('sensitive', TagCategory.feelings, 'Sensitive'),
  TagCode('mood_swings', TagCategory.feelings, 'Mood swings'),
  TagCode('excited', TagCategory.feelings, 'Excited'),
  TagCode('insecure', TagCategory.feelings, 'Insecure'),
  TagCode('grateful', TagCategory.feelings, 'Grateful'),
  // mind — calm re-parented from mood (same code); distracted/focused/
  // stressed are the attested Mind set.
  TagCode('calm', TagCategory.mind, 'Calm'),
  TagCode('distracted', TagCategory.mind, 'Distracted'),
  TagCode('focused', TagCategory.mind, 'Focused'),
  TagCode('stressed', TagCategory.mind, 'Stressed'),
  // motivation — legacy Clue category (A1-8), likely folded into Mind in
  // the current app; the option set is attested, so the picker carries it
  // without claiming current-app parity (issue #251's motivation row).
  TagCode('motivated', TagCategory.motivation, 'Motivated'),
  TagCode('unmotivated', TagCategory.motivation, 'Unmotivated'),
  TagCode('productive', TagCategory.motivation, 'Productive'),
  TagCode('unproductive', TagCategory.motivation, 'Unproductive'),
  // social_life
  TagCode('sociable', TagCategory.socialLife, 'Sociable'),
  TagCode('withdrawn', TagCategory.socialLife, 'Withdrawn'),
  TagCode('supportive', TagCategory.socialLife, 'Supportive'),
  TagCode('conflict', TagCategory.socialLife, 'Conflict'),
  // partying — substance-use data on a shared family record: the category
  // exists in the taxonomy and import path for every profile (lossless
  // import); its UI visibility on minor profiles is #259's per-profile
  // tracking-preference mechanism (default hidden, guardian-revealed).
  // `big_night` is Clue's attested "big night" option snake_cased for this
  // flat namespace — the importer's option map renames the raw string.
  TagCode('drinks', TagCategory.partying, 'Drinks'),
  TagCode('cigarettes', TagCategory.partying, 'Cigarettes'),
  TagCode('big_night', TagCategory.partying, 'Big night'),
  TagCode('hangover', TagCategory.partying, 'Hangover'),
  // collection_method — Issue #252: the four documented options (the
  // arXiv corpus's collection-method row, menstrual cup added later per
  // Clue's own announcement). Period underwear is "widely reported but
  // unverified", so it ships no code — and needs no schema change when it
  // ever does: `observations.code` is free text (unknown-never-drop) and
  // this list is data, so adding `period_underwear` is a one-line data
  // addition, exactly the extensible-registry shape issue #252 asks for.
  TagCode('pad', TagCategory.collectionMethod, 'Pad'),
  TagCode('tampon', TagCategory.collectionMethod, 'Tampon'),
  TagCode('panty_liner', TagCategory.collectionMethod, 'Panty liner'),
  TagCode('menstrual_cup', TagCategory.collectionMethod, 'Menstrual cup'),
  // exercise — Issue #252: running/yoga/biking/swimming are the legacy
  // attested set; walking/pilates/rest_day were added in Clue's 2023
  // redesign. All seven pass through the importer verbatim.
  TagCode('running', TagCategory.exercise, 'Running'),
  TagCode('yoga', TagCategory.exercise, 'Yoga'),
  TagCode('biking', TagCategory.exercise, 'Biking'),
  TagCode('swimming', TagCategory.exercise, 'Swimming'),
  TagCode('walking', TagCategory.exercise, 'Walking'),
  TagCode('pilates', TagCategory.exercise, 'Pilates'),
  TagCode('rest_day', TagCategory.exercise, 'Rest day'),
  // medication — Issue #252: the legacy table's four options. `cold/flu`
  // is attested under BOTH medication and ailments, so each instance is
  // category-qualified (the great_digestion/great_stool pattern — see the
  // library doc comment); the importer's option map renames both
  // documented spellings (`cold/flu`, `cold_flu`) onto the qualified
  // codes. `pain` keeps the attested option string as its code; the
  // display is qualified to stay unambiguous next to the Pain category
  // heading ("Cravings (unspecified)" precedent).
  TagCode('pain', TagCategory.medication, 'Pain (medication)'),
  TagCode(
    'cold_flu_medication',
    TagCategory.medication,
    'Cold/flu (medication)',
  ),
  TagCode('antihistamine', TagCategory.medication, 'Antihistamine'),
  TagCode('antibiotic', TagCategory.medication, 'Antibiotic'),
  // ailments — Issue #252: the legacy table's four options; `cold_flu_ailments`
  // is the category-qualified half of the medication/ailments `cold/flu`
  // collision above.
  TagCode('cold_flu_ailments', TagCategory.ailments, 'Cold/flu (ailments)'),
  TagCode('allergy', TagCategory.ailments, 'Allergy'),
  TagCode('injury', TagCategory.ailments, 'Injury'),
  TagCode('fever', TagCategory.ailments, 'Fever'),
];

/// Issue #249/#251/#252 categories whose Clue option set is not publicly
/// attested (Clue Plus-only, undocumented, or — for #251's `pms` —
/// presence-based with the option set not publicly enumerated; for #252's
/// `appointments` the category is confirmed single-event data but its
/// exact option strings are not publicly enumerated, and `supplements`
/// is Clue Plus-only with nothing enumerated). Each exists in the enum so
/// the schema and picker framework are real, but carries **no codes** in
/// [kTagTaxonomy] — the picker marks them "unverified — pin before
/// shipping" instead of inventing options, until a real Clue export pins
/// each set. `pms` the *presence* marker is deliberately separate: it
/// rides `day_entries.pms` (issue #220) outside this taxonomy, exactly as
/// Clue separates the PMS phase from the PMS option set.
const List<TagCategory> kUnverifiedTagCategories = [
  TagCategory.sleepQuality,
  TagCategory.breastsChest,
  TagCategory.hotFlashes,
  TagCategory.urine,
  TagCategory.vulvaVagina,
  TagCategory.pms,
  TagCategory.meditation,
  TagCategory.leisure,
  // Issue #252's two.
  TagCategory.appointments,
  TagCategory.supplements,
];

/// Issue #252's "single-event" categories — Clue's own treatment of
/// appointments, medications, and ailments as meaningfully tied to their
/// exact date rather than as cycle-pattern symptoms (birth control, the
/// issue's fourth single-event example, is absent because issue #260
/// ships it as its own model outside this taxonomy). These are the
/// categories a consumer may attach an exact `observations.observed_at`
/// to (#240's nullable column) and may exclude from cycle-trend/insights
/// aggregation — the seam issue #252's AC names for the Predictions &
/// Insights epic, which owns the actual consuming code; nothing here
/// aggregates or excludes anything by itself.
const Set<TagCategory> kSingleEventTagCategories = {
  TagCategory.appointments,
  TagCategory.medication,
  TagCategory.ailments,
};

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
