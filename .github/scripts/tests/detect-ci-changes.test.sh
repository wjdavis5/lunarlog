#!/usr/bin/env bash
# .github/scripts/tests/detect-ci-changes.test.sh
#
# Unit tests for .github/scripts/detect-ci-changes.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../detect-ci-changes.sh"
# shellcheck source=.github/scripts/tests/lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

run_detect() {
  local changed="$1"
  CHANGED_FILES_OVERRIDE="$changed" bash "$SCRIPT"
}

# ---------------------------------------------------------------------------
# Case 1: Cloudflare Worker changes only
# ---------------------------------------------------------------------------
cf_output="$(run_detect "workers/email/src/index.ts
site/worker/index.ts")"
assert_contains "CF workers set edge_functions=true" "$cf_output" "edge_functions=true"
assert_contains "CF workers set app_flutter=false" "$cf_output" "app_flutter=false"
assert_contains "CF workers set database=false" "$cf_output" "database=false"
assert_contains "CF workers set release_guards=false" "$cf_output" "release_guards=false"

# ---------------------------------------------------------------------------
# Case 2: Documentation only changes
# ---------------------------------------------------------------------------
docs_output="$(run_detect "docs/ops/inbound-email.md
README.md
CONCEPTS.md")"
assert_contains "Docs set app_flutter=false" "$docs_output" "app_flutter=false"
assert_contains "Docs set database=false" "$docs_output" "database=false"
assert_contains "Docs set edge_functions=false" "$docs_output" "edge_functions=false"
assert_contains "Docs set release_guards=false" "$docs_output" "release_guards=false"

# ---------------------------------------------------------------------------
# Case 3: Marketing site only changes
# ---------------------------------------------------------------------------
mkt_output="$(run_detect "marketing/assets/hero.png")"
assert_contains "Marketing set app_flutter=false" "$mkt_output" "app_flutter=false"
assert_contains "Marketing set database=false" "$mkt_output" "database=false"
assert_contains "Marketing set edge_functions=false" "$mkt_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 4a: Database config / generated snapshot changes (database only)
# ---------------------------------------------------------------------------
db_config_output="$(run_detect "supabase/config.toml
supabase/database.types.ts")"
assert_contains "Database config sets database=true" "$db_config_output" "database=true"
assert_contains "Database config sets app_flutter=false" "$db_config_output" "app_flutter=false"
assert_contains "Database config sets edge_functions=false" "$db_config_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 4b: Database migrations and pgTAP tests (database + app_flutter for pgtap_counts_test)
# ---------------------------------------------------------------------------
db_sql_output="$(run_detect "supabase/migrations/20260920000000_test.sql
supabase/tests/database/auth_test.sql")"
assert_contains "Database SQL sets database=true" "$db_sql_output" "database=true"
assert_contains "Database SQL sets app_flutter=true" "$db_sql_output" "app_flutter=true"
assert_contains "Database SQL sets edge_functions=false" "$db_sql_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 5: Flutter app changes
# ---------------------------------------------------------------------------
flutter_output="$(run_detect "lib/domain/models/day_entry.dart
test/domain/models/day_entry_test.dart")"
assert_contains "Flutter app sets app_flutter=true" "$flutter_output" "app_flutter=true"
assert_contains "Flutter app sets database=false" "$flutter_output" "database=false"
assert_contains "Flutter app sets edge_functions=false" "$flutter_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 6: Flutter web client files (root web/, not workers)
# ---------------------------------------------------------------------------
web_client_output="$(run_detect "web/index.html
web/_headers")"
assert_contains "Web client sets app_flutter=true" "$web_client_output" "app_flutter=true"
assert_contains "Web client sets edge_functions=false" "$web_client_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 7: Release guard scripts changes
# ---------------------------------------------------------------------------
guards_output="$(run_detect ".github/scripts/check-ci-gate.sh")"
assert_contains "Scripts set release_guards=true" "$guards_output" "release_guards=true"
assert_contains "Scripts set app_flutter=false" "$guards_output" "app_flutter=false"

# ---------------------------------------------------------------------------
# Case 8: CI workflow definition changes (.github/workflows/ci.yml)
# ---------------------------------------------------------------------------
ci_output="$(run_detect ".github/workflows/ci.yml")"
assert_contains "CI workflow sets app_flutter=true" "$ci_output" "app_flutter=true"
assert_contains "CI workflow sets database=true" "$ci_output" "database=true"
assert_contains "CI workflow sets edge_functions=true" "$ci_output" "edge_functions=true"
assert_contains "CI workflow sets release_guards=true" "$ci_output" "release_guards=true"

