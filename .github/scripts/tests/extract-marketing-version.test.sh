#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/extract-marketing-version.sh. Run with:
#
#   bash .github/scripts/tests/extract-marketing-version.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../extract-marketing-version.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

run_case() {
  printf '%s' "$1" | bash "$SCRIPT"
}

assert_eq "version with build metadata strips the +build suffix" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: 1.2.3+45\n')"

assert_eq "version with no build metadata passes through unchanged" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: 1.2.3\n')"

assert_eq "extra whitespace after the colon is trimmed" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion:    1.2.3+45\n')"

assert_eq "a trailing comment after the version is stripped, not left dangling" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: 1.2.3 # rc\n')"

assert_eq "a trailing comment survives alongside build metadata" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: 1.2.3+45 # rc\n')"

assert_eq "only the first version: line is used when more than one is present" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: 1.2.3\nversion: 9.9.9\n')"

missing_version_output="$(printf 'name: lunarlog\n' | bash "$SCRIPT" 2>&1)" && missing_version_rc=0 || missing_version_rc=$?
assert_eq "a pubspec.yaml with no version: line exits non-zero" "1" "$missing_version_rc"
assert_contains "a pubspec.yaml with no version: line reports a clear error" \
  "$missing_version_output" "no 'version:' line found"

# LLA-115 regressions: quoted YAML scalars and empty/comment-only values.

assert_eq "a double-quoted version with build metadata strips the quote, not just the +build" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: "1.2.3+45"\n')"

assert_eq "a single-quoted version strips the quote" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: \'1.2.3\'\n')"

assert_eq "a double-quoted version with no build metadata strips the quote" \
  "1.2.3" "$(run_case $'name: lunarlog\nversion: "1.2.3"\n')"

empty_value_output="$(printf 'name: lunarlog\nversion:\n' | bash "$SCRIPT" 2>&1)" && empty_value_rc=0 || empty_value_rc=$?
assert_eq "a version: line with no value at all exits non-zero" "1" "$empty_value_rc"
assert_contains "a version: line with no value reports a clear error, not the raw line" \
  "$empty_value_output" "could not parse a version value"

comment_only_output="$(printf 'name: lunarlog\nversion: # todo\n' | bash "$SCRIPT" 2>&1)" && comment_only_rc=0 || comment_only_rc=$?
assert_eq "a version: line that is only a comment exits non-zero" "1" "$comment_only_rc"
assert_contains "a comment-only version: line reports a clear error, not the raw line" \
  "$comment_only_output" "could not parse a version value"

malformed_output="$(printf 'name: lunarlog\nversion: abc\n' | bash "$SCRIPT" 2>&1)" && malformed_rc=0 || malformed_rc=$?
assert_eq "a non-numeric version value exits non-zero" "1" "$malformed_rc"
assert_contains "a non-numeric version value reports a clear error" \
  "$malformed_output" "not a valid x.y.z marketing version"

two_segment_output="$(printf 'name: lunarlog\nversion: 1.2\n' | bash "$SCRIPT" 2>&1)" && two_segment_rc=0 || two_segment_rc=$?
assert_eq "a version with only two segments (not x.y.z) exits non-zero" "1" "$two_segment_rc"
assert_contains "a two-segment version reports a clear error" \
  "$two_segment_output" "not a valid x.y.z marketing version"

trailing_dot_output="$(printf 'name: lunarlog\nversion: 1.2.3.\n' | bash "$SCRIPT" 2>&1)" && trailing_dot_rc=0 || trailing_dot_rc=$?
assert_eq "a version with a trailing dot exits non-zero" "1" "$trailing_dot_rc"

print_summary "extract-marketing-version.test.sh"
