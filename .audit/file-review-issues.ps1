# Files the verified bug/risk findings from the 2026-10-10 e2e code review.
# One-shot artifact; bodies are the review's evidence, reviewed commit 663ffc91.
$repo = 'wjdavis5/lunarlog'

$b1 = @'
## TL;DR

`useHasSyncSession` answers once, at mount, and never re-checks. A tab whose first probe resolves "no session" stays signed out for the life of the mount even after a session arrives through another tab, so the synced queries never enable and Today renders the signed-out home until a reload.

**Where:** `webapp/src/lib/queries.ts:56-91` (same one-shot shape in `webapp/src/lib/day/use-day.ts:40-54`).

## Evidence

The effect runs with `[]` deps and `hasSession` is set once from the first `getToken()` answer. The codebase explicitly designs for sessions that arrive without an auth mutation: `webapp/src/lib/authQueries.ts:158-164` ("a token renewal in a tab whose refresh cookie another tab's sign-in replaced"). In that tab, `useAuthSession` adopts the session on focus while `hasSession` stays false.

## Direction

Derive the flag from the auth-session query (or subscribe to the auth client) in both hooks.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Web: the session probe latches signed-out for the life of the mount' --body $b1 --label bug --label P2

$b2 = @'
## TL;DR

`startIdentityLink` returns the Worker's upstream authorize URL with only a string/non-empty check, and the page assigns it to `window.location`. A GoTrue that answers with an unexpected URL turns "link a sign-in method" into a top-level navigation anywhere.

**Where:** `webapp/src/lib/auth.ts:368-376`; caller `webapp/src/pages/AccountPage.tsx:210-212`.

## Evidence

The sibling ceremony pins its target: `startAppleDelete` rejects anything not starting with `APPLE_AUTHORIZE_URL` (`webapp/src/lib/auth.ts:407`) and has a hostile-value test. The link route has no scheme/host check. The CSP blocks `javascript:` but not an arbitrary `https://` destination.

## Direction

Apply the same prefix/scheme check the Apple path uses, and extend the hostile-value test to the link route.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Web: the identity-link redirect URL is not validated before navigation' --body $b2 --label bug --label P3

$b3 = @'
## TL;DR

Reminder settings has no error path for its config load. A failed read leaves `_config == null`, `build` re-kicks the load on every rebuild, and the body renders a permanent spinner with no message.

**Where:** `lib/ui/settings/reminder_settings_screen.dart:282-306` (no catch), `:412-414` (re-kick), `:438` (unconditional spinner).

## Evidence

`_ensureLoaded` awaits `Future.wait([service.load(...), modes.find(...)])` with no catch; a throw becomes an unhandled async error and the screen never leaves the spinner. Sibling settings screens render `InlineError` on load failure (for example `lib/ui/settings/import_screen.dart`).

## Direction

Catch the load, set an error field, and render `InlineError` with a retry instead of an unconditional spinner.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Flutter: reminder settings shows a permanent spinner when the config load fails' --body $b3 --label bug --label P2

$b4 = @'
## TL;DR

The home-widget profile picker resolves each active profile's guardians with uncaught one-shot reads. A storage error aborts the whole method, so the tap looks dead and the error becomes an unhandled async error.

**Where:** `lib/ui/settings/home_widget_section.dart:127` (loop over `guardians.getForProfile`), invoked via `unawaited` from `onTap` at `:105-107`. Same shape at `lib/ui/profiles/profile_picker_screen.dart:408-410`.

## Evidence

Every watch-side guardian read records and drops failures through the fail-open wrapper `watchGuardiansForProfileSafely` (`lib/ui/sharing/guardian_watch_mixin.dart:26-36`); `delete_account_dialog.dart:114-118` catches per profile. The one-shot reads do neither.

## Direction

Wrap the per-profile read (or the loop) in a catch and degrade to the empty-guardian fail-open path.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Flutter: one-shot guardian reads have no error path, so a storage error kills the action' --body $b4 --label bug --label P3

$b5 = @'
## TL;DR

