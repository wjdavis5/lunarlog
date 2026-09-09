# LunarLog Privacy Policy

**Effective Date:** September 7, 2026  
**Last Updated:** September 9, 2026 (a large bulk import now keeps a small server-side progress record — source label, row counts, status, timestamps, no health content — included in export and deletion like every other server-side record, see the Change History in Section 10; repositioned the product framing around sync and multi-guardian family collaboration rather than offline operation — see the Change History in Section 10; every disclosure below is unchanged in substance, only reordered and reworded; logged entries can now carry an import/device provenance label such as "imported from Clue" — see Section 2.A and the Change History in Section 10; account deletion now also removes feedback attachments and tickets explicitly, and discloses the admin notification email's separate retention; data-portability export now includes a server-side record alongside your on-device data — see the Change History in Section 10; also strengthened at-rest/backup protection for the local database — see the Change History in Section 10; "Export my data" is now reachable without a cloud account, from a new "Your data" section in Settings — see the Change History in Section 10; tracked symptom/option observations are now stored the same way as flow and tags — see Section 2.A and the Change History in Section 10; added "Import from file" to the "Your data" section, restoring a previously exported JSON file on-device via a new file-picker permission surface — see the Change History in Section 10)

LunarLog ("we", "our", or "the app") is a privacy-first menstrual cycle and symptom tracker built for families: an account syncs a profile across a guardian's own devices and lets it be shared with other guardians — co-parents, caregivers — each with their own role, so sync and multi-guardian collaboration are the product's priority, not a bolted-on option. We believe that reproductive and menstrual health data is deeply personal and sensitive. LunarLog is architected from the ground up to protect your privacy: your data is protected at rest by each device's own operating-system encryption (Section 1), nothing you log is uploaded until you sign in, and the app keeps logging, viewing, and predicting even when you have no network connection.

This Privacy Policy explains what information LunarLog processes, how that information is protected, and the choices and rights you have.

---

## 1. Core Principles

- **Built For Sync & Family Collaboration:** LunarLog's account (Supabase Auth) is what lets a profile sync across a guardian's own devices and be shared with other guardians — co-parents and caregivers each get their own role, invitation, and attribution (Section 5). This is the product's priority and its differentiator, not an add-on; nothing about it changes what data is collected, only that sharing and multi-device sync are what the app is built to do.
- **Protected at Rest:** All data stored on your device relies on your operating system's own at-rest protection (iOS Data Protection / Android device encryption) and is only shown behind device-level biometric or passcode authentication. On Android, the local database is excluded from cloud backup and device-to-device transfer by declaration (a database backed up off-device would leave the app's own protections behind). On iOS, the app marks the database file excluded from backup and applies the strongest available file-protection class, so it stays unreadable whenever the device is locked, not only before its first unlock after a restart — verified on device before release.
- **No Advertising or Data Brokers:** We do not display advertisements, sell your data, monetize your health information, or share data with data brokers or tracking networks.
- **Resilient Offline:** The app keeps working without a network — logging, viewing history, and predictions all run from the copy already on your device, and nothing you do offline is blocked or degraded. This is a reliability property, not a requirement to avoid an account: LunarLog does not require an internet connection to be useful in the moment, but syncing and sharing a profile with other guardians does require signing in.
- **Estimates From Your Own Logged Data:** LunarLog estimates the timing of the next period from the cycle history you log, computed entirely on your device; a guardian who can see a profile's cycle data can see its estimates. Fertility-related estimation (fertile-window and ovulation estimates, derived from the profile's own logged cycle history) is part of the product's intended scope — it does not exist in the app as of this update — and when it ships it will follow these same protections and the same guardian-visibility and ownership-transfer rules as all other cycle data (Section 5). An earlier version of this policy guaranteed that no fertility feature would ever exist; that guarantee was removed by owner decision in September 2026 (see the Change History in Section 10). Conception and pregnancy features remain outside the product's scope.
- **Minimal, Scrubbed Telemetry:** Crash and diagnostic reports are strictly scrubbed on your device before transmission to ensure no health data, personal notes, dates, or user identities ever leave your device.

---

## 2. Information We Collect and Process

