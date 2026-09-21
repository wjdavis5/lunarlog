#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-web-build-output.sh
#
# Verifies that a `flutter build web` output directory is actually
# deployable (epic #831, slice 3). The deploy workflow runs this after the
# build and before any Cloudflare upload; it fails closed so a build that
# silently dropped the static routing/header files can never be published
# with the app's SPA deep links (`/auth/callback`) or its CSP missing.
#
# The two files that matter and that Flutter copies verbatim from `web/`:
#   * `_headers`   -- the CSP and cross-origin-isolation policy
#                     (`docs/web/security-posture.md`, section 3).
#   * `_redirects` -- the status-200 SPA fallback to `index.html`.
# A build with either missing is broken; this script is the check.
#
# Input (env):
#   WEB_BUILD_DIR  Build output directory. Defaults to `build/web`.
#
# Exit code: 0 when the output is deployable, non-zero otherwise. Every
# failure prints an `::error::` annotation naming the missing piece.

BUILD_DIR="${WEB_BUILD_DIR:-build/web}"

fail() {
  echo "::error::$1"
  exit 1
}

[ -d "$BUILD_DIR" ] ||
  fail "Web build output directory '$BUILD_DIR' does not exist; the build did not produce a deployable artifact."

# The app entry point and its compiled bundle: a directory that has the
# static files but no app is not a deployable build.
[ -s "$BUILD_DIR/index.html" ] ||
  fail "Web build output '$BUILD_DIR/index.html' is missing or empty."
[ -s "$BUILD_DIR/main.dart.js" ] ||
  fail "Web build output '$BUILD_DIR/main.dart.js' is missing or empty; the release compile did not emit the app bundle."

# `_headers`: present, and actually carrying the CSP.
[ -s "$BUILD_DIR/_headers" ] ||
  fail "Web build output '$BUILD_DIR/_headers' is missing or empty; the deployed origin would have no CSP (epic #831 security posture)."
headers="$(cat "$BUILD_DIR/_headers")"
case $headers in
  *"Content-Security-Policy"*) ;;
  *)
    fail "Web build output '$BUILD_DIR/_headers' carries no Content-Security-Policy directive."
    ;;
esac

# `_redirects`: present, and carrying the status-200 catch-all to
# `index.html` that makes `/auth/callback` and deep links resolve.
[ -s "$BUILD_DIR/_redirects" ] ||
  fail "Web build output '$BUILD_DIR/_redirects' is missing or empty; SPA deep links such as /auth/callback would 404."
spa_fallback=0
# `read` splits on whitespace without pathname expansion -- important,
# because the source pattern is the literal `/*` and an unquoted split
# would glob-expand it against the filesystem root. Works on the Bash 3.2
# the macOS release-guards job still runs.
while read -r src dest status _rest; do
  if [ "${src:-}" = "/*" ] && [ "${dest:-}" = "/index.html" ] && [ "${status:-}" = "200" ]; then
    spa_fallback=1
  fi
done <"$BUILD_DIR/_redirects"
[ "$spa_fallback" = 1 ] ||
  fail "Web build output '$BUILD_DIR/_redirects' has no '/* /index.html 200' catch-all."

echo "Web build output '$BUILD_DIR' is deployable: index.html, main.dart.js, _headers (CSP), and the SPA _redirects fallback are present."
