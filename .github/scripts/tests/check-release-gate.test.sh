#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-release-gate.sh. Run with:
#
#   bash .github/scripts/tests/check-release-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-release-gate.sh"

pass=0
fail=0

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
  local desc="$1" expected="$2"
  if [ "$LAST_EXIT" -eq "$expected" ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected exit $expected, got $LAST_EXIT)"
    echo "$LAST_LOG" | sed 's/^/  /'
    fail=$((fail + 1))
  fi
}

assert_contains() {
  local desc="$1" needle="$2"
  if printf '%s' "$LAST_LOG" | grep -qF "$needle"; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected to find '$needle')"
    echo "$LAST_LOG" | sed 's/^/  /'
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local desc="$1" needle="$2"
  if printf '%s' "$LAST_LOG" | grep -qF "$needle"; then
    echo "FAIL: $desc (did not expect to find '$needle')"
    echo "$LAST_LOG" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    echo "PASS: $desc"
    pass=$((pass + 1))
  fi
}

# --- Basic gate scenarios (no production confirmation requirement) ---

run_case "shipped" "" "" ""
assert_exit "gate=shipped exits 0" 0
assert_not_contains "gate=shipped has no error annotation" "::error::"

run_case "" "" "" ""
assert_exit "unset gate variable exits non-zero" 1
assert_contains "unset gate error names issue #17" "issue #17"
assert_contains "unset gate error names the variable" "RELEASE_GATE_ACCOUNT_DELETION"

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
assert_contains "gate closed + warn mode emits a warning" "::warning::"
assert_not_contains "gate closed + warn mode emits no error" "::error::"
if [ "$LAST_GATE_OPEN" = "false" ]; then
  echo "PASS: gate closed + warn mode reports gate_open=false"
  pass=$((pass + 1))
else
  echo "FAIL: gate closed + warn mode expected gate_open=false, got '$LAST_GATE_OPEN'"
  fail=$((fail + 1))
fi

run_case "shipped" "warn" "" ""
assert_exit "gate open + RELEASE_GATE_MODE=warn exits 0" 0
assert_not_contains "gate open + warn mode has no warning annotation" "::warning::"
if [ "$LAST_GATE_OPEN" = "true" ]; then
  echo "PASS: gate open + warn mode reports gate_open=true"
  pass=$((pass + 1))
else
  echo "FAIL: gate open + warn mode expected gate_open=true, got '$LAST_GATE_OPEN'"
  fail=$((fail + 1))
fi

run_case "" "wat" "" ""
assert_exit "unknown RELEASE_GATE_MODE value falls back to hard-fail" 1
assert_contains "unknown RELEASE_GATE_MODE value emits an error, not a warning" "::error::"

# --- Production confirmation composite scenarios (U4) ---

run_case "shipped" "" "true" "production"
assert_exit "gate open + confirm_production=production: both pass" 0

run_case "shipped" "" "true" ""
assert_exit "gate open + confirm_production empty fails on confirmation" 1
assert_contains "empty confirmation error names the exact string to type" "production"

run_case "shipped" "" "true" "Production"
assert_exit "gate open + confirm_production=Production (near-miss) fails" 1

run_case "" "" "true" "production"
assert_exit "gate closed + confirm_production=production fails on gate" 1
assert_contains "gate-closed-with-confirmation error names issue #17" "issue #17"

run_case "" "" "true" ""
assert_exit "gate closed + confirmation missing: both failures reported" 1
error_count="$(printf '%s' "$LAST_LOG" | grep -c '::error::' || true)"
if [ "$error_count" -ge 2 ]; then
  echo "PASS: both the gate and confirmation failures are reported in one run"
  pass=$((pass + 1))
else
  echo "FAIL: expected at least 2 ::error:: lines, got $error_count"
  echo "$LAST_LOG" | sed 's/^/  /'
  fail=$((fail + 1))
fi

echo ""
echo "check-release-gate.test.sh: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
