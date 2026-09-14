#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-auth-config.sh (issue #266). Run
# with:
#
#   bash .github/scripts/tests/check-auth-config.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-auth-config.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

# run_case CONFIG_CONTENTS
# Populates: $LAST_EXIT $LAST_LOG
run_case() {
  local contents="$1"
  local tmpfile logfile
  tmpfile="$(mktemp)"
  logfile="$(mktemp)"
  printf '%s\n' "$contents" >"$tmpfile"
  set +e
  bash "$SCRIPT" "$tmpfile" >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$tmpfile" "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# The committed security posture this repo targets (issue #266, D-5) --
# matches what supabase/config.toml is expected to carry after this
# issue's fix. password_requirements is deliberately empty, not a
# complexity requirement -- review round 1: the client only enforces
# minimum_password_length (kMinPasswordLength = 12), so a non-empty value
# here would let the server reject a password the client already
# accepted.
good_config='[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
additional_redirect_urls = ["https://127.0.0.1:3000"]
jwt_expiry = 600
enable_refresh_token_rotation = true
refresh_token_reuse_interval = 10
enable_signup = false
enable_anonymous_sign_ins = false
enable_manual_linking = true
minimum_password_length = 12
password_requirements = ""

[auth.rate_limit]
email_sent = 2

[auth.email]
enable_signup = true
double_confirm_changes = true
enable_confirmations = true
secure_password_change = false
max_frequency = "1s"
otp_length = 8
otp_expiry = 600

[auth.sms]
enable_signup = false
enable_confirmations = false'

# The original stock-template values (issue #266's actual before-state) --
# every checked key wrong at once.
stock_config='[auth]
enabled = true
site_url = "http://127.0.0.1:3000"
jwt_expiry = 3600
enable_refresh_token_rotation = true
enable_signup = true
enable_anonymous_sign_ins = false
enable_manual_linking = false
minimum_password_length = 6
password_requirements = ""

[auth.rate_limit]
email_sent = 2

[auth.email]
enable_signup = true
double_confirm_changes = true
enable_confirmations = false
secure_password_change = false
otp_length = 6
otp_expiry = 3600

[auth.sms]
enable_signup = false'

run_case "$good_config"
assert_exit "the committed security posture passes cleanly" 0
assert_not_contains "clean config emits no error" "$LAST_LOG" "::error::"
assert_contains "clean config prints a confirmation line" "$LAST_LOG" \
  "matches this repo's committed security posture"

run_case "$stock_config"
assert_exit "the original stock template (issue #266's before-state) fails" 1
# password_requirements is NOT in this list: the stock default ("") is now
# also the expected value (review round 1), so it is the one checked key
# the stock config does not get wrong -- see the dedicated
# password_requirements-wrong case below for that key's own coverage.
for key in jwt_expiry enable_signup enable_manual_linking \
  minimum_password_length enable_confirmations otp_length otp_expiry; do
  assert_contains "stock config names $key as wrong" "$LAST_LOG" "$key"
done
assert_not_contains \
  "stock config's password_requirements ('') matches the expected value, so it is not reported wrong" \
  "$LAST_LOG" "password_requirements ="
error_count="$(printf '%s' "$LAST_LOG" | grep -c '::error::' || true)"
assert_eq "stock config reports all 7 remaining mismatches, not just the first" "7" "$error_count"

# --- Targeted single-field regressions, each isolated from a clean base ---

jwt_wrong="${good_config/jwt_expiry = 600/jwt_expiry = 3600}"
run_case "$jwt_wrong"
assert_exit "jwt_expiry alone wrong (3600) fails" 1
assert_contains "jwt_expiry mismatch names the actual and expected values" \
  "$LAST_LOG" "jwt_expiry = 3600 (expected 600)"

signup_wrong="${good_config/enable_signup = false/enable_signup = true}"
run_case "$signup_wrong"
assert_exit "top-level enable_signup alone wrong (true) fails" 1
assert_contains "enable_signup mismatch is under [auth], not [auth.email]" \
  "$LAST_LOG" "[auth] enable_signup"

# password_requirements is expected empty (review round 1); a non-empty
# value here (e.g. an accidental complexity requirement) must still be
# caught, even though it is no longer the stock config's own point of
# difference.
password_requirements_wrong="${good_config/password_requirements = \"\"/password_requirements = \"lower_upper_letters_digits_symbols\"}"
run_case "$password_requirements_wrong"
assert_exit "a non-empty password_requirements fails" 1
assert_contains \
  "password_requirements mismatch names the actual and expected values" \
  "$LAST_LOG" \
  "password_requirements = lower_upper_letters_digits_symbols (expected )"

# --- Section precision: a correct value in the WRONG section must not
# satisfy the [auth] check (the [auth.email] block also has enable_signup
# and enable_confirmations keys with different intended values) ---

wrong_section="$good_config"
# Corrupt [auth]'s own enable_confirmations equivalent by moving the
# correct otp_length value out of [auth.email] entirely -- this fixture
# keeps [auth.email] present but strips its otp_length line, proving a
# value that exists only in the wrong (or no) section is reported missing,
# not silently accepted from elsewhere.
wrong_section="$(printf '%s\n' "$wrong_section" | grep -v '^otp_length = 8$')"
run_case "$wrong_section"
assert_exit "otp_length missing from [auth.email] fails" 1
assert_contains "missing key is reported as missing, not silently passed" \
  "$LAST_LOG" "missing 'otp_length'"

# --- A commented-out correct value must not satisfy the check (the value
# actually in effect, jwt_expiry = 3600, is still wrong) ---

commented_trap="$(printf '%s\n' "$good_config" | \
  sed 's/^jwt_expiry = 600$/# jwt_expiry = 600\njwt_expiry = 3600/')"
run_case "$commented_trap"
assert_exit "a commented-out correct value above the real wrong one still fails" 1
assert_contains "the live (uncommented) wrong value is what gets reported" \
  "$LAST_LOG" "jwt_expiry = 3600 (expected 600)"

# --- Missing file ---

missing_log="$(mktemp)"
set +e
bash "$SCRIPT" "/no/such/file.toml" >"$missing_log" 2>&1
LAST_EXIT=$?
set -e
LAST_LOG="$(cat "$missing_log")"
rm -f "$missing_log"
assert_exit "a missing config file fails" 1
assert_contains "missing file error names the path" "$LAST_LOG" "not found"

print_summary "check-auth-config.test.sh"
