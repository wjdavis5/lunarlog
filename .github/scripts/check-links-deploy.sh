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
# Issue #1157 adds the store privacy-policy assertion. `/privacy` is the
# Privacy policy URL both stores list (docs/ops/store-declarations.md,
# docs/ops/play-health-declaration.md, Android's Health Connect rationale
# screen), and issue #1157 is exactly a deploy where it 404'd for days
# unnoticed. The asset layer's auto-trailing-slash serves the contract as
# two hops -- `/privacy` redirects to `/privacy/`, which serves the
# PRIVACY.md render -- so both are asserted: the bare URL must redirect
# exactly to `/privacy/`, and `/privacy/` must be 200 text/html. A deploy
# that drops the privacy page fails here instead of leaving the store
# listing pointing at a 404. `/support/` (the in-app help link's target and
# where #1153's copy fix ships) is asserted 200 text/html alongside.
#
# Issue #1139 adds the Cloudflare Web Analytics beacon assertion. Cloudflare
# injects the beacon into HTML responses for *browser* user-agents only --
# curl's default UA sees a clean body, which is exactly the blind spot the
# beacon shipped through -- so every live fetch below presents a browser UA
# with `Accept: text/html`, and every HTML route's body is asserted free of
# the beacon (`cloudflareinsights` / `data-cf-beacon`): a third-party
# analytics script the deployed CSP blocks (so the injection is inert
# today) and PRIVACY.md does not disclose. While BEACON_MUST_BE_ABSENT at
# the top of this script is false (the default) the finding is a loud
# ::warning:: and the check passes; flipping that constant to true -- one
# line, after the owner decides (toggle Web Analytics off, or keep and
# disclose in PRIVACY.md) -- makes the same finding a hard failure.
#
# Issue #1184 closes the gap between that assertion and the doc claim it
# backed (docs/web/security-posture.md): the beacon check is not five
# hand-picked routes, it is every HTML route the built site ships. The
# route list is enumerated from the Astro build output the deploy just
# uploaded (one route per .html file under LINKS_SITE_DIST, default
# <repo>/site/dist resolved from this script's own location), and each
# route is asserted 200, text/html, and beacon-free. site-deploy.yml
# builds the site before this check runs, so the wired path always
# enumerates the exact route set that was deployed. The built 404.html is
# excluded: the asset layer serves it only for *unmatched* paths, whose
# check below carries the beacon assertion -- requesting /404 directly
# would assert the asset layer's incidental serving shape, not any route
# a browser is ever served. When the build output is absent (only
# possible when the script runs outside the deploy workflow), the check
# warns and the beacon assertion covers only the unmatched-path 404 page
# below.
#
# Input (env):
#   LINKS_BASE_URL      Origin under test. Defaults to https://lunarlog.app.
#   LINKS_ATTEMPTS      Number of attempts. Defaults to 18.
#   LINKS_RETRY_DELAY   Seconds between attempts. Defaults to 5.
#   LINKS_SITE_DIST     Built-site directory the HTML route list is
#                       enumerated from (issue #1184). Defaults to
#                       <repo>/site/dist resolved from this script's own
#                       location; the fixture suite points it at a fake
#                       build tree.
#   LINKS_FIXTURES_DIR  Test seam. When set, response header and body dumps
#                       are read from files in this directory instead of the
#                       network (see
#                       `.github/scripts/tests/check-links-deploy.test.sh`),
#                       and the retry loop collapses to a single attempt.
#
# Exit code: 0 when every assertion holds, non-zero otherwise. Each failure
# prints an `::error::` annotation naming the URL and the mismatch.

BASE_URL="${LINKS_BASE_URL:-https://lunarlog.app}"
ATTEMPTS="${LINKS_ATTEMPTS:-18}"
RETRY_DELAY="${LINKS_RETRY_DELAY:-5}"
FIXTURES_DIR="${LINKS_FIXTURES_DIR:-}"

# Issue #1184: the HTML route list is enumerated from the Astro build
# output the deploy just uploaded. Resolved from this script's own location
# so it works from any cwd; site-deploy.yml checks out the repo and builds
# site/dist before running this script, so the default always finds it.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SITE_DIST="${LINKS_SITE_DIST:-$REPO_ROOT/site/dist}"
SITE_DIST="${SITE_DIST%/}"

