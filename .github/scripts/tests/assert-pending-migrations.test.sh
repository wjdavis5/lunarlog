#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/assert-pending-migrations.sh. Builds a
# throwaway git repo per case (the detect-version-bump.test.sh pattern),
# commits synthetic supabase/migrations trees, and feeds synthetic
# `supabase db push --dry-run` output on stdin pinned to the CLI 2.116.0
# format. Run with:
#
#   bash .github/scripts/tests/assert-pending-migrations.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../assert-pending-migrations.sh"
ALL_ZERO_SHA="0000000000000000000000000000000000000000"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

tmp_dirs=()

cleanup() {
  for d in "${tmp_dirs[@]:-}"; do
    [ -n "$d" ] && rm -rf "$d"
  done
  return 0
}
trap cleanup EXIT

new_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "test"
  mkdir -p "$dir/supabase/migrations"
  printf -- '-- base migration\n' > "$dir/supabase/migrations/20260101000000_base.sql"
  git -C "$dir" add -A
  git -C "$dir" commit -q -m "base"
  echo "$dir"
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

add_migration() {
  local dir="$1" name="$2"
  printf -- '-- synthetic migration %s\n' "$name" > "$dir/supabase/migrations/$name.sql"
}

# run_case DIR EVENT_NAME BEFORE_SHA DRY_RUN_OUTPUT
# Populates: $LAST_EXIT $LAST_LOG
run_case() {
  local dir="$1" event="$2" before="$3" output="$4"
  local logfile
  logfile="$(mktemp)"
  set +e
  (
    cd "$dir" || exit 1
    export EVENT_NAME="$event"
    export BEFORE_SHA="$before"
    printf '%s\n' "$output" | bash "$SCRIPT"
  ) >"$logfile" 2>&1
  LAST_EXIT=$?
  set -e
  LAST_LOG="$(cat "$logfile")"
  rm -f "$logfile"
}

assert_exit() {
  assert_eq "$1" "$2" "$LAST_EXIT"
}

# The exact dry-run shape of the pinned CLI 2.116.0, migrated per case.
dry_run_header='DRY RUN: migrations will *not* be pushed to the database.
Connecting to remote database...'

dry_run_listing_one() {
  printf '%s\nWould push these migrations:\n • %s\n' "$dry_run_header" "$1"
}

# --- 1. Happy path: push added one migration, dry run lists exactly it -----

dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
add_migration "$dir" "20260102000000_new_feature"
commit "$dir" "add migration"
run_case "$dir" push "$before" "$(dry_run_listing_one 20260102000000_new_feature.sql)"
assert_exit "push added one, dry run lists it: exit 0" 0
assert_contains "happy path reports the match" "$LAST_LOG" "matches exactly"

# --- 2. Push added nothing, dry run up to date ------------------------------

dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
printf 'docs only\n' > "$dir/README.tmp"
commit "$dir" "unrelated change"
run_case "$dir" push "$before" "$dry_run_header
Remote database is up to date."
assert_exit "no new migrations + up to date: exit 0" 0

# --- 3. Multi-commit push: migration added in an EARLIER commit of the push -

dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
add_migration "$dir" "20260102000000_first"
commit "$dir" "first commit of the push adds a migration"
add_migration "$dir" "20260103000000_second"
commit "$dir" "second commit adds another"
run_case "$dir" push "$before" "$(dry_run_listing_one 20260102000000_first.sql)"
assert_exit "multi-commit push, second migration missing from dry run: exit non-zero" 1
assert_contains "multi-commit case names the missing file" "$LAST_LOG" "20260103000000_second.sql"
run_case "$dir" push "$before" "$dry_run_header
Would push these migrations:
 • 20260102000000_first.sql
 • 20260103000000_second.sql"
assert_exit "multi-commit push, both listed: exit 0" 0

# --- 4. Extra: dry run lists a migration this push did not add --------------
# The issue #163 drift case: production is behind the repo and an unrelated
# push would silently carry (or skip) the gap.

dir="$(new_repo)"; tmp_dirs+=("$dir")
add_migration "$dir" "20260105000000_gap"
commit "$dir" "a migration whose deploy run failed lands on main"
before="$(sha_of "$dir" HEAD)" # before is AFTER the gap landed
printf 'docs only\n' > "$dir/README.tmp"
commit "$dir" "unrelated push"
run_case "$dir" push "$before" "$dry_run_header
Would push these migrations:
 • 20260105000000_gap.sql"
