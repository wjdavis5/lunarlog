/// Curated, verified clinical terminology mapping (Issue #152; epic
/// clinical-export). This is the verification pass A3-44/A3-45 asked for,
/// captured as a small explicitly-sourced code table rather than literals
/// scattered through a future FHIR Bundle builder (#157).
///
/// **The rule this whole file exists to enforce (binding, from #152): no
/// guessed codes.** Every [ClinicalCode] below either cites the external
/// authority it was verified against in [ClinicalCode.provenanceUrl], or
/// uses [kSystemLunarlogLocal] with a documented reason in
/// `docs/clinical/terminology.md`. Nothing in this file is a plausible
/// guess - each row was checked against an authoritative terminology
/// server before being added (see that doc's provenance column for the
/// exact query used per code).
///
/// Three code systems appear here, using the canonical FHIR system URIs
/// (verified against the FHIR R4 spec - these are what
/// `Observation.code.coding.system` and `Observation.valueCodeableConcept
/// .coding.system` expect):
/// - [kSystemLoinc] - `http://loinc.org` - codes the *question* (what was
///   measured/asked).
/// - [kSystemSnomed] - `http://snomed.info/sct` - codes the *finding*
///   (the symptom/observation itself).
/// - [kSystemLunarlogLocal] -
///   `https://lunarlog.app/fhir/CodeSystem/tag` -
///   lunarlog's own code system for concepts with no verified external
///   mapping. This is an `http(s)://` URL under a domain lunarlog
///   controls, not an unregistered `urn:` scheme: FHIR only requires
///   `Coding.system` to be a URI that uniquely identifies the coding
///   scheme (R4), but RFC 8141 requires `urn:` namespace identifiers to be
///   formally registered - which this constant's value before 2026-09-09,
///   `urn:lunarlog:code`, never was - and FHIR's own guidance for a
///   locally-defined system is an `http(s)://` URL under a domain the
///   publisher controls, even before any document is actually published at
///   that address. #961 moved the base here from
///   `https://github.com/wjdavis5/lunarlog/fhir/...`, before the first
///   store build shipped an export. **The `lunarlog.app` URI is frozen
///   from the first shipped build and must never change**, because a
///   Bundle already handed to a clinician cannot be recalled (see
///   `docs/clinical/terminology.md` for the local-code policy this
///   backs).
///
/// This module is pure Dart (KTD6): no Flutter, no `dart:io`, nothing that
/// reaches into `lib/data/`. It only describes codes; #157 is what will
/// spend them building an actual FHIR Bundle.
///
/// ## Reserved shapes (A3-46/A3-47/A3-48) — decided now, emitted later
///
/// Three concept groups carry mapping decisions recorded here ahead of
/// the FHIR builder (`lib/domain/export/fhir_bundle.dart`, #157) learning
/// to emit them, per #152's instruction to reserve the shape now so the
/// export design accounts for it. The underlying tracking features have
/// all landed since #152 was written — BBT observation logging
/// (`observations` rows with `category: 'bbt'`, consumed by
/// `lib/domain/insights/bbt_chart.dart`), #188's pregnancy lifecycle
/// mode, and #260's birth-control model — but the builder does not yet
/// emit any of these shapes; those rows ride its generic local-coding
/// fallback today, which is valid FHIR and carries no guessed code. No
/// premature guessed code ships ahead of the builder work:
/// - **Basal body temperature (A3-46):** [kBodyTemperatureLoinc] —
///   LOINC `8310-5` "Body temperature" (the code US Core / IPS
///   vital-signs profiles expect), emitted with a basal qualifier
///   (`bodySite`/method, or an additional local coding marking the
///   reading basal). Never an invented BBT-specific LOINC.
/// - **Pregnancy + estimated due date (A3-47):** pregnancy status is
///   conventionally a `Condition` (or an `Observation` of pregnancy
///   status); the estimated delivery date is an `Observation` coded with
///   the already-verified `11778-8` "Delivery date Estimated"
///   ([estimatedDeliveryDateCode]; USCDI:
///   https://www.healthit.gov/isa/uscdi-data/estimated-date-delivery).
///   No pregnancy-status/due-date data model exists yet — only the mode
///   — so this is shape reservation, not an implemented mapping.
/// - **Birth control (A3-48, #260):** [kBirthControlResourceShapes] —
///   `MedicationStatement` / `Device` + `DeviceUseStatement` /
///   `Procedure` by method shape. Never modeled as an `Observation`;
///   doing so would make the export look machine-generated rather than
///   clinically credible. No medication/device codes are reserved — none
///   has been verified against an external system.
library;

