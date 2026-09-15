#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/assert-pending-migrations.sh
#
# Issue #185: asserts that the migrations `supabase db push --dry-run` says
# it WOULD apply are exactly the migrations this push ADDED under
# supabase/migrations -- so the dry run stops being decorative output and
# starts failing the deploy before `db push` when the two disagree:
#
#   extra    (would apply, but this push did not add it) -- an earlier
#            merge's migration never actually reached production (its
#            deploy run failed or it was reverted), and stacking new
#            migrations on top of that gap would silently skip it. This is
#            exactly the drift issue #163 found in the wild.
#   missing  (this push added it, but the dry run does not list it) -- the
#            migration already exists on the project out-of-band (a manual
#            push, a Studio edit), so the repo's account of what production
#            runs has already diverged from reality.
#
# Mismatch in EITHER direction fails (exit 1). Unparseable dry-run output
# also fails -- never silently pass on a format the parser does not
# recognize.
#
# Inputs:
#   stdin      The captured combined stdout+stderr of
#              `supabase db push --dry-run`. The workflow's "List pending
#              migrations" step tees it into a file; this script never
#              invokes the CLI itself, so it is testable offline.
#   BEFORE_SHA github.event.before -- the previous tip of main before this
#              push. Added-file detection is `git diff --name-only
#              --diff-filter=A "$BEFORE_SHA" HEAD -- supabase/migrations`,
#              i.e. ADDED files only: a modified (e.g. comment-only UNDO
#              note, per AGENTS.md Migration Flow item 9) or deleted
#              migration is deliberately NOT expected to (re-)apply.
#   EVENT_NAME github.event_name. Only "push" asserts: a workflow_dispatch
#              re-run has no pushed range, and its whole purpose may be to
#              apply long-pending migrations -- asserting an empty range
#              against them would fail every deliberate manual retry.
#
# The dry-run output shape is pinned against the repo's pinned CLI version
# (2.116.0), verified in its source (apps/cli/src/legacy/shared/
# legacy-db-push-core.ts in supabase/cli at tag v2.116.0):
#
#   DRY RUN: migrations will *not* be pushed to the database.      (stderr)
#   Connecting to remote database...                               (stderr)
#   Would push these migrations:                                   (stderr)
#    • 20260101000000_example.sql                                  (stderr, bolded on a TTY)
#
# ...or, when nothing is pending, `Remote database is up to date.` on
# stdout. The bullet is U+2022 with one leading space; bolding is ANSI SGR
# and is stripped before parsing. If a future CLI changes the shape, the
# fail-closed branch below fires instead of a silent empty parse.
#
# Exit code: 0 on match (or a documented skip), 1 on any mismatch or
# unparseable input.

export LC_ALL=C
ALL_ZERO_SHA="0000000000000000000000000000000000000000"

# --- Parse the dry-run output into a sorted pending list -------------------

# Bash 3.2-safe ANSI SGR strip ($'...' quoting, not \x1b in the regex).
strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

dry_run="$(cat)"

pending_file="$(mktemp)"
expected_file="$(mktemp)"
trap 'rm -f "$pending_file" "$expected_file"' EXIT

normalized="$(printf '%s\n' "$dry_run" | strip_ansi)"

if printf '%s\n' "$normalized" | grep -q '^Would push these migrations:'; then
  # Everything from the migrations header to the seed header (absent when
  # there are no seeds -- then the range runs to EOF); keep only the
  # bullet lines, which carry the migration basename.
  printf '%s\n' "$normalized" \
    | sed -n '/^Would push these migrations:/,/^Would seed these files:/p' \
    | tail -n +2 \
    | sed -n '/^[[:space:]]*•[[:space:]]*/s/^[[:space:]]*•[[:space:]]*//p' \
    | sed '/^[[:space:]]*$/d' \
    | sort -u > "$pending_file"
  if [ ! -s "$pending_file" ]; then
    echo "::error::The dry-run output has a 'Would push these migrations:' header but no parseable bullet lines -- the pinned Supabase CLI (2.116.0) output format has likely changed. Update assert-pending-migrations.sh before pushing anything."
    exit 1
  fi
elif printf '%s\n' "$normalized" | grep -q 'is up to date\.'; then
  : > "$pending_file"
else
  echo "::error::The dry-run output matches no known shape (neither 'Would push these migrations:' nor 'is up to date.') -- refusing to assert blindly. Is this really the output of 'supabase db push --dry-run' from the pinned CLI 2.116.0?"
  exit 1
fi

# --- Resolve the expected list (migrations this push added) ----------------

if [ "${EVENT_NAME:-}" != "push" ]; then
  echo "::notice::Not a push event (${EVENT_NAME:-unknown}); skipping the dry-run-vs-added-migrations assertion. A manual dispatch has no pushed range to diff against."
  exit 0
fi

before="${BEFORE_SHA:-}"
if [ -z "$before" ]; then
  echo "::warning::github.event.before is empty; cannot determine what this push added. Skipping the dry-run-vs-added-migrations assertion (the destructive-statement scan below still runs)."
  exit 0
fi
if [ "$before" = "$ALL_ZERO_SHA" ]; then
  echo "::warning::github.event.before is the all-zero SHA (branch creation / rewritten history); cannot determine what this push added. Skipping the dry-run-vs-added-migrations assertion (the destructive-statement scan below still runs)."
  exit 0
fi
if ! git cat-file -e "${before}^{commit}" 2>/dev/null; then
  echo "::warning::before-commit $before is not present locally despite the full-history checkout; cannot determine what this push added. Skipping the dry-run-vs-added-migrations assertion (the destructive-statement scan below still runs)."
  exit 0
fi

# Added .sql files under supabase/migrations, basenames only: the dry-run
# list carries basenames, and every repo migration lives in that one
# directory. --diff-filter=A is the whole point -- a modified (UNDO-note
# retrofit) or deleted migration must not be expected to (re-)apply.
git diff --name-only --diff-filter=A "$before" HEAD -- supabase/migrations \
  | sed 's|.*/||' | sed -n '/\.sql$/p' | sort -u > "$expected_file" || {
    echo "::error::git diff against before-commit $before failed; cannot determine what this push added."
    exit 1
  }

# --- Compare ----------------------------------------------------------------

echo "Dry run says these migrations would be applied:"
sed 's/^/  • /' "$pending_file" || true
echo "This push added these migration files:"
sed 's/^/  + /' "$expected_file" || true

extra="$(comm -23 "$pending_file" "$expected_file")"
missing="$(comm -13 "$pending_file" "$expected_file")"

errors=0
if [ -n "$extra" ]; then
  echo "::error::The dry run would apply migration(s) this push did NOT add (they are pending against production but were not part of this change) -- a previous deploy left production behind. Resolve that first (re-run its failed supabase-migrate.yml run or investigate the gap); do not stack new migrations on top:"
  printf '%s\n' "$extra" | sed 's/^/  • /'
  errors=$((errors + 1))
fi
if [ -n "$missing" ]; then
  echo "::error::This push added migration file(s) the dry run does NOT list as pending -- they appear to already exist on the project out-of-band (manual push / Studio), so the repo's account of production has diverged. Investigate before pushing:"
  printf '%s\n' "$missing" | sed 's/^/  + /'
  errors=$((errors + 1))
fi

if [ "$errors" -eq 0 ]; then
  echo "Dry-run migration list matches exactly the migration files this push added."
fi

exit "$errors"
