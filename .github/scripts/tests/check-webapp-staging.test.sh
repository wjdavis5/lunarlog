#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-webapp-staging.sh (issue #1249), plus
# wiring assertions: webapp-deploy.yml runs the check after the deploy, ci.yml
# runs this suite in both release-guards jobs, and — the issue's acceptance
# criterion — the web CI job is NOT part of the store release gate's
# REQUIRED_CHECKS nor of the ruleset rollup's needs list. Run with:
#
#   bash .github/scripts/tests/check-webapp-staging.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-webapp-staging.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

DEPLOY_WORKFLOW="$SCRIPT_DIR/../../workflows/webapp-deploy.yml"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"
CI_GATE_SCRIPT="$SCRIPT_DIR/../check-ci-gate.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_fixtures DIR -- a settled, correct set of live response dumps (the
# CSP is the one webapp/worker/headers.ts declares).
make_fixtures() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/root.headers" <<'EOF'
HTTP/2 200
date: Wed, 30 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
content-security-policy: default-src 'self'; base-uri 'self'; connect-src 'self' https://dleexnnevuuddcgcpztq.supabase.co wss://dleexnnevuuddcgcpztq.supabase.co; font-src 'self'; form-action 'self'; frame-ancestors 'none'; img-src 'self'; manifest-src 'self'; object-src 'none'; script-src 'self'; style-src 'self'; upgrade-insecure-requests; require-trusted-types-for 'script'
strict-transport-security: max-age=63072000; includeSubDomains; preload
cross-origin-opener-policy: same-origin
x-frame-options: DENY
x-content-type-options: nosniff
referrer-policy: no-referrer
x-robots-tag: noindex
EOF
  cat >"$dir/root.body" <<'EOF'
<!doctype html><html lang="en"><head><meta charset="UTF-8"/><title>lunarlog</title><script type="module" crossorigin src="/assets/index-Bl8pzdv5.js"></script></head><body><div id="root"></div></body></html>
EOF
  cat >"$dir/auth-callback.headers" <<'EOF'
HTTP/2 200
date: Wed, 30 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
EOF
  cat >"$dir/auth-callback.body" <<'EOF'
<!doctype html><html lang="en"><head><title>lunarlog</title></head><body><div id="root"></div></body></html>
EOF
  cat >"$dir/auth-session.headers" <<'EOF'
HTTP/2 401
date: Wed, 30 Sep 2026 12:00:00 GMT
content-type: application/json
cache-control: no-store
EOF
  cat >"$dir/auth-session.body" <<'EOF'
{"error":"no_session"}
EOF
  cat >"$dir/privacy-redirect.headers" <<'EOF_X'
HTTP/2 301
date: Wed, 30 Sep 2026 12:00:00 GMT
location: https://lunarlog.app/privacy
content-type: text/plain; charset=utf-8
EOF_X
  cat >"$dir/privacy-redirect.body" <<'EOF_X'
Moved Permanently
EOF_X
  cat >"$dir/flutter-sw.headers" <<'EOF_X'
HTTP/2 200
date: Wed, 30 Sep 2026 12:00:00 GMT
content-type: application/javascript
cache-control: no-store
EOF_X
  cat >"$dir/flutter-sw.body" <<'EOF_X'
self.addEventListener('install', () => self.skipWaiting());
EOF_X
}

# make_retirement_fixtures DIR -- make_fixtures plus the cutover header on
# the shell: Clear-Site-Data carrying "cache" and "storage" but never
# "cookies" (issue #1248).
make_retirement_fixtures() {
  make_fixtures "$1"
  # Append the cutover header (portable: no sed -i, whose BSD form
  # differs, and no backslash-n-in-RHS GNU/BSD difference).
  printf 'clear-site-data: "cache", "storage"
' >>"$1/root.headers"
}

