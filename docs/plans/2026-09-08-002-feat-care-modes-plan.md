---
title: Care Modes - Per-Profile Vocabulary, Defaults, and Reminder Presets - Plan
type: feat
date: 2026-09-08
issue: wjdavis5/lunarlog#131
artifact_contract: ce-unified-plan/v1
artifact_readiness: implementation-complete
product_contract_source: issue-131
execution: code
---

# Care Modes - Per-Profile Vocabulary, Defaults, and Reminder Presets - Plan

**Target repo:** `lunarlog` (`wjdavis5/lunarlog`). All paths repo-relative.
This document was written after implementation to record what shipped and
why; the issue body remains the product authority.

---

## Goal Capsule

- **Objective:** A synced per-profile care mode (`standard` | `teen` |
  `caregiver` | `irregular`, default `standard`) that changes vocabulary,
  logging defaults, and reminder presets prospectively — the same screen
  no longer says the same thing to a teen logging her first cycles, an
  adult tracking her own, and a grandparent helping out.
- **Means:** `profiles.mode` follows the exact `birth_year`/`relationship`
  precedent end to end — Drift schema v5 + `sync_push` key allowlist /
  insert / containment-guarded update paths — and a pure-Dart copy
  registry plus reminder presets drive the overview panel, day sheet,
  and the reminder coordinator's next replan.
- **Authority hierarchy:** Issue #131 owns intent (its design constraints
  are hard requirements with tests); the roadmap
  ([`2026-09-04-0738-feat-target-state-roadmap-plan.md`](2026-09-04-0738-feat-target-state-roadmap-plan.md)
  R12/U6/KTD10) owns the settled shape; the task brief's settled
  decisions (synced column, containment-check update pattern, coordinator
  replan path) govern where the issue left room.
- **Stop conditions honored:** Prospective only — switching modes touches
  no saved entry; mode is presentation, never permission; mode is never
  derived from `birthYear`/`isMinor`; teen is not a reduced app; the
  estimate disclaimer appears in every mode variant, without exception.

---

## What Shipped

### U1. Server: `profiles.mode` + `sync_push` paths

