#!/usr/bin/env bash
set -euo pipefail

# Budget arithmetic for the `iOS Simulator tests` job in ci.yml (issue #1278).
#
# The job's failure mode before #1278 was never a named test -- it was the
# retry harness silently outgrowing the caps meant to contain it: a healthy
# cold-cache attempt measured 495s against a 500s per-attempt bound (run
# 36792571635, a PASS), so normal build-time variance pushed real runs past
# the bound before the first test started, and the 18-minute step cap could
# then kill attempt 2 mid-build. The budgets below are pinned and their
# arithmetic asserted so a future edit that re-opens that gap fails this
# suite instead of main.
#
# Run with:
#
#   bash .github/scripts/tests/ios-simulator-budgets.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"
GATE_TEST="$SCRIPT_DIR/../../../integration_test/gate_test.dart"

# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

# --- Fail-closed extraction -------------------------------------------------
#
# Every extractor dies loudly on an empty result: a ci.yml restructure that
# moves the anchors must turn this suite red here, not silently skip the
# invariant it was pinning (same posture as the arming-constant guard in
# check-web-deploy.test.sh).

require_nonempty() {
  local desc="$1" value="$2"
  if [ -z "$value" ]; then
    echo "FAIL: $desc (extraction came back empty -- ci.yml's anchors moved)"
    exit 1
  fi
}

# lines_between START_RE END_RE FILE -- FILE's slice from the line after the
# first line matching START_RE through the line before the next line matching
# END_RE. Built from grep -n line numbers and an explicit `sed -n a,bp`
# rather than sed range addresses, so the result does not depend on BSD vs
# GNU range-semantics corner cases (release-guards-macos runs this on macOS).
lines_between() {
  local start_re="$1" end_re="$2" file="$3"
  local s e
  s="$(grep -n "$start_re" "$file" | head -1 | cut -d: -f1)"
  if [ -z "$s" ]; then
    echo ""
    return
  fi
  e="$(awk -v s="$s" -v re="$end_re" 'NR > s && $0 ~ re { print NR; exit }' "$file")"
  if [ -z "$e" ]; then
    echo ""
    return
  fi
  sed -n "$((s + 1)),$((e - 1))p" "$file"
}

job_block="$(lines_between '^  ios-simulator:' '^  ci-required-checks:' "$CI_WORKFLOW")"
require_nonempty "the ios-simulator job block" "$job_block"

test_step_block="$(lines_between 'name: Run integration tests on the simulator' '^      - name: Shut down simulator' "$CI_WORKFLOW")"
require_nonempty "the Run integration tests step block" "$test_step_block"

build_step_block="$(lines_between 'name: Build the app for the simulator' '^      - name: Pick and boot a simulator' "$CI_WORKFLOW")"
require_nonempty "the Build the app for the simulator step block" "$build_step_block"

swift_step_block="$(lines_between 'name: Run the Swift channel unit tests on the simulator' '^      - name: Run integration tests on the simulator' "$CI_WORKFLOW")"
require_nonempty "the Swift channel unit-test step block" "$swift_step_block"

attempt_seconds="$(sed -n "s/^ *' \([0-9][0-9]*\) flutter test integration_test\/gate_test\.dart.*/\1/p" <<<"$test_step_block" | head -1)"
require_nonempty "the per-attempt bound from the python wrapper's argv" "$attempt_seconds"

step_minutes="$(sed -n 's/^ *timeout-minutes: \([0-9][0-9]*\)$/\1/p' <<<"$test_step_block" | head -1)"
require_nonempty "the test step's timeout-minutes" "$step_minutes"

build_minutes="$(sed -n 's/^ *timeout-minutes: \([0-9][0-9]*\)$/\1/p' <<<"$build_step_block" | head -1)"
require_nonempty "the build step's timeout-minutes" "$build_minutes"

swift_minutes="$(sed -n 's/^ *timeout-minutes: \([0-9][0-9]*\)$/\1/p' <<<"$swift_step_block" | head -1)"
require_nonempty "the Swift unit-test step's timeout-minutes" "$swift_minutes"

job_minutes="$(sed -n 's/^ *timeout-minutes: \([0-9][0-9]*\)$/\1/p' <<<"$job_block" | head -1)"
require_nonempty "the job's timeout-minutes" "$job_minutes"

flutter_cmd="$(sed -n "s/^ *' [0-9][0-9]* \(flutter test integration_test\/gate_test\.dart.*\)$/\1/p" <<<"$test_step_block")"
require_nonempty "the flutter test invocation line" "$flutter_cmd"

# --- The pinned budgets (issue #1278; the Swift step is #1610/#1666) -----------
#
# attempt_seconds = 750: the measured healthy cold-cache attempt is 495s
# (run 36792571635: pub, kernel compile, a 208s Xcode build, ~100s to
# install/launch/pass all 6 tests), against observed Xcode builds of
# 180-300s. The old 500s bound left five seconds of margin and consumed
# both attempts of run 36784132156 without one test line.
assert_eq "the per-attempt bound stays at the #1278 value" "750" "$attempt_seconds"
assert_eq "the test step's cap stays at the #1278 value" "30" "$step_minutes"
assert_eq "the Swift unit-test step's cap stays at the #1666 value" "20" "$swift_minutes"
assert_eq "the job cap stays at the #1666 value" "80" "$job_minutes"

