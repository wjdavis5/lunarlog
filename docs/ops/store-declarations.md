# Store privacy-declaration worksheet (issue [#21](https://github.com/wjdavis5/lunarlog/issues/21))

A single fill-in sheet for transcribing LunarLog's data-collection posture into
**App Store Connect → App Privacy** and **Play Console → Data safety** in one
sitting, plus the Play **Health apps** declaration cross-reference that gates a
Health Connect build. Every row is derived from the code and from `PRIVACY.md`,
with a citation, so an answer can be defended if a reviewer asks.

The companion issue is [#1065](https://github.com/wjdavis5/lunarlog/issues/1065):
`ios/Runner/PrivacyInfo.xcprivacy` does **not** yet declare two data types the
app actually sends off-device (push token; support-ticket content). Those rows
below are marked **[BLOCKED on #1065]** — do not file a manifest-inconsistent
answer for them. Everything else can be typed now.

## How to use this sheet

- **"Collected" means transmitted off the device** to LunarLog's servers or a
  third-party service. Data that never leaves the device (the home-screen widget
  container, Apple Health / Health Connect reads and writes, a share-sheet
  export, the local SQLite/IndexedDB copy) is **not collected** for either
  store's declaration, and adding a capability that stays on-device does not
  change a declaration (`PRIVACY.md` §9 lines 180-181).
- An **"s"** next to a row means it applies only when the user opts in:
  cloud sync, caregiver alerts, feedback, etc. The stores still require the
  type to be declared if *any* user can produce it.
- Recipients: **Supabase** is LunarLog's own processor, not a third party that
  the data is "shared" with in Play's sense; **Sentry / FCM / Resend** are
  processors too. No advertising, data-broker, or analytics recipient exists
  (`PRIVACY.md` §1 lines 16, §4 line 95).
- Tick each box as it is entered in the console. Nothing here is filed
  automatically — the consoles are owner-only actions.

### Recipients (for the "who receives it" questions)

| Recipient | What it receives | Citation |
|---|---|---|
| **Supabase** (`dleexnnevuuddcgcpztq`) | Account email, auth tokens, synced cycle/health rows, guardian memberships, notification preferences, push token, feedback tickets/replies/screenshots, the minimum-age consent row, prediction snapshots, change history, merge disclosures | `PRIVACY.md` §4:88, §2.A–§2.C |
| **Sentry** (`us.sentry.io`) | Scrubbed crash/error events; native crashes are OS-assembled and server-scrubbed | `PRIVACY.md` §4:89, §2.D:59-60 |
| **Apple** (Sign in with Apple) | Apple user identifier, relay email if chosen | `PRIVACY.md` §4:90 |
| **Google** (Google Sign-In) | Google ID token (email, basic account id) | `PRIVACY.md` §4:91 |
| **Resend** | Feedback reply email address and reply text | `PRIVACY.md` §4:92 |
| **Firebase Cloud Messaging / APNs** | Push registration token and the profile's internal id only — never a note, tag, flow, date, or name | `PRIVACY.md` §4:93 |

---

## 1. Data inventory → category mapping

Citations are `PRIVACY.md` section:line and, where useful, the code path.

| # | Data element | Off-device? | Recipient | Linked | Apple (App Privacy) category | Play Data safety type | Citation |
|---|---|---|---|---|---|---|---|
| 1 | Cycle days: date, flow level, symptoms, tags, shared note | Yes (s) | Supabase | Yes | Health & Fitness → **Health** | Health and fitness → **Health info** | `PRIVACY.md` §2.A:26-38 |
| 2 | Guardian notes (author-scoped, never merged) | Yes (s) | Supabase | Yes | Health & Fitness → **Health** | Health and fitness → **Health info** | `PRIVACY.md` §2.A:36 |
| 3 | Entry IANA time zone; caregiver's own time zone in notification prefs | Yes (s) | Supabase | Yes | Location → **Coarse Location** *(candidate — policy itself calls it "a coarse location signal")* | Location → **Approximate location** *(candidate)* | `PRIVACY.md` §2.A:28 |
| 4 | Profile info: display name, birth year, minor flag, sort/archive | Yes (s) | Supabase | Yes | Health & Fitness → **Health** (profile label); Contact Info → **Name** *(candidate)* | Health and fitness → **Health info** | `PRIVACY.md` §2.A:33, §5:118 |
| 5 | Same-date merge disclosure (losing note text / flow level + guardian ids), 30-day TTL | Yes (s) | Supabase | Yes | Health & Fitness → **Health** | Health and fitness → **Health info** | `PRIVACY.md` §2.A:34, §7:156 |
| 6 | Shared change history (which fields changed, by whom — never content), 90-day TTL | Yes (s) | Supabase | Yes | Usage Data → **Other Usage Data** *(candidate)* | App activity → **Other actions** *(candidate)* | `PRIVACY.md` §2.A:35, §7:156 |
| 7 | Import/device provenance + per-import progress record | Yes (s) | Supabase | Yes | Health & Fitness → **Health** (entry metadata) | Health and fitness → **Health info** | `PRIVACY.md` §2.A:32, §7:149 |
| 8 | Account email address | Yes (s) | Supabase; Apple/Google as IdP | Yes | Contact Info → **Email Address** | Personal info → **Email address** | `PRIVACY.md` §2.B:42 |
| 9 | Auth credentials, access/refresh tokens | Yes (s) | Supabase | Yes | *(no distinct nutrition category; not declared)* | *(not separately declared)* | `PRIVACY.md` §2.B:43 |
| 10 | Provider `sub` / Supabase account user id | Yes (s) | Supabase | Yes | Identifiers → **User ID** *(candidate)* | Personal info → **User IDs** *(candidate)* | `PRIVACY.md` §2.B:44 |
| 11 | **Push registration token** (+ device id, platform) | Yes (s) | Supabase + FCM/APNs | Yes | **[BLOCKED on #1065]** Identifiers → **Device ID** | Device or other IDs → **Device or other IDs** | `PRIVACY.md` §9:178; `lib/data/notifications/supabase_push_device_registry.dart:34-38` |
| 12 | Minimum-age acknowledgement (consent_via, acknowledged_at, app_version, policy_version) | Yes (s) | Supabase | Yes | *(no clean category — candidate)* | App activity → **Other actions** *(candidate)* | `PRIVACY.md` §5:117; `lib/data/consent/supabase_consent_service.dart:26-31` |
| 13 | Crash/error data, scrubbed; native crash reports OS-assembled | Yes | Sentry | No | Diagnostics → **Crash Data** | App info and performance → **Crash logs** | `PRIVACY.md` §2.D:57-62, §9:179 |
| 14 | Optional performance timings (off by default in every release build) | Yes (s) | Sentry | No | Diagnostics → **Performance Data** | App info and performance → **Other app performance data** | `PRIVACY.md` §2.D:61 |
| 15 | **Feedback: message + category + status** | Yes (s) | Supabase | Yes | **[BLOCKED on #1065]** User Content → **Customer Support** | Messages → **Other in-app messages** | `PRIVACY.md` §2.C:50-51; `lib/data/feedback/supabase_feedback_service.dart:42-52` |
| 16 | **Feedback reply email address + reply-thread text** | Yes (s) | Supabase + Resend | Yes | **[BLOCKED on #1065]** Contact Info → **Email Address**; User Content → **Customer Support** | Personal info → **Email address**; Messages → **Other in-app messages** | `PRIVACY.md` §2.C:51, §4:92 |
| 17 | **Feedback diagnostics** (OS/version, model, app version/build, locale, ≤25 breadcrumbs) | Yes (s) | Supabase | Yes | **[BLOCKED on #1065]** Diagnostics → **Other Diagnostic Data** | App info and performance → **Diagnostics** | `PRIVACY.md` §2.C:52; `feedback_service.dart:108-173` |
| 18 | **Optional feedback screenshot** | Yes (s) | Supabase Storage (`feedback-attachments`) | Yes | **[BLOCKED on #1065]** User Content → **Photos or Videos** | Photos and videos → **Photos** | `PRIVACY.md` §2.C:53; `supabase_feedback_service.dart:83-95` |
| 19 | Prediction-only snapshot (estimated period/fertile/ovulation/PMS days), while a connection is active | Yes (s) | Supabase | Yes | Health & Fitness → **Health** | Health and fitness → **Health info** | `PRIVACY.md` §5:124 |
| 20 | Guardian membership / roles / invitation metadata | Yes (s) | Supabase | Yes | Identifiers → **User ID** *(candidate)* | App activity → **Other actions**; Personal info → **User IDs** *(candidate)* | `PRIVACY.md` §5:119-121 |
| 21 | Home-screen widget container (state word, cycle-day count, relative countdown, opaque profile id, anchor date) | **No** | OS shared container | n/a | not collected | not collected | `PRIVACY.md` §2.E:66-67, §9:180 |
| 22 | Apple Health / Health Connect read **and** write (flow, intermenstrual bleeding, symptoms, mood, fertility/BBT; computed deviations read-only) | **No** | OS health store | n/a | not collected | not collected (Health declaration handled separately — §4 below) | `PRIVACY.md` §4:108, §9:181; `ios/Runner/PrivacyInfo.xcprivacy:72-102` |
| 23 | Clinical exports (JSON / FHIR / CSV) | **No** (user-initiated share sheet) | user-chosen destination | n/a | not collected | not collected | `PRIVACY.md` §4:110, §7:149-150 |
| 24 | Local SQLite (iOS/Android) / IndexedDB + session (signed-in web only) | Device only; browser store is **not** OS-protected | n/a | n/a | not collected | not collected | `PRIVACY.md` §1:15, §6:133 |

**Rows 3, 4, 6, 10, 12, 20 are "candidates":** the policy discloses them but no
store declaration has ever named them. Settle each during the #1065 sweep by
checking Apple's current category definitions and Google's data-type list, then
type the answer this sheet records. Rows 11, 15-18 are the concrete, already-known
gaps.

---

## 2. App Store Connect → App Privacy (transcription)

Entry point: App Store Connect → your app → **App Privacy** → *Get Started* /
*Edit*. Answer **"Yes, we collect data from this app."** Then add each type
below with these exact selections.

**Already declared in `PrivacyInfo.xcprivacy` (safe to type now):**

- [ ] Health & Fitness → **Health** — *Linked to the user's identity:* **Yes**;
      *Used for tracking:* **No**; *Purposes:* **App Functionality**.
- [ ] Contact Info → **Email Address** — Linked: **Yes**; Tracking: **No**;
      Purposes: **App Functionality**.
- [ ] Diagnostics → **Crash Data** — Linked: **No**; Tracking: **No**;
      Purposes: **App Functionality**.

**Pending #1065 (do not type until the manifest is reconciled):**

- [ ] Identifiers → **Device ID** (push token) — Linked: **Yes**; Tracking:
      **No**; Purposes: **App Functionality**.
- [ ] User Content → **Customer Support** (feedback message + reply thread) —
      Linked: **Yes**; Tracking: **No**; Purposes: **App Functionality**. (If
      your ASC flow labels it differently, the adjacent catch-all is
      User Content → **Other User Content**.)
- [ ] User Content → **Photos or Videos** (optional feedback screenshot) —
      Linked: **Yes**; Tracking: **No**; Purposes: **App Functionality**.
- [ ] Diagnostics → **Other Diagnostic Data** (feedback diagnostics) — Linked:
      **Yes**; Tracking: **No**; Purposes: **App Functionality**.
- [ ] Identifiers → **User ID** and/or Location → **Coarse Location** — only if
      the #1065 sweep decides the provider `sub`/account id and the time zone
      require their own entries.

**Tracking:** leave empty. `NSPrivacyTracking` is `false` with no tracking
domains (`ios/Runner/PrivacyInfo.xcprivacy:103-106`), and `PRIVACY.md` §9:177
states "Data Used to Track You: None".

**Privacy policy URL:** `https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md`.

---

## 3. Play Console → Data safety (transcription)

Entry point: Play Console → **App content → Data safety**.

**Global answers:**

- [ ] Does your app collect or share any required data types? **Yes.**
- [ ] Is all of the user data collected by your app encrypted in transit?
      **Yes** — every network call is HTTPS/TLS (`PRIVACY.md` §6:140).
- [ ] Do you provide a way for users to request that their data is deleted?
      **Yes** — in-app (see §5) plus email.
- [ ] (If asked) Committed to the Play Families policy? **No** — LunarLog is
      licensed 13+ with adult guardians managing household profiles
      (`PRIVACY.md` §5:117); it is not a child-directed app.

**Data types** — for each, "Collected" = transmitted off device; "Shared" = given
to a third party for its own use. LunarLog shares with **no** third party for
their own purposes (processors only), so every "Shared" answer is **No**
(confirm against Google's current service-provider definition at submission).

| Data type | Collected | Shared | Encrypted in transit | Deletion | Citation |
|---|---|---|---|---|---|
| Health and fitness → **Health info** | Yes | No | Yes | Yes | `PRIVACY.md` §2.A |
| Personal info → **Email address** | Yes | No | Yes | Yes | `PRIVACY.md` §2.B |
| Personal info → **User IDs** *(candidate)* | Yes | No | Yes | Yes | `PRIVACY.md` §2.B:44 |
| Location → **Approximate location** *(candidate)* | Yes | No | Yes | Yes | `PRIVACY.md` §2.A:28 |
| Messages → **Other in-app messages** (feedback) | Yes | No | Yes | Yes | `PRIVACY.md` §2.C |
| Photos and videos → **Photos** (feedback screenshot) | Yes | No | Yes | Yes | `PRIVACY.md` §2.C:53 |
| App activity → **Other actions** (feedback breadcrumbs, consent, memberships) | Yes | No | Yes | Yes | `PRIVACY.md` §2.C:52, §5:117 |
| App info and performance → **Crash logs** | Yes | No | Yes | Yes | `PRIVACY.md` §2.D |
| App info and performance → **Diagnostics** | Yes | No | Yes | Yes | `PRIVACY.md` §2.D:61 |
| Device or other IDs → **Device or other IDs** (push token) | Yes | No | Yes | Yes | `PRIVACY.md` §9:178 |

The four "candidate" rows are typed only if the #1065 sweep keeps them; the
remaining rows are safe to enter now.

---

## 4. Play Console → Health apps declaration (cross-reference)

Filing this form is a hard gate on any build requesting
`android.permission.health.*`, and it is **separate** from Data safety
(`docs/ops/play-health-declaration.md`). The full per-permission wording,
the declaration-form skeleton, and the release-gate mechanics live there — this
is the cross-reference so both consoles are typed in the same sitting.

**Permissions currently declared** (`android/app/src/main/AndroidManifest.xml:37-58`):

| # | Permission | Direction | Notes |
|---|---|---|---|
| 1 | `WRITE_MENSTRUATION` | Write | opt-in mirror of period/flow, forward-only |
| 2 | `WRITE_INTERMENSTRUAL_BLEEDING` | Write | same, spotting entries |
| 3 | `READ_MENSTRUATION` | Read | user-initiated import (issue #458) |
| 4 | `READ_INTERMENSTRUAL_BLEEDING` | Read | user-initiated import |
| 5 | `READ_HEALTH_DATA_HISTORY` | Read | full-history import (issue #992) — read-only |
| 6 | `WRITE_CERVICAL_MUCUS` | Write | fertility family (issue #228), write-only |
| 7 | `WRITE_OVULATION_TEST` | Write | write-only |
| 8 | `WRITE_BASAL_BODY_TEMPERATURE` | Write | write-only, no wearable-sourced value |

Symptom and mood health-store writes are **iOS-only** (HealthKit); Health
Connect has no symptom category types, so they are not part of this Android
declaration (`PRIVACY.md` §4:108). The iOS side is covered by the HealthKit
usage strings, not the Play form.

- [ ] Copy the eight per-permission justifications from
      `docs/ops/play-health-declaration.md`'s table into the live form.
- [ ] Answer the form's "shared with third parties?" question **No** — the sync
      writes only to the OS-mediated health store; cloud sync is a separate,
      independently opted-in feature (`PRIVACY.md` §4:108).
- [ ] Privacy policy URL: the same canonical PRIVACY.md link as Data safety.
- [ ] Capture the `PermissionsRationaleActivity` screen + the system grant
      dialog as the permission-flow screenshots.
- [ ] After approval, set the `PLAY_HEALTH_DECLARATION_CONFIRMED` repository
      variable to `true` (this is what unblocks `play-store-release.yml`'s
      production gate; issue #254).

**Drift found while cross-referencing:** `docs/ops/play-health-declaration.md`
says "for each of the **seven** permissions" (line 95) and "the **seven**
permissions" (line 96) while its table — and the manifest — list **eight**
after issue #228 added the fertility writes. Corrected to "eight" in this same
change so the worksheet and the form agree.

---

## 5. Deletion answers ("user can request deletion") — post-#17

Issue #17 shipped in-app account deletion, so both stores' deletion claims are
now true and can be transcribed as follows.

- **Apple — Guideline 5.1.1(v):** account creation is present, so deletion must
  be offered **in the app**. It is: Settings → Account → **Delete account**
  (`PRIVACY.md` §7:154). No further Apple declaration field exists for this.
- **Play — Data safety → Data deletion:**
  - "Do you provide users a way to request that their data is deleted?" →
    **Yes**.
  - "How can users request data deletion?" → **In-app** (Settings → Account →
    Delete account) **and by email** (`will@wjdavis5.net`). Select both.
  - Every data-type row above answers **Yes** to deletion.
- **What "Delete account" actually does (so the answer is defensible):** the
  `delete-account` Edge Function removes the account's server rows first
  (profiles, day entries, settings, memberships/invitations, consent record),
  removes feedback tickets, replies, and attachment objects, revokes the Apple
  grant when applicable, then deletes the Supabase account and wipes local data.
  It **fails closed** and stays retryable if the attachment cleanup or Apple
  revocation fails (`PRIVACY.md` §7:154; `lib/data/account/supabase_account_deletion_service.dart`).
- **Single-ticket narrower path:** a ticket deleted by email while the account
  stays open removes the ticket/reply rows; the attached screenshot is a tracked
  gap (`PRIVACY.md` §7:155). It does not change the account-level answer.

---

## 6. Drift checks: `PrivacyInfo.xcprivacy` vs `PRIVACY.md`

| # | Check | Result |
|---|---|---|
| 1 | Does the manifest declare the Health **read/import** added by #217/#992? | **No new declaration needed.** The HealthKit/Health Connect read and write are on-device only and never transmitted, so they are not a *collected* data type. The manifest header comment already covers #217 and #992 (`PrivacyInfo.xcprivacy:72-102`), and `PRIVACY.md` §9:181 agrees. No mismatch. |
| 2 | Widget App-Group data declared? | **Consistent.** The widget manifest declares `NSPrivacyCollectedDataTypes` empty and only UserDefaults reason `CA92.2`; the app manifest declares `CA92.1` + `CA92.2` (`ios/LunarLogWidget/PrivacyInfo.xcprivacy:19-35`). Data is on-device only (`PRIVACY.md` §9:180). No mismatch. |
| 3 | `tracking = false`? | **Consistent.** `NSPrivacyTracking` false, empty tracking domains (`PrivacyInfo.xcprivacy:103-106`); `PRIVACY.md` §9:177. No tracking. |
| 4 | **Push token declared?** | **MISMATCH.** `PRIVACY.md` §9:178 lists Device Push Token as *Data Linked to You*; the manifest has no Identifiers entry and its comment never mentions FCM. Real gap → **#1065**. |
| 5 | **Support/feedback data declared?** | **MISMATCH.** `PRIVACY.md` §2.C:48-55 discloses the message, reply email, diagnostics, and screenshot going off-device; neither the manifest nor `PRIVACY.md` §9's list declares them. Real gap → **#1065**. |
| 6 | Android health permissions vs the Play Health form | **Consistent in count** (8 declared, 8 tabled), but the prose said "seven" — documentation drift, corrected in this PR. |
| 7 | `PRIVACY.md` §9's list vs its own §2/§4 disclosures | **Incomplete** — §9 omits feedback content, diagnostics, screenshot, consent record, provider id, and the time-zone signal that §2/§4 disclose. Same reconciliation as #1065. |

**Issues filed:** [#1065](https://github.com/wjdavis5/lunarlog/issues/1065)
(reconcile `PrivacyInfo.xcprivacy` collected-data-types; blocks the push-token
and support rows above). No other mismatch was filed — checks 1-3 are deliberate
and documented, 6 was a one-word prose fix, and 7 folds into #1065.

**Also required before the next iOS submission** (separate Apple regime, not a
mismatch): run Xcode's *Generate Privacy Report* on a `Williams-Mini` archive
and reconcile `NSPrivacyAccessedAPITypes` — this environment cannot run it
(`docs/ops/ios-privacy-manifest.md`).

---

## 7. Re-file when (future features → declaration they change)

| Trigger | What changes | Declaration(s) to re-file |
|---|---|---|
| **#993** background health sync (Apple Health background delivery; Health Connect background reads) | Adds `READ_HEALTH_DATA_IN_BACKGROUND` and background-delivery entitlement; reads become automatic rather than tap-initiated | Play **Health apps** declaration (new permission + justification). Data safety likely unchanged (still on-device only) — confirm whether "collected" changes. App Privacy unchanged on category, but re-check purpose copy. |
| **#831** deployed signed-in web build | Signed-in browser holds synced rows + session in unencrypted browser storage; already disclosed in `PRIVACY.md` §6:133, but the deployed origin is new | Both stores' **security/data-safety** narrative and the Play **data deletion** answer (add "clear browser storage / sign out wipes it"). Apple/Play category list unchanged unless web-only features ship. |
| **#117** Claude/ChatGPT connector (open, needs ideation) | Would send health data to a third-party AI assistant — a true third party, not a processor | Play Data safety: **Shared = Yes** for Health info (a real change). App Privacy: Health linked and shared. Also `PRIVACY.md` §4. Needs a product decision first. |
| Any new off-device data type or new recipient | New row in §1 above, new category on both stores | Both declarations + `PRIVACY.md` §9 + `PrivacyInfo.xcprivacy` in the same change. |
| Any new `android.permission.health.*` (issues #186, #210, #246) | Health apps declaration review re-triggers | Play **Health apps** declaration (`docs/ops/play-health-declaration.md` "Re-check triggers"). |
| `PRIVACY.md` "Last Updated" changes | The policy the stores cite changed | Re-read the changed section and update any affected row here. |

---

## 8. Not done (owner's transcription)

- [ ] App Store Connect → App Privacy typed from §2 (minus the #1065-blocked rows).
- [ ] Play Console → Data safety typed from §3.
- [ ] Play Console → Health apps declaration form filed from §4 and approved,
      then `PLAY_HEALTH_DECLARATION_CONFIRMED=true`.
- [ ] Xcode *Generate Privacy Report* run and reconciled on `Williams-Mini`.
- [ ] #1065 resolved and the push-token + support rows added to both stores.
- [ ] Screenshots captured for the Health apps form.
