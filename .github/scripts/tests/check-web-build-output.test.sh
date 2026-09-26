#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-web-build-output.sh (epic #831,
# slice 3), plus wiring assertions that web-deploy.yml actually builds the
# sync web app, runs this check before deploying, passes the same defines
# ci.yml passes, and gates the Cloudflare upload on the two secrets. Run
# with:
#
#   bash .github/scripts/tests/check-web-build-output.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-web-build-output.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

DEPLOY_WORKFLOW="$SCRIPT_DIR/../../workflows/web-deploy.yml"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# make_build_dir DIR -- a minimal but valid deployable output.
make_build_dir() {
  local dir="$1"
  mkdir -p "$dir"
  printf '<!doctype html><title>lunarlog</title>\n' >"$dir/index.html"
  printf '// compiled app bundle\n' >"$dir/main.dart.js"
  cat >"$dir/_headers" <<'EOF'
/*
  Content-Security-Policy: default-src 'self'
EOF
  printf '/* /index.html 200\n' >"$dir/_redirects"
  # Issue #1091: a bootable build resolves CanvasKit locally.
  printf 'var _flutter=window._flutter||{};_flutter.buildConfig = {"engineRevision":"abc","useLocalCanvasKit":true};\n' \
    >"$dir/flutter_bootstrap.js"
}

# run_case DIR -- populates $LAST_EXIT and $LAST_LOG.
run_case() {
  local dir="$1"
  local logfile
  logfile="$(mktemp)"
  set +e
  WEB_BUILD_DIR="$dir" bash "$SCRIPT" >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# --- The happy path ---------------------------------------------------------

make_build_dir "$WORK/valid"
run_case "$WORK/valid"
assert_exit "a complete build output passes" 0
assert_not_contains "the pass emits no error annotation" "$LAST_LOG" "::error::"

# --- Each missing piece fails closed, naming the piece ----------------------

run_case "$WORK/does-not-exist"
assert_exit "a missing output directory refuses" 1
assert_contains "the missing directory is named" "$LAST_LOG" "does-not-exist"

make_build_dir "$WORK/no-index"
rm "$WORK/no-index/index.html"
run_case "$WORK/no-index"
assert_exit "missing index.html refuses" 1
assert_contains "index.html is named" "$LAST_LOG" "index.html"

make_build_dir "$WORK/no-bundle"
rm "$WORK/no-bundle/main.dart.js"
run_case "$WORK/no-bundle"
assert_exit "missing main.dart.js refuses" 1
assert_contains "main.dart.js is named" "$LAST_LOG" "main.dart.js"

make_build_dir "$WORK/no-headers"
rm "$WORK/no-headers/_headers"
run_case "$WORK/no-headers"
assert_exit "missing _headers refuses (fail closed on a missing CSP)" 1
assert_contains "_headers is named" "$LAST_LOG" "_headers"

make_build_dir "$WORK/no-redirects"
rm "$WORK/no-redirects/_redirects"
run_case "$WORK/no-redirects"
assert_exit "missing _redirects refuses (fail closed on 404ing deep links)" 1
assert_contains "_redirects is named" "$LAST_LOG" "_redirects"

make_build_dir "$WORK/empty-headers"
: >"$WORK/empty-headers/_headers"
run_case "$WORK/empty-headers"
assert_exit "a zero-byte _headers refuses" 1

make_build_dir "$WORK/no-csp"
printf '/*\n  X-Frame-Options: DENY\n' >"$WORK/no-csp/_headers"
run_case "$WORK/no-csp"
assert_exit "_headers without a CSP refuses" 1
assert_contains "the missing CSP is named" "$LAST_LOG" "Content-Security-Policy"

make_build_dir "$WORK/no-fallback"
printf '# no catch-all\n' >"$WORK/no-fallback/_redirects"
run_case "$WORK/no-fallback"
assert_exit "_redirects without the catch-all refuses" 1
assert_contains "the expected catch-all is named" "$LAST_LOG" "index.html 200"

make_build_dir "$WORK/wrong-status"
printf '/* /index.html 302\n' >"$WORK/wrong-status/_redirects"
run_case "$WORK/wrong-status"
assert_exit "a 302 fallback (a redirect, not a rewrite) refuses" 1

# --- Local CanvasKit (issue #1091) ------------------------------------------

make_build_dir "$WORK/no-bootstrap"
rm "$WORK/no-bootstrap/flutter_bootstrap.js"
run_case "$WORK/no-bootstrap"
assert_exit "missing flutter_bootstrap.js refuses (fail closed on a blank page)" 1
assert_contains "flutter_bootstrap.js is named" "$LAST_LOG" "flutter_bootstrap.js"

make_build_dir "$WORK/no-canvaskit"
printf 'var _flutter=window._flutter||{};_flutter.buildConfig = {"engineRevision":"abc"};\n' \
  >"$WORK/no-canvaskit/flutter_bootstrap.js"
run_case "$WORK/no-canvaskit"
assert_exit "a bootstrap without useLocalCanvasKit refuses" 1
assert_contains "the CanvasKit requirement is named" "$LAST_LOG" "useLocalCanvasKit"

make_build_dir "$WORK/local-canvaskit"
run_case "$WORK/local-canvaskit"
assert_exit "a bootstrap setting useLocalCanvasKit:true passes" 0

# --- Wiring: the deploy workflow actually uses the check and the secrets ----

deploy_yaml="$(cat "$DEPLOY_WORKFLOW")"

assert_contains "web-deploy.yml runs the build-output check" "$deploy_yaml" "check-web-build-output.sh"
assert_contains "web-deploy.yml builds the sync web app" "$deploy_yaml" '--dart-define=LUNARLOG_WEB_SYNC=true'
assert_contains "web-deploy.yml pins the Flutter version from FLUTTER_VERSION" "$deploy_yaml" 'flutter-version: ${{ env.FLUTTER_VERSION }}'
assert_contains "web-deploy.yml pins FLUTTER_VERSION to 3.47.2" "$deploy_yaml" "FLUTTER_VERSION: '3.47.2'"
assert_contains "web-deploy.yml passes SUPABASE_URL" "$deploy_yaml" '--dart-define=SUPABASE_URL="$SUPABASE_URL"'
assert_contains "web-deploy.yml passes SUPABASE_PUBLISHABLE_KEY" "$deploy_yaml" '--dart-define=SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY"'
assert_contains "web-deploy.yml passes SENTRY_DSN" "$deploy_yaml" '--dart-define=SENTRY_DSN="$SENTRY_DSN"'
assert_contains "web-deploy.yml passes GOOGLE_IOS_CLIENT_ID" "$deploy_yaml" '--dart-define=GOOGLE_IOS_CLIENT_ID="$GOOGLE_IOS_CLIENT_ID"'
assert_contains "web-deploy.yml passes GOOGLE_WEB_CLIENT_ID" "$deploy_yaml" '--dart-define=GOOGLE_WEB_CLIENT_ID="$GOOGLE_WEB_CLIENT_ID"'
assert_contains "web-deploy.yml passes FCM_PROJECT_ID" "$deploy_yaml" '--dart-define=FCM_PROJECT_ID="$FCM_PROJECT_ID"'
assert_contains "web-deploy.yml passes FCM_SENDER_ID" "$deploy_yaml" '--dart-define=FCM_SENDER_ID="$FCM_SENDER_ID"'
assert_contains "web-deploy.yml passes FCM_ANDROID_API_KEY" "$deploy_yaml" '--dart-define=FCM_ANDROID_API_KEY="$FCM_ANDROID_API_KEY"'
assert_contains "web-deploy.yml passes FCM_ANDROID_APP_ID" "$deploy_yaml" '--dart-define=FCM_ANDROID_APP_ID="$FCM_ANDROID_APP_ID"'
assert_contains "web-deploy.yml passes FCM_IOS_API_KEY" "$deploy_yaml" '--dart-define=FCM_IOS_API_KEY="$FCM_IOS_API_KEY"'
assert_contains "web-deploy.yml passes FCM_IOS_APP_ID" "$deploy_yaml" '--dart-define=FCM_IOS_APP_ID="$FCM_IOS_APP_ID"'
assert_contains "web-deploy.yml deploys with the pinned wrangler action" "$deploy_yaml" "cloudflare/wrangler-action@ebbaa1584979971c8614a24965b4405ff95890e0"
assert_contains "web-deploy.yml targets the lunarlog-app Pages project" "$deploy_yaml" "pages deploy build/web --project-name=lunarlog-app"
assert_contains "web-deploy.yml reads CLOUDFLARE_API_TOKEN" "$deploy_yaml" "CLOUDFLARE_API_TOKEN"
assert_contains "web-deploy.yml reads CLOUDFLARE_ACCOUNT_ID" "$deploy_yaml" "CLOUDFLARE_ACCOUNT_ID"
assert_contains "web-deploy.yml warns-and-skips without the secrets" "$deploy_yaml" "::warning::"
assert_not_contains "the deploy step cannot fail the run on a missing secret" "$deploy_yaml" "exit 1"

ci_yaml="$(cat "$CI_WORKFLOW")"
assert_contains "ci.yml release-guards runs this suite" "$ci_yaml" "bash .github/scripts/tests/check-web-build-output.test.sh"

# --- Issue #1091: local CanvasKit and the headless boot check ---------------

assert_contains "web-deploy.yml builds with local CanvasKit" "$deploy_yaml" "--no-web-resources-cdn"
assert_contains "ci.yml builds with local CanvasKit" "$ci_yaml" "--no-web-resources-cdn"
assert_contains "ci.yml runs the deployability check" "$ci_yaml" "check-web-build-output.sh"
assert_contains "web-deploy.yml runs the headless boot check" "$deploy_yaml" "tool/web_smoke"
assert_contains "ci.yml runs the headless boot check" "$ci_yaml" "tool/web_smoke"

print_summary "check-web-build-output.test.sh"
