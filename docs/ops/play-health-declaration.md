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

## Current permission set (issue #166 baseline; read side added by #458; fertility/measurement writes added by #228)

Scoped to the menstruation data types [#202](https://github.com/wjdavis5/lunarlog/issues/202)
(HS-7) needs for v1. The [#173](https://github.com/wjdavis5/lunarlog/issues/173)
platform-channel adapter and the [#193](https://github.com/wjdavis5/lunarlog/issues/193)/#374
opt-in, forward-only write paths are now live (`AppConfig.hasHealthSync`
is `true`): a bound profile's user-logged flow and spotting records are
written into the on-device Health Connect store, and nothing is
transmitted off-device through this feature. Writes carry user-logged or
imported data only — never a predicted or derived cycle value (the
written rule in `lib/data/health/health_channel.dart`'s library doc,
issue [#254](https://github.com/wjdavis5/lunarlog/issues/254). **Read
direction added by issue [#458](https://github.com/wjdavis5/lunarlog/issues/458),
the Android half of the owner's [#781](https://github.com/wjdavis5/lunarlog/issues/781)
read decision already applied to iOS by [#217](https://github.com/wjdavis5/lunarlog/issues/217):**
`HealthConnectAdapter.kt`'s `readPermissions` set now requests
`getReadPermission` for both record types, matching a real call site
(the user-initiated `getChangesToken`/`getChanges` import in
`readMenstrualFlow`), and `AndroidManifest.xml` declares the two
`READ_*` permissions. The import drops any record whose `dataOrigin` is
this app, so lunarlog's own writes are never re-imported, and it is
bounded to the last 30 days with no background or full-history read
(`READ_HEALTH_DATA_HISTORY` / `READ_HEALTH_DATA_IN_BACKGROUND` remain
undeclared). Adding a `READ_*` permission re-triggers the Play Health
apps declaration review: refile this form before any track Google
reviews ships the build. Extend the table below (never widen the
manifest silently) as later HS issues
([#186](https://github.com/wjdavis5/lunarlog/issues/186),
[#210](https://github.com/wjdavis5/lunarlog/issues/210),
[#246](https://github.com/wjdavis5/lunarlog/issues/246)) add data types.
**Issue [#228](https://github.com/wjdavis5/lunarlog/issues/228) added the
three fertility/measurement `WRITE_*` permissions below** (write-only:
its scope reads none of these types back), so this form must be re-filed
with the new rows before the next tracked build.

| Permission | Direction | Justification (draft — confirm against the live form's exact wording) |
|---|---|---|
| `android.permission.health.WRITE_MENSTRUATION` | Write | Lets the user optionally mirror period start/end dates and flow level they log in lunarlog into Health Connect, so other health apps they use can see the same cycle history. Opt-in, one profile at a time, forward-only from grant (matches the Clue-parity baseline scoped in issue #116's epic). |
| `android.permission.health.WRITE_INTERMENSTRUAL_BLEEDING` | Write | Same rationale as `WRITE_MENSTRUATION`, for intermenstrual bleeding entries. |
| `android.permission.health.READ_MENSTRUATION` | Read | Lets the user explicitly import menstrual-flow records another app wrote into Health Connect, so history logged elsewhere does not have to be re-entered. User-initiated only (Settings → Health app sync → Import from Health Connect), bounded to the last 30 days, into the one profile bound to this device; records lunarlog itself wrote are excluded by `dataOrigin` so nothing round-trips, and a value the user logged by hand is never overwritten. |
| `android.permission.health.READ_INTERMENSTRUAL_BLEEDING` | Read | Same rationale as `READ_MENSTRUATION`, for intermenstrual-bleeding records (stored as the app's spotting observations). No derived or predicted value is ever read or written. |
| `android.permission.health.WRITE_CERVICAL_MUCUS` | Write | Lets the user optionally mirror the cervical-mucus observation they log in lunarlog into Health Connect's `CervicalMucusRecord`, so their other health apps can see it. Opt-in, bound profile only, forward-only from grant; the app has no sensation concept, so the required `sensation` field is written as the platform's honest `SENSATION_UNKNOWN`. Write-only — no `READ_CERVICAL_MUCUS` is requested. |
| `android.permission.health.WRITE_OVULATION_TEST` | Write | Same rationale, for a logged ovulation-test result (`OvulationTestRecord`). The positive/peak distinction collapses to `RESULT_POSITIVE` (Health Connect's own docs describe positive as the possible "peak" result); a domain "high fertility" value does not exist, so `RESULT_HIGH` is deliberately never written. Write-only. |
| `android.permission.health.WRITE_BASAL_BODY_TEMPERATURE` | Write | Same rationale, for a manually tracked basal-body-temperature reading (`BasalBodyTemperatureRecord`), converted to Celsius before the write and written with the honest `MEASUREMENT_LOCATION_UNKNOWN` (the domain has no measurement-location field). A wearable- or platform-sourced BBT value is deliberately never written, so it can never be conflated with the user's own tracked reading. Write-only. |

## Declaration form skeleton

Fill this in against the live Play Console form at submission time — field
names below are the form's shape as of this writing and may drift; treat
this as a skeleton to walk through, not a verbatim transcript.

- [ ] **App description of health use:** one or two sentences describing
      that lunarlog is a menstrual cycle tracker that, with explicit
      opt-in, can write period/flow, intermenstrual-bleeding,
      cervical-mucus, ovulation-test, and basal-body-temperature records to
      Health Connect so the user's data is available to other health apps
      they choose to use, and — separately and only when the user starts an
      import — read the two user-recorded menstrual types back over the
      last 30 days so history logged in another app does not have to be
      re-entered (never a predicted or derived value; no background or
      full-history read; no wearable-sourced value is ever written or
      conflated with a hand-logged one).
- [ ] **Per-permission justification:** paste the justification column
      above (or the form's closer equivalent) for each of the seven
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
  the manifest (issues #186, #210, #246 will each do this).
  Adding a data type re-triggers Play's Health apps declaration review —
  update the per-permission table above and re-file before the build
  that carries it ships to any track Google reviews. **Issue #458 already
  triggered one:** it re-added the two `READ_*` permissions and the read
  call site, so this form must be re-filed (with the two new table rows)
  before the next production-track build. **Issue #228 triggered
  another:** it added the three fertility/measurement `WRITE_*`
  permissions and their table rows above, so the re-filed form must
  include them.
- `AppConfig.hasHealthSync` flipped to `true` with #173 and the #193/#374
  writes — the form is no longer a draft exercise: it must actually be
  filed (and the release-gate variable above set) before any
  production-track ship.
- `PRIVACY.md`'s description of Health Connect / platform sync changes.