# ---------------------------------------------------------------------------
# Case 9: Mixed changes (Flutter + Database)
# ---------------------------------------------------------------------------
mixed_output="$(run_detect "lib/data/db/db.dart
supabase/migrations/20260926000000_schema.sql")"
assert_contains "Mixed sets app_flutter=true" "$mixed_output" "app_flutter=true"
assert_contains "Mixed sets database=true" "$mixed_output" "database=true"
assert_contains "Mixed sets edge_functions=false" "$mixed_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 10: Sync bridge code changes (lib/data/sync/*)
# ---------------------------------------------------------------------------
sync_output="$(run_detect "lib/data/sync/sync_service.dart
test/data/sync/sync_test.dart")"
assert_contains "Sync sets app_flutter=true" "$sync_output" "app_flutter=true"
assert_contains "Sync sets database=true" "$sync_output" "database=true"
assert_contains "Sync sets edge_functions=false" "$sync_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 11: Change detection script itself changed (.github/scripts/detect-ci-changes.sh)
# ---------------------------------------------------------------------------
script_output="$(run_detect ".github/scripts/detect-ci-changes.sh")"
assert_contains "Script itself sets app_flutter=true" "$script_output" "app_flutter=true"
assert_contains "Script itself sets database=true" "$script_output" "database=true"
assert_contains "Script itself sets edge_functions=true" "$script_output" "edge_functions=true"
assert_contains "Script itself sets release_guards=true" "$script_output" "release_guards=true"

# ---------------------------------------------------------------------------
# Case 12: Empty/undetermined diff -> failsafe sets all to true
# ---------------------------------------------------------------------------
empty_output="$(run_detect "")"
assert_contains "Empty diff sets app_flutter=true" "$empty_output" "app_flutter=true"
assert_contains "Empty diff sets database=true" "$empty_output" "database=true"
assert_contains "Empty diff sets edge_functions=true" "$empty_output" "edge_functions=true"
assert_contains "Empty diff sets release_guards=true" "$empty_output" "release_guards=true"

# ---------------------------------------------------------------------------
# Case 13: AGENTS.md (checked by test/release/pgtap_counts_test.dart)
# ---------------------------------------------------------------------------
agents_output="$(run_detect "AGENTS.md")"
assert_contains "AGENTS.md sets app_flutter=true" "$agents_output" "app_flutter=true"
assert_contains "AGENTS.md sets database=false" "$agents_output" "database=false"
assert_contains "AGENTS.md sets edge_functions=false" "$agents_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 14: docs/product/voice-and-copy.md (checked by test/release/branding_identity_test.dart)
# ---------------------------------------------------------------------------
voice_output="$(run_detect "docs/product/voice-and-copy.md")"
assert_contains "voice-and-copy.md sets app_flutter=true" "$voice_output" "app_flutter=true"
assert_contains "voice-and-copy.md sets edge_functions=false" "$voice_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 15: supabase/functions/* (checked by test/release/branding_identity_test.dart)
# ---------------------------------------------------------------------------
fn_shared_output="$(run_detect "supabase/functions/_shared/notification_copy.ts")"
assert_contains "notification_copy.ts sets edge_functions=true" "$fn_shared_output" "edge_functions=true"
assert_contains "notification_copy.ts sets app_flutter=true" "$fn_shared_output" "app_flutter=true"
assert_contains "notification_copy.ts sets database=false" "$fn_shared_output" "database=false"

# ---------------------------------------------------------------------------
# Case 16: Database migration workflows (.github/workflows/supabase-migrate.yml)
# ---------------------------------------------------------------------------
migrate_wf_output="$(run_detect ".github/workflows/supabase-migrate.yml")"
assert_contains "supabase-migrate.yml sets database=true" "$migrate_wf_output" "database=true"
assert_contains "supabase-migrate.yml sets release_guards=true" "$migrate_wf_output" "release_guards=true"
assert_contains "supabase-migrate.yml sets app_flutter=false" "$migrate_wf_output" "app_flutter=false"

