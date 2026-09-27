#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-links-deploy.sh (issues #1090, #1099),
# plus wiring assertions that site-deploy.yml runs it after the deploy, that
# site.yml carries the site PR jobs and the weekly external link check, and
# that ci.yml's release-guards job runs this suite. Run with:
#
#   bash .github/scripts/tests/check-links-deploy.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-links-deploy.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

SITE_DEPLOY_WORKFLOW="$SCRIPT_DIR/../../workflows/site-deploy.yml"
SITE_WORKFLOW="$SCRIPT_DIR/../../workflows/site.yml"
SITE_PACKAGE_JSON="$SCRIPT_DIR/../../../site/package.json"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_fixtures DIR -- a settled, correct set of live response header dumps.
make_fixtures() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/home.headers" <<'EOF'
HTTP/2 200
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; base-uri 'self'; frame-ancestors 'none'; style-src 'self'
strict-transport-security: max-age=63072000; includeSubDomains; preload
x-frame-options: DENY
referrer-policy: no-referrer
x-content-type-options: nosniff
EOF
  cat >"$dir/apple-app-site-association.headers" <<'EOF'
HTTP/2 200
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: application/json; charset=utf-8
cache-control: public, max-age=3600
x-content-type-options: nosniff
EOF
  cat >"$dir/invite.headers" <<'EOF'
HTTP/2 200
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
referrer-policy: no-referrer
x-content-type-options: nosniff
cache-control: public, max-age=300
EOF
  cat >"$dir/assetlinks.json.headers" <<'EOF'
HTTP/2 404
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/plain; charset=utf-8
EOF
  cat >"$dir/notfound.headers" <<'EOF'
HTTP/2 404
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
x-content-type-options: nosniff
EOF
  cat >"$dir/fhir.headers" <<'EOF'
HTTP/2 404
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/plain; charset=utf-8
x-content-type-options: nosniff
EOF
}

