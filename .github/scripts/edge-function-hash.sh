#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/edge-function-hash.sh <function-dir>
#
# Prints one deterministic sha256 hex digest over every file's path and
# content under <function-dir> (recursively), independent of filesystem
# traversal order.
#
# LLA-110: the piece two different workflow runs -- possibly on two
# different runners, possibly days apart -- need to agree on byte-for-byte,
# without either one being able to see the other's working directory.
# supabase-migrate.yml's `migrate` job calls this right after `supabase
# functions deploy delete-account` succeeds and records the result as that
# deployment's evidence; migration-gate.yml (called from ios-release.yml /
# play-store-release.yml, potentially on a later commit and a different
# runner entirely) calls it again over whatever
# supabase/functions/delete-account looks like at release time and compares
# the two hashes -- a mismatch (or no recorded evidence at all) means the
# release cannot prove production is running the delete-account function
# this build expects, and the release is blocked the same way a missing
# migration blocks it.
#
# `find | sort` before hashing is what makes this order-independent: two
# directories with identical files but a different on-disk/readdir order
# still hash identically. Piping each file's own `sha256sum` line (which
# already includes that file's path) through `sha256sum` again folds
# per-file content and path into one final digest.

dir="${1:?usage: edge-function-hash.sh <function-dir>}"

if [ ! -d "$dir" ]; then
  echo "::error::edge-function-hash.sh: not a directory: $dir" >&2
  exit 1
fi

find "$dir" -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -d' ' -f1
