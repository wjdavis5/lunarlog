#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-qa-build-gate.sh
#
# The single implementation of "may a QA build (LUNARLOG_QA_BUILD=true,
# issue #739) reach this release destination?" (issue #739, scope item 4).
# Both store workflows call this from their qa-build-gate job before any
# build work. No git access, no network, no secrets.
#
# A QA build compiles the client-side security-prompt bypasses in (no
# unlock gate, no relock, no re-auth prompts), so it may only ever reach:
#   * TestFlight WITHOUT App Store review submission (ios-release.yml),
#   * Google Play's `internal` track (play-store-release.yml).
# Anything else fails closed.
#
# Inputs (env):
#   QA_BUILD           'true' when the dispatch requested a QA build.
#                      Anything else -- including unset or empty -- is a
#                      normal build: nothing to gate, exit 0.
#   SUBMIT_FOR_REVIEW  'true' when the iOS dispatch also requests App
#                      Store review submission (ios-release.yml passes
#                      inputs.submit_for_review). Empty/absent on the
#                      Play side.
#   TRACK              The destination Play track
#                      (play-store-release.yml passes inputs.track).
#                      Empty/absent on the iOS side. Only consulted when
#                      QA_BUILD is 'true'; 'internal' is the one allowed
#                      value.
#
# Exit code: 0 when the destination is permitted, non-zero otherwise.

value="${QA_BUILD:-}"
trimmed="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
# `tr`, not bash 4's ${trimmed,,}: ios-release.yml's qa-build-gate job runs
# on ubuntu, but this script follows check-release-gate.sh's portability
# rule so it also survives macOS's frozen Bash 3.2 if it ever moves there
# (the release-guards-macos CI job runs its test suite).
qa="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

if [ "$qa" != "true" ]; then
  echo "Not a QA build dispatch; nothing to gate here."
  exit 0
fi

submit="${SUBMIT_FOR_REVIEW:-}"
track="${TRACK:-}"

if [ "$submit" = "true" ]; then
  echo "::error::A QA build (qa_build: true, issue #739) disables the unlock gate, relock, and re-auth prompts, and must never be submitted for App Store review. Re-dispatch with submit_for_review: false (the QA binary stays on TestFlight) or qa_build: false."
  exit 1
fi

if [ -n "$track" ] && [ "$track" != "internal" ]; then
  echo "::error::A QA build (qa_build: true, issue #739) can only ship to Google Play's internal track; track '$track' is promotable toward production. Re-dispatch with track: internal or qa_build: false."
  exit 1
fi

echo "QA build dispatch accepted: TestFlight-only (iOS) / internal track (Play) -- never a store submission."
