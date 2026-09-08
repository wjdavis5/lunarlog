---
title: Cycle History with Omit-from-Average and Confidence Framing - Plan
type: feat
date: 2026-09-08
issue: wjdavis5/lunarlog#132
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-132
execution: code
---

# Cycle History with Omit-from-Average and Confidence Framing - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written after implementation to record what shipped and
why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** Make the cycle history the app already derives visible and
  correctable: a reverse-chronological history list with per-cycle
  omit-from-average, cycle statistics, high/learning/irregular confidence
  framing, and a three-option late resolver replacing the single-line late
  banner.
- **Means:** Extend the pure prediction core with a device-local omission
  seam (`omittedCycles.<profileId>` in `app_settings`), add a history
  derivation beside it, and render both through two new widgets in the
  overview. No schema, no sync model, no server changes.
- **Authority hierarchy:** Issue #132 owns intent; the roadmap
  ([`2026-09-04-0738-feat-target-state-roadmap-plan.md`](2026-09-04-0738-feat-target-state-roadmap-plan.md)
  U2/R4/R5/R6/KTD2) owns the settled shape; the task brief's settled
  decisions (device-local v1, cycle-only vocabulary, provisional
  thresholds) govern where the issue left room.
- **Stop conditions honored:** No fertility or ovulation vocabulary
  anywhere (R13); the estimate disclaimer on every surface showing a
  number (R17); `lib/domain` stays pure Dart; no persisted derived state.

---

## What Shipped

### U1. Domain: omission-aware prediction

`lib/domain/prediction/prediction.dart`

- `computePrediction` and `computePredictionFromEntries` take
  `Set<LocalDate> omittedCycleStarts` (default empty — every existing
  caller unchanged).
- A cycle length belongs to the cycle that *starts* it (episode start
  through next start, KTD2), so the omission check applies to the earlier
  start of each pair. Omitted lengths leave the average exactly like
  window-invalid ones; the raw `validCycleCount` still ignores omissions.
- **Skip semantics** (`kSkipAdvanceCycles = 1`): when the *open* cycle's
  start is omitted ("skip this cycle"), the estimate advances one
  averaged cycle — the skipped cycle is expected to run a mean length —
  and when the next period is finally logged, that cycle's real length is
  excluded from the average like any other omission. A skip does **not**
  lift the sixty-day pause (gate order: not-enough → paused → skip
  extension), so an over-sixty-day open cycle still resolves through
  "log it" (issue AC7).
- **Why the skip extension is needed for AC2:** with
  `estimate = lastStart + mean`, omitting a *completed* long outlier can
  only shrink the mean and move the estimate **earlier** — it can never
  clear a late flag. A long outlier produces a false late exactly when it
  is the *current* cycle (day 45 against a 30-day mean), and that case is
  what "skip this cycle" resolves: the estimate moves one full cycle out
  (Jul 27 → Aug 26 in the widget test) and `isLate` recomputes false.
  Omitting a completed outlier still moves the estimate (the other half
  of AC2); clearing a late *via the history list* works when a *short*
  outlier dragged the mean down (the 20-day-cycle widget test).

### U2. Domain: history derivation, confidence, codecs

`lib/domain/prediction/cycle_history.dart` (new)

- `CycleHistoryItem` (start, length, omitted, outlier flags) and
  `deriveCycleHistory` → `CycleHistoryView`: reverse-chronological items
  with the open cycle pinned first (KTD2: omittable-free in the list
  itself), counts, `meanCycleLengthDays` (mirrors the prediction's
  most-recent-three window so the UI never shows two disagreeing
  "averages"), `meanPeriodLengthDays` (mean bleed length over episodes
  whose start is not omitted, the open episode included), and
  `variationDays` (max − min of the averaged lengths).
- `CycleConfidence` mapping, with the thresholds named and documented as
  **provisional** pending real histories (roadmap assumption):
  `kConfidenceMinAveragedCycles = 3`,
  `kProvisionalIrregularSpreadDays = 7`,
  `kProvisionalIrregularValidRatio = 0.6`. Learning wins over irregular
  (below three averaged cycles there is genuinely nothing to estimate);
  otherwise a valid-ratio or spread breach reads irregular.
- Device-local codecs (KTD2): `omittedCycles.<profileId>` (JSON array of
  cycle-start ISO dates, canonically sorted; parsing never throws and
  keeps valid entries around malformed ones) and
  `lateSnooze.<profileId>` (the "remind me in 3 days" date;
  `kLateSnoozeDays = 3`; the resolver reappears on the snooze date
  itself). `CycleExclusionList` is the tiny read-modify-write seam over
  `SettingsStore`.
- Multi-device divergence of the omission list is an accepted v1
  limitation (settled decision) — stated in the UI caption, not synced.

### U3. Services: the omission list joins the streams

- `lib/domain/util/combine_latest.dart` (new): a binary combineLatest
  (`dart:async` has none and the repo avoids rxdart) — emits once both
  sources have fired, re-emits on either, forwards errors, closes when
  both close.