import '../tags.dart' as tags show TagCode, kTagTaxonomy, isValidTagCode;

/// `http://loinc.org` - LOINC codes the *question*.
const String kSystemLoinc = 'http://loinc.org';

/// `http://snomed.info/sct` - SNOMED CT codes the *finding*.
const String kSystemSnomed = 'http://snomed.info/sct';

/// The permanent URI base for lunarlog's own FHIR code systems -
/// `https://lunarlog.app/fhir/CodeSystem`. Every lunarlog-local
/// `Coding.system` this export emits is this one base plus a short path
/// segment (`/tag` for the tag taxonomy, `/flow` for flow levels,
/// `/export-version` for the Bundle's version tag). #961 collapsed the
/// three previously-repeated full-literal bases onto this single constant
/// and moved them here from `https://github.com/wjdavis5/lunarlog/fhir/...`,
/// before the first store build shipped an export. **Frozen from the first
/// shipped build and never to change**: a Bundle already handed to a
/// clinician cannot be recalled, so this value is an identity, not a link.
/// Nothing needs to resolve at it for FHIR validity.
const String kFhirCodeSystemBase = 'https://lunarlog.app/fhir/CodeSystem';

/// `https://lunarlog.app/fhir/CodeSystem/tag` -
/// lunarlog's own local code system, used whenever no external code has
/// been verified for a concept. See the file doc comment above and
/// `docs/clinical/terminology.md` for the policy. **Permanent once #157
/// emits FHIR Bundles** - do not change this value casually.
const String kSystemLunarlogLocal = '$kFhirCodeSystemBase/tag';

/// Where the local-code policy and every row's provenance is written up
/// in full. [ClinicalCode.provenanceUrl] points here (as a repo-relative
/// path, since it is not an externally hosted document) for every row
/// coded on [kSystemLunarlogLocal].
const String kLocalCodeDocPath = 'docs/clinical/terminology.md';

/// One coding: a `(system, code, display, provenanceUrl)` tuple matching
/// FHIR's `Coding` shape closely enough that building `Observation.code`
/// from it is a direct field copy. Immutable and value-comparable.
class ClinicalCode {
  const ClinicalCode({
    required this.system,
    required this.code,
    required this.display,
    required this.provenanceUrl,
  });

  /// The code system URI - one of [kSystemLoinc], [kSystemSnomed], or
  /// [kSystemLunarlogLocal].
  final String system;

  /// The code within [system] (e.g. `'8665-2'`, `'25064002'`,
  /// `'cramps'`).
  final String code;

  /// Human-readable display string for this coding.
  final String display;

  /// Where this mapping was verified: an `https://` URL to the
  /// authoritative source for [kSystemLoinc]/[kSystemSnomed] rows, or a
  /// repo-relative path (see [kLocalCodeDocPath]) recording the
  /// local-coding decision for [kSystemLunarlogLocal] rows.
  final String provenanceUrl;

  @override
  bool operator ==(Object other) =>
      other is ClinicalCode &&
      other.system == system &&
      other.code == code &&
      other.display == display &&
      other.provenanceUrl == provenanceUrl;

  @override
  int get hashCode => Object.hash(system, code, display, provenanceUrl);

  @override
  String toString() => '$system|$code ($display)';
}

