#!/usr/bin/env bash
set -euo pipefail

# .github/scripts/apple-client-secret.sh (Issue #974)
#
# Supabase's Apple provider cannot mint its own client secret: Sign in with
# Apple requires an ES256 JWT built from the SIWA `.p8` key, and Apple caps
# that JWT's lifetime at 6 months. When a rotation is missed the provider
# keeps returning "signed in" tokens right up until Apple rejects the
# exchange, so nothing errors until a real user tries to sign in with Apple -
# exactly the silent breakage issue #974 exists to prevent.
#
# This script holds the logic the rotation workflow
# (`.github/workflows/supabase-apple-secret-rotation.yml`) needs, so the
# workflow itself stays a thin, reviewable sequence of Management API calls
# and every decision here is covered by
# `.github/scripts/tests/apple-client-secret.test.sh` using a throwaway key
# generated inside the test - the real `.p8` is never touched by a test.
#
# The JWT shape mirrors `supabase/functions/_shared/apple_revoke.ts`'s
# in-process client secret exactly (same ES256 signing, same `iss` / `aud` /
# `kid` claims, same Web-Crypto-compatible raw `r || s` signature encoding),
# with ONE deliberate difference: `sub` is the Apple *Services ID*
# (`com.wjdavis5.lunarlog.web`), NOT the bundle id. Supabase's Apple provider
# serves the web / Services ID flow, and a secret whose `sub` is the bundle
# id still validates as a well-formed JWT - it is only rejected by Apple at
# token exchange. Getting that one claim wrong is the failure this issue
# warns about.
#
# Subcommands (configuration comes from the environment; only `mint` emits a
# secret, and only on stdout for the caller to hand straight to the API
# without ever logging it):
#
#   mint
#     Requires APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (PEM) and
#     APPLE_SERVICES_ID. Optional APPLE_SECRET_TTL_DAYS (default 180) and
#     APPLE_SECRET_MARGIN_DAYS (default 5); `exp = now + (TTL - margin) days`.
#     Writes the JWT to stdout.
#
#   jwt-claim <name>
#     Reads a JWT on stdin and prints that payload claim (or nothing). Used to
#     verify the value the project actually stored - `sub` is the Services ID
#     and `iat` proves freshness; neither is a secret.
#
#   client-id <current>
#     Prints the comma-separated `external_apple_client_id` list with both the
#     bundle id and the Services ID present, preserving any other entries and
#     their order. Pure - it reads the current value first and never drops an
#     entry.
#
#   staleness <last-success-epoch|-> <now-epoch> <max-age-days>
#     Prints `fresh` or `overdue`. `-` for the last-success epoch means no
#     prior successful rotation is recorded (first run) and is `fresh`.
#
# Never prints the `.p8`, the minted JWT, or the access token. Bash 3.2
# compatible (release-guards-macos): no associative arrays, no `${var,,}`,
# no `mapfile`.

# The primary App ID (bundle id). Fixed for this repo; the *Services* ID is
# supplied per-run via APPLE_SERVICES_ID so this script can never silently
# fall back to the bundle id for `sub`.
APPLE_BUNDLE_ID="com.wjdavis5.lunarlog"

log() { printf '%s\n' "$*" >&2; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }

# base64url without padding, straight off stdin.
b64url_encode() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

# Hex -> raw bytes -> base64url. The binary signature never becomes a shell
# variable (command substitution would strip any 0x00 byte and corrupt it):
# `printf %b` writes the bytes straight into the pipe.
hex_to_b64url() {
  local hex="$1" esc="" i=0
  while [ "$i" -lt "${#hex}" ]; do
    esc="$esc\\x${hex:$i:2}"
    i=$((i + 2))
  done
  printf '%b' "$esc" | b64url_encode
}

# `openssl dgst -sha256 -sign` emits the ECDSA signature as DER
# `SEQUENCE { INTEGER r, INTEGER s }`; a JWS ES256 signature is the raw
# `r || s`, each left-zero-padded to 32 bytes (64 bytes total). `asn1parse`
# reports each INTEGER's value as hex, so this returns 128 hex characters.
der_signature_to_raw_hex() {
  local der="$1" r s
  r="$(openssl asn1parse -inform DER -in "$der" 2>/dev/null | awk -F: '/INTEGER/{print $NF}' | sed -n '1p')"
  s="$(openssl asn1parse -inform DER -in "$der" 2>/dev/null | awk -F: '/INTEGER/{print $NF}' | sed -n '2p')"
  r="$(printf '%s' "$r" | tr -d '[:space:]')"
  s="$(printf '%s' "$s" | tr -d '[:space:]')"
  [ -n "$r" ] && [ -n "$s" ] || die "could not parse the ECDSA signature OpenSSL produced"
  # Normalise either direction: drop a leading DER sign byte if present,
  # then left-pad a short value back to exactly 32 bytes.
  while [ "${#r}" -gt 64 ]; do r="${r#00}"; done
  while [ "${#s}" -gt 64 ]; do s="${s#00}"; done
  while [ "${#r}" -lt 64 ]; do r="0$r"; done
  while [ "${#s}" -lt 64 ]; do s="0$s"; done
  printf '%s%s' "$r" "$s"
}

