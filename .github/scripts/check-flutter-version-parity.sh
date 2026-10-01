#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-flutter-version-parity.sh
#
# Issue #1276: every workflow that pins the Flutter SDK via a
# FLUTTER_VERSION env var must pin the SAME version ci.yml pins. Six
# workflows carry the pin today (ci, ios-release, play-store-release,
# site-deploy, web-deploy, webapp-deploy) and AGENTS.md's SDK-bump
# procedure names them -- but the list is prose, and it had already gone
# stale once (site-deploy.yml was missing before webapp-deploy.yml existed,
# and #1266's webapp-deploy.yml landed with a comment claiming AGENTS.md
# listed it when it didn't). The failure mode is real: an agent following
# the prose bumps four files, CI parity-tests the new SDK, and the staging
# deploy (site-deploy.yml's screenshots, webapp-deploy.yml's dart2js domain
# module) then compiles with the OLD one -- the deployed artifact is not
# the artifact that was tested. This check closes that mechanically: it
# does not read AGENTS.md at all (so the prose can never desync the
# enforcement) -- it scans every workflow file for FLUTTER_VERSION
# assignments and fails on the first one that disagrees with ci.yml's.
# Adding a seventh pinning workflow needs no edit here; forgetting to bump
# it fails the PR.
#
# A plain-text/regex line scanner, not a YAML parser -- the same tradeoff
# check-auth-config.sh documents for its own structural checks, justified
# here because a FLUTTER_VERSION pin is a single scalar line
# (`FLUTTER_VERSION: 'x.y.z'`) at whatever env-block nesting the workflow
# uses (ci.yml/ios-release.yml/play-store-release.yml/web-deploy.yml/
# webapp-deploy.yml top-level, site-deploy.yml job-level). Full-line `#`
# comments are stripped first so a commented-out example value can never
# satisfy or fail a check. Trailing comments ON a value line are NOT
# stripped -- a value line must be exactly `FLUTTER_VERSION: <quoted or
# bare value>`; anything else fails closed. `flutter-version: ${{
# env.FLUTTER_VERSION }}` (lowercase, no colon after the name) never
# matches the assignment pattern.
#
# Usage: check-flutter-version-parity.sh [workflows-dir] [reference-file]
#   Defaults to .github/workflows and <dir>/ci.yml (the repo root in CI).
#
# Exit code: 0 when every FLUTTER_VERSION assignment in every workflow
# equals ci.yml's (and ci.yml has exactly one); non-zero (with one
# ::error:: per finding) otherwise.
#
# Bash 3.2 compatible (no `${var,,}`, no associative arrays), even though
# this script currently only runs on ubuntu-latest in ci.yml -- see
# check-auth-config.sh's header for why that constraint is kept regardless.

DIR="${1:-.github/workflows}"
REFERENCE="${2:-$DIR/ci.yml}"

if [ ! -d "$DIR" ]; then
  echo "::error::$DIR not found"
  exit 1
fi
if [ ! -f "$REFERENCE" ]; then
  echo "::error::$REFERENCE not found"
  exit 1
fi

# Prints one trimmed, unquoted value per live (uncommented)
# FLUTTER_VERSION assignment in the given file. Prints nothing when the
# file carries no pin -- an expected, handled case, so `|| true` guards
# the pipeline against set -o pipefail promoting grep's no-match exit 1
# to a script-ending failure.
_version_values() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null \
    | grep -E '^[[:space:]]*FLUTTER_VERSION:' \
    | sed -E 's/^[[:space:]]*FLUTTER_VERSION:[[:space:]]*//' \
    | sed -E 's/^"(.*)"$/\1/' \
    | sed -E "s/^'(.*)'\$/\1/" \
    || true
}

# --- The reference: ci.yml must pin exactly one version ---

reference_values="$(_version_values "$REFERENCE")"
if [ -z "$reference_values" ]; then
  echo "::error::$REFERENCE declares no FLUTTER_VERSION -- the parity check has no reference; restore the pin (issue #1276)"
  exit 1
fi

reference="$(printf '%s\n' "$reference_values" | sort -u)"
reference_count="$(printf '%s\n' "$reference" | grep -c . || true)"
if [ "$reference_count" -ne 1 ]; then
  echo "::error::$REFERENCE declares $reference_count distinct FLUTTER_VERSION values ($(printf '%s' "$reference" | tr '\n' ' ')) -- one workflow, one pin"
  exit 1
fi

# --- Every other workflow: no pin is fine; a differing pin is not ---

errors=0
for file in "$DIR"/*.yml "$DIR"/*.yaml; do
  [ -f "$file" ] || continue
  [ "$file" = "$REFERENCE" ] && continue

  values="$(_version_values "$file")"
  if [ -z "$values" ]; then
    continue
  fi

  while IFS= read -r actual; do
    [ -z "$actual" ] && continue
    if [ "$actual" != "$reference" ]; then
      echo "::error::$file pins FLUTTER_VERSION '$actual' but $REFERENCE pins '$reference' -- bump every workflow in one change (AGENTS.md's SDK-bump procedure; issue #1276)"
      errors=$((errors + 1))
    fi
  done <<< "$values"
done

if [ "$errors" -eq 0 ]; then
  echo "Every workflow's FLUTTER_VERSION matches $REFERENCE's '$reference' (issue #1276 parity check)."
fi

[ "$errors" -eq 0 ]
