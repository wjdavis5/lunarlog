---
title: Data Export Epic (Issue #115) - Ideation/Plan
type: feat
date: 2026-09-22
issue: wjdavis5/lunarlog#115
artifact_contract: ce-unified-plan/v1
artifact_readiness: ready-for-owner-review
product_contract_source: issue-115
execution: ideation
---

# Data Export Epic — Ideation/Plan (Issue #115)

Date: 2026-09-22 · Branch: `opencode-deepseek/115-export-epic-plan` ·
Epic: clinical-export (P1). Companion inputs: #960 (CSV shape, owner
decision), #161 (C-CDA, deferred), #21 (store declarations), #849
(per-note privacy).

All paths repo-relative. Every citation was re-verified against this
checkout (tip `ebded9e9`). Where #115's body, #960's analysis, or a doc
has drifted from the tree, the drift is called out rather than copied.

## Context

Issue #115 is a scoping placeholder, not a spec:

> "Feature idea: broader data-export capability … Needs scoping/ideation —
> possible epic covering formats (CSV, PDF summary?), scope (single
> profile vs. household), and whether it should live alongside or replace
> the current JSON export."

Since it was filed, two of the three named formats shipped under other
issues: **CSV** under #469 and the **PDF clinician summary** under #154.
JSON was already shipped under #17 U5. So the epic's real remaining
questions are narrower than the body implies — and the honest answer to
"formats (CSV, PDF summary?)" is that there is no unbuilt format on the
roadmap: R13 commits to exactly "CSV, a one-page PDF summary, and JSON …
through the system share sheet"
(`docs/plans/2026-09-04-0738-feat-target-state-roadmap-plan.md:65`), and
C-CDA is explicitly deferred (#161).

The epic therefore does **not** need new format work. Its value is in
(a) reconciling what shipped against the owner's stated CSV intent (#960),
(b) unifying a set of four independently-built tiles into one export hub
with one range picker, one profile scope, and one redaction rule, and
(c) closing the store-declaration gap (#21) that the shipped formats
opened.

## Inventory — what already ships (verified)

Four export formats are live in **Settings → Your data**, each its own
tile mounted from `YourDataSection._sectionChildren`
(`lib/ui/settings/your_data_section.dart:186-193`):

| Format | Tile | Builder | Writer / filename | Scope | Range |
|---|---|---|---|---|---|
| **JSON** "Export my data" | `your_data_section.dart:211` | `lib/domain/export/account_export.dart:159` (`buildAccountExport`), merged `:469` | `lib/data/export/account_export_writer.dart:53`; `lunarlog-export-<ts>.json` `:84`, `application/json` | **every profile on the device** (`:381`,`:391-404`) + a merged `server` section when signed in | none — whole history |
| **FHIR R4** "Export clinical summary (FHIR)" | `lib/ui/settings/clinical_export_tile.dart:80` | `lib/domain/export/fhir_bundle.dart:270` | `lib/data/export/fhir_bundle_writer.dart`; `lunarlog-fhir-<yyyyMMdd>.json` `:36`, `application/fhir+json` `:31` | one live profile, chooser `:191` | shared picker `:256` |
| **PDF summary** "Export clinical summary (PDF)" | `lib/ui/settings/clinical_pdf_export_tile.dart:73` | `lib/domain/export/clinical_pdf_summary.dart:187` + `clinical_pdf.dart` | `lib/data/export/clinical_pdf_writer.dart:42`; `lunarlog-clinical-summary-<date>.pdf` `:27` | one live profile, chooser `:179` | shared picker `:209` |
| **CSV** "Export as CSV" | `lib/ui/settings/csv_export_tile.dart:51` | `lib/domain/export/csv_export.dart:90` (`buildCyclesCsv`), `:295` (`buildDailyLogCsv`) | `lib/data/export/csv_export_writer.dart:25`; **two** files `lunarlog-cycles-<date>.csv` + `lunarlog-daily-log-<date>.csv` `:38-41` | one live profile, chooser `:151` | **none** — whole history |

Shared infrastructure already exists:

- **Share + cleanup**: `lib/data/export/export_file_share.dart:57`
  (`writeShareExportAndCleanup`) writes under the protected Application
  Support directory (issue #843), hands files to `share_plus`, and deletes
  both the originals and the plugin cache copy. Every one of the four
  writers calls it.
- **Range selection**: `lib/domain/export/fhir_export_range.dart` (presets
  `:23-30`, resolver `:155`) and `lib/ui/settings/export_range_picker_sheet.dart:53`
  — used by FHIR and PDF only.
- **Profile chooser**: the same `SimpleDialog` is hand-rolled three times
  (`clinical_export_tile.dart:198`, `clinical_pdf_export_tile.dart:179`,
  `csv_export_tile.dart:151`); JSON instead exports all profiles.
- **Coherent snapshot read**: `lib/domain/repositories/account_export_snapshot_repository.dart:39-57`
  (issue #140 review, LLA-084/LLA-094) — used by JSON only.

Redaction discipline today is per-builder, not shared:

- JSON's R9: no sync bookkeeping, no guardian attribution ids, nothing not
  already a plain domain field (`account_export.dart:12-16`).
- FHIR extends R9 further for off-device documents: no storage-assigned id
  ever emitted (one-way v5 `urn:uuid` only), `Patient` carries only the
  display name, and **`DayEntry.note` is never read at all** — no function
  accepts it (`fhir_bundle.dart:47-57`).
- PDF matches FHIR's identifier discipline and **never reads `.note`**
  either (`clinical_pdf_summary.dart:43-47`; no `.note` reference in the
  file).
- CSV is the one free-text-bearing tabular format: it emits `notes` and
  `tags` (`csv_export.dart:257-258`) behind an RFC 4180 + formula-injection
  guard (`:52`, issue #563).

## Gaps #115 actually has

**G1 — Format gap: none unbuilt, but CSV shape is unresolved (owner).**
The shipped CSV is **two files** — a per-bleeding-episode `cycles` table
and a day-per-row `daily_log` table (`csv_export_writer.dart:38-41`). The
owner's 2026-09-20 decision on #960 is "one flat CSV file … one row per
day, tags in a column" — which the `daily_log` file already is, but the
`cycles` aggregate is extra. That is a real, owner-facing discrepancy, not
a tooling gap; #960's analysis already asks the owner to resolve it. No
new export infrastructure is needed either way.

**G2 — Scope gap: no consistent profile/household model.** JSON is
household (`List<Profile>`), while FHIR/PDF/CSV are single-profile. There
is no per-profile JSON export, no household clinical/tabular export, and
no shared "profile scope" control — each tile re-implements its own
chooser (or omits one). The picker's default is "the only live profile, or
ask", repeated three times.

**G3 — Range gap: CSV ignores the range picker.** FHIR and PDF both ask
via `showExportRangePickerSheet`; CSV and JSON export everything. CSV also
reads its exclusion set through `SettingsStore`/`parseOmittedCycles`
(`csv_export_tile.dart:186-189`) rather than the shared `CycleExclusionList`
the other two use — a second, divergent path to the same fact.

**G4 — Redaction gap: no shared rule, and two rules the issue names are
unimplemented.** Nothing is a "guardian-lens export": no export builder
reads a viewer's role or `isSubject`
(`lib/domain/models/profile_guardian.dart:96`, `:183`). And no tile reads
`Profile.isMinor`/`isMinorAsOf` (`lib/domain/models/profile.dart:134-142`)
— confirmed by grep, zero matches in any of the four tiles
(`your_data_section.dart`, `clinical_export_tile.dart`, `csv_export_tile.dart`,
`clinical_pdf_export_tile.dart`). So today any operator who can reach
Settings can export any profile on the device, minor profiles included.

**G5 — Store-declaration gap (#21).** `PRIVACY.md` §7 documents "Export my
data" (JSON, `:149`) and the FHIR clinical summary (`:150`) as bullets, but
**has no CSV bullet**; CSV is named only in §4's two transfer paragraphs
(`:106`, `:110`). §9 ("Apple App Store & Google Play Declarations",
`:174-181`) does not mention export at all — its two "adds no off-device
transfer" bullets cover the widget (`:180`) and health-platform sync
(`:181`) only. #21's checklist (`gh issue view 21`) covers App Store
Connect and Play Data safety only and does not mention export either.
Store-declaration-wise the four formats add **no new data type and no new
off-device transfer** — they are user-initiated hand-offs to the OS share
sheet — but the prose that says so is incomplete and neither #21's checklist
nor §9 asserts it.

**G6 — Hub gap.** Four independent tiles with four independent subtitles,
two scope behaviours, two range behaviours, and three copies of the same
chooser. There is no single surface that answers "what can I get out of
this app, and for whom".

## Recommended shape

One **"Your data" export hub**: keep the four formats as rows (they already
are), but drive them from one shared model rather than four hand-rolled
flows.

1. **One hub, per-format rows.** `YourDataSection` remains the host; the
   formats render as a single grouped list ("Export your data") with one
   row per format, each naming its audience and scope (e.g. "JSON — every
   profile, for restore", "FHIR — one profile, for a clinician"). This is a
   presentation refactor of `_sectionChildren`
   (`your_data_section.dart:186-193`), not a new capability.
2. **Shared profile scope.** Extract the triplicated chooser
   (`clinical_export_tile.dart:198`, `clinical_pdf_export_tile.dart:179`,
   `csv_export_tile.dart:151`) into one reusable helper, with a
   documented default (one live profile → export it directly; several →
   choose). JSON keeps its intentional household scope; clinical/tabular
   stay per-profile (see D-3).
3. **Shared range picker.** Leaving CSV and JSON at "everything" is **not**
   the recommendation: CSV should adopt the existing
   `showExportRangePickerSheet`/`FhirExportRange` machinery
   (`export_range_picker_sheet.dart:53`) so all four rows answer the range
   question the same way. The picker is already pure-domain-backed and
   makes no clinical claim; no new range type is needed, and JSON stays
   whole-history because it is the restore document (D-3).
4. **Shared redaction rule.** Introduce a pure domain function — e.g.
   `ExportRedaction` / `redactProfileForExport(...)` — that every format
   builder is required to run its per-profile input through, encoding two
   rules:
   - **Guardian-lens rule (#849):** an export produced by a viewer who is
     not the subject never includes a note the subject has marked private.
     Note this is **forward-compatible only**: no `is_private`/`private`
     column exists on `day_entries` or `guardian_notes` today (the
     guardian-lens plan records this at
     `docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:99-104`,
     and #849 is open). The seam lands now; it redacts nothing until #849's
     column exists.
   - **Minor-profile rule:** a minor's profile is exported only by an
     accepted guardian on that profile (`acceptedGuardianFor`,
     `profile_guardian.dart:183`; minor derivation
     `profile.dart:134-142`). No minor check exists in any tile today (G4).

## Per-format privacy / store-declaration implications (#21)

All four formats are built on-device and handed to the OS share sheet —
`PRIVACY.md:110` already says this for JSON/FHIR/CSV, and no format adds a
server round-trip. The per-format consequences:

- **JSON** is the broadest: it carries free-text notes, tags, guardian
  membership rows, and (when signed in) a `server` section
  (`account_export.dart:18-38`). Its own disclosure is §7's bullet
  (`PRIVACY.md:149`) plus §8's Data Portability entry (`:167`). No change.
- **FHIR / PDF** carry no note text and no storage ids (G4 above), so they
  are the safest to forward to a clinician; §7 already documents FHIR
  (`:150`) and should gain a matching PDF line.
- **CSV** is the only tabular format that emits `notes`/`tags`
  (`csv_export.dart:257-258`), so it carries the same free-text risk as
  JSON, behind the #563 formula guard. It has **no §7 bullet** today; a
  one-paragraph addition is required so §7 matches §4's claim
  (`PRIVACY.md:106`,`:110`).
- **No App Store / Play declaration category changes.** §4 already states
  that clinical exports are user-directed, user-controlled transfers
  (`PRIVACY.md:106`,`:110`), so no declared data type changes; §9 (`:174-181`)
  is silent on export, and #21's checklist does not assert the conclusion.
  #21 should gain an explicit "export formats add no new declared data type"
  line so it is recorded where the submission reviewer looks.

Relevant doc drift to correct while touching this area:
`docs/product/positioning.md:71-72` still says reading an exported file
back in "is being built (issue #140, PR #325 open); it is not in the
shipped app yet" — import shipped (`lib/domain/import/account_import.dart`,
`lib/data/import/account_importer.dart`; AGENTS.md), so that sentence is
stale. (Docs-only; not part of this epic's code.)

## Numbered decisions

**D-1 — Formats: ship the four that exist; add none now.** R13's format
list is complete (`roadmap:65`), CSV and PDF already ship, and C-CDA is
deferred with a recorded rationale (#161). The epic's deliverable is
consolidation and disclosure, not a new serializer. **Owner may override**
by asking for a format R13 does not name (none is proposed here).

**D-2 — New formats sit beside JSON; JSON is never replaced.** R13 names
"CSV, a one-page PDF summary, and JSON" as a set, and JSON is the only
lossless round-trip document the importer reads back (`account_export.dart`
`kAccountExportSchemaVersion` v14, `:143`;
`lib/domain/import/account_import.dart`). Replacing it would break restore.
**Recorded as decided** (nothing in the tree suggests otherwise).

**D-3 — Scope: JSON stays household; FHIR/PDF/CSV stay per-profile.** A
household clinical/tabular export is not requested by #115, has no
consumer (a clinician treats one patient), and would multiply the
redaction surface. A household **JSON** export is already correct because
it is the device-restore document. **Recorded as decided**; a household
roll-up belongs to #803's separate line of work (closed), not export.

**D-4 — Shared range picker, CSV included.** CSV adopts
`showExportRangePickerSheet`/`FhirExportRange`
(`export_range_picker_sheet.dart:53`). The cycles aggregate's semantics
under a range need one coder decision (does `cycles.csv` list only
episodes starting inside the range?), recorded as a coder open question.

**D-5 — Shared redaction rule, applied at each builder boundary.** A pure
domain redaction function (G4), not a post-hoc string filter, and not a
per-tile check. Both rules are encoded there so a fifth format cannot ship
without them.

**D-6 — The CSV shape decision is the owner's (#960); this plan does not
decide it.** #960 carries `needs-human-review` and the owner's 2026-09-20
comment. Two options, framed:

- **Option A — consolidate to the owner's stated shape.** `PlatformCsvExportWriter`
  shares one file, `lunarlog-daily-log-<date>.csv` (day-per-row, tags in a
  column — already `buildDailyLogCsv`, `csv_export.dart:295`). Question
  within A: is the `cycles` aggregate **dropped**, or kept inside the same
  workbook as a second sheet (not expressible in flat CSV, so dropping is
  the only true flat-CSV reading)?
- **Option B — keep the shipped two-file export (#469) as satisfying R13.**
  `cycles.csv` + `daily_log.csv` are both useful; the owner's one-file
  phrasing is a preference, not a defect.

**Recommendation (not a decision): Option B, unless the owner specifically
wants the flat single file.** The road-map clause R13 says "CSV" without a
file count; the two-file form is already shipped, tested
(`test/domain/export/csv_export_test.dart`), and reviewed, and the cycles
aggregate has no flat-CSV home. Consolidating would delete a working
artifact for a cosmetic match. If the owner wants one file, Option A is a
small, self-contained writer change (U5 below).

**D-7 — Extract the shared profile chooser and range flow; keep tiles
thin.** The three chooser copies collapse into one helper. This is a
pure-UI refactor with no export-content change.

**D-8 — Minor-profile export guard is a client-side gate backed by guardian
membership.** Exports of a minor profile require the operator to be an
accepted guardian on that profile (`acceptedGuardianFor`). This is a
presentation/UX gate; the authoritative access-control fact is RLS
(an operator can only have the profile's rows if RLS already allowed it),
and the local-only case (no membership rows yet) follows the existing
fail-open-to-operator discipline (`profile_guardian.dart:176-193`,
matching `_effectiveReadOnly`'s posture in the guardian-lens plan D-1).
Whether "accepted guardian" is the right bar, or owner/co-parent only, is
an **owner's** question (OQ-2).

**D-9 — #849 private-note redaction lands as a seam now, behaviour later.**
Implement the redaction function and call it from every builder, but it has
no column to read until #849 ships. Do not invent a schema; do not block
this epic on #849.

## KTDs

- **KTD1 — The hub is a unification, not a rewrite.** Keep the four
  builders, writers, filenames, mime types, and the shared
  `writeShareExportAndCleanup` path (`export_file_share.dart:57`); change
  only how the UI presents and parameterises them. This keeps every
  existing test (`test/domain/export/*`, `test/ui/*_export_tile_test.dart`,
  `test/ui/your_data_section_test.dart`) meaningful.
- **KTD2 — Redaction is a pure domain function applied to per-profile
  input, never a string filter over encoded output.** Filtering encoded
  JSON/CSV/FHIR after the fact is how a field gets missed; the function
  takes domain objects and returns domain objects, so a new format can only
  ignore it by not calling it — which a test can pin.
- **KTD3 — Everything stays on-device.** Global assumption #4
  (`docs/clinical/fhir-export.md:315-342`) and #154's body: no server-side
  renderer, no new egress surface. The share sheet is the boundary.
- **KTD4 — No new schema, no new RLS, no new RPC.** The epic is client
  code plus docs. #849 would add a column, but that is #849's work.
- **KTD5 — Determinism and version constants are preserved.** JSON's
  `kAccountExportSchemaVersion` (`account_export.dart:143`) and FHIR's
  `kFhirExportBundleVersion` (`fhir_bundle.dart:117`) are contracts; a
  redaction pass that changes output for a non-redacted profile would be a
  regression, so the default path must be byte-identical to today
  (pinned by the existing determinism tests).
- **KTD6 — The guardian-lens rule is viewer-derived, not profile-derived.**
  "Guardian-lens export" means the operator is not the subject
  (`ProfileGuardian.isSubject`, `profile_guardian.dart:96`), the same
  per-membership lens #850 defines
  (`docs/plans/2026-09-21-001-feat-per-viewer-guardian-lens-plan.md:53-74`),
  never `relationship`.
- **KTD7 — Filenames never carry a profile name.** FHIR already documents
  this (`clinical_export_tile.dart:11-14`); the hub must not regress it.

## Units of work

Each unit is sized for one coder (≤ ~400 changed lines including tests) and
carries its own tests. Ordered so each lands green on its own.

- **U1 — Export hub scaffold + shared profile chooser (~300).**
  Extract the triplicated `SimpleDialog` chooser
  (`clinical_export_tile.dart:198`, `clinical_pdf_export_tile.dart:179`,
  `csv_export_tile.dart:151`) into one reusable helper
  (`lib/ui/settings/export_profile_choice.dart` or similar), parameterised
  by title/subtitle, and group the four rows under one "Export" heading in
  `your_data_section.dart:186-193`. **Tests:** a widget test per tile
  proves the chosen profile reaches the collaborator; a
  `your_data_section_test.dart` case proves the grouped heading and the
  four rows render, and none on web/zero profiles.

- **U2 — CSV adopts the shared range picker (~350).**
  `csv_export_tile.dart` calls `showExportRangePickerSheet`
  (`export_range_picker_sheet.dart:53`) and filters entries/observations
  through `FhirExportRange.filterEntries`/`filterObservations`
  (`fhir_export_range.dart:61-71`) before building. Replace the divergent
  `SettingsStore`/`parseOmittedCycles` read (`:186-189`) with the shared
  `CycleExclusionList` the FHIR/PDF tiles already use. Decide and document
  the cycles-aggregate range semantics (OQ-4). **Tests:** `csv_export_tile_test.dart`
  gains range-selection cases (last-3-cycles narrows both files; cancel
  does nothing), and a domain test pins the aggregate's range boundary.

- **U3 — Shared redaction policy module (~350).**
  New pure `lib/domain/export/export_redaction.dart` with the guardian-lens
  rule (#849 seam; no-op until a private flag exists) and the derived
  private-note filter, plus a view-model (`ExportViewer`) built from
  `ProfileGuardian.isSubject` + role. Call it from
  `account_export.dart`'s and `csv_export.dart`'s per-profile paths so the
  free-text-bearing formats are covered first. **Tests:** a new
  `test/domain/export/export_redaction_test.dart` proving (a) an unredacted
  subject view is byte-identical to today's output, (b) a non-subject viewer
  drops a flagged note, and (c) a profile with no viewers set is unchanged.

- **U4 — Minor-profile export guard (~300).**
  Each format row resolves the operator's membership via
  `acceptedGuardianFor` (`profile_guardian.dart:183`) and refuses to export
  a profile whose `isMinorAsOf` is true (`profile.dart:134`) unless a
  membership is accepted — with honest copy, not a hidden tile (mirroring
  `_purgeImportedDataTile`'s "surface the honest error" posture,
  `your_data_section.dart:256-263`). **Tests:** a widget test that a minor
  profile exported by a non-guardian operator renders the guard copy and
  never calls the collaborator; a guardian does call it; the local-only
  fail-open case is pinned.

- **U5 — CSV flat-file consolidation (conditional on #960 = Option A;
  blocked on owner) (~200).**
  Change `PlatformCsvExportWriter.exportAndShare`
  (`csv_export_writer.dart:32`) to share one `daily_log` file and drop the
  cycles aggregate (or keep both files if the owner picks B — in which case
  this unit is cancelled). **Tests:** writer test asserts one shared file;
  `buildCyclesCsv` is removed or left tested but unwired, per the owner's
  answer.

- **U6 — Docs + store-declaration coverage (#21) (~150).**
  Add a CSV bullet to `PRIVACY.md` §7 beside JSON/FHIR
  (`PRIVACY.md:149-150`) and a PDF line; add an explicit "export formats add
  no new declared data type" item to #21's own checklist (the issue body,
  which today covers only App Store Connect and Play Data safety). Correct
  the stale #140 sentence in `docs/product/positioning.md:71-72`.
  **Tests:** none (docs); verified by review against
  `PRIVACY.md:106`,`:110`,`:149-150`,`:174-181`.

- **U7 — Guardian-lens private-note redaction activation (blocked on #849)
  (~150).** When #849's private flag ships, wire it into U3's module (the
  seam already exists). **Tests:** a domain test that a subject's private
  note is absent from a guardian-lens JSON/CSV export and present in the
  subject's own. Do not start until #849's column exists.

## Test plan

- **Domain:** `test/domain/export/export_redaction_test.dart` (U3, U7),
  `csv_export_test.dart` range semantics (U2). Existing
  `account_export_test.dart`, `fhir_bundle_test.dart`,
  `clinical_pdf_summary_test.dart`, `csv_export_test.dart` must stay green
  unchanged — the default (non-redacted, subject) path is byte-identical
  (KTD5).
- **Widget:** `csv_export_tile_test.dart` (U2), the three tile tests plus
  `your_data_section_test.dart` (U1, U4).
- **Gates:** `flutter analyze`, `flutter test`,
  `dart run tool/quality_gate.dart`. No `build_runner`/schema step
  (KTD4). `database.types.ts` regeneration not required.

## Out of scope

- Any new export format (C-CDA is deferred, #161).
- A household clinical/tabular export (D-3; #803 is the household line).
- Server-side rendering or a server export endpoint (KTD3).
- Building #849's private-note column (that is #849; this epic only lands
  the seam).
- Any RLS/policy/grant change (KTD4).
- Reading exports back in (import shipped; separate surface).

## Open questions

1. **CSV shape — one flat day-per-row file, or the shipped two-file
   (cycles + daily log)?** — **owner's** (#960, `needs-human-review`).
   Options and the plan's recommendation are D-6. This is the one decision
   that blocks U5.
2. **Minor-profile export bar: any accepted guardian, or owner/co-parent
   only?** — **owner's.** D-8 defaults to "accepted guardian" and surfaces
   the honest error; the tighter bar is a product/privacy call.
3. **Does a guardian-lens export need a visible "this copy omits notes you
   marked private" line**, or is silent omission correct? — **owner's**
   (copy/voice; depends on #849's surface conventions).
4. **Cycles aggregate under a date range** — does `cycles.csv` list only
   episodes whose start falls inside the chosen range, and how does the
   open cycle appear? — **coder's**, resolved in U2 and stated in the PR.
5. **Should CSV's two files ever become a ZIP**, or does the share sheet
   handle two files acceptably on both platforms? — **coder's**, informed
   by the device checklist; default is to keep two shared files (current
   behaviour).
6. **Does the hub group formats under one heading, or keep them as four
   sibling tiles with unified subtitles?** — **coder's**, a presentation
   call resolved in U1; the recommendation (one grouped heading) is the
   plan's default.
