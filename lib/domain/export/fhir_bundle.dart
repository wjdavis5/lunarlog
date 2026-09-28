/// FHIR R4 clinical export Bundle builder (Issue #157, epic
/// clinical-export). Pure Dart (KTD6): no Flutter, no `dart:io` — the only
/// untestable part of this export is the temp-file + share-sheet hand-off
/// in `lib/data/export/fhir_bundle_writer.dart`, which wraps
/// [buildFhirDocumentBundle] the same way
/// `lib/data/export/account_export_writer.dart` wraps
/// `lib/domain/export/account_export.dart`.
///
/// **What this builds.** `Bundle.type = "document"`: entry 0 is a
/// `Composition` (`status: final`, `type` LOINC `60591-5` "Patient summary
/// Document" — verified against `tx.fhir.org`, see
/// [kCompositionTypePatientSummary]), followed by one `Patient`, the
/// `Observation`s for cycle/symptom/vital-sign data, and one `Provenance`.
/// This is **IPS-shaped, not IPS-conformant** (Issue #157 A3-49, modeled on
/// https://hl7.org/fhir/uv/ips/ IG v2.0.0): the section layout and resource
/// choices follow the International Patient Summary's shape (Results +
/// Vital signs + Problems sections, plus the title-only "Cycle
/// observations" section issue #1138 added for the self-reported
/// non-problem entries, over a self-authored Composition), but **no
/// `meta.profile` is ever asserted** — IPS has required sections
/// (allergies, medications, problems-as-Condition) this app cannot
/// populate yet, and claiming the profile while failing validation is
/// worse than not claiming it. Nothing in this file sets `meta.profile`;
/// that is a deliberate omission, not an oversight, and stays that way
/// until a validator run against a specific IPS version passes (see
/// `docs/clinical/fhir-export.md`).
///
/// **Exclusion policy (extends R9).**
/// `lib/domain/export/account_export.dart:12-16` documents R9: no sync
/// bookkeeping, no guardian attribution ids, nothing not already a plain
/// domain field. This builder extends the same discipline further than R9
/// requires, because a FHIR document can leave the device and reach a
/// clinician or portal:
/// - [Profile.id], [DayEntry.id], [Observation.id] and every other
///   storage-assigned ULID are **never written into the output** — not
///   even as a FHIR `identifier`. They are only ever fed into
///   [_uuidFor]'s one-way v5 hash to derive a `urn:uuid` cross-reference
///   *within this one Bundle*; the hash cannot be reversed to recover the
///   original id, and the same id always hashes to the same `urn:uuid` so
///   the Bundle stays internally consistent and deterministic.
/// - `Patient` carries **only** [Profile.displayName] — no identifier
///   block at all (not even a namespaced-internal one; decided against —
///   see the `Patient` section of `docs/clinical/fhir-export.md`), no
///   `birthDate` (even though [Profile.birthYear] exists), no email, no
///   Supabase user id, no guardian ids.
/// - `Observation.performer` and a `note` mark the raw logged facts as
///   self-reported (never a clinician observation) — see
///   [kSelfReportedNoteText] and [_buildProvenance]'s `activity` coding.
///   The one exception is the app-calculated cycle-length Observation,
///   which carries neither (issue #1115).
/// - [DayEntry.note] (free-text) is never read by this file at all — no
///   function here even accepts it as an argument, so there is no code
///   path that could leak it. `test/domain/export/fhir_bundle_test.dart`
///   pins this with a fixture entry carrying a distinctive note string,
///   asserted absent from the encoded output.
/// - [Observation.excluded] rows (the BBT per-point exclusion flag,
///   A1-44) are skipped entirely — never emitted, not even with a
///   different `status` — since an excluded row is the user saying "this
///   point should not count"; exporting it at all would contradict that.
///   [Observation.valueText] is never emitted either: it is a free-text
///   escape hatch (A1-45), the same category of risk as [DayEntry.note].
///
/// **Versioning.** [kFhirExportBundleVersion] is carried as `Bundle.meta
/// .tag` ([_versionTag]) so a future change to this mapping is
/// distinguishable from v1's output by any downstream consumer.
///
/// **Determinism (per-resource, not Bundle-wide — #157 review fix).** Every
/// `urn:uuid` is derived from a stable name via [_uuidFor] (UUID v5, RFC
/// 4122 §4.3 — deterministic given the same namespace + name), never
/// `Uuid.v4()`/`DateTime.now()` internally, but not every resource's *name*
/// is itself independent of [exportedAt]:
/// - `Patient`, the flow-day `Observation`s, and the tag-derived
///   `Observation`s are named from stable domain identity alone
///   ([Profile.id]; [DayEntry.id]; `(profile.id, date, tag)`) — two exports
///   of the same underlying data produce the *same* ids for these
///   resources, run after run. That is the intended behavior: a system
///   re-ingesting a second export should update these same resources
///   rather than create duplicates of them.
/// - `Bundle`, `Composition`, `Provenance`, and the cycle-statistic
///   `Observation`s (typical cycle length, last menstrual period) are named
///   from `idKey` (`'${profile.id}:$timestamp'`), which bakes in
///   [exportedAt] — these ids are **not** stable across two calls with a
///   different `exportedAt` (see `test/domain/export/fhir_bundle_test.dart`
///   "a different exportedAt changes the Composition/Provenance ids but not
///   the Patient id"), because each export run is its own document
///   assertion (a new `Composition`/`Provenance` recording *that this
///   export happened*), while the underlying `Observation`-per-day-entry
///   entities they reference are not new.
/// Two calls with the *same* `exportedAt` (and everything else the same)
/// still produce byte-identical `jsonEncode` output, since nothing else in
/// this builder reads wall-clock time or randomness.
///
/// **Coding discipline.** Every `Observation.code`/`valueCodeableConcept`
/// coding comes from `lib/domain/export/clinical_terminology.dart`'s
/// verified table (Issue #152) or an explicit [kSystemLunarlogLocal] local
/// coding with a documented reason — never a guessed code. This file adds
/// four more verified LOINC codes clinical_terminology.dart does not
/// carry ([kCompositionTypePatientSummary], [kSectionResults],
/// [kSectionProblems], [kSectionVitalSigns] — all Composition/section-level,
/// not `Observation.code`, so they do not belong in that file's
/// exhaustively-tested `kLoincCodes`), each verified the same way (see
/// each constant's `provenanceUrl`).
library;

