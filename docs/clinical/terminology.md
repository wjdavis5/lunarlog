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
| lunarlog local | `https://lunarlog.app/fhir/CodeSystem/tag` | Concepts with no verified external mapping. An `http(s)://` URL under a domain lunarlog controls, not an unregistered `urn:` scheme (this system used `urn:lunarlog:code` until 2026-09-09) — FHIR only requires `Coding.system` to be a URI that uniquely identifies the scheme, but RFC 8141 requires `urn:` namespace identifiers to be formally registered, which `urn:lunarlog:code` never was; FHIR's own guidance for a locally-defined system is an `http(s)://` URL under a domain the publisher controls, which is what this string is even though no document is actually published at that address yet. #961 moved the base to `lunarlog.app` from `https://github.com/wjdavis5/lunarlog/fhir/...` before the first store build shipped an export. **This string is frozen from the first shipped build and must never change** — a Bundle already handed to a clinician cannot be recalled, and changing it later would break every previously exported `Observation.code`. |

## LOINC code set (A3-44)

Originally a verbatim copy of #152's own audit table. **Re-verified
2026-09-09** against the HL7 FHIR terminology server's LOINC lookup
(`https://tx.fhir.org/r4/CodeSystem/$lookup?system=http://loinc.org&code=<code>`)
rather than trusted as a copy alone, and **independently re-verified
2026-09-26** (tx.fhir.org / CSIRO Ontoserver, LOINC 2.82) for #1116, which
corrected several claims below. The 2026-09-26 pass is the provenance
record for every correction in this section.

### Audited rows

These are the seven rows of `kLoincCodes` plus the standalone
`kEstimatedDeliveryDateLoinc` (`11779-6`). Note the **"Used by"** column:
`8678-5`, `3146-8`, `64700-8` and `11778-8` are retained here as the
audit record but are **no longer emitted** — the export now uses the
SNOMED/LOINC replacements named in each note (issues #1115/#1116).

| Code | Display | Source | Verified | Used by |
|---|---|---|---|---|
| `8665-2` | Last menstrual period start date | https://loinc.org/8665-2 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | LMP Observation |
| `8678-5` | Menstrual status - Reported | https://loinc.org/8678-5 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | **not emitted** — "Menstrual status" is the state of menstruation, not a day's flow amount; per-day flow now uses SNOMED `364308001` |
| `3146-8` | Menstrual status | https://loinc.org/3146-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | **not emitted** — see `8678-5` |
| `92656-8` | Number of menstrual periods per year | https://loinc.org/92656-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | reserved, not emitted |
| `63888-2` | Age at first menstrual period | https://loinc.org/63888-2 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | reserved, not emitted |
| `64700-8` | Menstrual cycle typical days PhenX | https://loinc.org/64700-8 | 2026-09 (#152 A3-44); display corrected 2026-09-09 (tx.fhir.org SHORTNAME) | **not emitted** — **TRIAL status**, an ordinal PhenX survey question with a required band answer list (LL1227-9); cycle length now uses SNOMED `161716008` |
| `11778-8` | Delivery date Estimated | https://loinc.org/11778-8 | 2026-09 (#152 A3-44); re-verified 2026-09-09, 2026-09-26 | **not emitted** — means a due date a *practitioner selected*; an LMP-derived date uses `11779-6` |
| `11779-6` | Delivery date Estimated from last menstrual period | https://loinc.org/11779-6 | 2026-09-26 (tx.fhir.org) | estimated delivery date (reserved shape) |

### Refuted — never use

| Code | What it actually is | Source |
|---|---|---|
| `3141-9` | Body weight Measured — **not** a menstrual concept at all, despite being commonly cited as one | https://loinc.org/3141-9; re-verified 2026-09-09 (tx.fhir.org) |
| `49033-4` | Menstrual History - Reported — **not** a flow-amount code, despite being cited as one | 2026-09-26 (tx.fhir.org / CSIRO Ontoserver) |
| `21840-4` | Sex [NAACCR] — a cancer-registry field, unrelated to menstrual health | 2026-09-26 (tx.fhir.org / CSIRO Ontoserver) |
| `3151-8` | Inhaled oxygen flow rate — unrelated to menstrual health | 2026-09-26 (tx.fhir.org / CSIRO Ontoserver) |

### Unverified — do not use without independent verification

**Empty as of 2026-09-26.** The codes #152 left unresolved are now all
placed: `63871-7` and `8708-3` **do not exist** (both fail the LOINC mod-10
check digit and are absent from LOINC 2.82), and `49033-4`, `21840-4` and
`3151-8` were resolved to unrelated concepts and moved to the refuted table
above. `kUnverifiedLoincCodes` in the Dart module is therefore empty; a
test asserts that.

## Tag taxonomy — SNOMED CT dual coding (A3-45)

`Observation.code` for a symptom finding conventionally carries SNOMED CT
(the finding), not LOINC (the question) — see A3-45 in the issue. Every
export of a lunarlog tag therefore carries **two** codings: the clinical
one (SNOMED, when verified) and the lunarlog local one, always, so an
importer can recover the exact original tag without reversing a clinical
code (`dualCodingFor` in the Dart module implements this).

All 113 codes in `lib/domain/tags.dart` are covered — 12 verified SNOMED
rows plus issue #249's 28, issue #251's 22, issue #252's 19, issue
#253's 22, and issue #456's 5 explicit local decisions (see the sections
at the end of this document). Every SNOMED
row was checked live against the HL7 FHIR terminology server
(`https://tx.fhir.org`, R4, SNOMED CT edition `900000000000207008`
version `20250201`) via its `CodeSystem/$lookup` operation, confirming
the concept is **active** and recording its preferred term. The exact
query URL used for each row is that row's `provenanceUrl` in the Dart
module.

