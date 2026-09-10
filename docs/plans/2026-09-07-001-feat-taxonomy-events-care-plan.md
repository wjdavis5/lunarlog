# Plan — Built-in taxonomy: events and care categories (Issue #252)

Date: 2026-09-07 · Branch: `claude-orch/252-taxonomy-events-care` · Epic: Tracking Model (P1)

## Context

Issue #252 asks for Clue's events-and-care categories: `collection_method`,
`exercise`, `appointments`, `medication`, `ailments`, and `supplements`.
Today none of them exist in `lib/domain/tags.dart` (67 codes / 22
categories after #249 and #251).

Dependencies are landed: #240 (the free-text `observations` table —
`category`/`code` never a closed set, unknown-never-drop, `observed_at`
already a nullable column), #249 and #251 (the structural patterns this
issue repeats: re-parenting never renaming, the
`kUnverifiedTagCategories` caption pattern, the no-guessed-codes
local-decision rule). The importer's `kClueTypeMap` already maps the
`collection_method`/`exercise`/`appointments`/`medication`/`ailments`
export types onto same-named observation categories as pass-throughs —
what is missing is the client-side taxonomy (enum, picker codes, care-mode
headings, terminology). #251 (feelings/mind/lifestyle) just merged; its
categories are untouched here. #259's curation and #253's sex-life stay
out of scope; their seams are intact.

## Key decisions

- **Four categories get their attested option sets as real picker codes:**
  `collection_method` (`pad`, `tampon`, `panty_liner`, `menstrual_cup` —
  the four documented options; period underwear stays out, "widely
  reported but unverified"), `exercise` (`running`, `yoga`, `biking`,
  `swimming` legacy + `walking`, `pilates`, `rest_day` redesign — all 7),
  `medication` (`pain`, `cold_flu_medication`, `antihistamine`,
  `antibiotic`), `ailments` (`cold_flu_ailments`, `allergy`, `injury`,
  `fever`). Multi-select per day is inherent to the day-entry tag
  namespace — nothing to build.
- **`cold/flu` collides across medication and ailments in the flat
  day-entry tag namespace, so both instances are category-qualified** —
  the exact `great_digestion`/`great_stool` pattern (#249: qualify with
  the category name rather than rename away from the attested option; the
  raw export string is never the code's problem alone, the importer's
  option map renames it). Codes: `cold_flu_medication` /
  `cold_flu_ailments`; displays: "Cold/flu (medication)" /
  "Cold/flu (ailments)". Both documented spellings (`cold/flu` and
  `cold_flu`) map to the same code, the `nauseous`/`nauseated` → `nausea`
  tolerance pattern. Medication's `pain` option keeps the attested code
  `pain` but its display is qualified to "Pain (medication)" — the
  `cravings` → "Cravings (unspecified)" precedent: an unqualified "Pain"
  chip would collide textually with the Pain category heading in tests
  and read ambiguously in heading-less flat contexts (calendar layer
  panel).
- **`appointments` and `supplements` join `kUnverifiedTagCategories`
  with zero codes** (option strings unverified / not publicly
  enumerated): the day sheet renders the existing "unverified — pin
  before shipping" ARB caption, never an invented option. The enum grows
  to 28; the unverified set to 10.
