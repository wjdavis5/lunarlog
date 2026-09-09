# Plan — Period-starting-soon, fertile-window-soon, and cycle-statistic-change reminders (Issue #178)

Date: 2026-09-07 · Branch: `feat/178-reminder-kinds` · Epic: Reminders (P1)

## Context

Issue #178 completes the Clue "Your Cycle" catalogue beyond #136's per-type
architecture: **period-starting-soon**, **fertile-window-soon**, and
**cycle-statistic-change** reminders, plus the three-group settings layout
(Your Cycle / Your Birth Control / Other Reminders). Dependencies are all
landed: #136 (per-type `ReminderKind`/`ReminderConfig`/coordinator/action
executor — this work **extends** it, never forks), #143 (fertile-window
estimation), #213/#132/#220 (spread, tiers, and the displayed averages).

Out of scope, per the issue's own coverage table: the birth-control method
reminder (#183, REM-6) — the settings layout carries its group header and a
clear placeholder tile, nothing more. The caregiver alert path (#125/#5) is
untouched. No schema or migration changes: all new state is device-local
settings, same posture as #136's configs.

## Product contract

1. **`periodStartingSoon`** (Clue item 1): a kind distinct from the period-due
   reminder (`upcoming`), independently toggleable/configurable, defaulting to
   a **4-day** lead (`kPeriodStartingSameLeadDays` is not a thing — 4 is
   deliberately longer than due's 2, by construction and by constant
   documentation) against the same `estimatedNextStart` anchor.
2. **`fertileWindowSoon`** (Clue item 4): arms against the next **still-ahead**
   fertile window derived by #143's own `fertileWindowFor` over
   `ActivePrediction.forecast` — never a second window formula. No computed
   window ahead ⇒ no reminder (the AC's "cannot fire without a computed
   window"); no prediction at all ⇒ nothing, like every estimate-relative
   kind.
3. **`cycleStatisticChange`** (Clue item 5): fires on the day a **meaningful
   change** in the app's own displayed statistics is observed between
   successive live predictions:
   - the displayed confidence tier changes (any `CycleConfidence` transition),
     or
   - the displayed mean cycle length moves by ≥
     `kStatisticChangeMinCycleLengthShiftDays` (2) days, or
   - the displayed mean period length moves by ≥
     `kStatisticChangeMinPeriodLengthShiftDays` (1) day.
   Snapshots compare **rounded display values** (`meanCycleLengthDays.round()`
   etc. — "the app's own displayed averages", not raw doubles), and detection
   is transition-driven: the coordinator compares each new
   `ActivePrediction` emission against the stored per-profile baseline at its
   next replan — the prediction stream is the change signal, no polling timer.
   Thresholds are PROVISIONAL named constants, calibrated never (Clue does not
   publish its own), same posture as #213's.
4. **Per-type configuration**: each new kind is a `ReminderTypeConfig`
   (toggle, time-of-day, lead where anchored) in `ReminderConfig`, JSON
   round-tripped with the same tolerant decode; **all three ship off** so
   every existing profile's plan is byte-identical until the operator opts in
   (the same call #136 made for PMS-watch and the log nudge).
5. **Three-group settings layout** (Clue's IA): Your Cycle (period starting
   soon, period due, PMS watch, period late, fertile window soon, cycle
   statistic changes), Your Birth Control (#183 placeholder), Other Reminders
   (daily log nudge). Every kind keeps its own toggle/lead/time rows.
6. **Generic notification copy only** (AC 6): `kReminderTitle`/`kReminderBody`
   are untouched and shared by every kind; the payload gains nothing (kind
   name only, already generic). The fertile-window/statistic notifications
   carry **no action buttons** — "Started"/"Spotting" assert a period that a
   fertility or statistics nudge does not claim; the period-anchored kinds
   keep #136's buttons unchanged. Settings-screen copy moves to the ARB
   (`app_en.arb` + `flutter gen-l10n`, committed generated files).

## Key technical decisions

- **`CycleStatisticSnapshot`** (`lib/domain/notifications/statistic_change.dart`,
  new, pure Dart): rounded means + tier, `fromPrediction`, tolerant JSON codec,
  and `isMeaningfulStatisticChange`. The coordinator (sole detector) keeps
  baselines and change-signal dates in the device-local store via two new
  `SettingsKeys` (`reminder_statistic_baselines`,
  `reminder_statistic_change_signals`) through `ReminderConfigService` — so a
  change observed after a restart (sync landing overnight, a back-dated log)
  still fires that day, and a re-detection cannot double-fire (baseline updates
  with every observation; the signal is one date per profile, and the stable
  notification id makes same-day replans idempotent).
- **Planner input**: `planReminders` gains
  `statisticChangeSignals: Map<String, LocalDate>` — plans one reminder on the
  signal date, gated on the kind's toggle, riding the existing quiet-hours
  shift, same-day coalescing (a same-day late/upcoming reminder outranks it and
  the day's slot is lost, not deferred — accepted, rare), and the
  `kMaxPendingReminders` cap (eviction priority extended: late > upcoming >
  periodStartingSoon > PMS-watch > fertileWindowSoon > statisticChange > log —
  the daily nudge stays the most evictable).
- **Fertile anchor**: first forecast cycle whose `windowStart − lead` is still
  future — the same pre-arm-ahead posture every other kind uses against iOS's
  no-Dart-callback delivery. `estimateFertileWindow` (the *next* cycle's
  window) is often entirely in the past by mid-cycle, so the forecast walk is
  the correct anchor, and it reuses #143's shared `fertileWindowFor` core (no
  second formula, per that file's own invariant).
- **Persistence migration-free**: stored configs without the new keys decode
  to the off defaults (tolerant `fromJson`); older app versions reading a
  newer store ignore unknown JSON keys' effects the same way.

## Test plan

- Unit: snapshot equality/round-trip/tolerant decode; each threshold
  fires/doesn't (tier change, ±2 cycle days, ±1 period day, sub-threshold
  moves, identical snapshots); planner arms `periodStartingSoon` at its lead,
  `fertileWindowSoon` at the next ahead window (and nothing when every window
  is past/no prediction), statistic-change on the signal date only;
  coalescing/cap with the new kinds; defaults keep the pre-#178 plan.
- Coordinator: an emission that moves displayed statistics ≥ threshold records
  a signal and plans the same-day notification once; a sub-threshold move
  plans nothing; baselines persist through the service; disabled kind plans
  nothing.
- Widget: three group headers render; new toggles persist per profile;
  birth-control placeholder present; existing tests re-pointed at the ARB
  delegates.

## Quality gates

`flutter analyze`, `flutter test`, `dart run tool/quality_gate.dart` (90%
line floor, CRAP ≤ 10) — all must pass before the PR.