**Grown-taxonomy policy (binding, from #152's "no guessed codes"
rule):** #152 was written against a 17-tag taxonomy; the taxonomy has
since grown to 113. Every code added after #152 gets either a
fetch-verified external concept or an **explicit local decision** —
never a guess. Since no verification pass has been run for the
post-#152 additions, the default decision for each is explicit local
coding (lunarlog system URI + the tag's own human-readable display):
honest, valid FHIR, and round-trippable, with promotion to a verified
SNOMED row as follow-up work. A Dart test enumerates `kTagTaxonomy` and
fails if a new tag lands without a row in `kTagClinicalCodes`, so the
"every code has a decision" guarantee cannot silently rot as the
taxonomy grows.

### Pain

| lunarlog code | SNOMED concept | Term | Verified |
|---|---|---|---|
| `cramps` | `431416001` | Menstrual cramp | active, tx.fhir.org, 2026-09-26 |
| `headache` | `25064002` | Headache | active, tx.fhir.org, 2026-09 |
| `back_pain` | `161891005` | Backache | active, tx.fhir.org, 2026-09 |
| `breast_tenderness` | `53430007` | Pain of breast | active, tx.fhir.org, 2026-09-26 |

**Correction (issue #1114, re-verified 2026-09-26):** `cramps` previously
mapped to `266599000 "Dysmenorrhea (disorder)"`. That is a *disorder*-tier
concept emitted for every logged cramp day inside the IPS "Problem list -
Reported" section, which a receiving EHR could import as a diagnosis the
patient was never given. It now maps to the *finding*-tier `431416001
"Menstrual cramp (finding)"`, active since 2008. Likewise
`breast_tenderness` previously mapped to `55222007 "Tenderness of breast"`,
a sign a clinician finds by examination; the patient-reported symptom is
`53430007 "Pain of breast (finding)"`, which is what the tag actually is.
The generic "Cramps" tag is not distinguished by cycle phase at export
time; it is always emitted as the symptom-level concept, never the
disorder.

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

## `FlowLevel` — the *question* is SNOMED, the *values* stay local

`lib/domain/models/flow_level.dart` has **seven** values — `none`,
`spotting`, `notBleeding`, `light`, `medium`, `heavy`, `superHeavy`
(`spotting` is a deprecated alias for already-stored pre-#247 data, is
never written going forward, and **never exported**; `notBleeding` and
`none` are both non-bleed values and are never exported either — see
`isBleed`). The earlier "five values" list here was stale (issue #1116).

**The question code (issue #1115, re-verified 2026-09-26):** a per-day
flow `Observation` is coded with the single SNOMED concept `364308001
"Quantity of menstrual blood loss (observable entity)"`. The previous two
LOINC codings (`8678-5`, `3146-8`) both mean "Menstrual status" — the
state of menstruation, not how much blood was lost that day — and FHIR
treats two codings in one `CodeableConcept` as translations of one
concept, which they are not.

The *values* stay local on their own system, `kSystemLunarlogLocalFlow`
(`https://lunarlog.app/fhir/CodeSystem/flow`, defined in
`lib/domain/export/fhir_bundle.dart`) — **not** `kSystemLunarlogLocal`
(`.../CodeSystem/tag`, this file's own subject above). The two URIs exist
because they cover genuinely different concept spaces: `kSystemLunarlogLocal`
is specifically *the 113-code tag taxonomy* (`lib/domain/tags.dart`), and a
flow level was never one of those codes — v1 of the FHIR export coded it
on the tag system anyway (an oversight, not a decision), corrected by the
#157 review fix. `Provenance.activity`'s `self-reported` marker (see
`docs/clinical/fhir-export.md`'s "Self-reported" section) stays on
`kSystemLunarlogLocal` — a self-report marker is a single fixed value, not
a competing taxonomy the way flow levels are, so splitting it out into
its own system would not buy the same clarity. Both systems' rows are
**permanent once emitted**, the same as `kSystemLunarlogLocal` itself —
neither is to be changed casually.

The emitted `FlowLevel` local codes are the Dart enum names
(`light`/`medium`/`heavy`/`superHeavy`), while the *stored* value for the
heaviest level is `super_heavy`. The export deliberately keeps emitting
`superHeavy` (an existing local code value that may already be in a
customer's exported Bundle); `docs/clinical/fhir-export.md` records the
mapping and `fhir_bundle_test.dart` pins it.

Why the values are local, and why the earlier "no matching concept"
reasoning was itself partly wrong (issue #1116, re-verified 2026-09-26):

- `386692008` Menorrhagia is a **finding**, not a disorder (the earlier
  text called it disorder-tier); `308550003 "Normal menstrual blood loss"`
  also exists. Neither is a neutral descriptor of a *given day's* flow
  amount, so neither was adopted as a value coding.
- The exact question concept exists: `364308001`, now used as the
  `Observation.code` above.
- `9126005` is `"Menstrual spotting (finding)"`. It does **not** mean
  *intermenstrual* bleeding — that is `237130006` (the earlier claim was
  wrong).
- The code commonly cited as LOINC's flow-amount code is `49033-4`, which
  is actually `"Menstrual History - Reported"`; it is in the **refuted**
  table above and not usable.

`FlowLevel` therefore has no entry in `kTagClinicalCodes` (it is not a
tag-taxonomy code); its `Observation.code` is SNOMED `364308001` and each
emitted value is a local `kSystemLunarlogLocalFlow` coding, following the
same no-guessed-codes policy as any other unmapped concept above.

## Reserved rows (shape decisions recorded ahead of the builder)

The issue's own body reserves the shape for three more concept groups.
Per #152 AC, these decisions are documented **in the code-table module
itself** (`clinical_terminology.dart`'s "Reserved shapes" library doc plus
`kBodyTemperatureLoinc`/`kBasalBodyTemperatureSnomed`/`kBodyWeightLoinc`,
`estimatedDeliveryDateCode`, and `kBirthControlResourceShapes`), pinned by
tests; this section is their prose record. The underlying tracking
features have all landed since #152 was written — BBT observation logging
(#144 — `observations` rows with `category: 'bbt'`, consumed by
`lib/domain/insights/bbt_chart.dart`, #245), #188's pregnancy lifecycle
mode, and #260's birth-control model (`lib/domain/birth_control.dart`).
**BBT and weight are now emitted (issue #1115)**; pregnancy/due-date and
birth-control resource shapes remain reserved but unemitted. Birth-control
intake rows are deliberately **not** exported as Observations at all — see
`docs/clinical/fhir-export.md`.

### Basal body temperature (emitted as a vital sign, issue #1115)

LOINC `8310-5` "Body temperature" (https://loinc.org/8310-5) is the
standard vital-sign code US Core / IPS vital-signs profiles expect, but on
its own it understates BBT as a distinct clinical concept (resting,
first-waking). The builder therefore emits it — reserved as
`kBodyTemperatureLoinc`, deliberately **not** in `kLoincCodes` (that table
is exactly the A3-44 menstrual question seven) — **paired with** SNOMED
`300076005` "Basal body temperature" (`kBasalBodyTemperatureSnomed`, active
since 2002, verified against tx.fhir.org 2026-09-26), rather than a
`bodySite` qualifier or an invented BBT-specific LOINC code. The pair lands
in the IPS **Vital Signs** section (LOINC `8716-3`); weight uses LOINC
`29463-7` "Body weight" in the same section.

### Pregnancy + estimated due date (mode landed; no due-date data yet)

Pregnancy status is conventionally a `Condition` (or an `Observation` of
pregnancy status); estimated delivery date is an `Observation` using LOINC
`11779-6` "Delivery date Estimated from last menstrual period"
(`kEstimatedDeliveryDateLoinc`, verified against tx.fhir.org 2026-09-26;
USCDI lists it as a **Level 0** submission, not "included in USCDI" as an
earlier note overstated:
https://www.healthit.gov/isa/uscdi-data/estimated-date-delivery). The
previously reserved `11778-8` means a date a *practitioner selected*, so it
must not be used for an app-calculated, LMP-derived date. #188's lifecycle
modes carry a pregnancy *mode*, but no pregnancy-status or due-date data
model exists yet — only the shape is reserved.

### Birth control (model landed; builder emission pending, A3-9/#260)

| Method shape | FHIR resource |
|---|---|
| Oral / patch / ring / injection (ongoing, patient-reported) | `MedicationStatement` |
| IUD / implant (device in situ) | `Device` / `DeviceUseStatement` |
| Insertion event | `Procedure` |

Reserved as `kBirthControlResourceShapes` in the Dart module. Not
modeled as `Observation` for any of these — doing so would make the
export look machine-generated rather than clinically credible. No
specific medication/device codes are reserved since none has been
verified against an external system. The per-day `birth_control_*` intake
rows (#260) are therefore **not emitted at all** today (issue #1115): an
intake row is not an `Observation`, and no `MedicationStatement`/`Device`
builder exists yet, so it is deliberately absent rather than exported
under a wrong resource type. See `docs/clinical/fhir-export.md`.

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

## Issue #253's sensitive/fertility taxonomy — local decisions (2026-09)

Issue #253 grew `lib/domain/tags.dart` from 86 codes to 108 across 31
categories, adding `sex_life` (12 codes), `discharge` (5), and `tests`
(5). The same rule as every section above: each new code gets an
**explicit local decision**, no SNOMED CT concept fetch-verified in this
pass — `dualCodingFor` degrades each to its single local coding, which
is valid FHIR and round-trips exactly. Fetch-verify against
`tx.fhir.org` and promote clean resolves in the same follow-up pass as
the earlier sections' candidates.

New codes carrying local rows: `no_sex_today`, `low_sex_drive`,
`high_sex_drive`, `masturbation`, `withdrawal`, `protected_sex`,
`unprotected_sex`, `sex_toys`, `orgasm`, `no_orgasm`, `fantasies`,
`painful_intercourse` (sex_life); `none`, `sticky`, `creamy`,
`egg_white`, `atypical` (discharge); `ovulation_negative`,
`ovulation_positive`, `ovulation_peak`, `pregnancy_negative`,
`pregnancy_positive` (tests — deliberately local: these are self-read
home-test results, and coding them as clinical laboratory findings
would overstate what a self-reported test strip log entry is).

## Issue #456's `hot_flashes` taxonomy — local decisions (2026-09)

Issue #249 added `hot_flashes` as a top-level category with no attested
option set (Clue's own category is named "Hot flashes/perimenopause" —
`docs/import/clue-mapping.md`'s "no export type" list). Issue #456 adds
five codes to it: `hot_flashes`, `night_sweats`, `brain_fog`, `hrt`, and
`vaginal_dryness`. Same rule as every section above: no SNOMED CT
concept fetch-verified in this pass, so each is an explicit local
decision.

**Attestation gap, recorded rather than papered over:** Clue's own
support/marketing copy says Clue Perimenopause shipped "14 brand-new
tracking options ... such as hot flashes, night sweats, brain fog, HRT
and vaginal dryness" (`helloclue.com/articles/menopause/introducing-clue-
perimenopause`; `support.helloclue.com/hc/en-us/articles/
13059487439261`, which returned HTTP 403 to this pass's fetcher). Only
those five are named in any source this pass could reach — the remaining
~9 of the 14 are not enumerated anywhere publicly accessible found
during this pass. Per this file's own no-guessed-codes rule (and the
`kUnverifiedTagCategories` precedent above), the other ~9 are **not**
invented; `hot_flashes` ships with only the five attested codes and can
grow the same way `collection_method`/`exercise` did once a real Clue
export or an accessible copy of the support article pins the rest.
