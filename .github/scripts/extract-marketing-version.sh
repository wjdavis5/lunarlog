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
#
# Hardened again (issue LLA-115): the previous extraction used a single
# capture-group regex (`s/^version:[[:space:]]*([^[:space:]#]+).*/\1/`) that
# only rewrites the line when the capture group actually matches something.
# Two YAML shapes broke it silently, both exiting 0:
#   - a quoted scalar (`version: "1.2.3+45"`) has a `"` immediately after
#     the colon, which the capture group happily swallows as part of the
#     "value" -- the leading quote then rides all the way through `cut` into
#     the marketing version.
#   - an empty or comment-only value (`version:` or `version: # todo`) has
#     no non-whitespace, non-`#` character for the group to capture at all,
#     so the `s///` simply never matches and leaves $version_line
#     *completely unedited* -- the whole original line text ("version:" or
#     "version: # todo") comes out the other end as if it were the parsed
#     value, non-empty, so the `[ -z "$version" ]` guard never fires.
# The rewrite below never relies on a regex match succeeding to produce a
# result: prefix/comment/whitespace stripping via `sed` substitutions that
# are no-ops (not non-matches) when there's nothing to strip, one layer of
# surrounding quote-stripping via `case`, then an explicit emptiness check
# on what's left. A final `case`-based shape check rejects anything that
# isn't a plain `x.y.z` (digits and dots only, exactly two dots, no empty
# segment) instead of letting a malformed value reach the App Store Connect
# upload step, where today it only fails much later and far less clearly.

version_line="$(grep -m1 '^version:' || true)"
if [ -z "$version_line" ]; then
  echo "::error::extract-marketing-version.sh: no 'version:' line found in the input (expected pubspec.yaml on stdin)" >&2
  exit 1
fi

# Strip the "version:" prefix, then a trailing "# comment" (and the
# whitespace before it), then any remaining trailing whitespace. Each `sed`
# substitution below is unconditional -- it removes what it matches and
# leaves everything else exactly as-is, so (unlike the old capture-group
# regex) a value with nothing to strip never falls back to the untouched
# original line.
raw="$(printf '%s\n' "$version_line" | sed -E \
  -e 's/^version:[[:space:]]*//' \
  -e 's/[[:space:]]*#.*$//' \
  -e 's/[[:space:]]*$//')"

# A YAML scalar may be quoted (`version: "1.2.3"` or `version: '1.2.3'`);
# strip exactly one matching layer so the quote character itself never
# leaks into the marketing version.
case "$raw" in
  \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;;
  \'*\') raw="${raw#\'}"; raw="${raw%\'}" ;;
esac

if [ -z "$raw" ]; then
  echo "::error::extract-marketing-version.sh: could not parse a version value out of: $version_line" >&2
  exit 1
fi

marketing="$(printf '%s\n' "$raw" | cut -d'+' -f1)"

# pubspec.yaml's version is always "x.y.z" or "x.y.z+build" -- reject
# anything else (a stray word, a half-stripped quote, a missing/extra
# segment) now rather than letting it reach the release build/upload steps.
case "$marketing" in
  *[!0-9.]* | '' | .* | *. | *..*)
    echo "::error::extract-marketing-version.sh: '$marketing' (from: $version_line) is not a valid x.y.z marketing version" >&2
    exit 1
    ;;
esac
dot_count="$(printf '%s' "$marketing" | tr -cd '.' | wc -c)"
if [ "$dot_count" -ne 2 ]; then
  echo "::error::extract-marketing-version.sh: '$marketing' (from: $version_line) is not a valid x.y.z marketing version" >&2
  exit 1
fi

printf '%s\n' "$marketing"
