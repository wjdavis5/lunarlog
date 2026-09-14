#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-ci-gate.sh. Run with:
#
#   bash .github/scripts/tests/check-ci-gate.test.sh
#
# Tests check evaluation, fail-fast behavior on failure/cancelled/timed_out,
# latest-attempt re-run handling, custom check sets, and poll simulation,
# using local JSON fixtures without making network calls.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-ci-gate.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

# Helper to write a check-runs JSON payload
# write_check_runs <filepath> <json_check_runs_array>
write_check_runs() {
  local filepath="$1"
  local runs="$2"
  cat >"$filepath" <<EOF
{
  "total_count": 10,
  "check_runs": $runs
}
EOF
}

# Fixture 1: All 3 required checks succeed
FIXTURE_ALL_PASS="$WORKDIR/all_pass.json"
write_check_runs "$FIXTURE_ALL_PASS" '[
  {"id": 100, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 101, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 90, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 91, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 92, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 93, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 102, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"},
  {"id": 103, "name": "Build iOS (unsigned)", "status": "completed", "conclusion": "success"}
]'

# Fixture 2: Database tests failed
FIXTURE_DB_FAIL="$WORKDIR/db_fail.json"
write_check_runs "$FIXTURE_DB_FAIL" '[
  {"id": 200, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "failure"},
  {"id": 201, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 290, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 291, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 292, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 293, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 202, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"}
]'

# Fixture 3: Quality gate cancelled
FIXTURE_CANCELLED="$WORKDIR/cancelled.json"
write_check_runs "$FIXTURE_CANCELLED" '[
  {"id": 300, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 301, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 390, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 391, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 392, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 393, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 302, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "cancelled"}
]'

# Fixture 4: Edge Functions timed out
FIXTURE_TIMEOUT="$WORKDIR/timeout.json"
write_check_runs "$FIXTURE_TIMEOUT" '[
  {"id": 400, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 401, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "timed_out"},
  {"id": 490, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 491, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 492, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 493, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 402, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"}
]'

# Fixture 5: Missing checks (Verify/Test shards/Quality gate all missing)
FIXTURE_MISSING="$WORKDIR/missing.json"
write_check_runs "$FIXTURE_MISSING" '[
  {"id": 500, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 501, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"}
]'

# Fixture 6: Re-run attempt (attempt 1 failed, attempt 2 passed)
FIXTURE_RERUN="$WORKDIR/rerun.json"
write_check_runs "$FIXTURE_RERUN" '[
  {"id": 600, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "failure"},
  {"id": 601, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 602, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 690, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 691, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 692, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 693, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 603, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"}
]'

# Fixture 7: In-progress check
FIXTURE_IN_PROGRESS="$WORKDIR/in_progress.json"
write_check_runs "$FIXTURE_IN_PROGRESS" '[
  {"id": 700, "name": "Database tests (pgTAP)", "status": "in_progress", "conclusion": null},
  {"id": 701, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 790, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 791, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 792, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 793, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 702, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"}
]'

# Fixture 8: Empty runs array
FIXTURE_EMPTY="$WORKDIR/empty.json"
write_check_runs "$FIXTURE_EMPTY" '[]'

# Fixture 10: current CI job names (post-#644 sharded layout) — used to prove the
# script's built-in default REQUIRED_CHECKS names checks that actually exist.
FIXTURE_CURRENT_LAYOUT="$WORKDIR/current_layout.json"
write_check_runs "$FIXTURE_CURRENT_LAYOUT" '[
  {"id": 1000, "name": "Database tests (pgTAP)", "status": "completed", "conclusion": "success"},
  {"id": 1001, "name": "Edge Functions (deno test)", "status": "completed", "conclusion": "success"},
  {"id": 1002, "name": "Verify (codegen, analyze, web build)", "status": "completed", "conclusion": "success"},
  {"id": 1003, "name": "Test (shard 0)", "status": "completed", "conclusion": "success"},
  {"id": 1004, "name": "Test (shard 1)", "status": "completed", "conclusion": "success"},
  {"id": 1005, "name": "Test (shard 2)", "status": "completed", "conclusion": "success"},
  {"id": 1006, "name": "Quality gate (coverage floor + CRAP)", "status": "completed", "conclusion": "success"}
]'

# Fixture 9: API Error payload
FIXTURE_API_ERROR="$WORKDIR/api_error.json"
cat >"$FIXTURE_API_ERROR" <<'EOF'
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest"
}
EOF

