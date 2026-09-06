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
# Exit contract -- three outcomes, deliberately different, matching KTD10's
# "warn-and-skip a hiccup, but fail loudly on a corrupted or tampered binary"
# posture:
#   - Any of the three secrets missing: prints a ::warning:: naming issue
#     #19, leaves no ./sentry-cli file, and exits 0. A telemetry secret must
#     never fail a TestFlight/Play upload (R15).
#   - The download itself fails (timeout, transient 5xx, connection refused,
#     after the retries below are exhausted): prints a ::warning::, leaves no
#     ./sentry-cli file, and exits 0 -- same "degrade telemetry, never block
#     the release" posture as a missing secret (R15). A network hiccup
#     fetching the binary is not a security event.
#   - The download succeeds but its checksum does not match
#     SENTRY_CLI_SHA256 (or SENTRY_CLI_CHECKSUM_TOOL is unrecognized): this
#     script exits non-zero and, unlike the two cases above, the *caller
#     must let that failure fail the job* -- round 2 of issue #7's review
#     flagged wrapping this in `continue-on-error` as inverting KTD10's
#     fail-loudly intent, since a mismatch here means the pinned binary may
#     be corrupted or tampered with, not merely unreachable. Only a passing
#     checksum leaves ./sentry-cli present and executable.
#
# Callers gate the upload on the file's presence, e.g.:
#   bash .github/scripts/upload-sentry-symbols-setup.sh
#   if [ -x ./sentry-cli ]; then
#     ./sentry-cli debug-files upload <path>
#   fi
#
# R15/KTD10 split across the two callers: the step running *this script*
# runs with no `continue-on-error`, so a checksum mismatch fails the job
# loudly; only the later step that makes the actual Sentry upload network
# call (`./sentry-cli debug-files upload`/`upload-proguard`) carries
# `continue-on-error: true`, so an outage on Sentry's end degrades telemetry
# without blocking the TestFlight/Play upload. See ios-release.yml's and
# play-store-release.yml's "Set up sentry-cli" and "Upload Sentry debug
# symbols" steps.
set -euo pipefail

if [ -z "${SENTRY_AUTH_TOKEN:-}" ] || [ -z "${SENTRY_ORG:-}" ] || [ -z "${SENTRY_PROJECT:-}" ]; then
  echo "::warning::Sentry symbol upload skipped -- SENTRY_AUTH_TOKEN/ORG/PROJECT not set (issue #19)."
  exit 0
fi

# --fail: treat an HTTP error response (4xx/5xx) as a failure instead of
# saving the error body as if it were the binary. --max-time: never let a
# hung Sentry/GitHub endpoint block the release job indefinitely.
# --retry/--retry-delay/--retry-connrefused: ride out a transient blip
# (DNS hiccup, momentary 5xx, connection refused) before giving up. A
# failure that survives those retries is treated the same as a missing
# secret (warn-and-skip, exit 0) rather than failing the job -- this is a
# network hiccup fetching the binary, not evidence the binary itself is
# corrupted or tampered with, so it must not share the checksum-mismatch
# branch's fail-loud treatment below.
if ! curl -sSL --fail --max-time 60 --retry 3 --retry-delay 2 \
  --retry-connrefused -o sentry-cli "$SENTRY_CLI_DOWNLOAD_URL"; then
  echo "::warning::Sentry symbol upload skipped -- sentry-cli download failed (network hiccup or a yanked release asset)."
  rm -f sentry-cli
  exit 0
fi

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
