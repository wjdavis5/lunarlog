// _shared/push.ts (Issue #5, U5; KTD7)
//
// FCM HTTP v1 sender. Mints a Google OAuth access token by RS256-signing a
// JWT with Web Crypto and exchanging it at oauth2.googleapis.com/token --
// structurally the same shape as _shared/apple_revoke.ts's ES256
// client-secret flow, but RSA/RS256 (Google service-account keys are RSA)
// rather than ECDSA/ES256. No service-account JSON is committed.
//
// [sendPush] mints a fresh token on every call -- correct for a single
// one-off send, but push-dispatch's own batch (up to BATCH_SIZE claimed
// rows, each with its own recipient devices) used to call it once per
// (row, device), discarding a 3600s-lived token after a single use (round-1
// #13, round-2 #6). [createPushSender] fixes that: it mints exactly one
// token per invocation and reuses it across every send on the returned
// closure, falling back to a fresh mint-and-retry only if FCM ever rejects
// the cached one. No token is cached *across* invocations -- push-dispatch
// builds a fresh closure (via buildDeps) on every function invocation, and
// nothing in this module reaches for global/module-level state to persist
// one longer than that.
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

/** True for the FCM HTTP v1 statuses that mean the access token itself was
 * rejected (expired/invalid/insufficient scope) rather than anything about
 * the message or the target device -- the one case where re-minting and
 * retrying the same send is worth doing (round-2 review #6). */
function isAuthError(status: number): boolean {
  return status === 401 || status === 403;
}

/** The actual FCM HTTP v1 call given an already-minted [accessToken] --
 * factored out of [sendPush] so both it and [createPushSender]'s closure
 * (round-2 review #6) share one classification of the response, rather than
 * duplicating the unregistered/other logic. */
async function postToFcm(
  projectId: string,
  accessToken: string,
  message: unknown,
): Promise<SendPushResult & { status?: number }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
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
    return { ok: false, reason: "unregistered", detail: bodyText, status: response.status };
  }
  return { ok: false, reason: "other", detail: bodyText, status: response.status };
}

/**
 * Sends [message] via FCM HTTP v1, minting a fresh OAuth token first (the
 * exchange is attempted before the send; its failure short-circuits without
 * ever calling FCM). Classifies the failure kind rather than throwing, so
 * push-dispatch's batch loop can decide claim/attempt/disable handling per
 * kind (KTD2).
 *
 * This mints on every call, which is correct for a single one-off send but
 * wasteful across a batch (round-2 review #6, round-1 #13) -- push-dispatch
 * itself calls [createPushSender] instead, which mints once per invocation.
 * This function survives as that closure's own 401 fallback (a token
 * rejected mid-batch is re-minted exactly the way every send used to mint).
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
  const { status: _status, ...result } = await postToFcm(creds.projectId, accessToken, message);
  return result;
}

/**
 * Builds a send closure that mints one Google OAuth access token for
 * [creds] and reuses it across every call (round-2 review #6, round-1
 * #13) -- push-dispatch's `buildDeps` creates exactly one of these per
 * function invocation, so a batch of up to `BATCH_SIZE * devices-per-row`
 * sends costs one RSA-signed JWT and one `oauth2.googleapis.com` round
 * trip instead of one per send. If FCM rejects the cached token (401/403 --
 * e.g. it expired mid-invocation, or was otherwise invalid), that one send
 * falls back to a fresh mint-and-retry -- the same per-call behavior
 * [sendPush] always has -- so the cross-invocation win never costs a real
 * failure; the fresh token from that fallback is then cached for
 * subsequent calls on this same closure.
 */
export function createPushSender(
  creds: ServiceAccountCredentials,
): (message: unknown) => Promise<SendPushResult> {
  let tokenPromise: Promise<string> | null = null;

  const ensureToken = (): Promise<string> => {
    if (tokenPromise === null) {
      tokenPromise = mintAccessToken(creds).catch((error) => {
        tokenPromise = null;
        throw error;
      });
    }
    return tokenPromise;
  };

  return async (message: unknown): Promise<SendPushResult> => {
    let accessToken: string;
    try {
      accessToken = await ensureToken();
    } catch (error) {
      return { ok: false, reason: classifyThrown(error), detail: error instanceof Error ? error.message : String(error) };
    }

    const { status, ...result } = await postToFcm(creds.projectId, accessToken, message);
    if (result.ok || status === undefined || !isAuthError(status)) {
      return result;
    }

    // The cached token was rejected -- re-mint (the same per-call fallback
    // sendPush always uses) and retry this one send, then leave the fresh
    // token cached (via ensureToken/tokenPromise above) so later calls on
    // this same closure benefit from it too.
    tokenPromise = null;
    let freshToken: string;
    try {
      freshToken = await ensureToken();
    } catch (error) {
      return { ok: false, reason: classifyThrown(error), detail: error instanceof Error ? error.message : String(error) };
    }
    const { status: _retryStatus, ...retryResult } = await postToFcm(creds.projectId, freshToken, message);
    return retryResult;
  };
}