`supabase/migrations/20260908120000_profile_care_modes.sql` adds
`profiles.mode` (`text not null default 'standard'`, CHECK-constrained to
the closed set mirrored by the client `ProfileMode` enum), grants
`update (mode)` to `authenticated`, and `create or replace`s `sync_push`
— carried forward from `20260906200000_same_date_tag_merge.sql`'s body
(the current definition, not `20260906160000`'s) with exactly the mode
additions: the key allowlist entry, the `v_mode` parse (absent key →
`'standard'`), the INSERT column, and the `v_row ? 'mode'` containment
guard on UPDATE so a pre-#131 client's rename never clobbers a stored
mode (PR #108 review item #3's pattern). An out-of-set value lands the
row in `rejected` via the CHECK, like `birth_year`/`relationship`.

### U2. Client schema and sync path

Drift schema v5 (`profiles.mode`, `withDefault('standard')`, one
`addColumn` step in `db.dart`'s `onUpgradeSteps`), `row_codec.dart`
encodes `mode` on every profile push and normalises an absent/unknown
value to `standard` on decode (presentation-only, so it degrades rather
than throws — `ProfileRelationship`'s closed-set treatment, except
non-null), `remote_rows.dart`/`storage.dart` carry it through both apply
paths, and `mappers.dart` resolves the domain enum. The repository and
`ProfileController` accept a mode on create; an omitted mode on
`renameProfile` preserves the current one.

### U3. Domain: copy registry and reminder presets

`lib/domain/care_modes.dart` holds the four `CareModeCopy` variants
(overview headings/bodies, estimate label, overdue status line, category
headings + surfacing order) and
`lib/domain/notifications/reminder_presets.dart` the per-mode
`ReminderPreset`: standard arms both reminder types (unchanged), teen and
irregular keep upcoming but drop late, caregiver arms nothing. Both
resolve through switch expressions naming every mode (no wildcard), so a
future mode without copy or a preset is a compile error.

### U4. UI

The profile edit dialog and first-run creation form offer a Care mode
dropdown with a per-mode hint line. `OverviewPanel` and `MonthCalendar`
take the profile's mode and pass it through to the day sheet; the
overview cards render mode copy with the disclaimer in every mode (the
not-enough card gained it too, making the invariant total), and
`irregular` silences the late resolver in both the active-late and
paused states, replacing it with a quiet status line that never uses
"late" framing. The day sheet renders categories in the mode's order
with its headings — every category still present in every mode.

### U5. Reminder presets at the coordinator

`planReminders` takes an optional per-profile preset map (missing entry →
`ReminderPreset.all`, so existing callers and the pre-#131 plan are
byte-identical). The coordinator tracks each active profile's mode from
the same active-profiles stream that schedules the replan, so a mode
switch is applied at the next coordinator pass — no retroactive rewrite
of saved entries or past reminders (KTD10).

### U6. Export

`buildAccountExport` emits `profiles[].mode` (`toDb()` string) and the
document schema version bumped to 2.

---

## Key Technical Decisions

- **KTD-A. Mode is presentation, never permission — proved, not
  promised.** Nothing in any authorization path reads the mode: the
  pgTAP suite pins that a caregiver-role push cannot edit a profile's
  mode and that a caregiver still writes day entries on a mode-carrying
  profile; a widget test pins that a viewer guardian is read-only and
  the operator editable in all four modes; the `sync_push` role checks
  are textually unchanged by the migration.
- **KTD-B. Mode is chosen, never computed.** `isMinor` and `birthYear`
  remain inert display metadata; the "never derived" constraint is
  pinned by a test creating a minor with a birth year and asserting the
  mode still reads `standard` until a human picks one.
- **KTD-C. Teen reorders, never removes.** The teen category order is
  body → mood → pain → other (body-literacy framing first) and the body
  category is re-headed, but a test pins that the order is a permutation
  of every standard category and all 17 curated chips still render —
  "not a euphemism for a reduced app".
- **KTD-D. Only `irregular` silences the late resolver** (the roadmap's
  own test scenario), in both the active-late and paused states; the
  replacement line keeps the disclaimer, and teen keeps the standard
  resolver — honest late framing still applies to a teen with an
  established average.
- **KTD-E. The containment-guard update pattern is load-bearing.** A
  pre-#131 client never sends `mode`; without `v_row ? 'mode'` its
  ordinary rename would reset a stored mode through the UPDATE path (or
  violate NOT NULL through a naive read). Mirrors PR #108 review item
  #3's fix for `birth_year`/`relationship`; pinned in pgTAP.
- **KTD-F. Presets default to the pre-#131 plan.** `planReminders`
  without a preset entry produces exactly the plan it always did, so
  every existing caller (and test) is unaffected; only the coordinator
  feeds modes in.

## Not Done (deliberate)

- The issue comment's life-stage axis (#188 Conceive / #192 Pregnancy /
  #196 Perimenopause / #204) is orthogonal and explicitly not collapsed
  into this enum; the composition decision it demands is left to those
  issues, per the parity audit on #131.
- Age-gating scope (`isMinor` branching nothing, no minimum age in-app)
  stays in #269, per the issue comment.
- Mode-specific copy beyond the overview/day-sheet surfaces (settings
  labels, export prose) is unchanged; the vocabulary deliverable covers
  the surfaces the issue names.
- Device-side verification of the reminder presets against real OS
  scheduling is a manual device-checklist item, per the house posture.

## Verification

`flutter analyze` clean; `flutter test` green; `dart run
tool/quality_gate.dart` PASS; pgTAP suite green locally (647+13 tests)
via `supabase start` + `db reset --local` + `test db --local`, and in CI
via the `db-tests` job.