The JSON export decodes `observations.raw` with a bare `jsonDecode`, while the sync codec guards the same field with a typed error. The invariant "raw is JSON text" is enforced nowhere: the storage boundary checks only byte length.

**Where:** `lib/domain/export/account_export.dart:536`; guard counterpart `lib/data/sync/row_codec.dart:530-538`; write-time validator `lib/data/db/storage_local_writes.dart:322`.

## Evidence

`'raw': o.raw == null ? null : jsonDecode(o.raw!)` throws an untyped `FormatException` out of the export flow for a malformed stored value. Latent today: every current writer emits valid JSON. The sync push path already defends with `RowCodecError(invalidRaw)`.

## Direction

Give the export the same typed guard, or validate `raw` parses as JSON in `_validateObservation` so every future writer is covered.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Flutter: export decodes observations.raw unguarded while the sync codec guards it' --body $b5 --label bug --label P3

$b6 = @'
## TL;DR

Account deletion tombstones guardian notes only on profiles the caller owns. On a shared profile, the departing guardian's free-text notes stay live (their author is nulled by the cascade), still readable by every remaining accepted guardian and still exported to the owner. Revocation removes the same notes, so the stronger action leaves behind what the weaker one removes.

**Where:** `supabase/migrations/20260921100000_account_consents.sql:597` (`delete_account_data`; owned loop at `:646-677` calls `tombstone_profile_content`, whose notes step is `20260918150000_guardian_notes.sql:2860-2866`); cascade `on delete set null` at `20260918150000:96`; select policy at `:166-170`; revocation contrast at `20260918160000_revoke_guardian_notes.sql:153-160`.

## Evidence

`delete_account_data` never references `guardian_notes` itself; the only notes tombstoning in the deletion path runs for owned profiles. `guardian_notes` appears in neither `supabase/tests/account_deletion_test.sql` nor `account_deletion_shared_data_test.sql`.

## Direction

Add the same `update public.guardian_notes ... where logged_by_user_id = v_uid` tombstone for non-owned profiles (or state the deliberate difference in PRIVACY.md and pin it with a pgTAP case).

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'DB: account deletion leaves a departing guardian''s notes live on shared profiles' --body $b6 --label bug --label P2

$b7 = @'
## TL;DR

The advisor gate passes on empty stdin. With no input, `count` is an empty string, `[ "" -gt 0 ]` is false, and the script reaches its "gate passed" line and exits 0, despite its header promising malformed input is a hard failure. Any CLI change that leaves stdout empty while exiting 0 turns this security gate into a green no-op.

**Where:** `.github/scripts/check-advisor-gate.sh:71-100`; header contract at `:63-66`.

## Evidence

Reproduced under bash: `printf "" | bash .github/scripts/check-advisor-gate.sh` prints `[: : integer expected` then `Database advisor gate passed ...` and exits 0. The jq guard only runs when a document exists. The test suite (`tests/check-advisor-gate.test.sh`) has no empty-input case.

## Direction

Reject empty input explicitly before invoking jq, and add the empty-input case to the truth table.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'CI: the advisor gate passes on empty stdin (fail-open against its own contract)' --body $b7 --label bug --label P2

$b8 = @'
## TL;DR

The destructive-SQL scan truncates every line at the first `--`, including inside a string literal, before the statement-shape check. A destructive statement later on the same line as a literal containing `--` is silently missed.

**Where:** `.github/scripts/check-destructive-sql.sh:61-75` (`strip_comments`); the header at `:41-46` frames the literal limitation as failing closed, which is false in the destructive direction.

## Evidence

Reproduced under bash: `printf "INSERT INTO t VALUES (x--y); DROP TABLE users;\n" | bash .github/scripts/check-destructive-sql.sh` exits 0 with no output; the same input without the literal exits 1 and names the `DROP TABLE`.

## Direction

Strip comments only outside quoted strings and dollar-quoted bodies, and add the string-literal case to `check-destructive-sql.test.sh`.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'CI: the destructive-SQL scan misses statements after -- inside a string literal' --body $b8 --label bug --label P2

$b9 = @'
## TL;DR

