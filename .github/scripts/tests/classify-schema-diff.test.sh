#!/usr/bin/env bash
set -euo pipefail

# Truth table for .github/scripts/classify-schema-diff.sh (issue #513). Run
# with:
#
#   bash .github/scripts/tests/classify-schema-diff.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/../classify-schema-diff.sh"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

run_case() {
  out="$(printf '%s' "$1" | bash "$SCRIPT" 2>&1)" && rc=0 || rc=$?
}

assert_noise() {
  local desc="$1" sql="$2"
  run_case "$sql"
  assert_eq "$desc (exit 0)" "0" "$rc"
  assert_eq "$desc (nothing printed)" "" "$out"
}

assert_real() {
  local desc="$1" sql="$2" expect_contains="$3"
  run_case "$sql"
  assert_eq "$desc (exit 1)" "1" "$rc"
  assert_contains "$desc (reports why)" "$out" "$expect_contains"
}

# --- an empty diff is a pass -------------------------------------------

assert_noise "empty input" ""

# --- known re-emission noise is silent and exits 0 ----------------------

assert_noise "a single unchanged CREATE OR REPLACE FUNCTION" \
  $'CREATE OR REPLACE FUNCTION public.foo()\n RETURNS void\n LANGUAGE plpgsql\nAS $function$\nbegin\n  perform 1;\nend;\n$function$\n;'

assert_noise "the check_function_bodies preamble alone" \
  'set check_function_bodies = off;'

assert_noise "the check_function_bodies preamble with SET local" \
  'SET local check_function_bodies = off;'

assert_noise "several functions plus the preamble together" \
  $'set check_function_bodies = off;\n\nCREATE OR REPLACE FUNCTION public.a()\n RETURNS void\n LANGUAGE sql\nAS $function$select 1;$function$\n;\n\nCREATE OR REPLACE FUNCTION public.b()\n RETURNS void\n LANGUAGE sql\nAS $function$select 2;$function$\n;'

assert_noise "a matched DROP TRIGGER / CREATE TRIGGER pair (migra's recreate shape)" \
  $'DROP TRIGGER "day_entries_after_update_enqueue_alerts" ON "public"."day_entries";\n\nCREATE OR REPLACE FUNCTION public.enqueue_caregiver_alerts()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\nbegin\n  return null;\nend;\n$function$\n;\n\nCREATE TRIGGER day_entries_after_update_enqueue_alerts AFTER UPDATE ON public.day_entries FOR EACH ROW EXECUTE FUNCTION public.enqueue_caregiver_alerts();'

assert_noise "a matched trigger pair with IF EXISTS on the drop" \
  $'DROP TRIGGER IF EXISTS "day_entries_after_update_enqueue_alerts" ON "public"."day_entries";\n\nCREATE TRIGGER day_entries_after_update_enqueue_alerts AFTER UPDATE ON public.day_entries FOR EACH ROW EXECUTE FUNCTION public.enqueue_caregiver_alerts();'

# --- an unpaired trigger statement is real drift, not noise -------------

assert_real "a DROP TRIGGER with no matching CREATE TRIGGER fails" \
  'DROP TRIGGER "day_entries_after_update_enqueue_alerts" ON "public"."day_entries";' \
  "REAL: DROP TRIGGER"

assert_real "a CREATE TRIGGER with no matching DROP TRIGGER fails" \
  'CREATE TRIGGER some_new_trigger AFTER INSERT ON public.day_entries FOR EACH ROW EXECUTE FUNCTION public.some_fn();' \
  "REAL: CREATE TRIGGER"

assert_real "a drop/create pair for two DIFFERENT trigger names is not treated as matched" \
  $'DROP TRIGGER "trigger_a" ON "public"."day_entries";\n\nCREATE TRIGGER trigger_b AFTER INSERT ON public.day_entries FOR EACH ROW EXECUTE FUNCTION public.fn();' \
  "REAL: DROP TRIGGER"

# --- the narrow pg_net shadow-image exception (issue #194, #513) ---------
# The local shadow image lacks pg_net, so the linked-vs-shadow diff carries a
# CREATE EXTENSION statement for it that the shadow cannot have -- image gap,
# not drift. Issue #194's relocation runbook (20260918120000 + docs/ops/
# supabase-go-live.md) moves the linked project's registration from public to
# extensions via the support-assisted catalog update, so BOTH exact shapes
# are the known gap: `with schema public` before the runbook lands,
# `with schema extensions` after. Anything else still fails.

assert_noise "CREATE EXTENSION pg_net WITH SCHEMA public, quoted, is one allowed shape" \
  'create extension if not exists "pg_net" with schema "public";'

assert_noise "the public form unquoted and re-cased still matches" \
  'CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA public;'

assert_noise "CREATE EXTENSION pg_net WITH SCHEMA extensions (the post-runbook shape) is the other allowed shape" \
  'create extension if not exists "pg_net" with schema "extensions";'

assert_noise "the extensions form unquoted and re-cased still matches" \
  'CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA EXTENSIONS;'

assert_real "pg_cron is NOT covered by the pg_net exception" \
  'create extension if not exists "pg_cron" with schema "public";' \
  "REAL: create extension"

assert_real "pg_net in a schema other than public/extensions is NOT covered" \
  'create extension if not exists "pg_net" with schema "net";' \
  "REAL: create extension"

# --- any other statement type is real schema drift and fails closed -----

assert_real "a synthetic ALTER TABLE ADD COLUMN is caught" \
  'ALTER TABLE public.day_entries ADD COLUMN new_col text;' \
  "REAL: ALTER TABLE public.day_entries ADD COLUMN"

assert_real "a synthetic CREATE EXTENSION for an unrelated extension is caught" \
  'create extension if not exists "uuid-ossp" with schema "public";' \
  "REAL: create extension"

assert_real "a synthetic DROP TABLE is caught" \
  'DROP TABLE public.widgets;' \
  "REAL: DROP TABLE"

assert_real "a synthetic GRANT is caught" \
  'GRANT SELECT ON public.day_entries TO authenticated;' \
  "REAL: GRANT"

assert_real "a synthetic CREATE POLICY is caught" \
  'CREATE POLICY foo ON public.day_entries FOR SELECT USING (true);' \
  "REAL: CREATE POLICY"

# --- a semicolon inside a function body never ends the statement early --

assert_noise "a function body containing its own semicolons stays one statement" \
  $'CREATE OR REPLACE FUNCTION public.multi()\n RETURNS void\n LANGUAGE plpgsql\nAS $function$\ndeclare\n  v_x int;\nbegin\n  v_x := 1;\n  perform v_x;\nend;\n$function$\n;'

# --- noise and real statements mixed: noise is silent, real still fails -

assert_real "unchanged functions plus one real ALTER TABLE: only the real one is reported" \
  $'set check_function_bodies = off;\n\nCREATE OR REPLACE FUNCTION public.a()\n RETURNS void\n LANGUAGE sql\nAS $function$select 1;$function$\n;\n\nALTER TABLE public.day_entries ADD COLUMN new_col text;' \
  "REAL: ALTER TABLE"

print_summary "classify-schema-diff.test.sh"
