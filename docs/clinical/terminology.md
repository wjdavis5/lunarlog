# Clinical terminology mapping — LOINC/SNOMED

Issue #152 (epic: clinical-export). This is the verification pass A3-44
("commonly-cited menstrual-health LOINC codes" audit) and A3-45 (SNOMED
finding coding for the tag taxonomy) asked for: a small, explicitly-sourced
code table lunarlog's future FHIR export (#157) reads from, instead of
codes typed straight into a Bundle builder. The code lives in
[`lib/domain/export/clinical_terminology.dart`](../../lib/domain/export/clinical_terminology.dart);
this page is that file's provenance record.

**The rule everything below follows: no guessed codes.** A concept either
has a verified external code with a cited, fetched source, or it is
local-coded (the lunarlog local system below + a human-readable display)
and says so explicitly. Nothing here is "this is probably right."

## Code systems

| System | URI | Used for |
|---|---|---|
| LOINC | `http://loinc.org` | The *question* — what was measured or asked (menstrual status, cycle length, delivery date…). |
| SNOMED CT | `http://snomed.info/sct` | The *finding* — the symptom or observation itself (headache, nausea…). |
| lunarlog local | `https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/tag` | Concepts with no verified external mapping. An `http(s)://` URL under a domain lunarlog controls, not an unregistered `urn:` scheme (this system used `urn:lunarlog:code` until 2026-09-09) — FHIR only requires `Coding.system` to be a URI that uniquely identifies the scheme, but RFC 8141 requires `urn:` namespace identifiers to be formally registered, which `urn:lunarlog:code` never was; FHIR's own guidance for a locally-defined system is an `http(s)://` URL under a domain the publisher controls, which is what this string is even though no document is actually published at that address yet. **This string is permanent once #157 starts emitting FHIR Bundles** — changing it later would break every previously exported `Observation.code`. |

## LOINC code set (A3-44)

Originally a verbatim copy of #152's own audit table. **Re-verified
2026-09-09** against the HL7 FHIR terminology server's LOINC lookup
(`https://tx.fhir.org/r4/CodeSystem/$lookup?system=http://loinc.org&code=<code>`)
rather than trusted as a copy alone: all seven codes below, plus the
refuted `3141-9`, were checked against that server. Six matched the
original audit exactly; one (`64700-8`) had its display corrected — the
original text (`…days in a typical menstrual cycle [PhenX]`) was an
editorial elision from the issue body, not the code's actual LOINC
SHORTNAME, which the table below now uses verbatim.

### Verified — safe to use

| Code | Display | Source | Verified |
|---|---|---|---|
| `8665-2` | Last menstrual period start date | https://loinc.org/8665-2 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |
| `8678-5` | Menstrual status - Reported | https://loinc.org/8678-5 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |
| `3146-8` | Menstrual status | https://loinc.org/3146-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |
| `92656-8` | Number of menstrual periods per year | https://loinc.org/92656-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |
| `63888-2` | Age at first menstrual period | https://loinc.org/63888-2 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |
| `64700-8` | Menstrual cycle typical days PhenX | https://loinc.org/64700-8 | 2026-09 (#152 A3-44); display corrected 2026-09-09 (tx.fhir.org SHORTNAME) |
| `11778-8` | Delivery date Estimated | https://loinc.org/11778-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09 (tx.fhir.org) |

These are `kLoincCodes` in the Dart module — the list is exhaustive; a
test asserts it is exactly these seven codes.

### Refuted — never use

| Code | What it actually is | Source |
|---|---|---|
| `3141-9` | Body weight Measured — **not** a menstrual concept at all, despite being commonly cited as one | https://loinc.org/3141-9; re-verified 2026-09-09 (tx.fhir.org) |

### Unverified — do not use without independent verification

`49033-4`, `63871-7`, `21840-4`, `8708-3`, `3151-8` — these came up during
the audit but were not resolved to a verified menstrual concept. They are
not refuted (they may turn out fine), just not cleared for use yet.

`kRefutedLoincCodes` and `kUnverifiedLoincCodes` in the Dart module list
these codes; a test asserts neither list's codes are referenced by any
mapping row anywhere in this module.

## Tag taxonomy — SNOMED CT dual coding (A3-45)

`Observation.code` for a symptom finding conventionally carries SNOMED CT
(the finding), not LOINC (the question) — see A3-45 in the issue. Every
export of a lunarlog tag therefore carries **two** codings: the clinical
one (SNOMED, when verified) and the lunarlog local one, always, so an
importer can recover the exact original tag without reversing a clinical
code (`dualCodingFor` in the Dart module implements this).