/// The seven verified menstrual-health LOINC codes from #152's A3-44
/// pass, each sourced to its `loinc.org` page. This list is exhaustive -
/// a test asserts it contains exactly these seven and no others.
const List<ClinicalCode> kLoincCodes = [
  ClinicalCode(
    system: kSystemLoinc,
    code: '8665-2',
    display: 'Last menstrual period start date',
    provenanceUrl: 'https://loinc.org/8665-2',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '8678-5',
    display: 'Menstrual status - Reported',
    provenanceUrl: 'https://loinc.org/8678-5',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '3146-8',
    display: 'Menstrual status',
    provenanceUrl: 'https://loinc.org/3146-8',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '92656-8',
    display: 'Number of menstrual periods per year',
    provenanceUrl: 'https://loinc.org/92656-8',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '63888-2',
    display: 'Age at first menstrual period',
    provenanceUrl: 'https://loinc.org/63888-2',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '64700-8',
    display: 'Menstrual cycle typical days PhenX',
    provenanceUrl: 'https://loinc.org/64700-8',
  ),
  ClinicalCode(
    system: kSystemLoinc,
    code: '11778-8',
    display: 'Delivery date Estimated',
    provenanceUrl: 'https://loinc.org/11778-8',
  ),
];

/// LOINC codes that were checked during the A3-44 pass and found to
/// **not** mean what they are commonly cited as meaning. `3141-9` is
/// "Body weight Measured" - not a menstrual concept at all. Referenced by
/// code (not full [ClinicalCode] rows, since these must never be built
/// into an actual coding) purely so the never-referenced test has
/// something to check against.
const List<String> kRefutedLoincCodes = ['3141-9'];

/// LOINC codes that came up during the A3-44 pass but were **not**
/// resolved to a verified menstrual concept in that pass. Do not use
/// without independent verification - see #152.
const List<String> kUnverifiedLoincCodes = [
  '49033-4',
  '63871-7',
  '21840-4',
  '8708-3',
  '3151-8',
];

/// LOINC `8310-5` "Body temperature" — **reserved for basal body
/// temperature** (A3-46), not part of [kLoincCodes]: that table is
/// exactly the A3-44 verified *menstrual-health question* set, and a
/// vital-sign code is not one of those seven (a test pins both facts).
///
/// `8310-5` is the standard body-temperature code US Core / IPS
/// vital-signs profiles expect, but on its own it understates BBT as a
/// distinct clinical concept (resting, first-waking). When the FHIR
/// builder (#157) starts emitting BBT `Observation`s for
/// `observations.category = 'bbt'` rows, it must emit this code **with a
/// basal qualifier** — a `bodySite`/method qualifier, or an additional
/// lunarlog-local coding marking the reading basal — rather than
/// inventing a BBT-specific LOINC code. Revisit once a BBT-specific
/// LOINC is confirmed. Until then, BBT rows ride the builder's generic
/// local-coding fallback, which is valid FHIR and guesses nothing.
const ClinicalCode kBodyTemperatureLoinc = ClinicalCode(
  system: kSystemLoinc,
  code: '8310-5',
  display: 'Body temperature',
  provenanceUrl: 'https://loinc.org/8310-5',
);

