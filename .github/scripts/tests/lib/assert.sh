# .github/scripts/tests/lib/assert.sh
#
# Shared assertion helpers and pass/fail counters for the release-guard
# test harnesses. Source this file, call the assert_* functions, then
# print_summary at the end.
#
#   source "$SCRIPT_DIR/lib/assert.sh"
#   assert_eq "description" "$expected" "$actual"
#   print_summary "my-test.test.sh"

pass=0
fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected '$expected', got '$actual')"
    fail=$((fail + 1))
  fi
}

# Substring test, deliberately NOT `printf ... | grep -qF`.
#
# Every suite here runs under `set -euo pipefail`, and `grep -q` exits the
# moment it matches. On a large haystack whose match lands early (issue
# #739's workflow-wiring assertions read a ~900-line workflow and look for
# a needle on line 44) `printf` is still writing when grep closes the pipe,
# takes SIGPIPE, and exits 141 -- which `pipefail` promotes to the
# pipeline's status. The assertion then reported FAIL on content that
# plainly contained the needle, and did so only sometimes, because whether
# printf finishes first is a race. Observed on PR #721's CI ("FAIL:
# ios-release.yml declares the qa_build input" immediately above a dump of
# a file containing `qa_build:`), green on the same tree locally and on
# main.
#
# `assert_not_contains` had the sharper edge of the same bug: a SIGPIPE
# there makes the `if` take the else branch, so it PASSES -- silently
# inverting a real regression into a green check.
#
# bash's own `case` pattern match reads no pipe and spawns no process: the
# quoted "$needle" inside the pattern is matched literally, so glob
# metacharacters and leading dashes in a needle need no escaping (which is
# also why the `--` guard grep needed is gone). Works on bash 3.2, which
# the release-guards-macos job still runs.
assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case $haystack in
    *"$needle"*)
      echo "PASS: $desc"
      pass=$((pass + 1))
      ;;
    *)
      echo "FAIL: $desc (expected to find '$needle')"
      echo "$haystack" | sed 's/^/  /'
      fail=$((fail + 1))
      ;;
  esac
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  case $haystack in
    *"$needle"*)
      echo "FAIL: $desc (did not expect to find '$needle')"
      echo "$haystack" | sed 's/^/  /'
      fail=$((fail + 1))
      ;;
    *)
      echo "PASS: $desc"
      pass=$((pass + 1))
      ;;
  esac
}

print_summary() {
  local suite_name="$1"
  echo ""
  echo "$suite_name: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}
