#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-apple-secrets.sh
#
# Issue #513: decides how supabase-migrate.yml's "migrate" job should get
# the delete-account function its four Apple secrets, without hard-failing
# the whole job just because they aren't set as GitHub `production`
# environment secrets. Those secrets ARE set on the Supabase project itself
# (delete-account has been live in production since v231, deployed
# out-of-band) -- the old step only ever checked the GitHub side and never
# consulted the project, so it failed every run.
#
# Inputs:
#   APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_CLIENT_ID / APPLE_PRIVATE_KEY
#     The GitHub `production` environment secrets of the same names, already
#     exported into the job env by the caller (unset/empty when not
#     configured -- never read from stdin or an argument).
#   stdin
#     The JSON `supabase secrets list --output json --project-ref ...`
#     prints -- an array of objects with (at least) a "name" field, one per
#     secret already set on the Supabase project. Only read when at least
#     one of the four env vars above is unset, so a run with all four
#     GitHub secrets present never needs a project API call at all (the
#     caller should skip invoking `supabase secrets list` in that case --
#     see the workflow step, which pipes it in only on that branch). Digests
#     only, per `supabase secrets list`'s own output shape -- never a value.
#
# Output contract:
#   All four env vars set                    -> stdout `mode=set`, exit 0.
#   Some/all unset, but all four NAMES are
#   present in the stdin JSON                 -> stdout `mode=reuse`, exit 0.
#   Some/all unset, and at least one of the
#   four names is ALSO absent from the
#   project                                   -> `::error::` (stderr) naming
#                                                 exactly which names are
#                                                 missing, exit 1, no stdout.
#   stdin is not valid JSON (or `jq` itself
#   is unavailable)                           -> `::error::` (stderr), exit 1.
#
# The caller captures stdout as the step's `mode` output and gates "Set
# delete-account function secrets" on `mode == 'set'` -- `mode=reuse` means
# the project's own secrets are trusted as-is and must not be overwritten by
# a partial GitHub-secret set. Any `::notice::` for the reuse case is left to
# the caller (this script's stdout must stay exactly one line on success, so
# `mode_line="$(...)"` captures cleanly).
#
# `--output json` here is the legacy per-command `-o`/`--output` flag
# (json/yaml/toml/table/csv/pretty/env), not the global `--output-format`
# flag -- confirmed against the pinned CLI's own source at tag v2.116.0
# (apps/cli/src/legacy/commands/secrets/list/list.handler.ts and
# .../secrets.format.ts in supabase/cli): each element is
# `{"name": ..., "updated_at": ..., "value": <digest>}`, alphabetically
# keyed, values are always digests (`secrets.format.ts`'s own DIGEST column
# uses the same "value" field) -- `supabase secrets list` never prints an
# actual secret value in any output mode.
#
# Bash 3.2 compatible (macOS CI runner, issue #569's release-guards-macos
# job): no associative arrays, no `${var,,}`, no `mapfile`.

REQUIRED_NAMES="APPLE_TEAM_ID APPLE_KEY_ID APPLE_CLIENT_ID APPLE_PRIVATE_KEY"

if [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_KEY_ID:-}" ] && [ -n "${APPLE_CLIENT_ID:-}" ] && [ -n "${APPLE_PRIVATE_KEY:-}" ]; then
  echo "mode=set"
  exit 0
fi

input="$(cat)"

if ! present_names="$(printf '%s' "$input" | jq -r '.[].name' 2>&1)"; then
  echo "::error::Could not parse \`supabase secrets list --output json\` output while checking for existing Apple secrets on the Supabase project. jq said:" >&2
  printf '%s\n' "$present_names" >&2
  exit 1
fi

missing=""
for name in $REQUIRED_NAMES; do
  if ! printf '%s\n' "$present_names" | grep -qx "$name"; then
    missing="$missing $name"
  fi
done

if [ -n "$missing" ]; then
  echo "::error::Not all Apple secrets are set on the \`production\` environment, and the following are ALSO missing from the Supabase project's own secrets (checked via \`supabase secrets list\`):${missing}. The delete-account function cannot revoke an Apple identity without them (Issue #17 KTD3) -- add the missing one(s) above either as GitHub \`production\` environment secrets or directly on the Supabase project (\`supabase secrets set NAME=value --project-ref ...\`), then re-run. See AGENTS.md's 'Config & Credential Locations' for where each value comes from. This only blocks deploying delete-account -- migrations for unrelated supabase/** changes already pushed successfully above." >&2
  exit 1
fi

echo "mode=reuse"
