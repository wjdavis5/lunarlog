#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-pitr-gate.sh. Run with:
#
#   bash .github/scripts/tests/check-pitr-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-pitr-gate.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

# run_case SUPABASE_PITR_CONFIRMED
# Populates: $LAST_EXIT $LAST_LOG $LAST_GATE_OPEN
run_case() {
  local gate="$1"
  local logfile outfile
  logfile="$(mktemp)"
  outfile="$(mktemp)"
  set +e
  (
    export SUPABASE_PITR_CONFIRMED="$gate"
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

# --- Gate open ---

run_case "true"
assert_exit "gate=true exits 0" 0
assert_not_contains "gate=true has no error annotation" "$LAST_LOG" "::error::"
assert_eq "gate=true reports gate_open=true" "true" "$LAST_GATE_OPEN"

run_case "True"
assert_exit "mixed-case 'True' exits 0" 0

run_case "  TRUE  "
assert_exit "surrounding whitespace tolerated, exits 0" 0

# --- Gate closed (fail closed on everything else) ---

run_case ""
assert_exit "unset/empty gate variable exits non-zero" 1
assert_contains "closed gate emits an error annotation" "$LAST_LOG" "::error::"
assert_contains "closed gate error names the variable" "$LAST_LOG" "SUPABASE_PITR_CONFIRMED"
assert_contains "closed gate error names issue #185" "$LAST_LOG" "#185"
assert_contains "closed gate error points at the dashboard setting" "$LAST_LOG" "Backups"
assert_contains "closed gate error points at the go-live checklist" "$LAST_LOG" "supabase-go-live"
assert_contains "closed gate error points at issue #18's checklist" "$LAST_LOG" "#18"
assert_eq "closed gate reports gate_open=false" "false" "$LAST_GATE_OPEN"

run_case "false"
assert_exit "explicit 'false' exits non-zero" 1

run_case "1"
assert_exit "truthy-but-wrong value '1' exits non-zero" 1

run_case "shipped"
assert_exit "wrong sentinel 'shipped' (release-gate value) exits non-zero" 1

# --- Never automated ---

run_case "true"
assert_contains "open-gate log names the operator as the actor" "$LAST_LOG" "operator"

run_case ""
assert_contains "closed-gate error says never to set it from automation" "$LAST_LOG" "never set this variable from automation"

print_summary "check-pitr-gate.test.sh"
