# Claims ledger — lunarlog.app (issue #1105)

Every factual claim on the home page and the six feature pages maps to the
repo path (or the issue) that ships it. Reviewers check this ledger, not
their memory; `test/site/site_claims_test.dart` checks it mechanically:

- every `ships:` entry must be a repo path that exists (a path may carry a
  `(...)` annotation, which the test strips before checking);
- every claim carries at least one `ships:` path or one `issue:` reference;
- every page under `site/src/pages/` that makes product claims appears here.

Format, one `- claim:` bullet per claim:

```
- claim: the claim, in one line
  page: /the-page
  ships: lib/some/file.dart (what it proves); PRIVACY.md (§section)
  issue: #1105
```

`ships` entries are semicolon-separated repo paths, checked for existence
from the repo root. `issue` entries are semicolon-separated GitHub issue
numbers. Normative statements that no single file "ships" (positioning
calls, the default CTA) cite the doc or issue that made the call.

Unshipped features are deliberately absent: background health-platform sync
(issue #993, deferred), App Store / Google Play badges (listings not live —
issue #830), and any waitlist or email capture (the site collects nothing).

---

## Home — site/src/pages/index.astro

- claim: The browser app is the default call to action ("Use lunarlog in your browser" at app.lunarlog.app).
  page: /
  ships: site/src/pages/index.astro
  issue: #1105; #831
- claim: Free for personal use — stated in the hero fineprint alone (issue #1160: no security-speak in the hero; the no-ads stance leads on /privacy-security instead).
  page: /
  ships: README.md (License: PolyForm Noncommercial, free for personal use); pubspec.yaml (no billing dependency)
- claim: Sync and multi-guardian family collaboration are the product's lead, not an add-on.
  page: /
  ships: docs/product/positioning.md ("The family-collaboration story"); PRIVACY.md (§1 "Built For Sync & Family Collaboration")
  issue: #122
- claim: One account keeps several profiles, each shareable with its guardians.
  page: /
  ships: PRIVACY.md (§2.A "Profile information"); supabase/migrations/20260904010000_multi_guardian_schema.sql
- claim: A profile syncs across a guardian's own devices.
  page: /
  ships: supabase/migrations/20260903014211_sync_push.sql; PRIVACY.md (§3 "Cross-Device Synchronization")
- claim: Every entry carries the name of the person who logged it.
  page: /
  ships: PRIVACY.md (§2.A "Shared change history"; §5 attribution); supabase/migrations/20260916100000_day_entry_merge_events.sql
- claim: Same-date edits merge instead of overwriting, and both guardians see what happened.
  page: /
  ships: PRIVACY.md (§2.A "Same-date merge disclosures")
- claim: The shared month calendar shows what was logged beside the estimated days, always labelled as estimates (issue #1160: the home page links to /tracking for it instead of embedding a second near-the-fold PNG, which cost the Lighthouse performance budget).
  page: /
  ships: lib/l10n/app_en.arb (calendarCellPredictedPeriod, calendarCellPmsWindow); PRIVACY.md (§1 "Estimates From Your Own Logged Data")
- claim: The four roles are named exactly as the app names them (rendered from lib/l10n/app_en.arb via the UiLabel component).
  page: /
  ships: lib/l10n/app_en.arb (guardianRoleLabel*); site/src/components/UiLabel.astro; lib/domain/models/profile_guardian.dart
- claim: Role access is enforced by the server, not just the app.
  page: /
  ships: supabase/migrations/20260904010000_multi_guardian_schema.sql (RLS per role); PRIVACY.md (§5)
- claim: Direction one — you track for yourself, no account needed to log, and invite someone in with the role you choose; access is revocable.
  page: /
  ships: docs/product/positioning.md ("Either side can start"); lib/domain/sharing/invite_links.dart (issue #129); PRIVACY.md (§5)
- claim: Direction two — you set a profile up for someone else and invite them to log it themselves.
  page: /
  ships: docs/product/positioning.md ("Either side can start"); PRIVACY.md (§5 "Her Own Profile")
  issue: #802
- claim: Under-13 use begins only through a parent's invitation, and accepting it is the parental-consent record.
  page: /
  ships: PRIVACY.md (§5 "Minimum-Age Policy")
  issue: #957
- claim: A guardian can turn on optional alerts — when another guardian logs an entry, or when an expected entry hasn't arrived — and the lock-screen text is fixed and generic, never what was logged (issue #1160: "reminders that reach the right person" beat).
  page: /
  ships: PRIVACY.md (§4 FCM row); lib/domain/notifications/scheduling.dart (kReminderTitle, kReminderBody); supabase/functions/_shared/notification_copy.ts
- claim: Logging, history, and estimates work offline; sync resumes when a connection returns.
  page: /
  ships: PRIVACY.md (§1 "Resilient Offline")
- claim: Import from Clue, Apple Health, or Health Connect — user-initiated, never over a hand-logged value.
  page: /
  ships: lib/data/import/clue_importer.dart; lib/data/health/health_import_service.dart; PRIVACY.md (§2.A import provenance; §4 health paragraph)
- claim: Export as JSON, CSV, FHIR, or a one-page PDF — built on the device, no account required.
  page: /
  ships: PRIVACY.md (§7); lib/domain/export/account_export.dart; lib/domain/export/csv_export.dart; lib/domain/export/fhir_bundle.dart; lib/domain/export/clinical_pdf.dart
- claim: Estimates are computed on the device from a profile's own logged history and carry a confidence tier.
  page: /
  ships: PRIVACY.md (§1 "Estimates From Your Own Logged Data"); lib/l10n/app_en.arb (cycleConfidence*)
- claim: Estimates only — not medical advice.
  page: /
  ships: lib/domain/help/help_cards.dart ("Estimates only — not medical advice.")
- claim: The device copy sits behind the device's own lock.
  page: /
  ships: PRIVACY.md (§1 "Protected at Rest"; §6 "Biometric Security")
- claim: Sync runs over TLS into row-level-secured storage and is not end-to-end encrypted.
  page: /
  ships: PRIVACY.md (§6 "Cloud Storage Encryption — not end-to-end")
- claim: lunarlog is licensed 13 and up; someone younger uses it only through a parent's invitation.
  page: /
  ships: PRIVACY.md (§5 "Minimum-Age Policy")
  issue: #957
- claim: The screenshots on this site are rendered from the app by a scripted tool, not hand-captured.
  page: /
  ships: tool/screenshots/manifest.dart; site/scripts/screenshots.mjs
  issue: #1104
- claim: The full privacy policy at /privacy is the same document the app's own privacy dialog reads.
  page: /
  ships: site/src/pages/privacy.astro (renders PRIVACY.md at build time)
  issue: #1101

## Tracking and viewing — site/src/pages/tracking.astro

- claim: A day records flow (from an explicit "not bleeding today" note through super heavy), spotting, symptoms with intensity, numeric readings such as basal-body temperature, tags, and a note.
  page: /tracking
  ships: PRIVACY.md (§2.A health & cycle information list)
- claim: Flow and symptoms are stored as their own records tied to their day, not flattened into one text field.
  page: /tracking
  ships: PRIVACY.md (§2.A "stored as their own records tied to the day they were logged"); lib/data/db/tables.dart (day_entries, observations)
- claim: The calendar shows logged bleeds and tags, with the estimated next period, cycle days, and the estimated premenstrual window, always labelled as estimates.
  page: /tracking
  ships: lib/l10n/app_en.arb (calendarCellPredictedPeriod, calendarCellCycleDayFirstCycle, calendarCellPmsWindow)
- claim: Estimates are computed entirely on the device from the cycle history the profile holds — no other signal.
  page: /tracking
  ships: PRIVACY.md (§1 "Estimates From Your Own Logged Data")
- claim: Every estimate carries a confidence tier (high, provisional, rough, learning).
  page: /tracking
  ships: lib/l10n/app_en.arb (cycleConfidenceHigh, cycleConfidenceProvisional, cycleConfidenceRough, cycleConfidenceLearning)
- claim: A profile with too little history says so instead of guessing ("Keep logging — estimated bands appear once a few cycles are recorded.").
  page: /tracking
  ships: lib/l10n/app_en.arb (calendarKeepLogging)
- claim: lunarlog also estimates a fertile window and an ovulation day from the same history, and must not be used to prevent pregnancy.
  page: /tracking
  ships: PRIVACY.md (§1 fertile-window paragraph)
- claim: Logging, history, and estimates run from the device copy offline; edits and deletions work any time and deletions are permanently removed from synced copies.
  page: /tracking
  ships: PRIVACY.md (§1 "Resilient Offline"; §7 "Local Deletion")
- claim: A day note the profile's subject marks private is readable only by them; guardians see a placeholder; the choice exists only at write time.
  page: /tracking
  ships: PRIVACY.md (§5 "Guardian Roles & Read Visibility")
- claim: Estimates are not medical advice; talk to a clinician when worried.
  page: /tracking
  ships: lib/domain/help/help_cards.dart ("Estimates only — not medical advice. If something worries you, talk ...")

## Family sharing and roles — site/src/pages/family-sharing.astro

- claim: Entries are attributed to the person who logged them, and the server enforces role permissions.
  page: /family-sharing
  ships: supabase/migrations/20260904010000_multi_guardian_schema.sql; lib/domain/models/profile_guardian.dart
- claim: Primary Guardian and Co-Parent can log, edit the profile, and manage guardians; only the Primary Guardian can delete the profile or transfer ownership.
  page: /family-sharing
  ships: lib/domain/models/profile_guardian.dart (canLog, canEditProfile, canManageGuardians, canDeleteProfile)
- claim: Caregivers can log but cannot edit the profile or manage guardians.
  page: /family-sharing
  ships: lib/domain/models/profile_guardian.dart (canLog true, canEditProfile false)
- claim: Viewers are view-only — they cannot log or edit.
  page: /family-sharing
  ships: lib/domain/models/profile_guardian.dart (canLog false for viewer); PRIVACY.md (§5 "a viewer cannot log or edit entries")
- claim: Every accepted guardian reads everything logged on the profile, whatever their role; the one exception is the subject's own private day note.
  page: /family-sharing
  ships: PRIVACY.md (§5 "Guardian Roles & Read Visibility")
- claim: Either direction can start — a subject inviting a guardian in, or a guardian setting a profile up and inviting the subject; neither is the "real" one.
  page: /family-sharing
  ships: docs/product/positioning.md ("Either side can start")
- claim: Invitations are single-use links; the inviter picks the role and can change or revoke it later.
  page: /family-sharing
  ships: lib/domain/sharing/invite_links.dart (issue #129); PRIVACY.md (§5)
- claim: The subject invitation renders the app's own labels ("Her own profile"; "This is your profile") via UiLabel.
  page: /family-sharing
  ships: lib/l10n/app_en.arb (manageGuardiansPendingSubjectLabel, profilePickerSubjectSubtitle); site/src/components/UiLabel.astro
  issue: #802
- claim: When the subject accepts, their logging is attributed to their name while guardians keep access, symmetrically in both directions.
  page: /family-sharing
  ships: PRIVACY.md (§5 "Her Own Profile — subject membership")
- claim: For someone under 13 the invitation is the only way the app begins, and accepting it is the parental-consent record.
  page: /family-sharing
  ships: PRIVACY.md (§5 "Minimum-Age Policy")
  issue: #957
- claim: Accounts are for people 13 and older.
  page: /family-sharing
  ships: PRIVACY.md (§5 "Minimum-Age Policy")
- claim: Ownership of a minor's profile can transfer to the subject's own account in one step, with every entry's original attribution unchanged; the parent stays as co-manager or read-only, and the new owner can revoke that access.
  page: /family-sharing
  ships: lib/domain/sharing/ownership_transfer_service.dart; PRIVACY.md (§5 "Two-stage custodian model")
  issue: #4
- claim: Same-date merges keep the losing value briefly in a disclosure its author can recover, visible only to guardians, never in a notification, permanently deleted after 30 days.
  page: /family-sharing
  ships: PRIVACY.md (§2.A "Same-date merge disclosures"; §7 "Server-Side Retention Windows"); supabase/migrations/20260916100000_day_entry_merge_events.sql
- claim: A guardian can opt in to alerts when another guardian logs an entry or when an expected entry hasn't arrived (issue #1160 retitle: "Reminders that reach the right person"); the push payload carries only a token and profile id — never a note, tag, flow level, date, or profile name; the visible text is fixed and generic.
  page: /family-sharing
  ships: PRIVACY.md (§4 FCM row); lib/domain/notifications/scheduling.dart (kReminderTitle, kReminderBody); supabase/functions/_shared/notification_copy.ts
- claim: A build with no push configuration never contacts a push service.
  page: /family-sharing
  ships: PRIVACY.md (§4 FCM row); lib/config.dart (AppConfig.hasPush)
- claim: A prediction-only connection shows estimated days on a read-only calendar to one other account — never entries, notes, symptoms, or guardian access — and is refused for minor profiles by the server.
  page: /family-sharing
  ships: PRIVACY.md (§5 "Prediction-Only Sharing Excludes Minors"); lib/domain/sharing/prediction_connection_service.dart

## Life-stage modes — site/src/pages/life-stage-modes.astro

- claim: Every profile runs in exactly one of five modes: Period Tracking, Conceive, Pregnancy, Perimenopause, Postpartum.
  page: /life-stage-modes
  ships: lib/domain/models/lifecycle_mode.dart (LifecycleMode); supabase/migrations/20260909000000_profile_modes_and_cycle_overrides.sql (profile_modes_mode_check)
- claim: Period Tracking is the default mode.
  page: /life-stage-modes
  ships: lib/domain/models/lifecycle_mode.dart (fromDb falls back to tracking)
- claim: Conceive mode adds an estimated fertile window and a daily-chance reading framed with the research behind it.
  page: /life-stage-modes
  ships: lib/l10n/app_en.arb (conceiveWindowLabel, conceivePeakDay)
- claim: Pregnancy mode pauses the period estimate and counts by week from an estimated due date.
  page: /life-stage-modes
  ships: lib/l10n/app_en.arb (predictionsSuppressedByModeBody, pregnancyWeekTitle)
- claim: Perimenopause mode pauses the period estimate while logging and history continue.
  page: /life-stage-modes
  ships: lib/l10n/app_en.arb (predictionsSuppressedByModeBody names Pregnancy, Postpartum, or Perimenopause)
- claim: Postpartum mode counts the days of postpartum and offers to log when a first bleed arrives.
  page: /life-stage-modes
  ships: lib/l10n/app_en.arb (postpartumDayTitle; the postpartum overview offer, issue #455)
- claim: Switching modes is free and reversible and never deletes or rewrites logged data; estimates recompute from the same history.
  page: /life-stage-modes
  ships: lib/domain/models/lifecycle_mode.dart ("a switch never deletes or rewrites day_entries/observations")
- claim: The fertile-window estimate is derived from the profile's own logged history and must not be used to prevent pregnancy.
  page: /life-stage-modes
  ships: PRIVACY.md (§1 fertile-window paragraph)
- claim: Paused estimates say so openly instead of showing a stale prediction.
  page: /life-stage-modes
  ships: lib/l10n/app_en.arb (predictionsSuppressedTitle "Estimates paused", predictionsSuppressedByModeBody)
  issue: #528
- claim: A separate reading level (standard, teen, supported-care framing) changes vocabulary, composes with any life-stage mode, and teen framing is suggested once, never forced.
  page: /life-stage-modes
  ships: lib/domain/models/profile_mode.dart (issue #131); lib/l10n/app_en.arb (subjectTeenModeDialogTitle, subjectTeenModeDialogBody); lib/domain/models/lifecycle_mode.dart (orthogonality note)
  issue: #802

## Import — site/src/pages/import.astro

- claim: Import is always started by you; nothing runs in the background or on a schedule.
  page: /import
  ships: lib/data/health/health_import_service.dart ("Bound, never background"); PRIVACY.md (§4 "Reading is user-initiated and on-demand only")
- claim: The Clue import previews what it will add before it runs, and the same file imported twice adds nothing twice.
  page: /import
  ships: lib/ui/settings/import_screen.dart (pick -> preview -> confirm -> result); lib/data/import/clue_importer.dart (checksum-derived source_id, idempotent re-import)
- claim: Clue imports are stamped as imported from Clue, so imported history stays distinguishable.
  page: /import
  ships: lib/data/import/clue_importer.dart (source 'clue_import'); PRIVACY.md (§2.A import provenance)
- claim: Apple Health (iPhone) and Health Connect (Android) imports read menstrual-flow history — the whole history the store holds, a page at a time.
  page: /import
  ships: lib/data/health/health_import_service.dart (whole-history pages, issue #992); PRIVACY.md (§4 health paragraph)
- claim: A value you logged by hand is never overwritten by an import.
  page: /import
  ships: lib/data/health/health_import_service.dart (additive rule); lib/data/import/clue_importer.dart (same rule); PRIVACY.md (§4)
- claim: Entries lunarlog wrote to the health store itself are excluded from an import, so a round trip never doubles history.
  page: /import
  ships: lib/data/health/health_import_service.dart (source filtering); PRIVACY.md (§4 "Samples this app itself wrote are excluded by source filtering")
- claim: Imported days are labelled with their source, on the one profile the device is bound to.
  page: /import
  ships: lib/data/health/health_import_service.dart (provenance stamping, HealthSyncBinding); PRIVACY.md (§2.A)
- claim: An interrupted import is safe to re-run — nothing is duplicated.
  page: /import
  ships: lib/data/health/health_import_service.dart (idempotent source_id contract)
- claim: On iPhone, Apple's computed cycle deviations are shown as a labelled, dismissible second opinion — never merged into your data, never written back.
  page: /import
  ships: PRIVACY.md (§4 four computed cycle-deviation types paragraph)
- claim: A lunarlog JSON export can be restored on any device — additive, overwrites nothing, no account required.
  page: /import
  ships: lib/domain/import/account_import.dart; lib/data/import/account_importer.dart; PRIVACY.md (§7)
  issue: #140
- claim: Importing works on the device copy; nothing leaves the device unless you sign in and turn on sync.
  page: /import
  ships: PRIVACY.md (§2.A "before you sign in, none of it leaves the device"; §1 "Resilient Offline")

## Export — site/src/pages/export.astro

- claim: Every export is built on your device from Settings → Your data and handed to your share sheet; no account is required.
  page: /export
  ships: PRIVACY.md (§7 "Export Your Data"; §4 "Clinical export is a user-initiated transfer")
- claim: The JSON export contains every profile and entry visible on this device, with author attribution, and works fully offline.
  page: /export
  ships: PRIVACY.md (§7 "Export Your Data"); lib/domain/export/account_export.dart
- claim: The CSV export produces a per-cycle table and a day-per-row table with notes and tags in their own columns, escaped against spreadsheet formula injection.
  page: /export
  ships: PRIVACY.md (§7 "Export as CSV"); lib/domain/export/csv_export.dart
- claim: The FHIR export is an FHIR R4 bundle using LOINC and SNOMED CT codes only where a verified mapping exists (never a guessed code), labelled self-reported throughout, and carrying only the profile's display name.
  page: /export
  ships: PRIVACY.md (§7 "Export a Clinical Summary — FHIR"); lib/domain/export/fhir_bundle.dart; lib/domain/export/clinical_terminology.dart
- claim: The PDF export is a one-page clinician summary carrying the display name only and no note text.
  page: /export
  ships: PRIVACY.md (§7 "Export a Clinical Summary — PDF"); lib/domain/export/clinical_pdf.dart
- claim: No export is uploaded by lunarlog; the destination is always your choice.
  page: /export
  ships: PRIVACY.md (§4 "Clinical export is a user-initiated transfer, not collection")
- claim: A note the subject marked private is omitted from a guardian's JSON and CSV; the FHIR and PDF never include note text at all; the subject's own export includes their private notes.
  page: /export
  ships: PRIVACY.md (§7 "Export Your Data" guardian-lens rule)
- claim: A lunarlog export can be read back in — additive, nothing overwritten.
  page: /export
  ships: lib/domain/import/account_import.dart; lib/data/import/account_importer.dart
  issue: #140
- claim: Entries and whole profiles can be deleted in the app any time; account deletion is its own immediate flow.
  page: /export
  ships: PRIVACY.md (§7 "Local Deletion"; "Account & Cloud Deletion"); site/src/pages/delete-account.astro

## Privacy and security — site/src/pages/privacy-security.astro

- claim: The full policy is the canonical PRIVACY.md, rendered at /privacy — the same document the app reads.
  page: /privacy-security
  ships: site/src/pages/privacy.astro; PRIVACY.md
  issue: #1101
- claim: No advertising, no data brokers, no behavioral tracking, no data sale; third parties are a short named list.
  page: /privacy-security
  ships: PRIVACY.md (§1 "No Advertising or Data Brokers"; §3; §4)
- claim: Crash reports are scrubbed on the device before transmission — health data, notes, dates, and identity removed.
  page: /privacy-security
  ships: PRIVACY.md (§1 "Minimal, Scrubbed Telemetry"; §2.D); lib/observability/scrub.dart
- claim: An account is optional; before you sign in nothing leaves the device.
  page: /privacy-security
  ships: PRIVACY.md (§2.B; §2.A storage paragraph)
- claim: The local database relies on the OS's own at-rest protection, shown only after biometric or passcode authentication.
  page: /privacy-security
  ships: PRIVACY.md (§1 "Protected at Rest"; §6 "Device Encryption")
- claim: An optional in-app PIN, automatic inactivity relocking, immediate lock on leaving, and masked app-switcher previews.
  page: /privacy-security
  ships: PRIVACY.md (§6 "Optional In-App PIN", "Inactivity Timeout", "Screen Obfuscation")
- claim: The database is excluded from cloud backups on both platforms.
  page: /privacy-security
  ships: PRIVACY.md (§6 "Backup Exclusion")
- claim: Sync is not end-to-end encrypted: TLS in transit, AES-256 at rest in Supabase's Postgres, no client-side cipher — entries are readable Postgres columns protected by row-level security and infrastructure controls.
  page: /privacy-security
  ships: PRIVACY.md (§6 "Cloud Storage Encryption — not end-to-end")
- claim: Row-level security returns only the rows a guardian's memberships entitle them to.
  page: /privacy-security
  ships: PRIVACY.md (§6 "Database Row-Level Security")
- claim: A signed-in browser keeps synced data and the session in browser storage, outside operating-system protection.
  page: /privacy-security
  ships: PRIVACY.md (§6 "Signed-In Browser Build — Web")
- claim: Guardian alerts carry only a push token and profile identifier; visible text is fixed and generic.
  page: /privacy-security
  ships: PRIVACY.md (§4 FCM row); lib/domain/notifications/scheduling.dart (kReminderTitle, kReminderBody)
- claim: lunarlog is licensed 13+; under-13 use happens only through a parent's invitation, whose acceptance is the parental-consent record.
  page: /privacy-security
  ships: PRIVACY.md (§5 "Minimum-Age Policy")
  issue: #957
- claim: Minor profiles receive exactly the same protections as adult profiles and are never shared or analyzed.
  page: /privacy-security
  ships: PRIVACY.md (§5 "No Direct Marketing or Tracking")
- claim: Guardian notes on a young person's profile are visible to every guardian, including the young person once they hold an account; the app never offers a hidden note about a child.
  page: /privacy-security
  ships: PRIVACY.md (§5 "Guardian Notes Are Visible To The Child")
  issue: #800
- claim: Account deletion is immediate and permanent — server rows and the account — not a queued request; entries and profiles can be deleted any time.
  page: /privacy-security
  ships: PRIVACY.md (§7 "Account & Cloud Deletion"; "Local Deletion"); supabase/functions/delete-account/index.ts
- claim: A few narrow bookkeeping records age out on fixed schedules; the policy lists every one.
  page: /privacy-security
  ships: PRIVACY.md (§7 "Server-Side Retention Windows")