`asc.rb` reports "submitted for review: no" for any non-200 answer. An expired or revoked key (401) or a server failure (500) is indistinguishable from the endpoint's real "nothing submitted" (404), and the reassuring answer is exactly what this release-check tool exists to avoid.

**Where:** `scripts/asc.rb:117-118`.

## Evidence

`get` returns the status without aborting and the call ignores it; every other query in the script aborts on non-200 (`:78`, `:84`). `get` also maps an unparseable body to `{}` (`:69-74`), so a 200 with a non-JSON body reads as "none attached" rather than an error.

## Direction

Print `unknown (HTTP <code>)` or abort for anything but 200/404, and surface parse failures.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Tooling: asc.rb reports "submitted for review: no" for auth and server failures' --body $b9 --label bug --label P3

$b10 = @'
## TL;DR

Ten places where docs or comments contradict the shipped code, all verified by re-reading both sides during the 2026-10-10 e2e code review. Individually small; together they mislead reviewers and future re-emitters.

**Where and what:**
- `AGENTS.md:53` says "nine per-table key allowlists" and omits `c_guardian_note_keys`; the live `sync_push` carries ten (`supabase/migrations/20261006163211_sync_push_reimported_record_takeover.sql:194`).
- `pubspec.yaml:2` ("Offline, encrypted"), `lib/data/README.md:1`, `lib/domain/export/account_export.dart:6`, `lib/domain/widget/widget_data_store.dart:5`, `lib/domain/widget/widget_cycle_state.dart:10` call the local store encrypted; the reviewed posture is OS at-rest protection, no app cipher (`lib/data/db/db_factory.dart:8-13`, `lib/data/db/native_db.dart:1-4`).
- `lib/data/db/storage_local_writes.dart:1420-1423` lists `source_id` among the columns a tombstone clears; the write deliberately keeps it (issue #159, comment at `:1445-1449`).
- `lib/ui/settings/...` none; `android/.../PermissionsRationaleActivity.kt:80-85` says writes need every permission; since #1555 a partial grant writes the granted types. The class doc at `:27-28` is stale too ("nothing in this repo calls Health Connect yet").
- `lib/data/health/health_channel_codec.dart:36` documents `readCycleDeviations` without an iOS-only caveat; Android has no handler (`HealthConnectAdapter.kt:1423` falls to `notImplemented`) while the service is built for Android (`lib/composition/app_dependencies.dart:940`).
- `webapp/src/lib/schemas.ts:335` uses the UTC year for the minor check; the Dart rule uses the local year (`lib/domain/models/profile.dart:142`).
- `webapp/src/lib/day/day-entry-policy.ts:7-10` says the file is a stopgap to be deleted once the compiled module lands; it is the write gate (`webapp/src/lib/day/payloads.ts:298`) while the day page prefers the module with this port as fallback (`DayPage.tsx:218-235`). The README (`webapp/README.md:111-113`) still documents the `guardian_notes`/`settings` selects as live though their fetchers have no callers (`webapp/src/lib/domain.ts:844`, `:868`).
- `AGENTS.md`'s site.yml path list omits `lib/ui/**`, `tool/screenshots/**`, and `webapp/**` (`.github/workflows/site.yml:23-39`).
- `.github/scripts/check-ci-gate.sh:6-10` enumerates the required checks without "Web app (lint, typecheck, unit, build, e2e)" (its own default at `:48` includes it); the header also says "Comma-separated" while the convention is `|`.
- `.github/scripts/check-flutter-version-parity.sh:8-9,29` name `web-deploy.yml`, which no longer exists; `supabase/migrations/20260913017000_day_entries_column_grants.sql:1`, `20260905110000_account_deletion.sql:1`, and `20260913030000_ownership_transfer_revoke_prediction_connections.sql:1` each name a pre-rename filename in their first line.

Found by the 2026-10-10 e2e code review (reviewed commit 663ffc91).
'@
gh issue create --repo $repo --title 'Docs drift: ten places where docs or comments contradict the code (2026-10-10 review)' --body $b10 --label documentation
