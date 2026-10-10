# Verified findings ledger — e2e code review (working file, not committed)

Reviewed commit: 663ffc9107c408295fc234c269fa45a2254981cb (main at review time).
Verification rule: every finding below was re-read by the reviewer in the code before being kept.

## Flutter UI and platform (report 1, 6 findings, all verified)

1. [drift] Android has no `readCycleDeviations` case; Kotlin falls to `notImplemented()` (HealthConnectAdapter.kt:1423) while the codec table documents the method without an iOS-only caveat (health_channel_codec.dart:36) and `buildHealthDeviationInsights` is built for Android (`_healthImportPlatforms` includes android, app_dependencies.dart:940) and called after every import (health_sync_screen.dart:992, swallowed). iOS has the handler (AppDelegate.swift:1596).
2. [drift] PermissionsRationaleActivity.kt:80-85 tells users "Writing needs every write permission: while any one of them is off, lunarlog writes nothing", but since #1555 a partial grant writes the granted types (`writingSome`, health_flow_write_service.dart:756/981). The class doc at :27-28 is also stale ("nothing in this repo calls Health Connect yet").
3. [quality] Calendar symptom-layer selection is not reset on profile switch: `_layersUserSet`/`_activeLayers` (month_calendar.dart:781-782) survive `didUpdateWidget`'s profile-change branch (:1118-1138 resets entries and spotting only), so one profile's toggled layers apply to the next.
4. [risk] Reminder settings has no error path for its config load: `_ensureLoaded` (reminder_settings_screen.dart:282-306) has no catch, `build` re-kicks it on every rebuild while `_config == null` (:412-414), and `_body` renders a permanent spinner (:438). Other settings screens show InlineError on load failure.
5. [risk] One-shot guardian reads are uncaught: `_openPicker` loops `await guardians.getForProfile(...)` with no catch (home_widget_section.dart:127), invoked via `unawaited` from onTap (:105-107); a storage error makes the tap look dead. Watch-side reads use a fail-open safe wrapper (guardian_watch_mixin.dart:26-36).
6. [test-gap] health_deviation_card_test.dart:52-66 asserts only widget keys; the card's Text (health_deviation_card.dart:78-90) carries the l10n-composed label and range, which the test never asserts. A wrong label mapping would pass.

## React webapp and worker (report 2, 7 findings, all verified)

1. [bug] `useHasSyncSession` latches for the mount: the probe runs in `useEffect(..., [])` (queries.ts:56-91) and `hasSession` never updates after the first answer; `useDayView`'s uid uses the same one-shot shape (use-day.ts:40). The identity-change case this breaks is explicitly designed for (authQueries.ts:158-164).
2. [drift] Subject-invite minor check uses the UTC year (schemas.ts:335 `today.getUTCFullYear()`); the Dart rule uses the local year (profile.dart:142 `isMinorAsOf(today.year)`, callers pass local now). The two disagree around New Year west of UTC.
3. [quality] Dead reads: `fetchSettings` (domain.ts:844) and `fetchGuardianNotes` (domain.ts:868) have no importers; `SyncedData.guardian_notes` (domain.ts:276) is assigned only by emptySyncedData/mergeById and never by the pull; webapp/README.md:112-114 still documents the selects as live.
4. [risk] `startIdentityLink` returns `raw.url` with only a string/non-empty check (auth.ts:368-376) and AccountPage assigns it to window.location; the sibling `startAppleDelete` pins the host (auth.ts:407). No scheme/host check on the link route.
5. [test-gap] supabase.test.ts:63-69 asserts only `not.toThrow()` on the reset seam; the configured client path (memoisation, accessToken wiring) is never exercised in unit tests.
6. [drift] day-entry-policy.ts:7-10 says the file is a stopgap "deleted when the compiled module lands", but it is the write gate (payloads.ts:298) while DayPage prefers the module with this port as fallback (DayPage.tsx:218-235). Two copies of the date-bounds decision.
7. [quality] ManageGuardiansPage shows a blank page while the snapshot loads (and for an account with no profiles): the no-access branch needs `profiles.length > 0` (ManageGuardiansPage.tsx:138) and the fall-through renders an empty h1 (:166-170) with no loading state.

## Flutter core logic (report 3, 5 findings, all verified)

1. [drift] The local store is called "encrypted" in shipped metadata and docs while the reviewed posture is a plain sqlite3 file behind OS at-rest protection, no app cipher: pubspec.yaml:2 ("Offline, encrypted"), lib/data/README.md:1, account_export.dart:6, widget_data_store.dart:5, widget_cycle_state.dart:10. The posture itself is documented at db_factory.dart:8-13 and native_db.dart:1-4.
2. [drift] `_softDeleteObservation`'s doc lists `source_id` among the cleared payload columns (storage_local_writes.dart:1420-1423); the write deliberately keeps it, with an inline comment explaining issue #159 (sourceId survives a tombstone so a re-import recognises the row, :1445-1449).
3. [risk] Export decodes `observations.raw` with a bare `jsonDecode` (account_export.dart:536) while the sync codec guards the same field with a typed RowCodecError (row_codec.dart:530-538); the storage boundary only bounds the byte length (storage_local_writes.dart:322). Latent: every current writer emits valid JSON.
4. [quality] The import planner's observation identity key joins free-text fields with `|` (account_import.dart:2158-2159, used at :2169-2172), so a `|` inside category or code aliases two pairs; impact is one skipped row in an additive import.
5. [test-gap] supabase_account_deletion_service_test.dart:436-448 has no assertion after `await service.deleteAccount()`; it passes if the service does nothing. The sibling timeout test pins an observable outcome.

