#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-release-gate.sh. Run with:
#
#   bash .github/scripts/tests/check-release-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-release-gate.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

# run_case RELEASE_GATE_ACCOUNT_DELETION RELEASE_GATE_MODE REQUIRE_PRODUCTION_CONFIRMATION CONFIRM_PRODUCTION
# Populates: $LAST_EXIT $LAST_LOG $LAST_GATE_OPEN
run_case() {
  local gate="$1" mode="$2" require_confirm="$3" confirm="$4"
  local logfile outfile
  logfile="$(mktemp)"
  outfile="$(mktemp)"
  set +e
  (
    export RELEASE_GATE_ACCOUNT_DELETION="$gate"
    export RELEASE_GATE_MODE="$mode"
    export REQUIRE_PRODUCTION_CONFIRMATION="$require_confirm"
    export CONFIRM_PRODUCTION="$confirm"
    export GITHUB_OUTPUT="$outfile"
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  LAST_GATE_OPEN="$(grep -o 'gate_open=.*' "$outfile" 2>/dev/null | tail -1 | cut -d= -f2 || true)"
  rm -f "$logfile" "$outfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# --- Basic gate scenarios (no production confirmation requirement) ---

run_case "shipped" "" "" ""
assert_exit "gate=shipped exits 0" 0
assert_not_contains "gate=shipped has no error annotation" "$LAST_LOG" "::error::"

run_case "" "" "" ""
assert_exit "unset gate variable exits non-zero" 1
assert_contains "unset gate error names issue #17" "$LAST_LOG" "issue #17"
assert_contains "unset gate error names the variable" "$LAST_LOG" "RELEASE_GATE_ACCOUNT_DELETION"

run_case "" "" "" ""
assert_exit "empty gate variable exits non-zero (duplicate of unset)" 1

run_case "true" "" "" ""
assert_exit "truthy-but-wrong value 'true' exits non-zero" 1

run_case "Shipped" "" "" ""
assert_exit "mixed-case 'Shipped' exits 0" 0

run_case " shipped " "" "" ""
assert_exit "surrounding whitespace tolerated, exits 0" 0

run_case "" "warn" "" ""
assert_exit "gate closed + RELEASE_GATE_MODE=warn exits 0" 0
assert_contains "gate closed + warn mode emits a warning" "$LAST_LOG" "::warning::"
assert_not_contains "gate closed + warn mode emits no error" "$LAST_LOG" "::error::"
assert_eq "gate closed + warn mode reports gate_open=false" "false" "$LAST_GATE_OPEN"

run_case "shipped" "warn" "" ""
assert_exit "gate open + RELEASE_GATE_MODE=warn exits 0" 0
assert_not_contains "gate open + warn mode has no warning annotation" "$LAST_LOG" "::warning::"
assert_eq "gate open + warn mode reports gate_open=true" "true" "$LAST_GATE_OPEN"

run_case "" "wat" "" ""
assert_exit "unknown RELEASE_GATE_MODE value falls back to hard-fail" 1
assert_contains "unknown RELEASE_GATE_MODE value emits an error, not a warning" "$LAST_LOG" "::error::"

# --- Production confirmation composite scenarios ---

run_case "shipped" "" "true" "production"
assert_exit "gate open + confirm_production=production: both pass" 0

run_case "shipped" "" "true" ""
assert_exit "gate open + confirm_production empty fails on confirmation" 1
assert_contains "empty confirmation error names the exact string to type" "$LAST_LOG" "production"

run_case "shipped" "" "true" "Production"
assert_exit "gate open + confirm_production=Production (near-miss) fails" 1

run_case "" "" "true" "production"
assert_exit "gate closed + confirm_production=production fails on gate" 1
assert_contains "gate-closed-with-confirmation error names issue #17" "$LAST_LOG" "issue #17"

run_case "" "" "true" ""
assert_exit "gate closed + confirmation missing: both failures reported" 1
error_count="$(printf '%s' "$LAST_LOG" | grep -c '::error::' || true)"
assert_eq "both the gate and confirmation failures are reported in one run" "true" "$([ "$error_count" -ge 2 ] && echo true || echo false)"

# RELEASE_GATE_MODE=warn is documented to be ignored whenever a production
# confirmation is required (a production dispatch always hard-fails) --
# prove that precedence rather than leaving it accidentally-safe-by-disuse.
run_case "" "warn" "true" "production"
assert_exit "warn mode is ignored when confirmation is required: gate closed hard-fails" 1
assert_contains "warn+confirmation-required closed gate emits an error, not a warning" "$LAST_LOG" "::error::"
assert_not_contains "warn+confirmation-required closed gate emits no warning" "$LAST_LOG" "::warning::"

print_summary "check-release-gate.test.sh"
