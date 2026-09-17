// Apple token revocation (Issue #17, Unit U3; KTD3).
//
// Exchanges a one-time Sign in with Apple `authorizationCode` for a refresh
// token, then revokes that refresh token. Nothing here persists anything: no
// Apple refresh token is ever stored (KTD3) - a fresh authorization code is
// obtained at delete time by the client (`lib/ui/account/account_section.dart`,
// U6) and forwarded through the `delete-account` Edge Function (U2) for this
// module to consume once and discard.
//
// Never returns or logs Apple's response body, the authorization code, or
// either token - only a discriminated result kind. The caller (U2) logs that
// kind, never this module's internals.

/** Discriminated outcome. Never carries Apple's response body or a token.
 * `identity_mismatch` (Issue #560) is returned when the exchanged
 * `id_token`'s `sub` does not match the caller's own Apple identity id --
 * Apple's `client_id` binding on the token endpoint only stops a code
 * minted for a *different app* from being redeemed here; it does nothing to
 * stop a code minted for a *different Apple user* of this same app from
 * being redeemed by an attacker calling delete-account as themselves while
 * supplying someone else's authorization code. */
export type AppleRevokeResult =
  | { kind: "ok" }
  | { kind: "misconfigured" }
  | { kind: "apple_rejected" }
  | { kind: "identity_mismatch" }
  | { kind: "network" };

interface AppleRevokeConfig {
  teamId: string;
  keyId: string;
  clientId: string;
  /** PEM contents of the Apple-issued `.p8` signing key. */
  privateKey: string;
}

const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token";
const APPLE_REVOKE_URL = "https://appleid.apple.com/auth/revoke";

/** Short-lived (KTD3: built fresh per call, never cached or persisted). */
const CLIENT_SECRET_TTL_SECONDS = 300;

/**
 * Both Apple calls below are made mid-deletion, after the row-deletion RPC
 * has already run: a hung Apple endpoint must not strand the account
 * indefinitely between "rows gone" and "user gone" (the Edge Function's
 * ordering, KTD4). A timed-out fetch throws the same way a network error
 * does, so it is caught by the existing try/catch and resolves to `network`
 * - handled identically to any other revocation failure (fail closed).
 */
const APPLE_FETCH_TIMEOUT_MS = 10_000;

