# Plan — PMS as a logged and predicted phase (Issue #220)

Date: 2026-09-09 · Branch: `feat/220-pms-phase` · Epic: Predictions & Insights (P1)

## Context

Issue #220 asks for PMS as a first-class logged state (deliberately **not** a
member of the 17-tag taxonomy — Clue's own separation of the "PMS" phase from
the individual symptoms that may co-occur with it), 6-cycle average onset and
length reusing #213's `kAverageWindowCycles` exactly, a predicted PMS band on
the overview/calendar in #213's confidence vocabulary, and a hard
3-logged-intervals minimum below which nothing renders.

Dependency #213 (windows, tiers, forecast) is landed; #276 (forecast calendar)
and #340 (l10n) are landed; #132 (history) is landed. The taxonomy issues
(#247/#249/#251) that could own a taxonomy-shaped PMS entity are still open,
so per the brief's coordination note the marker lands as a **new synced
`day_entries` marker column** on the #159-provenance precedent
(containment-guarded `sync_push` path, CHECK backstop, pgTAP round-trip) —
documented here as the storage decision. Reminder wiring is **not** in scope
(#178); issue #136 blocks on this one.

## Product contract

1. **A day (or a run of days) can be marked PMS**, independent of flow and of
   every tag also logged that day. The marker is `day_entries.pms`
   (boolean, default false), mirrored in Drift schema v12, the domain model,
   the sync codec, and the JSON export (v7)/import round-trip.
2. **Averages** over the most recent `kAverageWindowCycles` (6) usable PMS
   intervals, where an *interval* is a maximal run of strictly consecutive
   logged PMS days (no bleed-style one-day-gap merging: a logged hole is a
   real "not PMS" signal), attributed to the first period starting after it:
   `onset` = days before that period the interval began, `length` = interval
   days **clamped to the onset** (so a PMS log that runs into the period
   contributes only its premenstrual portion, and a predicted band can never
   overlap the predicted bleed band).
3. **The hard minimum**: fewer than `kMinPmsIntervalsForPrediction` (3,
   mirroring `kMinCompletedValidCycles`) usable intervals predicts nothing —
   no band, no averages shown as if confident. The estimate also requires a
   live period estimate (`ActivePrediction`), because the band anchors before
   `estimatedNextStart`; `NotEnoughHistory` and the `provisional` seeded path
   never carry PMS.
4. **The band renders on the calendar** (replacing #276's fixed
   `estimate − 7 … − 1` PMS badge, which had no logged history behind it) and
   as a line on the overview (range + averages + tier + disclaimer). The tier
   is the period estimate's own `ActivePrediction.tier` — #213's vocabulary,
   never a second PMS confidence system.
5. **Every surfaced estimate sits next to the disclaimer** (`kEstimateDisclaimer`,
   R17).

## Key technical decisions

- **Storage shape** (`day_entries.pms boolean not null default false`): the
  tracking-model issues are still open; a dedicated synced column is the
  minimal honest shape and exactly follows #159's precedent. `pms` is health
  content, so unlike `source`/`source_id`/`import_id` it **clears on every
  tombstone** — `day_entries_tombstone_pms_check` (deleted_at is null or
  pms = false) is the structural backstop, mirroring
  `day_entries_tombstone_flow_check` (#224). `sync_push` (create-or-replace
  from `20260909141503_care_notes_visit_prep.sql`, same 7-arg signature) adds
  `pms` to the key allowlist, parses it ahead of the tombstone branch, clears
  it in all three tombstone-producing sites, writes it on INSERT, and on
  UPDATE guards it with `v_row ? 'pms'` **except when the push is itself a
  tombstone** (`when v_deleted_at is not null then false` comes first — the
  pgTAP suite caught the first draft letting the containment guard resurrect
  the marker through a delete). Same-date collisions: last-writer-wins like
  flow/note (a single boolean has nothing to union); the tags union is
  untouched.
- **Derivation lives with the prediction** (`lib/domain/prediction/pms.dart`,
  pure; `computePrediction` gains an optional `pmsDates` parameter and
  `computePredictionFromEntries` derives it from the entries). The estimate
  rides `ActivePrediction.pms`, so `CyclePredictionService`'s existing
  streams, memoisation, and every consumer get it with no new subscriptions —
  and a PMS-only edit always moves a row's `updatedAt`, which the #197
  fingerprint already folds.
- **Calendar**: `forecastDayCells` takes the optional estimate; PMS badge days
  are exactly the band, clamped to after today (past stays factual, KTD3);
  `null` means no PMS badge anywhere. The "PMS window" legend entry renders
  only while a band exists. Cramps keep their fixed window (KTD7, untouched).
- **Overview**: a section under the tier caption when
  `ActivePrediction.pms != null`: band range (locale-formatted), the rounded
  averages, the tier label, and the disclaimer.

## Implementation units

- **U1 — server**: `20260909160000_pms_day_marker.sql` (column, CHECK backstop,
  additive `update (pms)` grant, `sync_push` re-emission) + `pms_marker_test.sql`
  (15 pgTAP assertions: round-trip, resolved-row echo, containment guard,
  explicit false, direct tombstone clear, same-date loser/winner, CHECK
  backstop via SQLSTATE, revive).
- **U2 — client storage**: Drift v12 (`DayEntries.pms`, `_upgradeToV12`),
  codegen, `drift_schema_v12.json`, **`ci.yml` dump-filename bump** (the
  historically missed step), storage upsert/tombstone/apply paths, mappers,
  repository, schema-verification harness regeneration (`generated_migrations/`,
  version constants, the v11 index-seeding fix the new `from = 11` fixture
  leg exposed).
- **U3 — domain**: `DayEntry.pms`, row codec encode/decode (absent key →
  false), export v7 + import parse/plan (merge ORs the marker — the boolean
  analogue of the tags union), `pms.dart` + `ActivePrediction.pms`.
- **U4 — surfaces**: day-sheet PMS chip (outside the flow row and the
  taxonomy grid; read-only body names the marker), calendar band + legend
  gating, overview PMS section, ARB strings (`daySheetPmsChip`,
  `daySheetPmsGroup`, `overviewPmsBandLabel`,
  `overviewPmsDaysBeforePeriod`), gen-l10n.

## Acceptance criteria (issue ACs → where proven)

- Day/range markable independent of tags → day-sheet chip tests
  (`test/ui/logging_test.dart`), storage round-trip
  (`test/data/storage_sync_test.dart`).
- Onset/length averages over #213's 6-cycle window → `test/domain/pms_test.dart`
  (window truncation, clamping, means).
- Band renders once ≥3 PMS intervals, gated on the period estimate's tier →
  `test/domain/forecast_test.dart` (band coverage, clamp), calendar widget
  tests (`forecast_calendar_test.dart`, `calendar_navigation_test.dart`),
  overview widget test (`overview_test.dart`).
- Fewer than 3 intervals → no prediction → `pms_test.dart` hard-minimum cases,
  forecast "no badge anywhere" widget case, overview absence case, legend
  absence case.
- Round-trips through sync like any day-level field → `pms_marker_test.sql`,
  `row_codec_test.dart`, `storage_sync_test.dart`, export/import tests.

## Explicitly out of scope

- Reminder/notification wiring (#178, blocks-on-this #136).
- Partner-visible PMS phase (#151).
- Taxonomy restructuring (#247/#249/#251 own it; the marker is independent).
- Clue importer mapping of PMS concepts (#240-family, untouched).
