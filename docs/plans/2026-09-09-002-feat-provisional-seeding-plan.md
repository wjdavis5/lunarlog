# Plan — provisional predictions seeded from onboarding cycle facts (Issue #218)

Date: 2026-09-09 · Branch: `feat/218-provisional-seeding` · Epic: Predictions & Insights (P1)

## Context

Issue #218 asks that onboarding-collected cycle facts (last period start,
typical cycle length, typical period length) seed an immediate prediction at a
new **`provisional`** confidence tier, instead of the profile sitting in
`NotEnoughHistory` for the ~4+ months it takes to log `kMinCompletedValidCycles`
(3) real cycles. Clue's model: collect the three facts at setup, show a
prediction immediately, and refine it as real cycles land — "3 past cycles" is
an *accuracy* threshold, not a display threshold.

The boundary (coordinator brief, binding): **#216 owns the first-run form UI.**
This plan is the domain/data side only — the tier, the seeding computation,
storage, refinement displacement, overview rendering hooks, and clean seams the
form (#216) and the profile-settings editor will call. The form itself is not
built here.

Dependency #213 (confidence tiers `high`/`learning`/`irregular`) is landed;
#188's `profile_modes` storage exists (`mode`, `birth_control_method`, …) and is
where the birth-control-method and goal/mode answers route.

## Product contract

1. **New tier: `CycleConfidence.provisional`** — the lowest-honesty rung: an
   estimate computed from onboarding answers, not from logged history.
2. **Seeding** (pure function `seedProvisionalPrediction` in
   `lib/domain/prediction/prediction.dart`): a profile whose facts carry at
   least a last-period date *and* a typical cycle length (both required — a
   next-start date cannot be computed without them; typical period length alone
   is optional and falls back to `kDefaultPeriodLengthDays`) gets an
   `ActivePrediction` with:
   - `estimatedNextStart` = last period start + typical cycle length (rolled
     forward by the existing #221 `_rollLateEstimate` machinery once the
     estimate goes stale — a seeded estimate is never handed out arbitrarily
     far in the past);
   - `meanCycleLengthDays` = the supplied typical cycle length;
   - `meanPeriodLengthDays` = the supplied typical period length (or the
     fallback);
   - `tier` = `provisional` (`irregular` + `unusuallyLongCycle` when the span
     since the supplied start already exceeds `kMaxOpenCycleDays` — same
     never-go-silent posture as #221);
   - a 12-cycle `forecast` built by the existing `_buildForecast`, with a
     **fixed nominal spread** (`kProvisionalSpreadDays = 4.0`, a named
     PROVISIONAL calibration constant like the file's other thresholds) —
     there is no history to compute a standard deviation from, and hiding the
     uncertainty behind `spreadDays = 0` would be the dishonest option;
   - `averagedCycleLengths = const []`, `completedCycleCount = 0`,
     `validCycleCount = 0` — no observed cycles are claimed to exist.
3. **Seeding gate**: the supplied cycle length must lie inside
   `[kMinCycleDays, kMaxCycleDays]` (15–60). Outside that window the engine
   itself would never treat a *logged* cycle of that length as valid, so a
   seeded estimate from it could never be confirmed; the answer is still
   stored and synced (for #188/#233 to consume later), but the profile stays
   `NotEnoughHistory` until real cycles land.
4. **Displacement (no blending)**: `CyclePredictionService` still computes
   from entries exactly as today; only when that result is `NotEnoughHistory`
   does it consult the facts. Once ≥3 valid cycles exist the computed result
   is returned unchanged and `provisional` is never reported again for that
   profile — there is no mixing of onboarding numbers with real data.
5. **No-facts path bit-identical**: a profile that skipped the questions
   (null facts) keeps today's `NotEnoughHistory` — same object, same counts.
   The `kMinCompletedValidCycles` gate for logged-in-anger profiles is
   untouched (#132 lesson).
6. **Disclaimer on every surfaced number** — unchanged: the overview renders
   every estimate (provisional included) next to `kEstimateDisclaimer`.

## Storage (follows the issue's "stored on the profile" direction)

The facts are **profile-scoped columns that sync**, not device-local
`app_settings` — the issue says "stored on the profile", profiles sync, and a
second device or co-guardian must see the same seeded estimate. The
`birth_year`/`relationship` precedent (issue #4, migration
`20260906160000_profile_subject_metadata.sql`) is followed end to end:

| Column | Type | CHECK |
|---|---|---|
| `profiles.last_period_start` | `date` nullable | — (no future-date check: server `current_date` is UTC and would reject a legitimate "today" pick in a ahead-of-UTC zone; the domain clamps `cycleDay ≥ 1` defensively) |
| `profiles.typical_cycle_length_days` | `smallint` nullable | `between 1 and 365` (storage is honest-wide; the *seeding* gate above is the semantic bound) |
| `profiles.typical_period_length_days` | `smallint` nullable | `between 1 and 60` |

- **Local (Drift)**: schema v10 — three nullable columns on `Profiles`, a
  transactional `from < 10` upgrade step, regenerated `db.g.dart`,
  `drift_schemas/drift_schema_v10.json`, and `generated_migrations/`.
- **Domain**: `Profile.lastPeriodStart` (`LocalDate?`),
  `typicalCycleLengthDays`, `typicalPeriodLengthDays` — `copyWith` sentinel
  pattern, equality, hashCode; `ProfilesRepository.create` gains the three
  optional parameters (editability later rides the existing `update(Profile)`).
- **Wire**: `encodeProfile`/`decodeProfile` + `RemoteProfileRow` +
  `LunarLogStorage.upsertProfile`/`_applyProfile` carry the three keys; ISO
  `yyyy-MM-dd` for the date, like `profile_modes.mode_started_on`.
- **Server**: one migration `20260909120000_provisional_cycle_facts.sql` —
  columns + comments + `grant update (…) to authenticated` + `sync_push`
  carried forward from its latest 5-arg body with the three keys added to the
  profile allowlist, the parse block, the INSERT, and the UPDATE (each behind
  a `v_row ? 'key'` containment guard so a pre-#218 client's push never nulls
  a stored fact — the PR #108 item #3 lesson).
- **pgTAP**: `sync_push_test.sql` gains the round-trip / rejection /
  old-client-omission / direct-grant block mirroring the U1 metadata block.

**Birth-control-method and goal/mode answers** (the issue: "captured and
persisted even though their downstream consumers are separate issues") route
into #188's existing `profile_modes` row: a new
`ProfileModesRepository` domain interface + drift implementation
(`save`/`find` over `LunarLogStorage.upsertProfileMode`/`getProfileMode`) is
the seam; nothing here defines a birth-control enum (free text ≤
`kMaxBirthControlMethodLength`, placeholder "none/unspecified" default is the
form's concern) and the mode axis reuses `LifecycleMode` as-is.

## Seams exposed for #216 (documented, no form UI built)

- `ProfileController.createProfile(…, CycleFacts? facts, LifecycleMode?
  lifecycleMode, String? birthControlMethod)` — the one-call seam: creates the
  profile with facts, then lazily creates/updates the `profile_modes` row.
- `ProfileController.renameProfile(…, CycleFacts? facts)` — the
  profile-settings edit path (facts ride `ProfilesRepository.update`).
- `CyclePredictionService(…, profiles: ProfilesRepository?)` — the service now
  combines the profile's facts into every emission (null keeps the exact
  pre-#218 behavior; the #197 memoisation key gains a facts stamp).

## Overview hooks

- `_estimateDateText` already renders a range for every non-`high` tier —
  provisional renders `estimatedNextStart ± kProvisionalSpreadDays` for free.
- The tier caption and the TodayCard confidence chip route through
  **AppLocalizations** (`cycleConfidenceProvisional` etc.; the three existing
  tiers' ARB values are character-identical to the current domain literals so
  copy parity holds — asserted in `test/ui/l10n_test.dart`).
- `LunarLogColors.confidenceProvisional` (steel blue, fixed hue like the other
  confidence badges) + arms in every exhaustive `CycleConfidence` switch
  (`today_card`, `month_calendar.forecastBandOpacity`, `cycle_history_section`
  color fallbacks). `_stepTierDown` floors at `provisional` — there is no lower
  honest rung ("irregular" claims observed variation a seeded estimate does
  not have).

## Tests

- `test/domain/provisional_seeding_test.dart`: seeding math (next start,
  means, forecast anchor, tier), partial answers (no date / no cycle length /
  no period length), out-of-window refusal, stale-facts roll-forward +
  `unusuallyLongCycle` forced `irregular`, `cycleDay` clamping, displacement
  (facts + 3 real cycles → computed tiers only, `provisional` never returned;
  facts + <3 cycles → seeded).
- `test/domain/prediction_service_test.dart`: repository-seeded provisional
  emission, re-derivation on a facts edit, memoisation keyed on facts,
  no-repository bit-identical behavior (existing groups unchanged).
- `test/data/db_test.dart` + repository tests: create/update round-trip of the
  three columns; schema-v10 upgrade preserves rows.
- `test/data/row_codec_test.dart`: encode/decode round-trip; old-client payload
  without the keys decodes to nulls.
- `test/ui/l10n_test.dart`: parity assertions for the new ARB keys.
- pgTAP: the sync_push block above (CI `db-tests`).
- Existing prediction suite must stay green unchanged (no-regression gate).

## Not in scope

- The first-run form and profile-settings editor UI (#216).
- Birth-control vocabulary/enum (#233/#260) and mode-aware prediction changes
  (#192/#196/#204) — only the persisted answers land here.
- Any blending of provisional numbers with real cycles (explicitly rejected).