# run_case DIR [SCRIPT] -- populates $LAST_EXIT and $LAST_LOG. SCRIPT
# defaults to the check under test; the beacon-arming cases pass a sed-flipped
# copy to prove both modes (mirroring check-web-deploy.test.sh).
run_case() {
  local dir="$1" script="${2:-$SCRIPT}"
  local logfile
  logfile="$(mktemp)"
  set +e
  WEBAPP_STAGING_FIXTURES_DIR="$dir" bash "$script" >"$logfile" 2>&1
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
assert_exit "a correct staging origin passes" 0
assert_contains "the success line names the base URL-less origin" "$LAST_LOG" "staging smoke check passed"

# --- The required BASE_URL --------------------------------------------------

set +e
WEBAPP_STAGING_FIXTURES_DIR="" bash "$SCRIPT" >"$WORK/no-base-url.log" 2>&1
LAST_EXIT=$?
set -e
LAST_LOG="$(cat "$WORK/no-base-url.log")"
assert_exit "an unset WEBAPP_STAGING_BASE_URL fails closed" 1
assert_contains "the failure names the env var" "$LAST_LOG" "WEBAPP_STAGING_BASE_URL"

# --- The header truth table -------------------------------------------------

# edit_fixture FILE SED_SCRIPT -- in-place edit without `sed -i`, whose BSD
# form (`sed -i ''`, the release-guards-macos job's Bash 3.2/Sed) differs
# from GNU's: the suffix-less `-i` makes BSD treat the script's next word as
# the backup suffix and abort with "invalid command code". Pipe to a temp
# file and move over the original instead — the same shape the other suites
# use for their arming flips.
edit_fixture() {
  local file="$1" script="$2"
  sed "$script" "$file" >"$file.tmp"
  mv "$file.tmp" "$file"
}

make_fixtures "$WORK/no-csp"
grep -v "^content-security-policy:" "$WORK/valid/root.headers" >"$WORK/no-csp/root.headers"
run_case "$WORK/no-csp"
assert_exit "a missing CSP refuses" 1
assert_contains "the missing CSP is named" "$LAST_LOG" "content-security-policy"

make_fixtures "$WORK/unsafe-inline"
edit_fixture "$WORK/unsafe-inline/root.headers" "s/script-src 'self'/script-src 'self' 'unsafe-inline'/"
run_case "$WORK/unsafe-inline"
assert_exit "unsafe-inline in the CSP refuses" 1
assert_contains "the unsafe-inline rejection is named" "$LAST_LOG" "unsafe-inline"

make_fixtures "$WORK/wasm-eval"
edit_fixture "$WORK/wasm-eval/root.headers" "s/script-src 'self'/script-src 'self' 'wasm-unsafe-eval'/"
run_case "$WORK/wasm-eval"
assert_exit "wasm-unsafe-eval in the CSP refuses" 1
assert_contains "the wasm-unsafe-eval rejection is named" "$LAST_LOG" "wasm-unsafe-eval"

make_fixtures "$WORK/no-frame-ancestors"
edit_fixture "$WORK/no-frame-ancestors/root.headers" "s/; frame-ancestors 'none'//"
run_case "$WORK/no-frame-ancestors"
assert_exit "a missing frame-ancestors 'none' refuses" 1
assert_contains "the frame-ancestors requirement is named" "$LAST_LOG" "frame-ancestors 'none'"

make_fixtures "$WORK/no-trusted-types"
edit_fixture "$WORK/no-trusted-types/root.headers" "s/; require-trusted-types-for 'script'//"
run_case "$WORK/no-trusted-types"
assert_exit "a missing require-trusted-types-for refuses" 1
assert_contains "the trusted-types requirement is named" "$LAST_LOG" "require-trusted-types-for"

make_fixtures "$WORK/no-supabase-connect"
edit_fixture "$WORK/no-supabase-connect/root.headers" "s/ https:\/\/dleexnnevuuddcgcpztq.supabase.co wss:\/\/dleexnnevuuddcgcpztq.supabase.co//"
run_case "$WORK/no-supabase-connect"
assert_exit "a connect-src without the Supabase project refuses" 1
assert_contains "the https origin requirement is named" "$LAST_LOG" "https://dleexnnevuuddcgcpztq.supabase.co"

make_fixtures "$WORK/no-wss"
edit_fixture "$WORK/no-wss/root.headers" "s/ wss:\/\/dleexnnevuuddcgcpztq.supabase.co//"
run_case "$WORK/no-wss"
assert_exit "a connect-src without the wss origin refuses" 1
assert_contains "the wss origin requirement is named" "$LAST_LOG" "wss://dleexnnevuuddcgcpztq.supabase.co"

make_fixtures "$WORK/coop"
edit_fixture "$WORK/coop/root.headers" "s/cross-origin-opener-policy: same-origin/cross-origin-opener-policy: unsafe-none/"
run_case "$WORK/coop"
assert_exit "a wrong COOP refuses" 1
assert_contains "the COOP mismatch is named" "$LAST_LOG" "cross-origin-opener-policy"

make_fixtures "$WORK/no-hsts"
grep -v "^strict-transport-security:" "$WORK/valid/root.headers" >"$WORK/no-hsts/root.headers"
run_case "$WORK/no-hsts"
assert_exit "a missing HSTS refuses" 1
assert_contains "the missing HSTS is named" "$LAST_LOG" "strict-transport-security"

make_fixtures "$WORK/robots"
edit_fixture "$WORK/robots/root.headers" "s/x-robots-tag: noindex/x-robots-tag: index, follow/"
run_case "$WORK/robots"
assert_exit "a non-noindex X-Robots-Tag refuses" 1
assert_contains "the X-Robots-Tag mismatch is named" "$LAST_LOG" "x-robots-tag"

make_fixtures "$WORK/empty-shell"
cat >"$WORK/empty-shell/root.body" <<'EOF'
<!doctype html><html lang="en"><head><title>lunarlog</title></head><body><div id="root"></div></body></html>
EOF
run_case "$WORK/empty-shell"
assert_exit "a shell with no module script refuses" 1
assert_contains "the missing module script is named" "$LAST_LOG" "module"

make_fixtures "$WORK/callback-404"
cat >"$WORK/callback-404/auth-callback.headers" <<'EOF'
HTTP/2 404
date: Wed, 30 Sep 2026 12:00:00 GMT
content-type: text/html; charset=utf-8
EOF
run_case "$WORK/callback-404"
assert_exit "a 404 on /auth/callback refuses" 1
assert_contains "the callback failure is named" "$LAST_LOG" "/auth/callback?code=smoke"

# --- The /auth/session probe (issue #1280) ----------------------------------

make_fixtures "$WORK/session-500"
edit_fixture "$WORK/session-500/auth-session.headers" "s|^HTTP/2 401$|HTTP/2 500|"
run_case "$WORK/session-500"
assert_exit "a 500 on /auth/session refuses (the ctx-as-deps symptom)" 1
assert_contains "the session failure is named" "$LAST_LOG" "/auth/session"

make_fixtures "$WORK/session-200"
edit_fixture "$WORK/session-200/auth-session.headers" "s|^HTTP/2 401$|HTTP/2 200|"
run_case "$WORK/session-200"
assert_exit "a 200 on /auth/session refuses (signed-out must be exactly 401)" 1
assert_contains "the session failure is named" "$LAST_LOG" "/auth/session"

# --- The beacon: warn by default, armed = hard fail -------------------------

make_fixtures "$WORK/beacon"
cat >"$WORK/beacon/root.body" <<'EOF'
<!DOCTYPE html><html><head><title>lunarlog</title></head><body><script type="module" src="/assets/index.js"></script><script src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='{"token":"x"}'></script></body></html>
EOF

run_case "$WORK/beacon"
assert_exit "the injected beacon warns but passes while disarmed" 0
assert_contains "the beacon finding is printed" "$LAST_LOG" "Web Analytics beacon"
assert_contains "the warning names the arming constant" "$LAST_LOG" "BEACON_MUST_BE_ABSENT"

ARMED_SCRIPT="$WORK/check-webapp-staging-armed.sh"
sed "s/^BEACON_MUST_BE_ABSENT=false$/BEACON_MUST_BE_ABSENT=true/" "$SCRIPT" >"$ARMED_SCRIPT"
run_case "$WORK/beacon" "$ARMED_SCRIPT"
assert_exit "the armed beacon hard-fails" 1
assert_contains "the armed failure names the beacon" "$LAST_LOG" "Web Analytics beacon"

# The arming constant must stay extractable (issue #1186's discipline): if
# the sed above stopped matching, the armed case silently tested nothing.
grep -q "^BEACON_MUST_BE_ABSENT=" "$SCRIPT" || {
  echo "FAIL: BEACON_MUST_BE_ABSENT constant missing from the script under test"
  fail=$((fail + 1))
}

# --- Wiring -----------------------------------------------------------------

DEPLOY_WF="$(cat "$DEPLOY_WORKFLOW")"
assert_contains "webapp-deploy.yml exists and runs the check" "$DEPLOY_WF" "check-webapp-staging.sh"
# Issue #1405: the cutover has landed (app.lunarlog.app serves the Worker),
# so the one-shot probe and retirement steps are deleted, not gated. Either
# one coming back must fail this suite.
assert_not_contains "the one-shot retirement step stays deleted" "$DEPLOY_WF" "Retire the Flutter Pages project"
assert_not_contains "the cutover probe step stays deleted" "$DEPLOY_WF" "steps.cutover.outputs.done"
assert_contains "the deploy passes the resolved staging URL" "$DEPLOY_WF" "WEBAPP_STAGING_BASE_URL"
assert_contains "the deploy is gated on the Cloudflare credentials" "$DEPLOY_WF" "CLOUDFLARE_API_TOKEN"
assert_contains "the deploy builds with the Supabase defines" "$DEPLOY_WF" "VITE_SUPABASE_URL"
assert_contains "the deploy is workers-dev staging (no custom domain)" "$DEPLOY_WF" "workers_dev"

CI="$(cat "$CI_WORKFLOW")"
assert_contains "ci.yml runs this suite (ubuntu release-guards)" "$CI" "check-webapp-staging.test.sh"
assert_contains "ci.yml has a webapp job" "$CI" "name: Web app (lint, typecheck, unit, build, e2e)"
assert_contains "the webapp job is path-gated on the detect-changes output" "$CI" "outputs.webapp"
assert_contains "the webapp job runs the Playwright suite" "$CI" "npm run e2e"
assert_contains "the webapp job pins Node" "$CI" "node-version: '22'"

# The /auth/session probe must stay in the check under test itself: if the
# path ever stops matching fixture_path's session branch above, the two
# truth-table cases would silently test the root fixtures instead.
assert_contains "the check probes /auth/session (issue #1280)" "$(cat "$SCRIPT")" 'SESSION_URL="$BASE_URL/auth/session"'

# Issue #1249's acceptance criterion: the web CI job must NOT be a required
# check of the store release gate, and must not gate the ruleset rollup
# either (a path-filtered job in the rollup would fail every docs-only PR
# with a "skipped" dependency).
CI_GATE="$(cat "$CI_GATE_SCRIPT")"
assert_contains "check-ci-gate.sh's REQUIRED_CHECKS carries the webapp job (promoted at the #1258 launch)" "$CI_GATE" "Web app (lint, typecheck, unit, build, e2e)"
assert_contains "the ruleset rollup's needs carries webapp (#1258 launch promotion)" "$CI" "      - webapp"

# --- The #1258 cutover retirement duties ------------------------------------

make_retirement_fixtures "$WORK/retire-valid"
WEBAPP_CHECK_RETIREMENT=1 run_case "$WORK/retire-valid"
assert_exit "a correct cutover origin passes with retirement checks" 0

# The same origin WITHOUT the env: the retirement assertions are skipped
# (staging runs must keep passing without the cutover fixtures).
run_case "$WORK/valid"
assert_exit "staging runs skip the retirement assertions" 0

# Missing clear-site-data on the shell refuses.
make_retirement_fixtures "$WORK/retire-no-csd"
edit_fixture "$WORK/retire-no-csd/root.headers" '/^clear-site-data:/d'
WEBAPP_CHECK_RETIREMENT=1 run_case "$WORK/retire-no-csd"
assert_exit "a shell without clear-site-data refuses under retirement checks" 1
assert_contains "the missing clear-site-data is named" "$LAST_LOG" "clear-site-data"

# clear-site-data including cookies refuses (it would sign every page load out).
make_retirement_fixtures "$WORK/retire-cookies"
edit_fixture "$WORK/retire-cookies/root.headers" 's|^clear-site-data:.*|clear-site-data: "cache", "cookies", "storage"|'
WEBAPP_CHECK_RETIREMENT=1 run_case "$WORK/retire-cookies"
assert_exit "clear-site-data including cookies refuses" 1
assert_contains "the cookies danger is named" "$LAST_LOG" "cookies"

# A privacy.html that 200s instead of 301ing refuses.
make_retirement_fixtures "$WORK/retire-privacy-200"
edit_fixture "$WORK/retire-privacy-200/privacy-redirect.headers" 's|^HTTP/2 301|HTTP/2 200|'
WEBAPP_CHECK_RETIREMENT=1 run_case "$WORK/retire-privacy-200"
assert_exit "a non-301 privacy.html refuses" 1
assert_contains "the privacy redirect is named" "$LAST_LOG" "privacy.html"

# A missing flutter_service_worker.js refuses.
make_retirement_fixtures "$WORK/retire-no-sw"
rm "$WORK/retire-no-sw/flutter-sw.headers"
WEBAPP_CHECK_RETIREMENT=1 run_case "$WORK/retire-no-sw"
assert_exit "a missing retirement service worker refuses" 1

# Last on purpose: print_summary is what turns a failed case into a non-zero
# exit, so any case placed after it can never fail CI (issue #1394).
print_summary "check-webapp-staging.test.sh"
