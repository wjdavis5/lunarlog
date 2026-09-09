---
title: Onboarding - Identity/Value Cards and Cycle Questions in First Run - Plan
type: feat
date: 2026-09-09
issue: wjdavis5/lunarlog#216
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-216
execution: code
---

# Onboarding - Identity/Value Cards and Cycle Questions in First Run - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written alongside implementation to record what shipped
and why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** Replace lunarlog's one-sentence first run (B-22) with
  Clue-shaped onboarding: three skippable cards (identity/value,
  profiles-and-guardians with a truthful minor-checkbox explanation, the
  existing data/sync notice) before the existing name form, and the five
  cycle questions (last period date, typical cycle length, typical period
  length, birth-control method, goal/mode) after it (A2-41).
- **Means:** All inside `FirstRunScreen`'s existing step machine — the
  intro cards replace the single-notice step (gated by the same
  `firstRun_notice_shown` flag), and the cycle questions are a new step
  between the name form and profile creation, so the home gate's
  zero-profiles decision is untouched. All new copy goes through
  `AppLocalizations`/ARB (#340 pattern); the copy-parity suite gains the
  first-run entries.
- **Authority hierarchy:** Issue #216 owns the card list, the
  cycle-question table, and skippability; #218 (Predictions & Insights)
  owns the domain meaning of the cycle answers — per #216's own
  assumption this issue is UI-scoped and must not invent prediction
  seeding; #131/#188 (both landed) define what the minor checkbox and
  the two mode axes actually do today, and the card copy states only
  those real behaviours.
- **Stop conditions honored:** total added taps for a skip-everything
  user ≤ 2 versus today's flow; every question individually skippable;
  fertility-adjacent goal options on all profiles including minors
  (#123/#142 — no UI-level restriction); no illustrations from #164
  (not landed — text-only cards).

---

## What Shipped

### U1. Intro cards (three, skippable, before the name form)

`lib/ui/profiles/first_run_screen.dart`'s notice step becomes a
three-card intro, shown while `firstRunNoticeShown` is unset (the same
`SettingsKeys.firstRunNoticeShown` flag — the intro replaces the notice
step, so relaunch mid-intro resumes it and a preset flag skips it,
keeping the cold-start-link and restoring paths of the old flow
byte-for-byte):

1. **Identity/value card** — brand mark (an `Icons.nights_stay` glyph in
   a `CircleAvatar` plus the `LunarLog` wordmark — text-only, per the
   brief's "#164 illustrations do not exist yet" note), the headline "A
   private cycle log for your family", and the plain-language claims the
   AC names: family co-management, offline-first, no ads / no data
   selling / no behavioral tracking, never-paywalled predictions —
   worded against `docs/product/positioning.md` (#122/#334) and
   `PRIVACY.md`, which back each claim.
2. **Profiles/guardians card** — a profile is one person's log; after
   signing in a second guardian can be invited (pointing conceptually at
   #126's sharing discoverability); plus the truthful minor-checkbox
   explanation (below).
3. **Data/sync notice card** — today's copy verbatim (the #334
   repositioned `kFirstRunNoticeCopy`), advanced by today's "I
   understand" button.

**Skippability and the tap budget.** Cards 1 and 2 carry "Next"
(advance one card) and "Skip"; card 3 carries "I understand" and
"Skip". "Skip" on any card jumps past the whole intro and marks
`firstRunNoticeShown` — the intro is one skippable unit, which is what
makes the AC's arithmetic true: a skip-everything user spends one tap to
clear all three cards (replacing today's single notice tap one-for-one)
plus one tap on the cycle step's "Create profile", i.e. **+1 tap**
versus today's flow (≤ 2 required).

**The minor explanation is truthful to what landed.** #269's old "the
checkbox branches nothing" audit predates the health-sync work: today
`Profile.isMinor` (or a `birthYear` under 18) denies OS health-store
binding (`lib/domain/health/health_sync_binding.dart`'s
`minorRequiresOwnershipTransfer`, with
`AppConfig.healthSyncMinorBindingAllowed` hardcoded `false`), and #131
deliberately derives nothing else from it (mode is chosen, never
computed). The card and the new one-line form hint say exactly that:
the checkbox keeps the profile out of this phone's Health app sync and
does not restrict the app — wording and reminders come from the
separately-chosen care mode. Care-mode vocabulary (#131) and life-stage
mode (#188) are named as the separate axes they are.

### U2. Cycle questions (after the name form, before creation)

The name form's submit is relabelled "Continue" and moves validation
there; a new cycle-questions step renders the issue's five questions on
one screen, each individually skippable (blank = skipped), with the
final "Create profile" button performing the actual creation:

- **Last period start** — `showDatePicker` (no future dates; one year
  back), shown as a `MMMM d, y` date with a "Clear" affordance. Picker
  callable is injectable for tests.
- **Typical cycle length (days)** — numeric, validated to 10–90 when
  filled.
- **Typical period length (days)** — numeric, validated to 1–14 when
  filled.
- **Birth-control method** — selector over a UI-local closed list
  (`lib/ui/profiles/birth_control_choices.dart`: Not answered / None /
  Pill / Hormonal IUD / Copper IUD / Implant / Injection / Vaginal
  ring / Patch / Condom / Other) stored as free text into
  `profile_modes.birth_control_method` — deliberately *not* a domain
  enum, because #260 owns the tracked-method vocabulary and the server
  column is free text bounded at 64.
- **Goal / mode** — selector over #188's `LifecycleMode` axis
  (tracking/conceive/pregnancy/perimenopause/postpartum). The issue
  text ("matches #131's care-mode axis and the life-stage-mode
  assumption") predates #188 landing; with the two axes now explicitly
  orthogonal, the Clue-style goal question maps to the **life-stage**
  axis (`LifecycleMode`), while #131's care-mode axis stays the dropdown
  on the name form where #131 put it. Fertility-adjacent options
  (`conceive`) show on every profile including minors, per #123/#142.

### U3. Persistence seam (what has storage vs. what #218 owns)

`lib/domain/onboarding/onboarding_cycle_answers.dart` (pure Dart) holds
the whole answer set as `OnboardingCycleAnswers` plus the
`OnboardingCycleAnswersRecorder` seam.
`lib/data/repositories/drift_onboarding_cycle_answers_recorder.dart`
persists exactly the two answers that have landed storage (#188's
`profile_modes`): `lifecycleMode` and `birthControlMethod`, via
`LunarLogStorage.upsertProfileMode` — creating the row lazily only when
there is something to store, preserving an existing row's
`health_sync_consent` (never clobbering it with the default false),
keeping `mode_started_on` when the mode is unchanged and stamping today
only on an actual mode change.

**Last period date and the two typical lengths are deliberately not
persisted.** #216's assumption scopes this issue UI-only and #218 owns
"what the answers feed" (provisional-prediction seeding, itself blocked
on #213); inventing storage for them here would pre-empt #218's design.
The fields ride on `OnboardingCycleAnswers` — the seam #218 consumes —
and are noted as Not done in the PR.

### U4. Editability (AC "answers are editable later")

The two persisted answers become editable in the profile edit dialog
("Rename"/"Add profile" — the per-profile settings surface that exists
today): `profile_dialogs.dart` gains a "Life-stage mode" dropdown and a
"Birth-control method" dropdown, loaded from the stored
`profile_modes` row; `ProfileEditResult` carries them; the picker's
create/rename paths record them through the same U3 recorder. The three
#218-scoped answers have no storage to edit and are Not done.

### U5. Copy through ARB (#340 pattern)

~35 new `firstRun*` / `birthControl*` / `lifeStageMode*` messages in
`lib/l10n/app_en.arb`; generated localizations regenerated and
committed. The first-run screen's pre-existing literals ("I
understand", the notice, "Create a profile", "Name", the minor label,
"Care mode", "Create profile") are extracted with identical values
(copy-parity entries added to `test/ui/l10n_test.dart`), so every test
asserting those strings keeps passing. `LifecycleMode.label` /
`ProfileMode.label` dropdown labels stay the domain-enum English of
#340's declared follow-on (same as the existing care-mode dropdown);
the `LunarLog` wordmark is a const (a proper noun, not translatable
copy — #340's numeral precedent).

---

## Testing

- `test/ui/first_run_test.dart`: rewritten for the new flow — web ack →
  card 1; Next/Next/I-understand walk; Skip-jumps-past-the-intro (and
  persists the flag); the cycle step's fields, validation, and the
  Create button creating the profile + recording answers; the restoring
  and care-mode groups updated for the two-step tail.
- `test/data/onboarding_cycle_answers_test.dart`: recorder behavior —
  lazy row creation, mode-change stamping `mode_started_on`,
  unchanged-mode preserving it, `health_sync_consent` preservation,
  clearing a birth-control method, and the no-op when nothing to store.
- `test/ui/profiles_test.dart`, `account_test.dart`,
  `web_guardrails_test.dart`, `app_auth_provider_test.dart`: mechanical
  updates for the intro cards and the Continue → cycle → Create tail.
- `test/ui/l10n_test.dart`: parity group for the seven extracted
  first-run literals plus pinned values for the new messages.

## Known limitations (Not done)

- Illustrations (#164) — not landed; cards are text-only.
- Voice/copy guide #258 — not landed; copy is placeholder per #216's
  own AC note.
- Last period date / typical lengths: collected, carried on the seam,
  not persisted and not editable — #218's scope.
- Domain enums' labels (`ProfileMode`, `LifecycleMode`) remain
  hardcoded English per #340's declared follow-on.
