#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/check-destructive-sql.sh (LLA-109). Run
# with:
#
#   bash .github/scripts/tests/check-destructive-sql.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../check-destructive-sql.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

# Runs the script over $1 and captures both its exit code and stdout, so
# each case can assert on whichever (or both) it cares about.
run_case() {
  out="$(printf '%s' "$1" | bash "$SCRIPT" 2>&1)" && rc=0 || rc=$?
}

assert_safe() {
  local desc="$1" sql="$2"
  run_case "$sql"
  assert_eq "$desc (exit 0)" "0" "$rc"
}

assert_destructive() {
  local desc="$1" sql="$2" expect_contains="$3"
  run_case "$sql"
  assert_eq "$desc (exit 1)" "1" "$rc"
  assert_contains "$desc (reports why)" "$out" "$expect_contains"
}

# --- ordinary, non-destructive migrations pass cleanly ---------------------

assert_safe "a plain CREATE TABLE is not flagged" \
  'CREATE TABLE public.widgets (id uuid PRIMARY KEY, name text NOT NULL);'

assert_safe "ADD COLUMN is not flagged" \
  'ALTER TABLE public.widgets ADD COLUMN color text;'

assert_safe "an INSERT/UPDATE migration is not flagged" \
  $'INSERT INTO public.settings (key, value) VALUES (\'foo\', \'bar\');\nUPDATE public.settings SET value = \'baz\' WHERE key = \'foo\';'

# --- real destructive statements are still caught ---------------------------

assert_destructive "a plain DROP TABLE is caught" \
  'DROP TABLE public.widgets;' \
  "DROP TABLE"

assert_destructive "DROP TABLE IF EXISTS is still caught" \
  'DROP TABLE IF EXISTS public.widgets;' \
  "DROP TABLE"

assert_destructive "ALTER TABLE ... DROP COLUMN is still caught" \
  'ALTER TABLE public.widgets DROP COLUMN color;' \
  "DROP COLUMN"

assert_destructive "ALTER TABLE ... ALTER COLUMN ... TYPE is still caught" \
  'ALTER TABLE public.widgets ALTER COLUMN id TYPE bigint;' \
  "TYPE"

# --- LLA-109 false-negative fixes: statements split across lines -----------

assert_destructive "DROP / TABLE split across lines is now caught" \
  $'DROP\n  TABLE public.widgets;' \
  "DROP TABLE"

assert_destructive "a multi-line ALTER ... TYPE is now caught" \
  $'ALTER TABLE public.widgets\n  ALTER COLUMN id\n  TYPE bigint;' \
  "TYPE"

# --- LLA-109 false-positive fixes -------------------------------------------

assert_safe "ALTER PUBLICATION ... DROP TABLE is no longer a false positive" \
  'ALTER PUBLICATION supabase_realtime DROP TABLE public.widgets;'

assert_safe "a line comment mentioning DROP TABLE is no longer a false positive" \
  $'-- do not DROP TABLE widgets, see issue #1\nSELECT 1;'

assert_safe "a block comment mentioning DROP TABLE is no longer a false positive" \
  $'/* DROP TABLE widgets -- historical note */\nSELECT 1;'

assert_safe "a multi-line block comment mentioning DROP TABLE is no longer a false positive" \
  $'/*\n DROP TABLE widgets\n*/\nSELECT 1;'

# --- a destructive statement among several is still caught ------------------

assert_destructive "a destructive statement later in a multi-statement file is caught" \
  $'CREATE TABLE public.a (id int);\nDROP TABLE public.b;' \
  "DROP TABLE"

print_summary "check-destructive-sql.test.sh"