All 86 codes in `lib/domain/tags.dart` are covered — 17 verified SNOMED
rows plus issue #249's 28, issue #251's 22, and issue #252's 19 explicit
local decisions (see the sections at the end of this document). Every
SNOMED
row was checked live against the HL7 FHIR terminology server
(`https://tx.fhir.org`, R4, SNOMED CT edition `900000000000207008`
version `20250201`) via its `CodeSystem/$lookup` operation, confirming
the concept is **active** and recording its preferred term. The exact
query URL used for each row is that row's `provenanceUrl` in the Dart
module.

### Pain

| lunarlog code | SNOMED concept | Term | Verified |
|---|---|---|---|
| `cramps` | `266599000` | Dysmenorrhea | active, tx.fhir.org, 2026-09 |
| `headache` | `25064002` | Headache | active, tx.fhir.org, 2026-09 |
| `back_pain` | `161891005` | Backache | active, tx.fhir.org, 2026-09 |
| `breast_tenderness` | `55222007` | Tenderness of breast | active, tx.fhir.org, 2026-09 |

`266599000` is a **disorder**-tier concept (`Dysmenorrhea (disorder)`),
not finding-tier — used anyway because SNOMED's own synonyms for it
include the plain self-reported terms "Menstrual cramps" and "Period
pain", so it is the standard clinical designation for the lunarlog
`cramps` tag itself, not an overreach into a distinct diagnosis.

### Body

| lunarlog code | SNOMED concept | Term | Verified |
|---|---|---|---|
| `bloating` | `116289008` | Abdominal bloating | active, tx.fhir.org, 2026-09 |
| `acne` | `11381005` | Acne | active, tx.fhir.org, 2026-09 |
| `nausea` | `422587007` | Nausea | active, tx.fhir.org, 2026-09 |
| `fatigue` | `84229001` | Fatigue | active, tx.fhir.org, 2026-09 |
| `dizziness` | `404640003` | Dizziness | active, tx.fhir.org, 2026-09 |

`11381005` is likewise a disorder-tier concept (`Acne (disorder)`) rather
than finding-tier — SNOMED has no separate finding-tier acne concept, and
"acne" is already the plain term for the skin symptom itself rather than
a distinct diagnosis, so using the disorder-tier code does not overstate
what the lunarlog `acne` tag means.

### Mood — local-coded (5 of 6; grouping dissolved by issue #251)

Per #152's own assumption, mood tags are expected to resolve to
"local-coded, no match" rather than be forced into a plausible-looking
SNOMED concept:

| lunarlog code | Decision | Why |
|---|---|---|
| `irritable` | local | Expected local per #152's assumption; no forced match. |
| `calm` | local | Expected local per #152's assumption; no forced match. |
| `energetic` | local | Expected local per #152's assumption; no forced match. |
| `sensitive` | local | Expected local per #152's assumption; no forced match. |
| `sad` | local | Not one of #152's four named mood tags, but checked anyway: the closest active SNOMED concept is `366979004` "Depressed mood" (confirmed active, tx.fhir.org, 2026-09). Rejected as a mapping — "Depressed mood" is a clinical-disorder-adjacent term and using it for lunarlog's plain self-reported "sad" tag would overstate every ordinary low-mood day as a depressive finding. This is the same "don't force a match" judgment #152 asks for the other four mood tags, applied to a fifth. |

The one mood tag that *did* get a verified match:

| lunarlog code | SNOMED concept | Term | Verified |
|---|---|---|---|
| `anxious` | `48694002` | Anxiety | active, tx.fhir.org, 2026-09 |

### Other

| lunarlog code | SNOMED concept | Term | Verified |
|---|---|---|---|
| `sleep_trouble` | `301345002` | Difficulty sleeping | active, tx.fhir.org, 2026-09 |
| `cravings` | `248132003` | Craving for food or drink | active, tx.fhir.org, 2026-09 |

## Local-code policy

A row is local-coded (`system:` the lunarlog local system above, `code`
= the lunarlog tag/concept code, `display` = its own UI label) whenever:

- No SNOMED/LOINC concept was found for it at all, or
- A concept was found but using it would overstate, understate, or
  otherwise misrepresent what the lunarlog concept actually means (the
  `sad` → "Depressed mood" case above), or
- The issue itself expects the concept to stay local (the four named
  mood tags).