import '../limits.dart' show kPainIntensityScaleText;
import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/observation.dart';
import '../models/observation_category.dart';
import '../models/profile.dart';
import '../prediction/prediction.dart'
    show ActivePrediction, kMaxCycleDays, kMinCycleDays, kRecencyWindowCycles;
import '../tags.dart' as tags
    show
        TagClinicalRole,
        categoryFromWireName,
        contextualDisplayForTag,
        isValidTagCode,
        tagByCode,
        tagClinicalRole,
        tagClinicalRoleForCategory,
        tagClinicalRoleForCode;
import 'account_export.dart' show kAccountExportAppName;
import 'clinical_terminology.dart';

import 'package:uuid/uuid.dart';

/// Bumped whenever this file's FHIR mapping changes in a way a downstream
/// consumer must know about (parallels
/// `account_export.dart`'s `kAccountExportSchemaVersion`). Carried as
/// `Bundle.meta.tag` via [_versionTag] — see this file's "Versioning" doc
/// note above.
///
/// `2` (issues #1114/#1115): intensity-bearing rows carry a 1-5 scale
/// `note` (never a `referenceRange`), flow uses SNOMED `364308001`, cycle
/// length uses SNOMED `161716008`, the tag `code.text`/local displays are
/// self-describing, and BBT/weight moved into a Vital Signs section
/// (birth-control intake rows are no longer emitted as Observations).
///
/// `3` (issue #1138): the self-reported tag/row Observations are routed by
/// `tags.tagClinicalRole` instead of all landing in Problems — Problems
/// (11450-4) carries only symptom findings, home pregnancy/LH test results
/// moved into Results (30954-2, keeping their "Home test" labels),
/// normal/positive states moved to a new title-only "Cycle observations"
/// section, and medication, sex-life and substance tags are no longer
/// exported at all.
const int kFhirExportBundleVersion = 3;

/// lunarlog's own code system for the version tag ([_versionTag]) — a
/// distinct URI from [kSystemLunarlogLocal] (clinical concepts) because a
/// version marker is not a clinical coding. (Not the Bundle's own
/// `identifier.system` — #157 review fix: that is `urn:ietf:rfc:3986`,
/// since `identifier.value` is itself a URI; see [buildFhirDocumentBundle].)
const String kFhirExportVersionSystem =
    '$kFhirCodeSystemBase/export-version';

/// lunarlog's own code system for flow-level codings (#157 review fix,
/// `docs/clinical/terminology.md`'s "`FlowLevel`" section) — a distinct
/// URI from [kSystemLunarlogLocal], which
/// `clinical_terminology.dart` documents as *the tag system*
/// (`.../CodeSystem/tag`). A flow level is not a tag: giving it its own
/// system keeps `kSystemLunarlogLocal`'s own meaning ("one of the 113
/// `lib/domain/tags.dart` codes") exact, rather than overloading it with
/// an unrelated flow-amount scale. **Permanent once emitted**, the same as
/// [kSystemLunarlogLocal] itself — do not change this value casually.
const String kSystemLunarlogLocalFlow = '$kFhirCodeSystemBase/flow';

/// Where the local codings this file (as opposed to
/// clinical_terminology.dart's tag codings) introduces are documented:
/// flow-level codings (on [kSystemLunarlogLocalFlow]), the generic
/// per-`Observation`-row fallback coding, the self-reported
/// `Provenance.activity` coding, and the `intensity` component coding
/// (Issue #612, LLA-088 — see [_intensityComponent]) — the latter three
/// still on [kSystemLunarlogLocal] (#157 review fix only split flow
/// levels out into their own system, since only flow levels are a
/// genuinely distinct concept space from tags; "self-reported" and
/// "intensity" are both markers, not competing taxonomies, and the
/// generic observation-row fallback already keys off `category:code`
/// rather than colliding with a real tag code).
const String kFhirExportLocalCodeDocPath =
    'docs/clinical/fhir-export.md#local-codes-introduced-by-this-export';

/// LOINC `60591-5` "Patient summary Document" — verified against
/// `tx.fhir.org`'s `$lookup` operation
/// (`https://tx.fhir.org/r4/CodeSystem/$lookup?system=http://loinc.org&code=60591-5`,
/// `display` copied verbatim from that response). Used for
/// `Composition.type`.
const ClinicalCode kCompositionTypePatientSummary = ClinicalCode(
  system: kSystemLoinc,
  code: '60591-5',
  display: 'Patient summary Document',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://loinc.org&code=60591-5',
);

/// LOINC `30954-2` — the IPS "Results Section" code, verified the same way
/// as [kCompositionTypePatientSummary]. Holds the flow and
/// cycle-statistic `Observation`s and — since issue #1138 — the home
/// pregnancy/LH test Observations (a test result is a result, wherever it
/// was logged).
const ClinicalCode kSectionResults = ClinicalCode(
  system: kSystemLoinc,
  code: '30954-2',
  display: 'Relevant diagnostic tests/laboratory data note',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://loinc.org&code=30954-2',
);

/// LOINC `11450-4` — the IPS "Problems Section" code, verified the same
/// way. Holds the self-reported symptom `Observation`s — only symptoms
/// since issue #1138's `TagClinicalRole` routing (wellness states,
/// discharge types, positive mood, and the like go to the "Cycle
/// observations" section; home test results to Results; medications,
/// sex-life and substance tags are not exported). (These are
/// `Observation` findings, not `Condition` diagnoses — IPS's Problems
/// section normally expects Conditions; this export deliberately keeps
/// self-reported symptom logs as Observations rather than asserting them
/// as diagnosed conditions. See `docs/clinical/fhir-export.md`.)
const ClinicalCode kSectionProblems = ClinicalCode(
  system: kSystemLoinc,
  code: '11450-4',
  display: 'Problem list - Reported',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://loinc.org&code=11450-4',
);

/// LOINC `8716-3` "Vital signs note" — the IPS "Vital Signs" section code
/// (issue #1115), verified against `tx.fhir.org` (LOINC 2.82, 2026-09-26)
/// with the display copied verbatim from that response. Holds the BBT and
/// weight measurement `Observation`s, which used to ride the Problems
/// section as generic symptom findings.
const ClinicalCode kSectionVitalSigns = ClinicalCode(
  system: kSystemLoinc,
  code: '8716-3',
  display: 'Vital signs note',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://loinc.org&code=8716-3',
);

