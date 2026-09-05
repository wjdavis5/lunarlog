#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-release-gate.sh
#
# The single implementation of "is App Store / Play Store production
# submission permitted yet?" (issue #41). Both store workflows consult this
# script rather than carrying two divergent copies of the same rule. No git
# access, no network, no secrets.
#
# Inputs (env):
#   RELEASE_GATE_ACCOUNT_DELETION   Must equal "shipped" (case and
#                                   surrounding-whitespace tolerant) to open
#                                   the gate. Anything else -- including
#                                   unset or empty -- is closed. Closed is
#                                   the default: fail closed.
#   RELEASE_GATE_MODE                "warn" reports a closed gate as a
#                                   ::warning:: and does not fail the run by
#                                   itself (used by the iOS automatic-bump
#                                   path to degrade to TestFlight-only
#                                   rather than fail). Any other value,
#                                   including unset, is the hard-fail
#                                   default. Ignored when
#                                   REQUIRE_PRODUCTION_CONFIRMATION=true --
#                                   a production dispatch always hard-fails.
#   REQUIRE_PRODUCTION_CONFIRMATION  "true" additionally requires
#                                   CONFIRM_PRODUCTION to equal exactly
#                                   "production". Both the gate and the
#                                   confirmation are checked and reported
#                                   together, so a dispatcher sees every
#                                   reason at once rather than one per
#                                   attempt.
#   CONFIRM_PRODUCTION               The typed confirmation value to check
#                                   when REQUIRE_PRODUCTION_CONFIRMATION is
#                                   set.
#
# Exit code: 0 when submission is permitted (or the gate is closed but
# RELEASE_GATE_MODE=warn with no confirmation requirement), non-zero
# otherwise.
#
# Output: a `gate_open=true|false` line appended to $GITHUB_OUTPUT (when
# set), reporting the account-deletion gate's own state independent of
# RELEASE_GATE_MODE or the confirmation check -- this is what lets a
# warn-mode caller (the iOS submit path) suppress submission without
# failing the run.

GATE_MESSAGE="Release gate closed: the account-deletion feature (issue #17) has not shipped yet. App Store guideline 5.1.1(v) requires in-app account deletion before this build can go to store review/production. To open the gate once it has shipped, set the RELEASE_GATE_ACCOUNT_DELETION repository variable to 'shipped' (Settings -> Secrets and variables -> Actions -> Variables)."
CONFIRM_MESSAGE="Production confirmation missing or incorrect. Type exactly 'production' (all lowercase) into the confirm_production input to proceed with a production release."

value="${RELEASE_GATE_ACCOUNT_DELETION:-}"
trimmed="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
# `tr`, not bash 4's ${trimmed,,}: this script runs on ios-release.yml's
# macOS runner, which ships Bash 3.2 by default and has no case-conversion
# parameter expansion -- ${var,,} would crash the whole TestFlight pipeline.
lowered="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

errors=0
gate_open=false

if [ "$lowered" = "shipped" ]; then
  gate_open=true
  echo "Release gate open (RELEASE_GATE_ACCOUNT_DELETION=shipped)."
elif [ "${RELEASE_GATE_MODE:-}" = "warn" ] && [ "${REQUIRE_PRODUCTION_CONFIRMATION:-}" != "true" ]; then
  echo "::warning::$GATE_MESSAGE"
else
  echo "::error::$GATE_MESSAGE"
  errors=$((errors + 1))
fi

if [ "${REQUIRE_PRODUCTION_CONFIRMATION:-}" = "true" ]; then
  if [ "${CONFIRM_PRODUCTION:-}" != "production" ]; then
    echo "::error::$CONFIRM_MESSAGE"
    errors=$((errors + 1))
  else
    echo "Production confirmation received."
  fi
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "gate_open=$gate_open" >> "$GITHUB_OUTPUT"
fi

[ "$errors" -eq 0 ]
