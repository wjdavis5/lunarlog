#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-play-health-declaration.sh (issue
# #1735): the extracted Play production health-declaration gate. A missing
# manifest must fail closed -- the pre-fix inline `if ! grep -q` read grep's
# exit 2 as "nothing to gate" and passed without gating. Run with:
#
#   bash .github/scripts/tests/check-play-health-declaration.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-play-health-declaration.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

MANIFEST_REL="android/app/src/main/AndroidManifest.xml"

# run_gate <cwd> <PLAY_HEALTH_DECLARATION_CONFIRMED value>
run_gate() {
  local cwd="$1" confirmed="${2-}"
  local logfile
  logfile="$(mktemp)"
  set +e
  (
    cd "$cwd"
    export PLAY_HEALTH_DECLARATION_CONFIRMED="$confirmed"
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

# write_manifest <cwd> <contents>
write_manifest() {
  local cwd="$1" contents="$2"
  mkdir -p "$cwd/$(dirname "$MANIFEST_REL")"
  printf '%s\n' "$contents" >"$cwd/$MANIFEST_REL"
}

# Case 1 (issue #1735): a missing manifest fails closed. The pre-fix shape
# read grep's exit 2 as "nothing to gate" and exited 0.
run_gate "$WORKDIR" ""
assert_eq "missing manifest exits 1" 1 "$LAST_EXIT"
assert_contains "missing manifest is named" "$LAST_LOG" "not found"
assert_contains "missing manifest refuses to pass" "$LAST_LOG" "refusing to pass"

# Case 2: a manifest without health permissions -- nothing to gate.
write_manifest "$WORKDIR" \
  '<manifest xmlns:android="http://schemas.android.com/apk/res/android"><uses-permission android:name="android.permission.INTERNET"/></manifest>'
run_gate "$WORKDIR" ""
assert_eq "no health permissions exits 0" 0 "$LAST_EXIT"
assert_contains "nothing-to-gate message" "$LAST_LOG" "nothing to gate"

# Case 3: health permissions present, declaration not confirmed -- fail.
write_manifest "$WORKDIR" \
  '<uses-permission android:name="android.permission.health.READ_MENSTRUATION"/>'
run_gate "$WORKDIR" ""
assert_eq "health permissions without confirmation exits 1" 1 "$LAST_EXIT"
assert_contains "declaration error names the variable" "$LAST_LOG" "PLAY_HEALTH_DECLARATION_CONFIRMED"

# Case 4: any non-'true' confirmation value fails the same way.
run_gate "$WORKDIR" "yes"
assert_eq "a non-true confirmation exits 1" 1 "$LAST_EXIT"

# Case 5: health permissions present and confirmed -- pass.
run_gate "$WORKDIR" "true"
assert_eq "confirmed declaration exits 0" 0 "$LAST_EXIT"
assert_contains "satisfied message" "$LAST_LOG" "gate satisfied"

print_summary "check-play-health-declaration.test.sh"