/// `http://terminology.hl7.org/CodeSystem/list-empty-reason`, code
/// `unavailable` — a fixed FHIR R4 core CodeSystem (spec:
/// https://hl7.org/fhir/R4/valueset-list-empty-reason.html), not something
/// requiring a `tx.fhir.org` lookup the way a clinical SNOMED/LOINC coding
/// does. `Composition.section.emptyReason` (#157 review fix) when a
/// section has no `entry` — "the underlying data source has no [matching]
/// information available" is the closest of the six core reasons to "this
/// profile has no recorded cycle/symptom data yet," as opposed to
/// `notasked`/`withheld` (implies someone declined to answer) or `closed`
/// (implies a list that used to have entries and no longer does).
const ClinicalCode kSectionEmptyReasonUnavailable = ClinicalCode(
  system: 'http://terminology.hl7.org/CodeSystem/list-empty-reason',
  code: 'unavailable',
  display: 'Unavailable',
  provenanceUrl: 'https://hl7.org/fhir/R4/valueset-list-empty-reason.html',
);

/// `http://terminology.hl7.org/CodeSystem/provenance-participant-type`,
/// code `author` — verified against `tx.fhir.org`. `Provenance.agent.type`
/// for the self-reporting patient/guardian.
const ClinicalCode kProvenanceAgentTypeAuthor = ClinicalCode(
  system: 'http://terminology.hl7.org/CodeSystem/provenance-participant-type',
  code: 'author',
  display: 'Author',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://terminology.hl7.org/CodeSystem/provenance-participant-type&code=author',
);

/// No verified external code represents "patient self-report" as a
/// `Provenance.activity` in FHIR R4's core value sets — this is an
/// explicit local decision, not a guess (see
/// [kFhirExportLocalCodeDocPath]).
const ClinicalCode kSelfReportedActivity = ClinicalCode(
  system: kSystemLunarlogLocal,
  code: 'self-reported',
  display: 'Self-reported by patient or guardian',
  provenanceUrl: kFhirExportLocalCodeDocPath,
);

/// Text for every clinical `Observation.note` in this Bundle — the
/// "extension or note marking self-reported" Issue #157 asks for; this
/// file uses a note (paired with `performer` = Patient) rather than a
/// custom extension, since `Observation.note` is a core R4 element and
/// needs no new extension URI to define and maintain.
const String kSelfReportedNoteText =
    'Self-reported by the patient or guardian via lunarlog; not a '
    'clinician assessment.';

/// The note on the cycle-length `Observation` (issue #1115) — the value is
/// computed by the app from the profile's logged period starts, so it must
/// not be marked self-reported the way the raw symptom/flow rows are. The
/// window is built from the prediction engine's own constants
/// ([kMinCycleDays]..[kMaxCycleDays] within [kRecencyWindowCycles]) so
/// the wording cannot drift from what `ActivePrediction.meanCycleLengthDays`
/// actually averages.
const String kCalculatedCycleLengthNoteText =
    'Mean of the $kMinCycleDays-$kMaxCycleDays day cycles among the last '
    '$kRecencyWindowCycles completed cycles (cycles the patient or guardian '
    'excluded from averages are left out), calculated by lunarlog from '
    'period start dates logged by the patient or guardian; not measured '
    'or confirmed by a clinician.';

final Uuid _uuidGenerator = const Uuid();

/// A deterministic `urn:uuid` cross-reference id for [name] (UUID v5,
/// namespace [Namespace.url]) — the same [name] always yields the same
/// id, and [name] itself is never emitted into the output (see this
/// file's "Exclusion policy" doc note above).
String _uuidFor(String name) =>
    _uuidGenerator.v5(Namespace.url.value, 'lunarlog-fhir:$name');

/// `urn:uuid:<id>` for [name] — both a valid `Bundle.entry.fullUrl` and,
/// used identically elsewhere, a resolvable `reference` value.
String _fullUrl(String name) => 'urn:uuid:${_uuidFor(name)}';

/// One `(fullUrl, resource)` pair pending `{'fullUrl': ..., 'resource':
/// ...}` serialization as a `Bundle.entry`.
typedef _ResourceEntry = ({String fullUrl, Map<String, Object?> resource});

Map<String, Object?> _entryJson(_ResourceEntry entry) => {
      'fullUrl': entry.fullUrl,
      'resource': entry.resource,
    };

/// Builds the FHIR R4 document Bundle for one profile (see this file's
/// doc comment for the overall shape and its guarantees).
///
/// [dayEntries] and [observations] are expected pre-filtered to
/// [profile]'s own id and whatever date range the caller wants exported —
/// this function does not re-filter by profile or date itself. [prediction]
/// is optional: pass `null` when there is not enough cycle history yet
/// (`computePredictionFromEntries` returning `NotEnoughHistory`) — the
/// cycle-statistics `Observation`s are simply omitted, never fabricated.
Map<String, Object?> buildFhirDocumentBundle({
  required Profile profile,
  required List<DayEntry> dayEntries,
  List<Observation> observations = const [],
  ActivePrediction? prediction,
  required DateTime exportedAt,
  required String appVersion,
}) {
  final utcExportedAt = exportedAt.toUtc();
  final timestamp = utcExportedAt.toIso8601String();
  final idKey = '${profile.id}:$timestamp';

  final patientRef = _fullUrl('patient:${profile.id}');
  final compositionRef = _fullUrl('composition:$idKey');
  final provenanceRef = _fullUrl('provenance:$idKey');

  final flowEntries = _flowEntries(dayEntries, patientRef);
  final vitalSignEntries = _vitalSignEntries(observations, patientRef);
  final statEntries = _statEntries(prediction, idKey, patientRef);
  final selfReported = _partitionSelfReported(
    _routedSelfReportedEntries(profile, dayEntries, observations, patientRef),
  );

  final composition = _buildComposition(
    patientRef: patientRef,
    exportedAt: utcExportedAt,
    resultsRefs: [
      for (final entry in flowEntries) entry.fullUrl,
      for (final entry in statEntries) entry.fullUrl,
      // Home pregnancy/LH test results are results (#1138) — they share
      // this section with the flow and cycle-statistic Observations.
      for (final entry in selfReported.testResults) entry.fullUrl,
    ],
    vitalSignsRefs: [for (final entry in vitalSignEntries) entry.fullUrl],
    problemsRefs: [for (final entry in selfReported.problems) entry.fullUrl],
    cycleObservationsRefs: [
      for (final entry in selfReported.cycleObservations) entry.fullUrl,
    ],
  );
  final provenance = _buildProvenance(
    compositionRef: compositionRef,
    patientRef: patientRef,
    exportedAt: utcExportedAt,
    appVersion: appVersion,
  );

  final entries = <_ResourceEntry>[
    (fullUrl: compositionRef, resource: composition),
    (fullUrl: patientRef, resource: _buildPatient(profile)),
    for (final entry in flowEntries) entry,
    for (final entry in selfReported.problems) entry,
    for (final entry in selfReported.testResults) entry,
    for (final entry in selfReported.cycleObservations) entry,
    for (final entry in vitalSignEntries) entry,
    for (final entry in statEntries) entry,
    (fullUrl: provenanceRef, resource: provenance),
  ];

  return {
    'resourceType': 'Bundle',
    'id': _uuidFor('bundle:$idKey'),
    'type': 'document',
    // `identifier.system` is `urn:ietf:rfc:3986` (#157 review fix), not
    // [kFhirExportVersionSystem] — RFC 3986 is the correct `system` for a
    // FHIR identifier whose `value` is itself a URI (here, the Bundle's own
    // `urn:uuid:`), per the FHIR R4 spec's guidance for URI-valued
    // identifiers. The version-tag CodeSystem URI stays on `meta.tag`
    // ([_versionTag]) — a different concept (this mapping's version) from
    // what identifies this specific Bundle instance.
    'identifier': {
      'system': 'urn:ietf:rfc:3986',
      'value': _fullUrl('bundle:$idKey'),
    },
    'timestamp': timestamp,
    'meta': {
      'tag': [_versionTag()],
    },
    'entry': [for (final entry in entries) _entryJson(entry)],
  };
}

