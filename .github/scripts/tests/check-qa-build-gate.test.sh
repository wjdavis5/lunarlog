#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-qa-build-gate.sh (issue #739),
# plus wiring assertions that both store workflows actually consult it
# and actually compile the QA dart-define. Run with:
#
#   bash .github/scripts/tests/check-qa-build-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-qa-build-gate.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

IOS_WORKFLOW="$SCRIPT_DIR/../../workflows/ios-release.yml"
PLAY_WORKFLOW="$SCRIPT_DIR/../../workflows/play-store-release.yml"

# run_case QA_BUILD SUBMIT_FOR_REVIEW TRACK
# Populates: $LAST_EXIT $LAST_LOG
run_case() {
  local qa="$1" submit="$2" track="$3"
  local logfile
  logfile="$(mktemp)"
  set +e
  (
    export QA_BUILD="$qa"
    export SUBMIT_FOR_REVIEW="$submit"
    export TRACK="$track"
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

# --- The iOS scenario (SUBMIT_FOR_REVIEW set, TRACK empty) ---

run_case "true" "true" ""
assert_exit "iOS: QA build + submit_for_review refuses" 1
assert_contains "iOS refusal names issue #739" "$LAST_LOG" "issue #739"
assert_contains "iOS refusal tells the dispatcher how to proceed" "$LAST_LOG" "submit_for_review: false"

run_case "true" "false" ""
assert_exit "iOS: QA build without submission is allowed (TestFlight-only)" 0
assert_not_contains "allowed QA dispatch emits no error" "$LAST_LOG" "::error::"

run_case "false" "true" ""
assert_exit "iOS: normal build + submit_for_review passes through" 0
assert_not_contains "normal build emits no error" "$LAST_LOG" "::error::"

run_case "" "true" ""
assert_exit "iOS: unset QA_BUILD is a normal build" 0

# --- The Play scenario (TRACK set, SUBMIT_FOR_REVIEW empty) ---

run_case "true" "" "internal"
assert_exit "Play: QA build on the internal track is allowed" 0

run_case "true" "" "production"
assert_exit "Play: QA build on production refuses" 1
assert_contains "Play refusal names the only allowed track" "$LAST_LOG" "internal"

run_case "true" "" "alpha"
assert_exit "Play: QA build on alpha refuses" 1

run_case "true" "" "beta"
assert_exit "Play: QA build on beta refuses" 1

run_case "false" "" "production"
assert_exit "Play: normal build on production passes through" 0

run_case "" "" "production"
assert_exit "Play: unset QA_BUILD on production passes through" 0

# --- Case/whitespace tolerance on the QA flag itself ---

run_case "True" "" "production"
assert_exit "Play: 'True' (mixed case) is still a QA build and refuses" 1

run_case " true " "" "production"
assert_exit "Play: padded 'true' is still a QA build and refuses" 1

# --- Wiring: the workflows must actually use the gate and the define ---

ios_yaml="$(cat "$IOS_WORKFLOW")"
play_yaml="$(cat "$PLAY_WORKFLOW")"

assert_contains "ios-release.yml declares the qa_build input" "$ios_yaml" "qa_build:"
assert_contains "ios-release.yml runs the QA build gate script" "$ios_yaml" "check-qa-build-gate.sh"
assert_contains "ios-release.yml compiles the QA dart-define" "$ios_yaml" '--dart-define=LUNARLOG_QA_BUILD="$QA_BUILD"'
assert_contains "ios-release.yml release job needs the QA build gate" "$ios_yaml" "needs: [verify, migration-gate, release-gate, qa-build-gate, ci-gate]"

assert_contains "play-store-release.yml declares the qa_build input" "$play_yaml" "qa_build:"
assert_contains "play-store-release.yml runs the QA build gate script" "$play_yaml" "check-qa-build-gate.sh"
assert_contains "play-store-release.yml compiles the QA dart-define (bundle)" "$play_yaml" '--dart-define=LUNARLOG_QA_BUILD="$QA_BUILD"'
assert_contains "play-store-release.yml release job needs the QA build gate" "$play_yaml" "needs: [verify, production-gate, qa-build-gate, migration-gate, ci-gate]"
assert_contains "play-store-release.yml marks the QA Play release name" "$play_yaml" "releaseName: QA "

print_summary "check-qa-build-gate.test.sh"