# run_case DIR -- populates $LAST_EXIT and $LAST_LOG.
run_case() {
  local dir="$1"
  local logfile
  logfile="$(mktemp)"
  set +e
  LINKS_FIXTURES_DIR="$dir" bash "$SCRIPT" >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# --- The happy path ---------------------------------------------------------

make_fixtures "$WORK/valid"
run_case "$WORK/valid"
assert_exit "a correct live origin passes" 0
assert_not_contains "the pass emits no error annotation" "$LAST_LOG" "::error::"

# Header names are matched case-insensitively (fixtures above are lowercase;
# servers may emit any case).
make_fixtures "$WORK/valid-titlecase"
cat >"$WORK/valid-titlecase/apple-app-site-association.headers" <<'EOF'
HTTP/2 200
Content-Type: application/json; charset=utf-8
X-Content-Type-Options: nosniff
EOF
run_case "$WORK/valid-titlecase"
assert_exit "title-cased header names still pass" 0

# --- The home page's strict headers fail closed -----------------------------

make_fixtures "$WORK/home-redirect"
cat >"$WORK/home-redirect/home.headers" <<'EOF'
HTTP/2 301
location: https://example.com/
content-type: text/html
EOF
run_case "$WORK/home-redirect"
assert_exit "a redirected home page refuses" 1
assert_contains "the home URL is named on a redirect" "$LAST_LOG" "/"

make_fixtures "$WORK/home-no-csp"
cat >"$WORK/home-no-csp/home.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
strict-transport-security: max-age=63072000
x-frame-options: DENY
referrer-policy: no-referrer
x-content-type-options: nosniff
EOF
run_case "$WORK/home-no-csp"
assert_exit "a home page without a CSP refuses" 1
assert_contains "the missing CSP is named" "$LAST_LOG" "content-security-policy"

make_fixtures "$WORK/home-no-hsts"
cat >"$WORK/home-no-hsts/home.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; frame-ancestors 'none'
x-frame-options: DENY
referrer-policy: no-referrer
x-content-type-options: nosniff
EOF
run_case "$WORK/home-no-hsts"
assert_exit "a home page without HSTS refuses" 1
assert_contains "the missing HSTS is named" "$LAST_LOG" "strict-transport-security"

make_fixtures "$WORK/home-no-xfo"
cat >"$WORK/home-no-xfo/home.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; frame-ancestors 'none'
strict-transport-security: max-age=63072000
referrer-policy: no-referrer
x-content-type-options: nosniff
EOF
run_case "$WORK/home-no-xfo"
assert_exit "a home page without X-Frame-Options refuses" 1
assert_contains "the missing X-Frame-Options is named" "$LAST_LOG" "x-frame-options"

# --- The 404 page fails closed ----------------------------------------------

make_fixtures "$WORK/notfound-200"
cat >"$WORK/notfound-200/notfound.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/notfound-200"
assert_exit "an unmatched path that is not a 404 refuses" 1
assert_contains "the not-found URL is named" "$LAST_LOG" "this-page-does-not-exist"

make_fixtures "$WORK/notfound-redirect"
cat >"$WORK/notfound-redirect/notfound.headers" <<'EOF'
HTTP/2 301
location: /
content-type: text/html
EOF
run_case "$WORK/notfound-redirect"
assert_exit "a redirected unmatched path refuses" 1
assert_contains "the 404 location header is named" "$LAST_LOG" "location"

# --- The reserved /fhir/* paths fail closed ---------------------------------

make_fixtures "$WORK/fhir-redirect"
cat >"$WORK/fhir-redirect/fhir.headers" <<'EOF'
HTTP/2 301
location: /fhir/CodeSystem/other
content-type: text/plain
EOF
run_case "$WORK/fhir-redirect"
assert_exit "a redirected /fhir URI refuses (issue #961)" 1
assert_contains "the /fhir location header is named" "$LAST_LOG" "location"

# --- The AASA branch fails closed -------------------------------------------

make_fixtures "$WORK/aasa-redirect"
cat >"$WORK/aasa-redirect/apple-app-site-association.headers" <<'EOF'
HTTP/2 301
location: https://example.com/
content-type: text/html
EOF
run_case "$WORK/aasa-redirect"
assert_exit "a redirected AASA refuses (the status check does not follow it)" 1
assert_contains "the AASA URL is named on a redirect" "$LAST_LOG" "apple-app-site-association"

make_fixtures "$WORK/aasa-octet"
cat >"$WORK/aasa-octet/apple-app-site-association.headers" <<'EOF'
HTTP/2 200
content-type: application/octet-stream
x-content-type-options: nosniff
EOF
run_case "$WORK/aasa-octet"
assert_exit "an octet-stream AASA refuses" 1
assert_contains "the AASA content-type mismatch is named" "$LAST_LOG" "content-type"

make_fixtures "$WORK/aasa-no-nosniff"
cat >"$WORK/aasa-no-nosniff/apple-app-site-association.headers" <<'EOF'
HTTP/2 200
content-type: application/json; charset=utf-8
EOF
run_case "$WORK/aasa-no-nosniff"
assert_exit "an AASA without nosniff refuses" 1
assert_contains "the missing AASA nosniff is named" "$LAST_LOG" "x-content-type-options"

# --- The /invite branch fails closed ----------------------------------------

make_fixtures "$WORK/invite-plain"
cat >"$WORK/invite-plain/invite.headers" <<'EOF'
HTTP/2 200
content-type: text/plain
referrer-policy: no-referrer
x-content-type-options: nosniff
cache-control: public, max-age=300
EOF
run_case "$WORK/invite-plain"
assert_exit "a non-HTML invite refuses" 1
assert_contains "the invite URL is named" "$LAST_LOG" "/invite"

make_fixtures "$WORK/invite-no-referrer"
cat >"$WORK/invite-no-referrer/invite.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
x-content-type-options: nosniff
cache-control: public, max-age=300
EOF
run_case "$WORK/invite-no-referrer"
assert_exit "an invite without Referrer-Policy refuses" 1
assert_contains "the missing Referrer-Policy is named" "$LAST_LOG" "referrer-policy"

make_fixtures "$WORK/invite-cache"
cat >"$WORK/invite-cache/invite.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
referrer-policy: no-referrer
x-content-type-options: nosniff
cache-control: public, max-age=0, must-revalidate
EOF
run_case "$WORK/invite-cache"
assert_exit "the static-asset cache header on /invite refuses" 1
assert_contains "the cache-control mismatch is named" "$LAST_LOG" "cache-control"

# --- assetlinks must stay a Worker-handled 404 ------------------------------

make_fixtures "$WORK/assetlinks-200"
cat >"$WORK/assetlinks-200/assetlinks.json.headers" <<'EOF'
HTTP/2 200
content-type: application/json
EOF
run_case "$WORK/assetlinks-200"
assert_exit "an assetlinks.json that resolves refuses (Android is deferred)" 1
assert_contains "the assetlinks URL is named" "$LAST_LOG" "assetlinks.json"

# --- Wiring -----------------------------------------------------------------

site_deploy_yaml="$(cat "$SITE_DEPLOY_WORKFLOW")"
assert_contains "site-deploy.yml runs the post-deploy smoke check" "$site_deploy_yaml" "check-links-deploy.sh"
assert_contains "site-deploy.yml pins the wrangler version that understands run_worker_first + _headers" "$site_deploy_yaml" "wranglerVersion: '4.20.0'"
assert_contains "site-deploy.yml deploys from site/" "$site_deploy_yaml" "workingDirectory: 'site'"
assert_contains "site-deploy.yml installs the site deps" "$site_deploy_yaml" "npm ci"
assert_contains "site-deploy.yml builds the site" "$site_deploy_yaml" "npm run build"
assert_contains "site-deploy.yml caches the site lockfile" "$site_deploy_yaml" "site/package-lock.json"

site_yaml="$(cat "$SITE_WORKFLOW")"
assert_contains "site.yml is path-filtered to site/**" "$site_yaml" "site/**"
assert_contains "site.yml is path-filtered to PRIVACY.md" "$site_yaml" "PRIVACY.md"
assert_contains "site.yml is path-filtered to the literacy export" "$site_yaml" "lib/domain/content/**"
assert_contains "site.yml is path-filtered to the app labels" "$site_yaml" "lib/l10n/app_en.arb"
assert_contains "site.yml runs the site build (astro check + build)" "$site_yaml" "npm run build"
assert_contains "site.yml runs the internal link / off-origin check" "$site_yaml" "check:links"
assert_contains "site.yml validates the built HTML" "$site_yaml" "check:html"
assert_contains "site.yml runs the Lighthouse budgets" "$site_yaml" "check:lighthouse"
assert_contains "site.yml runs axe" "$site_yaml" "check:axe"
assert_contains "site.yml has the weekly external link check" "$site_yaml" "check:external-links"
assert_contains "site.yml is scheduled weekly" "$site_yaml" "schedule:"

site_package="$(cat "$SITE_PACKAGE_JSON")"
assert_contains "site/package.json pins Astro exactly" "$site_package" '"astro": "7.3.5"'
assert_contains "site/package.json pins @lhci/cli exactly" "$site_package" '"@lhci/cli": "0.15.1"'
assert_contains "site/package.json pins axe-core exactly" "$site_package" '"axe-core": "4.13.0"'
assert_contains "the build script runs astro check" "$site_package" "astro check"

site_headers="$(cat "$SCRIPT_DIR/../../../site/public/_headers")"
assert_contains "site/_headers carries the strict CSP" "$site_headers" "default-src 'self'"
assert_not_contains "site/_headers forbids inline styles/scripts" "$site_headers" "unsafe-inline"
assert_contains "site/_headers sends HSTS" "$site_headers" "Strict-Transport-Security:"
assert_contains "site/_headers denies framing" "$site_headers" "X-Frame-Options: DENY"
assert_contains "site/_headers sets a deny-by-default Permissions-Policy" "$site_headers" "Permissions-Policy:"
assert_contains "site.yml verifies _headers survives the build" "$site_yaml" "dist/_headers"

ci_yaml="$(cat "$CI_WORKFLOW")"
assert_contains "ci.yml release-guards runs this suite" "$ci_yaml" "bash .github/scripts/tests/check-links-deploy.test.sh"
assert_not_contains "ci.yml does not pull the site workflow into its required checks" "$ci_yaml" "site.yml"

print_summary "check-links-deploy.test.sh"