## Database (report 4, 5 findings, all verified)

1. [risk] Account deletion leaves a departing guardian's free-text notes live on shared profiles. `delete_account_data` (20260921100000_account_consents.sql:597) tombstones content only via `tombstone_profile_content` inside the owned-profiles loop (:646-677); that function tombstones ALL live notes on an owned profile (20260918150000_guardian_notes.sql:2860-2866), but nothing touches the caller's notes on profiles they only guard. The `logged_by_user_id ... on delete set null` cascade (:96) nulls the author, and the notes stay readable by every accepted guardian (:166-170). The revocation path removes them (20260918160000:153-160), so the stronger action (account deletion) leaves behind what the weaker one removes. No test covers it: `guardian_notes` appears in neither account_deletion_test.sql nor account_deletion_shared_data_test.sql.
2. [drift] AGENTS.md:53 says "nine per-table key allowlists" and omits `c_guardian_note_keys`; the live function carries ten (20261006163211:194), and the derived-allowlists test checks the tenth.
3. [quality] The `sync_push_sole_write_path` header (:15-18) claims every other client-writable table has no client write grant and "day_entries was the one exception"; in fact `profiles` (20260903014208:222), `observations` (20260908160000:333), `import_jobs` (20260908190000:238), and `notification_preferences` keep `grant select, insert` (plus others). The argument's inventory is inaccurate.
4. [test-gap] sync_pull_test.sql's tenant-isolation section asserts only `profiles` (:61-69) and `day_entries` (:71-75) against the outsider fixtures; the RPC returns eleven per-table keys, so nine branches have no foreign-row assertion.
5. [quality] Three migration headers name files that do not exist: 20260913017000_day_entries_column_grants.sql:1, 20260905110000_account_deletion.sql:1, 20260913030000_ownership_transfer_revoke_prediction_connections.sql:1 (each carries a pre-rename timestamp).

## Site and tooling (report 5, 8 findings, all verified; F1 and F2 reproduced at runtime)

1. [bug] check-advisor-gate.sh passes on empty stdin: `count` is an empty string, `[ "" -gt 0 ]` is false (printing `[: : integer expected`), and the script exits 0 with the "gate passed" line. Reproduced: `printf "" | bash .github/scripts/check-advisor-gate.sh` -> EXIT=0. The header (:63-66) promises malformed input is a hard failure. The test suite has no empty-input case.
2. [risk] check-destructive-sql.sh truncates each line at any `--`, including inside a string literal, before the statement-shape check. Reproduced: `INSERT INTO t VALUES (x--y); DROP TABLE users;` -> EXIT=0, no output; the control without the literal -> EXIT=1 and names the DROP.
3. [risk] scripts/asc.rb:117-118 prints "submitted for review: no" for any non-200 answer, so an expired key (401) or server failure reads as the reassuring answer; every other query in the script aborts on non-200.
4. [drift] AGENTS.md's site.yml path list omits three real triggers: `lib/ui/**`, `tool/screenshots/**` (issue #1104), and `webapp/**` (issue #1431) (site.yml:23-39).
5. [drift] check-ci-gate.sh's header (:6-10) enumerates the required checks without "Web app (lint, typecheck, unit, build, e2e)"; the script's own default (:48) and AGENTS.md include it. The header also says "Comma-separated" while the convention is `|`.
6. [quality] check-claims.mjs's top line says "Every factual claim in a guide carries a cite"; the enforced rule (:186-190) is at least one cite per guide.
7. [test-gap] tool/mutation_gate.dart's default scope claims to include uncommitted changes (:3-5) but runs `git diff --name-only` (:91), which misses untracked new lib/ files.
8. [drift] check-flutter-version-parity.sh's comments name `web-deploy.yml` (:8-9, :29), which no longer exists (only webapp-deploy.yml).

## Coverage statement for the final report

- Flutter app: core logic and UI/platform read by two scoped reviewers (domain/data exhaustive on the sync, health-ledger, import, export, deletion paths; UI sampled around state lifecycle, lenses, and error paths; prediction math not read).
- React clients: webapp src/worker exhaustive on auth, schemas, data layer, pages sampled; site worker and scripts exhaustive; site Astro pages sampled.
- Database: 114 migrations scanned by grep for every table/policy/grant/function/drop; about 45 read in whole; 15 pgTAP files read in whole.
- Not assessed: native Swift/Kotlin beyond the reviewed handlers; prediction math; most e2e suites; live runtime behavior of the apps.

## Citation corrections applied

- Report 1 F4 cited a sibling file `notification_preferences_screen.dart` that does not exist; the finding stands on the missing catch alone (other settings screens do use InlineError, e.g. import_screen.dart).
