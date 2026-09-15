#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-pitr-gate.sh
#
# Issue #185: fail-closed gate asserting the human operator has confirmed
# that point-in-time recovery (PITR)/backups are enabled on the production
# Supabase project, BEFORE supabase-migrate.yml's `db push` step runs
# against real family data. Migrations are forward-only here (AGENTS.md's
# Migration Flow; "never edit a merged migration in place"), so a bad
# row-rewriting migration has no in-place recovery -- PITR is the only
# undo, and it must be known-good before the push, not discovered missing
# after an incident.
#
# The Supabase CLI can query the Management API for backup status, but a
# workflow cannot tell "PITR is on" from "PITR is on AND a human accepted
# what that means for this project" -- so this follows the repo's gate
# convention instead: a fail-closed read of a GitHub repository variable,
# exactly like RELEASE_GATE_ACCOUNT_DELETION (check-release-gate.sh) and
# PLAY_HEALTH_DECLARATION_CONFIRMED (play-store-release.yml).
#
# SUPABASE_PITR_CONFIRMED=true is a ONE-TIME OPERATOR ACTION: verify the
# dashboard setting (Supabase dashboard -> Project Settings -> Database ->
# Backups; daily backups and PITR are paid-tier add-ons), cross it off
# docs/ops/supabase-go-live.md's checklist (issue #18), then set the
# variable in GitHub (Settings -> Secrets and variables -> Actions ->
# Variables). It is NOT a value a coordinator, agent, PR, or any other
# automation should ever set or flip -- flipping it is a deliberate human
# release action, same category as flipping RELEASE_GATE_ACCOUNT_DELETION.
#
# Inputs (env):
#   SUPABASE_PITR_CONFIRMED  Must equal "true" (case and
#                            surrounding-whitespace tolerant) to open the
#                            gate. Anything else -- including unset or
#                            empty -- is closed. Closed is the default:
#                            fail closed.
#
# Exit code: 0 when the gate is open, non-zero otherwise. The caller
# (supabase-migrate.yml's migrate job) runs this BEFORE `supabase db push`,
# so a non-zero exit skips the push and every later deploy step (the two
# post-deploy gates still run -- they are read-only and independently
# gated on `supabase link` succeeding).
#
# Output: a `gate_open=true|false` line appended to $GITHUB_OUTPUT (when
# set), mirroring check-release-gate.sh, so a future warn-mode caller can
# read the gate's own state without re-deriving it.

GATE_MESSAGE="PITR gate closed: production migration pushes are blocked until point-in-time recovery (PITR)/backups are confirmed on the Supabase project (issue #185). This is a one-time OPERATOR confirmation of a dashboard setting -- never set this variable from automation, a coordinator, or a PR. Remediation, in order: (1) verify backups/PITR on the Supabase dashboard (Project Settings -> Database -> Backups; daily backup and PITR are paid-tier add-ons), following docs/ops/supabase-go-live.md's checklist and issue #18; (2) as the repository owner, set the SUPABASE_PITR_CONFIRMED repository variable to 'true' (Settings -> Secrets and variables -> Actions -> Variables). Until then every supabase-migrate.yml run fails here, before db push touches the database."

value="${SUPABASE_PITR_CONFIRMED:-}"
trimmed="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
# `tr`, not bash 4's ${trimmed,,}: this repo's scripts must also survive
# macOS runners' frozen Bash 3.2 (see check-release-gate.sh's note and CI's
# release-guards-macos job).
lowered="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

if [ "$lowered" = "true" ]; then
  echo "PITR gate open (SUPABASE_PITR_CONFIRMED=true): the operator has confirmed backups/PITR on the production project."
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "gate_open=true" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

echo "::error::$GATE_MESSAGE"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "gate_open=false" >> "$GITHUB_OUTPUT"
fi
exit 1