### A. Health & Cycle Information (Local & Optional Cloud Sync)
When you log entries in LunarLog, you may record:
- Dates and timestamps of menstrual cycles.
- Flow intensity levels (spotting, light, medium, heavy).
- Personal tags and custom notes.
- Individual tracked symptoms and options (e.g. a specific pain, mood, or body symptom; a numeric measurement like temperature; an intensity rating) — stored as their own records tied to the day they were logged, the same way flow and tags are, and covered by the same storage and sync rules described here.
- Import/device provenance: which entries were logged manually versus imported from a source such as Clue, Apple Health, or Health Connect, and an internal key identifying the specific import run — used to label an entry in the app (e.g. "Imported from Clue") and to avoid creating duplicate entries when the same import is run again. This label is metadata about how an entry was recorded, not a new category of health content, and is covered by the same storage and sync rules as the entry itself.
- Profile information (display name, sort order, archive status, minor status flag).

**Storage:** This information is stored directly on your device in a SQLite database protected by your operating system's at-rest protection (see Section 1). Signing in and enabling cloud sync is what moves it to your account, where it syncs across your own devices and to any guardian the profile is shared with; before you sign in, none of it leaves the device.

### B. Account & Authentication Information (Optional)
An account is what makes cross-device sync and sharing a profile with other guardians possible, and creating one remains your choice — a build with no cloud configuration has no account at all. You can log, view, and get predictions in LunarLog without ever creating an account. If you sign in and enable cross-device sync, we process:
- **Email Address:** Used for account verification, passwordless sign-in links, and password recovery.
- **Authentication Credentials:** Handled securely via Supabase Auth. We support email/password, passwordless magic links, Sign in with Apple, and Google Sign-In.
- **Provider Identifiers:** If you authenticate via Apple or Google, we store a cryptographic subject identifier (`sub`) provided by the identity provider to link your account. We do not access your contacts, external profile files, or social graphs.

**Upload Consent:** When you sign in on a device that already holds local data, LunarLog asks for your explicit consent before uploading existing records to your account.

### C. Support Ticket Information (Optional)

If you use "Send feedback" (Settings, signed-in accounts only), we process:
- **The message you write**, your category selection (bug, feature request, support, other), and the reply email address you provide (pre-filled from your account, editable).
- **Diagnostics you approve:** app version, build number, OS name and version, device model, active locale, and up to 25 recent in-app navigation/error breadcrumbs — never health data, account identity, or credentials. The app shows you the exact diagnostics payload and lets you turn it off before you submit.
- **An optional screenshot**, attached only after an explicit consent step naming the risk that a screenshot of this app usually contains cycle data for a family member.

None of this leaves your device until you tap submit. A ticket you send is visible to the app's operator team and to you, in the app's Support history. Submitting a ticket also sends a short alert email to the operator (the ticket id, category, app version, and submission time — not your message, reply email, or attachment). That alert email lives in the operator's own inbox under that inbox's own retention, separate from the database record described above — deleting a ticket or your account (see "Support Ticket Retention" in Section 7) removes the database record, not a copy already delivered by email.

### D. Technical & Crash Information (Diagnostics)
To maintain app stability and diagnose crashes, LunarLog includes optional telemetry powered by Sentry.
- **Strict Privacy Floor:** Before any error or crash report leaves your device, an automated client-side scrubber (`lib/observability/scrub.dart`) removes all health information, dates, flow levels, notes, tags, profile names, user IDs, device names, auth tokens, and request payloads. A crash report may additionally carry the *names of the screens you visited* before the crash (e.g. "Settings", "Feedback") — never their contents or arguments; an unrecognized or third-party screen name is reported as "unknown" rather than passed through.
- **Native crash reports bypass this on-device scrubber.** An Android app freeze, an Android native (NDK) crash, an iOS app hang, or an iOS watchdog termination is assembled and sent by the operating system's crash-reporting layer, not by this app's code — it never passes through the scrubber described above. These reports carry device, thread, and stack state, not app content (no note, tag, date, or profile name is ever held in a form a native crash report can capture), and the same server-side scrubbing and IP suppression covers them.
- **Optional performance measurement:** if the operator running the app has separately enabled it, LunarLog can also measure how long the app takes to start and how long some in-app operations take. When enabled, this carries operation timings and HTTP status codes — never a URL's query string, never a request body, and never anything from the allowlist above. This measurement is off by default in every release build.
- Crash data is anonymous, not linked to your identity or health records, and used solely for bug fixes and app performance.

