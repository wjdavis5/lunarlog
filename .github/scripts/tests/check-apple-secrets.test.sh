#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-apple-secrets.sh (issue #513). Run with:
#
#   bash .github/scripts/tests/check-apple-secrets.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-apple-secrets.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

ALL_FOUR_PRESENT_JSON='[{"name":"APPLE_CLIENT_ID","updated_at":"2026-01-01T00:00:00Z","value":"digest1"},{"name":"APPLE_KEY_ID","updated_at":"2026-01-01T00:00:00Z","value":"digest2"},{"name":"APPLE_PRIVATE_KEY","updated_at":"2026-01-01T00:00:00Z","value":"digest3"},{"name":"APPLE_TEAM_ID","updated_at":"2026-01-01T00:00:00Z","value":"digest4"},{"name":"SOME_OTHER_SECRET","updated_at":"2026-01-01T00:00:00Z","value":"digest5"}]'

run_script() {
  # $1: stdin payload. Remaining args: NAME=value env assignments to export
  # for just this invocation (unset ones are left absent, not empty).
  local payload="$1"
  shift
  env -i PATH="$PATH" "$@" bash "$SCRIPT" <<< "$payload"
}

# --- all-set: every GitHub secret present -> mode=set, stdin never consulted ---
out="$(run_script 'not valid json -- must never be read' \
  APPLE_TEAM_ID=team APPLE_KEY_ID=key APPLE_CLIENT_ID=client APPLE_PRIVATE_KEY=pk)"
assert_eq "all four GitHub secrets set produces mode=set" "mode=set" "$out"

# --- none-set-but-present: no GitHub secrets, all four names on the project -> mode=reuse ---
out="$(run_script "$ALL_FOUR_PRESENT_JSON")"
assert_eq "no GitHub secrets but all four present on the project produces mode=reuse" \
  "mode=reuse" "$out"

# --- some-missing-on-project: no GitHub secrets, project is missing one name -> fail ---
missing_one_json='[{"name":"APPLE_CLIENT_ID","value":"digest1"},{"name":"APPLE_KEY_ID","value":"digest2"},{"name":"APPLE_TEAM_ID","value":"digest4"}]'
set +e
err_out="$(run_script "$missing_one_json" 2>&1 1>/dev/null)"
rc=$?
set -e
assert_eq "one name missing on the project exits non-zero" "1" "$rc"
assert_contains "the error names the specific missing secret" "$err_out" "APPLE_PRIVATE_KEY"
# The message must name only what's actually absent, not restate all four --
# otherwise this couldn't distinguish "1 of 4 missing" from "0 of 4 missing"
# by content alone.
assert_not_contains "the error does not also claim an already-present name (APPLE_TEAM_ID) is missing" \
  "$err_out" "APPLE_TEAM_ID"
assert_not_contains "the error does not also claim an already-present name (APPLE_KEY_ID) is missing" \
  "$err_out" "APPLE_KEY_ID"
assert_not_contains "the error does not also claim an already-present name (APPLE_CLIENT_ID) is missing" \
  "$err_out" "APPLE_CLIENT_ID"

# --- some-missing-on-project: partial GitHub secrets set too, project missing all four ---
set +e
err_out2="$(run_script '[]' APPLE_TEAM_ID=team 2>&1 1>/dev/null)"
rc2=$?
set -e
assert_eq "empty project secrets with a partial GitHub set still exits non-zero" "1" "$rc2"
assert_contains "the error names APPLE_KEY_ID as missing" "$err_out2" "APPLE_KEY_ID"
assert_contains "the error names APPLE_CLIENT_ID as missing" "$err_out2" "APPLE_CLIENT_ID"
assert_contains "the error names APPLE_PRIVATE_KEY as missing" "$err_out2" "APPLE_PRIVATE_KEY"
assert_contains "the error names APPLE_TEAM_ID as missing (project has none, GitHub-set doesn't count)" \
  "$err_out2" "APPLE_TEAM_ID"

# --- malformed JSON on stdin fails closed rather than silently reusing ---
set +e
err_out3="$(run_script 'not json at all' 2>&1 1>/dev/null)"
rc3=$?
set -e
assert_eq "malformed stdin JSON exits non-zero" "1" "$rc3"
assert_contains "malformed stdin produces an ::error:: annotation" "$err_out3" "::error::"

print_summary "check-apple-secrets.test.sh"
