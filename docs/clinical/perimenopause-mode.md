# Perimenopause mode (Issue #196)

This document is the written record for Perimenopause mode
(`profile_modes.mode = 'perimenopause'`): what the mode computes, where its
symptom vocabulary comes from, and — Issue #196's acceptance criterion AC5 —
the decision that reconciles it with Issue #131's `irregular` care mode.
It is the linked doc the issue's "written reconciliation decision" requires;
the implementation (`lib/domain/perimenopause.dart`, the Cycle View card,
the day-sheet category order) must stay in step with it.

## What the mode changes

`profile_modes.mode` is the **life-stage axis** (Issue #188): it varies what
the app computes and tracks. Perimenopause mode is for cycles that are
legitimately, naturally irregular, so:

1. **Period prediction is suppressed.** `prediction_service.dart`'s
   `_suppressesPrediction` already returns `PredictionsSuppressed` for
   `perimenopause` (Issue #528). There is therefore no days-late countdown
   and no next-period estimate to show, and none is fabricated.
2. **The Cycle View leads with comparison, not lateness.** The
   `PerimenopauseCard` (`lib/ui/components/perimenopause_card.dart`) selects
   the profile's last two cycles (`perimenopauseComparisonStarts`) and shows
   a cycle-to-cycle change summary — length change and bleed-day counts —
   with a button into Issue #235's full side-by-side comparison
   (`CycleComparisonScreen`). It reuses #235's data shaping
   (`deriveCycleComparison`); it does not build a second comparison surface.
3. **The fertile-window estimate is hidden.** `suppressesFertileWindow`
   gates the calendar band, its legend entry, and the explainer — a
   precise-looking ovulation window is the same false precision the mode's
   posture avoids. Prediction suppression (#528) already removes the
   forecast band; this makes the gate explicit and perimenopause-specific.
4. **The perimenopause symptom vocabulary is surfaced first.** The day sheet
   reorders its categories (`perimenopauseCategoryOrder`) so
   `hot_flashes`, `sleep`, `energy`, `mind`, and `feelings` come first. Like
   every other life-stage reordering, this only reorders — it never hides a
   category.

## Where the symptom vocabulary comes from

Clue Perimenopause launched with "14 brand-new tracking options"
(`support.helloclue.com/hc/en-us/articles/13059487439261`,
`helloclue.com/articles/menopause/introducing-clue-perimenopause`). Only
five are named in any source this repository's research could reach — **hot
flashes, night sweats, brain fog, HRT, and vaginal dryness** — and those
five shipped as codes under `TagCategory.hotFlashes` in Issue #456
(`lib/domain/tags.dart`). The remaining ~9 options are not publicly
attested, so they are deliberately **not invented** (the same
"no invented placeholder" discipline `kUnverifiedTagCategories` documents).
`perimenopauseCategoryOrder` therefore prioritizes the categories that carry
the mode's symptom vocabulary rather than pretending to enumerate options
that do not exist.

**`hot_flashes` itself is a top-level category available in every mode**,
not gated behind Perimenopause mode — per Clue's own scoping
(`support.helloclue.com/hc/en-us/articles/23179959665821`). This mode only
reorders it; it is never conditionally removed.

## Reconciliation with Issue #131's `irregular` care mode (AC5)

Issue #131's `irregular` care mode and this `perimenopause` life-stage mode
describe overlapping users from two different angles, and a shipped app
cannot leave the overlap undecided. The decision:

> **The two axes remain fully independent. There is no automatic coupling in
> either direction.**

- Entering Perimenopause life-stage mode does **not** change
  `profiles.mode` to `irregular`. Entering `irregular` care mode does **not**
  change `profile_modes.mode` to `perimenopause`.
- A profile may be in **any** care-mode framing while in Perimenopause
  life-stage mode (e.g. `perimenopause` + `caregiver` for the person helping
  her, or `perimenopause` + `teen` for a young person with premature ovarian
  insufficiency), and a profile may be in `irregular` care mode while in
  Period Tracking life-stage mode. Both combinations are valid.
- When both are set, they compose without conflict: the **care mode owns
  vocabulary and framing** (status labels, estimate wording — and it is the
  axis that silences the late banner and tier caption for `irregular`), while
  the **life-stage mode owns what is computed and laid out** (prediction
  suppression, the comparison-first Cycle View, the fertile-window gate, the
  category order). Where the two overlap — both exist to avoid false
  precision for irregular cycles — the suppressions are a union: either axis
  can silence a surface, and nothing re-enables it.

**Rationale.** Issue #188's binding orthogonality note ("this axis is
separate from #131's care modes ... both are per-profile, both sync, they
compose, and the two enums are never merged") already settles the model. The
temptation to auto-default one axis from the other would silently rewrite a
guardian's chosen care framing the moment a life-stage mode changed, and
would make `care_modes.dart`'s "mode is presentation, not permission"
guarantee conditional. Keeping them independent preserves both issues'
contracts: `irregular` stays a *vocabulary* choice and `perimenopause` stays
a *life-stage* choice, and neither can silently flip the other.

**Consequence for callers.** Any future surface that wants to know "should
this profile avoid false-precision cycle framing?" must ask **both** axes,
not infer one from the other — the same union rule the paragraph above
states. No client code currently infers one from the other, and a
`test/domain/perimenopause_test.dart` case pins that the life-stage mode
never consults `ProfileMode`.

## Health Platform Sync placeholders

`HKCategoryTypeIdentifier.menopausalState` and
`.bleedingAfterMenopause` are listed as `futureCandidate` entries in the
Health Platform Sync type registry (`lib/domain/health/health_type_registry.dart`).
No write path is implemented (A3-15). For whoever implements them later:
`menopausalState` is a point-in-time category sample whose start and end date
must be **identical** (HealthKit rejects a save where they differ, unlike the
interval samples the registry otherwise names), and
`.bleedingAfterMenopause` is an interval sample carrying
`HKCategoryValueVaginalBleeding`.
