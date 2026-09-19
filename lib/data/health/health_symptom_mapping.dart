/// The pure lunarlog-tag → HealthKit symptom mapping (Issue #238): the
/// single, reviewable table that turns a day entry's taxonomy tag codes
/// ([DayEntry.tags], `lib/domain/tags.dart`) into
/// `HKCategoryTypeIdentifier` symptom strings plus a
/// [HealthSymptomSeverity]. Like `health_flow_mapping.dart`, everything
/// decision-shaped lives here in pure Dart (no platform, channel, or I/O
/// dependency) so it carries full `flutter test` coverage; the Swift half
/// only receives resolved identifiers and builds an `HKCategorySample`
/// (see `HealthSymptomSample` in `lib/domain/health/health_platform.dart`).
///
/// **The permanent platform asymmetry (never worked around):** HealthKit
/// has first-class symptom category types with severity; Health Connect
/// has **none**. That is why this mapping exists only on the iOS write
/// path — Android's adapter registers the absence explicitly and answers
/// `unavailable`, and the Settings health-sync copy states the limitation.
/// Symptoms are never smuggled into a Health Connect record's notes or
/// metadata: that would be unreadable to other apps and would misrepresent
/// the data.
///
/// ## The mapping table
///
/// Direct 1:1 mappings — each code confirmed live in `tags.dart`:
///
/// | lunarlog tag | HealthKit symptom type |
/// |---|---|
/// | `cramps` | `abdominalCramps` |
/// | `headache` | `headache` |
/// | `back_pain` | `lowerBackPain` |
/// | `breast_tenderness` | `breastPain` |
/// | `bloating` | `bloating` |
/// | `acne` | `acne` |
/// | `nausea` | `nausea` |
/// | `fatigue` | `fatigue` |
/// | `dizziness` | `dizziness` |
///
/// Lossy mappings, each carrying what is lost:
///
/// * **Every mood/feeling tag → `moodChanges`.** HealthKit's
///   `moodChanges` category has no valence or direction concept: a `happy`
///   day and a `sad` day map to the same sample, so the *sign* of the mood
///   is lost. `sad` is a distinct HealthKit type in its own right, but
///   mapping only that one code would invert the loss asymmetry (see the
///   table comment below).
/// * **`sleep_trouble` → `sleepChanges`.** The direction and cause of the
///   sleep change are lost; `sleepChanges` records only that sleep
///   changed.
/// * **`cravings` → `appetiteChanges`.** The specific craving (sweet,
///   salty, …) is lost; only "appetite changed" is recorded.
///
/// ## Deliberately unsupported (a decision, not a gap)
///
/// `calm` and `energetic` are *positive states*, not symptoms. Folding
/// them into `moodChanges` would misrepresent a calm or energetic day as a
/// mood disturbance, so they are explicitly unsupported. Apple's
/// `HKStateOfMind` (iOS 18+) is their future home; see
/// [kUnsupportedHealthKitSymptoms] for each reason.
///
/// ## Every live tag is classified explicitly
///
/// Any tag in `tags.dart` that is not in [kSymptomHealthKitTypeIdentifiers]
/// or [kUnsupportedHealthKitSymptoms] must appear in
/// [kNotExportedTagCodes] — never silently dropped.
/// `test/data/health/health_symptom_mapping_test.dart` asserts the three
/// sets partition the live taxonomy exactly, so a future tag addition fails
/// the suite rather than vanishing from the Health export without review.
library;

import 'package:lunarlog/domain/health/health_platform.dart';
import 'package:lunarlog/domain/tags.dart';

/// The named mapping table: lunarlog tag code → HealthKit
/// `HKCategoryTypeIdentifier` symptom raw-case name. The string values are
/// the exact Swift enum case names (`HKCategoryTypeIdentifier(rawValue:)`
/// in `AppDelegate.swift` resolves them with no tag knowledge of its own).
///
/// Mood codes are included here even though the mapping is lossy (all of
/// them collapse to `moodChanges`) — the loss is documented per group in
/// the library doc, and a lossy mapping is still a mapping. `calm` is
/// deliberately NOT here: it is unsupported (see the library doc).
const Map<String, String> kSymptomHealthKitTypeIdentifiers = {
  // Direct 1:1.
  'cramps': 'abdominalCramps',
  'headache': 'headache',
  'back_pain': 'lowerBackPain',
  'breast_tenderness': 'breastPain',
  'bloating': 'bloating',
  'acne': 'acne',
  'nausea': 'nausea',
  'fatigue': 'fatigue',
  'dizziness': 'dizziness',
  // Lossy: every feelings-category tag → moodChanges (no valence/direction
  // survives). Deliberately not routing `sad` to HealthKit's own distinct
  // `sad` type: doing so would make one mood tag lossless and the other ten
  // lossy, an inconsistent reading of the same day's mood set.
  'irritable': 'moodChanges',
  'happy': 'moodChanges',
  'sad': 'moodChanges',
  'angry': 'moodChanges',
  'anxious': 'moodChanges',
  'indifferent': 'moodChanges',
  'sensitive': 'moodChanges',
  'mood_swings': 'moodChanges',
  'excited': 'moodChanges',
  'insecure': 'moodChanges',
  'grateful': 'moodChanges',
  // Lossy: the direction/cause of the change is lost.
  'sleep_trouble': 'sleepChanges',
  'cravings': 'appetiteChanges',
};

