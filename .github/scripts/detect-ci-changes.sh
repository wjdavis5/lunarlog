#!/usr/bin/env bash
# .github/scripts/detect-ci-changes.sh
#
# Analyzes changed files in this monorepo to determine which CI job suites
# need to execute:
#   - app_flutter: Flutter app, mobile builds (Android/iOS), web client, Flutter tests
#   - database: Supabase migrations, RLS, pgTAP tests, schema types
#   - edge_functions: Supabase Edge Functions & Cloudflare Workers (web/links, web/email)
#   - release_guards: CI scripts, workflows, and release gate checks
#   - webapp: the React web client (webapp/, issue #1249) — its own tree,
#     the schema snapshot it imports, and the arb its message catalogue is
#     generated from
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
  emit_output "webapp" "true"
  exit 0
fi

echo "Evaluating changed files in monorepo:"
echo "$changed_files" | sed 's/^/  /'

app_flutter=false
database=false
edge_functions=false
release_guards=false
webapp=false

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
      webapp=true
      ;;

    # Database migration workflows -> run release guards and database tests
    .github/workflows/supabase-migrate.yml|.github/workflows/migration-gate.yml)
      database=true
      release_guards=true
      ;;

    # Release workflows verified by Dart release tests (sentry_symbols_test.dart)
    .github/workflows/ios-release.yml|.github/workflows/play-store-release.yml|.github/scripts/upload-sentry-symbols-setup.sh)
      app_flutter=true
      release_guards=true
      ;;

    # Release guard scripts, tool coordinators, or other workflow files
    .github/workflows/*|.github/scripts/*|tool/coord/*|tool/orchestrator/*)
      release_guards=true
      ;;

    # Edge Functions (also checked by Flutter branding tests in test/release/branding_identity_test.dart)
    supabase/functions/*)
      edge_functions=true
      app_flutter=true
      ;;

    # Cloudflare Workers
    site/*|workers/*|web/email/*|web/links/*)
      edge_functions=true
      ;;

    # The web data layer (issue #1252): typed against the schema snapshot
    # and integration-tested against the live local stack, so its changes
    # run the database suite too — the same coupling as
    # supabase/database.types.ts below.
    webapp/src/lib/*|webapp/test/integration/*)
      webapp=true
      database=true
      ;;

    # The React web client (issue #1249): its own suite only — the app's
    # Flutter suites do not cover it.
    webapp/*)
      webapp=true
      ;;

    # The message catalogue's source feeds both the webapp's generated
    # copy and the Flutter app's localizations.
    lib/l10n/app_en.arb)
      webapp=true
      app_flutter=true
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

    # Database migrations and pgTAP tests:
    # Also read by Dart release tests (test/release/pgtap_counts_test.dart)
    supabase/migrations/*|supabase/tests/*)
      database=true
      app_flutter=true
      ;;

    # Local supabase config & generated schema snapshot (the latter is also
    # the webapp client's types source, issue #1249)
    supabase/config.toml|supabase/database.types.ts)
      database=true
      webapp=true
      ;;

    # Guard inputs read by Dart release/boundary tests:
    #   - AGENTS.md (read by test/release/pgtap_counts_test.dart)
    #   - docs/product/voice-and-copy.md (read by test/release/branding_identity_test.dart)
    #   - docs/links/* and site/public/* (read by test/domain/sharing/link_artifacts_test.dart)
    AGENTS.md|docs/product/voice-and-copy.md|docs/links/*|site/public/*)
      app_flutter=true
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
emit_output "webapp" "$webapp"
