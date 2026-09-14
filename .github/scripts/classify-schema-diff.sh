#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/classify-schema-diff.sh (issue #513)
#
# Splits a `supabase db diff --use-migra` SQL body (stdin) into top-level
# statements, dollar-quote aware (a `;` inside a $tag$ ... $tag$ function
# body never ends a statement), and classifies each. Known re-emission
# noise -- CREATE OR REPLACE FUNCTION, the `check_function_bodies = off`
# preamble, a DROP TRIGGER / CREATE TRIGGER pair sharing one name, and
# exactly `CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public` (see
# is_shadow_missing_pg_net below) -- is silent. Every other statement is
# printed (prefixed "REAL:") and the script exits 1: fail closed on
# anything not on that allow-list.

awk '
function trim(s) {
  gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s)
  return s
}
function trigger_name(stmt,    tmp, parts, count) {
  tmp = stmt
  gsub(/"/, "", tmp)
  count = split(tmp, parts, /[ \t]+/)
  if (tolower(parts[1]) == "drop") {
    if (tolower(parts[3]) == "if") return parts[5]
    return parts[3]
  }
  return parts[3]
}
# Issue #194 will move pg_net out of public; until then this one exact
# statement is the local shadow image lacking pg_net, not real drift --
# unquoted, quoted, or case-varied, but ONLY this extension in ONLY this
# schema. Anything else (pg_cron, a different schema, ...) still fails.
# Issue #194 own PR deferred the actual relocation (production pg_net is
# supabase_admin-owned and confirmed non-relocatable -- see that migration
# and supabase-migrate.yml advisor-gate step for the full rationale, and
# check-advisor-gate.sh for how the advisor finding itself is handled
# instead), so pg_net is expected to still be in `public` on every project
# this reaches for the foreseeable future -- this exception is not stale,
# just still pending its own follow-up.
function is_shadow_missing_pg_net(stmt,    t) {
  t = tolower(stmt)
  gsub(/"/, "", t)
  gsub(/[ \t\r\n]+/, " ", t)
  gsub(/^ +| +$/, "", t)
  sub(/;$/, "", t)
  return (t == "create extension if not exists pg_net with schema public") ? 1 : 0
}
BEGIN { n = 0; buf = ""; in_dollar = 0; tag = "" }
{
  line = $0
  sub(/\r$/, "", line)
  buf = buf line "\n"
  if (in_dollar) {
    close_at = index(line, tag)
    if (close_at == 0) next
    in_dollar = 0
    tail = substr(line, close_at + length(tag))
  } else if (match(line, /\$[A-Za-z_]*\$/)) {
    tag = substr(line, RSTART, RLENGTH)
    tail = substr(line, RSTART + RLENGTH)
    # A trivial one-line body ("AS $function$select 1;$function$") opens
    # and closes the same tag on one line -- only stay "in dollar" mode
    # when the closing tag is not also already on this line.
    in_dollar = (index(tail, tag) > 0) ? 0 : 1
    if (in_dollar) next
    tail = substr(tail, index(tail, tag) + length(tag))
  } else {
    tail = line
  }
  if (trim(tail) ~ /;$/) {
    n++
    stmt[n] = buf
    buf = ""
  }
}
END {
  if (trim(buf) != "") { n++; stmt[n] = buf }

  for (i = 1; i <= n; i++) {
    s = trim(stmt[i])
    ls = tolower(s)
    if (ls ~ /^drop trigger/) dropped[trigger_name(s)] = 1
    else if (ls ~ /^create trigger/) created[trigger_name(s)] = 1
  }

  real_count = 0
  for (i = 1; i <= n; i++) {
    s = trim(stmt[i])
    if (s == "") continue
    ls = tolower(s)
    if (ls ~ /^create or replace function/) continue
    if (ls ~ /^set( local)?[ \t]+check_function_bodies[ \t]*=[ \t]*off;?$/) continue
    if (is_shadow_missing_pg_net(s)) continue
    if (ls ~ /^drop trigger/ && (trigger_name(s) in created)) continue
    if (ls ~ /^create trigger/ && (trigger_name(s) in dropped)) continue
    real_count++
    print "REAL: " s
  }
  exit (real_count > 0) ? 1 : 0
}
'
