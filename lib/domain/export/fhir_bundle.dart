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
/// `Observation`s for cycle/symptom data, and one `Provenance`. This is
/// **IPS-shaped, not IPS-conformant** (Issue #157 A3-49, modeled on
/// https://hl7.org/fhir/uv/ips/ IG v2.0.0): the section layout and resource
/// choices follow the International Patient Summary's shape (Results +
/// Problems sections, a self-authored Composition), but **no
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
/// - `Observation.performer` and a `note` mark every clinical fact as
///   self-reported (never a clinician observation) — see
///   [kSelfReportedNoteText] and [_buildProvenance]'s `activity` coding.
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
/// - `Patient`, the flow-day `Observation`s, and the tag-derived symptom
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
/// three more verified LOINC codes clinical_terminology.dart does not
/// carry ([kCompositionTypePatientSummary], [kSectionResults],
/// [kSectionProblems] — all Composition/section-level, not
/// `Observation.code`, so they do not belong in that file's
/// exhaustively-tested `kLoincCodes`), each verified the same way (see
/// each constant's `provenanceUrl`).
library;

import '../models/day_entry.dart';
import '../models/flow_level.dart';
import '../models/observation.dart';
import '../models/profile.dart';
import '../prediction/prediction.dart' show ActivePrediction;
import '../tags.dart' as tags show isValidTagCode;
import 'account_export.dart' show kAccountExportAppName;
import 'clinical_terminology.dart';

import 'package:uuid/uuid.dart';

/// Bumped whenever this file's FHIR mapping changes in a way a downstream
/// consumer must know about (parallels
/// `account_export.dart`'s `kAccountExportSchemaVersion`). Carried as
/// `Bundle.meta.tag` via [_versionTag] — see this file's "Versioning" doc
/// note above.
const int kFhirExportBundleVersion = 1;

/// lunarlog's own code system for the version tag ([_versionTag]) — a
/// distinct URI from [kSystemLunarlogLocal] (clinical concepts) because a
/// version marker is not a clinical coding. (Not the Bundle's own
/// `identifier.system` — #157 review fix: that is `urn:ietf:rfc:3986`,
/// since `identifier.value` is itself a URI; see [buildFhirDocumentBundle].)
const String kFhirExportVersionSystem =
    'https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/export-version';

/// lunarlog's own code system for flow-level codings (#157 review fix,
/// `docs/clinical/terminology.md`'s "FlowLevel — stays fully local"
/// section) — a distinct URI from [kSystemLunarlogLocal], which
/// `clinical_terminology.dart` documents as *the tag system*
/// (`.../CodeSystem/tag`). A flow level is not a tag: giving it its own
/// system keeps `kSystemLunarlogLocal`'s own meaning ("one of the 45
/// `lib/domain/tags.dart` codes") exact, rather than overloading it with
/// an unrelated five-value scale. **Permanent once emitted**, the same as
/// [kSystemLunarlogLocal] itself — do not change this value casually.
const String kSystemLunarlogLocalFlow =
    'https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/flow';

/// Where the local codings this file (as opposed to
/// clinical_terminology.dart's tag codings) introduces are documented:
/// flow-level codings (on [kSystemLunarlogLocalFlow]), the generic
/// per-`Observation`-row fallback coding, and the self-reported
/// `Provenance.activity` coding (both still on [kSystemLunarlogLocal] —
/// #157 review fix only split flow levels out into their own system,
/// since only flow levels are a genuinely distinct concept space from
/// tags; "self-reported" is a marker, not a competing taxonomy, and the
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
/// as [kCompositionTypePatientSummary]. Holds the menstrual-status and
/// cycle-statistic `Observation`s.
const ClinicalCode kSectionResults = ClinicalCode(
  system: kSystemLoinc,
  code: '30954-2',
  display: 'Relevant diagnostic tests/laboratory data note',
  provenanceUrl:
      'https://tx.fhir.org/r4/CodeSystem/\$lookup?system=http://loinc.org&code=30954-2',
);