run_case() {
  local json_file="$1" required="$2" max_wait="${3:-0}" poll_interval="${4:-0}"
  local logfile
  logfile="$(mktemp)"
  set +e
  (
    export COMMIT_SHA="0123456789abcdef0123456789abcdef01234567"
    export CHECK_RUNS_JSON_FILE="$json_file"
    export REQUIRED_CHECKS="$required"
    export MAX_WAIT_SECONDS="$max_wait"
    export POLL_INTERVAL_SECONDS="$poll_interval"
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

DEFAULT_CHECKS="Database tests (pgTAP)|Edge Functions (deno test)|Verify (codegen, analyze, web build)|Test (shard 0)|Test (shard 1)|Test (shard 2)|Quality gate (coverage floor + CRAP)"

# Case 1: All required checks pass
run_case "$FIXTURE_ALL_PASS" "$DEFAULT_CHECKS"
assert_exit "all required checks pass exits 0" 0
assert_not_contains "all checks pass has no ::error::" "$LAST_LOG" "::error::"
assert_contains "log confirms Database tests passed" "$LAST_LOG" "✓ Database tests (pgTAP): success"
assert_contains "log confirms Edge Functions passed" "$LAST_LOG" "✓ Edge Functions (deno test): success"
assert_contains "log confirms Quality gate passed" "$LAST_LOG" "✓ Quality gate (coverage floor + CRAP): success"

# Case 2: Database tests failure fails fast
run_case "$FIXTURE_DB_FAIL" "$DEFAULT_CHECKS"
assert_exit "Database tests failure exits 1" 1
assert_contains "error message names failed check" "$LAST_LOG" "::error::Required check 'Database tests (pgTAP)' failed with conclusion 'failure'. Release blocked."

# Case 3: Quality gate cancelled fails fast
run_case "$FIXTURE_CANCELLED" "$DEFAULT_CHECKS"
assert_exit "cancelled check exits 1" 1
assert_contains "error message names cancelled check" "$LAST_LOG" "::error::Required check 'Quality gate (coverage floor + CRAP)' failed with conclusion 'cancelled'. Release blocked."

# Case 4: Edge functions timed out fails fast
run_case "$FIXTURE_TIMEOUT" "$DEFAULT_CHECKS"
assert_exit "timed_out check exits 1" 1
assert_contains "error message names timed_out check" "$LAST_LOG" "::error::Required check 'Edge Functions (deno test)' failed with conclusion 'timed_out'. Release blocked."

# Case 5: Missing check times out and exits 1
run_case "$FIXTURE_MISSING" "$DEFAULT_CHECKS" 0
assert_exit "missing check when max_wait=0 exits 1" 1
assert_contains "timeout error reported" "$LAST_LOG" "::error::Timed out after 0s waiting for required CI checks"
assert_contains "missing check named in state output" "$LAST_LOG" "Check 'Verify (codegen, analyze, web build)' was still in state 'missing'."

# Case 6: Re-run resolution takes higher id
run_case "$FIXTURE_RERUN" "$DEFAULT_CHECKS"
assert_exit "re-run attempt with newer success exits 0" 0
assert_not_contains "re-run success emits no error" "$LAST_LOG" "::error::"
assert_contains "log confirms Database tests success from second attempt" "$LAST_LOG" "✓ Database tests (pgTAP): success"

# Case 7: Custom check list
run_case "$FIXTURE_ALL_PASS" "Build iOS (unsigned)"
assert_exit "custom check list matching succeeds" 0
assert_contains "custom check listed in output" "$LAST_LOG" "✓ Build iOS (unsigned): success"

run_case "$FIXTURE_ALL_PASS" "Nonexistent Check" 0
assert_exit "custom nonexistent check fails" 1
assert_contains "nonexistent check reported missing" "$LAST_LOG" "Check 'Nonexistent Check' was still in state 'missing'."

# Case 8: Empty check runs payload
run_case "$FIXTURE_EMPTY" "$DEFAULT_CHECKS" 0
assert_exit "empty check runs exits 1" 1
assert_contains "empty runs times out" "$LAST_LOG" "::error::Timed out after 0s waiting for required CI checks"

# Case 9: API Error payload
run_case "$FIXTURE_API_ERROR" "$DEFAULT_CHECKS" 0
assert_exit "API error payload exits 1" 1
assert_contains "API error reported" "$LAST_LOG" "::error::Failed to verify CI checks"

# Case 10: Polling progression simulation (in_progress -> success)
run_case "$FIXTURE_IN_PROGRESS,$FIXTURE_ALL_PASS" "$DEFAULT_CHECKS" 5 0
assert_exit "simulated poll in_progress -> success exits 0" 0
assert_contains "first poll logs in_progress status" "$LAST_LOG" "⏳ Database tests (pgTAP): in_progress"
assert_contains "subsequent poll logs success" "$LAST_LOG" "✓ Database tests (pgTAP): success"

# Case 11: built-in default names the current (sharded) CI jobs — no REQUIRED_CHECKS override
run_case "$FIXTURE_CURRENT_LAYOUT" "" 0
assert_exit "built-in default passes on current CI job names" 0
assert_contains "default gate confirms Verify job" "$LAST_LOG" "✓ Verify (codegen, analyze, web build): success"
assert_contains "default gate confirms a Test shard" "$LAST_LOG" "✓ Test (shard 2): success"
assert_contains "default gate confirms Quality gate" "$LAST_LOG" "✓ Quality gate (coverage floor + CRAP): success"

print_summary "check-ci-gate.test.sh"