Map<String, Object?> _versionTag() => {
      'system': kFhirExportVersionSystem,
      'code': '$kFhirExportBundleVersion',
      'display': 'lunarlog-fhir-export-version',
    };

Map<String, Object?> _coding(ClinicalCode code) => {
      'system': code.system,
      'code': code.code,
      'display': code.display,
    };

/// `Patient` carries only [Profile.displayName] — no identifier, no
/// birthDate, no email, no internal id (see this file's "Exclusion
/// policy" doc note above; the decision to omit even a
/// namespaced-internal identifier is deliberate, not an oversight).
Map<String, Object?> _buildPatient(Profile profile) => {
      'resourceType': 'Patient',
      'name': [
        {'text': profile.displayName},
      ],
    };

List<_ResourceEntry> _flowEntries(
  List<DayEntry> dayEntries,
  String patientRef,
) =>
    [
      // `isBleed` (#157 review fix, #335 coupling) rather than the equality
      // check this replaced: a positive bleed allow-list, so an explicit
      // "not bleeding" day can never emit a flow Observation even as #335
      // adds flow levels beyond the current ones.
      for (final entry in dayEntries.where((e) => isBleed(e.flow)))
        (
          fullUrl: _fullUrl('observation:flow:${entry.id}'),
          resource: _flowObservation(entry, patientRef),
        ),
    ];

/// One `Observation` per bleed day (Issue #157: "one per day entry with
/// flow ≠ none"), coded with the single SNOMED `364308001` "Quantity of
/// menstrual blood loss" question code (issue #1115 — replacing the two
/// LOINC "Menstrual status" codings, which described the state of
/// menstruation rather than a day's amount) and a
/// [kSystemLunarlogLocalFlow] `valueCodeableConcept` naming the local flow
/// level.
Map<String, Object?> _flowObservation(DayEntry entry, String patientRef) => {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [_coding(kQuantityOfMenstrualBloodLossSnomed)],
        'text': kQuantityOfMenstrualBloodLossSnomed.display,
      },
      'subject': {'reference': patientRef},
      'effectiveDateTime': entry.localDate.iso,
      'valueCodeableConcept': {
        'coding': [_flowCoding(entry.flow)],
      },
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
      ],
    };

/// `system` is [kSystemLunarlogLocalFlow] (#157 review fix — its own
/// system, not [kSystemLunarlogLocal]/the tag system: a flow level is not
/// a tag). `display` comes from [flowLabel] (#157 review fix, #335
/// coupling) — the same human label `DaySheet`'s own flow chips use
/// (moved to `lib/domain/models/flow_level.dart` so this pure-Dart file
/// can share it without importing a UI widget file) — rather than a
/// bespoke title-case helper duplicating that logic.
Map<String, Object?> _flowCoding(FlowLevel flow) => _coding(
      ClinicalCode(
        system: kSystemLunarlogLocalFlow,
        code: flow.name,
        display: flowLabel(flow),
        provenanceUrl: kFhirExportLocalCodeDocPath,
      ),
    );

/// The self-reported `Observation`s from two sources (Issue #157 review
/// fix — the `observations` table alone missed every tagged symptom;
/// [DayEntry.tags] is the app's actual symptom surface, and the day sheet,
/// birth-control intake and the Clue import all write `observations` rows
/// too, issue #1116), **partitioned by `tags.tagClinicalRole` instead of
/// all landing in Problems (issue #1138)**:
/// - One per live (non-[Observation.excluded]) non-measurement, non-intake
///   `observations` row. Measurement rows (`bbt`/`weight`) are exported
///   as vital signs instead (see [_vitalSignEntries]) and birth-control
///   intake rows are not emitted as Observations at all (the A3-48 rule
///   `clinical_terminology.dart` documents), so both are filtered out here
///   (issue #1115).
/// - One per tag per day entry, from [DayEntry.tags] — **except** when a
///   live `observations` row already carries the same `(date, code)` pair,
///   so a fact captured as an explicit observation row is never duplicated
///   as a second, tag-derived one. The dedupe check runs over every live
///   row regardless of its role: the row carries the fact to whichever
///   section its role selects, and the tag must not double it there.
///
/// Each entry lands in one of three buckets via its [TagClinicalRole]:
/// `problem` findings for the Problems section, `testResult` home tests
/// for Results, `cycleObservation` normal/positive states for the
/// title-only "Cycle observations" section — while `notExported`
/// (medication, sex-life, substance) is dropped entirely (issue #1138).
({List<_ResourceEntry> problems, List<_ResourceEntry> testResults,
        List<_ResourceEntry> cycleObservations})
    _partitionSelfReported(
  List<(_ResourceEntry, tags.TagClinicalRole)> routed,
) {
  final problems = <_ResourceEntry>[];
  final testResults = <_ResourceEntry>[];
  final cycleObservations = <_ResourceEntry>[];
  for (final (entry, role) in routed) {
    switch (role) {
      case tags.TagClinicalRole.problem:
        problems.add(entry);
      case tags.TagClinicalRole.testResult:
        testResults.add(entry);
      case tags.TagClinicalRole.cycleObservation:
        cycleObservations.add(entry);
      case tags.TagClinicalRole.notExported:
        break; // Deliberately emitted nowhere (#1138).
    }
  }
  return (
    problems: problems,
    testResults: testResults,
    cycleObservations: cycleObservations,
  );
}

