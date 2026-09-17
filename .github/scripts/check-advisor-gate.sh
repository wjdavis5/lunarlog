#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-advisor-gate.sh (issue #454)
#
# Reads `supabase db advisors --type security --level warn --output-format
# json` (stdin) and fails (exit 1, listing what remains) on any finding, at
# WARN level or above, after excluding exactly three narrow, named cases --
# every other finding, INCLUDING a lint name this script has never seen
# before, still fails closed:
#
#   * authenticated_security_definer_function_executable -- by design,
#     covers the intentional ~30-RPC set (the whole point of that API is
#     to be called by `authenticated`). Excluded regardless of which
#     function it names.
#   * extension_in_public, but ONLY when metadata.name is exactly pg_net --
#     issue #194's pg_net relocation is runbook-gated, not migration-solved:
#     production's pg_net is supabase_admin-owned and non-relocatable
#     (`alter extension ... set schema` fails, confirmed locally, SQLSTATE
#     0A000; and even with extrelocatable flipped as superuser it fails on
#     pg_net's members living in `net`, not the registered schema -- see
#     20260918120000_pg_net_public_placement_guard.sql's header), and its
#     `net` schema ACL was granted by supabase_admin to postgres, anon,
#     authenticated, service_role, and supabase_functions_admin. A `drop
#     extension pg_net` inside an unattended migration risks two ways to
#     make things worse than leaving it alone: the `postgres` role may not
#     be permitted to drop a supabase_admin-owned extension at all (a
#     failed migration blocks every migration after it), and even a
#     successful recreate is not guaranteed to restore every one of those
#     Supabase-managed grants, which push dispatch depends on. The supported
#     path is the support-assisted catalog update in docs/ops/
#     supabase-go-live.md's "pg_net relocation runbook (issue #194)" (landed
#     with 20260918120000). This exclusion SELF-RETIRES: once the runbook
#     lands on the linked project the advisor stops emitting the finding
#     entirely, so the exclusion stops matching and can then be deleted.
#     ANY OTHER extension_in_public finding (a different extension, or
#     pg_net misreported under some other metadata shape) still fails.
#   * auth_leaked_password_protection -- a dashboard-only Auth setting
#     (Supabase dashboard: Authentication -> Policies), confirmed OFF in
#     production as of this PR, and already on the owner's manual
#     post-deploy auth checklist (issue #694). Remove this exclusion once
#     that checklist item is done -- this script cannot check or flip a
#     dashboard setting itself.
#
# Separately from those three, any finding whose level is exactly INFO
# (case-insensitive) is also dropped, regardless of its name -- production
# carries 7 by-design INFO-level rls_enabled_no_policy findings (RLS
# enabled with no policy, on purpose, for service-only tables) that this
# gate was never meant to fail on. The workflow step already passes
# `--level warn` to `db advisors` so the CLI omits INFO findings before
# they even reach this script; the level check here is defense in depth
# for the same input shape regardless of how it arrived (a future
# workflow change that drops `--level warn`, a `--type all` invocation,
# a CLI behavior change), not a second, independent gate. A finding with
# no `level` field, or an unrecognised level string (anything other than
# an exact case-insensitive match on "INFO"), is treated as NOT info --
# i.e. it is kept and can still fail the gate. Only WARN, ERROR, and this
# one INFO carve-out are ever excluded by level; nothing is ever
# excluded by level alone unless it is unambiguously INFO.
#
# Malformed input (invalid JSON, or a `results` field that is missing or
# not an array) is a hard failure, not a silent pass -- explicitly checked
# below rather than left to `set -e` alone, matching this repo's other
# stdin-JSON gate scripts (see check-apple-secrets.sh).
#
# Bash 3.2 compatible (macOS CI runner, issue #569's release-guards-macos
# job): no associative arrays, no `${var,,}`, no `mapfile`.

input="$(cat)"

if ! remaining="$(printf '%s' "$input" | jq -c '
  if (.results | type) != "array" then
    error("advisor JSON has no results array")
  else
    [.results[]
      | select(
          (.name == "authenticated_security_definer_function_executable")
          or (.name == "extension_in_public" and .metadata.name == "pg_net")
          or (.name == "auth_leaked_password_protection")
          or (((.level // "") | tostring | ascii_upcase) == "INFO")
          | not
        )
    ]
  end
' 2>&1)"; then
  echo "::error::Could not parse \`supabase db advisors --output-format json\` output (or it had no \`results\` array). jq said:" >&2
  printf '%s\n' "$remaining" >&2
  exit 1
fi

count="$(printf '%s' "$remaining" | jq 'length')"

if [ "$count" -gt 0 ]; then
  echo "::error::$count security advisor finding(s) at warn level or above, after the documented exclusions (issue #454):" >&2
  printf '%s' "$remaining" | jq -r '.[] | "- " + .name + ": " + .detail' >&2
  exit 1
fi

echo "Database advisor gate passed: no security finding at warn level or above, aside from the documented exclusions (issue #454)."
