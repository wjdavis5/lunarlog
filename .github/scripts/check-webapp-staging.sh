#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-webapp-staging.sh
#
# Post-deploy smoke check for the React web client's staging Worker
# (issue #1249). `webapp-deploy.yml` runs this immediately after the
# `wrangler deploy`, so the job fails when the workers.dev origin is not
# actually serving the release the repo declares.
#
# The assertions repurpose check-web-deploy.sh's (issue #1092, the Flutter
# web build's Pages smoke check) header and beacon pattern for the staging
# origin defined by webapp/worker/headers.ts:
#   * `/` returns 200 `text/html`, carries the security headers on every
#     response — a `Content-Security-Policy` with `script-src 'self'` and no
#     `unsafe-inline`/`unsafe-eval`/`wasm-unsafe-eval`, `frame-ancestors
#     'none'`, `connect-src` covering the Supabase project over https and
#     wss, `require-trusted-types-for 'script'`, `Cross-Origin-Opener-Policy:
#     same-origin`, `Strict-Transport-Security`, and
#     `X-Robots-Tag: noindex` — and its HTML ships a module script (the
#     actual app, not an empty shell).
#   * the HTML body fetched as a browser carries no Cloudflare Web Analytics
#     beacon (the check-web-deploy.sh #1139 posture, verbatim: the beacon is
#     a third-party script the deployed CSP blocks, so while
#     BEACON_MUST_BE_ABSENT is false the finding is a loud ::warning:: and
#     the check passes; flipping the constant makes it a hard failure).
#   * `/auth/callback?code=smoke` returns 200 `text/html` — the
#     single-page-application fallback (`not_found_handling` in
#     webapp/wrangler.jsonc), the entry #1250's flow lands in.
#
# Input (env):
#   WEBAPP_STAGING_BASE_URL   Origin under test. REQUIRED — the workers.dev
#                             hostname carries a per-account subdomain the
#                             repo cannot know; webapp-deploy.yml resolves
#                             it from the Cloudflare API after deploy.
#   WEBAPP_STAGING_ATTEMPTS   Number of attempts. Defaults to 18.
#   WEBAPP_STAGING_RETRY_DELAY  Seconds between attempts. Defaults to 5.
#   WEBAPP_STAGING_FIXTURES_DIR  Test seam. When set, response dumps are
#                             read from files in this directory instead of
#                             the network (see
#                             .github/scripts/tests/check-webapp-staging.test.sh),
#                             and the retry loop collapses to a single
#                             attempt.
#
# Exit code: 0 when every assertion holds, non-zero otherwise. Each failure
# prints an `::error::` annotation naming the URL and the mismatch.

BASE_URL="${WEBAPP_STAGING_BASE_URL:-}"
ATTEMPTS="${WEBAPP_STAGING_ATTEMPTS:-18}"
RETRY_DELAY="${WEBAPP_STAGING_RETRY_DELAY:-5}"
FIXTURES_DIR="${WEBAPP_STAGING_FIXTURES_DIR:-}"

# The production Supabase project staging is backed by (issue #1249); the
# same public origin webapp/worker/headers.ts allows in connect-src. The
# project URL is public (it ships inside every client).
SUPABASE_URL="${WEBAPP_STAGING_SUPABASE_URL:-https://dleexnnevuuddcgcpztq.supabase.co}"

ROOT_URL="$BASE_URL/"
CALLBACK_URL="$BASE_URL/auth/callback?code=smoke"

# Issue #1139's beacon posture, carried over from check-web-deploy.sh:
# browser UA only (the injector skips curl's default UA), warn-only while
# the constant is false.
BROWSER_UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
BEACON_MUST_BE_ABSENT=false

if [ -n "$FIXTURES_DIR" ]; then
  # Fixtures already hold the settled response; retrying adds nothing.
  ATTEMPTS=1
elif [ -z "$BASE_URL" ]; then
  echo "::error::WEBAPP_STAGING_BASE_URL is required (the workers.dev staging origin; webapp-deploy.yml resolves it from the Cloudflare API)."
  exit 1
elif ! command -v curl >/dev/null 2>&1; then
  echo "::error::curl is required for the webapp staging smoke check."
  exit 1
fi

fail() {
  echo "::error::$1"
  exit 1
}

# fixture_path URL KIND -- the recorded dump for a URL ("headers" or "body").
fixture_path() {
  case "$1" in
    */auth/callback*) printf '%s' "$FIXTURES_DIR/auth-callback.$2" ;;
    *) printf '%s' "$FIXTURES_DIR/root.$2" ;;
  esac
}

# fetch_headers URL -- prints the response's HTTP status line and headers to
# stdout. No `-L`: a redirect must be observed as a redirect, not followed.
fetch_headers() {
  local url="$1"
  if [ -n "$FIXTURES_DIR" ]; then
    local fixture
    fixture="$(fixture_path "$url" headers)"
    [ -f "$fixture" ] || {
      echo "missing fixture: $fixture" >&2
      return 1
    }
    cat "$fixture"
  else
    curl -sS --max-time 20 -A "$BROWSER_UA" -H 'Accept: text/html' -o /dev/null -D - "$url"
  fi
}