/// Every live self-reported row and every deduped day-entry tag, paired
/// with its [tags.TagClinicalRole] — the partition input
/// [_partitionSelfReported] buckets.
List<(_ResourceEntry, tags.TagClinicalRole)> _routedSelfReportedEntries(
  Profile profile,
  List<DayEntry> dayEntries,
  List<Observation> observations,
  String patientRef,
) {
  // Excluded rows (the BBT per-point flag, A1-44) are dropped before
  // anything else touches [observations] — see this file's "Exclusion
  // policy" doc note — so they can neither be emitted themselves nor
  // suppress a tag-derived Observation that would otherwise fill the gap
  // they leave. Measurement (`bbt`/`weight`) rows are vital signs, not
  // symptoms, birth-control intake rows are never Observations
  // (issue #1115), and free-text Clue tags (`category == 'tags'`) must
  // never leave the device (issue #1117) — none belongs in any section.
  final liveObservations = _liveSymptomObservations(observations);
  final existingDateCodes = _existingSymptomDateCodes(liveObservations);
  return [
    for (final observation in liveObservations)
      (
        (
          fullUrl: _fullUrl('observation:row:${observation.id}'),
          resource: _symptomObservation(observation, patientRef),
        ),
        _rowRole(observation),
      ),
    for (final entry in dayEntries)
      for (final tag in entry.tags)
        if (tags.isValidTagCode(tag) &&
            !existingDateCodes
                .contains(_dateCodeKey(entry.localDate.iso, tag)))
          (
            (
              // Deterministic v5 id from (profileId, date, tag) — see this
              // file's "Determinism" doc note: stable across export runs of
              // the same day entry, and unchanged by #1138's routing (the
              // same tag always hashes to the same urn:uuid wherever it is
              // now referenced from).
              fullUrl: _fullUrl(
                  'observation:tag:${profile.id}:${entry.localDate.iso}:$tag'),
              resource: _tagSymptomObservation(entry, tag, patientRef),
            ),
            tags.tagClinicalRole(tags.tagByCode(tag)!),
          ),
  ];
}

/// The live (non-excluded, non-measurement, non-intake, non-free-text)
/// `observations` rows the self-reported partition reads — the same filter
/// every consumer of these rows applies (see [_routedSelfReportedEntries]).
List<Observation> _liveSymptomObservations(List<Observation> observations) => [
      for (final observation in observations)
        if (!observation.excluded &&
            !observation.category.isMeasurement &&
            !_isBirthControlRow(observation) &&
            !_isFreeTextTagsRow(observation))
          observation,
    ];

/// The [tags.TagClinicalRole] of a live `observations` row: a row whose
/// option [Observation.code] is a taxonomy tag routes exactly as that tag
/// would (a Clue-imported `pregnancy_positive` and a day-entry tag
/// `pregnancy_positive` are the same fact); otherwise the row's category
/// wire code decides ([tags.tagClinicalRoleForCategory]) — and a category
/// this taxonomy does not know (Clue's `mucus`, or `spotting`) degrades to
/// the problem reading, the pre-#1138 behavior, rather than vanishing.
tags.TagClinicalRole _rowRole(Observation observation) {
  final code = observation.code;
  if (code != null) {
    final byCode = tags.tagClinicalRoleForCode(code);
    if (byCode != null) return byCode;
  }
  final byCategory =
      tags.categoryFromWireName(observation.category.wireCode);
  return byCategory == null
      ? tags.TagClinicalRole.problem
      : tags.tagClinicalRoleForCategory(byCategory);
}

/// Whether [observation] is a birth-control intake row (issue #1115) and so
/// must never be emitted as an `Observation`.
///
/// `ObservationCategory.isBirthControl` covers the app's six
/// `birth_control_*` category codes, but the **Clue import** writes the
/// unsuffixed category `'birth_control'` (`clue_option_map.dart`), which
/// [ObservationCategory.fromCode] does not know and so leaves as an
/// [UnknownObservationCategory] where `isBirthControl` is false. Matching
/// the wire string as well closes that leak without widening
/// `ObservationCategory.known` (other `isBirthControl` consumers would need
/// auditing first).
bool _isBirthControlRow(Observation observation) =>
    observation.category.isBirthControl ||
    observation.category.wireCode == 'birth_control' ||
    observation.category.wireCode.startsWith('birth_control_');

/// Whether [observation] is a free-text tag row (issue #1117) and so must
/// never be emitted off-device in a clinical export.
///
/// Clue's export writes free-text tags under `category: 'tags'` with the
/// raw user-typed text as `code` (`clue_option_map.dart`). Like `DayEntry.note`
/// and `Observation.valueText`, free-text notes entered by a user must never
/// be exported off-device, and a free-text tag that happens to equal a
/// taxonomy code must not falsely pick up a clinical coding.
bool _isFreeTextTagsRow(Observation observation) =>
    observation.category.wireCode == 'tags';

/// Measurement `Observation`s (issue #1115): one per live `bbt`/`weight`
/// row, exported in the IPS Vital Signs section rather than the Problems
/// list. Birth-control intake rows are deliberately absent — they must
/// never be modeled as `Observation`s (A3-48; see
/// `clinical_terminology.dart`'s `kBirthControlResourceShapes`).
///
/// Only a row that is an actual, interpretable measurement is a vital
/// sign: it must carry a numeric [Observation.valueNum] **and** a
/// recognised UCUM [Observation.unit] (see [_kUcumUnitCodes]). A Clue
/// import can store a BBT datapoint read from a raw `value`/`temperature`
/// key as `unit: 'value'`/`'temperature'` (ambiguous between °C and °F and
/// with no UCUM code), or a category-`bbt` row with no value at all; those
/// break the R4 vital-signs profile's required `valueQuantity.system`/
/// `code` and are omitted rather than exported as a malformed vital sign.
List<_ResourceEntry> _vitalSignEntries(
  List<Observation> observations,
  String patientRef,
) =>
    [
      for (final observation in observations)
        if (!observation.excluded &&
            observation.category.isMeasurement &&
            observation.valueNum != null &&
            _kUcumUnitCodes.containsKey(observation.unit))
          (
            fullUrl: _fullUrl('observation:row:${observation.id}'),
            resource: _vitalSignObservation(observation, patientRef),
          ),
    ];

