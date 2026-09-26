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
# Case 4: Database migration changes
# ---------------------------------------------------------------------------
db_output="$(run_detect "supabase/migrations/20260920000000_test.sql
supabase/tests/database/auth_test.sql")"
assert_contains "Database sets database=true" "$db_output" "database=true"
assert_contains "Database sets app_flutter=false" "$db_output" "app_flutter=false"
assert_contains "Database sets edge_functions=false" "$db_output" "edge_functions=false"

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

print_summary "detect-ci-changes.test.sh"