assert_contains "the invocation skips the implicit pub re-resolve (#1278 -- the job runs flutter pub get earlier in the same checkout)" "$flutter_cmd" "--no-pub"
assert_contains "the invocation targets the booted simulator by UDID" "$flutter_cmd" '-d "$SIM_UDID"'
assert_contains "the Swift unit-test step targets the booted simulator by UDID (#1610)" "$swift_step_block" '-destination "id=$SIM_UDID"'
assert_contains "the Swift unit-test step runs the Runner scheme's test target (#1610)" "$swift_step_block" "-scheme Runner"
assert_contains "the Swift unit-test step disables clone simulator spawning (#1666)" "$swift_step_block" "-parallel-testing-enabled NO"

# The Swift unit tests must run BEFORE the integration tests (issue #1610's
# CI failure, run 37568557173): the integration build records a deleted
# flutter_test_listener temp file as its kernel entrypoint in the shared
# DerivedData, and an xcodebuild test that runs after it fails in the
# Runner target's Run Script phase re-reading that entrypoint.
swift_line="$(grep -n 'name: Run the Swift channel unit tests on the simulator' "$CI_WORKFLOW" | head -1 | cut -d: -f1)"
require_nonempty "the Swift step's line number" "$swift_line"
integration_line="$(grep -n 'name: Run integration tests on the simulator' "$CI_WORKFLOW" | head -1 | cut -d: -f1)"
require_nonempty "the integration step's line number" "$integration_line"
assert_eq "the Swift step runs before the integration tests" \
  "before" \
  "$([ "$swift_line" -lt "$integration_line" ] && echo before || echo after)"

# --- The arithmetic the caps must keep true ---------------------------------

# Two bounded attempts plus the reboot between them fit under the step cap
# with real slack. The reboot is shutdown/sleep/boot/bootstatus (observed
# ~60s in run 36784132156) plus script overhead; 240s covers it fourfold.
step_cap_seconds=$((step_minutes * 60))
attempt_need=$((attempt_seconds * 2 + 240))
assert_eq "two ${attempt_seconds}s attempts + 240s reboot/overhead fit under the ${step_minutes}m step cap" \
  "fit" \
  "$([ "$step_cap_seconds" -ge "$attempt_need" ] && echo fit || echo "no: ${step_cap_seconds}s < ${attempt_need}s")"

# The job cap covers the build step, the integration-test step, the Swift
# unit-test step, and at least 6 minutes of checkout / Flutter setup / cache
# restore / simulator boot / shutdown (the same arithmetic the job's own
# comment documents).
job_need=$((build_minutes + step_minutes + swift_minutes + 6))
assert_eq "the ${job_minutes}m job cap covers ${build_minutes}m build + ${step_minutes}m test step + ${swift_minutes}m Swift step + 6m overhead" \
  "fit" \
  "$([ "$job_minutes" -ge "$job_need" ] && echo fit || echo "no: ${job_minutes}m < ${job_need}m")"

# The bound keeps >= 200s of headroom over the measured healthy-cold
# attempt, so a pass does not depend on a 1% margin.
assert_eq "the bound keeps >= 200s of headroom over the measured 495s healthy-cold attempt" \
  "fit" \
  "$([ "$attempt_seconds" -ge 695 ] && echo fit || echo "no: ${attempt_seconds}s < 695s")"

# --- The per-test bounds this step's premise rests on ------------------------
#
# The #827 per-test timeouts are what name a stuck test once tests are
# actually running; #1278 only widened the pre-test budget. The step comment
# says not to remove them -- pin the invariant here: every testWidgets in
# gate_test.dart carries the bound, and the bound is still 2 minutes.

# Fail closed (issue #1317): the two `grep -c ... || true` counts below must
# never compare equal by accident. A missing gate_test.dart leaves both
# counts empty (grep fails without printing), and a gutted one leaves both
# at 0 -- either way the assert_eq underneath sees two equal values and
# passes. Floor both counts first: a missing or gutted gate_test.dart dies
# loudly here, the same posture as the ci.yml extractions above.
if [ ! -f "$GATE_TEST" ]; then
  echo "FAIL: integration_test/gate_test.dart is missing -- this suite pins its per-test bounds"
  exit 1
fi
gate_tests="$(grep -c 'testWidgets(' "$GATE_TEST" || true)"
gate_bounds="$(grep -c 'timeout: _kTestTimeout' "$GATE_TEST" || true)"
if [ -z "$gate_tests" ] || [ "$gate_tests" -eq 0 ]; then
  echo "FAIL: gate_test.dart has no testWidgets( left -- there is nothing left to bound"
  exit 1
fi
if [ -z "$gate_bounds" ] || [ "$gate_bounds" -eq 0 ]; then
  echo "FAIL: gate_test.dart carries no 'timeout: _kTestTimeout' bound -- the #827 per-test bounds are gone"
  exit 1
fi
assert_eq "every testWidgets in gate_test.dart carries the #827 per-test bound" "$gate_tests" "$gate_bounds"
assert_contains "the per-test bound stays at the #827 value" \
  "$(cat "$GATE_TEST")" \
  "const Timeout _kTestTimeout = Timeout(Duration(minutes: 2));"

# --- Wiring -----------------------------------------------------------------

suite_runs="$(grep -c 'run: bash .github/scripts/tests/ios-simulator-budgets.test.sh' "$CI_WORKFLOW" || true)"
assert_eq "ci.yml runs this suite in both release-guards jobs" "2" "$suite_runs"

print_summary "ios-simulator-budgets.test.sh"
