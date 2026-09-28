#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-web-deploy.sh
#
# Post-deploy smoke check for the lunarlog web client on app.lunarlog.app
# (issue #1092). `web-deploy.yml` runs this immediately after the Cloudflare
# Pages upload, so the job fails when the origin is not actually serving the
# release the repo declares.
#
# `web/_headers` and `web/_redirects` are copied into the build and asserted
# against the build directory by `check-web-build-output.sh`, but that only
# proves the files were packaged -- not that Cloudflare applied them at the
# edge. `check-links-deploy.sh` (issue #1090) exists for exactly the same
# reason on the apex: a declared header that the origin never serves looks
# green in a unit test. This runs against the live origin, the only place
# that failure is visible.
#
# It retries for up to ~90 s to allow for edge propagation, then fails closed
# unless every assertion below holds for the deployed origin:
#   * `/` returns 200 `text/html` and carries the `/*` headers from
#     `web/_headers`: a `Content-Security-Policy` with `script-src 'self'`,
#     `Cross-Origin-Opener-Policy: same-origin`,
#     `Cross-Origin-Embedder-Policy: require-corp`, `Strict-Transport-Security`,
#     and `X-Robots-Tag: noindex`.
#   * `/auth/callback?code=smoke` returns 200 `text/html` (the `_redirects`
#     SPA fallback, not a 404).
#   * `/privacy.html` returns a 301 to `https://lunarlog.app/privacy`
#     (issue #1101: the retired second copy of the policy must redirect to
#     the canonical page, never 404 and never fall through to the SPA).
#   * `/flutter_bootstrap.js` returns 200 and sets
#     `"useLocalCanvasKit":true` (issue #1091: otherwise Flutter fetches
#     CanvasKit from a CDN the deployed CSP blocks).
#   * the `/` HTML body fetched as a browser carries no Cloudflare Web
#     Analytics beacon (issue #1139): `cloudflareinsights` /
#     `data-cf-beacon` in the body means the zone or the Pages project has
#     automatic Web Analytics switched on -- a third-party analytics script
#     the deployed CSP blocks (so the injection is inert today) and
#     PRIVACY.md does not disclose. While BEACON_MUST_BE_ABSENT at the top
#     of this script is false (the default) the finding is a loud
#     ::warning:: and the check passes; flipping that constant to true --
#     one line, after the owner decides (toggle Web Analytics off, or keep
#     and disclose in PRIVACY.md) -- makes the same finding a hard failure.
#
# Input (env):
#   WEB_DEPLOY_BASE_URL      Origin under test. Defaults to
#                            https://app.lunarlog.app.
#   WEB_DEPLOY_ATTEMPTS      Number of attempts. Defaults to 18.
#   WEB_DEPLOY_RETRY_DELAY   Seconds between attempts. Defaults to 5.
#   WEB_DEPLOY_FIXTURES_DIR  Test seam. When set, response dumps are read
#                            from files in this directory instead of the
#                            network (see
#                            `.github/scripts/tests/check-web-deploy.test.sh`),
#                            and the retry loop collapses to a single attempt.
#
# Exit code: 0 when every assertion holds, non-zero otherwise. Each failure
# prints an `::error::` annotation naming the URL and the mismatch.

BASE_URL="${WEB_DEPLOY_BASE_URL:-https://app.lunarlog.app}"
ATTEMPTS="${WEB_DEPLOY_ATTEMPTS:-18}"
RETRY_DELAY="${WEB_DEPLOY_RETRY_DELAY:-5}"
FIXTURES_DIR="${WEB_DEPLOY_FIXTURES_DIR:-}"

ROOT_URL="$BASE_URL/"
CALLBACK_URL="$BASE_URL/auth/callback?code=smoke"
PRIVACY_REDIRECT_URL="$BASE_URL/privacy.html"
BOOTSTRAP_URL="$BASE_URL/flutter_bootstrap.js"

# Issue #1139: Cloudflare injects its Web Analytics beacon into HTML
# responses for *browser* user-agents only -- curl's default UA gets a clean
# body, which is exactly the blind spot the beacon shipped through. Every
# live fetch below therefore presents a browser UA and `Accept: text/html`.
# The headers change nothing for the non-HTML fetch (flutter_bootstrap.js is
# served by extension, not content negotiation), so the assertions above
# keep their meaning.
BROWSER_UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

# Issue #1139 arming switch. The beacon is INERT today -- both origins' CSPs
# (script-src 'self') block the injected script from executing, so no data
# flows -- so the default posture is WARN: the deploy goes green with a
# loud ::warning:: naming the marker and the owner decision. Flip this to
# true (one line, its own reviewed commit) to make the same finding hard-
# fail the smoke check: do that when the owner decides they want the
# forcing function, or as the enforcement half of a keep-and-disclose
# decision. The decision itself lives in issue #1139.
BEACON_MUST_BE_ABSENT=false

# The canonical target `/privacy.html` must redirect to (issue #1101). Exact:
# the marketing site is the policy's only home.
PRIVACY_CANONICAL="https://lunarlog.app/privacy"

if [ -n "$FIXTURES_DIR" ]; then
  # Fixtures already hold the settled response; retrying adds nothing.
  ATTEMPTS=1
elif ! command -v curl >/dev/null 2>&1; then
  echo "::error::curl is required for the web deploy smoke check."
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
    */privacy.html) printf '%s' "$FIXTURES_DIR/privacy-redirect.$2" ;;
    */flutter_bootstrap.js) printf '%s' "$FIXTURES_DIR/flutter-bootstrap.$2" ;;
    *) printf '%s' "$FIXTURES_DIR/root.$2" ;;
  esac
}

