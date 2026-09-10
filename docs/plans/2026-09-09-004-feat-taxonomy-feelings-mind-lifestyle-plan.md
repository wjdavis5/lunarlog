# Plan — Built-in taxonomy: feelings, mind, and lifestyle (Issue #251)

Date: 2026-09-09 · Branch: `feat/251-taxonomy-mind` · Epic: Tracking Model (TM-4b, P1)

## Context

Issue #251 asks for Clue's feelings/mind/lifestyle categories: `feelings`,
`pms`, `mind`, `motivation`, `meditation`, `social_life`, `leisure`, and
`partying`. Today the mood vocabulary is 5 codes filed under one generic
`mood` category (`irritable`, `sad`, `anxious`, `calm`, `sensitive`).

Dependencies are landed: #240 (the free-text `observations` table —
`category`/`code` are never a closed set, unknown-never-drop), and #249
(the structural expansion whose patterns this issue repeats: re-parenting
never renaming, the `kUnverifiedTagCategories` caption pattern, the
no-guessed-codes local-decision rule). #220 landed first-class PMS
presence (`day_entries.pms` + its own day-sheet chip) while the taxonomy
issues were still open, and its plan explicitly left the taxonomy-shaped
PMS entity to this issue. #253 (sex life) and #259 (per-profile tracking
preferences) are still open — this issue touches neither's scope beyond
keeping their seams intact.

## Key decisions

