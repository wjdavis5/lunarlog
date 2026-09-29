#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-links-deploy.sh (issues #1090, #1099,
# #1157), plus wiring assertions that site-deploy.yml runs it after the deploy,
# that site.yml carries the site PR jobs and the weekly external link check,
# and that ci.yml's release-guards job runs this suite. Run with:
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

# make_fixtures DIR -- a settled, correct set of live response header and
# body dumps. The HTML routes carry .body fixtures for issue #1139's beacon
# assertion; the JSON routes are never body-checked.
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
  cat >"$dir/home.body" <<'EOF'
<!DOCTYPE html><html><head><title>lunarlog</title></head><body><h1>lunarlog</h1><p>Private by default.</p></body></html>
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
  cat >"$dir/invite.body" <<'EOF'
<!DOCTYPE html><html><body>Join a lunarlog profile</body></html>
EOF
  cat >"$dir/privacy.headers" <<'EOF'
HTTP/2 307
date: Fri, 26 Sep 2026 12:00:00 GMT
location: /privacy/
EOF
  cat >"$dir/privacy-slash.headers" <<'EOF'
HTTP/2 200
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
EOF
  cat >"$dir/privacy-slash.body" <<'EOF'
<!DOCTYPE html><html><body><h1>Privacy policy</h1></body></html>
EOF
  cat >"$dir/support.headers" <<'EOF'
HTTP/2 200
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
EOF
  cat >"$dir/support.body" <<'EOF'
<!DOCTYPE html><html><body><h1>Support</h1><p>No ads, no trackers, no analytics on this site.</p></body></html>
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
  cat >"$dir/notfound.body" <<'EOF'
<!DOCTYPE html><html><body><h1>404</h1></body></html>
EOF
  cat >"$dir/fhir.headers" <<'EOF'
HTTP/2 404
date: Fri, 26 Sep 2026 12:00:00 GMT
content-type: text/plain; charset=utf-8
x-content-type-options: nosniff
EOF
}

# run_case DIR [SCRIPT] -- populates $LAST_EXIT and $LAST_LOG. SCRIPT
# defaults to the check under test; the beacon-arming cases pass a sed-flipped
# copy (issue #1139's one-line arming constant) to prove both modes.
run_case() {
  local dir="$1" script="${2:-$SCRIPT}"
  local logfile
  logfile="$(mktemp)"
  set +e
  LINKS_FIXTURES_DIR="$dir" bash "$script" >"$logfile" 2>&1
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

# --- The store privacy URL fails closed (issue #1157) ------------------------

# The bare URL both stores list. When the privacy page is missing from the
# deploy (the #1157 failure), the auto-trailing-slash hop disappears and
# /privacy is a plain 404.
make_fixtures "$WORK/privacy-404"
cat >"$WORK/privacy-404/privacy.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/privacy-404"
assert_exit "a 404 at /privacy refuses (issue #1157)" 1
assert_contains "the privacy URL is named" "$LAST_LOG" "/privacy"

# The redirect hop must land on the canonical page, not anywhere else.
make_fixtures "$WORK/privacy-elsewhere"
cat >"$WORK/privacy-elsewhere/privacy.headers" <<'EOF'
HTTP/2 307
location: /support/
EOF
run_case "$WORK/privacy-elsewhere"
assert_exit "a /privacy redirect that misses /privacy/ refuses" 1
assert_contains "the privacy redirect target is named" "$LAST_LOG" "/privacy/"

# The page itself must be served once the redirect gets there.
make_fixtures "$WORK/privacy-slash-404"
cat >"$WORK/privacy-slash-404/privacy-slash.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/privacy-slash-404"
assert_exit "a 404 at /privacy/ refuses (the page is missing from the deploy)" 1
assert_contains "the canonical privacy URL is named" "$LAST_LOG" "/privacy/"

# --- The support page fails closed -------------------------------------------

make_fixtures "$WORK/support-404"
cat >"$WORK/support-404/support.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/support-404"
assert_exit "a 404 at /support/ refuses" 1
assert_contains "the support URL is named" "$LAST_LOG" "/support/"

# --- assetlinks must stay a Worker-handled 404 ------------------------------

make_fixtures "$WORK/assetlinks-200"
cat >"$WORK/assetlinks-200/assetlinks.json.headers" <<'EOF'
HTTP/2 200
content-type: application/json
EOF
run_case "$WORK/assetlinks-200"
assert_exit "an assetlinks.json that resolves refuses (Android is deferred)" 1
assert_contains "the assetlinks URL is named" "$LAST_LOG" "assetlinks.json"

# --- Cloudflare's Web Analytics beacon: warn by default, armed = hard fail --

# The injector only fires for browser user-agents, so every live fetch in
# the script presents one; each HTML route's body is then checked. The full
# injected tag below is issue #1139's QA capture, token elided.
make_fixtures "$WORK/home-cf-beacon"
cat >"$WORK/home-cf-beacon/home.body" <<'EOF'
<!DOCTYPE html><html><head><title>lunarlog</title></head><body><h1>lunarlog</h1><script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/v31edd6" integrity="sha512-x" data-cf-beacon='{"version":"2024.11.0","token":"x","r":1,"spa":2}' crossorigin="anonymous"></script></body></html>
EOF

# The arming constant is read out of the script under test, not assumed
# (issue #1186): the docs (docs/web/security-posture.md) promise that
# flipping BEACON_MUST_BE_ABSENT to true is a one-line reviewed commit, so
# the owner's arming commit must not be the commit that turns these suites
# red. The shipped value decides what the live script below is expected to
# do, and both modes are forced into copies of the script so both stay
# proven whichever way the flip was committed. The sed anchors on the
# constant's own line, so a rename or move of the constant leaves the
# extraction empty and fails right here -- the constant cannot silently
# drift.
BEACON_ARMED="$(sed -n 's/^BEACON_MUST_BE_ABSENT=//p' "$SCRIPT")"
case "$BEACON_ARMED" in
  true|false) ;;
  *)
    echo "FAIL: the arming constant must be BEACON_MUST_BE_ABSENT=true or =false on its own line in the script under test (got '$BEACON_ARMED')"
    exit 1
    ;;
