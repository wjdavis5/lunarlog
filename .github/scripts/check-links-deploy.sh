#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-links-deploy.sh
#
# Post-deploy smoke check for the apex site Worker on lunarlog.app
# (issue #1090; extended to the marketing pages by issue #1099).
# `site-deploy.yml` runs this immediately after `wrangler deploy`, so the job
# fails when the Worker is not actually owning its routes -- the exact failure
# #1090 documents: `wrangler.jsonc` bound static assets without
# `run_worker_first`, the asset layer answered both routes first, and the AASA
# went out as `application/octet-stream` with none of the Worker's headers
# while the unit tests stayed green (they call the handler directly). This
# runs against the live origin, which is the only place that failure is
# visible.
#
# It retries for up to ~90 s to allow for edge propagation, then fails
# closed unless every assertion below holds for the deployed origin.
#
# Issue #1099 adds the marketing-site assertions:
#   - `/` is 200 text/html carrying the strict header set from
#     `site/public/_headers` (CSP, HSTS, X-Frame-Options, Referrer-Policy,
#     nosniff);
#   - an unmatched path serves the Astro 404 page as a real 404, not a
#     redirect;
#   - the reserved `/fhir/*` URIs (issue #961) are a 404 and never a
#     redirect.
#
# Input (env):
#   LINKS_BASE_URL      Origin under test. Defaults to https://lunarlog.app.
#   LINKS_ATTEMPTS      Number of attempts. Defaults to 18.
#   LINKS_RETRY_DELAY   Seconds between attempts. Defaults to 5.
#   LINKS_FIXTURES_DIR  Test seam. When set, response header dumps are read
#                       from files in this directory instead of the network
#                       (see `.github/scripts/tests/check-links-deploy.test.sh`),
#                       and the retry loop collapses to a single attempt.
#
# Exit code: 0 when every assertion holds, non-zero otherwise. Each failure
# prints an `::error::` annotation naming the URL and the mismatch.

BASE_URL="${LINKS_BASE_URL:-https://lunarlog.app}"
ATTEMPTS="${LINKS_ATTEMPTS:-18}"
RETRY_DELAY="${LINKS_RETRY_DELAY:-5}"
FIXTURES_DIR="${LINKS_FIXTURES_DIR:-}"

HOME_URL="$BASE_URL/"
AASA_URL="$BASE_URL/.well-known/apple-app-site-association"
INVITE_URL="$BASE_URL/invite?code=smoke"
ASSETLINKS_URL="$BASE_URL/.well-known/assetlinks.json"
NOTFOUND_URL="$BASE_URL/this-page-does-not-exist"
FHIR_URL="$BASE_URL/fhir/CodeSystem/cycle-status"

if [ -n "$FIXTURES_DIR" ]; then
  # Fixtures already hold the settled response; retrying adds nothing.
  ATTEMPTS=1
elif ! command -v curl >/dev/null 2>&1; then
  echo "::error::curl is required for the links deploy smoke check."
  exit 1
fi

fail() {
  echo "::error::$1"
  exit 1
}

# fixture_path URL -- the recorded dump for a URL.
fixture_path() {
  case "$1" in
    */apple-app-site-association) printf '%s' "$FIXTURES_DIR/apple-app-site-association.headers" ;;
    */assetlinks.json) printf '%s' "$FIXTURES_DIR/assetlinks.json.headers" ;;
    */invite*) printf '%s' "$FIXTURES_DIR/invite.headers" ;;
    */fhir/*) printf '%s' "$FIXTURES_DIR/fhir.headers" ;;
    */this-page-does-not-exist) printf '%s' "$FIXTURES_DIR/notfound.headers" ;;
    "$HOME_URL"|"$BASE_URL") printf '%s' "$FIXTURES_DIR/home.headers" ;;
    *) printf '%s' "$FIXTURES_DIR/unknown.headers" ;;
  esac
}