- `CyclePredictionService` gains an optional `SettingsStore`; `watch`
  combines the day-entry stream with the omission-list watch, so the
  estimate — and everything downstream that consumes `watch` (the
  reminder coordinator's replan and the reminder-window publisher) —
  reacts to every omit/restore/skip for free. `current()` reads the list
  once.
- `CycleHistoryService` (new) exposes the same combined stream mapped
  through `deriveCycleHistory`.
- `lib/app.dart` constructs both services with settings and provides
  `CycleHistoryService` and `CycleExclusionList` alongside the existing
  providers.

### U4. UI: history section and late resolver

- `lib/ui/overview/cycle_history_section.dart` (new): the history card —
  confidence chip + plain-language summary, the statistics row (avg
  cycle / avg period / variation, `—` when not computable), disclaimer,
  the reverse-chronological list (open cycle pinned; per-cycle
  Omit/Include for in-window cycles; "Outlier — never averaged" auto-flag
  with no toggle, since a manual omit on top would be a no-op; greyed
  "Excluded from averages" state), the skipped-open-cycle Undo, and the
  device-local caption. Hidden entirely for profiles with no episodes.
- `lib/ui/overview/late_resolver.dart` (new): replaces the late banner in
  both the active-late and the paused states. Three options — Log it
  (opens the ordinary DaySheet on today, via the panel), Skip this cycle
  (appends the open start to the exclusion list), Remind me in 3 days
  (writes the snooze; a one-line "We will check back on <date>." note
  with a Show-options escape hatch replaces the resolver until then).
  Read-only callers see the informational line only.
- `lib/ui/overview/overview_panel.dart`: renders the resolver under the
  estimate (late) and the awaiting card (paused), the history section
  below the state card, and gains the same effective read-only rule as
  `MonthCalendar` (archived **or** accepted viewer role, failing open on
  unknown roles) plus the auth/guardians plumbing that rule needs.
  `ProfileDetailScreen` forwards `readOnly`, `timezoneProvider`, and the
  guardians repository.

### U5. Tests

- Domain: `test/domain/prediction_test.dart` (omission filtering, gate
  degradation, attribution-to-start, skip semantics, pause interplay),
  `test/domain/cycle_history_test.dart` (list order/flags, statistics,
  confidence mapping, codecs, `CycleExclusionList`), and
  `test/domain/cycle_history_service_test.dart` +
  `prediction_service_test.dart` (stream reactions, isolation) and
  `test/domain/combine_latest_test.dart`.
- Widgets: `test/ui/cycle_history_test.dart` walks the issue's acceptance
  checklist (AC1–AC8, snooze, read-only, auth-refresh); the updated
  `test/ui/overview_test.dart` covers the resolver inside the existing
  overview states. The old "no partial numbers" sweep is now scoped to
  the not-enough *card*, because the history card legitimately renders
  recorded dates and lengths (real history, not a partial estimate).

---

## Key Technical Decisions

- **KTD-A. Omission is keyed by cycle start.** The list stores episode
  starts; a length is excluded iff the start of the cycle it belongs to
  is listed. This makes "skip this cycle" (open start) and a later manual
  omit of the same cycle one identical operation.
- **KTD-B. Skip advances the estimate one averaged cycle, purely.** No
  snooze state is involved in clearing the late flag — the estimate is a
  pure function of (episodes, omissions, today), so a skip that is
  later undone restores the old late window exactly (widget-tested both
  directions). "Remind me in 3 days" is deliberately a *separate*,
  display-only snooze: the OS-level late reminders continue per the
  existing pre-arm; the snooze governs the in-app banner only.
- **KTD-C. The displayed average mirrors the predictor's.** The history
  card shows the mean over the same most-recent-three usable lengths
  that drive the estimate, never an all-history mean that would disagree
  with the estimate on screen.
- **KTD-D. Mean period length excludes omitted cycles' episodes** (the
  issue's "exclude this cycle from my averages") but always includes the
  open episode — a skipped cycle's bleed, if any, still happened.
- **KTD-E. Read-only is inherited, not reinvented.** The resolver's Log
  it and the history card's omit controls are hidden for archived
  profiles and accepted viewer-role guardians, reusing
  `acceptedGuardianFor`'s fail-open null-vs-empty discipline from
  `MonthCalendar` (issue #3 gap-closure U6's rule).

## Not Done (deliberate)

- The omission list and snooze do not sync (settled v1 limitation, KTD2);
  a follow-up would need a decision about which table owns them.
- No forecast calendar (roadmap U3) — separate issue, depends on this
  one's confidence shape.
- Provisional thresholds are constants, not settings; they are expected
  to move once measured against real histories.

## Verification

`flutter analyze` clean; `flutter test` 1292 passing;
`dart run tool/quality_gate.dart` PASS (coverage 93.86% ≥ 90%, CRAP gate
clean). Device checklist (two-device divergence of the omission list,
the real snooze against OS reminders) remains a manual check per
`docs/ops/supabase-go-live.md`'s device-checklist posture.