assert_exit "pending-but-not-added (drift) fails" 1
assert_contains "drift case names the extra migration" "$LAST_LOG" "20260105000000_gap.sql"
assert_contains "drift case explains the failure mode" "$LAST_LOG" "previous deploy left production behind"

# --- 5. Missing: push added a migration the dry run does not list -----------

dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
add_migration "$dir" "20260106000000_applied_out_of_band"
commit "$dir" "add migration"
run_case "$dir" push "$before" "$dry_run_header
Remote database is up to date."
assert_exit "added-but-not-pending (applied out of band) fails" 1
assert_contains "out-of-band case names the missing migration" "$LAST_LOG" "20260106000000_applied_out_of_band.sql"

# --- 6. Modified (not added) migration must not be expected to re-apply ----
# The UNDO-note retrofit case (AGENTS.md Migration Flow item 10): a
# comment-only edit to an already-applied migration file.

dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
printf -- '-- base migration, now with an UNDO: note\n' > "$dir/supabase/migrations/20260101000000_base.sql"
commit "$dir" "comment-only retrofit"
run_case "$dir" push "$before" "$dry_run_header
Remote database is up to date."
assert_exit "comment-only retrofit of an applied migration: exit 0" 0

# --- 7. Parser robustness ----------------------------------------------------

# ANSI SGR bolding around the filename only (the CLI renders each line as
# ` • ` + bold(basename) -- the bullet itself is never inside the escape).
dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
add_migration "$dir" "20260107000000_ansi"
commit "$dir" "add migration"
run_case "$dir" push "$before" "$(printf '%s\nWould push these migrations:\n • \033[1m20260107000000_ansi.sql\033[0m\n' "$dry_run_header")"
assert_exit "ANSI-bolded bullet line parsed: exit 0" 0

# A seed section after the migration list must not be parsed as migrations.
dir="$(new_repo)"; tmp_dirs+=("$dir")
before="$(sha_of "$dir" HEAD)"
add_migration "$dir" "20260108000000_with_seed"
commit "$dir" "add migration"
run_case "$dir" push "$before" "$dry_run_header
Would push these migrations:
 • 20260108000000_with_seed.sql
Would seed these files:
 • supabase/seed.sql"
assert_exit "seed bullets not counted as migrations: exit 0" 0

# Header present but no bullet lines: format drift fails closed.
run_case "$dir" push "$before" "$dry_run_header
Would push these migrations:"
assert_exit "header without bullets (format drift) fails closed" 1
assert_contains "format-drift error names the pinned CLI version" "$LAST_LOG" "2.116.0"

# Output matching no known shape at all fails closed.
run_case "$dir" push "$before" "totally unexpected output"
assert_exit "unrecognized dry-run output fails closed" 1

# --- 8. Skips -----------------------------------------------------------------

# workflow_dispatch has no pushed range: never asserts, even on mismatch.
run_case "$dir" workflow_dispatch "" "$dry_run_header
Would push these migrations:
 • 20260109000000_dispatch_only.sql"
assert_exit "workflow_dispatch skips the assertion" 0
assert_contains "dispatch skip is a notice, not a warning" "$LAST_LOG" "::notice::"

# Empty before-SHA: warn and skip.
run_case "$dir" push "" "$dry_run_header
Would push these migrations:
 • 20260109000000_dispatch_only.sql"
assert_exit "empty before-SHA warns and skips" 0
assert_contains "empty before-SHA emits a warning" "$LAST_LOG" "::warning::"

# All-zero before-SHA (branch creation / rewritten history): warn and skip.
run_case "$dir" push "$ALL_ZERO_SHA" "$dry_run_header
Would push these migrations:
 • 20260109000000_dispatch_only.sql"
assert_exit "all-zero before-SHA warns and skips" 0

# before-commit not present locally (force-push): warn and skip.
run_case "$dir" push "1234567890123456789012345678901234567890" "$dry_run_header
Would push these migrations:
 • 20260109000000_dispatch_only.sql"
assert_exit "unresolvable before-SHA warns and skips" 0

print_summary "assert-pending-migrations.test.sh"