/// The clinical coding for every code in [tags.kTagTaxonomy] (all 113 —
/// #152's A3-45 pass over the original 17, plus issue #249's 28, issue
/// #251's 22, issue #252's 19, issue #253's 22, and issue #456's 5 new
/// codes as explicit local decisions; see docs/clinical/terminology.md).
///
/// Rows are one of two kinds:
/// - A verified SNOMED CT finding ([kSystemSnomed]): the concept id and
///   preferred term were confirmed active against the HL7 FHIR
///   terminology server (`https://tx.fhir.org`, an authoritative
///   SNOMED CT terminology service) at the query URL in
///   [ClinicalCode.provenanceUrl] - not guessed from memory.
/// - An explicit local decision ([kSystemLunarlogLocal]): either no
///   SNOMED concept matches without overreaching (see
///   `docs/clinical/terminology.md` for the per-tag reasoning), or the
///   tag is one of the four mood tags (`irritable`, `sensitive`, `calm`,
///   `energetic`) #152 itself expects to stay local rather than force a
///   match.
///
/// Every entry here uses the tag's own [tags.TagCode.code] as the
/// [ClinicalCode.code] when local-coded, and the tag's
/// [tags.TagCode.display] as [ClinicalCode.display] when local-coded, so
/// a local row is byte-identical to what [dualCodingFor] would build
/// anyway (see its doc comment).
const Map<String, ClinicalCode> kTagClinicalCodes = {
  // pain
  'cramps': ClinicalCode(
    system: kSystemSnomed,
    code: '266599000',
    display: 'Dysmenorrhea',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=266599000',
  ),
  'headache': ClinicalCode(
    system: kSystemSnomed,
    code: '25064002',
    display: 'Headache',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=25064002',
  ),
  'back_pain': ClinicalCode(
    system: kSystemSnomed,
    code: '161891005',
    display: 'Backache',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=161891005',
  ),
  'breast_tenderness': ClinicalCode(
    system: kSystemSnomed,
    code: '55222007',
    display: 'Tenderness of breast',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=55222007',
  ),
  // body
  'bloating': ClinicalCode(
    system: kSystemSnomed,
    code: '116289008',
    display: 'Abdominal bloating',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=116289008',
  ),
  'acne': ClinicalCode(
    system: kSystemSnomed,
    code: '11381005',
    display: 'Acne',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=11381005',
  ),
  'nausea': ClinicalCode(
    system: kSystemSnomed,
    code: '422587007',
    display: 'Nausea',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=422587007',
  ),
  'fatigue': ClinicalCode(
    system: kSystemSnomed,
    code: '84229001',
    display: 'Fatigue',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=84229001',
  ),
  'dizziness': ClinicalCode(
    system: kSystemSnomed,
    code: '404640003',
    display: 'Dizziness',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=404640003',
  ),
  // mood - irritable/calm/energetic/sensitive stay local per #152's own
  // assumption (mood tags should not be forced into a match); sad stays
  // local because the closest verified concept (SNOMED 366979004
  // "Depressed mood") overstates a self-reported mood-log tag with a
  // clinical-disorder-adjacent term - see docs/clinical/terminology.md.
  'irritable': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'irritable',
    display: 'Irritable',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sad': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sad',
    display: 'Sad',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'anxious': ClinicalCode(
    system: kSystemSnomed,
    code: '48694002',
    display: 'Anxiety',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=48694002',
  ),
  'calm': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'calm',
    display: 'Calm',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'energetic': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'energetic',
    display: 'Energetic',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sensitive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sensitive',
    display: 'Sensitive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  // other
  'sleep_trouble': ClinicalCode(
    system: kSystemSnomed,
    code: '301345002',
    display: 'Difficulty sleeping',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=301345002',
  ),
  'cravings': ClinicalCode(
    system: kSystemSnomed,
    code: '248132003',
    display: 'Craving for food or drink',
    provenanceUrl: 'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=248132003',
  ),

  // Issue #249's expanded physical categories. Every new code is an
  // explicit local decision, per the no-guessed-codes rule: no SNOMED CT
  // concept has been fetch-verified for any of them in this pass, so each
  // carries the lunarlog local coding only (never a plausible-but-unchecked
  // external code). External verification for the ones with real clinical
  // concepts (e.g. migraine) is deferred follow-up work, tracked on
  // docs/clinical/terminology.md; until then `dualCodingFor` degrades each
  // to its single local coding exactly as designed.
  'ovulation': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'ovulation',
    display: 'Ovulation pain',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'migraine': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'migraine',
    display: 'Migraine',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'migraine_with_aura': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'migraine_with_aura',
    display: 'Migraine with aura',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'pain_free': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pain_free',
    display: 'Pain free',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'fully_energized': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'fully_energized',
    display: 'Fully energized',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'tired': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'tired',
    display: 'Tired',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'exhausted': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'exhausted',
    display: 'Exhausted',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  '0_to_3_hours': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: '0_to_3_hours',
    display: '0-3 hours',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  '3_to_6_hours': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: '3_to_6_hours',
    display: '3-6 hours',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  '6_to_9_hours': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: '6_to_9_hours',
    display: '6-9 hours',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  '9_or_more_hours': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: '9_or_more_hours',
    display: '9+ hours',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'good_skin': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'good_skin',
    display: 'Good skin',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'oily_skin': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'oily_skin',
    display: 'Oily skin',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'dry_skin': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'dry_skin',
    display: 'Dry skin',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'good_hair': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'good_hair',
    display: 'Good hair',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'bad_hair': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'bad_hair',
    display: 'Bad hair',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'oily_hair': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'oily_hair',
    display: 'Oily hair',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'dry_hair': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'dry_hair',
    display: 'Dry hair',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'gassy': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'gassy',
    display: 'Gassy',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'great_digestion': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'great_digestion',
    display: 'Great',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'normal': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'normal',
    display: 'Normal',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'constipated': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'constipated',
    display: 'Constipated',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'great_stool': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'great_stool',
    display: 'Great',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'diarrhea': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'diarrhea',
    display: 'Diarrhea',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sweet': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sweet',
    display: 'Sweet',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'salty': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'salty',
    display: 'Salty',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'carbs': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'carbs',
    display: 'Carbs',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'chocolate': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'chocolate',
    display: 'Chocolate',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),

  // Issue #251's feelings/mind/lifestyle categories. Same rule as #249's
  // block above: every new code is an explicit local decision, no SNOMED
  // CT concept fetch-verified in this pass, so each carries the lunarlog
  // local coding only — `dualCodingFor` degrades each to it exactly as
  // designed. The five re-parented mood codes (irritable/sad/anxious/
  // calm/sensitive) keep their existing rows above untouched —
  // re-parenting changes a code's category, never its coding.
  'happy': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'happy',
    display: 'Happy',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'angry': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'angry',
    display: 'Angry',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'indifferent': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'indifferent',
    display: 'Indifferent',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'mood_swings': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'mood_swings',
    display: 'Mood swings',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'excited': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'excited',
    display: 'Excited',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'insecure': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'insecure',
    display: 'Insecure',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'grateful': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'grateful',
    display: 'Grateful',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'distracted': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'distracted',
    display: 'Distracted',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'focused': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'focused',
    display: 'Focused',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'stressed': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'stressed',
    display: 'Stressed',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'motivated': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'motivated',
    display: 'Motivated',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'unmotivated': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'unmotivated',
    display: 'Unmotivated',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'productive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'productive',
    display: 'Productive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'unproductive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'unproductive',
    display: 'Unproductive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sociable': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sociable',
    display: 'Sociable',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'withdrawn': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'withdrawn',
    display: 'Withdrawn',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'supportive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'supportive',
    display: 'Supportive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'conflict': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'conflict',
    display: 'Conflict',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'drinks': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'drinks',
    display: 'Drinks',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'cigarettes': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'cigarettes',
    display: 'Cigarettes',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'big_night': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'big_night',
    display: 'Big night',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'hangover': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'hangover',
    display: 'Hangover',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),

  // Issue #252's events-and-care categories. Same rule as #249's and
  // #251's blocks above: every new code is an explicit local decision, no
  // SNOMED CT concept fetch-verified in this pass, so each carries the
  // lunarlog local coding only — `dualCodingFor` degrades each to it
  // exactly as designed. (fever/allergy/injury are the likeliest
  // candidates for the follow-up tx.fhir.org verification pass.)
  'pad': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pad',
    display: 'Pad',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'tampon': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'tampon',
    display: 'Tampon',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'panty_liner': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'panty_liner',
    display: 'Panty liner',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'menstrual_cup': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'menstrual_cup',
    display: 'Menstrual cup',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'running': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'running',
    display: 'Running',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'yoga': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'yoga',
    display: 'Yoga',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'biking': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'biking',
    display: 'Biking',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'swimming': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'swimming',
    display: 'Swimming',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'walking': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'walking',
    display: 'Walking',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'pilates': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pilates',
    display: 'Pilates',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'rest_day': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'rest_day',
    display: 'Rest day',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'pain': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pain',
    display: 'Pain (medication)',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'cold_flu_medication': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'cold_flu_medication',
    display: 'Cold/flu (medication)',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'antihistamine': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'antihistamine',
    display: 'Antihistamine',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'antibiotic': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'antibiotic',
    display: 'Antibiotic',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'cold_flu_ailments': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'cold_flu_ailments',
    display: 'Cold/flu (ailments)',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'allergy': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'allergy',
    display: 'Allergy',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'injury': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'injury',
    display: 'Injury',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'fever': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'fever',
    display: 'Fever',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),

  // Issue #253's sensitive and fertility categories. Same rule as #249's,
  // #251's and #252's blocks above: every new code is an explicit local
  // decision, no SNOMED CT concept fetch-verified in this pass, so each
  // carries the lunarlog local coding only — `dualCodingFor` degrades each
  // to it exactly as designed.
  'no_sex_today': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'no_sex_today',
    display: 'No sex today',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'low_sex_drive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'low_sex_drive',
    display: 'Low sex drive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'high_sex_drive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'high_sex_drive',
    display: 'High sex drive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'masturbation': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'masturbation',
    display: 'Masturbation',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'withdrawal': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'withdrawal',
    display: 'Withdrawal',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'protected_sex': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'protected_sex',
    display: 'Protected sex',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'unprotected_sex': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'unprotected_sex',
    display: 'Unprotected sex',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sex_toys': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sex_toys',
    display: 'Sex toys',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'orgasm': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'orgasm',
    display: 'Orgasm',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'no_orgasm': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'no_orgasm',
    display: 'No orgasm',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'fantasies': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'fantasies',
    display: 'Fantasies',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'painful_intercourse': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'painful_intercourse',
    display: 'Painful intercourse',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'none': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'none',
    display: 'No discharge',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sticky': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sticky',
    display: 'Sticky',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'creamy': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'creamy',
    display: 'Creamy',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'egg_white': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'egg_white',
    display: 'Egg white',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'atypical': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'atypical',
    display: 'Atypical',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'ovulation_negative': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'ovulation_negative',
    display: 'Ovulation · negative',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'ovulation_positive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'ovulation_positive',
    display: 'Ovulation · positive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'ovulation_peak': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'ovulation_peak',
    display: 'Ovulation · peak',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'pregnancy_negative': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pregnancy_negative',
    display: 'Pregnancy · negative',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'pregnancy_positive': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'pregnancy_positive',
    display: 'Pregnancy · positive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),

  // Issue #456's five attested hot_flashes/Clue-Perimenopause codes. Same
  // rule as every block above: no SNOMED CT concept fetch-verified in
  // this pass, so each carries the lunarlog local coding only.
  'hot_flashes': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'hot_flashes',
    display: 'Hot flash',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'night_sweats': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'night_sweats',
    display: 'Night sweats',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'brain_fog': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'brain_fog',
    display: 'Brain fog',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'hrt': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'hrt',
    display: 'HRT',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'vaginal_dryness': ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'vaginal_dryness',
    display: 'Vaginal dryness',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
};

