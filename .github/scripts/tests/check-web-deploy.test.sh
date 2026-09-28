#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-web-deploy.sh (issue #1092), plus
# wiring assertions that web-deploy.yml ensures the Pages project exists
# idempotently, runs the smoke check after the upload, and that ci.yml's
# release-guards jobs run this suite. Run with:
#
#   bash .github/scripts/tests/check-web-deploy.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-web-deploy.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

DEPLOY_WORKFLOW="$SCRIPT_DIR/../../workflows/web-deploy.yml"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_fixtures DIR -- a settled, correct set of live response dumps.
make_fixtures() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/root.headers" <<'EOF'
HTTP/2 200
date: Sat, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self' blob:
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
strict-transport-security: max-age=63072000; includeSubDomains; preload
x-robots-tag: noindex
EOF
  cat >"$dir/root.body" <<'EOF'
<!DOCTYPE html><html><head><title>lunarlog</title></head><body><script src="main.dart.js"></script></body></html>
EOF
  cat >"$dir/auth-callback.headers" <<'EOF'
HTTP/2 200
date: Sat, 26 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
EOF
  cat >"$dir/privacy-redirect.headers" <<'EOF'
HTTP/2 301
date: Sat, 26 Sep 2026 12:00:00 GMT
location: https://lunarlog.app/privacy
EOF
  cat >"$dir/flutter-bootstrap.headers" <<'EOF'
HTTP/2 200
date: Sat, 26 Sep 2026 12:00:00 GMT
content-type: application/javascript
EOF
  cat >"$dir/flutter-bootstrap.body" <<'EOF'
var _flutter=window._flutter||{};_flutter.buildConfig = {"engineRevision":"abc","useLocalCanvasKit":true};
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
  WEB_DEPLOY_FIXTURES_DIR="$dir" bash "$script" >"$logfile" 2>&1
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
cat >"$WORK/valid-titlecase/root.headers" <<'EOF'
HTTP/2 200
Content-Type: text/html; charset=utf-8
Content-Security-Policy: default-src 'self'; script-src 'self'
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Strict-Transport-Security: max-age=63072000
X-Robots-Tag: noindex
EOF
run_case "$WORK/valid-titlecase"
assert_exit "title-cased header names still pass" 0

# --- `/` fails closed -------------------------------------------------------

make_fixtures "$WORK/root-404"
cat >"$WORK/root-404/root.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/root-404"
assert_exit "a 404 on / refuses" 1
assert_contains "the root status mismatch is named" "$LAST_LOG" "expected HTTP 200"

make_fixtures "$WORK/root-plain"
cat >"$WORK/root-plain/root.headers" <<'EOF'
HTTP/2 200
content-type: text/plain; charset=utf-8
EOF
run_case "$WORK/root-plain"
assert_exit "a non-HTML / refuses" 1
assert_contains "the content-type mismatch is named" "$LAST_LOG" "content-type"

make_fixtures "$WORK/root-no-csp"
cat >"$WORK/root-no-csp/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
strict-transport-security: max-age=63072000
x-robots-tag: noindex
EOF
run_case "$WORK/root-no-csp"
assert_exit "a missing CSP refuses" 1
assert_contains "the missing CSP is named" "$LAST_LOG" "content-security-policy"

make_fixtures "$WORK/root-csp-no-script-self"
cat >"$WORK/root-csp-no-script-self/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; script-src https://cdn.example.com
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
strict-transport-security: max-age=63072000
x-robots-tag: noindex
EOF
run_case "$WORK/root-csp-no-script-self"
assert_exit "a CSP without script-src 'self' refuses" 1
assert_contains "the script-src requirement is named" "$LAST_LOG" "script-src 'self'"

make_fixtures "$WORK/root-coop"
cat >"$WORK/root-coop/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: script-src 'self'
cross-origin-opener-policy: unsafe-none
cross-origin-embedder-policy: require-corp
strict-transport-security: max-age=63072000
x-robots-tag: noindex
EOF
run_case "$WORK/root-coop"
assert_exit "a wrong COOP refuses" 1
assert_contains "the COOP mismatch is named" "$LAST_LOG" "cross-origin-opener-policy"

make_fixtures "$WORK/root-coep"
cat >"$WORK/root-coep/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: script-src 'self'
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: unsafe-none
strict-transport-security: max-age=63072000
x-robots-tag: noindex
EOF
run_case "$WORK/root-coep"
assert_exit "a wrong COEP refuses" 1
assert_contains "the COEP mismatch is named" "$LAST_LOG" "cross-origin-embedder-policy"

