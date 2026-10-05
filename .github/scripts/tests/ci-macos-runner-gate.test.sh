#!/usr/bin/env bash
set -euo pipefail

# The macOS jobs in ci.yml only take a Mac when they have work to do.
#
# Three jobs need macOS: `release-guards-macos`, `ios` and `ios-simulator`.
# Each opens with a gate step that reads one of detect-changes' outputs and,
# when the change does not concern it (a web- or site-only pull request),
# skips every later step. The job still has to run, because the "Main"
# ruleset requires its check by name. But it does not have to run on a Mac
# to say "nothing to do", and macOS runners are the scarce ones: with a few
# pull requests open, those gate-only jobs queued behind real iOS builds for
# longer than the rest of CI took.
#
# So each job's `runs-on` is an expression on the same output its gate
# reads: macOS when the suite runs, Linux when it is skipped. That is only
# safe while two things hold, and this suite pins both:
#
#   1. The runner choice and the gate read the same output. If they
#      disagreed, the suite could be told to run on Linux.
#   2. Every step after the gate is conditional on the gate. One
#      unconditional step (an `if: always()` clean-up, say) would run on
#      Linux, fail there, and fail a required check on every web-only PR.
#
# Run with:
#
#   bash .github/scripts/tests/ci-macos-runner-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_WORKFLOW="${CI_WORKFLOW:-$SCRIPT_DIR/../../workflows/ci.yml}"

# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

require_nonempty() {
  local desc="$1" value="$2"
  if [ -z "$value" ]; then
    echo "FAIL: $desc (extraction came back empty -- ci.yml's anchors moved)"
    exit 1
  fi
}

# job_block JOB -- the lines of one job: from its `  JOB:` key to the line
# before the next two-space key. Line numbers from grep and an explicit
# `sed -n a,bp`, so BSD and GNU sed agree (this runs on macOS too).
job_block() {
  local job="$1" start next total
  start="$(grep -n "^  ${job}:\$" "$CI_WORKFLOW" | head -n 1 | cut -d: -f1 || true)"
  require_nonempty "job '${job}' exists in ci.yml" "$start"
  total="$(wc -l < "$CI_WORKFLOW" | tr -d ' ')"
  next="$(tail -n "+$((start + 1))" "$CI_WORKFLOW" | grep -n '^  [a-z0-9-]*:$' | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$next" ]; then
    sed -n "${start},${total}p" "$CI_WORKFLOW"
  else
    sed -n "${start},$((start + next - 1))p" "$CI_WORKFLOW"
  fi
}

# count_lines PATTERN -- how many lines of stdin match (0, not an error,
# when none do).
count_lines() {
  grep -c -- "$1" || true
}

check_job() {
  local job="$1" output="$2" block runs_on expected steps guarded job_if gate_first

  block="$(job_block "$job")"
  require_nonempty "job '${job}' has a body" "$block"

  # 1. The runner is chosen from the output the gate reads.
  runs_on="$(printf '%s\n' "$block" | grep '^    runs-on:' | head -n 1 || true)"
  expected="    runs-on: \${{ needs.detect-changes.outputs.${output} == 'true' && 'macos-latest' || 'ubuntu-latest' }}"
  assert_eq "${job}: takes a Mac only when ${output} is true" "$expected" "$runs_on"

  assert_contains "${job}: its gate reads the same output" \
    "$block" "needs.detect-changes.outputs.${output} }}\" = \"true\""

  assert_contains "${job}: waits for detect-changes" "$block" "    needs: detect-changes"

  # The check must always report, so the job itself is never conditional.
  job_if="$(printf '%s\n' "$block" | count_lines '^    if:')"
  assert_eq "${job}: has no job-level condition" "0" "$job_if"

  # 2. Every step after the gate is conditional on it.
  steps="$(printf '%s\n' "$block" | count_lines '^      - ')"
  guarded="$(printf '%s\n' "$block" | count_lines "^        if: steps.check_run.outputs.run == 'true'")"
  if [ "$steps" -lt 2 ]; then
    echo "FAIL: ${job}: found ${steps} step(s) (extraction is wrong -- ci.yml's indentation moved)"
    exit 1
  fi
  assert_eq "${job}: all ${steps} steps but the gate are conditional on it" \
    "$((steps - 1))" "$guarded"

  # ...and the gate is the first step, so its output exists for the rest.
  gate_first="$(printf '%s\n' "$block" | grep -A 1 '^      - ' | head -n 2 | count_lines 'id: check_run')"
  assert_eq "${job}: the gate is its first step" "1" "$gate_first"
}

check_job "release-guards-macos" "release_guards"
check_job "ios" "app_flutter"
check_job "ios-simulator" "app_flutter"

# No job asks for a Mac unconditionally. A fourth macOS job added later has
# to make the same choice, or say here why it cannot.
unconditional="$(grep -c '^    runs-on: macos' "$CI_WORKFLOW" || true)"
assert_eq "no job in ci.yml takes a Mac unconditionally" "0" "$unconditional"

conditional="$(grep -c "^    runs-on: .*&& 'macos-latest' || 'ubuntu-latest'" "$CI_WORKFLOW" || true)"
assert_eq "exactly the three macOS jobs choose their runner" "3" "$conditional"

# --- Wiring -----------------------------------------------------------------

suite_runs="$(grep -c 'run: bash .github/scripts/tests/ci-macos-runner-gate.test.sh' "$CI_WORKFLOW" || true)"
assert_eq "ci.yml runs this suite in both release-guards jobs" "2" "$suite_runs"

print_summary "ci-macos-runner-gate.test.sh"