/// `http://terminology.hl7.org/CodeSystem/observation-category#vital-signs`
/// — the `Observation.category` the R4 `vitalsigns`/`bodytemp`/
/// `bodyweight` profiles (and IPS 2.0.1's `sectionVitalSigns.entry:vitalSign`
/// slice, which references `vitalsigns`) require 1..1. Display "Vital
/// Signs" verified on `tx.fhir.org` 2026-09-26.
const String _kVitalSignsCategorySystem =
    'http://terminology.hl7.org/CodeSystem/observation-category';

/// One vital-sign `Observation` (issue #1115): basal body temperature as
/// LOINC `8310-5` plus SNOMED `300076005`, weight as LOINC `29463-7`.
/// Values and UCUM units come from the shared [_symptomObservationValue],
/// so a measurement's `valueQuantity` is emitted exactly as it is for any
/// other row.
Map<String, Object?> _vitalSignObservation(
  Observation observation,
  String patientRef,
) {
  final isBasalBodyTemperature =
      observation.category == ObservationCategory.bbt;
  return {
    'resourceType': 'Observation',
    'status': 'final',
    'category': [
      {
        'coding': [
          {
            'system': _kVitalSignsCategorySystem,
            'code': 'vital-signs',
            'display': 'Vital Signs',
          },
        ],
      },
    ],
    'code': {
      'coding': isBasalBodyTemperature
          ? [_coding(kBodyTemperatureLoinc), _coding(kBasalBodyTemperatureSnomed)]
          : [_coding(kBodyWeightLoinc)],
      'text': isBasalBodyTemperature ? 'Basal body temperature' : 'Body weight',
    },
    'subject': {'reference': patientRef},
    'effectiveDateTime': observation.localDate.iso,
    ..._symptomObservationValue(observation),
    'performer': [
      {'reference': patientRef},
    ],
    'note': [
      {'text': kSelfReportedNoteText},
    ],
  };
}

/// `'<localDate.iso>|<code>'` for every live `observations` row that
/// carries a [Observation.code] — the dedupe key [_tagSymptomEntries]
/// checks against.
Set<String> _existingSymptomDateCodes(List<Observation> liveObservations) => {
      for (final observation in liveObservations)
        if (observation.code != null)
          _dateCodeKey(observation.localDate.iso, observation.code!),
    };

String _dateCodeKey(String isoDate, String code) => '$isoDate|$code';

/// One `Observation` per logged option row (Issue #157: "one per
/// observation row"). Dual-coded via [dualCodingFor] when [Observation.code]
/// is a known tag code from `lib/domain/tags.dart`; otherwise falls back to
/// a [kSystemLunarlogLocal] coding built from `category`/`code` — the
/// ~200-option Clue-model observation vocabulary (Issue #240) is not the
/// same closed set as the 113-tag taxonomy `dualCodingFor` covers, and a
/// gap there must degrade to a local coding rather than guess a clinical
/// code (mirrors `dualCodingFor`'s own "no guessed codes" degrade).
Map<String, Object?> _symptomObservation(
  Observation observation,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': _symptomCode(observation),
      'subject': {'reference': patientRef},
      'effectiveDateTime': observation.localDate.iso,
      // #157 review fix, LLA-088 (Issue #612): `intensity` -> `valueInteger`,
      // `valueNum`+`unit` -> `valueQuantity` — but FHIR R4's `value[x]` is
      // 0..1 (hl7.org/fhir/R4/observation.html: "Actual result", cardinality
      // 0..1), so a row carrying BOTH (a coded severity alongside a numeric
      // measurement on the same observation row) can never emit both as
      // top-level `value[x]` siblings without producing an invalid
      // Observation. See [_symptomObservationValue]'s doc comment for the
      // primary-value-plus-component resolution.
      ..._symptomObservationValue(observation),
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
        // Issue #1114: a graded severity is meaningless without its scale —
        // a clinician reads a bare "4" on the usual 0-10 pain scale. This
        // is a `note`, not a `referenceRange`: an untyped R4 referenceRange
        // asserts the *normal* range, which "1-5" would wrongly do, and on
        // a row whose top-level value is a measurement it would qualify
        // that value. It also covers the intensity-in-component case.
        if (observation.intensity != null)
          {'text': kPainIntensityNoteText},
      ],
    };

/// Resolves [observation]'s `value[x]` (at most one key, R4's 0..1
/// cardinality) plus an optional `component` array (Issue #612, LLA-088).
///
/// - Neither [Observation.intensity] nor [Observation.valueNum]: no keys at
///   all (unchanged from before this fix).
/// - Exactly one of the two: that one becomes the top-level `value[x]`,
///   exactly as before this fix — the common case (a coded-severity symptom
///   row, or a numeric measurement row like BBT/weight) never gains a
///   `component` array it didn't have before.
/// - Both present (an edge case the domain model's generic row shape
///   permits, even though no production write path logs both today): the
///   numeric measurement is the more clinically precise fact and becomes
///   the top-level `valueQuantity`; the coded severity is never dropped —
///   it moves into a single-entry `component`, FHIR's own mechanism for a
///   secondary value alongside a primary one (e.g. a blood-pressure
///   Observation's systolic/diastolic components), with its own `code`
///   ([kSystemLunarlogLocalIntensity]) and `valueInteger`.
Map<String, Object?> _symptomObservationValue(Observation observation) {
  final intensity = observation.intensity;
  final valueNum = observation.valueNum;
  if (valueNum == null) {
    return intensity == null ? const {} : {'valueInteger': intensity};
  }
  final valueQuantity = {'valueQuantity': _valueQuantity(valueNum, observation.unit)};
  if (intensity == null) return valueQuantity;
  return {
    ...valueQuantity,
    'component': [_intensityComponent(intensity)],
  };
}

/// A local coding for the severity/intensity axis (Issue #612, LLA-088) —
/// no verified LOINC/SNOMED code for a bare "intensity" concept is carried
/// in `clinical_terminology.dart`'s table, so this follows that file's own
/// documented fallback: an explicit [kSystemLunarlogLocal] coding rather
/// than a guessed clinical code (this file's "Coding discipline" doc note).
Map<String, Object?> _intensityComponent(int intensity) => {
      'code': {
        'coding': [
          _coding(const ClinicalCode(
            system: kSystemLunarlogLocal,
            code: 'intensity',
            display: 'Symptom intensity',
            provenanceUrl: kFhirExportLocalCodeDocPath,
          )),
        ],
      },
      'valueInteger': intensity,
    };

