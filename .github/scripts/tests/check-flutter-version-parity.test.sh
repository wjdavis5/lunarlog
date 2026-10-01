#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-flutter-version-parity.sh
# (issue #1276). The check scans every workflow for FLUTTER_VERSION
# assignments and fails when any disagrees with ci.yml's -- the mechanical
# closure of the stale-prose failure mode where AGENTS.md's SDK-bump
# procedure named four workflows while six pinned the var, so a bump
# following the prose left staging (site-deploy.yml's screenshot renders,
# webapp-deploy.yml's dart2js domain module) compiling with the old SDK
# while CI parity-tested the new one. These fixtures are built in a temp
# dir; the real repo tree is exercised separately by ci.yml's live
# "Check workflow Flutter version parity" step (the same split as
# check-auth-config). Run with:
#
#   bash .github/scripts/tests/check-flutter-version-parity.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-flutter-version-parity.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORKFLOWS="$(mktemp -d)"
cleanup() {
  rm -rf "$WORKFLOWS"
}
trap cleanup EXIT

# run_case
# Populates: $LAST_EXIT $LAST_LOG. Runs the check against the fixture dir.
run_case() {
  local logfile
  logfile="$(mktemp)"
  set +e
  bash "$SCRIPT" "$WORKFLOWS" "$WORKFLOWS/ci.yml" >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# ci.yml's real shape: a top-level env block carrying the reference pin,
# plus lowercase `flutter-version:` usage lines that must never be
# mistaken for assignments.
ci_yml='name: CI
env:
  FLUTTER_VERSION: '"'"'3.47.2'"'"'
jobs:
  check:
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
'

# site-deploy.yml's real shape: the pin nested at JOB level, not
# top-level, with a full-line comment naming the var right above it.
site_yml='name: Site deploy
jobs:
  deploy:
    env:
      # Pinned to the same SDK every other workflow builds with (see
      # FLUTTER_VERSION in ci.yml) so the screenshots render with the
      # exact engine the app ships on.
      FLUTTER_VERSION: '"'"'3.47.2'"'"'
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
'

# A workflow with no Flutter pin at all (e.g. a future docs/deploy
# workflow) -- skipped, never an error.
no_flutter_yml='name: Docs deploy
jobs:
  deploy:
    steps:
      - run: echo "no Flutter here"
'

printf '%s\n' "$ci_yml" >"$WORKFLOWS/ci.yml"
printf '%s\n' "$site_yml" >"$WORKFLOWS/site-deploy.yml"
printf '%s\n' "$no_flutter_yml" >"$WORKFLOWS/docs-deploy.yml"

# --- All pins agree ---------------------------------------------------

run_case
assert_exit "a job-level pin matching ci.yml's passes (site-deploy.yml's nesting)" 0
assert_not_contains "the agreeing tree emits no error" "$LAST_LOG" "::error::"
assert_contains "the agreeing tree prints a confirmation naming the pinned version" \
  "$LAST_LOG" "matches $WORKFLOWS/ci.yml's '3.47.2'"

# --- The issue's actual failure mode: one drifted workflow ------------

printf '%s\n' "${site_yml/3.47.2/3.48.0}" >"$WORKFLOWS/site-deploy.yml"
run_case
assert_exit "one workflow pinned to an older version fails" 1
assert_contains "the error names the drifted file" "$LAST_LOG" "site-deploy.yml"
assert_contains "the error names the actual and reference values" \
  "$LAST_LOG" "pins FLUTTER_VERSION '3.48.0' but $WORKFLOWS/ci.yml pins '3.47.2'"
assert_not_contains "the clean workflow without a pin is not reported" "$LAST_LOG" "docs-deploy.yml"
error_count="$(printf '%s' "$LAST_LOG" | grep -c '::error::' || true)"
assert_eq "exactly one error for one drifted pin" "1" "$error_count"

# Restore the agreeing tree.
printf '%s\n' "$site_yml" >"$WORKFLOWS/site-deploy.yml"

# --- A commented-out correct value must not satisfy the check ---------

# site-deploy.yml's live pin bumped but the old value left behind in the
# explanatory comment: the live (uncommented) wrong value is what counts,
# and the comment mentioning FLUTTER_VERSION must not be read as a pin.
commented_trap='jobs:
  deploy:
    env:
      # Pinned to the same SDK every other workflow builds with (see
      # FLUTTER_VERSION: '"'"'3.47.2'"'"' in ci.yml).
      FLUTTER_VERSION: '"'"'3.48.0'"'"'
'
printf '%s\n' "$commented_trap" >"$WORKFLOWS/site-deploy.yml"
run_case
assert_exit "a live wrong pin fails even with a commented-out correct one" 1
assert_contains "the commented example is not mistaken for the live pin" \
  "$LAST_LOG" "pins FLUTTER_VERSION '3.48.0'"
printf '%s\n' "$site_yml" >"$WORKFLOWS/site-deploy.yml"

# --- Usage lines are not assignments ----------------------------------

# A workflow whose ONLY FLUTTER_VERSION occurrences are lowercase
# `flutter-version:` usage steps (no env declaration) carries no pin and
# must be skipped, not flagged for "missing" or for the reference value.
usage_only_yml='name: Screens
jobs:
  shots:
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
'
printf '%s\n' "$usage_only_yml" >"$WORKFLOWS/screenshots.yml"
run_case
assert_exit "a workflow that only USES env.FLUTTER_VERSION (no declaration) is skipped" 0
assert_not_contains "the usage-only workflow is not reported" "$LAST_LOG" "screenshots.yml"
rm -f "$WORKFLOWS/screenshots.yml"

# --- Double-quoted values compare equal to single-quoted ones ---------

double_quoted_yml='name: Site deploy
jobs:
  deploy:
    env:
      FLUTTER_VERSION: "3.47.2"
'
printf '%s\n' "$double_quoted_yml" >"$WORKFLOWS/site-deploy.yml"
run_case
assert_exit "a double-quoted pin matching the reference passes" 0
printf '%s\n' "$site_yml" >"$WORKFLOWS/site-deploy.yml"

# --- ci.yml itself: the reference must exist and be unambiguous -------

no_ref_yml='name: CI
jobs:
  check:
    steps:
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.47.2"
'
printf '%s\n' "$no_ref_yml" >"$WORKFLOWS/ci.yml"
run_case
assert_exit "ci.yml declaring no FLUTTER_VERSION fails closed" 1
assert_contains "the missing-reference error names ci.yml" "$LAST_LOG" \
  "$WORKFLOWS/ci.yml declares no FLUTTER_VERSION"
printf '%s\n' "$ci_yml" >"$WORKFLOWS/ci.yml"

two_refs_yml='name: CI
env:
  FLUTTER_VERSION: '"'"'3.47.2'"'"'
  FLUTTER_VERSION: '"'"'3.48.0'"'"'
'
printf '%s\n' "$two_refs_yml" >"$WORKFLOWS/ci.yml"
run_case
assert_exit "ci.yml declaring two distinct versions fails closed" 1
assert_contains "the ambiguous-reference error names both values" "$LAST_LOG" \
  "2 distinct FLUTTER_VERSION values"
printf '%s\n' "$ci_yml" >"$WORKFLOWS/ci.yml"

# --- A pin appearing twice in ONE file, one drifted --------------------

split_pin='name: Multi
env:
  FLUTTER_VERSION: '"'"'3.47.2'"'"'
jobs:
  a:
    env:
      FLUTTER_VERSION: '"'"'3.48.0'"'"'
'
printf '%s\n' "$split_pin" >"$WORKFLOWS/multi.yml"
run_case
assert_exit "two disagreeing pins inside one workflow file fail" 1
assert_contains "the intra-file disagreement names the file" "$LAST_LOG" "multi.yml"
rm -f "$WORKFLOWS/multi.yml"

# --- Missing inputs fail closed ----------------------------------------

set +e
bash "$SCRIPT" "$WORKFLOWS/no-such-dir" > /dev/null 2>&1
LAST_EXIT=$?
set -e
assert_exit "a missing workflows directory fails" 1

set +e
bash "$SCRIPT" "$WORKFLOWS" "$WORKFLOWS/no-such-ref.yml" >"$WORKFLOWS/missing-ref.log" 2>&1
LAST_EXIT=$?
set -e
LAST_LOG="$(cat "$WORKFLOWS/missing-ref.log")"
assert_exit "a missing reference file fails" 1
assert_contains "the missing-reference error names the path" "$LAST_LOG" "not found"

# --- The real repo tree (defence in depth; CI runs this live too) ------

# The unit fixtures above prove the truth table; this last case proves
# the script works against the real .github/workflows layout the same
# run's checkout carries -- if the committed tree ever drifts, this suite
# fails here in addition to the live ci.yml step.
set +e
bash "$SCRIPT" "$SCRIPT_DIR/../../../.github/workflows" \
  "$SCRIPT_DIR/../../../.github/workflows/ci.yml" >"$WORKFLOWS/live.log" 2>&1
LAST_EXIT=$?
set -e
LAST_LOG="$(cat "$WORKFLOWS/live.log")"
assert_exit "the committed tree's six FLUTTER_VERSION pins all match ci.yml" 0
assert_contains "the live run names the pinned version" "$LAST_LOG" "'3.47.2'"

print_summary "check-flutter-version-parity.test.sh"