---

## 3. How We Use Your Information

We use the information we process strictly for the following purposes:
1. **Core App Functionality:** Enabling you to log, view, and organize cycle records across profiles.
2. **Cross-Device Synchronization (Optional):** Mirroring your encrypted records across your authorized devices using row-level-secured cloud storage.
3. **App Reliability & Security:** Diagnosing technical faults and preventing unauthorized access through biometric locks and automated inactivity relocking.

We **do not** use your information for targeted advertising, marketing communications, automated profiling, or behavioral tracking.

---

## 4. Third-Party Service Providers

LunarLog limits third-party integration to essential operational infrastructure:

| Service | Purpose | Data Received | Location / Security |
| :--- | :--- | :--- | :--- |
| **Supabase** | Cloud authentication and database sync (optional) | Account email, encrypted cycle entries, authentication tokens | Encrypted in transit (TLS 1.3) and at rest (AES-256); Row-Level Security enforced |
| **Sentry** | Crash reporting and error diagnostics | Anonymized stack traces, OS version, device architecture, the names of screens visited before a crash, and (only when separately enabled) operation timings (all health/identity data stripped) | Client-side scrubbed for app-originated reports; a native crash report (Android NDK/ANR, iOS app hang/watchdog termination) is assembled by the operating system and is instead covered by server-side scrubbing and IP suppression; retained for a maximum of 90 days for debugging |
| **Apple (Sign in with Apple)** | Optional identity provider on iOS/macOS | Apple user identifier, relay email address (if selected) | Governed by Apple Privacy Policy |
| **Google (Google Sign-In)** | Optional identity provider | Google ID token (email and basic account identifier) | Governed by Google Privacy Policy |
| **Resend** | Transactional support email (an admin alert when you submit a ticket; the admin's reply email to you) | Reply email address and, for the reply you receive, the reply text | Governed by Resend's Privacy Policy |
| **Firebase Cloud Messaging (FCM)** | Optional remote push alerts to a caregiver when another guardian logs an entry, or when an expected entry hasn't arrived (only when a guardian turns this on; a build with no push configuration never contacts FCM at all) | Your device's push registration token and the profile's internal identifier only. Never a note, tag, flow level, date, or profile name - the notification you see on your lock screen is always the same fixed generic text the app's own local reminders already use | Governed by Google Privacy Policy; delivered over Apple/Google's push infrastructure (APNs on iOS, FCM on Android) |

No other third parties receive data from LunarLog.

---

## 5. Minors' Privacy & Family Profiles

LunarLog is intended to be operated by a parent, legal guardian, or adult individual. 
- **Two-stage custodian model:** A profile starts under the adult who created it, who holds both `profiles.user_id` (the account that can delete the record) and the profile's primary-guardian membership. That parent can later **transfer ownership** of a minor's profile to the minor's own account once they are ready to hold it themselves. Transferring moves both facts together to the child's account in a single operation and stamps the profile with when the move happened; every past entry keeps its original "logged by" attribution unchanged, so the record's history is never rewritten. The parent chooses, at the moment they initiate the transfer, whether they keep logging as a co-manager or drop to read-only; either way the parent's continued access afterward is an ordinary membership, not custodial control — the child can revoke it at any time, the same way any guardian can be removed from a shared profile. A parent who deletes their own account no longer removes a profile they have transferred away; conversely, if the child later deletes their own account, the profile and its history go with it, exactly as they would for any account holder.
- **No Direct Marketing or Tracking:** We do not knowingly collect personal data directly from children under 13 (or under 16 in certain jurisdictions) without parental consent. Minor profiles receive the same end-to-end encryption and protections as adult profiles and are never shared or analyzed.
- **Fertility Data Follows Cycle Data:** Fertility-related data and estimates, when they exist, receive no special-case handling of any kind: a guardian who can already see a profile's cycle data sees that profile's fertility data and estimates too, and fertility data transfers with the profile in an ownership transfer exactly like every other entry on it. The same feature set is available on every profile, including minor profiles, with no restriction — an explicit owner decision (September 2026), not a default.

---

## 6. Security Protections

We implement rigorous technical safeguards to ensure the security and confidentiality of your data:
- **Device Encryption:** The local database relies on your device's own operating-system-level encryption (iOS Data Protection / Android device encryption), shown to you only after biometric or passcode authentication.
- **Backup Exclusion:** On Android, the local database is excluded from both cloud backup and device-to-device transfer by declaration. On iOS, the app marks the database file excluded from backup and applies the strongest file-protection class so it is unreadable while the device is locked — verified on device before release.
- **Biometric Security:** Biometric authentication (Face ID / Touch ID / Android Biometrics) required to unlock the app.
- **Inactivity Timeout:** Configurable automatic relocking after inactivity, plus immediate locking upon backgrounding. The one exception is while a sign-in or unlock prompt the app itself opened is on screen: the system reports those the same way it reports you leaving, so locking is deferred for their duration. The app's contents stay masked throughout, the app relocks as soon as the prompt closes if you have left, and a prompt left open relocks the app after two minutes regardless of the inactivity setting.
- **Screen Obfuscation:** App switcher and lock screen previews are masked to prevent unauthorized viewing.
- **Transport Security:** All network transmissions use HTTPS with modern TLS (TLS 1.2/1.3) and strong cipher suites.
- **Database Row-Level Security:** Cloud database tables enforce PostgreSQL Row-Level Security (RLS) ensuring each user can only read and write their own rows.

---

## 7. Data Export & Retention & Deletion Rights

You have complete control over your data:
- **Export Your Data:** From Settings → Your data, "Export my data" saves a JSON file of your profiles and day entries (built entirely from the copy already on your device, so it works fully offline and without a cloud account - it needs only that at least one profile exists on this device) and hands it to your device's normal share sheet - AirDrop, Files, email, or any app you choose. The file includes every profile and day entry already synced to this device - your own profiles, and, if you are an accepted caregiver or co-parent on someone else's profile (multi-guardian sharing, Settings → Account), that profile's entries too, since those are the same records you can already view and log in the app. It never includes sync-protocol internals, other accounts' identifiers or tokens, or credentials. When you are signed in and online, the file additionally merges in a section covering your account's own server-side data - see the Data Portability entry below for what that includes; signed out, or without a network connection, the export still completes using only what is on this device, and the file records that the server step did not run. If you are exporting on a shared or borrowed device, review the file before sharing it further - it reflects everything that account can currently see, not only entries you personally logged.
- **Local Deletion:** You can delete individual cycle entries or entire profiles from the app at any time. Deleted records are tombstoned and permanently removed upon sync.
- **Sign Out & Local Wipe:** Signing out of your account gives you the option to discard all local database records from that device immediately.
- **Sign Out Everywhere:** You can invalidate sessions across all devices from the Account settings.
- **Account & Cloud Deletion:** From Settings → Account, "Delete account" immediately and permanently deletes your account: every server row you own (profiles, day entries, settings, your guardian memberships and invitations, and the small progress record kept for any bulk import you ran — a source label, row counts, status, and timestamps, no health content), the Supabase account itself (including, if you signed in with Apple, revoking that app's access via Apple's own revocation endpoint), and this device's local data. Your feedback tickets and their reply threads, and any attached screenshots, are also deleted explicitly as part of this same process (see "Support Ticket Retention" below) — not left to happen only as a side effect of the account being removed. The confirmation offers "Export first" so you can save a copy before proceeding. This is not a request queued for later - the server-side rows and the account are normally gone by the time the confirmation completes. The one exception: for an Apple-signed-in account, your data rows are deleted first and then, if Apple cannot confirm the revocation, the account sign-in itself is deliberately left in place rather than deleted with a live Apple grant still attached - the app tells you what happened and lets you retry, which completes the deletion. If any attached screenshot cannot be removed from storage, the same fail-closed rule applies: the deletion stops and is left retryable rather than completing with a screenshot left behind. You can still reach us at `will@wjdavis5.net` for any deletion the in-app flow does not cover (e.g. if you no longer have access to the device).
- **Support Ticket Retention:** Feedback tickets and their reply threads are retained to support ongoing conversations and app improvement; you can request deletion of a ticket at any time by emailing `will@wjdavis5.net`, and every ticket you own — along with any attached screenshot — is also removed automatically the moment you delete your account (see above): account deletion fails closed rather than completing with a ticket or screenshot left behind. Deleting a single ticket by emailing us (without deleting your whole account) removes the ticket and reply-thread database records themselves; an attached screenshot for that single-ticket case still needs your account to exist at request time so we can delete that file in the same pass, unlike the whole-account path above, which removes the screenshot itself as part of deleting the account. This narrower, request-only gap for a single ticket kept while your account remains open is a tracked improvement, not yet built.

---

## 8. Your Legal Rights (GDPR, CCPA, and Worldwide)

Depending on your jurisdiction (such as the European Economic Area, United Kingdom, California, and other US states), you have the right to:
- **Access:** Know what personal data is processed and request a copy.
- **Rectification:** Correct inaccurate or incomplete information.
- **Erasure:** Request that your personal data be permanently erased ("Right to be Forgotten").
- **Restrict or Object to Processing:** Object to or limit specific processing activities.
- **Data Portability:** Receive your data in a structured, commonly used, and machine-readable format - in-app via "Export my data" (Settings → Your data), which produces a JSON file and works whether or not you have a cloud account, and whether or not you are signed in. When you are signed in and online, the file additionally merges your locally stored profiles and day entries with the server's own record of your account under a `server` section: your guardian memberships and roles, the invitations and ownership transfers you created or accepted, your notification preferences, your registered devices (with each device's push token redacted to its last 4 characters), your feedback tickets and their reply threads, your reminder settings, and the progress record for any bulk import you ran (a source label, row counts, status, and timestamps, no health content). For a profile you share rather than own, that section covers only your own memberships, preferences, and the entries you personally logged - never another guardian's private data. The export always includes your on-device data - signed in or signed out, online or offline; the server section is included only when you are signed in and that network call succeeds, and the file records which happened (`serverIncluded`).
- **Withdraw Consent:** Withdraw consent for cloud synchronization or error reporting at any time.