# fetch_body URL -- prints the response body to stdout.
fetch_body() {
  local url="$1"
  if [ -n "$FIXTURES_DIR" ]; then
    local fixture
    fixture="$(fixture_path "$url" body)"
    [ -f "$fixture" ] || {
      echo "missing fixture: $fixture" >&2
      return 1
    }
    cat "$fixture"
  else
    curl -sS --max-time 20 -A "$BROWSER_UA" -H 'Accept: text/html' "$url"
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
# its value must start with PREFIX.
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

# expect_header_contains DUMP NAME NEEDLE URL -- the header must be present
# and its value must contain NEEDLE (the CSP carries many directives, so an
# exact match would be brittle).
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

# expect_header_present DUMP NAME URL -- the header must be present, whatever
# its value.
expect_header_present() {
  local dump="$1" name="$2" url="$3" got
  got="$(header_value "$dump" "$name" || true)"
  if [ -z "$got" ]; then
    printf '%s: missing %s header. ' "$url" "$name"
  fi
}

# expect_csp_without DUMP FORBIDDEN URL -- the CSP must NOT contain the
# directive (the unsafe-* evaluation paths the issue forbids).
expect_csp_without() {
  local dump="$1" forbidden="$2" url="$3" got
  got="$(header_value "$dump" content-security-policy || true)"
  if [ -z "$got" ]; then
    printf '%s: missing content-security-policy header. ' "$url"
    return 0
  fi
  case "$got" in
    *"$forbidden"*) printf '%s: the CSP must not contain '%s'. ' "$url" "$forbidden" ;;
  esac
}

# beacon_finding URL -- the finding text for an injected Web Analytics
# beacon: the accumulated problem text when armed, the body of the
# ::warning:: line when warn-only.
beacon_finding() {
  printf '%s: Cloudflare Web Analytics beacon injected into the staging HTML (issue #1249, carrying over check-web-deploy.sh #1139) -- turn Web Analytics automatic injection off for the account/zone, or record the decision to keep it and disclose it in PRIVACY.md. ' "$1"
}

# expect_body_without_cf_beacon BODY URL -- same contract as
# check-web-deploy.sh's (issue #1139): warn-only while BEACON_MUST_BE_ABSENT
# is false, a hard failure once it flips to true.
expect_body_without_cf_beacon() {
  local body="$1" url="$2"
  case "$body" in
    *cloudflareinsights*|*data-cf-beacon*) ;;
    *) return 0 ;;
  esac
  if [ "$BEACON_MUST_BE_ABSENT" != "true" ]; then
    printf '::warning::%s(warn-only while BEACON_MUST_BE_ABSENT=false at the top of this script; flip it once the owner decides)\n' "$(beacon_finding "$url")" >&2
    return 0
  fi
  beacon_finding "$url"
}

# check_once -- prints the accumulated problems (empty on success) and
# returns non-zero when any assertion failed.
check_once() {
  local root callback root_body problems=""

  root="$(fetch_headers "$ROOT_URL" 2>/dev/null || true)"
  callback="$(fetch_headers "$CALLBACK_URL" 2>/dev/null || true)"
  root_body="$(fetch_body "$ROOT_URL" 2>/dev/null || true)"

  # `/` is the app shell: 200 HTML carrying the declared security posture.
  problems="${problems}$(expect_status "$root" 200 "$ROOT_URL")"
  problems="${problems}$(expect_header_prefix "$root" content-type text/html "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "script-src 'self'" "$ROOT_URL")"
  problems="${problems}$(expect_csp_without "$root" "'unsafe-inline'" "$ROOT_URL")"
  problems="${problems}$(expect_csp_without "$root" "'unsafe-eval'" "$ROOT_URL")"
  problems="${problems}$(expect_csp_without "$root" "'wasm-unsafe-eval'" "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "frame-ancestors 'none'" "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "require-trusted-types-for 'script'" "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "$SUPABASE_URL" "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "wss://$(printf '%s' "$SUPABASE_URL" | sed 's|^https://||')" "$ROOT_URL")"
  problems="${problems}$(expect_header_exact "$root" cross-origin-opener-policy same-origin "$ROOT_URL")"
  problems="${problems}$(expect_header_present "$root" strict-transport-security "$ROOT_URL")"
  problems="${problems}$(expect_header_exact "$root" x-robots-tag noindex "$ROOT_URL")"

  # And the shell must actually be the app: a module script tag (the Vite
  # bundle), plus no Web Analytics beacon as a browser sees it (issue #1139).
  case "$root_body" in
    *"<script type=\"module\""*) ;;
    *) problems="${problems}$ROOT_URL: the shell HTML carries no <script type=module> tag. " ;;
  esac
  problems="${problems}$(expect_body_without_cf_beacon "$root_body" "$ROOT_URL")"

  # `/auth/callback` must reach the SPA fallback, never a 404 -- #1250's
  # entry point.
  problems="${problems}$(expect_status "$callback" 200 "$CALLBACK_URL")"
  problems="${problems}$(expect_header_prefix "$callback" content-type text/html "$CALLBACK_URL")"

  if [ -n "$problems" ]; then
    printf '%s' "$problems"
    return 1
  fi
  return 0
}

attempt=1
while :; do
  if reason="$(check_once)"; then
    echo "Webapp staging smoke check passed for '$BASE_URL' (/, /auth/callback)."
    exit 0
  fi

  if [ "$attempt" -ge "$ATTEMPTS" ]; then
    fail "webapp staging smoke check failed for '$BASE_URL' after $attempt attempt(s): $reason"
  fi

  echo "Staging origin not ready (attempt $attempt/$ATTEMPTS): $reason"
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done