make_fixtures "$WORK/root-no-hsts"
cat >"$WORK/root-no-hsts/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: script-src 'self'
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
x-robots-tag: noindex
EOF
run_case "$WORK/root-no-hsts"
assert_exit "a missing HSTS refuses" 1
assert_contains "the missing HSTS is named" "$LAST_LOG" "strict-transport-security"

make_fixtures "$WORK/root-robots"
cat >"$WORK/root-robots/root.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
content-security-policy: script-src 'self'
cross-origin-opener-policy: same-origin
cross-origin-embedder-policy: require-corp
strict-transport-security: max-age=63072000
x-robots-tag: index, follow
EOF
run_case "$WORK/root-robots"
assert_exit "a non-noindex X-Robots-Tag refuses" 1
assert_contains "the X-Robots-Tag mismatch is named" "$LAST_LOG" "x-robots-tag"

# --- Cloudflare's Web Analytics beacon: warn by default, armed = hard fail --

# The full injected tag, exactly as Cloudflare's edge emits it into HTML for
# browser user-agents (issue #1139's QA capture, token elided).
make_fixtures "$WORK/root-cf-beacon"
cat >"$WORK/root-cf-beacon/root.body" <<'EOF'
<!DOCTYPE html><html><head><title>lunarlog</title></head><body><script type="module" src="https://static.cloudflareinsights.com/beacon.min.js/v31edd6" integrity="sha512-x" data-cf-beacon='{"version":"2024.11.0","token":"x","r":1,"spa":2}' crossorigin="anonymous"></script></body></html>
EOF

# Warn-only default (BEACON_MUST_BE_ABSENT=false at the top of the script):
# the injection is inert (the CSP blocks the script), so it fails nothing --
# the finding is a loud ::warning:: naming the marker and the owner
# decision, and the deploy goes green.
run_case "$WORK/root-cf-beacon"
assert_exit "an injected Web Analytics beacon warns but passes while unarmed" 0
assert_contains "the warning is a ::warning:: annotation" "$LAST_LOG" "::warning::"
assert_contains "the warning names the injection" "$LAST_LOG" "Cloudflare Web Analytics beacon"
assert_contains "the warning names the arming constant" "$LAST_LOG" "BEACON_MUST_BE_ABSENT"
assert_contains "the warning names the owner decision (issue #1139)" "$LAST_LOG" "issue #1139"
assert_not_contains "the unarmed pass emits no error annotation" "$LAST_LOG" "::error::"

# Armed mode: the same fixture hard-fails. The armed script is the original
# with only the arming constant's line flipped -- proving the flip is one
# tested line (a rename or move of the constant makes this sed a no-op and
# this case fails, so the constant cannot silently drift).
armed_script="$WORK/armed-check-web-deploy.sh"
sed 's/^BEACON_MUST_BE_ABSENT=false$/BEACON_MUST_BE_ABSENT=true/' "$SCRIPT" >"$armed_script"
run_case "$WORK/root-cf-beacon" "$armed_script"
assert_exit "an armed check refuses on the same beacon fixture" 1
assert_contains "the armed failure is an error annotation" "$LAST_LOG" "::error::"
assert_contains "the armed failure names the beacon" "$LAST_LOG" "Cloudflare Web Analytics beacon"
assert_contains "the armed failure names the remediation (issue #1139)" "$LAST_LOG" "issue #1139"

# Arming must not disturb the clean path.
run_case "$WORK/valid" "$armed_script"
assert_exit "an armed check still passes a beacon-free origin" 0
assert_not_contains "the clean armed pass emits no warning" "$LAST_LOG" "::warning::"

# Either marker alone must be caught: the injector's tag shape can change
# on either side (src host vs data attribute). Both proven armed, where the
# catch is a hard failure.
make_fixtures "$WORK/root-cf-insights-src"
cat >"$WORK/root-cf-insights-src/root.body" <<'EOF'
<!DOCTYPE html><html><body><script src="https://static.cloudflareinsights.com/beacon.min.js"></script></body></html>
EOF
run_case "$WORK/root-cf-insights-src" "$armed_script"
assert_exit "a cloudflareinsights script src alone refuses when armed (either marker matches)" 1

make_fixtures "$WORK/root-cf-attr"
cat >"$WORK/root-cf-attr/root.body" <<'EOF'
<!DOCTYPE html><html><body><script data-cf-beacon='{"token":"x"}'></script></body></html>
EOF
run_case "$WORK/root-cf-attr" "$armed_script"
assert_exit "a data-cf-beacon attribute alone refuses when armed (either marker matches)" 1

# --- `/auth/callback` fails closed ------------------------------------------

make_fixtures "$WORK/callback-404"
cat >"$WORK/callback-404/auth-callback.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/callback-404"
assert_exit "a 404 on /auth/callback refuses (the SPA fallback is missing)" 1
assert_contains "the callback URL is named" "$LAST_LOG" "/auth/callback"