To exercise any of these rights, please contact us at `will@wjdavis5.net`.

---

## 9. Apple App Store & Google Play Declarations

In compliance with Apple App Store Guidelines (including Guideline 5.1.1 and `PrivacyInfo.xcprivacy`) and Google Play Data Safety:
- **Data Used to Track You:** None (`NSPrivacyTracking: false`).
- **Data Linked to You:** Email Address (App Functionality), Health Information (App Functionality, only when cloud sync is active), Device Push Token (App Functionality, only when a guardian enables caregiver alerts on a build with push configured).
- **Data Not Linked to You:** Crash Data (App Functionality, fully anonymized).

---

## 10. Changes to this Privacy Policy

We may update this Privacy Policy from time to time to reflect improvements to the app, legal requirements, or architectural changes. The "Last Updated" date at the top of this document will always indicate when changes were made. Substantial changes will be highlighted in app release notes.

### Change History

- **September 9, 2026:** Sections 7 and 8 now disclose a small server-side progress record kept for a large bulk import (issue #167, the RPC that makes the Clue-import feature issue #159 laid the groundwork for actually able to complete): a source label, row counts, status, and timestamps, so the app can show progress and resume an interrupted import. No import feature exists yet as of this date. This record carries no health content whatsoever - no symptom, flow, or cycle data - and is treated exactly like every other server-side record already described here: it is included in "Export my data" and removed by "Delete account" along with the rest of your data, and it is never sent over the realtime sync channel.
- **September 9, 2026 (restore from file):** Added "Import from file" (issue #140) to the "Your data" section in Settings, the counterpart to "Export my data": it reads a JSON file this app previously exported, on-device only, and never uploads it anywhere — the file is picked through the operating system's own file picker (a new, disclosed permission surface: this app can now read a file you explicitly choose), parsed and validated locally, previewed (profile count, entry count, date range, and the merge policy) before anything is written, and then merged into the local store on explicit confirmation. Nothing already on the device is ever deleted or silently overwritten; a colliding entry is merged (tags combined, the heavier flow level kept, an existing note kept) and reported, not replaced. This does not add a new category of data collected — it is a second local read/write path for data this policy already covers.
- **September 9, 2026 (positioning):** Reframed this policy's product framing (issue #122): the opening summary and Core Principles (Section 1) now lead with the account, cross-device sync, and multi-guardian family sharing as the product's priority, and describe offline operation as a reliability property rather than the product's identity. No disclosure changed in substance — every fact that was true before (nothing uploads until you sign in, the local store is protected by the OS's own at-rest protection, an account remains optional and a build with no cloud configuration has none) remains true; only the framing and emphasis changed. Section 2.A's storage description was also reworded so it no longer reads as describing an app-managed "encrypted SQLite database" independent from Section 1's OS-at-rest-protection description — the two always meant the same thing and now say so consistently.
- **September 9, 2026:** Section 2.A now discloses import/device provenance (issue #159, the foundation for a future Clue/Apple Health/Health Connect import feature): entries and tracked symptoms can carry a label recording where they came from (e.g. "Imported from Clue") and an internal key used to avoid creating duplicates when the same import is run twice. No import feature exists yet as of this date — this column exists so a future importer has somewhere to write that label — but disclosing it now, rather than only when an importer ships, keeps this policy accurate about what the schema can already record. This is a new disclosed field, not a new category of data collected: it describes how an already-disclosed entry was recorded, the same local-first storage and optional-sync rules apply, and it is never used to identify or contact anyone.
- **September 8, 2026:** "Export my data" is now reachable without a cloud account (Issue #222; source B-17): it moved from the sign-in-gated Account section into a new "Your data" section in Settings that shows whenever at least one profile exists on the device, regardless of sign-in state. Signed out, the export still produces the same on-device-only document it always could (`serverIncluded: false`); signed in, it additionally merges the server-side section described in the Data Portability entry above (Section 8). "Delete account" is unchanged and still lives in the Account section, since account deletion is inherently account-scoped.
- **September 8, 2026:** Data Portability (Section 8) now describes the server-side half of "Export my data" (Issue #248): when signed in and online, the exported file merges a `server` section - guardian memberships/roles, invitations and ownership transfers you created or accepted, notification preferences, registered devices (push token redacted to its last 4 characters), feedback tickets and replies, and reminder settings - into the existing local export, scoped so a shared (non-owned) profile only ever surfaces your own memberships, preferences, and self-authored entries. The local half of export is unaffected and still works fully offline.
- **September 8, 2026 (tracking model foundation):** Section 2.A now discloses that individual tracked symptoms and options are stored as their own records tied to the day they were logged (issue #240), alongside flow and tags, rather than only as part of a day's flow/tag list — this is a storage-shape change, not a new category of data collected: these values are the same kind of cycle/symptom information the app already tracked, still local-first, still covered by the same optional-sync and guardian-visibility rules.
- **September 8, 2026:** Account deletion now removes the caller's feedback-attachment screenshots from storage and deletes feedback tickets (and their reply threads) explicitly, both as fail-closed steps of account deletion itself, rather than the tickets' removal depending only on a later step (revoking Apple, deleting the Supabase account) that could fail and the screenshots not being removed at all (issues D-24/D-25). Also added the disclosure, in Section 2.C, that submitting a ticket sends a short alert email to the operator with its own retention outside the app's database, separate from the ticket record itself.
- **September 8, 2026:** Strengthened the "Protected at Rest" principle and the "Device Encryption" security protection (issue #244): the local database moved to a directory that receives its own explicit backup handling — on iOS the app now marks the database file excluded from backup and applies the platform's strongest file-protection class (verified on device before release); on Android the database is excluded from both cloud backup and device-to-device transfer by declaration, alongside its existing backup-off setting.
- **September 7, 2026:** Removed the "No Fertility Tracking or Algorithms" Core Principle. The product owner decided (issues #123 and #142) to pursue full parity with a full cycle-tracking product, including ovulation and fertile-window estimation, so this policy no longer guarantees that fertility features will never exist. Those features do not exist in the app as of this date — today the app tracks cycles and flow and estimates the next period — and when they ship, fertility-related data and estimates will follow the same local-first protections and the same guardian-visibility and ownership-transfer rules as all other cycle data (Section 5). Conception and pregnancy features remain outside the product's scope.
- **September 6, 2026:** Added the Firebase Cloud Messaging disclosure for caregiver push alerts.
- **September 3, 2026:** Initial policy.

---

## 11. Contact Information

If you have any questions, concerns, or requests regarding this Privacy Policy or the handling of your data, please contact:

**William Davis (LunarLog Maintainer)**  
Email: [will@wjdavis5.net](mailto:will@wjdavis5.net)  
Repository: [https://github.com/wjdavis5/lunarlog](https://github.com/wjdavis5/lunarlog)  
Issues: [https://github.com/wjdavis5/lunarlog/issues](https://github.com/wjdavis5/lunarlog/issues)  
