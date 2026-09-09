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
   already follows, just at the document level. Two sections:
   - **Results** (LOINC `30954-2`) — the menstrual-status Observations
     (one per day entry that is a bleed day — see `isBleed` below) and,
     when available, the two cycle-statistic Observations derived from
     `ActivePrediction`.
   - **Problems** (LOINC `11450-4`) — the self-reported symptom
     Observations: one per live (non-excluded) `observations` table row,
     plus one per tag per day entry from `DayEntry.tags` (see "Symptom
     Observations: two sources" below). These are FHIR `Observation`
     findings, not `Condition` diagnoses: IPS's Problems section normally
     expects Conditions, and this export deliberately never asserts a
     self-reported symptom log as a diagnosed condition. Problems was
     still the closer semantic fit of the two IPS sections for a symptom
     finding, so that is where it went, with this caveat recorded rather
     than silently choosing a wrong-but-quieter section.
   Each section carries a minimal generated narrative (`text.div`) — a
   count and a fixed sentence, never raw entry content, so the narrative
   itself never discloses anything the coded Observations don't already
   carry — and, when it has no entries at all, an `emptyReason` (coded
   `unavailable` on the FHIR core `list-empty-reason` CodeSystem) instead
   of a bare empty `entry` array.
2. **Patient** — see below.
3. **Observation** entries — flow-day, symptom, and (if present)
   cycle-statistic.
4. **Provenance** — exactly one per Bundle.

## Symptom Observations: two sources (#157 review fix)

Early v1 read only the `observations` table (Issue #240's per-option-row
child table) for symptom findings — but nothing in production actually
writes that table yet, so every tagged symptom (`DayEntry.tags`, the
app's real symptom-logging surface) was silently missing from the export.
The Problems section now emits from **both**:

- One `Observation` per live (`excluded == false`) `observations` row,
  dual-coded via `dualCodingFor` (or the local fallback — see "Coding
  discipline" below).
- One `Observation` per tag per day entry, from `DayEntry.tags`, also
  dual-coded via `dualCodingFor` — **except** when a live `observations`
  row already carries the same `(effectiveDateTime, code)` pair, so a
  symptom captured both ways is never emitted twice. An `observations`
  row with `excluded == true` does *not* count for this dedupe check
  (see "Exclusion policy" below) — an excluded row means there is
  nothing there to have already captured that symptom.

Each tag-derived Observation's id is a deterministic UUID v5 hash of
`(profile.id, effectiveDateTime, tag)` — stable across two export runs of
the same day entry, the same guarantee the flow-day and `observations`-row
Observations already had (see "Determinism" below).

## `Observation` value shape (#157 review fix)

A symptom `Observation` (from either source above) carries, when present
on the underlying row:

- `intensity` → `valueInteger`.
- `valueNum` + `unit` → `valueQuantity`. `unit` carries the UCUM code
  (`system: http://unitsofmeasure.org`, `code`) for the closed unit set
  `Observation.unit` documents today (`celsius`→`Cel`,
  `fahrenheit`→`[degF]`, `kg`→`kg`, `lb`→`[lb_av]`); an unrecognised unit
  degrades to a plain `unit` display string with no `system`/`code` —
  still valid FHIR, never a guessed UCUM code.
- `valueText` is **never** emitted, under any circumstance — see
  "Exclusion policy" below.

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

Every clinical `Observation` and the `Provenance` itself mark the data as
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

## IPS-shaped, not IPS-conformant

Modeled on the [International Patient Summary](https://hl7.org/fhir/uv/ips/)
(IG v2.0.0, FHIR R4) — a Composition-led document with Results/Problems
sections — but **no `Bundle.meta.profile` or `Composition.meta.profile` is
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
- Pregnancy/birth-control resource mapping is out of scope (per the
  issue's own Assumptions) until those tracking features exist —
  `clinical_terminology.dart` already reserves the shape for that.
- **`DayEntry.note` (#157 review fix)** is never read by `fhir_bundle.dart`
  at all — no function in that file even accepts it as a parameter, so
  there is no code path that could leak it into the export. Free-text a
  guardian typed into a day's note field is exactly the kind of content
  this export must never carry off-device.
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
`https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/export-version`,
`code` the current `kFhirExportBundleVersion` (`1` as of this writing). A
future change to this file's mapping bumps that constant so a downstream
consumer (or a person comparing two exports) can tell the shapes apart.

## Coding discipline: no guessed codes

Every `Observation.code` / `valueCodeableConcept` coding comes from
[`clinical_terminology.dart`](../../lib/domain/export/clinical_terminology.dart)'s
verified table (issue #152) or an explicit local coding on lunarlog's own
system (`kSystemLunarlogLocal`,
`https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag`) with a
documented reason — never a code typed from memory. `fhir_bundle.dart`
itself adds three more verified LOINC codes and one verified HL7
terminology code that `clinical_terminology.dart` does not carry, because
they are Composition/section/Provenance-level, not `Observation.code`, so
they don't belong in that file's exhaustively-tested `kLoincCodes` list:

| Code | System | Display | Used for | Verified |
|---|---|---|---|---|
| `60591-5` | LOINC | Patient summary Document | `Composition.type` | `tx.fhir.org` $lookup, 2026-09-09 |
| `30954-2` | LOINC | Relevant diagnostic tests/laboratory data note | Results section `.code` | `tx.fhir.org` $lookup, 2026-09-09 |
| `11450-4` | LOINC | Problem list - Reported | Problems section `.code` | `tx.fhir.org` $lookup, 2026-09-09 |
| `author` | `http://terminology.hl7.org/CodeSystem/provenance-participant-type` | Author | `Provenance.agent.type` | `tx.fhir.org` $lookup, 2026-09-09 |

Menstrual-status and cycle-statistic Observations reuse
`clinical_terminology.dart`'s `menstrualStatusCodes` (`8678-5`, `3146-8`)
and `cycleLengthCodes` (`64700-8`), plus the standalone verified LOINC
`8665-2` ("Last menstrual period start date") for the last-menstrual-period
Observation. Symptom Observations reuse `dualCodingFor` — a SNOMED CT
finding coding plus the lunarlog local coding, or the local coding alone
when no verified SNOMED match exists for that tag.

### Local codes introduced by this export

Concepts this file codes locally that `clinical_terminology.dart` does not
already cover. **#157 review fix:** flow levels moved to their own local
system, `kSystemLunarlogLocalFlow`
(`https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/flow`) — distinct
from `kSystemLunarlogLocal` (`.../CodeSystem/tag`), which
`clinical_terminology.dart` documents as specifically the 17-tag system.
A flow level is not a tag, so it no longer shares that system's URI; see
`docs/clinical/terminology.md`'s "FlowLevel — stays fully local" section
for both URIs and why they're separate.

- **Flow level** (`spotting`/`light`/`medium`/`heavy`, as the
  `valueCodeableConcept` on a menstrual-status Observation; system
  `kSystemLunarlogLocalFlow`): no LOINC answer-list code was verified for
  lunarlog's specific five-level flow scale, so each level is its own
  local code, `display` from `flowLabel` (the same human label
  `DaySheet`'s own flow chips use — moved into
  `lib/domain/models/flow_level.dart` so this pure-Dart builder can share
  it without importing a UI widget file).
- **Generic observation-row fallback** (`<category>:<code>`, e.g.
  `bbt:reading`; system `kSystemLunarlogLocal`): the `observations` table
  (issue #240) models roughly 200 Clue-style option codes, a much larger
  and looser vocabulary than the 17-tag taxonomy `dualCodingFor` covers.
  When an observation row's `code` is not one of those 17 tags, this is
  the fallback — a local coding built directly from the row's own
  `category`/`code`, never a guessed clinical concept for a vocabulary
  that hasn't been verified yet.
- **`self-reported`** (`Provenance.activity`; system
  `kSystemLunarlogLocal` — still the tag system's URI, since a
  self-report marker is not a competing taxonomy the way flow levels
  are): see "Self-reported" above.

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

- **No date range yet.** `buildFhirDocumentBundle` is already per-profile
  and takes whatever `dayEntries`/`observations` the caller passes in, so
  a date-ranged export is a caller-side change, not a builder change —
  but `ClinicalExportTile` (the UI) always passes the profile's whole
  history today, with no range UI. That is the next piece of this epic's
  UI work, not this issue's scope. (Profile *selection* itself — as
  opposed to date range — is no longer v1-scoped-out: #157 review fix
  added a chooser for several live profiles, and archived profiles are
  excluded; see `lib/ui/settings/clinical_export_tile.dart`'s own doc
  comment.)
- **Validating against IPS.** Once the HL7 FHIR validator is run against
  this Bundle shape for a specific IPS package version and it passes,
  `meta.profile` can be added — see "IPS-shaped, not IPS-conformant"
  above.
- **Pregnancy/birth-control resources** (A3-47/A3-48): deferred until
  those tracking features exist, per the issue's own Assumptions.
- **C-CDA output** (#161, CE-4): blocked on this issue per its
  Dependencies; not started.