esac

# Warn-only mode (BEACON_MUST_BE_ABSENT=false): the injection is inert (the
# CSP blocks the script), so it fails nothing -- the finding is a loud
# ::warning:: naming the marker and the owner decision, and the deploy goes
# green. Proven on a copy forced unarmed, so the warn path keeps coverage
# even after the owner arms the real script (issue #1186).
unarmed_script="$WORK/unarmed-check-links-deploy.sh"
sed 's/^BEACON_MUST_BE_ABSENT=.*/BEACON_MUST_BE_ABSENT=false/' "$SCRIPT" >"$unarmed_script"
run_case "$WORK/home-cf-beacon" "$unarmed_script"
assert_exit "an injected Web Analytics beacon warns but passes while unarmed" 0
assert_contains "the warning is a ::warning:: annotation" "$LAST_LOG" "::warning::"
assert_contains "the warning names the injection" "$LAST_LOG" "Cloudflare Web Analytics beacon"
assert_contains "the warning names the arming constant" "$LAST_LOG" "BEACON_MUST_BE_ABSENT"
assert_contains "the warning names the owner decision (issue #1139)" "$LAST_LOG" "issue #1139"
assert_not_contains "the unarmed pass emits no error annotation" "$LAST_LOG" "::error::"

# Armed mode: the same fixture hard-fails. A copy forced armed whatever the
# shipped value (see the extraction above for the drift guard).
armed_script="$WORK/armed-check-links-deploy.sh"
sed 's/^BEACON_MUST_BE_ABSENT=.*/BEACON_MUST_BE_ABSENT=true/' "$SCRIPT" >"$armed_script"
run_case "$WORK/home-cf-beacon" "$armed_script"
assert_exit "an armed check refuses on the same beacon fixture" 1
assert_contains "the armed failure is an error annotation" "$LAST_LOG" "::error::"
assert_contains "the armed failure names the beacon" "$LAST_LOG" "Cloudflare Web Analytics beacon"
assert_contains "the armed failure names the remediation (issue #1139)" "$LAST_LOG" "issue #1139"

# And the shipped script itself must behave as its own constant declares
# (issue #1186) -- this is the expectation that follows the reviewed flip.
run_case "$WORK/home-cf-beacon"
if [ "$BEACON_ARMED" = "true" ]; then
  assert_exit "the shipped script refuses on the beacon fixture, as its armed constant declares" 1
  assert_contains "the shipped armed failure is an error annotation" "$LAST_LOG" "::error::"
  assert_not_contains "the shipped armed script emits no warning" "$LAST_LOG" "::warning::"
