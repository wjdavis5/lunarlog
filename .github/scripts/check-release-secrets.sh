#!/usr/bin/env bash
# Issue #1791: fails fast, and names every one of them, when a secret the
# Play release needs is missing. Runs as the first job of
# play-store-release.yml, so a dispatch without credentials fails in
# seconds instead of part-way through a build, and reports the full list
# rather than the first name it trips over. Only names are ever printed.
#
# See docs/ops/play-store-release.md for how to provision each one.
set -euo pipefail

missing=()

if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then missing+=("ANDROID_KEYSTORE_BASE64"); fi
if [ -z "${ANDROID_KEYSTORE_PASSWORD:-}" ]; then missing+=("ANDROID_KEYSTORE_PASSWORD"); fi
if [ -z "${ANDROID_KEY_ALIAS:-}" ]; then missing+=("ANDROID_KEY_ALIAS"); fi
if [ -z "${ANDROID_KEY_PASSWORD:-}" ]; then missing+=("ANDROID_KEY_PASSWORD"); fi
if [ -z "${PLAY_STORE_JSON_KEY:-}" ]; then missing+=("PLAY_STORE_JSON_KEY"); fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "::error::Missing release secrets: ${missing[*]}. See docs/ops/play-store-release.md for how to provision them."
  exit 1
fi

echo "All release secrets are configured."
