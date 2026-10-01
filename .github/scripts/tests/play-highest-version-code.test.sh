#!/usr/bin/env bash
set -euo pipefail

# Truth table + offline end-to-end proof for
# .github/scripts/play-highest-version-code.rb (issue #1302) -- the Play
# twin of PR #1260's asc-highest-build.rb clamp. Covers the env-validation
# and bad-credential aborts, the full token-exchange -> edits -> bundles
# lookup against a local stub server (no Google network; the script's
# GOOGLE_OAUTH_TOKEN_URL / ANDROIDPUBLISHER_BASE_URL test seams point it at
# tests/play-highest-version-code-stub.rb), the RS256 JWT the script sends
# verified against a throwaway key, both in-range selection and the
# empty-range no-output case, both API-failure aborts, the real per-bundle
# versionCode scalar shape plus the legacy versionCodes array and a
# neither-field schema-mismatch warning (issue #1355), and the workflow
# wiring. Run with:
#
#   bash .github/scripts/tests/play-highest-version-code.test.sh
#
# Requires ruby on PATH (the release workflow needs it too); everything else
# is stdlib.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../play-highest-version-code.rb"
STUB="$SCRIPT_DIR/play-highest-version-code-stub.rb"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

PLAY_WORKFLOW="$SCRIPT_DIR/../../workflows/play-store-release.yml"
CI_WORKFLOW="$SCRIPT_DIR/../../workflows/ci.yml"

if ! command -v ruby >/dev/null 2>&1; then
  echo "FAIL: ruby is not on PATH (ubuntu-latest release-guards runners ship it)"
  exit 1
fi

# Throwaway RSA key + a service-account JSON wrapping its private half, so
# the suite proves real RS256 signing without ever seeing production
# credentials.
KEYDIR="$(mktemp -d)"
ruby -e '
  require "openssl"
  require "json"
  key = OpenSSL::PKey::RSA.generate(2048)
  File.write(ARGV[0], key.to_pem)
  File.write(ARGV[1], key.public_key.to_pem)
  File.write(ARGV[2], JSON.generate(
    type: "service_account",
    client_email: "stub-sa@stub-project.iam.gserviceaccount.com",
    private_key: key.to_pem))
' "$KEYDIR/client_key.pem" "$KEYDIR/public_key.pem" "$KEYDIR/service_account.json"

STUB_PID=""

start_stub() {
  # start_stub <bundles-json-file> <record-dir> <port-file>
  ruby "$STUB" "$1" "$2" "$3" &
  STUB_PID=$!
  local i
  for i in $(seq 1 100); do
    if [ -s "$3" ]; then
      return 0
    fi
    if ! kill -0 "$STUB_PID" 2>/dev/null; then
      echo "FAIL: stub server exited before accepting"
      exit 1
    fi
    sleep 0.1
  done
  echo "FAIL: stub server never reported a port"
  exit 1
}

stop_stub() {
  if [ -n "$STUB_PID" ]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
    STUB_PID=""
  fi
}
trap '[ -n "$STUB_PID" ] && kill "$STUB_PID" 2>/dev/null || true' EXIT

