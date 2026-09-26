#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-links-deploy.sh (issue #1090), plus
# wiring assertions that links-deploy.yml runs it after the deploy and that
# ci.yml's release-guards job runs this suite. Run with:
#
#   bash .github/scripts/tests/check-links-deploy.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-links-deploy.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

LINKS_DEPLOY_WORKFLOW="$SCRIPT_DIR/../../workflows/links-deploy.yml"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_fixtures DIR -- a settled, correct set of live response header dumps.
make_fixtures() {
  local dir="$1"
  mkdir -p "$dir"
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

links_yaml="$(cat "$LINKS_DEPLOY_WORKFLOW")"
assert_contains "links-deploy.yml runs the post-deploy smoke check" "$links_yaml" "check-links-deploy.sh"
assert_contains "links-deploy.yml pins the wrangler version that understands run_worker_first" "$links_yaml" "wranglerVersion: '4.20.0'"
assert_contains "links-deploy.yml deploys from site/" "$links_yaml" "workingDirectory: 'site'"

ci_yaml="$(cat "$CI_WORKFLOW")"
assert_contains "ci.yml release-guards runs this suite" "$ci_yaml" "bash .github/scripts/tests/check-links-deploy.test.sh"

print_summary "check-links-deploy.test.sh"