else
  assert_exit "the shipped script warns but passes, as its unarmed constant declares" 0
  assert_contains "the shipped unarmed pass warns" "$LAST_LOG" "::warning::"
  assert_not_contains "the shipped unarmed pass emits no error annotation" "$LAST_LOG" "::error::"
fi

# Arming must not disturb the clean path.
run_case "$WORK/valid" "$armed_script"
assert_exit "an armed check still passes a beacon-free origin" 0
assert_not_contains "the clean armed pass emits no warning" "$LAST_LOG" "::warning::"

# Either marker alone must be caught: the injector's tag shape can change
# on either side (src host vs data attribute). Both proven armed, where the
# catch is a hard failure.
make_fixtures "$WORK/support-cf-src"
cat >"$WORK/support-cf-src/support.body" <<'EOF'
<!DOCTYPE html><html><body><h1>Support</h1><script src="https://static.cloudflareinsights.com/beacon.min.js"></script></body></html>
EOF
run_case "$WORK/support-cf-src" "$armed_script"
assert_exit "a cloudflareinsights script src on /support/ refuses when armed (either marker matches)" 1
assert_contains "the support URL is named" "$LAST_LOG" "/support/"

make_fixtures "$WORK/privacy-slash-cf-attr"
cat >"$WORK/privacy-slash-cf-attr/privacy-slash.body" <<'EOF'
<!DOCTYPE html><html><body><h1>Privacy policy</h1><script data-cf-beacon='{"token":"x"}'></script></body></html>
EOF
run_case "$WORK/privacy-slash-cf-attr" "$armed_script"
assert_exit "a data-cf-beacon attribute on /privacy/ refuses when armed (either marker matches)" 1

# --- Wiring -----------------------------------------------------------------

script_sh="$(cat "$SCRIPT")"
assert_contains "the smoke check presents a browser UA to the live origin (issue #1139)" "$script_sh" '-A "$BROWSER_UA"'
assert_contains "the smoke check asks the origin for HTML (issue #1139)" "$script_sh" "Accept: text/html"
assert_contains "the smoke check body-checks every HTML route (issue #1139)" "$script_sh" "expect_body_without_cf_beacon"
assert_contains "the beacon assertion defaults to warn-only (the owner has not decided)" "$script_sh" "BEACON_MUST_BE_ABSENT=false"
assert_contains "the warn finding is a ::warning:: annotation" "$script_sh" "::warning::"
assert_contains "the smoke check matches the beacon's src host (issue #1139)" "$script_sh" "cloudflareinsights"
assert_contains "the smoke check matches the beacon's data attribute (issue #1139)" "$script_sh" "data-cf-beacon"

site_deploy_yaml="$(cat "$SITE_DEPLOY_WORKFLOW")"
assert_contains "site-deploy.yml runs the post-deploy smoke check" "$site_deploy_yaml" "check-links-deploy.sh"
assert_contains "site-deploy.yml pins the wrangler version that understands run_worker_first + _headers" "$site_deploy_yaml" "wranglerVersion: '4.20.0'"
assert_contains "site-deploy.yml deploys from site/" "$site_deploy_yaml" "workingDirectory: 'site'"
assert_contains "site-deploy.yml installs the site deps" "$site_deploy_yaml" "npm ci"
assert_contains "site-deploy.yml builds the site" "$site_deploy_yaml" "npm run build"
assert_contains "site-deploy.yml caches the site lockfile" "$site_deploy_yaml" "site/package-lock.json"
# Issue #1157: the deploy's screenshot step must force the material_fonts
# re-download (#1158's fix) -- a stale runner SDK cache is what took every
# deploy down and froze the privacy URL at a 404.
assert_contains "site-deploy.yml's screenshot step forces the material_fonts re-download (issue #1158)" "$site_deploy_yaml" "flutter precache --universal --force"

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
# Issue #1157's pre-merge half: the PR workflow runs the same screenshots
# step on the same runner image, so a fonts failure is caught before the
# merge, not on the next deploy.
assert_contains "site.yml renders the app screenshots before the build" "$site_yaml" "npm run screenshots"
assert_contains "site.yml's screenshot step forces the material_fonts re-download" "$site_yaml" "flutter precache --universal --force"

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