# ---------------------------------------------------------------------------
# Case 17: Release workflows read by Dart tests (sentry_symbols_test.dart)
# ---------------------------------------------------------------------------
release_wf_output="$(run_detect ".github/workflows/ios-release.yml
.github/scripts/upload-sentry-symbols-setup.sh")"
assert_contains "Release workflow sets release_guards=true" "$release_wf_output" "release_guards=true"
assert_contains "Release workflow sets app_flutter=true" "$release_wf_output" "app_flutter=true"
assert_contains "Release workflow sets database=false" "$release_wf_output" "database=false"

# ---------------------------------------------------------------------------
# Case 18: site/public/* and docs/links/* (checked by link_artifacts_test.dart)
# ---------------------------------------------------------------------------
links_output="$(run_detect "site/public/invite.html
docs/links/apple-app-site-association")"
assert_contains "Hosted link assets set app_flutter=true" "$links_output" "app_flutter=true"
assert_contains "Hosted link assets set database=false" "$links_output" "database=false"

# A pure site/public/* change must classify on its own (issue #1344): the
# site/* arm shadowed the site/public/* alternative entirely, and this
# case's mixed list used to hide that -- invite.html alone classified
# app_flutter=false, so link_artifacts_test.dart never ran on such a PR.
site_public_only_output="$(run_detect "site/public/invite.html")"
assert_contains "pure site/public change sets app_flutter=true" "$site_public_only_output" "app_flutter=true"
assert_contains "pure site/public change keeps edge_functions=true" "$site_public_only_output" "edge_functions=true"

# ---------------------------------------------------------------------------
# Case 19: Dynamic scan: all static paths read by readRepoFile('...') or
# File('...') in test/
# ---------------------------------------------------------------------------
# Ensures every external repository path read by a Dart release guard test
# will trigger app_flutter=true when modified in a PR. Issue #1122 asked for
# the scan and #1368 extended it: the original regex matched only
# readRepoFile('...'), while test/site/ reads its guard inputs
# (site/claims.md, site/src/pages/*.astro, site/scripts/check-axe.mjs,
# site/lighthouserc.cjs, PRIVACY.md, ...) directly through dart:io's
# File('...'), so those paths were never flagged. \bFile\( keeps the match
# off suffixed identifiers (FakePickedFile, XFile, ...) the same way the
# unanchored readRepoFile alternative stays off readRepoFile's tail; the
# [^$] capture class still skips string interpolations, exactly as before.
python3 -c "
import os, re, subprocess, sys

regex = re.compile(r'''(?:readRepoFile|\bFile)\(['\"]([^'\"\$]+)['\"]\)''')
found = set()
for root, _, files in os.walk('test'):
    for f in files:
        if f.endswith('.dart'):
            with open(os.path.join(root, f)) as fh:
                for m in regex.findall(fh.read()):
                    found.add(m)

script = '$SCRIPT'
failed = False
for path in sorted(found):
    env = dict(os.environ, CHANGED_FILES_OVERRIDE=path)
    res = subprocess.run(['bash', script], capture_output=True, text=True, env=env)
    if 'app_flutter=true' not in res.stdout:
        print(f'FAIL: readRepoFile/File path {path} did not result in app_flutter=true', file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)
"
assert_eq "Dynamic scan of all readRepoFile/File paths classify to app_flutter=true" "0" "$?"

# ---------------------------------------------------------------------------
# Case 12: React web client changes (webapp/**, issue #1249)
# ---------------------------------------------------------------------------
webapp_output="$(run_detect "webapp/src/App.tsx
webapp/worker/index.ts")"
assert_contains "Webapp sets webapp=true" "$webapp_output" "webapp=true"
assert_contains "Webapp sets app_flutter=false" "$webapp_output" "app_flutter=false"
assert_contains "Webapp sets database=false" "$webapp_output" "database=false"
assert_contains "Webapp sets edge_functions=false" "$webapp_output" "edge_functions=false"

# ---------------------------------------------------------------------------
# Case 12b: The web data layer (webapp/src/lib/**, webapp/test/integration/**,
# issue #1252) is typed against the schema snapshot and integration-tested
# against the live stack, so it also turns on the database suite. UI paths
# outside src/lib stay webapp-only (Case 12).
# ---------------------------------------------------------------------------
web_domain_output="$(run_detect "webapp/src/lib/domain.ts
webapp/test/integration/domain.integration.test.ts")"
assert_contains "Web data layer sets webapp=true" "$web_domain_output" "webapp=true"
assert_contains "Web data layer sets database=true" "$web_domain_output" "database=true"
assert_contains "Web data layer sets app_flutter=false" "$web_domain_output" "app_flutter=false"