make_fixtures "$WORK/callback-plain"
cat >"$WORK/callback-plain/auth-callback.headers" <<'EOF'
HTTP/2 200
content-type: text/plain; charset=utf-8
EOF
run_case "$WORK/callback-plain"
assert_exit "a non-HTML /auth/callback refuses" 1

# --- `flutter_bootstrap.js` fails closed ------------------------------------

make_fixtures "$WORK/bootstrap-404"
cat >"$WORK/bootstrap-404/flutter-bootstrap.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/bootstrap-404"
assert_exit "a 404 on flutter_bootstrap.js refuses" 1
assert_contains "the bootstrap URL is named" "$LAST_LOG" "/flutter_bootstrap.js"

make_fixtures "$WORK/bootstrap-cdn"
cat >"$WORK/bootstrap-cdn/flutter-bootstrap.body" <<'EOF'
var _flutter=window._flutter||{};_flutter.buildConfig = {"engineRevision":"abc"};
EOF
run_case "$WORK/bootstrap-cdn"
assert_exit "a bootstrap without useLocalCanvasKit refuses" 1
assert_contains "the CanvasKit requirement is named" "$LAST_LOG" "useLocalCanvasKit"

# --- `/privacy.html` fails closed (issue #1101) ------------------------------

make_fixtures "$WORK/privacy-404"
cat >"$WORK/privacy-404/privacy-redirect.headers" <<'EOF'
HTTP/2 404
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/privacy-404"
assert_exit "a 404 on /privacy.html refuses (the retired copy must redirect)" 1
assert_contains "the privacy URL is named" "$LAST_LOG" "/privacy.html"
assert_contains "the privacy status mismatch is named" "$LAST_LOG" "expected HTTP 301"

make_fixtures "$WORK/privacy-spa-fallback"
cat >"$WORK/privacy-spa-fallback/privacy-redirect.headers" <<'EOF'
HTTP/2 200
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/privacy-spa-fallback"
assert_exit "the SPA fallback swallowing /privacy.html with a 200 refuses" 1

make_fixtures "$WORK/privacy-wrong-target"
cat >"$WORK/privacy-wrong-target/privacy-redirect.headers" <<'EOF'
HTTP/2 301
location: https://github.com/wjdavis5/lunarlog/blob/main/PRIVACY.md
EOF
run_case "$WORK/privacy-wrong-target"
assert_exit "a 301 to any URL but the canonical policy refuses" 1
assert_contains "the canonical target is named" "$LAST_LOG" "https://lunarlog.app/privacy"

# --- Wiring -----------------------------------------------------------------

script_sh="$(cat "$SCRIPT")"
assert_contains "the smoke check presents a browser UA to the live origin (issue #1139)" "$script_sh" '-A "$BROWSER_UA"'
assert_contains "the smoke check asks the origin for HTML (issue #1139)" "$script_sh" "Accept: text/html"
assert_contains "the beacon assertion defaults to warn-only (the owner has not decided)" "$script_sh" "BEACON_MUST_BE_ABSENT=false"
assert_contains "the warn finding is a ::warning:: annotation" "$script_sh" "::warning::"
assert_contains "the smoke check matches the beacon's src host (issue #1139)" "$script_sh" "cloudflareinsights"
assert_contains "the smoke check matches the beacon's data attribute (issue #1139)" "$script_sh" "data-cf-beacon"

deploy_yaml="$(cat "$DEPLOY_WORKFLOW")"

assert_contains "web-deploy.yml runs the post-deploy smoke check" "$deploy_yaml" "check-web-deploy.sh"
assert_contains "web-deploy.yml creates the Pages project idempotently" "$deploy_yaml" "pages project create"
assert_contains "web-deploy.yml creates the production branch 'main'" "$deploy_yaml" "--production-branch=main"
assert_contains "web-deploy.yml treats 'already exists' as success" "$deploy_yaml" "already exists"
assert_contains "web-deploy.yml ensures the project with the pinned wrangler" "$deploy_yaml" "wrangler@3.89.0"
assert_contains "web-deploy.yml still deploys with the pinned wrangler action" "$deploy_yaml" "cloudflare/wrangler-action@ebbaa1584979971c8614a24965b4405ff95890e0"

ci_yaml="$(cat "$CI_WORKFLOW")"
assert_contains "ci.yml release-guards runs this suite" "$ci_yaml" "bash .github/scripts/tests/check-web-deploy.test.sh"
web_deploy_test_runs="$(grep -c 'check-web-deploy.test.sh' "$CI_WORKFLOW" || true)"
assert_eq "ci.yml runs this suite in both release-guards jobs" 2 "$web_deploy_test_runs"

print_summary "check-web-deploy.test.sh"
