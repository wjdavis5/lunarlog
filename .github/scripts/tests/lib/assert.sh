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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "PASS: $desc"
    pass=$((pass + 1))
  else
    echo "FAIL: $desc (expected to find '$needle')"
    echo "$haystack" | sed 's/^/  /'
    fail=$((fail + 1))
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    echo "FAIL: $desc (did not expect to find '$needle')"
    echo "$haystack" | sed 's/^/  /'
    fail=$((fail + 1))
  else
    echo "PASS: $desc"
    pass=$((pass + 1))
  fi
}

print_summary() {
  local suite_name="$1"
  echo ""
  echo "$suite_name: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}
