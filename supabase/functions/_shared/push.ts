// _shared/push.ts (Issue #5, U5; KTD7)
//
// FCM HTTP v1 sender. Mints a fresh Google OAuth access token per call by
// RS256-signing a JWT with Web Crypto and exchanging it at
// oauth2.googleapis.com/token -- structurally the same shape as
// _shared/apple_revoke.ts's ES256 client-secret flow, but RSA/RS256 (Google
// service-account keys are RSA) rather than ECDSA/ES256. No service-account
// JSON is committed, and no long-lived token is cached across invocations --
// push-dispatch's batches are small and bounded (see index.ts), so minting
// per-send is deliberately simple over efficient.
//
// Credentials are a plain parameter, never read from `Deno.env` inside this
// module (the _shared/email.ts round-7 lesson) -- push-dispatch/index.ts's
// `buildDeps` reads the service-account JSON once and passes it down, which
// is also what lets this file's tests stub `fetch` with no `--allow-env`.

export interface ServiceAccountCredentials {
  projectId: string;
  clientEmail: string;
  /** PEM contents (PKCS8) of the service account's private key. */
  privateKey: string;
}

/** `unregistered` means the token is dead (uninstalled app, expired token) --
 * distinct from every other failure because the caller should stop retrying
 * that specific device rather than the send in general. */
export type SendPushResult =
  | { ok: true }
  | { ok: false; reason: "timeout" | "network_error" | "unregistered" | "other"; detail?: string };

const FCM_TIMEOUT_MS = 10_000;
const OAUTH_TOKEN_URL = "https://oauth2.googleapis.com/token";
const OAUTH_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeJson(value: unknown): string {
  return base64UrlEncodeBytes(new TextEncoder().encode(JSON.stringify(value)));
}

/** Parses the service account's PEM into the raw PKCS8 DER Web Crypto
 * needs, mirroring _shared/apple_revoke.ts's importApplePrivateKey. */
async function importServiceAccountKey(pem: string): Promise<CryptoKey> {
  const base64Body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64Body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/**
 * Mints a fresh Google OAuth access token for FCM HTTP v1 by RS256-signing a
 * JWT with [creds] and exchanging it for an access token. Throws on any
 * failure -- [sendPush] classifies that as a send failure without ever
 * having attempted the actual FCM send (the OAuth exchange is attempted
 * before the send and its failure short-circuits without a send).
 */
export async function mintAccessToken(creds: ServiceAccountCredentials): Promise<string> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: creds.clientEmail,
    scope: OAUTH_SCOPE,
    aud: OAUTH_TOKEN_URL,
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  };
  const signingInput = `${base64UrlEncodeJson(header)}.${base64UrlEncodeJson(payload)}`;
  const key = await importServiceAccountKey(creds.privateKey);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );
  const assertion = `${signingInput}.${base64UrlEncodeBytes(new Uint8Array(signature))}`;

  const response = await fetch(OAUTH_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
    signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`oauth_token_exchange_failed_${response.status}`);
  }
  const body = await response.json();
  const accessToken = (body as Record<string, unknown>)["access_token"];
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new Error("oauth_token_exchange_missing_access_token");
  }
  return accessToken;
}

function classifyThrown(error: unknown): "timeout" | "network_error" {
  return error instanceof DOMException && error.name === "TimeoutError"
    ? "timeout"
    : "network_error";
}

/**
 * Sends [message] via FCM HTTP v1, minting a fresh OAuth token first (the
 * exchange is attempted before the send; its failure short-circuits without
 * ever calling FCM). Classifies the failure kind rather than throwing, so
 * push-dispatch's batch loop can decide claim/attempt/disable handling per
 * kind (KTD2).
 */
export async function sendPush(
  creds: ServiceAccountCredentials,
  message: unknown,
): Promise<SendPushResult> {
  let accessToken: string;
  try {
    accessToken = await mintAccessToken(creds);
  } catch (error) {
    return { ok: false, reason: classifyThrown(error), detail: error instanceof Error ? error.message : String(error) };
  }

  const url = `https://fcm.googleapis.com/v1/projects/${creds.projectId}/messages:send`;
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
      signal: AbortSignal.timeout(FCM_TIMEOUT_MS),
    });
  } catch (error) {
    return { ok: false, reason: classifyThrown(error) };
  }

  if (response.ok) {
    return { ok: true };
  }

  let bodyText = "";
  try {
    bodyText = await response.text();
  } catch {
    // Best-effort detail only.
  }
  const isUnregistered = response.status === 404 ||
    bodyText.includes("UNREGISTERED") ||
    bodyText.includes("NOT_FOUND");
  if (isUnregistered) {
    return { ok: false, reason: "unregistered", detail: bodyText };
  }
  return { ok: false, reason: "other", detail: bodyText };
}