HOME_URL="$BASE_URL/"
AASA_URL="$BASE_URL/.well-known/apple-app-site-association"
INVITE_URL="$BASE_URL/invite?code=smoke"
ASSETLINKS_URL="$BASE_URL/.well-known/assetlinks.json"
NOTFOUND_URL="$BASE_URL/this-page-does-not-exist"
FHIR_URL="$BASE_URL/fhir/CodeSystem/cycle-status"
PRIVACY_URL="$BASE_URL/privacy"
PRIVACY_PAGE_URL="$BASE_URL/privacy/"
SUPPORT_URL="$BASE_URL/support/"

# Issue #1139: Cloudflare injects its Web Analytics beacon into HTML
# responses for *browser* user-agents only -- curl's default UA gets a clean
# body, which is exactly the blind spot the beacon shipped through. Every
# live fetch below therefore presents a browser UA and `Accept: text/html`.
# The headers change nothing for the JSON routes (the AASA, assetlinks,
# /fhir/* are served by extension, not content negotiation), so the
# assertions on them keep their meaning.
BROWSER_UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'

# Issue #1139 arming switch. The beacon is INERT today -- the apex CSP
# (script-src 'self') blocks the injected script from executing, so no data
# flows -- so the default posture is WARN: the deploy goes green with a
# loud ::warning:: naming the marker and the owner decision. Flip this to
# true (one line, its own reviewed commit) to make the same finding hard-
# fail the smoke check: do that when the owner decides they want the
# forcing function, or as the enforcement half of a keep-and-disclose
# decision. The decision itself lives in issue #1139.
BEACON_MUST_BE_ABSENT=false

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

# fixture_path URL KIND -- the recorded dump for a URL ("headers" or
# "body"). Only the HTML routes ever get a body fetch (issue #1139's beacon
# assertion is HTML-only; the JSON routes are never body-checked), so only
# those have .body fixtures.
fixture_path() {
  case "$1" in
    */apple-app-site-association) printf '%s' "$FIXTURES_DIR/apple-app-site-association.$2" ;;
    */assetlinks.json) printf '%s' "$FIXTURES_DIR/assetlinks.json.$2" ;;
    */invite*) printf '%s' "$FIXTURES_DIR/invite.$2" ;;
    */fhir/*) printf '%s' "$FIXTURES_DIR/fhir.$2" ;;
    */privacy/) printf '%s' "$FIXTURES_DIR/privacy-slash.$2" ;;
    */privacy) printf '%s' "$FIXTURES_DIR/privacy.$2" ;;
    */support/) printf '%s' "$FIXTURES_DIR/support.$2" ;;
    */this-page-does-not-exist) printf '%s' "$FIXTURES_DIR/notfound.$2" ;;
    "$HOME_URL"|"$BASE_URL") printf '%s' "$FIXTURES_DIR/home.$2" ;;
    # Any enumerated route (issue #1184): the URL path becomes the fixture
    # stem -- leading/trailing slashes stripped, inner slashes dashed
    # (/guides/getting-started/ -> route-guides-getting-started.*). Pure
    # parameter expansion: the route loop below calls this once per fetch,
    # and it must not add a process spawn per route.
    *)
      local stem="${1#"$BASE_URL"}"
      stem="${stem#/}"
      stem="${stem%/}"
      printf '%s' "$FIXTURES_DIR/route-${stem//\//-}.$2" ;;
  esac
}

# enumerated_routes -- prints the URL of every HTML route the built site
# ships, one per line, sorted (issue #1184). One route per .html file under
# SITE_DIST: dist/index.html is the home page, <dir>/index.html a
# directory-format page (Astro's default), any other .html a flat public
# file (public/invite.html at /invite). 404.html is skipped -- the asset
# layer serves it only for unmatched paths, and the unmatched-path check in
# check_once carries its beacon assertion. Returns non-zero when the build
# output is absent, so the caller can warn and fall back to the built-in
# routes.
enumerated_routes() {
  local f rel
  [ -d "$SITE_DIST" ] || return 1
  find "$SITE_DIST" -type f -name '*.html' | LC_ALL=C sort |
    while IFS= read -r f; do
      rel="${f#"$SITE_DIST"/}"
      case "$rel" in
        404.html) ;;
        index.html) printf '%s/\n' "$BASE_URL" ;;
        */index.html) printf '%s/%s/\n' "$BASE_URL" "${rel%/index.html}" ;;
        *) printf '%s/%s\n' "$BASE_URL" "${rel%.html}" ;;
      esac
    done
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