/// LOINC `11450-4` — the IPS "Problems Section" code, verified the same
/// way. Holds the self-reported symptom `Observation`s. (These are
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
  final symptomEntries =
      _symptomEntries(profile, dayEntries, observations, patientRef);
  final statEntries = _statEntries(prediction, idKey, patientRef);

  final composition = _buildComposition(
    patientRef: patientRef,
    exportedAt: utcExportedAt,
    resultsRefs: [
      for (final entry in flowEntries) entry.fullUrl,
      for (final entry in statEntries) entry.fullUrl,
    ],
    problemsRefs: [for (final entry in symptomEntries) entry.fullUrl],
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
    for (final entry in symptomEntries) entry,
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
      // "not bleeding" day can never emit a menstrual-status Observation
      // even after #335 adds flow levels beyond today's five.
      for (final entry in dayEntries.where((e) => isBleed(e.flow)))
        (
          fullUrl: _fullUrl('observation:flow:${entry.id}'),
          resource: _flowObservation(entry, patientRef),
        ),
    ];

/// One `Observation` per bleed day (Issue #157: "one per day entry with
/// flow ≠ none"), coded with both [menstrualStatusCodes] LOINC codes
/// (`8678-5` patient-reported, `3146-8` general) and a
/// [kSystemLunarlogLocal] `valueCodeableConcept` naming the local flow
/// level.
Map<String, Object?> _flowObservation(DayEntry entry, String patientRef) => {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [for (final code in menstrualStatusCodes) _coding(code)],
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

/// Symptom `Observation`s from two sources (Issue #157 review fix — the
/// `observations` table alone missed every tagged symptom, since nothing in
/// production writes that table yet; [DayEntry.tags] is the app's actual
/// symptom surface):
/// - One per live (non-[Observation.excluded]) `observations` row —
///   [_rowSymptomEntries].
/// - One per tag per day entry, from [DayEntry.tags] — [_tagSymptomEntries]
///   — **except** when a live `observations` row already carries the same
///   `(date, code)` pair, so a symptom already captured as an explicit
///   observation row is never duplicated as a second, tag-derived one.
List<_ResourceEntry> _symptomEntries(
  Profile profile,
  List<DayEntry> dayEntries,
  List<Observation> observations,
  String patientRef,
) {
  // Excluded rows (the BBT per-point flag, A1-44) are dropped before
  // anything else touches [observations] — see this file's "Exclusion
  // policy" doc note — so they can neither be emitted themselves nor
  // suppress a tag-derived Observation that would otherwise fill the gap
  // they leave.
  final liveObservations = [
    for (final observation in observations) if (!observation.excluded) observation,
  ];
  final existingDateCodes = _existingSymptomDateCodes(liveObservations);
  return [
    ..._rowSymptomEntries(liveObservations, patientRef),
    ..._tagSymptomEntries(profile, dayEntries, existingDateCodes, patientRef),
  ];
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
/// same closed set as the 67-tag taxonomy `dualCodingFor` covers, and a
/// gap there must degrade to a local coding rather than guess a clinical
/// code (mirrors `dualCodingFor`'s own "no guessed codes" degrade).
List<_ResourceEntry> _rowSymptomEntries(
  List<Observation> liveObservations,
  String patientRef,
) =>
    [
      for (final observation in liveObservations)
        (
          fullUrl: _fullUrl('observation:row:${observation.id}'),
          resource: _symptomObservation(observation, patientRef),
        ),
    ];

Map<String, Object?> _symptomObservation(
  Observation observation,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {'coding': _symptomCodings(observation)},
      'subject': {'reference': patientRef},
      'effectiveDateTime': observation.localDate.iso,
      // #157 review fix: `intensity` -> `valueInteger`, `valueNum`+`unit`
      // -> `valueQuantity`. [Observation.valueText] is never emitted (see
      // this file's "Exclusion policy" doc note) — a free-text escape
      // hatch is exactly the kind of field this export excludes.
      if (observation.intensity != null) 'valueInteger': observation.intensity,
      if (observation.valueNum != null)
        'valueQuantity': _valueQuantity(observation.valueNum!, observation.unit),
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
      ],
    };

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

List<Map<String, Object?>> _symptomCodings(Observation observation) {
  final code = observation.code;
  if (code != null && tags.isValidTagCode(code)) {
    return [for (final coding in dualCodingFor(code)) _coding(coding)];
  }
  return [_coding(_localObservationCoding(observation))];
}

ClinicalCode _localObservationCoding(Observation observation) => ClinicalCode(
      system: kSystemLunarlogLocal,
      code: '${observation.category}:${observation.code ?? observation.category}',
      display: observation.code ?? observation.category,
      provenanceUrl: kFhirExportLocalCodeDocPath,
    );

/// One `Observation` per tag per day entry (Issue #157 review fix), from
/// [DayEntry.tags] — the app's actual symptom surface, since nothing in
/// production writes the `observations` table yet. Skips a `(date, tag)`
/// pair already present in [existingDateCodes] (a live `observations` row
/// covering the same day/code — see [_symptomEntries]'s dedupe note) and
/// any tag that is not a recognised taxonomy code (defensive: every
/// [DayEntry.tags] entry is validated against the taxonomy at the write
/// boundary, but this builder does not re-trust that — an unrecognised
/// code here degrades to "not exported" rather than a guessed clinical
/// coding, the same discipline [dualCodingFor] itself enforces).
List<_ResourceEntry> _tagSymptomEntries(
  Profile profile,
  List<DayEntry> dayEntries,
  Set<String> existingDateCodes,
  String patientRef,
) =>
    [
      for (final entry in dayEntries)
        for (final tag in entry.tags)
          if (tags.isValidTagCode(tag) &&
              !existingDateCodes.contains(_dateCodeKey(entry.localDate.iso, tag)))
            (
              // Deterministic v5 id from (profileId, date, tag) — see this
              // file's "Determinism" doc note: stable across export runs of
              // the same day entry, unlike the Bundle/Composition/
              // Provenance/stat-Observation ids.
              fullUrl: _fullUrl(
                  'observation:tag:${profile.id}:${entry.localDate.iso}:$tag'),
              resource: _tagSymptomObservation(entry, tag, patientRef),
            ),
    ];

Map<String, Object?> _tagSymptomObservation(
  DayEntry entry,
  String tag,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [for (final coding in dualCodingFor(tag)) _coding(coding)],
      },
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

/// LOINC `64700-8` (typical cycle length), value = [ActivePrediction
/// .meanCycleLengthDays] rounded to the nearest whole day.
Map<String, Object?> _cycleLengthObservation(
  ActivePrediction prediction,
  String patientRef,
) =>
    {
      'resourceType': 'Observation',
      'status': 'final',
      'code': {
        'coding': [_coding(cycleLengthCodes.first)],
      },
      'subject': {'reference': patientRef},
      'effectiveDateTime': prediction.today.iso,
      'valueQuantity': {
        'value': prediction.meanCycleLengthDays.round(),
        'unit': 'd',
        'system': 'http://unitsofmeasure.org',
        'code': 'd',
      },
      'performer': [
        {'reference': patientRef},
      ],
      'note': [
        {'text': kSelfReportedNoteText},
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
  required List<String> problemsRefs,
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
          '${_entryCount(problemsRefs.length, 'Problems')}.',
        ),
      },
      'section': [
        _buildSection(
          title: 'Results',
          code: kSectionResults,
          refs: resultsRefs,
          emptyNarrative: 'No cycle observations recorded.',
          narrativeSuffix: 'cycle/menstrual observation(s) recorded.',
        ),
        _buildSection(
          title: 'Problems',
          code: kSectionProblems,
          refs: problemsRefs,
          emptyNarrative: 'No symptom findings recorded.',
          narrativeSuffix: 'self-reported symptom finding(s) recorded.',
        ),
      ],
    };

/// One Composition section: a minimal generated narrative (counts only —
/// never raw entry content, so the narrative itself never leaks anything
/// beyond what the coded `Observation` entries already carry) plus the
/// section's own `entry` references.
Map<String, Object?> _buildSection({
  required String title,
  required ClinicalCode code,
  required List<String> refs,
  required String emptyNarrative,
  required String narrativeSuffix,
}) =>
    {
      'title': title,
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