/// Deliberately unsupported tag codes, each with the reason it is not
/// mapped. This is a documented product decision, not an unimplemented
/// gap: `calm` and `energetic` are positive states, and representing them
/// as symptoms would misstate the day. `HKStateOfMind` (iOS 18+) is the
/// future home once the app adopts it.
const Map<String, String> kUnsupportedHealthKitSymptoms = {
  'calm':
      'Positive state, not a symptom: forcing it into moodChanges would '
      'misrepresent a calm day as a mood disturbance. Future home: '
      'HKStateOfMind (iOS 18+).',
  'energetic':
      'Positive state, not a symptom: forcing it into a symptom category '
      'would misrepresent an energetic day as a complaint. Future home: '
      'HKStateOfMind (iOS 18+).',
};

/// Every remaining live taxonomy code — logged options that are real data
/// but have no HealthKit symptom category type, or no business being
/// exported as one (exercise, medication, collection method, discharge,
/// test results, duration buckets, positive "none today" assertions, …).
/// The completeness test requires this set to be explicit so an accidental
/// gap is impossible.
const Set<String> kNotExportedTagCodes = {
  // pain (already partly mapped): no HealthKit type for ovulation pain,
  // migraine, or the positive "pain free" assertion.
  'ovulation',
  'migraine',
  'migraine_with_aura',
  kPainFreeCode,
  // energy: only `fatigue` maps; the positive/quantitative states do not.
  'fully_energized',
  'tired',
  'exhausted',
  // sleep: duration buckets have no category type (`sleep_trouble` maps).
  '0_to_3_hours',
  '3_to_6_hours',
  '6_to_9_hours',
  '9_or_more_hours',
  // skin: only `acne` maps.
  'good_skin',
  'oily_skin',
  'dry_skin',
  // hair: no HealthKit category type at all.
  'good_hair',
  'bad_hair',
  'oily_hair',
  'dry_hair',
  // digestion: only `bloating`/`nausea` map.
  'gassy',
  'great_digestion',
  // stool: no HealthKit symptom category type.
  'normal',
  'constipated',
  'great_stool',
  'diarrhea',
  // cravings: only the legacy boolean `cravings` code maps.
  'sweet',
  'salty',
  'carbs',
  'chocolate',
  // hot_flashes: HealthKit has `hotFlashes`/`nightSweats`, but this PR's
  // mapping table is deliberately scoped to the issue's confirmed set; the
  // rest pass through unexported rather than being guessed.
  'hot_flashes',
  'night_sweats',
  'brain_fog',
  'hrt',
  'vaginal_dryness',
  // mind: `calm` is unsupported (positive state); the rest are no
  // HealthKit symptom type.
  'distracted',
  'focused',
  'stressed',
  // motivation: no HealthKit symptom category type.
  'motivated',
  'unmotivated',
  'productive',
  'unproductive',
  // social_life
  'sociable',
  'withdrawn',
  'supportive',
  'conflict',
  // partying
  'drinks',
  'cigarettes',
  'big_night',
  'hangover',
  // collection_method
  'pad',
  'tampon',
  'panty_liner',
  'menstrual_cup',
  // exercise
  'running',
  'yoga',
  'biking',
  'swimming',
  'walking',
  'pilates',
  'rest_day',
  // medication
  'pain',
  'cold_flu_medication',
  'antihistamine',
  'antibiotic',
  // ailments
  'cold_flu_ailments',
  'allergy',
  'injury',
  'fever',
  // sex_life
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
  // discharge
  'none',
  'sticky',
  'creamy',
  'egg_white',
  'atypical',
  // tests
  'ovulation_negative',
  'ovulation_positive',
  'ovulation_peak',
  'pregnancy_negative',
  'pregnancy_positive',
};

/// How one live tag code is handled by the HealthKit symptom export.
sealed class SymptomHealthKitExport {
  const SymptomHealthKitExport();
}

/// The tag maps to [typeIdentifier] (a HealthKit
/// `HKCategoryTypeIdentifier` raw-case name).
final class SymptomHealthKitMapped extends SymptomHealthKitExport {
  const SymptomHealthKitMapped(this.tagCode, this.typeIdentifier);