function readConfig(): AppleRevokeConfig | null {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  if (!teamId || !keyId || !clientId || !privateKey) return null;
  return { teamId, keyId, clientId, privateKey };
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

/** Parses the `.p8` PEM into the raw PKCS8 DER Web Crypto needs. */
async function importApplePrivateKey(pem: string): Promise<CryptoKey> {
  const base64Body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64Body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/**
 * Builds the ES256 client-secret JWT Apple's token/revoke endpoints require
 * in place of a static client secret (U3 step 1): `iss` is the Apple Team
 * ID, `sub`/`aud` identify this app's Sign in with Apple client (the bundle
 * id, per AGENTS.md), `kid` names the signing key, and the whole thing
 * expires in minutes - it is minted fresh for this one call, never cached.
 *
 * A Web Crypto ECDSA P-256 signature is the raw `r || s` concatenation
 * (64 bytes), which is exactly the JWS ES256 encoding - no DER-to-raw
 * conversion is needed, unlike RSA/RS256 JWTs.
 */
async function buildClientSecret(config: AppleRevokeConfig): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: config.keyId, typ: "JWT" };
  const payload = {
    iss: config.teamId,
    iat: nowSeconds,
    exp: nowSeconds + CLIENT_SECRET_TTL_SECONDS,
    aud: "https://appleid.apple.com",
    sub: config.clientId,
  };
  const signingInput =
    `${base64UrlEncodeJson(header)}.${base64UrlEncodeJson(payload)}`;
  const key = await importApplePrivateKey(config.privateKey);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(signature))}`;
}

async function exchangeCodeForRefreshToken(
  config: AppleRevokeConfig,
  clientSecret: string,
  authorizationCode: string,
): Promise<
  { ok: true; refreshToken: string; idToken: string } | { ok: false; result: AppleRevokeResult }
> {
  let response: Response;
  try {
    response = await fetch(APPLE_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
      signal: AbortSignal.timeout(APPLE_FETCH_TIMEOUT_MS),
    });
  } catch {
    return { ok: false, result: { kind: "network" } };
  }
  if (!response.ok) {
    return { ok: false, result: { kind: "apple_rejected" } };
  }
  let refreshToken: unknown;
  let idToken: unknown;
  try {
    const body = await response.json();
    refreshToken = (body as Record<string, unknown>)?.refresh_token;
    idToken = (body as Record<string, unknown>)?.id_token;
  } catch {
    return { ok: false, result: { kind: "apple_rejected" } };
  }
  if (typeof refreshToken !== "string" || refreshToken.length === 0) {
    return { ok: false, result: { kind: "apple_rejected" } };
  }
  // Issue #560: the id_token is required, not merely optional metadata --
  // its `sub` claim is the only thing that lets the caller below bind this
  // exchange to a specific Apple user before revoking anything.
  if (typeof idToken !== "string" || idToken.length === 0) {
    return { ok: false, result: { kind: "apple_rejected" } };
  }
  return { ok: true, refreshToken, idToken };
}

/**
 * Decodes (never verifies signature) a JWT's payload segment and returns its
 * `sub` claim, or null on any malformed input. Signature verification is
 * deliberately not performed here: this id_token is read directly out of a
 * response this module itself just received over TLS from
 * `appleid.apple.com` (never anything supplied by the client or read back
 * from storage), so the trust boundary is the HTTPS connection to Apple
 * itself, exactly like `refresh_token` from the same response is trusted
 * without any signature of its own.
 */
function decodeIdTokenSub(idToken: string): string | null {
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;
  try {
    let base64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) base64 += "=";
    const payloadJson = new TextDecoder().decode(
      Uint8Array.from(atob(base64), (c) => c.charCodeAt(0)),
    );
    const payload = JSON.parse(payloadJson) as Record<string, unknown>;
    const sub = payload["sub"];
    return typeof sub === "string" && sub.length > 0 ? sub : null;
  } catch {
    return null;
  }
}

/**
 * The pure decision at the heart of Issue #560's fix, factored out so it can
 * be unit-tested with no network and no `Deno.env` access (unlike
 * `revokeAppleToken` as a whole, which reads Apple credentials from the
 * environment via `readConfig()` and so needs `--allow-env` to exercise at
 * all - not granted to this suite's plain `deno test` invocation, matching
 * every other credential-reading path in this file). Never verifies the
 * id_token's signature - see `decodeIdTokenSub`'s own comment for why that
 * is an acceptable trust boundary here.
 */
export function verifyIdentityBinding(
  idToken: string,
  expectedAppleUserId: string,
): "ok" | "apple_rejected" | "identity_mismatch" {
  const sub = decodeIdTokenSub(idToken);
  if (sub === null) return "apple_rejected";
  return sub === expectedAppleUserId ? "ok" : "identity_mismatch";
}

async function revokeRefreshToken(
  config: AppleRevokeConfig,
  clientSecret: string,
  refreshToken: string,
): Promise<AppleRevokeResult> {
  let response: Response;
  try {
    response = await fetch(APPLE_REVOKE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: config.clientId,
        client_secret: clientSecret,
        token: refreshToken,
        token_type_hint: "refresh_token",
      }),
      signal: AbortSignal.timeout(APPLE_FETCH_TIMEOUT_MS),
    });
  } catch {
    return { kind: "network" };
  }
  return response.ok ? { kind: "ok" } : { kind: "apple_rejected" };
}

/**
 * Exchanges [authorizationCode] for a refresh token and immediately revokes
 * it. Missing Apple secrets resolve to `misconfigured` rather than silently
 * skipping revocation (U3 step 5) - the Edge Function (U2) surfaces that as
 * a typed failure and stops before deleting the `auth.users` row (KTD4).
 *
 * Issue #560: [expectedAppleUserId] is the caller's own Apple identity id
 * (GoTrue's `identities[provider=="apple"].id`, equal to Apple's `sub`
 * claim), resolved by the caller from their own verified session - never
 * from anything in the request body. Apple's `client_id` binding on the
 * token endpoint only proves the authorization code was minted for *this
 * app*; it says nothing about *which Apple user* minted it. Without this
 * check, an attacker who obtained a valid Apple authorization code for
 * victim B (e.g. via a compromised device, a leaked code, or a malicious
 * client) could call delete-account authenticated as themselves while
 * supplying B's code: Apple would revoke B's grant while the attacker's own
 * grant is never touched. The exchanged `id_token`'s `sub` is decoded and
 * compared against [expectedAppleUserId] before the revoke call is ever
 * made - a mismatch resolves to `identity_mismatch` and nothing is revoked.
 */
export async function revokeAppleToken(
  authorizationCode: string,
  expectedAppleUserId: string,
): Promise<AppleRevokeResult> {
  const config = readConfig();
  if (!config) return { kind: "misconfigured" };

  let clientSecret: string;
  try {
    clientSecret = await buildClientSecret(config);
  } catch {
    return { kind: "misconfigured" };
  }

  const exchanged = await exchangeCodeForRefreshToken(
    config,
    clientSecret,
    authorizationCode,
  );
  if (!exchanged.ok) return exchanged.result;

  // A malformed/undecodable id_token from Apple's own token endpoint is
  // treated the same as an outright rejection - fail closed rather than
  // ever revoking without having been able to confirm whose grant it is.
  const binding = verifyIdentityBinding(exchanged.idToken, expectedAppleUserId);
  if (binding !== "ok") return { kind: binding };

  return revokeRefreshToken(config, clientSecret, exchanged.refreshToken);
}