/// The `Observation.note` appended to every intensity-bearing row (issue
/// #1114), built from the shared [kPainIntensityScaleText] so it matches
/// the clinician PDF's wording. A note rather than a `referenceRange`: R4
/// reads an untyped referenceRange as the *normal* range, which would
/// assert 1-5 is normal and (on a row whose primary value is a
/// measurement) misqualify that value.
const String kPainIntensityNoteText =
    'Intensity self-rated from $kPainIntensityScaleText; '
    'this is not the 0-10 clinical pain scale.';

/// UCUM unit codes for the closed `Observation.unit` set
/// `lib/domain/models/observation.dart` documents (`celsius`/`fahrenheit`/
/// `kg`/`lb`), verified against `http://unitsofmeasure.org`'s UCUM table.
/// An unrecognised [unit] (a future addition this map hasn't caught up
/// with yet) degrades to a plain `unit` display string with no
/// `system`/`code` — still valid FHIR, never a guessed UCUM code.
const Map<String, String> _kUcumUnitCodes = {
  'celsius': 'Cel',
  'fahrenheit': '[degF]',
  'kg': 'kg',
  'lb': '[lb_av]',
};

Map<String, Object?> _valueQuantity(double value, String? unit) {
  final ucumCode = unit == null ? null : _kUcumUnitCodes[unit];
  return {
    'value': value,
    'unit': ?unit,
    if (ucumCode != null) 'system': 'http://unitsofmeasure.org',
    'code': ?ucumCode,
  };
}

/// `Observation.code` for a live `observations` row: its codings plus a
/// `text` label built to stay meaningful with no category heading, since a
/// tag Observation carries none (issue #1114).
Map<String, Object?> _symptomCode(Observation observation) {
  final code = observation.code;
  if (code != null && tags.isValidTagCode(code)) {
    return _tagCode(code);
  }
  final local = _localObservationCoding(observation);
  return {
    'coding': [_coding(local)],
    'text': local.display,
  };
}

/// `Observation.code` for a taxonomy [tagCode]: dual-coded via
/// [dualCodingFor], with the lunarlog-local coding's `display` and the
/// `CodeableConcept.text` both set to [contextualDisplayForTag] — the
/// self-describing label (`tags.dart`) that does not depend on a category
/// heading the export never carries (issue #1114).
Map<String, Object?> _tagCode(String tagCode) {
  final display = tags.contextualDisplayForTag(tags.tagByCode(tagCode)!);
  return {
    'coding': _codingsForDisplay(dualCodingFor(tagCode), display),
    'text': display,
  };
}

/// [codings] with the lunarlog-local entry's `display` replaced by
/// [display] (issue #1114). External SNOMED/LOINC displays are the
/// terminology servers' own validated strings and are never rewritten;
/// only the local coding — lunarlog's own label — is contextualised.
List<Map<String, Object?>> _codingsForDisplay(
  List<ClinicalCode> codings,
  String display,
) =>
    [
      for (final coding in codings)
        if (coding.system == kSystemLunarlogLocal)
          {
            'system': coding.system,
            'code': coding.code,
            'display': display,
          }
        else
          _coding(coding),
    ];

/// Category contexts whose snake_case wire name is not the label a reader
/// should see in a Problem list (issue #1114 / reverification): "Discharge"
/// is overloaded with hospital discharge, and an unattested Clue `tests`
/// option would read as a laboratory result.
const Map<String, String> _kFallbackCategoryLabels = {
  'discharge': 'Vaginal discharge',
  'tests': 'Home test',
};

/// The display for a local (non-tag) `observations`-row coding in a
/// namespace with no category heading (issue #1114): the category context
/// plus the option, e.g. `'Birth control pill: missed'` rather than a bare
/// `'missed'` a clinician cannot place. When the option is the category
/// itself (e.g. a spotting row's `spotting`) the context alone is returned
/// — "Spotting", never "Spotting: spotting". The category's snake_case wire
/// code is rendered in sentence case (underscores become spaces).
String fhirLocalDisplayFor(String categoryWireCode, String? code) {
  final context =
      _kFallbackCategoryLabels[categoryWireCode] ??
          _sentenceCase(categoryWireCode);
  if (code == null || code == categoryWireCode) return context;
  final displayOption = code.replaceAll('_', ' ');
  return '$context: $displayOption';
}

String _sentenceCase(String wireCode) {
  final spaced = wireCode.replaceAll('_', ' ');
  if (spaced.isEmpty) return spaced;
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

ClinicalCode _localObservationCoding(Observation observation) => ClinicalCode(
      system: kSystemLunarlogLocal,
      code:
          '${observation.category.wireCode}:${observation.code ?? observation.category.wireCode}',
      display: fhirLocalDisplayFor(
        observation.category.wireCode,
        observation.code,
      ),
      provenanceUrl: kFhirExportLocalCodeDocPath,
    );

/// One `Observation` per tag per day entry (Issue #157 review fix), from
/// [DayEntry.tags] — the app's tagged-symptom surface, alongside the
/// `observations` rows the day sheet, birth-control intake and the Clue
/// import also write (issue #1116). Routing, dedupe against a live
/// `observations` row, and the unknown-code drop all happen in
/// [_routedSelfReportedEntries]; this builds the resource itself.
Map<String, Object?> _tagSymptomObservation(
  DayEntry entry,
  String tag,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': _tagCode(tag),
      'subject': {'reference': patientRef},
      'effectiveDateTime': entry.localDate.iso,
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
      ],
    };

List<_ResourceEntry> _statEntries(
  ActivePrediction? prediction,
  String idKey,
  String patientRef,
) {
  if (prediction == null) return const [];
  return [
    (
      fullUrl: _fullUrl('observation:cycle-length:$idKey'),
      resource: _cycleLengthObservation(prediction, patientRef),
    ),
    (
      fullUrl: _fullUrl('observation:lmp:$idKey'),
      resource: _lastMenstrualPeriodObservation(prediction, patientRef),
    ),
  ];
}

/// SNOMED `161716008` "Usual length of menstrual cycle" (issue #1115),
/// value = [ActivePrediction.meanCycleLengthDays] rounded to the nearest
/// whole day. Unlike the other clinical Observations this is **not**
/// self-reported: the app calculates it from the profile's logged period
/// starts, so it carries no `performer` and a note saying so rather than
/// [kSelfReportedNoteText].
Map<String, Object?> _cycleLengthObservation(
  ActivePrediction prediction,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [_coding(cycleLengthCodes.first)],
        'text': kUsualLengthOfMenstrualCycleSnomed.display,
      },
      'subject': {'reference': patientRef},
      'effectiveDateTime': prediction.today.iso,
      'valueQuantity': {
        'value': prediction.meanCycleLengthDays.round(),
        'unit': 'd',
        'system': 'http://unitsofmeasure.org',
        'code': 'd',
      },
      // R4 `Observation.method` — the value is a computed mean, not a
      // measured one (issue #1115; PR #1124 reverification).
      'method': {
        'text': 'Calculated (mean of recent logged cycles)',
      },
      'note': [
        {'text': kCalculatedCycleLengthNoteText},
      ],
    };