# Run the script with the caller's exported env.
# Populates: $LAST_EXIT, $LAST_OUT (stdout), $LAST_LOG (stderr)
run_case() {
  local outfile errfile
  outfile="$(mktemp)"
  errfile="$(mktemp)"
  set +e
  ruby "$SCRIPT" >"$outfile" 2>"$errfile"
  LAST_EXIT=$?
  set -e
  LAST_OUT="$(cat "$outfile")"
  LAST_LOG="$(cat "$errfile")"
  rm -f "$outfile" "$errfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# --- Env validation (aborts before any network) ---

unset PLAY_STORE_JSON_KEY PACKAGE_NAME RANGE_LOW RANGE_HIGH
unset GOOGLE_OAUTH_TOKEN_URL ANDROIDPUBLISHER_BASE_URL
run_case
assert_exit "everything unset refuses" 1
assert_contains "refusal names PLAY_STORE_JSON_KEY" "$LAST_LOG" "missing PLAY_STORE_JSON_KEY"

PLAY_STORE_JSON_KEY="{}" PACKAGE_NAME="com.wjdavis5.lunarlog" RANGE_LOW=1000
export PLAY_STORE_JSON_KEY PACKAGE_NAME RANGE_LOW
run_case
assert_exit "missing RANGE_HIGH refuses" 1
assert_contains "refusal names RANGE_HIGH" "$LAST_LOG" "missing RANGE_HIGH"

export RANGE_HIGH=499999
PLAY_STORE_JSON_KEY="not json at all"
export PLAY_STORE_JSON_KEY
run_case
assert_exit "non-JSON service account refuses" 1
assert_contains "refusal says the key is not valid JSON" "$LAST_LOG" "not valid JSON"

PLAY_STORE_JSON_KEY='{"private_key":"nope"}'
export PLAY_STORE_JSON_KEY
run_case
assert_exit "service account without client_email refuses" 1
assert_contains "refusal names the unusable service account" "$LAST_LOG" "not a usable service account"

PLAY_STORE_JSON_KEY='{"client_email":"x@y.iam.gserviceaccount.com","private_key":"also not a key"}'
export PLAY_STORE_JSON_KEY
run_case
assert_exit "garbage private key refuses" 1
assert_contains "refusal names the unusable service account (bad key)" "$LAST_LOG" "not a usable service account"

PACKAGE_NAME="../evil"
export PACKAGE_NAME
run_case
assert_exit "path-tricking PACKAGE_NAME refuses" 1
assert_contains "refusal names the bad application id" "$LAST_LOG" "not an application id"

# --- End-to-end happy paths against the stub (real JWT + real HTTP calls) ---

# The real edits.bundles.list shape: one integer versionCode per bundle
# (issue #1355 -- these fixtures previously used a versionCodes array the
# API never sends, so the whole suite passed while the live clamp never
# fired; keep this the shape Google actually returns).
BUNDLES_ALL="$KEYDIR/bundles_all.json"
printf '%s' '{"kind":"androidpublisher#bundlesListResponse","bundles":[{"versionCode":1101},{"versionCode":2100},{"versionCode":501002}]}' >"$BUNDLES_ALL"

RECORD="$KEYDIR/record"
mkdir -p "$RECORD"
PORT_FILE="$RECORD/port"
: >"$PORT_FILE"
start_stub "$BUNDLES_ALL" "$RECORD" "$PORT_FILE"
port="$(cat "$PORT_FILE")"
base="http://127.0.0.1:$port"
export GOOGLE_OAUTH_TOKEN_URL="$base/token" ANDROIDPUBLISHER_BASE_URL="$base"

PLAY_STORE_JSON_KEY="$(cat "$KEYDIR/service_account.json")"
PACKAGE_NAME="com.wjdavis5.lunarlog"
RANGE_LOW=1000
RANGE_HIGH=499999
export PLAY_STORE_JSON_KEY PACKAGE_NAME RANGE_LOW RANGE_HIGH
run_case
assert_exit "production range lookup succeeds" 0
assert_eq "production range picks the highest in-range versionCode" "2100" "$LAST_OUT"

RANGE_LOW=500000
RANGE_HIGH=999999
export RANGE_LOW RANGE_HIGH
run_case
assert_exit "QA range lookup succeeds" 0
assert_eq "QA range picks the highest in-range versionCode" "501002" "$LAST_OUT"

PACKAGE_NAME="boom.example"
export PACKAGE_NAME
run_case
assert_exit "edits-insert failure refuses" 1
assert_contains "edits-insert failure names the HTTP status" "$LAST_LOG" "edits insert failed: HTTP 403"

PACKAGE_NAME="bundleboom.example"
export PACKAGE_NAME
run_case
assert_exit "bundles-query failure refuses" 1
assert_contains "bundles-query failure names the HTTP status" "$LAST_LOG" "bundles query failed: HTTP 500"
stop_stub

# --- What the script actually sent (recorded by the stub) ---

token_record=""
for f in "$RECORD"/*-POST.txt; do
  [ -e "$f" ] || continue
  if grep -q '^PATH /token$' "$f"; then
    token_record="$f"
  fi
done
if [ -z "$token_record" ]; then
  echo "FAIL: stub never recorded the token exchange"
  exit 1
fi

jwt="$(sed -n 's/^BODY grant_type=[^&]*&assertion=\([A-Za-z0-9._-]*\)$/\1/p' "$token_record")"
if [ -z "$jwt" ]; then
  echo "FAIL: token request carried no parsable JWT assertion"
  exit 1
fi

jwt_file="$(mktemp)"
printf '%s' "$jwt" >"$jwt_file"
JWT_CHECK="$(ruby -e '
  require "openssl"
  require "json"
  require "base64"
  dec = ->(seg) do
    seg += "=" * ((4 - seg.length % 4) % 4)
    Base64.urlsafe_decode64(seg)
  end
  pub = OpenSSL::PKey::RSA.new(File.read(ARGV[0]))
  header, payload, sig = File.read(ARGV[1]).strip.split(".")
  sig_ok = pub.verify(OpenSSL::Digest::SHA256.new, dec.(sig), "#{header}.#{payload}")
  puts "SIG_OK=#{sig_ok}"
  puts "ALG=#{JSON.parse(dec.(header))["alg"]}"
  claims = JSON.parse(dec.(payload))
  puts "ISS=#{claims["iss"]}"
  puts "SCOPE=#{claims["scope"]}"
  puts "AUD=#{claims["aud"]}"
' "$KEYDIR/public_key.pem" "$jwt_file")"
rm -f "$jwt_file"

assert_contains "JWT signature verifies against the throwaway key" "$JWT_CHECK" "SIG_OK=true"
assert_contains "JWT header declares RS256" "$JWT_CHECK" "ALG=RS256"
assert_contains "JWT iss is the service account" "$JWT_CHECK" "ISS=stub-sa@stub-project.iam.gserviceaccount.com"
assert_contains "JWT scope is androidpublisher" "$JWT_CHECK" "SCOPE=https://www.googleapis.com/auth/androidpublisher"
assert_contains "JWT aud is the token endpoint" "$JWT_CHECK" "AUD=$base/token"

insert_record=""
bundles_record=""
delete_record=""
for f in "$RECORD"/*.txt; do
  [ -e "$f" ] || continue
  if grep -q '^PATH /androidpublisher/v3/applications/com.wjdavis5.lunarlog/edits$' "$f" && grep -q '^METHOD POST$' "$f"; then
    insert_record="$f"
  fi
  if grep -q '^METHOD GET$' "$f" && grep -q '/bundles' "$f" && grep -q 'com.wjdavis5.lunarlog' "$f"; then
    bundles_record="$f"
  fi
  if grep -q '^METHOD DELETE$' "$f"; then
    delete_record="$f"
  fi
done
if [ -z "$insert_record" ]; then
  echo "FAIL: stub never recorded the edits insert"
  exit 1
fi
assert_eq "lookup queried the app's own package" "com.wjdavis5.lunarlog" \
  "$(grep -o 'applications/[a-zA-Z0-9.]*' "$insert_record" | head -n 1 | cut -d/ -f2)"
assert_contains "the script authorized with the exchanged token" "$(cat "$bundles_record")" \
  '"authorization":"Bearer stub-access-token"'
if [ -z "$delete_record" ]; then
  echo "FAIL: the throwaway edit was never deleted"
  exit 1
fi

# --- Empty range: uploads exist but none inside the scanned namespace ---

BUNDLES_BELOW="$KEYDIR/bundles_below.json"
printf '%s' '{"kind":"androidpublisher#bundlesListResponse","bundles":[{"versionCode":999}]}' >"$BUNDLES_BELOW"
RECORD2="$KEYDIR/record-empty"
mkdir -p "$RECORD2"
PORT_FILE2="$RECORD2/port"
: >"$PORT_FILE2"
start_stub "$BUNDLES_BELOW" "$RECORD2" "$PORT_FILE2"
port2="$(cat "$PORT_FILE2")"
base2="http://127.0.0.1:$port2"
export GOOGLE_OAUTH_TOKEN_URL="$base2/token" ANDROIDPUBLISHER_BASE_URL="$base2"

PACKAGE_NAME="com.wjdavis5.lunarlog"
RANGE_LOW=1000
RANGE_HIGH=499999
export PACKAGE_NAME RANGE_LOW RANGE_HIGH
run_case
assert_exit "out-of-range-only uploads still succeed" 0
assert_eq "empty range prints nothing" "" "$LAST_OUT"
stop_stub

# --- Response-shape guards (issue #1355): the legacy array shape, and a
# --- bundles list whose entries carry no version field at all ---

# The fixtures above now pin the real per-bundle versionCode scalar; this
# case proves the older versionCodes array shape is still honoured, so an
# API shape revert cannot silently disarm the clamp again.
BUNDLES_LEGACY="$KEYDIR/bundles_legacy.json"
printf '%s' '{"kind":"androidpublisher#bundlesListResponse","bundles":[{"versionCode":1200},{"versionCodes":[1101,1500]}]}' >"$BUNDLES_LEGACY"
RECORD3="$KEYDIR/record-legacy"
mkdir -p "$RECORD3"
PORT_FILE3="$RECORD3/port"
: >"$PORT_FILE3"
start_stub "$BUNDLES_LEGACY" "$RECORD3" "$PORT_FILE3"
port3="$(cat "$PORT_FILE3")"
base3="http://127.0.0.1:$port3"
export GOOGLE_OAUTH_TOKEN_URL="$base3/token" ANDROIDPUBLISHER_BASE_URL="$base3"

PACKAGE_NAME="com.wjdavis5.lunarlog"
RANGE_LOW=1000
RANGE_HIGH=499999
export PACKAGE_NAME RANGE_LOW RANGE_HIGH
run_case
assert_exit "legacy versionCodes array shape still succeeds" 0
assert_eq "legacy array's highest in-range entry wins" "1500" "$LAST_OUT"
stop_stub

# A bundles list whose entries carry neither field must warn on stderr while
# still succeeding with no stdout -- the workflow keeps its counter number,
# but the log now says why the clamp stayed silent instead of passing
# silently (the failure mode that hid issue #1355).
BUNDLES_NO_FIELD="$KEYDIR/bundles_no_field.json"
printf '%s' '{"kind":"androidpublisher#bundlesListResponse","bundles":[{"sha1":"aa"},{"sha256":"bb"}]}' >"$BUNDLES_NO_FIELD"
RECORD4="$KEYDIR/record-no-field"
mkdir -p "$RECORD4"
PORT_FILE4="$RECORD4/port"
: >"$PORT_FILE4"
start_stub "$BUNDLES_NO_FIELD" "$RECORD4" "$PORT_FILE4"
port4="$(cat "$PORT_FILE4")"
base4="http://127.0.0.1:$port4"
export GOOGLE_OAUTH_TOKEN_URL="$base4/token" ANDROIDPUBLISHER_BASE_URL="$base4"

run_case
assert_exit "a bundles list with no version field still succeeds" 0
assert_eq "no version field prints nothing" "" "$LAST_OUT"
assert_contains "no version field warns about the schema mismatch" "$LAST_LOG" "neither versionCode nor versionCodes"
stop_stub

# --- Workflow wiring ---

WORKFLOW="$(cat "$PLAY_WORKFLOW")"
assert_contains "play-store-release.yml invokes the clamp script" "$WORKFLOW" "play-highest-version-code.rb"
assert_contains "the clamp step receives the service-account secret" "$WORKFLOW" 'PLAY_STORE_JSON_KEY: ${{ secrets.PLAY_STORE_JSON_KEY }}'
assert_contains "production scan range is the 1xxx-499999 namespace" "$WORKFLOW" "range_low=1000"
assert_contains "production scan range upper bound" "$WORKFLOW" "range_high=499999"
assert_contains "QA scan range is the 501xxx namespace" "$WORKFLOW" "range_low=500000"
assert_contains "QA scan range upper bound" "$WORKFLOW" "range_high=999999"
assert_contains "a failed lookup warns and falls back to the counter" "$WORKFLOW" "trusting the run-counter number"
assert_contains "a counter collision is clamped past Play's highest" "$WORKFLOW" "is not above the highest uploaded versionCode"
assert_contains "the lookup failure is scoped warn-only" "$WORKFLOW" '::warning::Could not read the highest uploaded versionCode from Google Play'

CI="$(cat "$CI_WORKFLOW")"
assert_contains "CI's release-guards job runs this suite" "$CI" "play-highest-version-code.test.sh"

print_summary "play-highest-version-code.test.sh"
