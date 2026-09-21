#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-advisor-gate.sh (issue #454). Run with:
#
#   bash .github/scripts/tests/check-advisor-gate.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-advisor-gate.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

run_script() {
  # $1: stdin payload.
  bash "$SCRIPT" <<< "$1"
}

finding() {
  # $1: name, $2: detail, $3: metadata JSON object (default {}),
  # $4: level (default "WARN" -- matches the real advisor JSON shape,
  # where every result carries a level field).
  local name="$1" detail="$2" metadata="${3:-{\}}" level="${4:-WARN}"
  printf '{"name":"%s","detail":"%s","metadata":%s,"level":"%s"}' "$name" "$detail" "$metadata" "$level"
}

# --- empty results: pass ------------------------------------------------

out="$(run_script '{"results":[]}')"
assert_contains "empty results passes" "$out" "Database advisor gate passed"

# --- exactly the two documented exclusions, together: still pass --------

two="$(finding authenticated_security_definer_function_executable "sync_push is executable by authenticated" '{"name":"sync_push"}'),$(finding extension_in_public "Extension pg_net is installed in the public schema" '{"name":"pg_net"}')"
out="$(run_script "{\"results\":[$two]}")"
assert_contains "both documented exclusions together still pass" "$out" "Database advisor gate passed"

# --- authenticated_security_definer_function_executable, any function name, excluded ---

out="$(run_script "{\"results\":[$(finding authenticated_security_definer_function_executable "create_guardian_invitation is executable by authenticated" '{"name":"create_guardian_invitation"}')]}")"
assert_contains "authenticated_security_definer_function_executable is excluded regardless of which function it names" \
  "$out" "Database advisor gate passed"

# --- extension_in_public for pg_net specifically: excluded ---------------

out="$(run_script "{\"results\":[$(finding extension_in_public "Extension pg_net is installed in the public schema" '{"name":"pg_net"}')]}")"
assert_contains "extension_in_public for pg_net is excluded" "$out" "Database advisor gate passed"

# --- extension_in_public for any OTHER extension: NOT excluded -----------

set +e
err="$(run_script "{\"results\":[$(finding extension_in_public "Extension pg_cron is installed in the public schema" '{"name":"pg_cron"}')]}" 2>&1 1>/dev/null)"
rc=$?
set -e
assert_eq "extension_in_public for pg_cron (not pg_net) exits non-zero" "1" "$rc"
assert_contains "the error reports the pg_cron finding" "$err" "extension_in_public"

# --- auth_leaked_password_protection: NO LONGER excluded (issue #972) -----
# The owner turned leaked-password protection ON (issue #18 dashboard
# checklist, completed 2026-09-20), so the finding is gone from production
# and the exclusion was removed. If it ever comes back the toggle was
# turned off again, and the gate must fail so issue #18 is reopened --
# never silently excused.

set +e
err_leaked="$(run_script "{\"results\":[$(finding auth_leaked_password_protection "Leaked password protection is disabled" '{}')]}" 2>&1 1>/dev/null)"
rc_leaked=$?
set -e
assert_eq "auth_leaked_password_protection is no longer excluded and exits non-zero" "1" "$rc_leaked"
assert_contains "the error reports the leaked-password finding" "$err_leaked" "auth_leaked_password_protection"

# --- any other/unknown finding still fails closed -------------------------

set +e
err2="$(run_script "{\"results\":[$(finding function_search_path_mutable "Function public.some_fn has a role mutable search_path" '{"name":"some_fn"}')]}" 2>&1 1>/dev/null)"
rc2=$?
set -e
assert_eq "an ordinary function_search_path_mutable finding still exits non-zero" "1" "$rc2"
assert_contains "the error names it" "$err2" "function_search_path_mutable"

set +e
err3="$(run_script "{\"results\":[$(finding some_brand_new_lint_never_seen_before "whoa" '{}')]}" 2>&1 1>/dev/null)"
rc3=$?
set -e
assert_eq "a lint name this script has never seen before still exits non-zero (fails closed)" "1" "$rc3"
assert_contains "the error names it" "$err3" "some_brand_new_lint_never_seen_before"

