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
///   `https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag` -
///   lunarlog's own code system for concepts with no verified external
///   mapping. This is an `http(s)://` URL under a domain lunarlog
///   actually controls (the GitHub org that publishes this repo), not an
///   unregistered `urn:` scheme: FHIR only requires `Coding.system` to be
///   a URI that uniquely identifies the coding scheme (R4), but RFC 8141
///   requires `urn:` namespace identifiers to be formally registered -
///   which this constant's previous value, `urn:lunarlog:code`, never
///   was - and FHIR's own guidance for a locally-defined system is an
///   `http(s)://` URL under a domain the publisher controls, even before
///   any document is actually published at that address. **This string
///   is permanent once #157 starts emitting FHIR Bundles** - changing it
///   later would break every previously exported `Observation.code`, so
///   it is not to be revisited casually (see
///   `docs/clinical/terminology.md` for the local-code policy this
///   backs).
///
/// This module is pure Dart (KTD6): no Flutter, no `dart:io`, nothing that
/// reaches into `lib/data/`. It only describes codes; #157 is what will
/// spend them building an actual FHIR Bundle.
library;

import '../tags.dart' as tags show TagCode, kTagTaxonomy, isValidTagCode;

/// `http://loinc.org` - LOINC codes the *question*.
const String kSystemLoinc = 'http://loinc.org';

/// `http://snomed.info/sct` - SNOMED CT codes the *finding*.
const String kSystemSnomed = 'http://snomed.info/sct';

/// `https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag` -
/// lunarlog's own local code system, used whenever no external code has
/// been verified for a concept. See the file doc comment above and
/// `docs/clinical/terminology.md` for the policy. **Permanent once #157
/// emits FHIR Bundles** - do not change this value casually.
const String kSystemLunarlogLocal =
    'https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag';

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

/// The clinical coding for every code in [tags.kTagTaxonomy] (all 17,
/// #152's A3-45 pass over `lib/domain/tags.dart`).
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
  'cramps':  ClinicalCode(
    system: kSystemSnomed,
    code: '266599000',
    display: 'Dysmenorrhea',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=266599000',
  ),
  'headache':  ClinicalCode(
    system: kSystemSnomed,
    code: '25064002',
    display: 'Headache',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=25064002',
  ),
  'back_pain':  ClinicalCode(
    system: kSystemSnomed,
    code: '161891005',
    display: 'Backache',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=161891005',
  ),
  'breast_tenderness':  ClinicalCode(
    system: kSystemSnomed,
    code: '55222007',
    display: 'Tenderness of breast',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=55222007',
  ),
  // body
  'bloating':  ClinicalCode(
    system: kSystemSnomed,
    code: '116289008',
    display: 'Abdominal bloating',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=116289008',
  ),
  'acne':  ClinicalCode(
    system: kSystemSnomed,
    code: '11381005',
    display: 'Acne',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=11381005',
  ),
  'nausea':  ClinicalCode(
    system: kSystemSnomed,
    code: '422587007',
    display: 'Nausea',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=422587007',
  ),
  'fatigue':  ClinicalCode(
    system: kSystemSnomed,
    code: '84229001',
    display: 'Fatigue',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=84229001',
  ),
  'dizziness':  ClinicalCode(
    system: kSystemSnomed,
    code: '404640003',
    display: 'Dizziness',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=404640003',
  ),
  // mood - irritable/calm/energetic/sensitive stay local per #152's own
  // assumption (mood tags should not be forced into a match); sad stays
  // local because the closest verified concept (SNOMED 366979004
  // "Depressed mood") overstates a self-reported mood-log tag with a
  // clinical-disorder-adjacent term - see docs/clinical/terminology.md.
  'irritable':  ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'irritable',
    display: 'Irritable',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sad':  ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sad',
    display: 'Sad',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'anxious':  ClinicalCode(
    system: kSystemSnomed,
    code: '48694002',
    display: 'Anxiety',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=48694002',
  ),
  'calm':  ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'calm',
    display: 'Calm',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'energetic':  ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'energetic',
    display: 'Energetic',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  'sensitive':  ClinicalCode(
    system: kSystemLunarlogLocal,
    code: 'sensitive',
    display: 'Sensitive',
    provenanceUrl: '$kLocalCodeDocPath#local-code-policy',
  ),
  // other
  'sleep_trouble':  ClinicalCode(
    system: kSystemSnomed,
    code: '301345002',
    display: 'Difficulty sleeping',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=301345002',
  ),
  'cravings':  ClinicalCode(
    system: kSystemSnomed,
    code: '248132003',
    display: 'Craving for food or drink',
    provenanceUrl:
        'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://snomed.info/sct&code=248132003',
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
    orElse: () => throw ArgumentError.value(
        tagCode, 'tagCode', 'not a known tag code'),
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
List<ClinicalCode> get cycleLengthCodes => [
      loincByCode('64700-8')!,
    ];
