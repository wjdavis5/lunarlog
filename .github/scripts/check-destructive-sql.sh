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
# Strings, quoted identifiers, and dollar-quoted bodies are opaque (issue
# #1833): the stripper walks each line as characters and tracks a
# single-quoted string (with `''` doubling and `E'...'`/`U&'...'` backslash
# escapes), a double-quoted identifier (with `""` doubling), a dollar-quoted
# body (`$tag$...$tag$`, including `$$`), and a block comment (nestable, as
# Postgres allows). The content of those regions is dropped rather than
# printed, so a `--` inside a literal no longer truncates the line, a `;`
# inside one no longer splits a statement, and a "DROP TABLE" inside one is
# not a statement at all. This is still a text-pattern heuristic, not a
# parser: a column literally named "type" can still false-positive an ALTER
# TABLE statement, and a string form the walker does not know (an exotic
# escape syntax) can desync it for the rest of the file, so the review step
# stays a human's, not the script's.

# The character walker (issue #1833). States persist across lines: in_single
# with esc (an E'...'/U&'...' string), in_double, dollar (the open tag), and
# in_block (the nesting depth). Only code characters reach `out`; every
# quoted or commented region is dropped.
strip_comments() {
  awk '
    BEGIN { in_block = 0; in_single = 0; esc = 0; in_double = 0; dollar = ""; sq = "\047"; dq = "\042" }
    {
      line = $0
      out = ""
      i = 1
      n = length(line)
      while (i <= n) {
        if (in_block > 0) {
          two = substr(line, i, 2)
          if (two == "*/") { in_block--; i += 2; continue }
          if (two == "/*") { in_block++; i += 2; continue }
          i++
          continue
        }
        if (in_single) {
          c = substr(line, i, 1)
          if (esc && c == "\134") { i += 2; continue }
          if (c == sq) {
            if (substr(line, i + 1, 1) == sq) { i += 2; continue }
            in_single = 0
            esc = 0
          }
          i++
          continue
        }
        if (in_double) {
          if (substr(line, i, 1) == dq) {
            if (substr(line, i + 1, 1) == dq) { i += 2; continue }
            in_double = 0
          }
          i++
          continue
        }
        if (dollar != "") {
          if (substr(line, i, length(dollar)) == dollar) { i += length(dollar); dollar = ""; continue }
          i++
          continue
        }
        two = substr(line, i, 2)
        if (two == "--") break
        if (two == "/*") { in_block = 1; i += 2; continue }
        c = substr(line, i, 1)
        if (c == sq) { in_single = 1; i++; continue }
        if ((c == "E" || c == "e") && substr(line, i + 1, 1) == sq) { in_single = 1; esc = 1; i += 2; continue }
        if ((c == "U" || c == "u") && substr(line, i + 1, 1) == "&" && substr(line, i + 2, 1) == sq) {
          in_single = 1
          esc = 1
          i += 3
          continue
        }
        if (c == dq) { in_double = 1; i++; continue }
        if (c == "$") {
          rest = substr(line, i)
          if (match(rest, /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/)) {
            dollar = substr(rest, 1, RLENGTH)
            i += RLENGTH
            continue
          }
        }
        out = out c
        i++
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
# The trailing `printf '\n'` (issue #1833): a final statement with no `;`
# would otherwise be dropped, because `read` at EOF without a trailing
# newline returns nonzero and skips the loop body.
done < <(strip_comments | tr '\n' ' ' | tr ';' '\n'; printf '\n')

if [ -n "$reasons" ]; then
  printf '%s' "$reasons"
  exit 1
fi

exit 0