# --- INFO-level findings are dropped regardless of name; WARN is not ------
# Production carries 7 by-design INFO-level rls_enabled_no_policy findings
# (service-only tables) that this gate must never fail on -- but a WARN
# finding of the very same, otherwise-unexcluded lint name must still fail.

out="$(run_script "{\"results\":[$(finding rls_enabled_no_policy "Table public.notification_outbox has RLS enabled, but no policies exist" '{"name":"notification_outbox"}' INFO)]}")"
assert_contains "an INFO finding of a non-excluded lint passes" "$out" "Database advisor gate passed"

set +e
err_warn_level="$(run_script "{\"results\":[$(finding rls_enabled_no_policy "Table public.notification_outbox has RLS enabled, but no policies exist" '{"name":"notification_outbox"}' WARN)]}" 2>&1 1>/dev/null)"
rc_warn_level=$?
set -e
assert_eq "a WARN finding of the same, otherwise-unexcluded lint exits non-zero" "1" "$rc_warn_level"
assert_contains "the error names it" "$err_warn_level" "rls_enabled_no_policy"

# lowercase "info" also matches (case-insensitive) -- the real CLI has
# always emitted uppercase, but the check itself does not assume that.
out="$(run_script "{\"results\":[$(finding rls_enabled_no_policy "x" '{}' info)]}")"
assert_contains "a lowercase info level also passes (case-insensitive)" "$out" "Database advisor gate passed"

# --- a finding with no level field, or an unrecognised level, fails closed ---
# Neither is treated as INFO -- only an unambiguous case-insensitive match
# on "INFO" is ever excluded by level.

set +e
err_no_level="$(run_script '{"results":[{"name":"some_lint","detail":"no level field at all","metadata":{}}]}' 2>&1 1>/dev/null)"
rc_no_level=$?
set -e
assert_eq "a finding with no level field exits non-zero" "1" "$rc_no_level"
assert_contains "the error names it" "$err_no_level" "some_lint"

set +e
err_unknown_level="$(run_script "{\"results\":[$(finding some_lint "an unrecognised level string" '{}' DEBUG)]}" 2>&1 1>/dev/null)"
rc_unknown_level=$?
set -e
assert_eq "an unrecognised level string exits non-zero" "1" "$rc_unknown_level"
assert_contains "the error names it" "$err_unknown_level" "some_lint"

# --- exclusions plus one real finding: still fails, reports only the real one ---

mixed="$(finding authenticated_security_definer_function_executable "x" '{"name":"y"}'),$(finding extension_in_public "Extension pg_net is installed in the public schema" '{"name":"pg_net"}'),$(finding function_search_path_mutable "Function public.real_finding has a role mutable search_path" '{"name":"real_finding"}')"
set +e
err4="$(run_script "{\"results\":[$mixed]}" 2>&1 1>/dev/null)"
rc4=$?
set -e
assert_eq "excluded findings plus one real finding still exits non-zero" "1" "$rc4"
assert_contains "the error reports the real finding" "$err4" "real_finding"
assert_not_contains "the error does not also report the excluded authenticated_security_definer_function_executable finding" \
  "$err4" "authenticated_security_definer_function_executable"
assert_not_contains "the error does not also report the excluded pg_net extension_in_public finding" \
  "$err4" "Extension pg_net"

# --- malformed / missing-results input fails closed -----------------------

set +e
err5="$(run_script 'not json at all' 2>&1 1>/dev/null)"
rc5=$?
set -e
assert_eq "malformed JSON exits non-zero" "1" "$rc5"
assert_contains "malformed JSON produces an ::error:: annotation" "$err5" "::error::"

set +e
err6="$(run_script '{}' 2>&1 1>/dev/null)"
rc6=$?
set -e
assert_eq "a results-less object exits non-zero" "1" "$rc6"
assert_contains "the missing-results case produces an ::error:: annotation" "$err6" "::error::"

set +e
err7="$(run_script '{"results":"not-an-array"}' 2>&1 1>/dev/null)"
rc7=$?
set -e
assert_eq "a non-array results field exits non-zero" "1" "$rc7"
assert_contains "the non-array-results case produces an ::error:: annotation" "$err7" "::error::"

print_summary "check-advisor-gate.test.sh"
