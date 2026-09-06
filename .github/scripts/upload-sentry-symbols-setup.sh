#!/usr/bin/env bash
# Shared by ios-release.yml and play-store-release.yml (issue #7 U5; KTD10).
#
# Guards on the three Sentry upload secrets and, when present, downloads and
# checksum-verifies a pinned sentry-cli release binary into ./sentry-cli.
# Never `curl | bash`: the binary is downloaded, verified with the
# platform's own checksum tool, then made executable -- never piped
# straight into a shell, and never executed by this script itself.
#
# Required env:
#   SENTRY_AUTH_TOKEN, SENTRY_ORG, SENTRY_PROJECT  the upload secrets (the guard)
#   SENTRY_CLI_DOWNLOAD_URL                        pinned release binary URL
#   SENTRY_CLI_SHA256                              its expected sha256
#   SENTRY_CLI_CHECKSUM_TOOL                        "sha256sum" or "shasum"
#
# Exit contract -- the two outcomes are deliberately different, matching
# KTD10's "warn-and-skip a missing secret, but fail loudly on a corrupted or
# tampered binary" posture:
#   - Any of the three secrets missing: prints a ::warning:: naming issue
#     #19, leaves no ./sentry-cli file, and exits 0. A telemetry secret must
#     never fail a TestFlight/Play upload (R15).
#   - Secrets present: downloads and verifies the binary. A checksum
#     mismatch (or a failed download) is a real problem -- this script
#     exits non-zero and the calling step, and therefore the job, fails.
#     Only a passing checksum leaves ./sentry-cli present and executable.
#
# Callers gate the upload on the file's presence, e.g.:
#   bash .github/scripts/upload-sentry-symbols-setup.sh
#   if [ -x ./sentry-cli ]; then
#     ./sentry-cli debug-files upload <path>
#   fi
#
# R15: this script's own exit code alone is not enough to keep a Sentry
# outage from blocking a signed release -- `set -euo pipefail` means a
# non-zero exit here (a download timeout, a transient 5xx) already fails
# this script, but the *calling workflow step* must additionally run with
# `continue-on-error: true` so that failure degrades telemetry rather than
# the TestFlight/Play upload. See ios-release.yml's and
# play-store-release.yml's "Upload Sentry debug symbols" steps.
set -euo pipefail

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
  echo "::warning::Sentry symbol upload skipped -- SENTRY_AUTH_TOKEN/ORG/PROJECT not set (issue #19)."
  exit 0
fi

# --fail: treat an HTTP error response (4xx/5xx) as a failure instead of
# saving the error body as if it were the binary. --max-time: never let a
# hung Sentry/GitHub endpoint block the release job indefinitely.
# --retry/--retry-delay/--retry-connrefused: ride out a transient blip
# (DNS hiccup, momentary 5xx, connection refused) before giving up.
curl -sSL --fail --max-time 60 --retry 3 --retry-delay 2 \
  --retry-connrefused -o sentry-cli "$SENTRY_CLI_DOWNLOAD_URL"

case "$SENTRY_CLI_CHECKSUM_TOOL" in
  sha256sum) echo "${SENTRY_CLI_SHA256}  sentry-cli" | sha256sum -c - ;;
  shasum) echo "${SENTRY_CLI_SHA256}  sentry-cli" | shasum -a 256 -c - ;;
  *)
    echo "::error::unknown SENTRY_CLI_CHECKSUM_TOOL '$SENTRY_CLI_CHECKSUM_TOOL' (expected sha256sum or shasum)"
    exit 1
    ;;
esac

chmod +x sentry-cli
./sentry-cli --version