- **`mood` is rebuilt, not extended.** Every `mood` code survives with its
  exact string (code-stability rule); only its category changes:
  `sad`/`anxious`/`sensitive`/`irritable` re-parent to `feelings`
  (`irritable` stays as the lunarlog-specific extra the issue names —
  no Clue equivalent, never dropped), `calm` re-parents to `mind`.
  `energetic` already moved to `energy` (#249). With nothing left, the
  `mood` enum value is removed — a zero-code category that is *not*
  option-set-unverified would render the unverified caption dishonestly.
  The Dart enum is presentational (day entries store code strings;
  `observations.category` is free text), so no data migration exists or
  is needed.
- **Codes with attested option sets** become real picker codes:
  `feelings` (`happy`, `sad`, `angry`, `anxious`, `indifferent` high;
  `sensitive`, `mood_swings` medium; `excited`, `insecure`, `grateful`
  redesign-attested; plus `irritable`), `mind` (`calm`, `distracted`,
  `focused`, `stressed`), `motivation` (`motivated`, `unmotivated`,
  `productive`, `unproductive` — the option set is attested even though
  the category is legacy; the issue says "add as a category ... primarily
  so historic Clue exports import losslessly", which the picker presence
  mirrors without claiming current-app parity), `social_life`
  (`sociable`, `withdrawn`, `supportive`, `conflict`), `partying`
  (`drinks`, `cigarettes`, `big_night`, `hangover`).
- **Option-set-unverified categories** join `kUnverifiedTagCategories`
  with zero codes and the existing "unverified — pin before shipping"
  caption: `pms` (presence-based; option set not publicly enumerated —
  and presence logging already lives on the #220 chip, deliberately
  outside the taxonomy per #220's own plan), `meditation`
  (presence/duration-style, undocumented), `leisure` (undocumented).
  No invented placeholder anywhere.
- **`big_night`, not `big night`.** Clue's attested partying option is
  the two-word "big night"; codes in the flat day-entry-tag namespace are
  snake_case, so the picker code is `big_night` and the importer's option
  map renames `big night` → `big_night` — the exact `period_cramps` →
  `cramps` pattern (#249). `drinks`/`cigarettes`/`hangover` pass through
  and match the taxonomy codes option-for-option.
- **Importer**: `kClueTypeMap` gains `meditation` and `partying`
  (pass-through specs; every option string a real export carries lands in
  `observations.category = 'meditation'/'partying'` verbatim unless the
  map renames it). The #190 doc's "no export `type` at all" list drops
  both; unrecognised types still escape to `ClueUnknownDatapoint`.
  `leisure`'s unknown-never-drop guarantee (AC) is already the pass-through
  default — pinned with a dedicated test.
- **Clinical terminology**: all 22 new codes get explicit local decisions
  in `kTagClinicalCodes` (no guessed SNOMED — the #249 rule verbatim);
  `terminology.md` documents the section. The re-parented five keep their
  existing rows untouched.
- **Care modes (#131 seam)**: every mode's `categoriesInOrder` stays a
  full permutation of `TagCategory.values` — teen reorders (body, then
  the feelings/mind cluster), never removes. The new categories append
  after `body` in the enum order.
- **#259 seam — partying on minor profiles, deliberately not implemented
  here**: #259 owns the per-profile tracking-preference mechanism
  (default-hidden on `isMinor`, primary-guardian reveal). Building the
  default-hidden half without the reveal path would strand the category
  unloggable for minors and would half-implement #259's curation, which
  the brief forbids; a mode-keyed hide would break #131's pinned
  permutation invariant ("teen is not a reduced app"). What this issue
  ships is AC6's data-model half: `partying` exists in the taxonomy and
  the import path for **every** profile, losslessly, so #259's visibility
  default lands on a real category.

## Implementation units

- **U1 — taxonomy** (`lib/domain/tags.dart`): replace `mood` with
  `feelings`, `mind`, `motivation`, `socialLife`, `leisure`,
  `meditation`, `pms`, `partying`; re-parent the five legacy codes; add
  the 22 new codes; grow `kUnverifiedTagCategories` to 8; update the
  library doc comment (counts, #251 rule).
- **U2 — care modes** (`lib/domain/care_modes.dart`): labels + orders for
  all four modes; teen's reorder keeps body first with feelings/mind next.
- **U3 — importer** (`lib/domain/import/clue/clue_option_map.dart`,
  `docs/import/clue-mapping.md`, `test/fixtures/clue/mapping_table.json`):
  the two new type specs, the doc's table rows + escape-list edit, and
  fixture rows (appended, so existing indices stay stable).
- **U4 — terminology** (`lib/domain/export/clinical_terminology.dart`,
  `docs/clinical/terminology.md`): 22 local-decision rows + doc section.
- **U5 — tests**: `tags_test.dart` (counts, per-category sets,
  re-parenting, unverified set, vocabulary guard), `care_modes_test.dart`
  (permutation holds at 22 categories), `logging_test.dart` (chip totals,
  headings, unverified-caption count, teen order), `clinical_terminology_test.dart`
  (golden table + counts), `clue_export_parser_test.dart` (fixture rows +
  synthetic #251 input: `big night` → `big_night`, leisure pass-through),
  `db_test.dart` comment refresh. No ARB changes: the only new user-facing
  string is the existing `daySheetUnverifiedPin` caption; category
  headings are care-mode copy literals per the #131/#249 pattern.

## Acceptance criteria (issue ACs → where proven)

- All 8 categories exist as observations categories, with the
  unverified-caption note where the finding says so → importer specs +
  `tags_test.dart` + day-sheet caption test (`pms`/`meditation`/`leisure`
  are the captioned three; `feelings`/`mind`/`motivation`/`social_life`/
  `partying` carry the attested sets).
- `sad`/`anxious`/`sensitive`/`calm` keep exact codes, category changes →
  `tags_test.dart` re-parenting test.
- `irritable` preserved under `feelings` → same test.
- `leisure` import preserves unknown options verbatim → parser test with
  a fabricated option string.
- `partying` in the schema for all profiles → taxonomy + importer + tests;
  the `isMinor` default-hidden/reveal mechanism is #259's (stated in the
  PR, per this issue's own Proposed-change note).
- `pms` presence hook → already live since #220 (`day_entries.pms`, chip,
  prediction input); the `pms` observations category round-trips import;
  no prediction logic added.

## Verification

`flutter pub get`, `flutter analyze`, `flutter test`,
`dart run tool/quality_gate.dart` — all before the PR.