# ---------------------------------------------------------------------------
# Case 13: The schema snapshot also feeds the webapp's typed client (#1249)
# ---------------------------------------------------------------------------
types_output="$(run_detect "supabase/database.types.ts")"
assert_contains "Types snapshot sets webapp=true" "$types_output" "webapp=true"
assert_contains "Types snapshot sets database=true" "$types_output" "database=true"

# ---------------------------------------------------------------------------
# Case 14: The arb feeds the webapp catalogue AND the Flutter localizations
# ---------------------------------------------------------------------------
arb_output="$(run_detect "lib/l10n/app_en.arb")"
assert_contains "Arb sets webapp=true" "$arb_output" "webapp=true"
assert_contains "Arb sets app_flutter=true" "$arb_output" "app_flutter=true"

# ---------------------------------------------------------------------------
# Case 15: CI workflow / detection script changes run the webapp suite too
# ---------------------------------------------------------------------------
assert_contains "CI workflow sets webapp=true" "$ci_output" "webapp=true"
assert_contains "Detection script itself sets webapp=true" "$script_output" "webapp=true"

# ---------------------------------------------------------------------------
# Case 16: The Dart domain the web client compiles (#1251) rebuilds and
# re-tests the webapp AND keeps the app's own Flutter suites
# ---------------------------------------------------------------------------
domain_output="$(run_detect "lib/domain/prediction/prediction.dart
lib/domain/export/account_export.dart")"
assert_contains "Domain engine sets webapp=true" "$domain_output" "webapp=true"
assert_contains "Domain engine sets app_flutter=true" "$domain_output" "app_flutter=true"

entrypoint_output="$(run_detect "tool/web_domain/main.dart
tool/web_domain/facade.dart")"
assert_contains "Domain facade sets webapp=true" "$entrypoint_output" "webapp=true"
assert_contains "Domain facade sets app_flutter=true" "$entrypoint_output" "app_flutter=true"

# ---------------------------------------------------------------------------
# Case 20: integration_test/gate_test.dart is read by
# .github/scripts/tests/ios-simulator-budgets.test.sh (issue #1317), which
# pins every testWidgets( call's `timeout: _kTestTimeout` bound -- so a
# gate_test-only PR must run the release-guards suites too. Without that,
# a breaking gate_test edit merges green (release_guards=false skips the
# budgets suite) and the next unrelated .github/** PR goes red. It is
# still a Flutter integration test, so app_flutter stays on as well.
# ---------------------------------------------------------------------------
gate_test_output="$(run_detect "integration_test/gate_test.dart")"
assert_contains "gate_test.dart sets release_guards=true" "$gate_test_output" "release_guards=true"
assert_contains "gate_test.dart keeps app_flutter=true" "$gate_test_output" "app_flutter=true"
assert_contains "gate_test.dart sets database=false" "$gate_test_output" "database=false"
assert_contains "gate_test.dart sets edge_functions=false" "$gate_test_output" "edge_functions=false"

# The rest of integration_test/* keeps the old app_flutter-only mapping.
other_it_output="$(run_detect "integration_test/smoke_test.dart")"
assert_contains "other integration tests keep app_flutter=true" "$other_it_output" "app_flutter=true"
assert_contains "other integration tests keep release_guards=false" "$other_it_output" "release_guards=false"

# ---------------------------------------------------------------------------
# Case 21: Release-guard suite inputs (issue #1344) -- the bash suites under
# .github/scripts/tests/ read repo files via ../../../ and pin what those
# files carry:
#   - check-links-deploy.test.sh reads site/package.json (its :18) and
#     site/public/_headers (its :648) -- the pinned astro/@lhci/cli/
#     axe-core versions and the CSP/HSTS/X-Frame-Options/
#     Permissions-Policy headers.
#   - check-ios-widget-signing.test.sh reads ios/ExportOptions-ci.plist and
#     both .entitlements files (its :17-19) -- the two-bundle App Group
#     signing posture (issue #141 / PR #1007).
# A PR touching only these used to classify release_guards=false, skip both
# suites, merge green, and turn the next unrelated .github/** PR red (the
# issue #1317 failure class). Each must match before the generic site/* and
# ios/* arms, which set only edge_functions/app_flutter.
# ---------------------------------------------------------------------------
headers_output="$(run_detect "site/public/_headers")"
assert_contains "_headers sets release_guards=true" "$headers_output" "release_guards=true"
assert_contains "_headers keeps edge_functions=true" "$headers_output" "edge_functions=true"