A local row is still valid FHIR — `Coding.system` + `Coding.code` +
`Coding.display` — and is honest about being lunarlog's own vocabulary
rather than dressing it up as a clinical code it isn't.

## `FlowLevel` — stays fully local

`lib/domain/models/flow_level.dart`'s five values (`none`, `spotting`,
`light`, `medium`, `heavy`) were checked against SNOMED CT for a verified
flow-amount scale and none was found that fits without overreaching:

**System URI (#157 review fix, 2026-09-09):** flow levels are coded on
their own local system, `kSystemLunarlogLocalFlow`
(`https://github.com/wjdavis5/lunarlog/fhir/CodeSystem/flow`, defined in
`lib/domain/export/fhir_bundle.dart`) — **not** `kSystemLunarlogLocal`
(`.../CodeSystem/tag`, this file's own subject above). The two URIs exist
because they cover genuinely different concept spaces: `kSystemLunarlogLocal`
is specifically *the 17-code tag taxonomy* (`lib/domain/tags.dart`), and a
flow level was never one of those 17 codes — v1 of the FHIR export coded
it on the tag system anyway (an oversight, not a decision), which this
fix corrects. `Provenance.activity`'s `self-reported` marker (see
`docs/clinical/fhir-export.md`'s "Self-reported" section) stays on
`kSystemLunarlogLocal` — a self-report marker is a single fixed value, not
a competing taxonomy the way flow levels are, so splitting it out into
its own system would not buy the same clarity. Both systems' rows are
**permanent once emitted**, the same as `kSystemLunarlogLocal` itself —
neither is to be changed casually.

- The only close matches describe *abnormal* flow as a standalone
  concept, not a neutral descriptor of a given cycle day's flow amount —
  e.g. `64206003` **Hypomenorrhea (finding)** (abnormally light/scanty
  flow — finding-tier, not a diagnosis) and menorrhagia (heavy menstrual
  bleeding, a disorder-tier concept). Coding every "heavy" day entry with
  a bleeding-disorder concept, or every "light" day with an abnormal-flow
  finding, would misrepresent normal cycle variation as pathology, exactly
  the kind of wrong-but-plausible code #152 rules out.
- `9126005` "Menstrual spotting" was also checked and rejected for
  `spotting`: it specifically means *intermenstrual* bleeding (between
  periods), not the lightest flow intensity within a tracked period —
  a different clinical concept than lunarlog's `FlowLevel.spotting`.
- LOINC's own flow-amount code (commonly cited as `49033-4`) is in this
  issue's **unverified** list above and is not usable regardless.

`FlowLevel` therefore has no entry in `kTagClinicalCodes` (it is not a
tag-taxonomy code) and no dedicated `ClinicalCode` rows in the Dart
module; a future export of `FlowLevel` should emit a local coding only,
following the same policy as any other unmapped concept above.

## Deferred rows (blocked on #249/#260/#192)

The issue's own body reserves the shape for three more concept groups
that don't exist in lunarlog yet — this pass documents the intended
mapping now (per #152's own instructions) but ships no code for any of
them, since the underlying data doesn't exist on `main`:

### Basal body temperature (blocked on #144)

LOINC `8310-5` "Body temperature" is the standard vital-sign code US
Core / IPS vital-signs profiles expect, but on its own it understates
BBT as a distinct clinical concept (resting, first-waking). Once #144
ships BBT tracking, emit `8310-5` with a `bodySite`/method qualifier or
an additional local coding marking the reading as basal — do not invent
a BBT-specific LOINC code.

### Pregnancy + estimated due date (blocked on #131 pregnancy mode)

Pregnancy status is conventionally a `Condition` (or an `Observation` of
pregnancy status); estimated delivery date is an `Observation` using the
already-verified LOINC `11778-8` "Delivery date Estimated" (USCDI:
https://www.healthit.gov/isa/uscdi-data/estimated-date-delivery). This
mapping is already verified above — only the pregnancy-mode data model
is missing.

### Birth control (blocked on #260/#192, A3-9)

| Method shape | FHIR resource |
|---|---|
| Oral / patch / ring / injection (ongoing, patient-reported) | `MedicationStatement` |
| IUD / implant (device in situ) | `Device` / `DeviceUseStatement` |
| Insertion event | `Procedure` |

Not modeled as `Observation` for any of these — doing so would make the
export look machine-generated rather than clinically credible. No
specific medication/device codes are reserved here since #260/#192
haven't landed the method taxonomy this would key off of.

## Issue #249's expanded taxonomy — local decisions (2026-09)

Issue #249 grew `lib/domain/tags.dart` from 17 codes to 45 across 15
categories. Every new code is covered in `kTagClinicalCodes` by an
**explicit local decision** (system `kSystemLunarlogLocal`, code = the tag
code, display = the tag display): no SNOMED CT concept has been
fetch-verified for any of them yet, and the no-guessed-codes rule above
outranks the temptation to ship a plausible concept id. `dualCodingFor`
degrades each to its single local coding, which is valid FHIR and
round-trips exactly. Fetch-verify against `tx.fhir.org` — and promote the
rows that resolve cleanly (migraine, migraine with aura, ovulation pain,
diarrhea, constipation are the likely candidates) to verified SNOMED rows
in a follow-up pass, updating the Dart module and this table together.

New codes carrying local rows: `ovulation`, `migraine`,
`migraine_with_aura`, `pain_free`, `fully_energized`, `tired`,
`exhausted`, `0_to_3_hours`, `3_to_6_hours`, `6_to_9_hours`,
`9_or_more_hours`, `good_skin`, `oily_skin`, `dry_skin`, `good_hair`,
`bad_hair`, `oily_hair`, `dry_hair`, `gassy`, `great_digestion`,
`normal`, `constipated`, `great_stool`, `diarrhea`, `sweet`, `salty`,
`carbs`, `chocolate`. The 17 pre-existing rows (including `cravings`, now
filed under the cravings category as the legacy "unspecified craving"
member) are unchanged.

## Issue #251's feelings/mind/lifestyle taxonomy — local decisions (2026-09)

Issue #251 grew `lib/domain/tags.dart` from 45 codes to 67 across 22
categories, rebuilding the old `mood` grouping into `feelings`, `mind`,
`motivation`, `social_life`, and `partying` (plus the option-set-unverified
`pms`, `meditation`, and `leisure`). The same rule as #249's section above:
every new code gets an **explicit local decision**, no SNOMED CT concept
fetch-verified in this pass — `dualCodingFor` degrades each to its single
local coding, which is valid FHIR and round-trips exactly. Fetch-verify
against `tx.fhir.org` and promote clean resolves in the same follow-up
pass as #249's candidates.

The five re-parented codes (`irritable`, `sad`, `anxious`, `calm`,
`sensitive`) keep their existing rows — including `anxious`'s verified
SNOMED `48694002` "Anxiety" — untouched: re-parenting changes a code's
category, never its coding or its code string.

New codes carrying local rows: `happy`, `angry`, `indifferent`,
`mood_swings`, `excited`, `insecure`, `grateful` (feelings);
`distracted`, `focused`, `stressed` (mind); `motivated`, `unmotivated`,
`productive`, `unproductive` (motivation); `sociable`, `withdrawn`,
`supportive`, `conflict` (social life); `drinks`, `cigarettes`,
`big_night`, `hangover` (partying). The `pms`, `meditation`, and
`leisure` categories ship no codes yet (option sets unverified —
`kUnverifiedTagCategories`), so they add no rows here.

## Issue #252's events/care taxonomy — local decisions (2026-09)

Issue #252 grew `lib/domain/tags.dart` from 67 codes to 86 across 28
categories, adding `collection_method` (pad/tampon/panty_liner/
menstrual_cup), `exercise` (running/yoga/biking/swimming/walking/pilates/
rest_day), `medication` (pain/cold_flu_medication/antihistamine/
antibiotic), and `ailments` (cold_flu_ailments/allergy/injury/fever),
plus the option-set-unverified `appointments` and `supplements`. The same
rule as #249's and #251's sections above: every new code gets an
**explicit local decision**, no SNOMED CT concept fetch-verified in this
pass — `dualCodingFor` degrades each to its single local coding, which is
valid FHIR and round-trips exactly. Fetch-verify against `tx.fhir.org`
and promote clean resolves in the same follow-up pass as #249's/#251's
candidates (`fever`, `allergy`, and `injury` are the likeliest).

`cold/flu` is an attested option of BOTH the medication and ailments
categories, and the day-entry tag namespace is flat, so both instances
are category-qualified codes (`cold_flu_medication` /
`cold_flu_ailments`); medication's `pain` option keeps the attested code
`pain` with a qualified display ("Pain (medication)") so it never reads
as the Pain category. The `appointments` and `supplements` categories
ship no codes yet (option sets unverified — `kUnverifiedTagCategories`),
so they add no rows here.