/// The lunarlog-local coding for [tagCode]: `system` [kSystemLunarlogLocal],
/// `code` [tagCode] itself, `display` the taxonomy's own
/// [tags.TagCode.display]. This is what round-trip fidelity means in
/// [dualCodingFor] - whatever else an `Observation.code` carries, this
/// coding is always present so an importer can recover the exact lunarlog
/// tag without reversing a clinical code.
///
/// Throws [ArgumentError] if [tagCode] is not in [tags.kTagTaxonomy].
ClinicalCode localTagCoding(String tagCode) {
  final tag = tags.kTagTaxonomy.firstWhere(
    (tags.TagCode t) => t.code == tagCode,
    orElse: () =>
        throw ArgumentError.value(tagCode, 'tagCode', 'not a known tag code'),
  );
  return ClinicalCode(
    system: kSystemLunarlogLocal,
    code: tag.code,
    display: tag.display,
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  );
}

/// The codings a FHIR `Observation.code` should carry for [tagCode]: the
/// verified clinical coding from [clinicalCodes] (defaults to
/// [kTagClinicalCodes]) when one exists, plus the lunarlog local coding
/// from [localTagCoding] always (dual coding, per #152's A3-45: "the
/// export emits `Observation.code` with a SNOMED coding plus the existing
/// lunarlog code as a second `coding` entry").
///
/// When [clinicalCodes] already resolved [tagCode] to a local decision,
/// that row *is* the local coding (same system/code/display), so this
/// returns a single-element list rather than a duplicate. When [tagCode]
/// is a real taxonomy tag that simply has no row in [clinicalCodes] yet
/// (a gap, not an unknown code), this **degrades** to the local coding
/// rather than throwing - a local-only coding is still valid FHIR and
/// carries no guessed clinical code, which is exactly the fallback #152's
/// "no guessed codes" rule asks for.
///
/// The optional [clinicalCodes] parameter exists for testability (it
/// defaults to the real [kTagClinicalCodes] table for every production
/// call site); callers should not normally pass it.
///
/// Throws [ArgumentError] only when [tagCode] is not in
/// [tags.kTagTaxonomy] at all.
List<ClinicalCode> dualCodingFor(
  String tagCode, {
  Map<String, ClinicalCode> clinicalCodes = kTagClinicalCodes,
}) {
  if (!tags.isValidTagCode(tagCode)) {
    throw ArgumentError.value(tagCode, 'tagCode', 'not a known tag code');
  }
  final local = localTagCoding(tagCode);
  final clinical = clinicalCodes[tagCode];
  if (clinical == null || clinical.system == kSystemLunarlogLocal) {
    return [local];
  }
  return [clinical, local];
}