cmd_mint() {
  local team_id="${APPLE_TEAM_ID:-}"
  local key_id="${APPLE_KEY_ID:-}"
  local pem="${APPLE_PRIVATE_KEY:-}"
  local services_id="${APPLE_SERVICES_ID:-}"
  [ -n "$team_id" ] || die "APPLE_TEAM_ID is not set"
  [ -n "$key_id" ] || die "APPLE_KEY_ID is not set"
  [ -n "$pem" ] || die "APPLE_PRIVATE_KEY is not set"
  [ -n "$services_id" ] || die "APPLE_SERVICES_ID is not set - it must be the Services ID (e.g. com.wjdavis5.lunarlog.web), never the bundle id"

  local ttl_days="${APPLE_SECRET_TTL_DAYS:-180}"
  local margin_days="${APPLE_SECRET_MARGIN_DAYS:-5}"
  local now exp
  now="$(date -u +%s)"
  exp=$(( now + (ttl_days - margin_days) * 86400 ))

  local header payload signing_input
  header="$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$key_id")"
  payload="$(printf '{"iss":"%s","iat":%s,"exp":%s,"aud":"https://appleid.apple.com","sub":"%s"}' \
    "$team_id" "$now" "$exp" "$services_id")"
  signing_input="$(printf '%s' "$header" | b64url_encode).$(printf '%s' "$payload" | b64url_encode)"

  local key_file der_file
  key_file="$(mktemp "${TMPDIR:-/tmp}/apple-client-secret.XXXXXX")"
  der_file="$(mktemp "${TMPDIR:-/tmp}/apple-client-secret-sig.XXXXXX")"
  chmod 600 "$key_file" 2>/dev/null || true
  # Always clean up the materialised private key, even on failure. `:-`
  # guards the trap against running after these locals have gone out of scope.
  trap 'rm -f "${key_file:-}" "${der_file:-}"' EXIT

  # Strip CR so a CRLF secret cannot break the PEM base64 decode.
  printf '%s\n' "$pem" | tr -d '\r' > "$key_file"

  printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$key_file" > "$der_file"

  printf '%s.%s\n' "$signing_input" "$(hex_to_b64url "$(der_signature_to_raw_hex "$der_file")")"
}

cmd_jwt_claim() {
  local claim="${1:-}"
  [ -n "$claim" ] || die "jwt-claim needs a claim name"
  local token b64
  token="$(cat)"
  case "$token" in
    *.*.*) ;;
    *) return 0 ;; # not a JWT: print nothing rather than fail the caller
  esac
  b64="$(printf '%s' "$token" | cut -d. -f2 | tr '_-' '/+')"
  case $(( ${#b64} % 4 )) in
    2) b64="$b64==" ;;
    3) b64="$b64=" ;;
  esac
  printf '%s' "$b64" | openssl base64 -d -A 2>/dev/null | jq -r --arg c "$claim" '.[$c] // empty' 2>/dev/null || true
}

cmd_client_id() {
  local current="${1:-}"
  local services_id="${APPLE_SERVICES_ID:-}"
  [ -n "$services_id" ] || die "APPLE_SERVICES_ID is not set - it must be the Services ID (e.g. com.wjdavis5.lunarlog.web), never the bundle id"

  local out="" entry
  while IFS= read -r entry; do
    entry="$(printf '%s' "$entry" | tr -d '[:space:]')"
    [ -n "$entry" ] || continue
    case ",$out," in
      *",$entry,"*) continue ;;
    esac
    if [ -n "$out" ]; then out="$out,$entry"; else out="$entry"; fi
  done < <(printf '%s' "$current" | tr ',' '\n')

  case ",$out," in
    *",$APPLE_BUNDLE_ID,"*) ;;
    *) if [ -n "$out" ]; then out="$APPLE_BUNDLE_ID,$out"; else out="$APPLE_BUNDLE_ID"; fi ;;
  esac
  case ",$out," in
    *",$services_id,"*) ;;
    *) out="$out,$services_id" ;;
  esac
  printf '%s\n' "$out"
}

cmd_staleness() {
  local last="${1:-}" now="${2:-}" max_days="${3:-180}"
  # No prior successful run recorded: first run, nothing to flag.
  if [ -z "$last" ] || [ "$last" = "-" ]; then
    printf 'fresh\n'
    return 0
  fi
  [ -n "$now" ] || die "staleness needs the current epoch as its second argument"
  if [ "$(( now - last ))" -gt "$(( max_days * 86400 ))" ]; then
    printf 'overdue\n'
  else
    printf 'fresh\n'
  fi
}

case "${1:-}" in
  mint) shift; cmd_mint "$@" ;;
  jwt-claim) shift; cmd_jwt_claim "$@" ;;
  client-id) shift; cmd_client_id "$@" ;;
  staleness) shift; cmd_staleness "$@" ;;
  *)
    log "usage: $0 {mint|jwt-claim <name>|client-id <current>|staleness <last-success-epoch|-> <now-epoch> <max-age-days>}"
    exit 2
    ;;
esac