site_pkg_output="$(run_detect "site/package.json")"
assert_contains "site/package.json sets release_guards=true" "$site_pkg_output" "release_guards=true"
assert_contains "site/package.json keeps edge_functions=true" "$site_pkg_output" "edge_functions=true"

plist_output="$(run_detect "ios/ExportOptions-ci.plist")"
assert_contains "ExportOptions-ci.plist sets release_guards=true" "$plist_output" "release_guards=true"
assert_contains "ExportOptions-ci.plist keeps app_flutter=true" "$plist_output" "app_flutter=true"

entitlements_output="$(run_detect "ios/Runner/Runner.entitlements
ios/LunarLogWidget/LunarLogWidget.entitlements")"
assert_contains "entitlements set release_guards=true" "$entitlements_output" "release_guards=true"
assert_contains "entitlements keep app_flutter=true" "$entitlements_output" "app_flutter=true"

# Other ios/* and site/* files keep their old single-suite mapping -- the
# arms above are pinned to the files the suites actually read.
other_ios_output="$(run_detect "ios/Runner/Info.plist")"
assert_contains "other ios files keep app_flutter=true" "$other_ios_output" "app_flutter=true"
assert_contains "other ios files keep release_guards=false" "$other_ios_output" "release_guards=false"
other_site_output="$(run_detect "site/worker/index.ts")"
assert_contains "other site files keep edge_functions=true" "$other_site_output" "edge_functions=true"
assert_contains "other site files keep release_guards=false" "$other_site_output" "release_guards=false"

# ---------------------------------------------------------------------------
# Case 21b: Site copy and claims-ledger guard inputs (issue #1368) -- the
# Flutter suites under test/site/ read these with File('...'):
#   - site_claims_test.dart reads site/claims.md (its setUpAll) and the
#     site/src/pages/*.astro sources of its `pages` map;
#   - store_pages_test.dart reads site/src/pages/delete-account.astro and
#     support.astro, site/src/pages/sitemap.xml.ts, site/scripts/check-axe.mjs
#     and site/lighthouserc.cjs.
# A PR touching only these used to classify app_flutter=false (the generic
# site/* arm set edge_functions only) and site.yml runs no flutter test, so
# the site-copy edit merged green and the next unrelated Flutter PR went red
# on an assertion it never touched (issue #1317's failure class). Each must
# match before the generic site/* arm, which sets only edge_functions.
# ---------------------------------------------------------------------------
claims_ledger_output="$(run_detect "site/claims.md")"
assert_contains "site/claims.md sets app_flutter=true" "$claims_ledger_output" "app_flutter=true"
assert_contains "site/claims.md keeps edge_functions=true" "$claims_ledger_output" "edge_functions=true"
assert_contains "site/claims.md keeps release_guards=false" "$claims_ledger_output" "release_guards=false"

site_pages_output="$(run_detect "site/src/pages/index.astro")"
assert_contains "site/src/pages set app_flutter=true" "$site_pages_output" "app_flutter=true"
assert_contains "site/src/pages keep edge_functions=true" "$site_pages_output" "edge_functions=true"

site_components_output="$(run_detect "site/src/components/Screenshot.astro")"
assert_contains "site/src/components set app_flutter=true" "$site_components_output" "app_flutter=true"
assert_contains "site/src/components keep edge_functions=true" "$site_components_output" "edge_functions=true"

site_scripts_output="$(run_detect "site/scripts/check-axe.mjs")"
assert_contains "site/scripts set app_flutter=true" "$site_scripts_output" "app_flutter=true"
assert_contains "site/scripts keep edge_functions=true" "$site_scripts_output" "edge_functions=true"

lighthouserc_output="$(run_detect "site/lighthouserc.cjs")"
assert_contains "site/lighthouserc.cjs sets app_flutter=true" "$lighthouserc_output" "app_flutter=true"
assert_contains "site/lighthouserc.cjs keeps edge_functions=true" "$lighthouserc_output" "edge_functions=true"

# Other site/* files keep the old edge_functions-only mapping -- the arm
# above is pinned to the paths the test/site suites actually read.
astro_config_output="$(run_detect "site/astro.config.mjs")"
assert_contains "other site files keep edge_functions=true (astro.config)" "$astro_config_output" "edge_functions=true"
assert_contains "other site files keep app_flutter=false (astro.config)" "$astro_config_output" "app_flutter=false"

