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
is `true`): a bound profile's user-logged records are
written into the on-device Health Connect store, and nothing is
transmitted off-device through this feature. **This paragraph said so
before it was true on Android:** the Kotlin write handlers and the
manifest permissions existed, but the write coordinator was built on iOS
only, so Android requested the five write permissions and wrote nothing
until issue [#1478](https://github.com/wjdavis5/lunarlog/issues/1478)
turned the write direction on (see "What the Android build writes"
below, verified on an Android 15 emulator). Writes carry user-logged or
imported data only — never a predicted or derived cycle value (the
written rule in `lib/data/health/health_channel.dart`'s library doc,
issue [#254](https://github.com/wjdavis5/lunarlog/issues/254). **Read
direction added by issue [#458](https://github.com/wjdavis5/lunarlog/issues/458),
the Android half of the owner's [#781](https://github.com/wjdavis5/lunarlog/issues/781)
read decision already applied to iOS by [#217](https://github.com/wjdavis5/lunarlog/issues/217):**
`HealthConnectAdapter.kt`'s `readPermissions` set now requests
`getReadPermission` for both record types, matching a real call site
(the user-initiated paged import in `readMenstrualFlowPage`), and
`AndroidManifest.xml` declares the two `READ_*` permissions. The import
drops any record whose `dataOrigin` is this app, so lunarlog's own writes
are never re-imported. **Issue [#992](https://github.com/wjdavis5/lunarlog/issues/992)
lifted the old 30-day cap:** the import is full-history now, so
`android.permission.health.READ_HEALTH_DATA_HISTORY` is declared and
requested (a row was added to the table below). **Issue
[#993](https://github.com/wjdavis5/lunarlog/issues/993) added background
reads:** `READ_HEALTH_DATA_IN_BACKGROUND` is declared (row below), served
by `HealthBackgroundImportWorker.kt`'s periodic WorkManager job, which
wakes the running app's Dart side to run the same prompt-free, guarded
import pass — nothing about the read direction's data types changed.
Adding a `READ_*` permission re-triggers
the Play Health apps declaration review: refile this form before any track
Google reviews ships the build. Extend the table below (never widen the
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
| `android.permission.health.READ_MENSTRUATION` | Read | Lets the user explicitly import menstrual-flow records another app wrote into Health Connect, so history logged elsewhere does not have to be re-entered. The first import is user-initiated (Settings → Health app sync → Import from Health Connect); once that pass has completed for the bound profile, the same prompt-free pass also runs on a periodic background schedule so the imported history stays current without a manual tap (issues #993 and #1215 — the background pass never prompts, never writes, and stays a silent no-op until that first import has run). Either pass reads the whole available history in pages (issue #992; no longer bounded to 30 days), into the one profile bound to this device; records lunarlog itself wrote are excluded by `dataOrigin` so nothing round-trips, and a value the user logged by hand is never overwritten. |
| `android.permission.health.READ_INTERMENSTRUAL_BLEEDING` | Read | Same rationale as `READ_MENSTRUATION`, for intermenstrual-bleeding records (stored as the app's spotting observations). No derived or predicted value is ever read or written. |
| `android.permission.health.READ_HEALTH_DATA_HISTORY` | Read | Lets the same import read the whole health history rather than only the 30 days preceding the permission grant (Health Connect's default cap). Requested alongside the two menstrual read types; what it unlocks is the same paged history read described above — the user-started first import and, once that has run, the periodic background pass that keeps the history current (issues #993 and #1215) — never a continuous or real-time read: every pass pages through the store and stops at the end of the available data. |
| `android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND` | Read | Lets the same menstrual-data import keep the user's history current without requiring a manual tap every time (issue #993). A periodic WorkManager job wakes the running app and triggers one import pass — the same pass the Settings action runs: the two menstrual read types only, into the one profile bound to this device, records the app itself wrote excluded by `dataOrigin`, a hand-logged value never overwritten, nothing ever written back to Health Connect, no UI, and only outcome counts logged. The pass checks the device-binding guard and the Health Connect granted-permission set first and does nothing when either refuses (an unbound device, a revoked permission, or a never-completed first import are all silent no-ops), so the permission never enables a read the foreground import could not perform. |
| `android.permission.health.WRITE_CERVICAL_MUCUS` | Write | Lets the user optionally mirror the cervical-mucus observation they log in lunarlog into Health Connect's `CervicalMucusRecord`, so their other health apps can see it. Opt-in, bound profile only, forward-only from grant; the app has no sensation concept, so the required `sensation` field is written as the platform's honest `SENSATION_UNKNOWN`. Write-only — no `READ_CERVICAL_MUCUS` is requested. |
| `android.permission.health.WRITE_OVULATION_TEST` | Write | Same rationale, for a logged ovulation-test result (`OvulationTestRecord`). The positive/peak distinction collapses to `RESULT_POSITIVE` (Health Connect's own docs describe positive as the possible "peak" result); a domain "high fertility" value does not exist, so `RESULT_HIGH` is deliberately never written. Write-only. |
| `android.permission.health.WRITE_BASAL_BODY_TEMPERATURE` | Write | Same rationale, for a manually tracked basal-body-temperature reading (`BasalBodyTemperatureRecord`), converted to Celsius before the write and written with the honest `MEASUREMENT_LOCATION_UNKNOWN` (the domain has no measurement-location field). A wearable- or platform-sourced BBT value is deliberately never written, so it can never be conflated with the user's own tracked reading. Write-only. |

## What the Android build writes (issue #1478)

Checked on an Android 15 (API 35) emulator with the system Health
Connect, by logging each kind of entry for a fabricated bound profile and
reading it back in Health Connect's own "Data and access" screens. This
is the behavior the form must describe.

| Logged in lunarlog | Health Connect record | Shown by Health Connect as |
|---|---|---|
| Flow: light, medium, heavy | `MenstruationFlowRecord` at the day's local midnight | Menstruation — "Light / Medium / Heavy flow" |
| Flow: super heavy | `MenstruationFlowRecord`, `FLOW_HEAVY` (Health Connect has no heavier level) | "Heavy flow" |
| Spotting on a day inside a period | `MenstruationFlowRecord`, `FLOW_LIGHT` | "Light flow" |
| Spotting between periods | `IntermenstrualBleedingRecord` | Spotting |
| Each period (a run of bleed days) | one `MenstruationPeriodRecord`, first day's midnight to the last instant of the last day | "Period day N of M" |
| Discharge: sticky, creamy, egg white | `CervicalMucusRecord` (appearance only; sensation unknown) | Cervical mucus |
| Ovulation test: negative, positive, peak | `OvulationTestRecord` (peak is written as positive) | Ovulation test |
| Basal body temperature | `BasalBodyTemperatureRecord`, Celsius, location unknown | Vitals — Basal body temperature |

Not written, and the in-app screen says so: symptoms and moods (Health
Connect has no such types), discharge tagged "atypical" or "no
discharge", pregnancy tests, notes, and anything logged for a profile
other than the one bound to the device.

How it behaves, for the form's free-text answers and for the reviewer's
walkthrough:

- **Asking.** Choosing the profile on Settings → Health Connect sync is
  the opt-in; the first write pass then opens Health Connect's permission
  sheet (writes and reads together). Until that has happened the screen
  reads "Health Connect access: not yet asked".
- **Forward-only.** Nothing logged before access was granted is written.
- **Edits and deletions.** Every record carries the lunarlog row's id as
  its `clientRecordId`, so an edit replaces the record and a deleted
  entry (or a day set back to no flow) deletes it. The period record is
  corrected or deleted with the days it covers.
- **Which permissions writing needs.** Every write permission, and no
  read permission: declining "Access past data" or background access
  does not stop writes. While any one write permission is off, nothing is
  written and the screen reads "Health Connect access: denied — open
  Settings to change".
- **Turning it off.** "Stop syncing to this phone" stops writes and
  leaves what was already written in Health Connect; so does removing the
  permission there.

## Declaration form skeleton

Fill this in against the live Play Console form at submission time — field
names below are the form's shape as of this writing and may drift; treat
this as a skeleton to walk through, not a verbatim transcript.

- [ ] **App description of health use:** one or two sentences describing
      that lunarlog is a menstrual cycle tracker that, with explicit
      opt-in, can write period/flow, intermenstrual-bleeding,
      cervical-mucus, ovulation-test, and basal-body-temperature records to
      Health Connect so the user's data is available to other health apps
      they choose to use, and — separately — read the two user-recorded
      menstrual types back over the full available history, in pages, so
      history logged in another app does not have to be re-entered. The
      import runs when the user starts it from Settings, and — once the
      user has opted in, bound a profile, and run that first import — a
      periodic background check triggers the same import pass so the
      history stays current without a manual tap (never a predicted or
      derived value; nothing is ever written back; no wearable-sourced
      value is ever written or conflated with a hand-logged one).
- [ ] **Per-permission justification:** paste the justification column
      above (or the form's closer equivalent) for each of the nine
      permissions.
- [ ] **Data sharing disclosure:** confirm the form's questions about
      whether health data is shared with third parties are answered "no" —
      lunarlog's Health Connect sync writes to the OS-mediated Health
      Connect store only; it does not transmit health data to any lunarlog
      server or third party as part of this feature (cloud sync to
      Supabase, when separately enabled, is a distinct, independently
      opt-in feature — see `PRIVACY.md` Section 2A).
- [ ] **Privacy policy URL:** the canonical policy URL already in use
      elsewhere in Play Console (`https://lunarlog.app/privacy`, issue
      #1101) — the same one `PermissionsRationaleActivity` deep-links to.
- [ ] **Screenshots / demonstration of the permission-request flow:**
      capture the `PermissionsRationaleActivity` screen and the system
      Health Connect grant dialog on a device with Health Connect
      installed (bind a profile in Settings → Health Connect sync; since
      issue #1478 the write path opens the grant dialog by itself a
      moment later. The rationale screen opens from Health Connect → App
      permissions → lunarlog → "Read privacy policy").
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
  include them. **Issue #992 triggered a third:** it added
  `READ_HEALTH_DATA_HISTORY` (and its table row) and lifted the 30-day
  read cap, so the re-filed form must include it too. **Issue #993
  triggered a fourth:** it added `READ_HEALTH_DATA_IN_BACKGROUND` (and its
  table row above) for the periodic background-import job, so the re-filed
  form must include it too — the row's justification names the exact
  background flow (same import pass, same guards, no UI, counts-only
  logging) Google's reviewers ask background-read declarations to
  demonstrate.
- `AppConfig.hasHealthSync` flipped to `true` with #173 and the #193/#374
  writes — the form is no longer a draft exercise: it must actually be
  filed (and the release-gate variable above set) before any
  production-track ship.
- **Issue #1478 turned Android's writes on.** No permission was added or
  removed (the manifest already declared all five write permissions), but
  the app's behavior now matches the write rows above for the first time,
  and the `PermissionsRationaleActivity` text changed to list every type
  written. Re-capture the rationale screen and the grant flow for the
  form, and file it before the next track Google reviews.
- `PRIVACY.md`'s description of Health Connect / platform sync changes.