# fetch_headers URL -- prints the response's HTTP status line and headers to
# stdout. No `-L`: a redirect must be observed as a redirect, not followed, so
# the "200, no redirect" contract can actually be asserted. `--max-time 20`
# caps each request: a hung connection fails this attempt (empty output, so
# the status check fails it) and the retry loop simply tries again, rather
# than stalling the job while it holds the deploy concurrency group.
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
# its value must start with PREFIX (e.g. `text/html` accepting
# `text/html; charset=utf-8`).
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

# beacon_finding URL -- the finding text for an injected Web Analytics
# beacon: the accumulated problem text when armed, the body of the
# ::warning:: line when warn-only.
beacon_finding() {
  printf '%s: Cloudflare Web Analytics beacon injected into the HTML (issue #1139) -- turn Web Analytics automatic injection off for the zone/project, or record the decision to keep it and disclose it in PRIVACY.md. ' "$1"
}

# expect_body_without_cf_beacon BODY URL -- the HTML body must carry no
# Cloudflare Web Analytics beacon (issue #1139): a third-party analytics
# script the deployed CSP blocks (so it is inert today) and PRIVACY.md does
# not disclose. Both spellings the injector emits are matched -- the
# `static.cloudflareinsights.com` script src and the `data-cf-beacon`
# attribute -- so a change to the tag's shape on either side still fails.
# While BEACON_MUST_BE_ABSENT is false (the default) the finding is a loud
# ::warning:: on the step log and this check still passes -- hard-failing
# every deploy over an inert injection is the owner's call, not this
# script's. Flipping the constant to true turns the same finding into an
# accumulated problem and a hard failure.
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
  local root callback privacy_redirect bootstrap_headers bootstrap_body root_body problems=""

  root="$(fetch_headers "$ROOT_URL" 2>/dev/null || true)"
  callback="$(fetch_headers "$CALLBACK_URL" 2>/dev/null || true)"
  privacy_redirect="$(fetch_headers "$PRIVACY_REDIRECT_URL" 2>/dev/null || true)"
  bootstrap_headers="$(fetch_headers "$BOOTSTRAP_URL" 2>/dev/null || true)"
  bootstrap_body="$(fetch_body "$BOOTSTRAP_URL" 2>/dev/null || true)"
  root_body="$(fetch_body "$ROOT_URL" 2>/dev/null || true)"

  # `/` is the app shell: 200 HTML carrying every `/*` header declared in
  # `web/_headers`.
  problems="${problems}$(expect_status "$root" 200 "$ROOT_URL")"
  problems="${problems}$(expect_header_prefix "$root" content-type text/html "$ROOT_URL")"
  problems="${problems}$(expect_header_contains "$root" content-security-policy "script-src 'self'" "$ROOT_URL")"
  problems="${problems}$(expect_header_exact "$root" cross-origin-opener-policy same-origin "$ROOT_URL")"
  problems="${problems}$(expect_header_exact "$root" cross-origin-embedder-policy require-corp "$ROOT_URL")"
  problems="${problems}$(expect_header_present "$root" strict-transport-security "$ROOT_URL")"
  problems="${problems}$(expect_header_exact "$root" x-robots-tag noindex "$ROOT_URL")"

  # And the shell itself, as a browser sees it, must carry no Web Analytics
  # beacon (issue #1139; see expect_body_without_cf_beacon).
  problems="${problems}$(expect_body_without_cf_beacon "$root_body" "$ROOT_URL")"

  # `/auth/callback` must reach the SPA fallback (`web/_redirects`), never a
  # 404 -- the slice-2 email links land here.
  problems="${problems}$(expect_status "$callback" 200 "$CALLBACK_URL")"
  problems="${problems}$(expect_header_prefix "$callback" content-type text/html "$CALLBACK_URL")"

  # The retired `/privacy.html` must 301 to the canonical policy page
  # (issue #1101) -- not 404, and never the SPA fallback swallowing it with
  # a 200.
  problems="${problems}$(expect_status "$privacy_redirect" 301 "$PRIVACY_REDIRECT_URL")"
  problems="${problems}$(expect_header_exact "$privacy_redirect" location "$PRIVACY_CANONICAL" "$PRIVACY_REDIRECT_URL")"

  # `flutter_bootstrap.js` must resolve CanvasKit from the build rather than
  # www.gstatic.com, which the deployed CSP blocks (issue #1091).
  problems="${problems}$(expect_status "$bootstrap_headers" 200 "$BOOTSTRAP_URL")"
  case "$bootstrap_body" in
    *'"useLocalCanvasKit":true'*) ;;
    *) problems="${problems}$BOOTSTRAP_URL: flutter_bootstrap.js is missing \"useLocalCanvasKit\":true (issue #1091). " ;;
  esac

  if [ -n "$problems" ]; then
    printf '%s' "$problems"
    return 1
  fi
  return 0
}

attempt=1
while :; do
  if reason="$(check_once)"; then
    echo "Web deploy smoke check passed for '$BASE_URL' (/, /auth/callback, /privacy.html -> 301, /flutter_bootstrap.js)."
    exit 0
  fi

  if [ "$attempt" -ge "$ATTEMPTS" ]; then
    fail "web deploy smoke check failed for '$BASE_URL' after $attempt attempt(s): $reason"
  fi

  echo "Live origin not ready (attempt $attempt/$ATTEMPTS): $reason"
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done
