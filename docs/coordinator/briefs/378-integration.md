Worktree C:/git/repos/lunarlog-wt/259-tracking-prefs (branch feat/259-tracking-prefs, PR #378, currently conflicts with main). Task: integrate PR #378 (issue #259, tracking preferences) with the just-merged #376 (schema v13, migration 20260909210000_profile_transferred_to_user_id.sql, sync_push re-emitted with transferred_to_user_id tolerated-not-read).

Because both branches bumped schemaVersion to 13 and re-emitted sync_push from different bases:
1. `git fetch origin && git rebase origin/main` (or merge — your call, no force-push).
2. RENUMBER: your schemaVersion 13 becomes 14 (main owns v13 now); rename your migration file to sort AFTER 20260909210000 (e.g. 20260909220000_...); regenerate drift_schemas/drift_schema_v14.json; bump the ci.yml codegen-freshness dump filename to v14; update test/data/db generated migration helpers/schema constants.
3. WEAVE sync_push: main's current body (from #376) + your tracking_preferences additions (allowlist key, parse, insert, containment-guarded update). Do not drop #376's transferred_to_user_id tolerated-not-read handling or any other carried section. Read main's current sync_push definition FIRST and rebase your additions onto it.
4. Update schema_migration_test constants and any pgTAP that asserts schema version; rerun the FULL pgTAP suite if Docker is available (else note it for CI).
5. Gates: export PATH="/c/src/flutter/bin:$PATH"; flutter pub get && flutter analyze && flutter test && dart run tool/quality_gate.dart — all green.
6. Push the branch (no force) and COMMENT on PR #378 summarizing the renumber + weave.

The PR body/ACs are unchanged; #259's own tests must still pass. Return ONLY: a three-sentence summary of the integration and green-gate evidence.
