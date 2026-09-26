#!/usr/bin/env bash
# .github/scripts/detect-ci-changes.sh
#
# Analyzes changed files in this monorepo to determine which CI job suites
# need to execute:
#   - app_flutter: Flutter app, mobile builds (Android/iOS), web client, Flutter tests
#   - database: Supabase migrations, RLS, pgTAP tests, schema types
#   - edge_functions: Supabase Edge Functions & Cloudflare Workers (web/links, web/email)
#   - release_guards: CI scripts, workflows, and release gate checks
#
# Emits outputs to $GITHUB_OUTPUT (or prints to stdout when unset).
#
# Inputs (env):
#   EVENT_NAME               github.event_name (e.g. "pull_request", "push", "merge_group")
#   BASE_REF                 github.base_ref (e.g. "main")
#   BEFORE_SHA               github.event.before (may be empty or all-zeros on push)
#   CHANGED_FILES_OVERRIDE   Newline-separated list of file paths (used for tests)
set -euo pipefail

EVENT_NAME="${EVENT_NAME:-}"
BASE_REF="${BASE_REF:-main}"
BEFORE_SHA="${BEFORE_SHA:-}"
ALL_ZERO_SHA="0000000000000000000000000000000000000000"

emit_output() {
  local key="$1"
  local val="$2"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$key=$val" >> "$GITHUB_OUTPUT"
  fi
  echo "$key=$val"
}

# 1. Resolve changed files list
changed_files=""

if [ -n "${CHANGED_FILES_OVERRIDE:-}" ]; then
  changed_files="$CHANGED_FILES_OVERRIDE"
elif [ "$EVENT_NAME" = "pull_request" ]; then
  # Try merge-base with origin base ref, fallback to base ref
  target_ref="origin/${BASE_REF}"
  if ! git rev-parse --verify "$target_ref" >/dev/null 2>&1; then
    target_ref="${BASE_REF}"
  fi
  if git rev-parse --verify "$target_ref" >/dev/null 2>&1; then
    base_sha="$(git merge-base HEAD "$target_ref" 2>/dev/null || echo "$target_ref")"
    changed_files="$(git diff --name-only "$base_sha"...HEAD 2>/dev/null || true)"
  fi
elif [ "$EVENT_NAME" = "push" ]; then
  if [ -n "$BEFORE_SHA" ] && [ "$BEFORE_SHA" != "$ALL_ZERO_SHA" ] && git cat-file -e "$BEFORE_SHA" >/dev/null 2>&1; then
    changed_files="$(git diff --name-only "$BEFORE_SHA" HEAD 2>/dev/null || true)"
  else
    changed_files="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
  fi
elif [ "$EVENT_NAME" = "merge_group" ]; then
  base_sha="$(git merge-base HEAD "origin/main" 2>/dev/null || echo "HEAD~1")"
  changed_files="$(git diff --name-only "$base_sha"...HEAD 2>/dev/null || true)"
else
  # Manual run or local run: check diff against origin/main or HEAD~1
  if git rev-parse --verify "origin/main" >/dev/null 2>&1; then
    base_sha="$(git merge-base HEAD "origin/main" 2>/dev/null || echo "origin/main")"
    changed_files="$(git diff --name-only "$base_sha"...HEAD 2>/dev/null || true)"
  else
    changed_files="$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
  fi
fi

# If changed_files could not be evaluated (e.g. shallow clone or initial commit),
# fail-safe: run all suites.
if [ -z "$changed_files" ]; then
  echo "::notice::Could not determine changed files; defaulting all CI suites to true."
  emit_output "app_flutter" "true"
  emit_output "database" "true"
  emit_output "edge_functions" "true"
  emit_output "release_guards" "true"
  exit 0
fi

echo "Evaluating changed files in monorepo:"
echo "$changed_files" | sed 's/^/  /'

app_flutter=false
database=false
edge_functions=false
release_guards=false

# 2. Classify changed files
while IFS= read -r file; do
  [ -z "$file" ] && continue

  case "$file" in
    # CI workflow definition or change detection script itself changed -> run everything
    .github/workflows/ci.yml|.github/scripts/detect-ci-changes.sh)
      app_flutter=true
      database=true
      edge_functions=true
      release_guards=true
      ;;

    # Release guard scripts, tool coordinators, or other workflow files
    .github/workflows/*|.github/scripts/*|tool/coord/*|tool/orchestrator/*)
      release_guards=true
      ;;

    # Cloudflare Workers and Deno Edge Functions
    site/*|workers/*|web/email/*|web/links/*|supabase/functions/*)
      edge_functions=true
      ;;

    # Standalone marketing site or static marketing pages
    marketing/*)
      # Independent marketing assets do not affect app, database, or functions
      ;;

    # Sync bridge code: exercises both Flutter client and Supabase sync_push / local db round-trip
    lib/data/sync/*|test/data/sync/*)
      app_flutter=true
      database=true
      ;;

    # Database: migrations, pgTAP SQL tests, local supabase config, generated schema snapshot
    supabase/migrations/*|supabase/tests/*|supabase/config.toml|supabase/database.types.ts|.github/workflows/supabase-migrate.yml|.github/workflows/migration-gate.yml)
      database=true
      ;;

    # Core Flutter application: Dart code, tests, integration tests, assets, Flutter web client, native Android & iOS
    lib/*|test/*|integration_test/*|android/*|ios/*|assets/*|pubspec.*|analysis_options.yaml|l10n.yaml|dart_defines*|web/*|tool/web_smoke/*|tool/quality/*|tool/quality_gate.dart)
      app_flutter=true
      ;;

    # Documentation, repo metadata, and editor/agent configs
    docs/*|*.md|LICENSE*|.gitignore|.agents/*|.aw/*|.vscode/*|.idea/*|.mcp.json)
      # Docs-only and metadata changes do not need any build/test suites
      ;;

    # Any unclassified file: safe fallback to app_flutter
    *)
      app_flutter=true
      ;;
  esac
done <<< "$changed_files"

echo "Detected suite requirements:"
emit_output "app_flutter" "$app_flutter"
emit_output "database" "$database"
emit_output "edge_functions" "$edge_functions"
emit_output "release_guards" "$release_guards"