# fetch URL -- prints the response's HTTP status line and headers to stdout.
# No `-L`: a redirect must be observed as a redirect, not followed, so the
# "200, no redirect" contract can actually be asserted. `--max-time 20` caps
# each request: a hung connection fails this attempt (empty output, so the
# status check fails it) and the retry loop simply tries again, rather than
# stalling the job until GitHub's 6-hour limit while it holds the deploy
# concurrency group.
fetch() {
  local url="$1"
  if [ -n "$FIXTURES_DIR" ]; then
    local fixture
    fixture="$(fixture_path "$url")"
    [ -f "$fixture" ] || {
      echo "missing fixture: $fixture" >&2
      return 1
    }
    cat "$fixture"
  else
    curl -sS --max-time 20 -o /dev/null -D - "$url"
  fi
}

# header_value DUMP NAME -- prints the response header's value, trimmed, or
# nothing. Header names are compared case-insensitively (lowercased via tr
# so this stays Bash 3.2-compatible, which the release-guards-macos job runs).
header_value() {
  local dump="$1" name="$2"
  local line lower value
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      *:*) ;;
      *) continue ;;
    esac
    lower="$(printf '%s' "${line%%:*}" | tr '[:upper:]' '[:lower:]')"
    if [ "$lower" = "$name" ]; then
      value="${line#*:}"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"
      printf '%s' "$value"
      return 0
    fi
  done <<<"$dump"
  return 1
}

# expect_status DUMP WANT URL -- prints an error message on mismatch, nothing
# on success.
expect_status() {
  local dump="$1" want="$2" url="$3"
  local first="${dump%%$'\n'*}"
  case "$first" in
    "HTTP/"*" $want" | "HTTP/"*" $want "*) return 0 ;;
    *)
      printf '%s: expected HTTP %s, got '%s'. ' "$url" "$want" "${first:-<no response>}"
      ;;
  esac
}

# expect_header_prefix DUMP NAME PREFIX URL -- the header must be present and
# its value must start with PREFIX (e.g. `application/json` accepting
# `application/json; charset=utf-8`).
expect_header_prefix() {
  local dump="$1" name="$2" prefix="$3" url="$4" got
  got="$(header_value "$dump" "$name" || true)"
  if [ -z "$got" ]; then
    printf '%s: missing %s header. ' "$url" "$name"
    return 0
  fi
  case "$got" in
    "$prefix"*) return 0 ;;
    *) printf '%s: expected %s to start with '%s', got '%s'. ' "$url" "$name" "$prefix" "$got" ;;
  esac
}

# expect_header_exact DUMP NAME VALUE URL -- the header must be present with
# exactly this value.
expect_header_exact() {
  local dump="$1" name="$2" want="$3" url="$4" got
  got="$(header_value "$dump" "$name" || true)"
  if [ -z "$got" ]; then
    printf '%s: missing %s header. ' "$url" "$name"
    return 0
  fi
  if [ "$got" != "$want" ]; then
    printf '%s: expected %s '%s', got '%s'. ' "$url" "$name" "$want" "$got"
  fi
}

# expect_header_contains DUMP NAME NEEDLE URL -- the named header must be
# present and its value must contain NEEDLE (e.g. a CSP directive).
expect_header_contains() {
  local dump="$1" name="$2" needle="$3" url="$4" got
  got="$(header_value "$dump" "$name" || true)"
  if [ -z "$got" ]; then
    printf '%s: missing %s header. ' "$url" "$name"
    return 0
  fi
  case "$got" in
    *"$needle"*) return 0 ;;
    *) printf '%s: expected %s to contain '%s', got '%s'. ' "$url" "$name" "$needle" "$got" ;;
  esac
}

# expect_header_absent DUMP NAME URL -- the header must not be present. Used
# to prove a route never redirects (no `location`).
expect_header_absent() {
  local dump="$1" name="$2" url="$3" got
  got="$(header_value "$dump" "$name" || true)"
  if [ -n "$got" ]; then
    printf "%s: unexpected %s header ('%s'). " "$url" "$name" "$got"
  fi
}

