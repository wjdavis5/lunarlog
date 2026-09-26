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

# ---------------------------------------------------------------------------
# Case 19: Dynamic scan: all static paths read by readRepoFile('...') in test/
# ---------------------------------------------------------------------------
# Ensures every external repository path read by a Dart release guard test
# will trigger app_flutter=true when modified in a PR.
python3 -c "
import os, re, subprocess, sys

regex = re.compile(r'''readRepoFile\(['\"]([^'\"\$]+)['\"]\)''')
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
        print(f'FAIL: readRepoFile path {path} did not result in app_flutter=true', file=sys.stderr)
        failed = True

if failed:
    sys.exit(1)
"
assert_eq "Dynamic scan of all readRepoFile paths classify to app_flutter=true" "0" "$?"

print_summary "detect-ci-changes.test.sh"
