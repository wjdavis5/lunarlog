#!/usr/bin/env bash
# .github/scripts/check-play-health-declaration.sh
#
# The Play production health-declaration gate (issue #254), extracted from
# play-store-release.yml so the release-guards suite can pin its exit-status
# truth table (issue #1735).
#
# Inputs (env):
#   PLAY_HEALTH_DECLARATION_CONFIRMED  Repository variable. Must be 'true'
#                                      when the manifest requests health
#                                      permissions.
#
# Exit codes:
#   0: nothing to gate (no health permissions in the manifest), or health
#      permissions present with the declaration confirmed.
#   1: the manifest is missing/unreadable, or it requests health permissions
#      without the declaration confirmed.
set -euo pipefail

manifest="android/app/src/main/AndroidManifest.xml"

# Issue #1735: the original inline `if ! grep -q ...` treated grep's exit 2
# (file missing) as "nothing to gate" and passed the gate without gating
# anything. A manifest that cannot be read is a hard failure -- the gate
# exists to run against the real manifest.
if [ ! -f "$manifest" ]; then
  echo "::error::Health declaration gate: manifest '$manifest' not found - refusing to pass without checking it (issue #1735)."
  exit 1
fi
if [ ! -r "$manifest" ]; then
  echo "::error::Health declaration gate: manifest '$manifest' is not readable - refusing to pass without checking it (issue #1735)."
  exit 1
fi

if ! grep -q "android.permission.health\." "$manifest"; then
  echo "No health permissions in the manifest; nothing to gate."
  exit 0
fi

if [ "${PLAY_HEALTH_DECLARATION_CONFIRMED:-}" != "true" ]; then
  echo "::error::The manifest requests android.permission.health.* permissions, but the Play Console Health apps declaration is not recorded as filed and approved."
  echo "::error::Complete docs/ops/play-health-declaration.md (the Health apps declaration form, per-permission justifications, privacy-policy URL), then set the PLAY_HEALTH_DECLARATION_CONFIRMED repository variable to 'true'."
  exit 1
fi

echo "Health permissions present and PLAY_HEALTH_DECLARATION_CONFIRMED=true; health declaration gate satisfied (issue #254)."
