#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-release-secrets.sh (issue #1791),
# plus wiring assertions that play-store-release.yml consults it before
# any other job and that every secret it checks is one the workflow reads.
# Run with:
#
#   bash .github/scripts/tests/check-release-secrets.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-release-secrets.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

PLAY_WORKFLOW="$SCRIPT_DIR/../../workflows/play-store-release.yml"

ALL_SECRETS="ANDROID_KEYSTORE_BASE64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD PLAY_STORE_JSON_KEY"

# run_case UNSET_NAMES...
# Exports every secret to a placeholder except the named ones, which stay
# unset, then runs the script. Populates: $LAST_EXIT $LAST_LOG
run_case() {
  local logfile
  logfile="$(mktemp)"
  set +e
  (
    for name in $ALL_SECRETS; do
      case " $* " in
        *" $name "*) unset "$name" ;;
        *) export "$name=placeholder" ;;
      esac
    done
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

run_case
assert_eq "all five set: exits 0" 0 "$LAST_EXIT"
assert_contains "all five set: says so" "$LAST_LOG" "All release secrets are configured."

run_case ANDROID_KEYSTORE_BASE64
assert_eq "keystore missing: exits 1" 1 "$LAST_EXIT"
assert_contains "keystore missing: names it" "$LAST_LOG" "ANDROID_KEYSTORE_BASE64"

run_case PLAY_STORE_JSON_KEY
assert_eq "Play key missing: exits 1" 1 "$LAST_EXIT"
assert_contains "Play key missing: names it" "$LAST_LOG" "PLAY_STORE_JSON_KEY"

run_case ANDROID_KEY_ALIAS PLAY_STORE_JSON_KEY
assert_eq "two missing: exits 1" 1 "$LAST_EXIT"
assert_contains "two missing: names the alias" "$LAST_LOG" "ANDROID_KEY_ALIAS"
assert_contains "two missing: names the Play key" "$LAST_LOG" "PLAY_STORE_JSON_KEY"

play_yaml="$(cat "$PLAY_WORKFLOW")"
assert_contains "play-store-release.yml declares the preflight job" "$play_yaml" "preflight:"
assert_contains "play-store-release.yml runs the preflight script" "$play_yaml" "check-release-secrets.sh"
assert_contains "play-store-release.yml release job needs the preflight" "$play_yaml" "needs: [preflight, verify, production-gate, qa-build-gate, migration-gate, ci-gate]"

# Every secret the script checks must be a name the workflow reads, so a
# secret renamed on one side fails here instead of at dispatch time.
for name in $ALL_SECRETS; do
  assert_contains "play-store-release.yml reads $name" "$play_yaml" "secrets.$name"
done

print_summary "check-release-secrets.test.sh"
