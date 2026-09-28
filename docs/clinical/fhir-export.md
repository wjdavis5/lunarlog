# FHIR R4 clinical export Bundle

Issue #157 (epic: clinical-export), depends on #152 (terminology, this
repo's [`terminology.md`](terminology.md)) and #240 (the `observations`
child table). Builder:
[`lib/domain/export/fhir_bundle.dart`](../../lib/domain/export/fhir_bundle.dart);
writer:
[`lib/data/export/fhir_bundle_writer.dart`](../../lib/data/export/fhir_bundle_writer.dart);
UI: [`lib/ui/settings/clinical_export_tile.dart`](../../lib/ui/settings/clinical_export_tile.dart)
("Export clinical summary (FHIR)", Settings → Your data).

lunarlog's original export
([`account_export.dart`](../../lib/domain/export/account_export.dart)) is
the internal JSON round-trip/backup document — schemaVersion, profiles,
day entries, observations, merged with the server's own export when
signed in. This is a **separate, clinician-consumable** format: a FHIR R4
`Bundle`, built entirely on-device from the same local data, delivered
through the same share-sheet pattern but as its own file
(`lunarlog-fhir-<yyyyMMdd>.json`, `application/fhir+json`).

## Bundle shape

`Bundle.type = "document"`. Entry order:

1. **Composition** (`status: final`, `type` LOINC `60591-5` "Patient
   summary Document") — the document header. `author` and `subject` are
   both the Patient. Alongside `status`/`type`/`date`/`author`/`title` (the
   elements a FHIR-conformant Composition requires), it carries its own
   document-level `text` narrative (a `status: generated` summary of the
   record counts) — the same discipline each section's own `text.div`
   already follows, just at the document level. Four sections:
   - **Results** (LOINC `30954-2`) — the menstrual-flow Observations
     (one per day entry that is a bleed day — see `isBleed` below), the
     two cycle-statistic Observations derived from `ActivePrediction` when
     available, and — since issue #1138 — the home pregnancy/LH test
     Observations (a test result is a result, wherever it was logged,
     keeping its "Home test" labels).
   - **Vital signs** (LOINC `8716-3`, issue #1115) — the BBT and weight
     measurement Observations (see "Measurement rows" below).
   - **Problems** (LOINC `11450-4`) — the self-reported **symptom**
     Observations: one per live (non-excluded) `observations` table row,
     plus one per tag per day entry from `DayEntry.tags`, each routed by
     `tags.tagClinicalRole` so only symptom findings land here
     (issue #1138 — see "Self-reported Observations: two sources, four
     destinations" below). These are FHIR `Observation`
     findings, not `Condition` diagnoses: IPS's Problems section normally
     expects Conditions, and this export deliberately never asserts a
     self-reported symptom log as a diagnosed condition. Problems was
     still the closer semantic fit of the two IPS sections for a symptom
     finding, so that is where it went, with this caveat recorded rather
     than silently choosing a wrong-but-quieter section. Measurement rows
     and birth-control intake rows are deliberately **not** here (see
     "Measurement rows" and "Exclusion policy").
   - **Cycle observations** (no section code, issue #1138) — the
     normal/positive states, fertility signs, and daily context
     (`great_digestion`, discharge types, positive mood, sleep durations,
     exercise, collection method, `pain_free`) that must never read as
     patient problems. The section ships **title-only**: no verified LOINC
     section code exists for a patient-stated non-problem observation
     section (candidates checked against `tx.fhir.org` $lookup,
     2026-09-28: `11369-6` is "History of Immunization note"; `61149-5`
     and `75318-0` do not resolve), and R4's `Composition.section.code` is
     0..1 — the same "worse to claim than omit" discipline as the
     `meta.profile` omission. Its narrative says outright that its entries
     are "normal states and daily context, not problems".
   Each section carries a minimal generated narrative (`text.div`) — a
   count and a fixed sentence, never raw entry content, so the narrative
   itself never discloses anything the coded Observations don't already
   carry — and, when it has no entries at all, an `emptyReason` (coded
   `unavailable` on the FHIR core `list-empty-reason` CodeSystem) instead
   of a bare empty `entry` array.
2. **Patient** — see below.
3. **Observation** entries — flow-day, self-reported (symptom / test
   result / cycle observation), vital-sign, and (if present)
   cycle-statistic.
4. **Provenance** — exactly one per Bundle.

## Self-reported Observations: two sources, four destinations (#157 review fix; #1138 routing)

Early v1 read only the `observations` table (Issue #240's per-option-row
child table) for symptom findings — but at the time nothing in production
wrote that table, so every tagged symptom (`DayEntry.tags`, the app's real
symptom-logging surface) was silently missing from the export. **That
"nothing writes it" claim is now stale (issue #1116):** the day sheet
writes pain, spotting, BBT and weight rows, birth-control intake writes
its `birth_control_*` rows, and the Clue import writes rows too
(`birth_control` and other categories). The self-reported Observations
emit from **both**:

- One `Observation` per live (`excluded == false`) non-measurement,
  non-intake `observations` row, dual-coded via `dualCodingFor` (or the
  local fallback — see "Coding discipline" below). Measurement
  (`bbt`/`weight`) rows and birth-control intake rows
  (`birth_control_*` and the Clue `birth_control` category) are
  filtered out here — see "Measurement rows" and
  "Exclusion policy".
- One `Observation` per tag per day entry, from `DayEntry.tags`, also
  dual-coded via `dualCodingFor` — **except** when a live `observations`
  row already carries the same `(effectiveDateTime, code)` pair, so a
  fact captured both ways is never emitted twice. An `observations`
  row with `excluded == true` does *not* count for this dedupe check
  (see "Exclusion policy" below) — an excluded row means there is
  nothing there to have already captured that fact.

### Where each entry lands: `TagClinicalRole` (issue #1138)

Until #1138 every one of those entries went to Problems — so "Great
(digestion)", egg-white discharge, sex-drive tags, home pregnancy test
results and "Took an antibiotic" all read as patient problems. The
shared predicate `tags.tagClinicalRole` (`lib/domain/tags.dart`) now
routes each entry by category first, then by code inside the mixed
categories that carry both a symptomatic and a normal/positive half:

- **`problem`** → Problems (11450-4): the symptoms (cramps, headache,
  bloating, fatigue, irritability, ailments such as fever or injury, …).
- **`testResult`** → Results (30954-2): the five `tests` codes
  (pregnancy/LH), keeping their "Home test" labels.
- **`cycleObservation`** → the title-only "Cycle observations" section:
  normal/positive states and daily context (`great_*`, stool "Normal",
  discharge types, positive mood, `pain_free`, sleep-duration buckets,
  good skin/hair, exercise, collection method).
- **`notExported`** → emitted nowhere: medications taken (plus the
  `hot_flashes` category's `hrt`, a therapy routed with them), the whole
  `sex_life` category, and the substance-use `partying` category —
  sensitive on a minor's record, omitted by default per the issue.

A row whose option code is a taxonomy tag routes exactly as that tag
would (a Clue-imported `pregnancy_positive` and a day-entry tag are the
same fact); a row with a raw Clue string routes by its category
(`tagClinicalRoleForCategory` — a `kSymptomTagCategories` member defaults
to the problem reading so an unclassifiable option in a symptom category
still shows as a finding, any other category routes to cycle context),
and a wire category this taxonomy does not know at all (`spotting`,
Clue's `mucus`) keeps the pre-#1138 problem reading rather than silently
vanishing. The symptom/non-symptom line is issue #1147's
`kSymptomTagCategories` + `kWellnessTagCodes` via `isSymptomTagCode` —
the same predicate the clinician PDF's symptom grid consumes (its fix is
issue #1144, merged as #1147) — so both exports draw one line.

Each tag-derived Observation's id is a deterministic UUID v5 hash of
`(profile.id, effectiveDateTime, tag)` — stable across two export runs of
the same day entry, the same guarantee the flow-day and `observations`-row
Observations already had (see "Determinism" below). #1138's routing
changed where an entry is *referenced from*, never its id: the same tag
hashes to the same `urn:uuid` wherever it now lands.

### Tag labels are self-describing (issue #1114)

A tag `Observation` carries no category heading, so its
`CodeableConcept.text` (and the lunarlog-local coding's `display`) is the
only human-readable text a receiving system may show. The export uses
`contextualDisplayForTag` (`lib/domain/tags.dart`): a per-code override
where no category prefix reads correctly ("Trouble sleeping", "Home
pregnancy test: positive", "Home ovulation (LH) test: negative", "Took
pain medication", "Took an antibiotic", "Sex: withdrawal method
(pull-out)", "Ailment: allergy symptoms", "Alcoholic drinks"), otherwise
`flatDisplayForTag` plus a category context for options that lose their
meaning alone ("Sleep duration: 0-3 hours", "Vaginal discharge: Egg
white", "Stool: Normal", "Craving: Sweet"). Collisions stay disambiguated
("Great (digestion)" / "Great (stool)"). A non-tag `observations` row's
local fallback display is category-qualified too (e.g. "Vaginal discharge:
egg white"), and a row whose option is its own category renders as the
category alone ("Spotting", never "Spotting: spotting"). Underscores in
option codes are rendered as spaces.

### Measurement rows: Vital Signs, not Problems (issue #1115)

Live `bbt` and `weight` `observations` rows no longer ride the generic
local fallback into Problems. They are emitted in the IPS **Vital Signs**
section (LOINC `8716-3`) with `Observation.category`
`http://terminology.hl7.org/CodeSystem/observation-category#vital-signs`
(the R4 `vitalsigns`/`bodytemp`/`bodyweight` profiles require it 1..1):

- BBT → LOINC `8310-5` "Body temperature" **plus** SNOMED `300076005`
  "Basal body temperature", value and UCUM unit unchanged.
- Weight → LOINC `29463-7` "Body weight", value and UCUM unit unchanged.

Only a row that is an actual, interpretable measurement becomes a vital
sign: it needs a numeric value **and** a recognised UCUM unit (`Cel`,
`[degF]`, `kg`, `[lb_av]`). A Clue BBT datapoint read from a raw
`value`/`temperature` key stores `unit: 'value'`/`'temperature'` (no UCUM
code, and ambiguous between °C and °F), and an unknown-shape row can carry
no value at all; both break the profile's required
`valueQuantity.system`/`code` and are omitted rather than exported.

Birth-control intake rows — the app's `birth_control_*` categories and the
Clue import's unsuffixed `birth_control` category — are not emitted at all:
they are not `Observation`s (the A3-48 rule
`clinical_terminology.dart` records), and no `MedicationStatement`/`Device`
builder exists yet, so they are deliberately absent rather than exported
under a wrong resource type.

## `Observation` value shape (#157 review fix; Issue #612 LLA-088)

A symptom `Observation` (from either source above) carries, when present
on the underlying row:

- `intensity` → `valueInteger`, **with** a second `Observation.note`
  stating the scale (issue #1114): "Intensity self-rated from 1 (least
  intense) to 5 (most intense); this is not the 0-10 clinical pain scale."
  A **note**, not a `referenceRange`: R4 reads an untyped reference range
  as the *normal* range, so a 1-5 range would assert 1-5 is normal and, on
  a row whose top-level value is a measurement, would wrongly qualify that
  value. The scale wording is shared with the clinician PDF.
- `valueNum` + `unit` → `valueQuantity`. `unit` carries the UCUM code
  (`system: http://unitsofmeasure.org`, `code`) for the closed unit set
  `Observation.unit` documents today (`celsius`→`Cel`,
  `fahrenheit`→`[degF]`, `kg`→`kg`, `lb`→`[lb_av]`); an unrecognised unit
  degrades to a plain `unit` display string with no `system`/`code` —
  still valid FHIR, never a guessed UCUM code.
- `valueText` is **never** emitted, under any circumstance — see
  "Exclusion policy" below.

**`value[x]` is 0..1 (Issue #612, LLA-088).** FHIR R4 allows at most one
`value[x]` choice on an `Observation`
(`hl7.org/fhir/R4/observation.html`: "Actual result" [0..1]) — a row
carrying both `intensity` and `valueNum` can never emit `valueInteger` AND
`valueQuantity` as top-level siblings without producing an invalid
resource. Only `valueNum` (the more clinically precise, measured fact)
becomes the top-level `value[x]` in that case; `intensity` is never
dropped — it moves into a single-entry `component` (the same FHIR
mechanism a blood-pressure Observation uses for its systolic/diastolic
pair), coded with the new local `intensity` code below. The common,
single-value case (only one of the two set on the row — true for every
production write path today) is unaffected: that value still goes
straight onto the top level, exactly as before this fix.

## Patient resource: display name only

`Patient` carries `name: [{text: <display name>}]` and nothing else. No
`identifier` block at all — not even a namespaced-internal one. That was
a considered choice, not an oversight: any identifier durable enough to be
useful to a downstream system (an internal ULID, even namespaced) is also
durable enough to become a cross-system linking key once the file leaves
the device, and the whole point of this export is that it can leave the
device. No `birthDate` either, even though `Profile.birthYear` exists —
issue #157 asks for "the display name and nothing else," and an optional
approximate birth year is exactly the kind of extra field that decision is
meant to keep out.

## Self-reported, never a clinician observation

The raw logged `Observation`s and the `Provenance` itself mark the data as
patient/guardian self-report:

- `Observation.performer` is the Patient (never a `Practitioner`).
- `Observation.note` carries a fixed sentence: "Self-reported by the
  patient or guardian via lunarlog; not a clinician assessment." (a plain
  R4 `note`, not a custom extension — no new extension URI to define and
  maintain for this).
- The single `Provenance.agent` has `type` coded `author`
  (`http://terminology.hl7.org/CodeSystem/provenance-participant-type`,
  verified against `tx.fhir.org`) and `who` = the Patient.
- `Provenance.activity` is coded `self-reported` on lunarlog's own local
  system — no verified external FHIR R4 code represents "patient
  self-report" as a `Provenance.activity` in the core value sets, so this
  is an explicit local decision (see "Local codes" below), not a guess.

**Exception — calculated values are not self-reported (issue #1115).**
The typical-cycle-length `Observation` is computed by lunarlog from the
profile's logged period starts, so it is **not** marked self-reported: it
carries no `performer`, an `Observation.method.text` of "Calculated (mean
of recent logged cycles)", and a note spelling that out — "Mean of the
15-60 day cycles among the last 12 completed cycles (cycles the patient or
guardian excluded from averages are left out), calculated by lunarlog from
period start dates logged by the patient or guardian; not measured or
confirmed by a clinician." The window wording is built from the prediction
engine's own constants. (The LMP `Observation` *is* self-reported — its
value is the logged period-start date itself, not a derivation.) The
earlier "every clinical Observation is self-reported" claim was misleading
for this row (issue #1116).

## IPS-shaped, not IPS-conformant

Modeled on the [International Patient Summary](https://hl7.org/fhir/uv/ips/)
(IG v2.0.0, FHIR R4) — a Composition-led document with Results/Vital
signs/Problems sections — but **no `Bundle.meta.profile` or
`Composition.meta.profile` is
ever asserted**. IPS has required sections this app cannot populate yet
(Allergies, Medications, and Problems as `Condition` resources, not
`Observation`s) — claiming the profile while a real IPS validator would
fail it is worse than not claiming it. This stays true until a validator
run (the [HL7 FHIR validator](https://confluence.hl7.org/display/FHIR/Using+the+FHIR+Validator))
against a specific IPS package version actually passes; when that happens,
`meta.profile` gets added deliberately, in its own change, not backfilled
quietly into this one.

## Exclusion policy (extends R9)

`account_export.dart`'s R9 (no sync bookkeeping, no guardian attribution
ids, nothing not already a plain domain field) is extended further here,
because a FHIR document can leave the device:

- No storage-assigned id (`Profile.id`, `DayEntry.id`, `Observation.id`)
  is ever written into the output literally — not even as a FHIR
  `identifier`. Every `Bundle.entry.fullUrl` / `reference` is a
  deterministic `urn:uuid` derived via UUID v5 (RFC 4122 §4.3, namespace
  `Namespace.url`) from a name built out of the internal id — a one-way
  hash used only to keep references internally consistent and
  deterministic within one Bundle, never a way to recover the original id
  from the output.
- No `loggedByUserId`/`lastModifiedByUserId`/`sourceId`/`importId`/email/
  Supabase user id anywhere.
- **Birth-control intake rows (#1115)** are never emitted — the app's
  per-day `birth_control_*` categories and the Clue import's unsuffixed
  `birth_control` category alike. The A3-48 rule
  is that no birth-control method shape is modeled as an `Observation`;
  these intake rows are not an
  `Observation`-shaped concept, and no `MedicationStatement`/`Device`
  builder exists yet, so they are absent rather than exported under a
  wrong resource type. Pregnancy/birth-control resource mapping remains
  out of scope until those resource builders exist —
  `clinical_terminology.dart` already reserves the shape for that.
- **`DayEntry.note` (#157 review fix)** is never read by `fhir_bundle.dart`
  at all — no function in that file even accepts it as a parameter, so
  there is no code path that could leak it into the export. Free-text a
  guardian typed into a day's note field is exactly the kind of content
  this export must never carry off-device.
- **Free-text Clue tags (#1117)** (`category == 'tags'`) are never emitted.
  Clue's export writes user-entered free-text tags into `observations` under
  `category: 'tags'` with the raw text as `code`. Like `DayEntry.note` and
  `Observation.valueText`, user-entered free text must never leave the device
  in a clinical export, and a free-text tag that happens to equal a taxonomy
  string (e.g. "headache") must not falsely pick up clinical coding.
- **`Observation.excluded` rows (#157 review fix)** — the BBT per-point
  exclusion flag (A1-44) — are skipped entirely: not emitted, not marked
  `entered-in-error`, just absent. Exporting an excluded point at all
  would contradict the user having marked it as not counting.
  `Observation.valueText` (the free-text escape hatch, A1-45) is likewise
  never emitted, for the same reason as `DayEntry.note` above.

`test/domain/export/fhir_bundle_test.dart` pins this: it asserts the
literal internal ids used to build a fixture Bundle never appear anywhere
in the encoded output, that no forbidden key (`userId`/`email`/
`loggedByUserId`/etc.) appears anywhere either, that a distinctive
`DayEntry.note` fixture string never appears in the output, and that an
excluded `observations` row (and its `valueText`) never does either.

## Versioning

`Bundle.meta.tag` carries one entry: `system`
`https://lunarlog.app/fhir/CodeSystem/export-version`,
`code` the current `kFhirExportBundleVersion` (`3` as of
issue #1138, which routed the self-reported tag/row Observations by
`TagClinicalRole`: Problems carries only symptoms, home test results
moved to Results, normal/positive states moved to a new title-only
"Cycle observations" section, and medication/sex-life/substance tags are
no longer exported; `2` was issues #1114/#1115, which changed the pain
scale, flow/cycle-length coding, tag labels, and the Vital Signs
section). A future change to this
file's mapping bumps that constant so a downstream consumer (or a person
comparing two exports) can tell the shapes apart.

## Code-system URIs are permanent (frozen from the first shipped build)

Every lunarlog-local `Coding.system` this export emits is built from a
single constant, `kFhirCodeSystemBase`
(`https://lunarlog.app/fhir/CodeSystem`, issue #961), plus a short path
segment: `/tag` (`kSystemLunarlogLocal`, the tag taxonomy), `/flow`
(`kSystemLunarlogLocalFlow`), and `/export-version`
(`kFhirExportVersionSystem`). #961 moved the base here from
`https://github.com/wjdavis5/lunarlog/fhir/...` before the first store
build shipped an export, and collapsed three separately-repeated
full-literal bases onto the one constant. **These URIs are frozen from
the first shipped build and must never change** — a Bundle already handed
to a clinician cannot be recalled, so the URI is an identity, not a link.
Nothing needs to resolve at it for FHIR validity (hosting is issue #450's
separate concern).

## Coding discipline: no guessed codes

Every `Observation.code` / `valueCodeableConcept` coding comes from
[`clinical_terminology.dart`](../../lib/domain/export/clinical_terminology.dart)'s
verified table (issue #152) or an explicit local coding on lunarlog's own
system (`kSystemLunarlogLocal`,
`https://lunarlog.app/fhir/CodeSystem/tag`) with a
documented reason — never a code typed from memory. `fhir_bundle.dart`
itself adds four more verified LOINC codes and two verified HL7
terminology codes that `clinical_terminology.dart` does not carry, because
they are Composition/section/Provenance/category-level, not
`Observation.code`, so
they don't belong in that file's exhaustively-tested `kLoincCodes` list:

| Code | System | Display | Used for | Verified |
|---|---|---|---|---|
| `60591-5` | LOINC | Patient summary Document | `Composition.type` | `tx.fhir.org` $lookup, 2026-09-09 |
| `30954-2` | LOINC | Relevant diagnostic tests/laboratory data note | Results section `.code` | `tx.fhir.org` $lookup, 2026-09-09 |
| `11450-4` | LOINC | Problem list - Reported | Problems section `.code` | `tx.fhir.org` $lookup, 2026-09-09 |
| `8716-3` | LOINC | Vital signs note | Vital signs section `.code` | `tx.fhir.org` $lookup, 2026-09-26 |
| `vital-signs` | `http://terminology.hl7.org/CodeSystem/observation-category` | Vital Signs | vital-sign `Observation.category` | `tx.fhir.org` $validate-code, 2026-09-26 |
| `author` | `http://terminology.hl7.org/CodeSystem/provenance-participant-type` | Author | `Provenance.agent.type` | `tx.fhir.org` $lookup, 2026-09-09 |
| `unavailable` | `http://terminology.hl7.org/CodeSystem/list-empty-reason` | Unavailable | `Composition.section.emptyReason` | FHIR R4 core CodeSystem / `tx.fhir.org` |

The #1138 "Cycle observations" section appears in no row above on
purpose: no verified LOINC section code exists for it (candidates checked
against `tx.fhir.org` $lookup, 2026-09-28 — see "Bundle shape"), so it
ships title-only rather than with a guessed code.

Observation-level coding (post-#1115/#1116):

- Per-day flow: SNOMED `364308001` "Quantity of menstrual blood loss"
  (`kQuantityOfMenstrualBloodLossSnomed`) as the single question code,
  with the local flow-level `valueCodeableConcept`.
- Typical cycle length: SNOMED `161716008` "Usual length of menstrual
  cycle" (`cycleLengthCodes`), value in `d`.
- LMP: the standalone LOINC `8665-2` "Last menstrual period start date".
- BBT: LOINC `8310-5` + SNOMED `300076005`; weight: LOINC `29463-7`.
- Symptoms reuse `dualCodingFor` — a SNOMED CT finding coding plus the
  lunarlog local coding, or the local coding alone when no verified
  SNOMED match exists for that tag.

### Local codes introduced by this export

Concepts this file codes locally that `clinical_terminology.dart` does not
already cover. **#157 review fix:** flow levels moved to their own local
system, `kSystemLunarlogLocalFlow`
(`https://lunarlog.app/fhir/CodeSystem/flow`) — distinct
from `kSystemLunarlogLocal` (`.../CodeSystem/tag`), which
`clinical_terminology.dart` documents as specifically the 113-code tag
system. A flow level is not a tag, so it no longer shares that system's
URI; see `docs/clinical/terminology.md`'s "`FlowLevel`" section for both
URIs and why they're separate.

- **Flow level** (`light`/`medium`/`heavy`/`superHeavy`, as the
  `valueCodeableConcept` on a flow Observation; system
  `kSystemLunarlogLocalFlow`): no LOINC answer-list code was verified for
  lunarlog's flow scale, so each emitted level is its own local code, with
  `display` from `flowLabel` (the same human label `DaySheet`'s own flow
  chips use — moved into `lib/domain/models/flow_level.dart` so this
  pure-Dart builder can share it without importing a UI widget file).
  The emitted set is only the bleed levels (`isBleed`): `spotting` is a
  deprecated stored alias and is **never exported**; `none` and
  `notBleeding` are non-bleed and never exported. `superHeavy` **is**
  exported. **Stored value → emitted code:** `super_heavy` (the wire
  value on `day_entries.flow`) → the local code `superHeavy` (the Dart
  enum name, kept stable because it may already be in a customer's
  exported Bundle); `fhir_bundle_test.dart` pins this mapping.
- **Generic observation-row fallback** (`<category>:<code>`, e.g.
  `other:wearable_metric`; system `kSystemLunarlogLocal`): the
  `observations` table (issue #240) models roughly 200 Clue-style option
  codes, a much larger and looser vocabulary than the 113-tag taxonomy
  `dualCodingFor` covers. When a live symptom row's `code` is not one of
  those tags, this is the fallback — a local coding built directly from
  the row's own `category`/`code`, never a guessed clinical concept for a
  vocabulary that hasn't been verified yet. Its `display` is
  category-qualified (e.g. "Vaginal discharge: egg white") so the label is
  meaningful with no section heading (issue #1114).
- **`self-reported`** (`Provenance.activity`; system
  `kSystemLunarlogLocal` — still the tag system's URI, since a
  self-report marker is not a competing taxonomy the way flow levels
  are): see "Self-reported" above.
- **`intensity`** (Issue #612, LLA-088; the `component.code` when a row
  carries both a numeric value and a coded severity — see "`Observation`
  value shape" above; system `kSystemLunarlogLocal`): no verified
  LOINC/SNOMED code represents a bare "symptom intensity" axis
  independent of the concept it's rating, so this is an explicit local
  decision, the same treatment as `self-reported` above.

## Determinism

**Per-resource, not Bundle-wide (#157 review fix — the original claim of
"two calls produce byte-identical JSON" was true only because every
earlier test happened to hold `exportedAt` fixed, not because every
resource id is independent of it):**

- `Patient`, the flow-day `Observation`s, and the tag-derived symptom
  `Observation`s (see "Symptom Observations: two sources" above) are
  named from stable domain identity alone — `Profile.id`; `DayEntry.id`;
  `(profile.id, effectiveDateTime, tag)` — so two export runs of the same
  underlying data produce the *same* ids for these resources, run after
  run. **This is the intended behavior**: a system re-ingesting a second
  export of the same profile should update these same resources, not
  create duplicates of them.
- `Bundle`, `Composition`, `Provenance`, and the cycle-statistic
  Observations (typical cycle length, last menstrual period) are named
  from a key that bakes in `exportedAt` — these ids **change** across two
  calls with a different `exportedAt`, because each export run is its own
  new document assertion ("this export happened at this instant"), even
  though the underlying entities the flow/symptom Observations describe
  are not new.

Every `urn:uuid`, whichever group it falls into, still comes from UUID v5
(a stable hash of its name, never `Uuid.v4()` or wall-clock entropy) —
what varies between the two groups is only whether `exportedAt` is part
of the *name* being hashed. Two calls with the same `exportedAt` (and
everything else the same) still produce byte-identical `jsonEncode`
output end to end, since nothing else in this builder reads wall-clock
time or randomness.

## v1 scope and what a future pass would add

- **Date range (Issue #459).** `buildFhirDocumentBundle` is per-profile and
  takes whatever `dayEntries`/`observations` the caller passes in — a
  date-ranged export is a caller-side change, not a builder change.
  `ClinicalExportTile` now asks for a range (see
  `lib/ui/settings/export_range_picker_sheet.dart` and
  `lib/domain/export/fhir_export_range.dart`) after the profile choice and
  before the Bundle is built: presets for the last 3/6/12 completed
  cycles (derived via `lib/domain/episodes/episodes.dart`, the same
  episode model the history list and predictions use), the last 12
  months, everything, or a custom start/end — defaulting to the last 6
  completed cycles. Only the raw flow/symptom entries embedded in the
  document are narrowed to the chosen range; the cycle-length/last-
  menstrual-period statistics are always computed from the profile's full
  history, independent of the chosen range. (Profile *selection* itself —
  as opposed to date range — was already not v1-scoped-out: #157 review
  fix added a chooser for several live profiles, and archived profiles
  are excluded; see `lib/ui/settings/clinical_export_tile.dart`'s own doc
  comment.)
- **Validating against IPS.** Once the HL7 FHIR validator is run against
  this Bundle shape for a specific IPS package version and it passes,
  `meta.profile` can be added — see "IPS-shaped, not IPS-conformant"
  above.
- **Pregnancy/birth-control resources** (A3-47/A3-48): deferred until
  those resource builders exist, per the issue's own Assumptions.
  Birth-control intake rows are excluded from the Bundle meanwhile (see
  "Exclusion policy").
- **C-CDA output** (#161, CE-4): blocked on this issue per its
  Dependencies; not started.
