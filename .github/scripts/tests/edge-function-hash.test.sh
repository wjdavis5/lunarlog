#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/edge-function-hash.sh (LLA-110). Run with:
#
#   bash .github/scripts/tests/edge-function-hash.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../edge-function-hash.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Every comparison below hashes the *same* directory path before and after
# a mutation -- the hash embeds each file's path (via `sha256sum`'s own
# output line), so comparing across two different directory paths would
# always differ regardless of content and prove nothing.
mkdir -p "$WORK/f"

printf 'export function a() {}\n' > "$WORK/f/index.ts"
printf '{"a":1}\n' > "$WORK/f/deno.json"
hash_1="$(bash "$SCRIPT" "$WORK/f")"

hash_1_again="$(bash "$SCRIPT" "$WORK/f")"
assert_eq "the same directory hashes identically across repeated runs" \
  "$hash_1" "$hash_1_again"

# Delete and re-create both files in the opposite order, same final
# content -- proves the hash depends only on sorted content, not on
# `find`'s filesystem/creation-order traversal.
rm "$WORK/f/index.ts" "$WORK/f/deno.json"
printf '{"a":1}\n' > "$WORK/f/deno.json"
printf 'export function a() {}\n' > "$WORK/f/index.ts"
hash_1_reordered="$(bash "$SCRIPT" "$WORK/f")"
assert_eq "identical content re-created in a different order hashes identically" \
  "$hash_1" "$hash_1_reordered"

# Edit one file's content.
printf 'export function a() { return 1; }\n' > "$WORK/f/index.ts"
hash_2="$(bash "$SCRIPT" "$WORK/f")"
if [ "$hash_1" = "$hash_2" ]; then
  echo "FAIL: editing one file's content changes the hash (both were $hash_1)"
  fail=$((fail + 1))
else
  echo "PASS: editing one file's content changes the hash"
  pass=$((pass + 1))
fi

# Add a new file (content reverted to match hash_1's state otherwise).
printf 'export function a() {}\n' > "$WORK/f/index.ts"
printf 'export function b() {}\n' > "$WORK/f/helper.ts"
hash_3="$(bash "$SCRIPT" "$WORK/f")"
if [ "$hash_1" = "$hash_3" ]; then
  echo "FAIL: adding a file changes the hash (both were $hash_1)"
  fail=$((fail + 1))
else
  echo "PASS: adding a file changes the hash"
  pass=$((pass + 1))
fi

missing_output="$(bash "$SCRIPT" "$WORK/does-not-exist" 2>&1)" && missing_rc=0 || missing_rc=$?
assert_eq "a missing directory exits non-zero" "1" "$missing_rc"
assert_contains "a missing directory reports a clear error" \
  "$missing_output" "not a directory"

print_summary "edge-function-hash.test.sh"