- **Single-event seam (the `occurred_at`/exclusion AC):**
  `observations.observed_at` already exists (#240) and is nullable, so an
  appointments observation can carry an exact time today — pinned with a
  storage round-trip test. The aggregation half ships as the taxonomy
  seam the issue describes: `kSingleEventTagCategories`
  (`appointments`, `medication`, `ailments` — the issue's own single-event
  list, birth control excluded since #260 owns its own model), documented
  for the Predictions & Insights epic's consuming code, which is **not**
  built here per the AC's own parenthetical.
- **Collection method extensibility:** the fifth option (period
  underwear) needs no schema change by design — `observations.code` is
  free text (unknown-never-drop) and the taxonomy is a data list; adding
  `period_underwear` later is a one-line data addition. Documented on the
  category, no placeholder code shipped.
- **Importer**: `medication` and `ailments` type specs gain the `cold/flu`
  and `cold_flu` rename options; `collection_method`/`exercise`/
  `appointments` stay pass-through (their options now match taxonomy
  codes option-for-option, or — appointments — pass verbatim until a real
  export pins the strings). `supplements` gets **no** `kClueTypeMap`
  entry: no source attests a `supplements` export type at all (it stays
  on the mapping doc's "no export type" list, now noted as a taxonomy
  category); an export that ever carries one escapes to the
  `ClueUnknownDatapoint` hatch losslessly until pinned.
- **Clinical terminology**: all 19 new codes get explicit local decisions
  in `kTagClinicalCodes` (67 → 86; no guessed SNOMED — the #249/#251 rule
  verbatim); `terminology.md` documents the section and the follow-up
  fetch-verify pass.
- **Care modes (#131 seam)**: every mode's `categoriesInOrder` stays a
  full permutation of `TagCategory.values` (28); the six new categories
  append after `partying` in enum order (teen appends them at the end of
  its explicit reorder). Headings are care-mode label literals per the
  #131/#249/#251 pattern; the only user-facing string is the existing
  `daySheetUnverifiedPin` ARB caption — no new ARB keys.
- **`dizziness` is untouched** — it stays the lunarlog-only body code the
  issue says it is.

## Implementation units

- **U1 — taxonomy** (`lib/domain/tags.dart`): 6 new enum values, 19 new
  codes, `kUnverifiedTagCategories` + `appointments`/`supplements`,
  `kSingleEventTagCategories`, library doc comment update (counts,
  #252 rules).
- **U2 — care modes** (`lib/domain/care_modes.dart`): 6 labels per mode;
  teen order grows to the full 28-permutation.
- **U3 — importer** (`lib/domain/import/clue/clue_option_map.dart`,
  `docs/import/clue-mapping.md`, `test/fixtures/clue/mapping_table.json`
  unchanged): medication/ailments rename options + comments; doc table
  rows for medication/ailments/collection_method/exercise/appointments;
  supplements note on the no-export-type list.
- **U4 — terminology** (`lib/domain/export/clinical_terminology.dart`,
  `docs/clinical/terminology.md`): 19 local-decision rows + doc section +
  count updates (67 → 86).
- **U5 — tests**: `tags_test.dart` (counts 86/28, per-category sets,
  unverified set of 10, single-event set, collision-qualified displays,
  vocabulary guard untouched), `care_modes_test.dart` (six categories
  surfaced in every mode; permutation holds at 28), `logging_test.dart`
  (86 chips + 2 toggles, 28 headings, 10 unverified captions, teen
  totals), `clinical_terminology_test.dart` (golden table + counts),
  `clue_option_map_test.dart` (the cold/flu rename specs),
  `clue_export_parser_test.dart` (fixture expectation for the ailments
  rename + a #252 synthetic-input test: both `cold/flu` spellings, plus
  collection-method/exercise pass-throughs),
  `storage_observations_test.dart` (appointments + `observed_at`
  round-trip), `db_test.dart` comment refresh.

## Acceptance criteria (issue ACs → where proven)

- All six categories exist as observations categories with the stated
  option sets (or the unverified caption for `appointments`' exact
  strings and all of `supplements`) → `tags_test.dart` + day-sheet
  caption test + importer specs.
- `appointments` observations can carry a non-null `observed_at` →
  existing #240 column, pinned by a storage round-trip test; excludable
  from trend/insights aggregation **by category** → the
  `kSingleEventTagCategories` seam + docs; the consuming aggregation code
  is the Predictions & Insights epic's and is deliberately not built here
  (the AC's own parenthetical) — stated in the PR body.
- `dizziness` unaffected → unchanged in `tags.dart`; `tags_test.dart`
  body-category pin still passes.
- Medication and ailments multi-select per day → inherent to the
  day-entry tag namespace (chip grid is multi-select); pinned implicitly
  by the tags round-trip tests.

## Verification

`export PATH="/c/src/flutter/bin:$PATH"`, `flutter pub get`,
`flutter analyze`, `flutter test`, `dart run tool/quality_gate.dart` —
all before the PR.
