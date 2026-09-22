#!/usr/bin/env bash
set -euo pipefail

# Issue #141 / PR #1007: the home-screen widget is a separate app extension
# with its own App ID (com.wjdavis5.lunarlog.LunarLogWidget). Because the
# shared App Group (group.com.wjdavis5.lunarlog.widgets) must be declared on
# both App IDs, a signed App Store build now signs TWO bundles, each needing
# its own provisioning profile. A change that reverts either half -- dropping
# IOS_WIDGET_PROVISION_PROFILE_BASE64, or deleting the widget bundle id from
# ExportOptions-ci.plist -- would not be caught until a release run failed at
# export (after the archive), so it is pinned here. Run with:
#
#   bash .github/scripts/tests/check-ios-widget-signing.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_WORKFLOW="$SCRIPT_DIR/../../workflows/ios-release.yml"
EXPORT_PLIST="$SCRIPT_DIR/../../../ios/ExportOptions-ci.plist"
RUNNER_ENTITLEMENTS="$SCRIPT_DIR/../../../ios/Runner/Runner.entitlements"
WIDGET_ENTITLEMENTS="$SCRIPT_DIR/../../../ios/LunarLogWidget/LunarLogWidget.entitlements"
# shellcheck source=lib/assert.sh
source "$SCRIPT_DIR/lib/assert.sh"

ios_yaml="$(cat "$IOS_WORKFLOW")"
plist="$(cat "$EXPORT_PLIST")"
app_entitlements="$(cat "$RUNNER_ENTITLEMENTS")"
widget_entitlements="$(cat "$WIDGET_ENTITLEMENTS")"

# --- ios-release.yml installs both profiles, each failing closed ---

assert_contains "ios-release.yml installs the app profile from IOS_PROVISION_PROFILE_BASE64" \
  "$ios_yaml" 'PROFILE_BASE64: ${{ secrets.IOS_PROVISION_PROFILE_BASE64 }}'
assert_contains "ios-release.yml installs the widget profile from IOS_WIDGET_PROVISION_PROFILE_BASE64" \
  "$ios_yaml" 'WIDGET_PROFILE_BASE64: ${{ secrets.IOS_WIDGET_PROVISION_PROFILE_BASE64 }}'

assert_contains "the app profile install fails closed, naming its secret" \
  "$ios_yaml" "Secret IOS_PROVISION_PROFILE_BASE64 is empty or not configured."
assert_contains "the widget profile install fails closed, naming its secret" \
  "$ios_yaml" "Secret IOS_WIDGET_PROVISION_PROFILE_BASE64 is empty or not configured."
assert_contains "the widget profile failure carries a ::error:: annotation" \
  "$ios_yaml" "::error::Secret IOS_WIDGET_PROVISION_PROFILE_BASE64"

assert_contains "the widget profile path is recorded for cleanup" \
  "$ios_yaml" 'WIDGET_PROVISIONING_PROFILE_PATH='
assert_contains "cleanup removes the widget profile by its recorded path" \
  "$ios_yaml" 'rm -f "$WIDGET_PROVISIONING_PROFILE_PATH"'

# --- ExportOptions-ci.plist maps both bundle ids to a profile name ---

assert_contains "ExportOptions-ci.plist maps the app bundle id" \
  "$plist" "<key>com.wjdavis5.lunarlog</key>"
assert_contains "ExportOptions-ci.plist maps the widget bundle id" \
  "$plist" "<key>com.wjdavis5.lunarlog.LunarLogWidget</key>"
assert_contains "ExportOptions-ci.plist names the app profile 'Lunarlog'" \
  "$plist" "<string>Lunarlog</string>"
assert_contains "ExportOptions-ci.plist names the widget profile 'LunarLogWidget'" \
  "$plist" "<string>LunarLogWidget</string>"

# --- The invariant underneath: the App Group is on both targets ---

assert_contains "Runner.entitlements declares the shared App Group" \
  "$app_entitlements" "group.com.wjdavis5.lunarlog.widgets"
assert_contains "LunarLogWidget.entitlements declares the shared App Group" \
  "$widget_entitlements" "group.com.wjdavis5.lunarlog.widgets"

print_summary "check-ios-widget-signing.test.sh"