  final String tagCode;
  final String typeIdentifier;
}

/// The tag is deliberately not exported; [reason] says why.
final class SymptomHealthKitUnsupported extends SymptomHealthKitExport {
  const SymptomHealthKitUnsupported(this.tagCode, this.reason);

  final String tagCode;
  final String reason;
}

/// The tag is real data with no HealthKit symptom counterpart (or no
/// business being one), so it is not written to the health store.
final class SymptomHealthKitNotExported extends SymptomHealthKitExport {
  const SymptomHealthKitNotExported(this.tagCode);

  final String tagCode;
}

/// Classifies [code] (total: an unknown code — a custom registry tag, a
/// future peer's vocabulary — is [SymptomHealthKitNotExported], never an
/// error).
SymptomHealthKitExport classifySymptomHealthKitExport(String code) {
  final typeIdentifier = kSymptomHealthKitTypeIdentifiers[code];
  if (typeIdentifier != null) {
    return SymptomHealthKitMapped(code, typeIdentifier);
  }
  final reason = kUnsupportedHealthKitSymptoms[code];
  if (reason != null) {
    return SymptomHealthKitUnsupported(code, reason);
  }
  return SymptomHealthKitNotExported(code);
}

/// Maps a stored pain grade (1-5, `Observation.intensity`) onto a
/// [HealthSymptomSeverity].
///
/// **Fidelity is bounded by whether an intensity was recorded.** HealthKit
/// symptom samples *need* a severity value, but lunarlog only grades pain
/// (`category: 'pain'`); every other symptom is a boolean tag. So this
/// returns [HealthSymptomSeverity.unspecified] for a `null` grade — the
/// common case — by design, not as a bug. A graded 1 is `mild`; 2-3 is
/// `moderate`; 4-5 is `severe` (matching the caregiver alert's
/// `intensity >= 4` high-severity threshold).
HealthSymptomSeverity severityForPainIntensity(int? intensity) {
  if (intensity == null) return HealthSymptomSeverity.unspecified;
  if (intensity <= 1) return HealthSymptomSeverity.mild;
  if (intensity <= 3) return HealthSymptomSeverity.moderate;
  return HealthSymptomSeverity.severe;
}

/// One resolved symptom sample, before the write service attaches the
/// source record id/version and day envelope.
class ResolvedHealthKitSymptom {
  const ResolvedHealthKitSymptom({
    required this.tagCode,
    required this.typeIdentifier,
    required this.severity,
  });

  /// The lunarlog taxonomy code that produced this sample.
  final String tagCode;

  /// The HealthKit `HKCategoryTypeIdentifier` raw-case name.
  final String typeIdentifier;

  final HealthSymptomSeverity severity;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedHealthKitSymptom &&
          other.tagCode == tagCode &&
          other.typeIdentifier == typeIdentifier &&
          other.severity == severity;

  @override
  int get hashCode => Object.hash(tagCode, typeIdentifier, severity);
}

/// Resolves one day's [tags] into the set of HealthKit symptom samples to
/// write.
///
/// * A not-exported or unsupported tag contributes nothing (it is never a
///   silent bug — [classifySymptomHealthKitExport] and the completeness
///   test make the decision explicit).
/// * Samples are **deduplicated by [ResolvedHealthKitSymptom.typeIdentifier]**:
///   a day with `sad` and `anxious` writes one `moodChanges` sample (the
///   type has no valence to distinguish them), while `cramps` and
///   `headache` write one each. The surviving severity is the highest among
///   the merged tags.
/// * [gradedPainIntensities] is the output of
///   `gradedPainIntensitiesFrom` (`lib/domain/logging/day_sheet_reconciliation.dart`)
///   — keyed by taxonomy code. A tag with no grade gets
///   [HealthSymptomSeverity.unspecified].
List<ResolvedHealthKitSymptom> resolveHealthKitSymptoms({
  required Iterable<String> tags,
  required Map<String, int> gradedPainIntensities,
}) {
  final byType = <String, ResolvedHealthKitSymptom>{};
  for (final tag in tags) {
    final export = classifySymptomHealthKitExport(tag);
    if (export is! SymptomHealthKitMapped) continue;
    final severity = severityForPainIntensity(gradedPainIntensities[tag]);
    final existing = byType[export.typeIdentifier];
    if (existing == null || severity.index > existing.severity.index) {
      byType[export.typeIdentifier] = ResolvedHealthKitSymptom(
        tagCode: tag,
        typeIdentifier: export.typeIdentifier,
        severity: severity,
      );
    }
  }
  return byType.values.toList(growable: false);
}
