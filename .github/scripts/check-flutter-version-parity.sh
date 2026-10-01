#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-flutter-version-parity.sh
#
# Issue #1276: every workflow that pins the Flutter SDK via a
# FLUTTER_VERSION env var must pin the SAME version ci.yml pins. Seven
# workflows carry the pin today (ci, ios-release, play-store-release,
# site, site-deploy, web-deploy, webapp-deploy -- site.yml joined when
# issue #1316 moved its SDK pin off a step-level literal) and AGENTS.md's
# SDK-bump procedure names them -- but the list is prose, and it had
# already gone stale once (site-deploy.yml was missing before
# webapp-deploy.yml existed, and #1266's webapp-deploy.yml landed with a
# comment claiming AGENTS.md listed it when it didn't). The failure mode
# is real: an agent following the prose bumps four files, CI parity-tests
# the new SDK, and the staging deploy (site-deploy.yml's screenshots,
# webapp-deploy.yml's dart2js domain module) then compiles with the OLD
# one -- the deployed artifact is not the artifact that was tested. This
# check closes that mechanically: it does not read AGENTS.md at all (so
# the prose can never desync the enforcement) -- it scans every workflow
# file for FLUTTER_VERSION assignments and fails on the first one that
# disagrees with ci.yml's. Adding an eighth pinning workflow needs no edit
# here; forgetting to bump it fails the PR.
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
# Issue #1316 hardened the scan in both directions, same line-scanner
# tradeoff:
#   - every live `flutter-version:` step input (flutter-action's
#     lowercase key) must read `${{ env.FLUTTER_VERSION }}`. A literal
#     value is invisible to the assignment scan above -- site.yml carried
#     exactly `flutter-version: '3.47.2'`, so this gate and AGENTS.md's
#     `grep -rl FLUTTER_VERSION` enumeration both skipped it. A literal
#     that happens to EQUAL ci.yml's version still fails: it would drift
#     silently at the next bump. Any other expression (a matrix var, a
#     secret, a default) fails too -- if a workflow ever legitimately
#     needs one, this script is the deliberate place to carve the
#     exception.
#   - a workflow that READS `${{ env.FLUTTER_VERSION }}` without defining
#     FLUTTER_VERSION also fails: flutter-action falls back to the latest
#     stable -- exactly the untested-SDK drift this check exists to
#     prevent, and the env line is easy to lose while refactoring the
#     step it feeds.
#
# Usage: check-flutter-version-parity.sh [workflows-dir] [reference-file]
#   Defaults to .github/workflows and <dir>/ci.yml (the repo root in CI).
#
# Exit code: 0 when every FLUTTER_VERSION assignment in every workflow
# equals ci.yml's (and ci.yml has exactly one), every `flutter-version:`
# step input reads `${{ env.FLUTTER_VERSION }}`, and every workflow
# reading `env.FLUTTER_VERSION` defines it; non-zero (with one ::error::
# per finding) otherwise.
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

# Prints one trimmed, unquoted value per live (uncommented) lowercase
# `flutter-version:` step input in the given file -- flutter-action's
# usage lines, which the assignment scan above must never mistake for
# pins (issue #1276) but which issue #1316 makes parity-checked in their
# own right: every one must read `${{ env.FLUTTER_VERSION }}`, never a
# literal. Same `|| true` guard as _version_values: no match is an
# expected, handled case.
_usage_values() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null \
    | grep -E '^[[:space:]]*flutter-version:' \
    | sed -E 's/^[[:space:]]*flutter-version:[[:space:]]*//' \
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

# --- Every workflow: the #1316 rules apply to the reference too; the ---
# --- value-drift comparison is the only reference-exempt check        ---

errors=0
for file in "$DIR"/*.yml "$DIR"/*.yaml; do
  [ -f "$file" ] || continue

  values="$(_version_values "$file")"

  # Issue #1316, rule 2: a workflow that reads env.FLUTTER_VERSION but
  # carries no FLUTTER_VERSION assignment installs latest stable.
  if [ -z "$values" ]; then
    env_reads="$(grep -v '^[[:space:]]*#' "$file" 2>/dev/null \
      | grep -E '\$\{\{[[:space:]]*env\.FLUTTER_VERSION' \
      || true)"
    if [ -n "$env_reads" ]; then
      echo "::error::$file reads \${{ env.FLUTTER_VERSION }} but never defines FLUTTER_VERSION -- flutter-action installs the latest stable instead of the tested SDK; add the env pin (issue #1316)"
      errors=$((errors + 1))
    fi
  fi

  # Issue #1316, rule 1: no literal flutter-version: values -- the input
  # must flow through env.FLUTTER_VERSION so one bump reaches it.
  usages="$(_usage_values "$file")"
  while IFS= read -r actual; do
    [ -z "$actual" ] && continue
    case "$actual" in
      *env.FLUTTER_VERSION*) ;;
      *)
        echo "::error::$file pins flutter-version as the literal '$actual' -- use \${{ env.FLUTTER_VERSION }} with a FLUTTER_VERSION env definition so the next SDK bump reaches this workflow too (issue #1316)"
        errors=$((errors + 1))
        ;;
    esac
  done <<< "$usages"

  # The reference cannot disagree with itself.
  [ "$file" = "$REFERENCE" ] && continue
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
  echo "Every workflow's FLUTTER_VERSION matches $REFERENCE's '$reference', every flutter-version: input reads it, and every env.FLUTTER_VERSION reader defines it (issues #1276/#1316 parity check)."
fi

[ "$errors" -eq 0 ]
