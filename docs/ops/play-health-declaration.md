# Play Console Health apps declaration

Operator checklist for the Play Console "Health apps" declaration, a hard
gate on shipping any lunarlog build that requests `android.permission.health.*`
permissions (issue [#166](https://github.com/wjdavis5/lunarlog/issues/166),
which added the manifest permissions and the `PermissionsRationaleActivity`
plumbing this form describes). Referenced from
[`supabase-go-live.md`](supabase-go-live.md)'s "Apple / Google store
plumbing" section. Tick items here as they are done; this is the honest
record of what the operator has and has not filed. Never record account
credentials or the declaration's submission id in this file.

**Full store-compliance work — the Play Data safety section, and the iOS
`PrivacyInfo.xcprivacy` reconciliation once HealthKit ships (issue
[#156](https://github.com/wjdavis5/lunarlog/issues/156)) — is tracked
separately as issue [#254](https://github.com/wjdavis5/lunarlog/issues/254),
not duplicated here.** This document only covers the Health Connect-specific
declaration form.

## Why this exists

Play Console requires apps that declare `android.permission.health.*`
permissions to complete a "Health apps" declaration before a build using
those permissions can be distributed on a production (or most testing)
track. This is separate from and in addition to the ordinary Play Data
safety form. Google reviews the declaration; a build can be rejected or
removed if the declared use doesn't match actual behavior.

## Current permission set (issue #166 baseline)

Scoped to the menstruation data types [#202](https://github.com/wjdavis5/lunarlog/issues/202)
(HS-7) needs for v1. The [#173](https://github.com/wjdavis5/lunarlog/issues/173)
platform-channel adapter and the [#193](https://github.com/wjdavis5/lunarlog/issues/193)/#374
opt-in, forward-only write paths are now live (`AppConfig.hasHealthSync`
is `true`): a bound profile's user-logged flow and spotting records are
written into the on-device Health Connect store, and nothing is
transmitted off-device through this feature. Writes carry user-logged or
imported data only — never a predicted or derived cycle value (the
written rule in `lib/data/health/health_channel.dart`'s library doc,
issue [#254](https://github.com/wjdavis5/lunarlog/issues/254). Extend the
table below (never widen the manifest silently) as later HS issues
([#186](https://github.com/wjdavis5/lunarlog/issues/186),
[#210](https://github.com/wjdavis5/lunarlog/issues/210),
[#228](https://github.com/wjdavis5/lunarlog/issues/228)) add data types.

| Permission | Direction | Justification (draft — confirm against the live form's exact wording) |
|---|---|---|
| `android.permission.health.READ_MENSTRUATION` | Read | Lets a user who grants access see their previously-logged period and flow history reflected back from Health Connect, e.g. after reinstalling the app or when another app wrote data first. Read only for the profile explicitly bound as this device's owner (product assumption #3, enforced by issue #153's guard) — a guardian's device never reads another profile's data from its own health store. |
| `android.permission.health.WRITE_MENSTRUATION` | Write | Lets the user optionally mirror period start/end dates and flow level they log in lunarlog into Health Connect, so other health apps they use can see the same cycle history. Opt-in, one profile at a time, forward-only from grant (matches the Clue-parity baseline scoped in issue #116's epic). |
| `android.permission.health.READ_INTERMENSTRUAL_BLEEDING` | Read | Same rationale as `READ_MENSTRUATION`, for spotting/bleeding logged between periods rather than during them — a distinct Health Connect record type from menstruation flow. |
| `android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING` | Write | Same rationale as `WRITE_MENSTRUATION`, for intermenstrual bleeding entries. |

## Declaration form skeleton

Fill this in against the live Play Console form at submission time — field
names below are the form's shape as of this writing and may drift; treat
this as a skeleton to walk through, not a verbatim transcript.

- [ ] **App description of health use:** one or two sentences describing
      that lunarlog is a menstrual cycle tracker that, with explicit
      opt-in, can read and write period/flow and intermenstrual-bleeding
      records to Health Connect so the user's data is available to other
      health apps they choose to use.
- [ ] **Per-permission justification:** paste the justification column
      above (or the form's closer equivalent) for each of the four
      permissions.
- [ ] **Data sharing disclosure:** confirm the form's questions about
      whether health data is shared with third parties are answered "no" —
      lunarlog's Health Connect sync writes to the OS-mediated Health
      Connect store only; it does not transmit health data to any lunarlog
      server or third party as part of this feature (cloud sync to
      Supabase, when separately enabled, is a distinct, independently
      opt-in feature — see `PRIVACY.md` Section 2A).
- [ ] **Privacy policy URL:** the canonical policy URL already in use
      elsewhere in Play Console
      (`https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md`) — the
      same one `PermissionsRationaleActivity` deep-links to.
- [ ] **Screenshots / demonstration of the permission-request flow:**
      capture the `PermissionsRationaleActivity` screen and the system
      Health Connect grant dialog on a device with Health Connect
      installed (the call site exists since #173/#193 — bind a profile in
      Settings and run one sync pass to trigger them).
- [ ] Submit and record the review outcome here (approved / rejected +
      reason, never the submission id or account credentials).
- [ ] **Open the release gate:** once the form is filed and approved, set
      the `PLAY_HEALTH_DECLARATION_CONFIRMED` repository variable to
      `true` (Settings → Secrets and variables → Actions → Variables).
      `play-store-release.yml`'s production-track gate fails every
      `production` dispatch until this is set — the fail-closed
      enforcement of this checklist (issue #254).

## Consistency anchor

This declaration's answers must stay consistent with `PRIVACY.md`'s public
claims and with the per-permission comment in
`android/app/src/main/AndroidManifest.xml`. If either changes which health
data types lunarlog reads or writes, re-open this checklist.

## Release-gate enforcement (issue #254)

`play-store-release.yml`'s `production-gate` job checks this checklist's
enabler before any `production` dispatch builds: when the manifest
requests any `android.permission.health.*` permission and the
`PLAY_HEALTH_DECLARATION_CONFIRMED` repository variable is not `true`,
the dispatch fails before any build runs. The variable is the recorded
"form filed and approved" switch — flip it only after the declaration
above has actually been submitted and accepted, and leave it in place
across re-declarations (re-review is triggered by the manifest change
itself, tracked in "Re-check triggers" below, not by re-flipping).

## Re-check triggers

- A new `android.permission.health.*` permission is added or removed from
  the manifest (issues #186, #210, #228, #246 will each do this).
  Adding a data type re-triggers Play's Health apps declaration review —
  update the per-permission table above and re-file before the build
  that carries it ships to any track Google reviews.
- `AppConfig.hasHealthSync` flipped to `true` with #173 and the #193/#374
  writes — the form is no longer a draft exercise: it must actually be
  filed (and the release-gate variable above set) before any
  production-track ship.
- `PRIVACY.md`'s description of Health Connect / platform sync changes.
