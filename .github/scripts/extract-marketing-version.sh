#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/extract-marketing-version.sh
#
# Extracts the marketing version -- the "x.y.z" part before the "+build"
# suffix -- from pubspec.yaml content on stdin. The single implementation
# of this parsing rule: both release workflows' "Resolve build and version
# numbers" step and detect-version-bump.sh's historical-version lookup
# call this instead of each hand-rolling the same pipeline.

grep '^version:' | sed 's/^version: *//' | cut -d'+' -f1
