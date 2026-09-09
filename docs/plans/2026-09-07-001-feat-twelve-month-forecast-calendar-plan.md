---
title: Twelve-Month Forward Calendar with Predicted Bleed Bands and Symptom Layers - Plan
type: feat
date: 2026-09-07
issue: wjdavis5/lunarlog#133
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-133
execution: code
---

# Twelve-Month Forward Calendar with Predicted Bleed Bands and Symptom Layers - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written after implementation to record what shipped and
why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** Make the calendar answer forward-looking questions —
  twelve months of forward navigation, predicted bleed bands rendered
  distinctly from logged fills (hatched vs. solid, confidence-weighted),
  cycle-day numerals on the first predicted cycle only, PMS/cramps badges
  at fixed offsets off the active estimate, symptom layers (up to three,
  defaulting to the profile's most-used tags), a read-only explainer for
  future cells, and a keep-logging strip when no estimate is active.
- **Means:** Two new pure-Dart domain modules (`lib/domain/prediction/forecast.dart`,
  `lib/domain/symptoms/symptom_layers.dart`) plus a rework of
  `lib/ui/logging/month_calendar.dart`. No schema, no migration, no sync
  model, no server changes; every per-cell flag is derived per stream
  emission.
- **Authority hierarchy:** Issue #133 owns intent; the roadmap
  ([`2026-09-04-0738-feat-target-state-roadmap-plan.md`](2026-09-04-0738-feat-target-state-roadmap-plan.md)
  R1/R2/R3, KTD7/KTD8) owns the settled shape; the coordinator brief
  (stale PRIVACY.md note, confidence-weighted bands, screen-reader
  semantics, future cells non-loggable, no persisted state) governs where
  the issue left room.
- **Stop conditions honored:** Future cells never open the day sheet
  (KTD8); no persisted forecast/layer state (derive per emission); bleed-
  estimate and symptom-history rendering only — no fertility or ovulation
  overlays and no fertility vocabulary (the brief retires PRIVACY.md's old
  guarantee but keeps this issue's scope unchanged); `lib/domain` stays
  pure Dart.

---

## Key Technical Decisions

- **KTD1 — Forecast generation is interim and swappable.** Issue #213
  (open) owns rebuilding the prediction engine to emit
  `forecast: List<PredictedCycle>`. Its parity-audit comment asks this
  issue to consume rather than re-derive. #213 has not landed, and the
  coordinator brief binds this issue to proceed on #132's
  `ActivePrediction`/`CycleConfidence`. `deriveForecast` is therefore a
  minimal, pure, single-purpose chaining derivation (estimated next start
  + mean cycle length, one cycle per step) isolated in its own module so
  #213 replaces one function, not the calendar.
- **KTD2 — Horizons.** Forward navigation allows exactly twelve months
  past the current month (`kForwardMonthLimit`). Forecast cycles are
  derived until their start passes the end of the navigable horizon, so
  bands cover every navigable month even for short (15-day) cycles; a
  defensive `kForecastMaxCycles` (32, unreachable at the 15-day minimum)
  bounds the loop.
- **KTD3 — Past stays factual.** `forecastDayCells` emits nothing at or
  before today, and the widget renders forecast markers only on future
  cells with no logged entry. A logged day always renders as logged.
- **KTD4 — Confidence weight.** Cycle 0 carries the history's
  `CycleConfidence`; every later cycle steps down one tier (`high` →
  `learning`; `learning`/`irregular` floor) because uncertainty
  compounds. The band's hatch opacity maps from that per-cycle tier
  (`forecastBandOpacity`): high 0.9, learning 0.6, irregular 0.35.
  Spread (`variationDays` + one day per cycle out, provisional) is shown
  in the explainer text only, not drawn.
- **KTD5 — Numerals chain nowhere.** Cycle-day numerals render across the
  *first predicted cycle only* (the one starting at
  `estimatedNextStart`, numeral = day − start + 1 over the full cycle
  length), never on later cycles.
- **KTD6 — Badges are fixed offsets (roadmap KTD7).** PMS covers
  estimate − 7 … − 1; cramps covers estimate − 2 … + 2; only while an
  estimate is active, only on future days.
- **KTD7 — Semantics now, not later.** Every day cell carries a
  `Semantics` label distinguishing logged bleed, logged symptoms, plain
  unlogged, predicted period day (with cycle day and tier), predicted
  PMS/cramps window, and plain future — the distinction #138 will build
  on, in both themes.
- **KTD8 — Layer defaults are derived, selection is ephemeral.** The
  active layer set initializes to the profile's three most-used tags
  (recomputed per emission until the operator first toggles); toggles
  live in widget state only. At most three layers may be active; a
  fourth is refused with a snackbar. The query shape
  (`rankTagUsage`/`defaultLayerTags`) is a reusable pure module, the
  app's first "query over history" seam.
- **KTD9 — Services are optional seams.** `MonthCalendar` reads
  `CyclePredictionService?`/`CycleHistoryService?` from context when
  present (omission-aware, matching the overview's estimates) and falls
  back to deriving from its own entry stream otherwise, mirroring the
  existing nullable-provider discipline (`AuthController?`,
  `LunarLogStorage?`).

---

## What Shipped

### U1. Domain: forecast derivation

`lib/domain/prediction/forecast.dart`

- `ForecastCycle` (start, periodLengthDays, spreadDays, tier, index),
  `deriveForecast({prediction, history, today})`, and
  `forecastDayCells({cycles, today})` producing a per-ISO-date
  `ForecastDayCell` (predictedBleed, cycleDayNumber, pmsBadge,
  crampsBadge, tier, cycleIndex) for days strictly after today only.
- Constants: `kForecastHorizonMonths`, `kForecastMaxCycles`,
  `kForecastSpreadGrowthPerCycle`, `kDefaultPredictedPeriodDays` (4,
  provisional), `kPmsLeadDays` (7), `kCrampsLeadDays`/`kCrampsTrailDays`
  (2/2).

### U2. Domain: symptom-layer query

`lib/domain/symptoms/symptom_layers.dart`

- `rankTagUsage(entries)` (count desc, taxonomy order on ties),
  `defaultLayerTags(entries, {max: 3})`, and
  `layerMatches(entry, tag)` — the reusable history-query seam.

### U3. UI: the forward calendar

`lib/ui/logging/month_calendar.dart`

- Forward navigation capped at today's month + 12; badge/band/numeral
  rendering per KTD3–KTD6; hatched (CustomPaint) vs. solid fills;
  brightness-aware layer/badge palettes; symptom-layer chip panel
  (collapsible, FilterChips over the taxonomy); read-only future-day
  explainer bottom sheet (`kRouteFutureDayExplainerScreen`, registered);
  keep-logging strip under `NotEnoughHistory`/`PausedAwaitingNextPeriod`;
  `Semantics` labels per KTD7.
- `lib/observability/route_names.dart`: `kRouteFutureDayExplainerScreen`
  added to the registry.

### U4. Tests

- `test/domain/forecast_test.dart`: cycle chaining, tier degradation,
  spread growth, horizon coverage and cap, per-day cells (band clamping
  at today, first-cycle-only numerals including non-bleed days, badge
  windows, overlap, nothing in the past), band opacity mapping.
- `test/domain/symptom_layers_test.dart`: ranking, tie-breaks, defaults,
  unknown-code tolerance, matching.
- `test/ui/forecast_calendar_test.dart`: AC1–AC7 walked end-to-end
  against the issue checklist (12-month navigation and cap, bands six
  months ahead distinct from logged fills, numerals first cycle only,
  layer toggling and three-layer cap, most-used defaults, explainer not
  day sheet on future tap, keep-logging strip with no bands, semantics
  distinct, both themes).
- `test/ui/logging_test.dart`: the two tests asserting the removed
  old-world behavior (forward nav disabled at the current month;
  generic symptom-only dot when the day's tags form the default layer)
  updated to the new contracts.

---

## Not Done (explicitly out of scope)

- #213's engine-side forecast (recency windows, per-cycle confidence
  calibration) — this plan's `deriveForecast` is the interim seam it
  replaces.
- Fertility/ovulation overlays (#143) and any a11y work beyond the
  semantic labels (#138).
- Visual review on physical small/large phones (needs a device; the
  widget tests cover both brightness themes at two viewport sizes).
