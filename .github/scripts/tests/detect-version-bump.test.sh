#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/detect-version-bump.sh. Builds a
# throwaway git repo per case, commits synthetic pubspec.yaml contents, and
# asserts on the emitted `submit=` value and on warning presence. Run with:
#
#   bash .github/scripts/tests/detect-version-bump.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../detect-version-bump.sh"
ALL_ZERO_SHA="0000000000000000000000000000000000000000"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

tmp_dirs=()

cleanup() {
  for d in "${tmp_dirs[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
}
trap cleanup EXIT

new_repo() {
  local dir
  dir="$(mktemp -d)"
  tmp_dirs+=("$dir")
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  echo "$dir"
}

write_pubspec() {
  local dir="$1" version="$2"
  printf 'name: lunarlog\nversion: %s\ndescription: test\n' "$version" > "$dir/pubspec.yaml"
}

commit() {
  local dir="$1" msg="$2"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "$msg"
}

sha_of() {
  local dir="$1" ref="$2"
  git -C "$dir" rev-parse "$ref"
}

# run_case DIR EVENT_NAME BEFORE_SHA SUBMIT_FOR_REVIEW CURRENT_VERSION
# Populates: $LAST_SUBMIT $LAST_LOG
run_case() {
  local dir="$1" event="$2" before="$3" submit_for_review="$4" current="$5"
  local outfile="$dir/.gh_output"
  local logfile="$dir/.log"
  rm -f "$outfile" "$logfile"
  (
    cd "$dir" || exit 1
    export GITHUB_OUTPUT="$outfile"
    export EVENT_NAME="$event"
    export BEFORE_SHA="$before"
    export SUBMIT_FOR_REVIEW="$submit_for_review"
    export CURRENT_VERSION="$current"
    bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_SUBMIT="$(grep -o 'submit=.*' "$outfile" 2>/dev/null | tail -1 | cut -d= -f2 || true)"
  LAST_LOG="$(cat "$logfile")"
}

assert_submit() {
  local desc="$1" expected="$2"
  assert_eq "$desc" "$expected" "${LAST_SUBMIT:-<none>}"
}

assert_warning() {
  assert_contains "$1" "$LAST_LOG" "::warning::"
}

assert_no_warning() {
  assert_not_contains "$1" "$LAST_LOG" "::warning::"
}

# --- Case 1: Bump in the tip commit of a one-commit push -> submit=true ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.1.0"
commit "$dir" "bump tip"
run_case "$dir" "push" "$before" "" "1.1.0"
assert_submit "bump in tip commit of one-commit push" "true"

# --- Case 2: Bump in the FIRST of three pushed commits, tip unchanged ---
# This is the regression the issue reports; it must fail before the fix.
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.1.0"
commit "$dir" "bump (commit 1 of 3)"
echo "unrelated change" >> "$dir/README.md"
commit "$dir" "unrelated (commit 2 of 3)"
echo "more" >> "$dir/README.md"
commit "$dir" "unrelated tip (commit 3 of 3)"
run_case "$dir" "push" "$before" "" "1.1.0"
assert_submit "bump in first of three commits, tip unchanged" "true"

# --- Case 3: Bump in the middle of a five-commit push -> submit=true ---
dir="$(new_repo)"
write_pubspec "$dir" "2.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
echo "a" > "$dir/a.txt"; commit "$dir" "commit 1 of 5"
echo "b" > "$dir/b.txt"; commit "$dir" "commit 2 of 5"
write_pubspec "$dir" "2.1.0"
commit "$dir" "bump (commit 3 of 5)"
echo "c" > "$dir/c.txt"; commit "$dir" "commit 4 of 5"
echo "d" > "$dir/d.txt"; commit "$dir" "commit 5 of 5 (tip)"
run_case "$dir" "push" "$before" "" "2.1.0"
assert_submit "bump in middle of five-commit push" "true"

# --- Case 4: No bump anywhere in a three-commit push -> submit=false, no warning ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
echo "a" > "$dir/a.txt"; commit "$dir" "commit 1 of 3"
echo "b" > "$dir/b.txt"; commit "$dir" "commit 2 of 3"
echo "c" > "$dir/c.txt"; commit "$dir" "commit 3 of 3 (tip)"
run_case "$dir" "push" "$before" "" "1.0.0"
assert_submit "no bump anywhere in three-commit push" "false"
assert_no_warning "no bump anywhere in three-commit push emits no warning"

# --- Case 5: Bump in commit 1 reverted in commit 3 -> submit=false ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.1.0"
commit "$dir" "bump (commit 1 of 3)"
echo "b" > "$dir/b.txt"; commit "$dir" "commit 2 of 3"
write_pubspec "$dir" "1.0.0"
commit "$dir" "revert (commit 3 of 3, tip)"
run_case "$dir" "push" "$before" "" "1.0.0"
assert_submit "bump then revert in same push nets out to no bump" "false"

# --- Case 6: Build-metadata-only change, same marketing version -> submit=false ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0+7"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.0.0+8"
commit "$dir" "build bump only"
run_case "$dir" "push" "$before" "" "1.0.0"
assert_submit "build-metadata-only change does not submit" "false"

# --- Case 7: workflow_dispatch + submit_for_review=true -> submit=true, no git reads ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
# Intentionally garbage before-SHA: if the script performed a git read here
# it would fail loudly; success proves the short-circuit skipped git.
run_case "$dir" "workflow_dispatch" "not-a-real-sha" "true" "1.0.0"
assert_submit "manual dispatch with submit_for_review=true" "true"
assert_no_warning "manual submit_for_review=true short-circuit performs no git reads"

# --- Case 8: workflow_dispatch + submit_for_review=false, bumped version -> submit=false ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
run_case "$dir" "workflow_dispatch" "" "false" "1.1.0"
assert_submit "manual dispatch without submit_for_review does not auto-submit" "false"

# --- Case 9: Before-SHA is the all-zero SHA -> fallback to HEAD~1 + warning ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base (HEAD~1)"
write_pubspec "$dir" "1.1.0"
commit "$dir" "tip"
run_case "$dir" "push" "$ALL_ZERO_SHA" "" "1.1.0"
assert_submit "all-zero before-SHA falls back to HEAD~1 verdict" "true"
assert_warning "all-zero before-SHA emits a warning"

# --- Case 10: Before-SHA absent from local object store (force-push) -> fallback + warning ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base (HEAD~1)"
echo "unrelated" > "$dir/unrelated.txt"
commit "$dir" "tip (no bump)"
fake_sha="$(printf 'not-a-real-object-000000000000' | sha1sum | cut -d' ' -f1)"
run_case "$dir" "push" "$fake_sha" "" "1.0.0"
assert_submit "unreachable before-SHA falls back to HEAD~1 verdict" "false"
assert_warning "unreachable before-SHA emits a warning"

# --- Case 11: pubspec.yaml absent at the before-commit -> fallback + warning ---
dir="$(new_repo)"
echo "placeholder" > "$dir/README.md"
commit "$dir" "base without pubspec.yaml"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "add pubspec (HEAD~1)"
echo "unrelated" > "$dir/unrelated.txt"
commit "$dir" "tip (no bump)"
run_case "$dir" "push" "$before" "" "1.0.0"
assert_submit "pubspec absent at before-commit falls back to HEAD~1 verdict" "false"
assert_warning "pubspec absent at before-commit emits a warning"

# --- Case 12: Both before-SHA and HEAD~1 unavailable (single-commit repo) ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "only commit"
run_case "$dir" "push" "" "" "1.0.0"
assert_submit "single-commit repo with no usable history treats version as unchanged" "false"
assert_warning "single-commit repo with no usable history emits a warning"

# --- Case 13: pubspec.yaml at the before-commit has no parseable version: line
# (malformed/hand-edited history) -> fallback + warning, never a script crash ---
dir="$(new_repo)"
printf 'name: lunarlog\ndescription: no version line here\n' > "$dir/pubspec.yaml"
commit "$dir" "base with malformed pubspec"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "add real version (HEAD~1)"
echo "unrelated" > "$dir/unrelated.txt"
commit "$dir" "tip (no bump)"
run_case "$dir" "push" "$before" "" "1.0.0"
assert_submit "malformed pubspec at before-commit falls back to HEAD~1 verdict" "false"
assert_warning "malformed pubspec at before-commit emits a warning"

# --- Case 14: $GITHUB_OUTPUT unset -> script still runs and prints the verdict ---
dir="$(new_repo)"
write_pubspec "$dir" "1.0.0"
commit "$dir" "base"
before="$(sha_of "$dir" HEAD)"
write_pubspec "$dir" "1.1.0"
commit "$dir" "bump"
logfile="$dir/.log-no-output"
(
  cd "$dir" || exit 1
  unset GITHUB_OUTPUT || true
  export EVENT_NAME="push"
  export BEFORE_SHA="$before"
  export SUBMIT_FOR_REVIEW=""
  export CURRENT_VERSION="1.1.0"
  bash "$SCRIPT"
) >"$logfile" 2>&1
assert_contains "unset \$GITHUB_OUTPUT prints the verdict to stdout instead of failing" \
  "$(cat "$logfile")" "submit=true"

print_summary "detect-version-bump.test.sh"
