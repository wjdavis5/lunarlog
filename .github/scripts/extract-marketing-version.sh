#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/extract-marketing-version.sh
#
# Extracts the marketing version -- the "x.y.z" part before the "+build"
# suffix -- from pubspec.yaml content on stdin. The single implementation
# of this parsing rule: both release workflows' "Resolve build and version
# numbers" step and detect-version-bump.sh's historical-version lookup
# call this instead of each hand-rolling the same pipeline.
#
# Hardened (issue #572): a naive `sed 's/^version: *//'` does not stop at a
# trailing comment, so `version: 1.2.3 # rc` used to yield `1.2.3 # rc` --
# which, spliced unquoted into `--build-name=$marketing`, silently comments
# out every flag after it in a release build (including every
# --dart-define). The extraction below stops at the first whitespace or
# `#`, uses only the first `version:` line when more than one is present,
# and fails loudly instead of silently emitting an empty string when no
# `version:` line exists at all.

version_line="$(grep -m1 '^version:' || true)"
if [ -z "$version_line" ]; then
  echo "::error::extract-marketing-version.sh: no 'version:' line found in the input (expected pubspec.yaml on stdin)" >&2
  exit 1
fi

version="$(printf '%s\n' "$version_line" | sed -E 's/^version:[[:space:]]*([^[:space:]#]+).*/\1/')"
if [ -z "$version" ]; then
  echo "::error::extract-marketing-version.sh: could not parse a version value out of: $version_line" >&2
  exit 1
fi

printf '%s\n' "$version" | cut -d'+' -f1
