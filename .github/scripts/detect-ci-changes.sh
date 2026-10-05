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
#     the schema snapshot it imports, the arb its message catalogue is
#     generated from, and (issue #1251) the Dart domain the client compiles
#     to JavaScript (lib/domain/** + tool/web_domain/**: a domain change
#     rebuilds and re-parity-tests the web client; the domain itself and
#     the Dart pinning test keep the app_flutter suites too)
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

    # Release-guard suite inputs (issue #1344), matched before the generic
    # site/* arm below (which would otherwise swallow them for
    # edge_functions only): .github/scripts/tests/check-links-deploy.test.sh
    # reads site/package.json (its :18 -- the pinned astro/@lhci/cli/
    # axe-core versions and the `astro check` build gate) and
    # site/public/_headers (its :648 -- the CSP, HSTS, X-Frame-Options and
    # Permissions-Policy headers), so a breaking edit must run the
    # release-guards suites -- otherwise it merges green (release_guards=
    # false skips the suite) and the next unrelated .github/** PR goes red
    # on an assertion it never touched (issue #1317's failure class).
    site/package.json|site/public/_headers)
      edge_functions=true
      release_guards=true
      ;;

    # Hosted site assets read by test/domain/sharing/link_artifacts_test.dart.
    # Matched before the site/* arm below on purpose (issue #1344): that
    # arm's site/* alternative shadowed site/public/* here, so the
    # documented app_flutter=true never fired for a pure site/public/*
    # PR and link_artifacts_test.dart was skipped. edge_functions stays on
    # -- these assets ship with the Cloudflare site the generic arm covers.
    site/public/*)
      app_flutter=true
      edge_functions=true
      ;;

    # Site copy, claims ledger, and site tooling read by the Flutter suites
    # under test/site/ (issue #1368), matched before the generic site/* arm
    # below (which would otherwise swallow them for edge_functions only):
    #   - site_claims_test.dart reads site/claims.md (its setUpAll) and the
    #     site/src/pages/*.astro sources of its `pages` map with File();
    #   - store_pages_test.dart reads site/src/pages/delete-account.astro and
    #     support.astro, site/src/pages/sitemap.xml.ts,
    #     site/scripts/check-axe.mjs and site/lighthouserc.cjs the same way.
    # site.yml installs Flutter only to render screenshots and runs no
    # flutter test, so without app_flutter here a breaking site-copy edit
    # skips both suites, merges green, and the next unrelated Flutter PR
    # goes red on an assertion it never touched (issue #1317's failure
    # class). edge_functions stays on -- these files ship with the
    # Cloudflare site the generic arm covers.
    site/claims.md|site/src/*|site/scripts/*|site/lighthouserc.cjs)
      app_flutter=true
      edge_functions=true
      ;;

    # Cloudflare Workers (site/package.json, site/public/* and the
    # test/site/ reads above match earlier, with their extra suites)
    site/*|workers/*|web/email/*|web/links/*)
      edge_functions=true
      ;;

    # The web domain's TS schema snapshot and shared fixture file are also
    # read by the app's own test/domain/web_domain_fixtures_test.dart with
    # File('...') (issue #1368): a breaking edit used to classify
    # webapp-only, skip that Dart parity pin, merge green, and turn the
    # next unrelated Flutter PR red. Matched before the generic webapp arms
    # below, so webapp=true is restated here on purpose.
    webapp/src/domain/schemas.ts|webapp/test/domain/fixtures.json|webapp/worker/headers.ts)
      webapp=true
      app_flutter=true
      ;;

    # The web client's sign-in providers are read by the app's own
    # test/site/privacy_browser_error_reporting_test.dart with File('...'):
    # it pins PRIVACY.md's list of web sign-in methods to the OAuthProvider
    # type declared here. Same failure class as the arm above -- a provider
    # added or removed used to classify webapp+database only, skip that
    # Dart pin, merge green, and turn the next unrelated Flutter PR red.
    # Matched before the generic webapp/src/lib arm below, so webapp=true
    # and database=true are restated here on purpose.
    webapp/src/lib/auth.ts)
      webapp=true
      database=true
      app_flutter=true
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

    # The Dart domain the web client compiles to JavaScript (issue #1251):
    # a domain change (engine or facade/entrypoint) rebuilds the module and
    # reruns the web client's parity suite — and still runs the app's own
    # Flutter suites, which cover the domain and the Dart pinning test.
    lib/domain/*|tool/web_domain/*)
      webapp=true
      app_flutter=true
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

    # Local supabase config (issue #1367): ci.yml's release-guards job reads
    # it directly -- check-auth-config.sh (issue #266) defaults to
    # supabase/config.toml and pins the committed [auth] block -- so a
    # config-only PR must run the release-guard suites too. Without this,
    # such a PR merges green (release_guards=false skips the job) and the
    # next unrelated .github/** PR goes red on an assertion it never touched
    # (issue #1317's failure class). Split from the generated schema
    # snapshot's arm below, which no release guard reads.
    supabase/config.toml)
      database=true
      webapp=true
      release_guards=true
      ;;

    # Generated schema snapshot (also the webapp client's types source,
    # issue #1249)
    supabase/database.types.ts)
      database=true
      webapp=true
      ;;

    # Guard inputs read by Dart release/boundary tests:
    #   - AGENTS.md (read by test/release/pgtap_counts_test.dart)
    #   - docs/product/voice-and-copy.md (read by test/release/branding_identity_test.dart)
    #   - docs/links/* (read by test/domain/sharing/link_artifacts_test.dart)
    #   - PRIVACY.md (read by test/site/privacy_header_test.dart,
    #     privacy_background_gate_test.dart,
    #     privacy_browser_error_reporting_test.dart, site_claims_test.dart
    #     and store_pages_test.dart)
    #   - docs/ops/store-declarations.md (read by test/site/store_pages_test.dart)
    #   - docs/web/security-posture.md (read by
    #     test/site/privacy_browser_error_reporting_test.dart)
    # (site/public/* moved above the generic site/* arm -- issue #1344:
    #  the site/* alternative shadowed it here, so it never fired. The
    #  PRIVACY.md / store-declarations / security-posture entries are issue
    #  #1368: the docs/* and *.md arms below swallowed them the same way,
    #  so the test/site assertions pinning their content never ran on a
    #  docs-only PR.)
    AGENTS.md|PRIVACY.md|docs/product/voice-and-copy.md|docs/ops/store-declarations.md|docs/web/security-posture.md|docs/links/*)
      app_flutter=true
      ;;

    # Read by a release-guard suite (issue #1317):
    # .github/scripts/tests/ios-simulator-budgets.test.sh reads
    # integration_test/gate_test.dart and pins every testWidgets( call's
    # `timeout: _kTestTimeout` bound plus the bound's value, so a
    # gate_test-only change must run the release-guards suites too --
    # otherwise the budgets suite is skipped, a breaking gate_test edit
    # merges green, and the next unrelated .github/** PR goes red on an
    # assertion it never touched. It is still a Flutter integration test,
    # so the app_flutter suites stay on as well (this arm deliberately
    # matches before the generic integration_test/* arm below, which is
    # why it has to restate app_flutter=true itself).
    integration_test/gate_test.dart)
      app_flutter=true
      release_guards=true
      ;;

    # Read by a release-guard suite (issue #1344):
    # .github/scripts/tests/check-ios-widget-signing.test.sh reads
    # ios/ExportOptions-ci.plist and both .entitlements files (its :17-19)
    # and pins the two-bundle App Group signing posture they encode, so a
    # breaking edit must run the release-guards suites too -- otherwise it
    # merges green and the next unrelated .github/** PR goes red on an
    # assertion it never touched (issue #1317's failure class). They are
    # still iOS app sources under the generic ios/* arm below, so
    # app_flutter stays on as well.
    ios/ExportOptions-ci.plist|ios/Runner/Runner.entitlements|ios/LunarLogWidget/LunarLogWidget.entitlements)
      app_flutter=true
      release_guards=true
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