/// LOINC `8665-2` (last menstrual period start date), value = [ActivePrediction
/// .lastEpisodeStart].
Map<String, Object?> _lastMenstrualPeriodObservation(
  ActivePrediction prediction,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [_coding(loincByCode('8665-2')!)],
      },
      'subject': {'reference': patientRef},
      'effectiveDateTime': prediction.today.iso,
      'valueDateTime': prediction.lastEpisodeStart.iso,
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
      ],
    };

Map<String, Object?> _buildComposition({
  required String patientRef,
  required DateTime exportedAt,
  required List<String> resultsRefs,
  required List<String> vitalSignsRefs,
  required List<String> problemsRefs,
  required List<String> cycleObservationsRefs,
}) =>
    {
      'resourceType': 'Composition',
      'status': 'final',
      'type': {
        'coding': [_coding(kCompositionTypePatientSummary)],
      },
      'title': 'lunarlog clinical summary — cycle and symptom export',
      'date': exportedAt.toIso8601String(),
      'author': [
        {'reference': patientRef},
      ],
      'subject': {'reference': patientRef},
      // Document-level narrative (#157 review fix) — required alongside
      // `status`/`type`/`date`/`author`/`title` for a Composition a person
      // (not just a coded consumer) can render directly; counts only, the
      // same discipline as each section's own `text.div`.
      'text': {
        'status': 'generated',
        'div': _narrativeDiv(
          '${_entryCount(resultsRefs.length, 'Results')}, '
          '${_entryCount(vitalSignsRefs.length, 'Vital signs')}, '
          '${_entryCount(problemsRefs.length, 'Problems')}, '
          '${_entryCount(cycleObservationsRefs.length, 'Cycle observations')}.',
        ),
      },
      'section': [
        _buildSection(
          title: 'Results',
          code: kSectionResults,
          refs: resultsRefs,
          // Now also holds the home pregnancy/LH test results (#1138), so
          // the narrative names the section's mixed contents by its own
          // title rather than a "cycle observations" phrase it no longer
          // owns (that phrase is the next section's).
          emptyNarrative: 'No results recorded.',
          narrativeSuffix: 'result observation(s) recorded.',
        ),
        _buildSection(
          title: 'Vital signs',
          code: kSectionVitalSigns,
          refs: vitalSignsRefs,
          emptyNarrative: 'No vital signs recorded.',
          narrativeSuffix: 'vital sign observation(s) recorded.',
        ),
        _buildSection(
          title: 'Problems',
          code: kSectionProblems,
          refs: problemsRefs,
          emptyNarrative: 'No symptom findings recorded.',
          narrativeSuffix: 'self-reported symptom finding(s) recorded.',
        ),
        // Issue #1138's clearly-non-problem section: the normal/positive
        // states, fertility signs, and daily context the problem list must
        // not carry. Narrative says outright that these are not problems.
        _buildSection(
          title: 'Cycle observations',
          code: null,
          refs: cycleObservationsRefs,
          emptyNarrative: 'No self-reported cycle observations recorded.',
          narrativeSuffix:
              'self-reported cycle observation(s) recorded — normal states '
              'and daily context, not problems.',
        ),
      ],
    };

/// One Composition section: a minimal generated narrative (counts only —
/// never raw entry content, so the narrative itself never leaks anything
/// beyond what the coded `Observation` entries already carry) plus the
/// section's own `entry` references.
///
/// [code] is nullable: every section here has a verified LOINC section
/// code except "Cycle observations" (#1138) — no verified LOINC code
/// exists for a patient-stated non-problem observation section (candidates
/// checked against `tx.fhir.org` $lookup on 2026-09-28: `11369-6` is
/// LOINC's "History of Immunization note", not general health; `61149-5`
/// and `75318-0` do not resolve), and R4's `Composition.section.code` is
/// 0..1 — so that section ships title-only, the same "worse to claim than
/// omit" discipline as the `meta.profile` omission above.
Map<String, Object?> _buildSection({
  required String title,
  required ClinicalCode? code,
  required List<String> refs,
  required String emptyNarrative,
  required String narrativeSuffix,
}) =>
    {
      'title': title,
      if (code != null)
        'code': {
          'coding': [_coding(code)],
        },
      'text': {
        'status': 'generated',
        'div': _narrativeDiv(
          refs.isEmpty ? emptyNarrative : '${refs.length} $narrativeSuffix',
        ),
      },
      // #157 review fix: `emptyReason` (see [kSectionEmptyReasonUnavailable])
      // when there is nothing to list, rather than a bare empty `entry`.
      if (refs.isEmpty)
        'emptyReason': {
          'coding': [_coding(kSectionEmptyReasonUnavailable)],
        },
      'entry': [for (final ref in refs) {'reference': ref}],
    };

String _narrativeDiv(String text) =>
    '<div xmlns="http://www.w3.org/1999/xhtml">$text</div>';

/// `'3 Results entries'` / `'1 Problems entry'` — the document-level
/// narrative's per-section clause.
String _entryCount(int count, String sectionTitle) =>
    '$count $sectionTitle entr${count == 1 ? 'y' : 'ies'}';

/// One `Provenance` per Bundle (Issue #157: "exactly one"), recording the
/// export timestamp and marking the whole document as patient/guardian
/// self-report via lunarlog.
Map<String, Object?> _buildProvenance({
  required String compositionRef,
  required String patientRef,
  required DateTime exportedAt,
  required String appVersion,
}) =>
    {
      'resourceType': 'Provenance',
      'target': [
        {'reference': compositionRef},
      ],
      'recorded': exportedAt.toIso8601String(),
      'agent': [
        {
          'type': {
            'coding': [_coding(kProvenanceAgentTypeAuthor)],
          },
          'who': {'reference': patientRef},
        },
      ],
      'activity': {
        'coding': [_coding(kSelfReportedActivity)],
      },
      'entity': [
        {
          'role': 'source',
          'what': {'display': '$kAccountExportAppName v$appVersion'},
        },
      ],
    };
