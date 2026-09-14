#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/check-auth-config.sh
#
# Issue #266: supabase/config.toml's [auth] block is committed, version-
# controlled config for the LOCAL Supabase stack (`supabase start`) -- this
# script is the CI enforcement that a future edit cannot silently drift it
# back toward the permissive stock Supabase CLI template (jwt_expiry back
# to 3600, enable_signup back to true, etc.). It guards this repo's
# committed security posture; it is NOT a production-parity check and
# nothing here pushes these values to production -- supabase config push
# was deliberately NOT added to supabase-migrate.yml (review round 1):
# config.toml also carries local-only settings (site_url =
# http://127.0.0.1:3000, [auth.external.apple] disabled with an empty
# client_id, local SMTP, etc.) that must never reach the live project, so
# applying the documented production posture there stays a deliberate,
# manual dashboard action -- see docs/ops/supabase-go-live.md's "Supabase
# Auth" checklist for that manual checklist and PR #694's description for
# the review finding.
#
# Expected values below are the documented production posture from that
# checklist and issue #266 itself (D-5), used here as the values the
# COMMITTED LOCAL config should match so `supabase start` at least
# reproduces the same security posture developers and CI test against
# (password_requirements is the one deliberate exception -- see its own
# comment below). MFA settings are deliberately left alone -- issue #268
# builds on this issue's config-as-code baseline for that, it is not this
# issue's scope.
#
# A plain-text/regex line scanner, not a full TOML parser -- the same
# tradeoff test/release/export_compliance_test.dart's header documents for
# its own structural checks, justified here because this only needs to
# compare a handful of scalar keys inside two known sections ([auth] and
# [auth.email]), not round-trip arbitrary TOML. Full-line `#` comments are
# stripped first so a commented-out example value can never satisfy a
# check.
#
# Usage: check-auth-config.sh [path-to-config.toml]
#   Defaults to supabase/config.toml (relative to the current directory --
#   the repo root in CI).
#
# Exit code: 0 when every expected key/value pair below is present in the
# expected section with the expected value; non-zero (with one ::error::
# per mismatch) otherwise.
#
# Bash 3.2 compatible on request (no `${var,,}`, no associative arrays),
# even though this script currently only runs on ubuntu-latest in ci.yml --
# see AGENTS.md / the coder instructions for why that constraint is kept
# regardless.

CONFIG_PATH="${1:-supabase/config.toml}"

if [ ! -f "$CONFIG_PATH" ]; then
  echo "::error::$CONFIG_PATH not found"
  exit 1
fi

# Strip full-line comments up front (leading '#', optional whitespace
# before it) so every helper below reads only live TOML.
_stripped="$(grep -v '^[[:space:]]*#' "$CONFIG_PATH" || true)"

# Prints the body of a top-level or dotted TOML table header (e.g. "auth"
# or "auth.email"), up to but not including the next "[" header line.
# Reads $_stripped, so comments are already gone. Prints nothing if the
# section is absent.
_section_body() {
  local header="$1"
  printf '%s\n' "$_stripped" | awk -v h="[$header]" '
    $0 == h { found=1; next }
    found && /^\[/ { exit }
    found { print }
  '
}

# Reads the value of a "key = value" line out of a section body (the last
# match if the key appears more than once), trims surrounding whitespace
# and one layer of double quotes. Prints nothing if the key is absent --
# `|| true` guards the pipeline against `set -o pipefail` treating "no
# match" (grep's exit 1) as a script-ending failure, since "the key is
# genuinely absent" is an expected, handled case here, not a script bug.
_kv() {
  local body="$1" key="$2"
  printf '%s\n' "$body" \
    | grep -E "^[[:space:]]*${key}[[:space:]]*=" \
    | tail -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*//" \
    | sed -E 's/[[:space:]]*$//' \
    | sed -E 's/^"(.*)"$/\1/' \
    || true
}

errors=0

# _check SECTION KEY EXPECTED
_check() {
  local section="$1" key="$2" expected="$3" body actual
  body="$(_section_body "$section")"
  actual="$(_kv "$body" "$key")"
  if [ -z "$actual" ] && ! printf '%s\n' "$body" | grep -qE "^[[:space:]]*${key}[[:space:]]*="; then
    echo "::error::$CONFIG_PATH [$section] is missing '$key' (expected '$expected') -- see docs/ops/supabase-go-live.md's Supabase Auth checklist / issue #266"
    errors=$((errors + 1))
    return
  fi
  if [ "$actual" != "$expected" ]; then
    echo "::error::$CONFIG_PATH [$section] $key = $actual (expected $expected) -- see docs/ops/supabase-go-live.md's Supabase Auth checklist / issue #266"
    errors=$((errors + 1))
  fi
}

# --- [auth]: the documented production posture (issue #266, D-5) ---
_check auth jwt_expiry 600
_check auth enable_signup false
_check auth enable_manual_linking true
_check auth minimum_password_length 12
# Empty, not a complexity requirement (review round 1): the client only
# enforces minimum_password_length above (kMinPasswordLength = 12 in
# lib/ui/l10n/auth_failure_copy.dart) -- a non-empty value here would let
# the server reject a password the client already accepted. See
# supabase/config.toml's own comment on this key.
_check auth password_requirements ""

# --- [auth.email] ---
_check auth.email enable_confirmations true
_check auth.email otp_length 8
_check auth.email otp_expiry 600

if [ "$errors" -eq 0 ]; then
  echo "$CONFIG_PATH [auth] matches this repo's committed security posture. This checks the committed LOCAL config only -- it does not verify or push production, which is applied manually per docs/ops/supabase-go-live.md's Supabase Auth checklist."
fi

[ "$errors" -eq 0 ]