# check_once -- prints the accumulated problems (empty on success) and
# returns non-zero when any assertion failed.
check_once() {
  local home aasa invite assetlinks notfound fhir problems=""

  home="$(fetch "$HOME_URL" 2>/dev/null || true)"
  aasa="$(fetch "$AASA_URL" 2>/dev/null || true)"
  invite="$(fetch "$INVITE_URL" 2>/dev/null || true)"
  assetlinks="$(fetch "$ASSETLINKS_URL" 2>/dev/null || true)"
  notfound="$(fetch "$NOTFOUND_URL" 2>/dev/null || true)"
  fhir="$(fetch "$FHIR_URL" 2>/dev/null || true)"

  # The home page is served by the static-asset layer, so the strict header
  # set from `site/public/_headers` must be attached to it.
  problems="${problems}$(expect_status "$home" 200 "$HOME_URL")"
  problems="${problems}$(expect_header_prefix "$home" content-type text/html "$HOME_URL")"
  problems="${problems}$(expect_header_contains "$home" content-security-policy "default-src 'self'" "$HOME_URL")"
  problems="${problems}$(expect_header_contains "$home" content-security-policy "frame-ancestors 'none'" "$HOME_URL")"
  problems="${problems}$(expect_header_prefix "$home" strict-transport-security "max-age=" "$HOME_URL")"
  problems="${problems}$(expect_header_exact "$home" x-frame-options DENY "$HOME_URL")"
  problems="${problems}$(expect_header_exact "$home" referrer-policy no-referrer "$HOME_URL")"
  problems="${problems}$(expect_header_exact "$home" x-content-type-options nosniff "$HOME_URL")"

  # The AASA must be served by the Worker: 200 with no redirect,
  # application/json, and nosniff (index.ts's AASA branch).
  problems="${problems}$(expect_status "$aasa" 200 "$AASA_URL")"
  problems="${problems}$(expect_header_prefix "$aasa" content-type application/json "$AASA_URL")"
  problems="${problems}$(expect_header_exact "$aasa" x-content-type-options nosniff "$AASA_URL")"

  # /invite* must go through the Worker, which puts its own headers on the
  # asset (index.ts's invite branch): text/html, no-referrer, nosniff, and a
  # short cache.
  problems="${problems}$(expect_status "$invite" 200 "$INVITE_URL")"
  problems="${problems}$(expect_header_prefix "$invite" content-type text/html "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" referrer-policy no-referrer "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" x-content-type-options nosniff "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" cache-control "public, max-age=300" "$INVITE_URL")"

  # Android is deferred: no assetlinks.json file exists, so this route
  # reaches the Worker and must 404.
  problems="${problems}$(expect_status "$assetlinks" 404 "$ASSETLINKS_URL")"

  # An unmatched path serves the Astro 404 page: a real 404, text/html, and
  # never a redirect.
  problems="${problems}$(expect_status "$notfound" 404 "$NOTFOUND_URL")"
  problems="${problems}$(expect_header_prefix "$notfound" content-type text/html "$NOTFOUND_URL")"
  problems="${problems}$(expect_header_absent "$notfound" location "$NOTFOUND_URL")"

  # Issue #961: the frozen FHIR URIs are reserved. They must be a 404, never
  # a redirect.
  problems="${problems}$(expect_status "$fhir" 404 "$FHIR_URL")"
  problems="${problems}$(expect_header_absent "$fhir" location "$FHIR_URL")"

  if [ -n "$problems" ]; then
    printf '%s' "$problems"
    return 1
  fi
  return 0
}

attempt=1
while :; do
  if reason="$(check_once)"; then
    echo "Site deploy smoke check passed for '$BASE_URL' (home page headers, AASA, /invite, 404, /fhir reservation)."
    exit 0
  fi

  if [ "$attempt" -ge "$ATTEMPTS" ]; then
    fail "site deploy smoke check failed for '$BASE_URL' after $attempt attempt(s): $reason"
  fi

  echo "Live origin not ready (attempt $attempt/$ATTEMPTS): $reason"
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done
