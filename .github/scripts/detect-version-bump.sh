#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/detect-version-bump.sh
#
# Decides whether the just-built iOS release should submit for App Store
# review (issue #41, finding #6). The old inline step compared pubspec.yaml
# at HEAD against HEAD~1, so a `version:` bump landing anywhere except the
# tip commit of a multi-commit push was silently missed. This script
# evaluates the whole pushed range instead, with a loud fallback when the
# range can't be evaluated.
#
# Inputs are environment variables only -- no ${{ }} interpolation inside
# this file -- so it runs identically under `bash detect-version-bump.sh`
# in a test harness and inside GitHub Actions.
#
#   EVENT_NAME         github.event_name (e.g. "push", "workflow_dispatch")
#   BEFORE_SHA          github.event.before (may be empty or the all-zero SHA)
#   SUBMIT_FOR_REVIEW   inputs.submit_for_review ("true"/"false"/empty)
#   CURRENT_VERSION     the marketing version already resolved by the
#                       workflow's `version` step (e.g. "1.2.3")
#
# Output: a `submit=true|false` line appended to $GITHUB_OUTPUT (or printed
# to stdout when $GITHUB_OUTPUT is unset, so this is runnable by hand),
# plus human-readable log lines and, on an unevaluable range, a
# `::warning::` naming why.

ALL_ZERO_SHA="0000000000000000000000000000000000000000"

emit_submit() {
  # Append to $GITHUB_OUTPUT when Actions provides one; otherwise print the
  # verdict to stdout so the script is runnable by hand. A literal
  # "/dev/stdout" default is avoided here -- appending to it from inside a
  # shell function behaves inconsistently across environments (observed:
  # MSYS/Git-Bash interleaving), where a plain echo does not.
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "submit=$1" >> "$GITHUB_OUTPUT"
  else
    echo "submit=$1"
  fi
}

warn() {
  echo "::warning::$1"
}

extract_version() {
  # $1 = raw pubspec.yaml content. Marketing version is the "x.y.z" part
  # before the "+build" suffix -- same extraction the workflow's own
  # `Resolve build and version numbers` step performs, so the two can never
  # disagree about what a "version" is.
  printf '%s\n' "$1" | grep '^version:' | sed 's/^version: *//' | cut -d'+' -f1
}

# R4: an explicit dispatch request to submit always wins, independent of any
# bump, and needs no git access at all.
if [ "${SUBMIT_FOR_REVIEW:-}" = "true" ]; then
  emit_submit true
  echo "Submission requested manually via workflow_dispatch."
  exit 0
fi

# A manual dispatch that did NOT ask to submit never auto-submits from a
# version bump. workflow_dispatch has no coherent "pushed range" to diff
# (github.event.before is unset), so inferring intent from whatever HEAD
# happens to be would be surprising rather than helpful.
if [ "${EVENT_NAME:-}" = "workflow_dispatch" ]; then
  emit_submit false
  echo "Manual dispatch without submit_for_review; not submitting."
  exit 0
fi

current="${CURRENT_VERSION:-}"
if [ -z "$current" ]; then
  echo "::error::CURRENT_VERSION is not set. Cannot evaluate a version bump."
  exit 1
fi

before="${BEFORE_SHA:-}"
previous=""
resolved=false

if [ -z "$before" ]; then
  warn "github.event.before is empty; cannot evaluate the pushed range. Falling back to HEAD~1."
elif [ "$before" = "$ALL_ZERO_SHA" ]; then
  warn "github.event.before is the all-zero SHA (first push of a branch/new ref); cannot evaluate the pushed range. Falling back to HEAD~1."
elif ! git cat-file -e "${before}^{commit}" 2>/dev/null; then
  warn "before-commit $before is not present locally (likely a force-push rewriting history); cannot evaluate the pushed range. Falling back to HEAD~1."
else
  if raw="$(git show "${before}:pubspec.yaml" 2>/dev/null)"; then
    previous="$(extract_version "$raw")"
    resolved=true
  else
    warn "pubspec.yaml did not exist at before-commit $before; cannot evaluate the pushed range. Falling back to HEAD~1."
  fi
fi

if [ "$resolved" = false ]; then
  if raw="$(git show 'HEAD~1:pubspec.yaml' 2>/dev/null)"; then
    previous="$(extract_version "$raw")"
  else
    warn "HEAD~1 is also unavailable (single-commit repo); treating version as unchanged."
    previous="$current"
  fi
fi

if [ "$current" != "$previous" ]; then
  emit_submit true
  echo "Version bumped ($previous -> $current); will submit for App Store review."
else
  emit_submit false
  echo "Version unchanged ($current); uploading to TestFlight only."
fi
