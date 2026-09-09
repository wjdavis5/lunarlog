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
(HS-7) needs for v1. No code path reads or writes through Health Connect
yet — `AppConfig.hasHealthSync` is hardcoded `false` until
[#173](https://github.com/wjdavis5/lunarlog/issues/173) lands the platform
adapter. Extend the table below (never widen the manifest silently) as
later HS issues ([#186](https://github.com/wjdavis5/lunarlog/issues/186),
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
      Health Connect grant dialog once #173 lands an actual call site to
      trigger them (this issue's plumbing alone doesn't yet produce a
      request Google can screenshot end-to-end).
- [ ] Submit and record the review outcome here (approved / rejected +
      reason, never the submission id or account credentials).

## Consistency anchor

This declaration's answers must stay consistent with `PRIVACY.md`'s public
claims and with the per-permission comment in
`android/app/src/main/AndroidManifest.xml`. If either changes which health
data types lunarlog reads or writes, re-open this checklist.

## Re-check triggers

- A new `android.permission.health.*` permission is added or removed from
  the manifest (issues #186, #210, #228, #246 will each do this).
- `AppConfig.hasHealthSync` flips to `true` for the first time (#173) —
  that's the point the "Screenshots" item above becomes achievable and the
  form should actually be submitted, not just drafted.
- `PRIVACY.md`'s description of Health Connect / platform sync changes.
