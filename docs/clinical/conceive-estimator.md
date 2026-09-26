# Conceive-mode conception estimator (Issue #204)

This document is the written evidence basis for the per-day conception
likelihood shown in Conceive mode (`profile_modes.mode = 'conceive'`). The
in-app copy (`kConceiveEvidenceBasis` / `kConceiveDisclaimer` in
`lib/ui/overview/estimate_copy.dart`) and the implementation
(`lib/domain/conceive.dart`) must stay in step with this file; the issue's
acceptance criteria require the evidence basis to be stated both in the UI
and in code/docs.

## What Clue does, and what lunarlog ships instead

Clue's Conceive mode uses **Dynamic Optimal Timing (DOT)**, a proprietary
model developed by the Institute for Reproductive Health at Georgetown
University. DOT is not published in a form lunarlog can license or
reproduce, so this build ships a **documented substitute** rather than
claiming parity with an algorithm it cannot name, cite, or verify. That
distinction is stated in-app, not only here.

## The substitute: Wilcox, Weinberg & Baird (1995)

The estimator uses the day-by-day conception probabilities reported by
Wilcox, Weinberg & Baird, *"Timing of sexual intercourse in relation to
ovulation"*, **N Engl J Med** 1995;333(23):1517-1521
([doi:10.1056/NEJM199512073332301](https://doi.org/10.1056/NEJM199512073332301)).
These are the population-average probabilities of a clinical pregnancy
following a single act of intercourse on a given day relative to ovulation:

| Day relative to ovulation | Probability |
| ------------------------- | ----------- |
| −5                        | 0.10        |
| −4                        | 0.16        |
| −3                        | 0.14        |
| −2                        | 0.27        |
| −1                        | 0.31        |
| 0 (ovulation)             | 0.33        |

The study reports that conception occurred only during the six-day period
ending on the estimated day of ovulation, so there is no published
probability for the day after ovulation and the curve ends at day 0. (The
0.10 point estimate belongs to day −5, not to any day after ovulation.)

The table is a named constant (`kConceptionProbabilityByDayOffset`) in
`lib/domain/conceive.dart`, not inline literals, so the numbers and this
record cannot drift apart.

## How the window is anchored

The estimator is pure calendar arithmetic over the same period-start history
`lib/domain/prediction/prediction.dart` already predicts the next period
from. Estimated ovulation is the predicted next period start minus
`kDefaultLutealPhaseDays` (14 days — Clue's own published constant, shared
with issue #143's fertile-window estimate so the two can never disagree about
the luteal assumption). The cited days −5 … 0 then land on their civil
dates. The estimate carries the **same `CycleConfidence` tier** as the
period estimate it is derived from — it never invents a second confidence
vocabulary (the #213/#143 rule).

## Distinction from #143's fertile-window estimate

Issue #143 answers "which days are around the estimated ovulation day" with a
**binary window**. This estimator answers "how likely is conception from
intercourse on each day" with a **per-day probability curve**. They share the
ovulation anchor but never share a derivation. Both disclaimers render next
to the Conceive curve, plus a line naming which estimate the reader is
looking at.

### One-day difference between fertile window and conception curve (Issue #898)

The calendar fertile window (`kFertileWindowLeadDays` = 5, `kFertileWindowTrailDays` = 1)
spans ovulation −5 … +1, providing a 7-day binary window with a 1-day trailing cushion
after estimated ovulation to absorb ovulation-timing uncertainty. In contrast, the
conception curve spans ovulation −5 … 0 (6 days), ending strictly on estimated
ovulation day based on the empirical findings of Wilcox 1995. Thus, the calendar
fertile window extends 1 day longer than the conception curve for the same cycle.
Both estimators remain faithful to their respective bases, and `kConceiveDisclaimer`
explicitly notes this distinction in the UI.

## What this estimator must never do

**It is computed from period start dates alone.** Clue deliberately keeps DOT
working from period dates alone; ovulation-test results, discharge
observations, and basal body temperature readings are logged for the user's
own reference and **must not feed this curve** (those signals narrow
confidence for the #143 Period Tracking estimate only). The implementation
enforces this by construction — `conceiveEstimateFromHistory` takes only day
entries, reads only their flow-carrying dates, and accepts no observation or
measurement input. `test/domain/conceive_test.dart` pins that logging an
ovulation test or a discharge/BBT signal leaves the curve byte-for-byte
unchanged.

## Safety

This likelihood **must not be used to prevent pregnancy**. It is not birth
control and not a backup to birth control. It is not a test or a diagnosis,
and it cannot tell anyone whether they are fertile today. It is a
population-average study applied to a calendar estimate, and it has not been
validated as a personal prediction. Every surface that renders it carries
`kConceiveDisclaimer` (and the #143 `kFertileWindowDisclaimer`) in full; the
disclaimer is never softened or omitted.
