#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-destructive-sql.sh
#
# Statement-aware destructive-SQL scan (LLA-109) over a migration file's SQL
# content on stdin. Exits 1 and prints one "REASON: statement text" line per
# offending statement when the SQL contains a real DROP TABLE statement, or
# an ALTER TABLE statement with a DROP COLUMN clause or a column type
# change (`... TYPE ...`); exits 0 silently when it finds none.
#
# Supersedes supabase-migrate.yml's former "Fail on a destructive statement
# in an unapplied migration" step, which ran a single `grep -E` over the
# file's raw lines and was simultaneously too permissive and too paranoid:
#
#   - too permissive (false negatives): grep matches one line at a time, so
#     a statement split across lines -- `DROP\n  TABLE foo;`, or a
#     multi-line `ALTER TABLE foo\n  ALTER COLUMN bar\n  TYPE text;` --
#     never has "drop"+"table" (or "alter table"+"type") on any single
#     line, and evaded the pattern entirely.
#   - too paranoid (false positives): the pattern matched the phrase "drop
#     table" or "alter table ... type" ANYWHERE in the file, including
#     inside a SQL comment (`-- do not drop table x`) and inside an
#     unrelated statement that merely contains the same words as a
#     sub-clause -- `ALTER PUBLICATION supabase_realtime DROP TABLE foo;`
#     removes a table from realtime replication; it does not touch the
#     table's data or schema at all, yet it matched.
#
# Fix: strip comments (`--` and `/* */`, including multi-line block
# comments) first, then join the remaining SQL into one line per statement
# (splitting on `;`, which also normalizes away line breaks inside a single
# statement -- fixing the multi-line false negatives above) before checking
# each statement's shape. A statement is destructive only when the SQL
# command it actually *is* -- its own first two words, not text found
# anywhere inside it -- is DROP TABLE, or is ALTER TABLE and it separately
# contains a DROP COLUMN clause or a `TYPE` column-type change. This fixes
# both false-positive shapes above: "alter publication" and "alter table"
# are different first-two-words, and stripped comments can no longer
# contribute any words at all.
#
# Still a text-pattern heuristic, not a real SQL parser or a query against
# the target tables' actual row counts (a string literal containing "--" or
# "/*" is not specially handled, the same limitation the original grep
# had, and a column literally named "type" can still false-positive an
# ALTER TABLE statement, same as before) -- it fails closed on the pattern
# either way, deliberately, same as before.

strip_comments() {
  awk '
    {
      line = $0
      out = ""
      while (1) {
        if (incomment) {
          close_at = index(line, "*/")
          if (close_at == 0) { line = ""; break }
          line = substr(line, close_at + 2)
          incomment = 0
          continue
        }
        dash_at = index(line, "--")
        block_at = index(line, "/*")
        if (dash_at == 0 && block_at == 0) {
          out = out line
          break
        }
        if (block_at > 0 && (dash_at == 0 || block_at < dash_at)) {
          out = out substr(line, 1, block_at - 1)
          line = substr(line, block_at + 2)
          incomment = 1
          continue
        }
        out = out substr(line, 1, dash_at - 1)
        line = ""
        break
      }
      print out
    }
  '
}

reasons=""

while IFS= read -r statement; do
  trimmed="$(printf '%s' "$statement" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -n "$trimmed" ] || continue
  lower="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
  first_two="$(printf '%s\n' "$lower" | awk '{print $1, $2}')"

  case "$first_two" in
    "drop table")
      reasons="${reasons}DROP TABLE: ${trimmed}"$'\n'
      ;;
    "alter table")
      if printf '%s\n' "$lower" | grep -Eq '(^|[^[:alnum:]_])drop[[:space:]]+column([^[:alnum:]_]|$)'; then
        reasons="${reasons}ALTER TABLE ... DROP COLUMN: ${trimmed}"$'\n'
      elif printf '%s\n' "$lower" | grep -Eq '(^|[^[:alnum:]_])type([^[:alnum:]_]|$)'; then
        reasons="${reasons}ALTER TABLE ... TYPE: ${trimmed}"$'\n'
      fi
      ;;
  esac
done < <(strip_comments | tr '\n' ' ' | tr ';' '\n')

if [ -n "$reasons" ]; then
  printf '%s' "$reasons"
  exit 1
fi

exit 0
