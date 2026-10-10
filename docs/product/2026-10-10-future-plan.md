# lunarlog future plan, October 2026

This plan defines the product's next phase and tracks it in GitHub issues. It follows `2026-10-10-product-review.md`, which grounds the current state in the repository. The plan acts on three fronts: release proof, privacy completeness, and the family-sharing differentiator. Everything else waits.

## The thesis

Success is a working public release with proof, not more surface. lunarlog already has the feature set and the test depth. What it lacks is a green Android path, run device checklists, a closed privacy gate, finished launch operations, and documents that match reality. The differentiator worth deepening is the family collaboration, and two designed features wait there. New feature bets, a second clinical serializer, and an AI connector all wait behind release proof. Spending the next phase on finishing is cheaper and more certain than spending it on widening.

## Priority order

P0, release proof.

- #1791 Get one green Android internal-track release. The workflow has never succeeded.
- #1505 Close the migration approval hole so a push cannot reach production before the run is approved.
- #22, #29, #725 Run the device checklists. Owner and device work.
- #1797 The release readiness umbrella tracks the whole submission and closes when every box is checked.

P0, privacy gate. Close before any submission.

- #1501 and #1705, the two open privacy bugs.
- #782 The health-consent column. AGENTS.md already describes it as promised by #188, and it does not exist.

P1, launch operations.

- #970 Custom SMTP. Without it, sign-ups are capped and only team addresses receive mail.
- #1093 Console steps for the web client.
- #1100 Console steps for the site.
- #19 Sentry project and DSN, so crash reporting stops being inert.
- #1261 Confirm the App Store Connect key.

P1, deepen the differentiator.

- #850 Guardian lens, ready for implementation. The positioning doc names family collaboration as the differentiator, and this is the designed next step.
- #1048 Teen privacy, awaiting the owner's decision. It gates a real audience.

P2, quality.

- #1792, #1793, and #1794 were closed on 2026-10-10. Verification found the areas already carry behavior tests, so the units were retired instead of written. The review's correction paragraph has the details.
- Documentation truth. This run fixes the drift list in the review.

P2, web client.

- #1795 First-run onboarding.
- #1796 Insights surface.

P3 and deferred, with reasons.

- #1107 Inbound email worker. Implementation-ready, but it serves support flows that matter after SMTP and launch.
- #161 C-CDA output stays deferred. PDF and FHIR cover the realistic consumers.
- #117 AI connector deferred. No user evidence, and it widens the surface before the core is proven.
- #30 Passkeys stay blocked on a relying-party domain. #738 MFA stays off by the owner's product call.

## What this plan will not do

- No new feature bets before the release proof exists.
- No second clinical serializer.
- No AI connector.
- No re-enabling MFA without a security trigger.
- No new platform surface. The web client and the site are enough for now.

## Issue map

| Initiative | Issue | Priority | Who moves it |
|---|---|---|---|
| Android internal release | #1791 | P1 | Agent investigates and fixes, owner dispatches |
| Migration approval hole | #1505 | P1 | Owner process call, agent can draft the workflow fix |
| Device checklists | #22, #29, #725 | P1 | Owner and device |
| Release readiness umbrella | #1797 | P1 | Owner, tracked |
| Privacy bugs | #1501, #1705 | P1, P2 | Owner decision, then agent |
| Health-consent column | #782 | P1 | Owner decision, then agent |
| Custom SMTP | #970 | P1 | Owner console |
| Console steps | #1093, #1100 | P1 | Owner console |
| Crash reporting | #19 | P1 | Owner project, then agent |
| App Store Connect key | #1261 | P1 | Owner |
| Guardian lens | #850 | P1 | Agent after the owner's go |
| Teen privacy | #1048 | P1 | Owner decision |
| Account UI tests | #1792 | P2 | Closed, already covered |
| Insights UI tests | #1793 | P2 | Closed, already covered |
| Prediction core tests | #1794 | P2 | Closed, already covered |
| Documentation truth | this run's drift fixes | P2 | Agent |
| Web onboarding | #1795 | P2 | Agent, owner adjusts the flow |
| Web insights | #1796 | P3 | Agent |
| Inbound email worker | #1107 | P3 | Deferred |
| C-CDA | #161 | P3 | Deferred |
| AI connector | #117 | P3 | Deferred |

## Execution in this run

Order for the 24-hour run that produced this plan. File the plan (done, #1791 through #1797). Commit the review and this plan. Fix the documentation drifts. Then work the first P0 item an agent can move, the Android release investigation in #1791. Each unit lands as its own pull request through the repository gates. Work that needs the owner's console access, a device, or a dispatch is parked in #1797 with the exact steps. The run trail records each decision.

## How to read the issues

Existing issues keep their numbers and labels. New issues from this review carry the `roadmap` label and were filed on 2026-10-10. An issue with `needs-human-review` waits on a decision or access only the owner can provide. Everything else is available for an agent to pick up.