# fetch_body URL -- prints the response body to stdout. Same fixture seam,
# timeout cap, and browser-UA headers as `fetch` (issue #1139: the browser
# UA is what makes the edge's injection visible at all).
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

# expect_redirect_to DUMP WANT_LOCATION URL -- the response must be a 3xx
# redirect whose location is exactly WANT_LOCATION. Used for the asset
# layer's auto-trailing-slash hop (`/privacy` -> `/privacy/`): which 3xx
# code the asset layer picks is its own choice (307 today), so any 3xx
# passes, but the redirect target is the contract and is matched exactly.
expect_redirect_to() {
  local dump="$1" want_location="$2" url="$3"
  local first="${dump%%$'\n'*}" got
  case "$first" in
    "HTTP/"*" 3"[0-9][0-9] | "HTTP/"*" 3"[0-9][0-9]" "*) ;;
    *)
      printf '%s: expected a 3xx redirect, got '%s'. ' "$url" "${first:-<no response>}"
      return 0
      ;;
  esac
  got="$(header_value "$dump" location || true)"
  if [ "$got" != "$want_location" ]; then
    printf '%s: expected the redirect to land on '%s', got '%s'. ' "$url" "$want_location" "${got:-<none>}"
  fi
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
  local home aasa invite assetlinks notfound fhir privacy privacy_page support problems=""
  local notfound_body
  local routes route_url route route_body route_problems

  home="$(fetch "$HOME_URL" 2>/dev/null || true)"
  aasa="$(fetch "$AASA_URL" 2>/dev/null || true)"
  invite="$(fetch "$INVITE_URL" 2>/dev/null || true)"
  assetlinks="$(fetch "$ASSETLINKS_URL" 2>/dev/null || true)"
  notfound="$(fetch "$NOTFOUND_URL" 2>/dev/null || true)"
  fhir="$(fetch "$FHIR_URL" 2>/dev/null || true)"
  privacy="$(fetch "$PRIVACY_URL" 2>/dev/null || true)"
  privacy_page="$(fetch "$PRIVACY_PAGE_URL" 2>/dev/null || true)"
  support="$(fetch "$SUPPORT_URL" 2>/dev/null || true)"
  notfound_body="$(fetch_body "$NOTFOUND_URL" 2>/dev/null || true)"

  # The home page is served by the static-asset layer, so the strict header
  # set from `site/public/_headers` must be attached to it. Its body's
  # beacon assertion (issue #1139) now lives in the route enumeration below
  # (issue #1184), which covers it like every other HTML route.
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

  # /invite* must go through the Worker, which writes this page's headers
  # itself (index.ts's invite branch): `_headers` does not reach a response
  # the Worker produces. So the Worker has to send what `_headers` sends
  # everywhere else, and this is where that is checked: text/html,
  # no-referrer, nosniff, the frame and transport policies, a short cache
  # the proxy may not transform, and a Content-Security-Policy that allows
  # nothing but the page's own inline script and style, by hash.
  #
  # Until these were asserted the page had no Content-Security-Policy at
  # all. Issue #1139's beacon is "inert" only where a policy refuses it, and
  # on this page, the one whose address carries a redeemable code, nothing
  # did: the injected script ran. `no-transform` asks the proxy not to
  # inject here in the first place; the policy is what holds if it does.
  #
  # Its body's beacon assertion still lives in the route enumeration below
  # (issue #1184) -- the enumerated /invite (from public/invite.html)
  # reaches the same Worker branch as this query-carrying URL.
  problems="${problems}$(expect_status "$invite" 200 "$INVITE_URL")"
  problems="${problems}$(expect_header_prefix "$invite" content-type text/html "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" referrer-policy no-referrer "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" x-content-type-options nosniff "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" cache-control "public, max-age=300, no-transform" "$INVITE_URL")"
  problems="${problems}$(expect_header_contains "$invite" content-security-policy "default-src 'none'" "$INVITE_URL")"
  problems="${problems}$(expect_header_contains "$invite" content-security-policy "frame-ancestors 'none'" "$INVITE_URL")"
  problems="${problems}$(expect_header_contains "$invite" content-security-policy "script-src 'sha256-" "$INVITE_URL")"
  problems="${problems}$(expect_header_prefix "$invite" strict-transport-security "max-age=" "$INVITE_URL")"
  problems="${problems}$(expect_header_exact "$invite" x-frame-options DENY "$INVITE_URL")"

  # Issue #1157: the store privacy-policy URL must resolve. `/privacy` (the
  # exact URL both stores list) redirects to `/privacy/`, which serves the
  # PRIVACY.md render; a deploy that drops the privacy page turns one of
  # the two hops into a 404.
  problems="${problems}$(expect_redirect_to "$privacy" "/privacy/" "$PRIVACY_URL")"
  problems="${problems}$(expect_status "$privacy_page" 200 "$PRIVACY_PAGE_URL")"
  problems="${problems}$(expect_header_prefix "$privacy_page" content-type text/html "$PRIVACY_PAGE_URL")"

  # The support page must stay live: it is where the in-app help link goes
  # and where #1153's import-scope copy fix ships.
  problems="${problems}$(expect_status "$support" 200 "$SUPPORT_URL")"
  problems="${problems}$(expect_header_prefix "$support" content-type text/html "$SUPPORT_URL")"

  # Issue #1184: the beacon assertion (with a 200 text/html precondition, so
  # a dropped page cannot pass vacuously) now runs over EVERY HTML route the
  # built site ships, not just the routes the blocks above cover. The route
  # list is enumerated from the Astro build output the deploy just uploaded
  # (see enumerated_routes); without it -- only possible outside the deploy
  # workflow -- a loud warning emits and the beacon assertion shrinks to the
  # unmatched-path 404 page below.
  if routes="$(enumerated_routes)"; then
    while IFS= read -r route_url; do
      [ -n "$route_url" ] || continue
      route="$(fetch "$route_url" 2>/dev/null || true)"
      route_body="$(fetch_body "$route_url" 2>/dev/null || true)"
      # One command substitution for all three assertions, not one each:
      # this loop runs once per route per attempt and every $( ) is a fork.
      route_problems="$(expect_status "$route" 200 "$route_url"
        expect_header_prefix "$route" content-type text/html "$route_url"
        expect_body_without_cf_beacon "$route_body" "$route_url")"
      problems="$problems$route_problems"
    done <<<"$routes"
  else
    printf '::warning::%s: site build output not found at %s -- the HTML routes cannot be enumerated; the beacon assertion covers only the unmatched-path 404 page (issue #1184)\n' "$BASE_URL" "$SITE_DIST" >&2
  fi

  # Android is deferred: no assetlinks.json file exists, so this route
  # reaches the Worker and must 404.
  problems="${problems}$(expect_status "$assetlinks" 404 "$ASSETLINKS_URL")"

  # An unmatched path serves the Astro 404 page: a real 404, text/html, and
  # never a redirect. Its body's beacon assertion stays here rather than in
  # the route enumeration below: the built 404.html is served only for
  # unmatched paths (it is excluded from the enumeration), so this URL is
  # how a browser actually receives that page.
  problems="${problems}$(expect_status "$notfound" 404 "$NOTFOUND_URL")"
  problems="${problems}$(expect_header_prefix "$notfound" content-type text/html "$NOTFOUND_URL")"
  problems="${problems}$(expect_header_absent "$notfound" location "$NOTFOUND_URL")"
  problems="${problems}$(expect_body_without_cf_beacon "$notfound_body" "$NOTFOUND_URL")"

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
    echo "Site deploy smoke check passed for '$BASE_URL' (home page headers, AASA, /invite, /privacy, /support/, 404, /fhir reservation, and a 200-HTML beacon-free check over every HTML route of the built site)."
    exit 0
  fi

  if [ "$attempt" -ge "$ATTEMPTS" ]; then
    fail "site deploy smoke check failed for '$BASE_URL' after $attempt attempt(s): $reason"
  fi

  echo "Live origin not ready (attempt $attempt/$ATTEMPTS): $reason"
  sleep "$RETRY_DELAY"
  attempt=$((attempt + 1))
done
