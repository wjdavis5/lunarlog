---
title: Per-Viewer Guardian Lens (Issue #850) - Plan
type: feat
date: 2026-09-21
issue: wjdavis5/lunarlog#850
artifact_contract: ce-unified-plan/v1
artifact_readiness: ready-for-implementation
product_contract_source: issue-850
execution: code
---

# Per-Viewer Guardian Lens — Plan (Issue #850)

Date: 2026-09-21 · Branch: `opencode-deepseek/850-guardian-lens-plan` · Epic: Sharing / UI-UX (P1)

All paths repo-relative. Line citations were re-verified against this
checkout (tip `86194453`) — where the issue body or the issue's own
analysis comment has drifted, the drift is called out explicitly rather
than copied.

## Context

Every profile in the app renders one UI to everyone. The only
viewer-dependent branch anywhere is `role.canLog → readOnly`, so a parent
opening her daughter's `teen`-mode profile reads "Your next period is
estimated around:" and sees the full subject Today card, and there is no
guardian-facing "is anything needed from me" surface at all. Issue #850
asks for a **per-viewer lens**: the subject keeps today's own-voice
screen; every other viewer (parent, co-parent, caregiver) gets a
guardian logistics card with the headline facts and three quick actions.

The owner approved the direction on 2026-09-20 (issue comment), with three
adjustments: (a) the lens is decided from #802's now-present
`profile_guardians.is_subject` marker plus role, with the
`relationship == self` fallback dropped; (b) because #849's outcome was
**no `full`/`status` tier** — guardians read everything except a note the
subject marks private — every guardian gets the tap-through rather than a
tier-gated reveal; (c) `ProfileMode.caregiver` is retired as a mode (wire
value kept, mapped to `standard`) and reminder presets move from mode to
lens.

The surface this plan describes does not exist yet, and the issue's own
citations have drifted (its `lib/ui/overview/month_calendar.dart`,
`lib/ui/day/day_sheet.dart`, and `lib/ui/analysis/analysis_tab.dart` paths
are now `lib/ui/logging/` and `lib/ui/insights/`). No `GuardianLens` type
exists in `lib/`. The `_teen` second-person copy is still present
(`lib/domain/care_modes.dart:292,294`), and the activity feed's
"counts, not content" discipline is intact
(`lib/ui/sharing/activity_feed_screen.dart:301-327`).

## Numbered decisions

**D-1 — The lens is per membership, from `isSubject` + role, never from
`relationship`.** `ProfileGuardian.isSubject` is the fact
(`lib/domain/models/profile_guardian.dart:96`), server-stamped by the
subject-invitation accept path or `accept_ownership_transfer`
(`supabase/migrations/20260920120000_profile_subject_membership.sql:284-300,596-612`),
synced on the row (`lib/data/sync/remote_rows.dart:245,267`) and defaulted
false on a pre-#802 pull (`lib/data/sync/row_codec.dart:735`). The
resolver is:

```
member = acceptedGuardianFor(guardians, currentUserId)   // :183
lens   = (member != null && !member.isSubject) ? guardian : subject
```

`relationship == ProfileRelationship.self` is deliberately **not** consulted
(and is not used for viewer semantics anywhere today — `profile.dart:152-155`
uses the child relationships only for subject-invite eligibility). No
signed-in membership (a local-only operator, a profile whose guardian rows
have not synced) resolves to **subject**, matching the existing
fail-open-to-the-operator discipline of `_effectiveReadOnly`
(`overview_panel.dart:491-496`). This is presentation only and changes no
permission: a viewer still cannot write.

**D-2 — Two lenses, two front pages.** Subject lens keeps the existing
`_overviewBody` (`lib/ui/overview/overview_panel.dart:618-709`)
unchanged. Guardian lens renders one `GuardianOverviewCard` instead of the
subject card stack: subject name, next-period estimate (date or range +
tier), PMS start when present, last-logged relative age, and a
"nothing due from you" line — then the three quick actions. Subject-only
cards (pregnancy/postpartum/perimenopause/conceive, the irregular
suggestion, the late resolver, the health-deviation card, the
notifications-off hint [the guardian device deliberately has no local
reminders], and the "About this estimate" expander) do not render under
the guardian lens. The shared `kEstimateDisclaimer`
(`lib/ui/overview/estimate_copy.dart:15`) stays at the bottom of both,
because the card carries an estimate.

**D-3 — "Counts, not content" on the card.** The card never names a
symptom, tag code, or note text. It follows the activity feed's rule —
flow *label*, tag *count*, note *boolean*, never text
(`lib/ui/sharing/activity_feed_screen.dart:301-327`). Tags and notes are
one tap in (the day sheet), not on the card.

**D-4 — Every guardian gets the tap-through; no tier.** Per #849's
2026-09-20 owner decision (no `full`/`status` tier; guardians read
everything except a note the subject marks private), the card is a
*default view*, never a gate. The per-note private flag is #849's own
follow-on (not built in the tree today — no `is_private`/`private`
column on `day_entries` or `guardian_notes` in
`supabase/migrations/`), and this lens needs no change when it lands
because the lens already assumes full read. `PRIVACY.md:119` already
states the read-visibility rule, and `:123` the guardian-note rule.

**D-5 — Retire `ProfileMode.caregiver`; keep the wire value.** The enum
member survives as a legacy value exactly as `irregular` does after #853
(`lib/domain/models/profile_mode.dart:9-24`). `choosableModes` drops it
(`:58-62`); `ProfileMode.fromDb('caregiver')` maps to `standard` (`:47-52`);
the `_caregiver` copy (`lib/domain/care_modes.dart:389-401`) is folded into
`_standard` at `_baseCopyFor` (`:434-439`); `profiles_mode_check` keeps
accepting `'caregiver'` (`supabase/migrations/20260908120000_profile_care_modes.sql:41-44`)
so an old client's push is not rejected; a one-statement server backfill
converges stored rows. No Drift schema bump is needed — the read boundary
(`row_codec.dart:627-643`'s `fromDb` → `toDb()` fold) and the next push
converge the local wire string, the #853 precedent
(`lib/data/db/db.dart:1259-1275`).

**D-6 — Reminder presets move from mode to lens.** Today the per-profile
mode alone selects the preset (`lib/domain/notifications/reminder_presets.dart:45-58`,
`caregiver → none` at `:53`) and the coordinator maps it per active profile
(`lib/data/notifications/reminder_coordinator.dart:404-426`). Under the
owner's decision a **guardian device gets no local reminders at all** and
relies on server caregiver alerts (#5); only the subject's device arms
mode presets. So the coordinator gains a subject-profile source and gates
`presets[id]` to `ReminderPreset.none` for a guardian. `caregiver`'s
preset arm becomes `all` (mode is no longer the suppressor).

**D-7 — Third-person on a guardian's device.** `docs/product/voice-and-copy.md:17-21`
rule 2: "You" is the reader, the subject is named or referred to in the
third person, and "your data" must never appear on a surface that may be
guarding someone else's record. Under the guardian lens every subject
second-person string that renders on the guardian's device needs a
third-person variant. Because the care-mode strings are still hardcoded
English in the registry (unlike the #1004-localized ARB strings), the
registry gains a lens-aware variant while ARB strings get new keys.

**D-8 — The guardian's Calendar keeps `readOnly` exactly as it is.** The
lens changes *defaults and voice*, not permission. A `viewer` remains
read-only everywhere (`_effectiveReadOnly`); the guardian-specific
calendar change is only that symptom layers default off and flow on (the
layer toggles already exist on `MonthCalendar`), so the front calendar
answers "when" without a symptom map.

## What a guardian sees, surface by surface (today's only branch)

The complete set of viewer-dependent branches today, all
`role.canLog → readOnly`:

| Surface | Site | Current branch |
|---|---|---|
| Overview / Today | `lib/ui/overview/overview_panel.dart:494-496` (`_effectiveReadOnly`), `:918` (`canLog:`) | read-only only |
| Calendar | `lib/ui/logging/month_calendar.dart:1133-1135` (`_effectiveReadOnly`), passed at `:1342` | read-only only |
| Day sheet | caller passes `readOnly`; labels its reason at `lib/ui/logging/day_sheet.dart:2816-2824` (`_readOnlyReason`), write gate for guardian notes at `:2832-2838`, branch at `:1766` | read-only only |
| Analysis | `lib/ui/insights/analysis_tab.dart:576-578` | read-only only |
| Care | `lib/ui/care/care_notes_screen.dart:162-177` | read-only only |
| Today FAB | `lib/ui/components/today_log_fab.dart:140-141` | hidden if `!canLog` |
| Activity feed | `lib/ui/sharing/activity_feed_screen.dart:394-396` | day sheet read-only |
| Profile picker | `lib/ui/profiles/profile_picker_screen.dart:260,356` | hides log-for-her |
| Home widget | `lib/domain/widget/widget_profile_options.dart:88` | hides the log button |
| Account import | `lib/domain/import/account_import.dart:1499-1500` | exporter/guardian fold |

Under the lens, a guardian additionally gets: the logistics card on
Today (D-2); Calendar symptom layers default off / flow on; and
third-person voice on Calendar, Day sheet, Analysis, and Care. Content is
otherwise identical — guardians read every entry, symptom, tag, care
note, and guardian note (D-4). Analysis keeps its full stats and history
(after #1005, the recap copy is already third-person for the strings it
touched); the subject-only recap gate is D-7/U8.

## Dependencies and adjacent outcomes

- **#802** shipped the `isSubject` marker this lens derives from
  (`supabase/migrations/20260920120000_profile_subject_membership.sql`;
  `lib/domain/models/profile_guardian.dart:96`). Today it drives only
  picker grouping (`lib/domain/sharing/sharing_overview.dart:43,45-50,69`),
  the subject subtitle (`lib/ui/l10n/guardian_role_copy.dart:45-47`), the
  accept-sheet intro (`lib/ui/sharing/accept_invite_sheet.dart:136`), the
  Manage Guardians badge (`lib/ui/sharing/manage_guardians_screen.dart:1506-1513`),
  and the once-per-device teen-mode suggestion
  (`lib/ui/sharing/manage_guardians_screen.dart:199-200`). It drives no
  lens; that is this plan's work.
- **#801 (guardian note) is CLOSED/shipped**:
  `supabase/migrations/20260918150000_guardian_notes.sql`,
  `lib/domain/models/guardian_note.dart`,
  `lib/ui/care/guardian_notes_section.dart`, mounted in the day sheet at
  `lib/ui/logging/day_sheet.dart:2856+`. The card's "Add a note" action
  reuses that path; it is a dependency already satisfied.
- **#851 (supplies) is partially shipped**: the `kind` column and RLS
  posture (`supabase/migrations/20260920130000_supplies_kit.sql:51-54`)
  and the `_SuppliesSection`
  (`lib/ui/care/care_notes_screen.dart:226-239,777+`) exist. The
  ahead-of-time alerts (`period_soon`, `pms_soon`, `restock_due`) are not
  yet built; the card's supplies action reaches the shipped list, and the
  forward-looking detail (e.g. "Restock before ~Sep 24") renders on the
  card once #851's outbox kinds land. This plan must not duplicate #851's
  table or alerts.
- **#849** outcome is folded in per D-4. The re-scoped per-note private
  flag and the "graduated privacy for older teens" epic are separate
  future work; neither blocks this plan.
- **#853** is the precedent for retiring a mode member while keeping its
  wire value (`lib/domain/models/profile_mode.dart:9-24`;
  `supabase/migrations/20260920110000_profile_irregular_framing.sql`).
- **#1005** (CLOSED) already moved some subject second-person strings to
  third person (`completedCycleProgress`, `cycleHistoryOpenCycleNotCounted`,
  `perimenopauseLength*`, `pregnancyExitExclusionBody`). This plan is the
  remaining pass for surfaces the lens now exposes.

## Second-person strings needing a guardian variant

Care-mode registry (`lib/domain/care_modes.dart`, hardcoded English —
still un-localized):

- `_teen.notEnoughTitle` "Your record is just getting started" (`:292`)
- `_teenNotEnoughBody` "Every entry builds the picture of your cycle." (`:81-83`)
- `_teen.nextEstimateLabel` "Your next period is estimated around:" (`:294`)
- `_composedNextEstimateLabel(teen)` "Your next period may start around:" (`:96`)
- `_irregularNotEnoughBody` "… Your estimates may stay ranges rather than dates." (`:88-90`)
- `_composedNotEnoughSuffix(teen)` " Your estimates may stay ranges rather than dates for a while." (`:136-137`)

Localized overview strings (guardian reads these on the subject's profile):

- `overviewStaleHistoryTitle` / `overviewStaleHistoryBody` (`lib/l10n/app_en.arb:764,768`)
- `overviewLongCycleBody` (`:752`)
- `overviewPmsBandLabel` "… before your period …" (`:1652`)
- `overviewIrregularSuggestionBody` (`:1749`)
- `overviewEstimateLoadError` (`:732`)
- `predictionsDisabledBody` "Your cycle history and tracking continue unchanged." (`:1702`)

Day sheet / Analysis / misc:

- `daySheetCycleStartDialogBody` "… you're on cycle day {cycleDay} … your averages and estimates." (`lib/l10n/app_en.arb:491`)
- `cycleRecapUsualRange`, `cycleRecapEstimatesMoreConfident`,
  `cycleRecapEstimatesLessConfident`, `cycleRecapAverageMoved`
  (`:3027,3058,3062,3066`) — the per-cycle recap is subject-facing and
  should be subject-lens only, not merely re-worded.
- `cycleComparisonNotEnoughBody` (`:264`), `cycleConfidenceSummaryProvisional`
  (`:724`) — audit and re-word where the guardian can reach them.
- Hardcoded, **not** in ARB: `lib/ui/insights/analysis_tab.dart:584`
  `'Could not load your cycle analysis.'` and
  `lib/ui/components/today_log_fab.dart:180` `'Log today'` (an l10n debt
  this pass should close while touching the file).

## Units of work

Each unit is sized for one coder (≤ ~400 changed lines including tests)
and carries its own tests. Units are ordered so each lands green on its
own.

- **U1 — Domain: `GuardianLens` + resolver (~150).**
  New `lib/domain/sharing/guardian_lens.dart`: `enum GuardianLens { subject, guardian }`,
  `GuardianLens guardianLensFor(List<ProfileGuardian> guardians, String? currentUserId)`
  per D-1, plus a role accessor delegating to `acceptedGuardianFor`.
  Pure Dart (no Flutter/drift), matching `sharing_overview.dart`'s
  layering. Tests: `test/domain/sharing/guardian_lens_test.dart` —
  subject membership, helper membership, primary-guardian creator
  (`isSubject=false`), null viewer id, empty rows (→ subject), revoked row
  (ignored), role carried through.

- **U2 — Client: retire `ProfileMode.caregiver` (~300).**
  `profile_mode.dart` (drop from `choosableModes`; `fromDb('caregiver') → standard`;
  keep member/`toDb`/`label`/`hint` for the wire), `care_modes.dart`
  (delete `_caregiver` copy and `_caregiverNotEnoughBody`, route the
  `caregiver` arm of `_baseCopyFor` to `_standard`),
  `reminder_presets.dart` (caregiver arm → `all`). Update
  `test/domain/care_modes_test.dart:289,461-463`,
  `test/domain/notifications/reminder_config_test.dart:113-115`, and any
  picker/dialog test asserting three modes. No Drift schema bump (D-5).

- **U3 — Server: caregiver backfill migration + pgTAP (~150).**
  New timestamp-sorted migration under `supabase/migrations/`
  (`update public.profiles set mode = 'standard' where mode = 'caregiver';`
  ordered idempotently, #853's two-statement shape) — `profiles_mode_check`
  and `sync_push`'s `'mode'` allowlist are **not** changed, so an old
  client's `caregiver` push is still accepted. Tests: a pgTAP file
  asserting the backfill, that an old-arity push carrying `mode='caregiver'`
  is accepted, and that the stored wire value survives.

- **U4 — Reminder presets move mode → lens (~300).**
  `ReminderCoordinator` (`lib/data/notifications/reminder_coordinator.dart:63-160,398-426`)
  gains a subject-profile source (new injected dependency; null keeps the
  pre-#850 all-subject default) and gates each `presets[id]` to
  `ReminderPreset.none` when the viewer is not the subject; wiring in
  `lib/app.dart:484-540` and `lib/composition/app_dependencies.dart:613-630`
  feeds the new source from the existing guardians/current-user seams.
  Tests: coordinator/scheduling tests (`test/data/scheduling_test.dart`,
  `test/domain/notifications/reminder_config_test.dart`) proving a
  guardian profile arms nothing while a subject profile arms its mode
  preset, and that a caregiver-mode profile now behaves as standard.

- **U5 — Overview: guardian logistics card + lens branch (~350).**
  New `lib/ui/overview/guardian_overview_card.dart` ("counts, not content"
  per D-3; actions wired to the existing guardian-note sheet, the care
  screen (`CareNotesButton`/`CareNotesScreen`), and supplies), plus the
  `_overviewBody` branch at `overview_panel.dart:618-709` selecting it
  from `guardianLensFor`. Include the bounded last-logged read (prefer a
  latest-entry query over a second full-history subscription; a small
  repository/storage addition is acceptable). Tests:
  `test/ui/overview_test.dart` — subject vs guardian card, no symptom/tag/
  note text, actions present for a logging role and absent for a viewer,
  disclaimer present in both.

- **U6 — Calendar: guardian defaults (~200).**
  `lib/ui/logging/month_calendar.dart` reads the lens (alongside its
  `_effectiveReadOnly` at `:1133-1135`) and defaults symptom layers off /
  flow on for a guardian, leaving the toggles intact. Tests:
  calendar widget tests asserting the guardian default layers and the
  unchanged subject default.

- **U7 — Care-mode registry third-person variants (~350).**
  `lib/domain/care_modes.dart` gains a lens-aware copy path (a
  `GuardianLens`/subject-name parameter on `careModeCopyFor`,
  defaulting to the subject lens) so the strings enumerated above render
  third-person for a guardian; call sites (`overview_panel.dart:281-288`,
  `month_calendar.dart:870`, `day_sheet.dart:575`,
  `analysis_tab.dart:261`) pass the lens. Tests: `care_modes_test.dart`
  subject-vs-guardian variants, and a layering test that the registry
  stays pure Dart.

- **U8 — Remaining copy + recap gating (~300).**
  Add guardian variants for the ARB strings enumerated above, localize the
  two hardcoded strings (`analysis_tab.dart:584`, `today_log_fab.dart:180`),
  run `flutter gen-l10n`, and gate the per-cycle recap to the subject lens
  (`analysis_tab.dart:610-613,666+`). Tests: widget tests asserting the
  guardian sees third-person copy and no recap, plus the subject lens
  unchanged.

## Test plan

- **Unit/domain:** `test/domain/sharing/guardian_lens_test.dart` (U1);
  `test/domain/care_modes_test.dart` and `reminder_config_test.dart` (U2,
  U4, U7).
- **Widget:** `test/ui/overview_test.dart` (U5), calendar tests (U6),
  analysis/care/day-sheet copy tests (U7, U8) — asserting a guardian gets
  no subject card, no symptom names/tag codes/note text, and no recap,
  and that a subject's view is byte-for-byte the pre-#850 copy.
- **Server:** pgTAP `db reset --local` + `test db --local` (U3); the
  derived-allowlist test (`supabase/tests/sync_push_derived_allowlists_test.sql`)
  must stay green because no column/allowlist changed.
- **Gates:** `flutter analyze`, `flutter test`,
  `dart run tool/quality_gate.dart`; `dart run build_runner build
  --delete-conflicting-outputs` only if U5's storage read changes the
  Drift schema (it should not). `database.types.ts` regeneration is **not**
  required (no schema change in U3).

## Out of scope

- The per-note private flag and the graduated-privacy epic (#849's
  re-scoped follow-ons).
- #851's ahead-of-time alert kinds and restock/pms copy (dependency, not
  this plan's work); no new supplies table.
- Any RLS, policy, or grant change — the lens is presentation, never
  permission (D-8).
- Push-notification payload or server alert changes.
- A household roll-up across profiles (#803).

## Open questions

1. **Exact copy and tone of the logistics card** ("nothing due from you",
   the headline phrasing, whether the subject's name or "they" is used) —
   **owner's**, matching `voice-and-copy.md`'s product-writing posture.
2. **What feeds "nothing due from you"** — supplies only, or
   supplies + unchecked visit-prep + a missed-entry signal? — **owner's**
   (it defines the card's promise); the bounded data plumbing is the
   coder's.
3. **Does "Add a note" open the day sheet scrolled to the guardian-note
   section, or a dedicated composer?** — **owner's** (interaction choice);
   the implementation is the coder's.
4. **Should a co-parent with `canEditProfile` get any extra card
   affordance** (e.g. Manage Guardians) beyond the three actions? —
   **owner's**; default in this plan is no extra affordance.
5. **Fail-open lens for a not-yet-synced membership** (a freshly invited
   guardian briefly sees the subject lens until rows arrive) — **coder's**,
   following the existing `_effectiveReadOnly` fail-open; call out in the
   PR rather than block.
6. **Whether the guardian card replaces the whole overview body or sits
   above it** — **coder's**, resolved by D-2 (replace the subject-only
   stack; keep the shared disclaimer).
7. **Bounded "last logged" read shape** (new latest-entry query vs reusing
   `watchForProfile`'s existing stream) — **coder's** engineering call.
