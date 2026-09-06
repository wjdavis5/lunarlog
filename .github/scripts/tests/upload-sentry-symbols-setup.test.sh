#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/upload-sentry-symbols-setup.sh. Run with:
#
#   bash .github/scripts/tests/upload-sentry-symbols-setup.test.sh
#
# Uses a tiny fake "sentry-cli" fixture (a shell script, not the real ~20MB
# binary) served over a file:// URL -- curl fetches file:// URLs natively,
# so this exercises the real download/checksum/chmod/execute path without a
# network call or the real download's size/time cost.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../upload-sentry-symbols-setup.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

FIXTURE="$WORKDIR/fake-sentry-cli.sh"
cat >"$FIXTURE" <<'EOF'
#!/usr/bin/env bash
echo "fake-sentry-cli 1.0.0"
EOF
# Deliberately not chmod +x: curl's file:// handler can copy a source
# file's mode bits along with its content, so the fixture must start
# non-executable for the "checksum mismatch never leaves sentry-cli
# executable" case below to actually prove the *script's* chmod (not
# curl's file copy) is what makes the success case executable.
#
# sha256sum is not on macOS by default (this test also runs on
# release-guards-macos, mirroring ios-release.yml's macos-latest runner) --
# fall back to shasum -a 256, the same choice the script itself offers.
if command -v sha256sum >/dev/null 2>&1; then
  FIXTURE_SHA256="$(sha256sum "$FIXTURE" | cut -d' ' -f1)"
else
  FIXTURE_SHA256="$(shasum -a 256 "$FIXTURE" | cut -d' ' -f1)"
fi
# Local-dev (Windows Git Bash) needs a Windows-style path after file:// --
# CI's Linux/macOS runners use the plain POSIX path directly.
if command -v cygpath >/dev/null 2>&1; then
  FIXTURE_URL="file:///$(cygpath -m "$FIXTURE")"
else
  FIXTURE_URL="file://$FIXTURE"
fi

# run_case SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT SENTRY_CLI_SHA256 SENTRY_CLI_CHECKSUM_TOOL
# Populates: $LAST_EXIT $LAST_LOG $LAST_CLI_PRESENT $LAST_CLI_EXECUTABLE
run_case() {
  local token="$1" org="$2" project="$3" sha="$4" tool="$5"
  local rundir logfile
  rundir="$(mktemp -d)"
  logfile="$(mktemp)"
  set +e
  (
    cd "$rundir"
    export SENTRY_AUTH_TOKEN="$token"
    export SENTRY_ORG="$org"
    export SENTRY_PROJECT="$project"
    export SENTRY_CLI_DOWNLOAD_URL="$FIXTURE_URL"
    export SENTRY_CLI_SHA256="$sha"
    export SENTRY_CLI_CHECKSUM_TOOL="$tool"
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  LAST_CLI_PRESENT="false"
  LAST_CLI_EXECUTABLE="false"
  if [ -e "$rundir/sentry-cli" ]; then LAST_CLI_PRESENT="true"; fi
  if [ -x "$rundir/sentry-cli" ]; then LAST_CLI_EXECUTABLE="true"; fi
  rm -f "$logfile"
  rm -rf "$rundir"
}

# --- Missing-secret guard: warn-and-skip, never fails the job ---

run_case "" "org" "proj" "$FIXTURE_SHA256" "sha256sum"
assert_eq "empty SENTRY_AUTH_TOKEN exits 0" 0 "$LAST_EXIT"
assert_contains "empty SENTRY_AUTH_TOKEN warns naming issue #19" "$LAST_LOG" "issue #19"
assert_eq "empty SENTRY_AUTH_TOKEN leaves no sentry-cli file" "false" "$LAST_CLI_PRESENT"

run_case "token" "" "proj" "$FIXTURE_SHA256" "sha256sum"
assert_eq "empty SENTRY_ORG exits 0" 0 "$LAST_EXIT"
assert_eq "empty SENTRY_ORG leaves no sentry-cli file" "false" "$LAST_CLI_PRESENT"

run_case "token" "org" "" "$FIXTURE_SHA256" "sha256sum"
assert_eq "empty SENTRY_PROJECT exits 0" 0 "$LAST_EXIT"
assert_eq "empty SENTRY_PROJECT leaves no sentry-cli file" "false" "$LAST_CLI_PRESENT"

run_case "" "" "" "$FIXTURE_SHA256" "sha256sum"
assert_eq "all three secrets empty exits 0" 0 "$LAST_EXIT"

# --- Secrets present: download, verify, chmod, execute ---

run_case "token" "org" "proj" "$FIXTURE_SHA256" "sha256sum"
assert_eq "valid checksum (sha256sum tool) exits 0" 0 "$LAST_EXIT"
assert_eq "valid checksum leaves sentry-cli executable" "true" "$LAST_CLI_EXECUTABLE"
assert_contains "valid checksum prints the fixture's --version output" "$LAST_LOG" "fake-sentry-cli 1.0.0"
assert_not_contains "no warning on the success path" "$LAST_LOG" "::warning::"

run_case "token" "org" "proj" "$FIXTURE_SHA256" "shasum"
assert_eq "valid checksum (shasum tool, macOS-shaped) exits 0" 0 "$LAST_EXIT"
assert_eq "valid checksum via shasum leaves sentry-cli executable" "true" "$LAST_CLI_EXECUTABLE"

# --- A tampered/wrong checksum must fail the job, not warn-and-skip ---

run_case "token" "org" "proj" "0000000000000000000000000000000000000000000000000000000000000000" "sha256sum"
assert_eq "checksum mismatch exits non-zero (fails the job)" 1 "$LAST_EXIT"
# set -e aborts the script at the failed checksum command, before chmod or
# `--version` -- proven here by the fixture's own output never appearing,
# which is the guarantee that actually matters (KTD10: never execute an
# unverified binary). A file-mode assertion here would be unreliable: Git
# Bash on Windows treats any file starting with a `#!` shebang as
# executable regardless of chmod state, which real POSIX chmod semantics
# (this script's actual CI runners: ubuntu-latest, macos-latest) do not.
assert_not_contains "checksum mismatch never runs the unverified binary" \
  "$LAST_LOG" "fake-sentry-cli 1.0.0"

run_case "token" "org" "proj" "$FIXTURE_SHA256" "md5sum"
assert_eq "an unrecognized checksum tool fails closed" 1 "$LAST_EXIT"
assert_contains "unrecognized checksum tool names itself in the error" "$LAST_LOG" "md5sum"

print_summary "upload-sentry-symbols-setup.test.sh"
