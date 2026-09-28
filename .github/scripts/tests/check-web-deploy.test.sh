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

# run_case DIR -- populates $LAST_EXIT and $LAST_LOG.
run_case() {
  local dir="$1"
  local logfile
  logfile="$(mktemp)"
  set +e
  WEB_DEPLOY_FIXTURES_DIR="$dir" bash "$SCRIPT" >"$logfile" 2>&1
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