# ---------------------------------------------------------------------------
# Case 21c: Doc and webapp guard inputs the Case 19 File('...') scan swept
# in (issue #1368) -- each is read by a Flutter test via File('...') and was
# swallowed by the docs/*, *.md or webapp/* arms:
#   - PRIVACY.md (test/site/privacy_header_test.dart,
#     privacy_background_gate_test.dart,
#     privacy_browser_error_reporting_test.dart, site_claims_test.dart and
#     store_pages_test.dart)
#   - docs/ops/store-declarations.md (store_pages_test.dart)
#   - docs/web/security-posture.md
#     (privacy_browser_error_reporting_test.dart)
#   - webapp/src/domain/schemas.ts and webapp/test/domain/fixtures.json
#     (test/domain/web_domain_fixtures_test.dart -- the webapp suites stay
#     on too; the arm shadows the generic webapp arms and restates
#     webapp=true on purpose)
# ---------------------------------------------------------------------------
privacy_output="$(run_detect "PRIVACY.md")"
assert_contains "PRIVACY.md sets app_flutter=true" "$privacy_output" "app_flutter=true"

store_decl_output="$(run_detect "docs/ops/store-declarations.md")"
assert_contains "store-declarations.md sets app_flutter=true" "$store_decl_output" "app_flutter=true"

security_posture_output="$(run_detect "docs/web/security-posture.md")"
assert_contains "security-posture.md sets app_flutter=true" "$security_posture_output" "app_flutter=true"

webapp_schemas_output="$(run_detect "webapp/src/domain/schemas.ts")"
assert_contains "webapp schemas.ts sets app_flutter=true" "$webapp_schemas_output" "app_flutter=true"
assert_contains "webapp schemas.ts keeps webapp=true" "$webapp_schemas_output" "webapp=true"

webapp_fixtures_output="$(run_detect "webapp/test/domain/fixtures.json")"
assert_contains "webapp fixtures.json sets app_flutter=true" "$webapp_fixtures_output" "app_flutter=true"
assert_contains "webapp fixtures.json keeps webapp=true" "$webapp_fixtures_output" "webapp=true"

# Other docs and webapp files keep their old mapping -- the arms above are
# pinned to the files the suites actually read.
go_live_output="$(run_detect "docs/ops/supabase-go-live.md")"
assert_contains "other docs keep app_flutter=false" "$go_live_output" "app_flutter=false"
other_webapp_output="$(run_detect "webapp/src/App.tsx")"
assert_contains "other webapp files keep app_flutter=false" "$other_webapp_output" "app_flutter=false"
assert_contains "other webapp files keep webapp=true" "$other_webapp_output" "webapp=true"

# ---------------------------------------------------------------------------
# Case 22: Dynamic scan: all repo files read via ../../../ in the bash
# release-guard suites (issue #1344)
# ---------------------------------------------------------------------------
# Mirrors Case 19 for the bash suites: every repository path a suite under
# .github/scripts/tests/ reads through ../../../ must classify
# release_guards=true, so a suite cannot silently start pinning a new file
# that change detection never routes to the release-guards jobs. Directory
# reads (check-flutter-version-parity.test.sh's .github/workflows) are
# skipped: a directory itself is never a PR's changed path, and its
# contents are covered by the generic .github/workflows/* arm. Pure bash
# on purpose -- driving the detector through a python subprocess breaks on
# a Windows host (env vars do not cross into WSL bash, so every run would
# hit the detector's all-true failsafe and the scan could only false-pass).
scan_failed=0
while IFS= read -r scan_path; do
  [ -z "$scan_path" ] && continue
  [ -f "$scan_path" ] || continue
  scan_output="$(CHANGED_FILES_OVERRIDE="$scan_path" bash "$SCRIPT")"
  case "$scan_output" in
    *"release_guards=true"*) ;;
    *)
      echo "FAIL: bash-suite read path $scan_path did not result in release_guards=true (add a release_guards arm to detect-ci-changes.sh)" >&2
      scan_failed=1
      ;;
  esac
done <<EOF
$(grep -hoE '\.\./\.\./\.\./[A-Za-z0-9_./-]+' "$SCRIPT_DIR"/*.test.sh | sed 's#^\.\./\.\./\.\./##' | sort -u)
EOF
assert_eq "Dynamic scan of all bash-suite ../../../ reads classify to release_guards=true" "0" "$scan_failed"

print_summary "detect-ci-changes.test.sh"
