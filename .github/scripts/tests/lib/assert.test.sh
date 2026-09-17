#!/usr/bin/env bash
set -euo pipefail

# Regression coverage for lib/assert.sh's own substring helpers.
#
# Every release-guard suite runs under `set -euo pipefail` and sources
# these helpers, so a bug here is invisible: it reports a wrong verdict in
# the voice of whichever suite called it. The implementation used to be
# `printf '%s' "$haystack" | grep -qF -- "$needle"`, which races -- `grep
# -q` exits on the first match, `printf` takes SIGPIPE on a large haystack
# whose match lands early, and `pipefail` promotes that 141 to the
# pipeline's status. assert_contains then reported FAIL on matching
# content (seen on PR #721's CI: "FAIL: ios-release.yml declares the
# qa_build input" printed directly above a dump containing `qa_build:`),
# and assert_not_contains reported PASS on content that DID contain the
# needle -- a real regression rendered green.
#
# The cases below pin both directions against exactly that shape: a
# haystack far larger than a pipe buffer with the needle in its first few
# lines.
#
#   bash .github/scripts/tests/lib/assert.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert.sh
source "$SCRIPT_DIR/assert.sh"

# ~700 KB, needle on line 2 -- orders of magnitude past any pipe buffer,
# so a grep -q implementation is guaranteed to close the pipe early.
big_haystack="first line
      qa_build:
"
filler="$(printf 'x%.0s' $(seq 1 1000))"
for _ in $(seq 1 700); do
  big_haystack="$big_haystack$filler
"
done

outer_pass=0
outer_fail=0

expect() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    outer_pass=$((outer_pass + 1))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    outer_fail=$((outer_fail + 1))
  fi
}

# --- assert_contains -------------------------------------------------

pass=0; fail=0
assert_contains "inner" "$big_haystack" "qa_build:" > /dev/null
expect "assert_contains matches an early needle in a huge haystack (no SIGPIPE race)" "1 0" "$pass $fail"

pass=0; fail=0
assert_contains "inner" "$big_haystack" "not-in-there" > /dev/null
expect "assert_contains still fails on a genuinely absent needle" "0 1" "$pass $fail"

pass=0; fail=0
assert_contains "inner" "a --dart-define=X b" "--dart-define=X" > /dev/null
expect "assert_contains treats a leading-dash needle as text, not an option" "1 0" "$pass $fail"

pass=0; fail=0
assert_contains "inner" 'needs: [verify, qa-build-gate]' 'needs: [verify, qa-build-gate]' > /dev/null
expect "assert_contains treats glob metacharacters in the needle literally" "1 0" "$pass $fail"

pass=0; fail=0
assert_contains "inner" 'literal a*c here' 'a*c' > /dev/null
expect "assert_contains does not let a needle's * match arbitrary text" "1 0" "$pass $fail"

pass=0; fail=0
assert_contains "inner" 'abbbc' 'a*c' > /dev/null
expect "assert_contains's * is literal: 'a*c' does not match 'abbbc'" "0 1" "$pass $fail"

# --- assert_not_contains ---------------------------------------------

pass=0; fail=0
assert_not_contains "inner" "$big_haystack" "qa_build:" > /dev/null
expect "assert_not_contains FAILS on an early needle in a huge haystack (the inverted-verdict bug)" "0 1" "$pass $fail"

pass=0; fail=0
assert_not_contains "inner" "$big_haystack" "not-in-there" > /dev/null
expect "assert_not_contains passes when the needle really is absent" "1 0" "$pass $fail"

echo ""
echo "assert.test.sh: $outer_pass passed, $outer_fail failed"
[ "$outer_fail" -eq 0 ]