/// Finds a verified LOINC row by its code, or `null` if [code] is not in
/// [kLoincCodes].
ClinicalCode? loincByCode(String code) {
  for (final row in kLoincCodes) {
    if (row.code == code) return row;
  }
  return null;
}

/// The LOINC rows #157's FHIR Bundle builder should use for menstrual
/// status observations: `8678-5` (patient-reported) and `3146-8` (the
/// general "Menstrual status" question).
List<ClinicalCode> get menstrualStatusCodes => [
  loincByCode('8678-5')!,
  loincByCode('3146-8')!,
];

/// The LOINC row #157's FHIR Bundle builder should use for typical cycle
/// length: `64700-8`.
List<ClinicalCode> get cycleLengthCodes => [loincByCode('64700-8')!];

/// The LOINC row reserved for the estimated delivery date `Observation`
/// of the pregnancy shape (A3-47): `11778-8` "Delivery date Estimated",
/// one of the A3-44 verified seven, included in USCDI
/// (https://www.healthit.gov/isa/uscdi-data/estimated-date-delivery).
///
/// **Shape reservation, not an implemented mapping.** Pregnancy status
/// is conventionally a `Condition` (or an `Observation` of pregnancy
/// status) — never an `Observation` with this code; the EDD specifically
/// is the `Observation`. #188's lifecycle modes carry a pregnancy *mode*
/// but no pregnancy-status or due-date data model exists yet, so nothing
/// consumes this getter; it exists so the export design already accounts
/// for the resource split the day that data lands (see the library doc's
/// "Reserved shapes" section).
ClinicalCode get estimatedDeliveryDateCode => loincByCode('11778-8')!;

/// The A3-48 birth-control resource-shape reservation: which FHIR
/// resource each method shape must be exported as, keyed by method
/// shape. `#260`'s birth-control model has landed
/// (`lib/domain/birth_control.dart`: profile-level method plus per-day
/// `birth_control_*` intake observation rows), but the FHIR builder does
/// not yet emit any of these shapes — its generic local-coding fallback
/// covers the intake rows meanwhile.
///
/// The binding rule (a test pins it): **no birth-control method shape is
/// ever modeled as an `Observation`** — exporting ongoing medication,
/// an in-situ device, or an insertion event as an "observation" is
/// exactly what makes an export look machine-generated rather than
/// clinically credible. No medication/device codes are reserved here;
/// none has been verified against an external system (the
/// no-guessed-codes rule).
const List<(String, String)> kBirthControlResourceShapes = [
  // (method shape, FHIR resource)
  ('oral_patch_ring_injection', 'MedicationStatement'),
  ('iud_implant', 'Device / DeviceUseStatement'),
  ('insertion_event', 'Procedure'),
];
