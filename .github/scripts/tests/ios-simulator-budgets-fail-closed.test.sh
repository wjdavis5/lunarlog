#!/usr/bin/env bash
set -euo pipefail

# Truth table for the gate_test.dart fail-closed guards inside
# ios-simulator-budgets.test.sh (issue #1317).
#
# The budgets suite pins integration_test/gate_test.dart's per-test
# `timeout: _kTestTimeout` bounds by comparing two `grep -c ... || true`
# counts. Before #1317 that comparison passed when gate_test.dart was
# missing or had no testWidgets( left -- two empty results comparing
# equal -- so the guard had the same hole it exists to close. This suite
# runs the budgets script inside a sandbox repo tree (its own copy of
# assert.sh plus the real ci.yml, so every ci.yml-derived assertion keeps
# passing and the gate_test.dart guards are the only variable) and pins
# each failure mode's exit status and message.
#
# Run with:
#
#   bash .github/scripts/tests/ios-simulator-budgets-fail-closed.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SCRIPT_DIR/ios-simulator-budgets.test.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A healthy gate_test.dart: the exact #827 declaration the budgets suite
# asserts on, two testWidgets( calls, two `timeout: _kTestTimeout` bounds.
FIXTURE_HEALTHY="$WORK/fixture_healthy.dart"
cat > "$FIXTURE_HEALTHY" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

const Timeout _kTestTimeout = Timeout(Duration(minutes: 2));

void main() {
  testWidgets('one', (tester) async {}, timeout: _kTestTimeout);
  testWidgets('two', (tester) async {}, timeout: _kTestTimeout);
}
EOF

# Tests but no bounds: the count mismatch the assert_eq below the guards
# must still catch.
FIXTURE_NO_BOUNDS="$WORK/fixture_no_bounds.dart"
cat > "$FIXTURE_NO_BOUNDS" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

const Timeout _kTestTimeout = Timeout(Duration(minutes: 2));

void main() {
  testWidgets('one', (tester) async {});
  testWidgets('two', (tester) async {});
}
EOF

# The declaration but no tests at all: the zero-testWidgets( floor.
FIXTURE_NO_TESTS="$WORK/fixture_no_tests.dart"
cat > "$FIXTURE_NO_TESTS" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

const Timeout _kTestTimeout = Timeout(Duration(minutes: 2));

void main() {}
EOF

# A gate_test.dart whose counts disagree (3 tests, 2 bounds): unequal
# non-empty counts, the case the original assert_eq already caught.
FIXTURE_MISMATCHED="$WORK/fixture_mismatched.dart"
cat > "$FIXTURE_MISMATCHED" <<'EOF'
import 'package:flutter_test/flutter_test.dart';

const Timeout _kTestTimeout = Timeout(Duration(minutes: 2));

void main() {
  testWidgets('one', (tester) async {}, timeout: _kTestTimeout);
  testWidgets('two', (tester) async {}, timeout: _kTestTimeout);
  testWidgets('three', (tester) async {});
}
EOF

# build_sandbox FIXTURE [--missing]
#   Shapes $WORK like the repo root the way the budgets suite resolves its
#   inputs from BASH_SOURCE: .github/scripts/tests/{suite,lib/assert.sh},
#   .github/workflows/ci.yml (the real one, copied verbatim), and
#   integration_test/gate_test.dart from FIXTURE. --missing leaves
#   gate_test.dart absent.
build_sandbox() {
  local fixture="$1"
  rm -rf "$WORK/.github" "$WORK/integration_test"
  mkdir -p "$WORK/.github/scripts/tests/lib" "$WORK/.github/workflows" "$WORK/integration_test"
  cp "$SUITE" "$WORK/.github/scripts/tests/ios-simulator-budgets.test.sh"
  cp "$SCRIPT_DIR/lib/assert.sh" "$WORK/.github/scripts/tests/lib/assert.sh"
  cp "$SCRIPT_DIR/../../workflows/ci.yml" "$WORK/.github/workflows/ci.yml"
  if [ "$fixture" != "--missing" ]; then
    cp "$fixture" "$WORK/integration_test/gate_test.dart"
  fi
}

run_sandbox_suite() {
  set +e
  SANDBOX_OUT="$(bash "$WORK/.github/scripts/tests/ios-simulator-budgets.test.sh" 2>&1)"
  SANDBOX_RC=$?
  set -e
}

# ---------------------------------------------------------------------------
# Case 1: gate_test.dart missing -> fail closed with the missing-file message
# ---------------------------------------------------------------------------
build_sandbox --missing
run_sandbox_suite
assert_eq "a missing gate_test.dart fails the suite" "1" "$SANDBOX_RC"
assert_contains "the missing-file guard names gate_test.dart" "$SANDBOX_OUT" \
  "FAIL: integration_test/gate_test.dart is missing"

# ---------------------------------------------------------------------------
# Case 2: gate_test.dart with no testWidgets( left -> fail closed
# (grep -c prints 0 on an existing file, so this is the zero floor, not the
# empty-string case)
# ---------------------------------------------------------------------------
build_sandbox "$FIXTURE_NO_TESTS"
run_sandbox_suite
assert_eq "a gate_test.dart with zero testWidgets( fails the suite" "1" "$SANDBOX_RC"
assert_contains "the zero-tests guard says what vanished" "$SANDBOX_OUT" \
  "no testWidgets( left"

# ---------------------------------------------------------------------------
# Case 3: tests but no `timeout: _kTestTimeout` bounds -> fail closed
# ---------------------------------------------------------------------------
build_sandbox "$FIXTURE_NO_BOUNDS"
run_sandbox_suite
assert_eq "a gate_test.dart with no bounds fails the suite" "1" "$SANDBOX_RC"
assert_contains "the no-bounds guard names the #827 bound" "$SANDBOX_OUT" \
  "#827 per-test bounds are gone"

# ---------------------------------------------------------------------------
# Case 4: unequal non-empty counts -> the original assert_eq still catches it
# (pre-existing behavior, pinned here so the guards above can't regress it)
# ---------------------------------------------------------------------------
build_sandbox "$FIXTURE_MISMATCHED"
run_sandbox_suite
assert_eq "mismatched test/bound counts fail the suite" "1" "$SANDBOX_RC"
assert_contains "the count mismatch surfaces as the original assertion" "$SANDBOX_OUT" \
  "every testWidgets in gate_test.dart carries the #827 per-test bound"

# ---------------------------------------------------------------------------
# Case 5: a healthy gate_test.dart still passes the whole suite
# ---------------------------------------------------------------------------
build_sandbox "$FIXTURE_HEALTHY"
run_sandbox_suite
assert_eq "a healthy gate_test.dart passes the suite" "0" "$SANDBOX_RC"
assert_contains "the healthy run's summary shows no failures" "$SANDBOX_OUT" \
  "0 failed"

print_summary "ios-simulator-budgets-fail-closed.test.sh"
