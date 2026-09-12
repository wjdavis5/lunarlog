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

print_summary "extract-marketing-version.test.sh"
