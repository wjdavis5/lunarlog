// _shared/push.test.ts (Issue #5, U5)
//
// Generates a throwaway RSA keypair at test time (never a real credential)
// so mintAccessToken's real Web Crypto signing path runs under `deno test`
// with no `--allow-env`/`--allow-net` beyond the stubbed `fetch` below.

import { assert, assertEquals } from "jsr:@std/assert@1";
import { sendPush, type ServiceAccountCredentials } from "./push.ts";

async function generateTestPrivateKeyPem(): Promise<string> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const exported = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  const bytes = new Uint8Array(exported);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  const base64 = btoa(binary);
  const lines = base64.match(/.{1,64}/g) ?? [];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----`;
}

const testCredsPromise: Promise<ServiceAccountCredentials> = (async () => ({
  projectId: "test-project",
  clientEmail: "test@test-project.iam.gserviceaccount.com",
  privateKey: await generateTestPrivateKeyPem(),
}))();

/** Swaps `globalThis.fetch` for the duration of `run`, restoring the
 * original afterward even if `run` throws (mirrors email.test.ts's
 * withStubs). */
async function withFetchStub<T>(stub: typeof fetch, run: () => Promise<T>): Promise<T> {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    return await run();
  } finally {
    globalThis.fetch = original;
  }
}

function urlOf(input: RequestInfo | URL): string {
  return typeof input === "string" ? input : input.toString();
}

const oauthOk = () => new Response(JSON.stringify({ access_token: "fake-token" }), { status: 200 });

Deno.test("sendPush: a stubbed fetch returning 200 yields success", async () => {
  const creds = await testCredsPromise;
  let sendAttempted = false;
  const result = await withFetchStub(
    (async (input: RequestInfo | URL) => {
      if (urlOf(input).includes("oauth2.googleapis.com")) return oauthOk();
      sendAttempted = true;
      return new Response(JSON.stringify({ name: "projects/test/messages/1" }), { status: 200 });
    }) as typeof fetch,
    () => sendPush(creds, { message: {} }),
  );
  assertEquals(result, { ok: true });
  assert(sendAttempted, "the FCM send endpoint must actually be called");
});

Deno.test("sendPush: a 404 with FCM's UNREGISTERED error yields unregistered", async () => {
  const creds = await testCredsPromise;
  const result = await withFetchStub(
    (async (input: RequestInfo | URL) => {
      if (urlOf(input).includes("oauth2.googleapis.com")) return oauthOk();
      return new Response(
        JSON.stringify({ error: { status: "NOT_FOUND", message: "Requested entity was not found. (UNREGISTERED)" } }),
        { status: 404 },
      );
    }) as typeof fetch,
    () => sendPush(creds, { message: {} }),
  );
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.reason, "unregistered");
});

Deno.test("sendPush: an aborting fetch yields timeout", async () => {
  const creds = await testCredsPromise;
  const result = await withFetchStub(
    (async (input: RequestInfo | URL) => {
      if (urlOf(input).includes("oauth2.googleapis.com")) return oauthOk();
      throw new DOMException("The signal has been aborted", "TimeoutError");
    }) as typeof fetch,
    () => sendPush(creds, { message: {} }),
  );
  assertEquals(result, { ok: false, reason: "timeout" });
});

Deno.test("sendPush: a thrown network error yields network_error", async () => {
  const creds = await testCredsPromise;
  const result = await withFetchStub(
    (async (input: RequestInfo | URL) => {
      if (urlOf(input).includes("oauth2.googleapis.com")) return oauthOk();
      throw new TypeError("network down");
    }) as typeof fetch,
    () => sendPush(creds, { message: {} }),
  );
  assertEquals(result, { ok: false, reason: "network_error" });
});

Deno.test(
  "sendPush: the OAuth exchange is attempted before the send and its failure short-circuits without a send",
  async () => {
    const creds = await testCredsPromise;
    let sendAttempted = false;
    const result = await withFetchStub(
      (async (input: RequestInfo | URL) => {
        if (urlOf(input).includes("oauth2.googleapis.com")) {
          return new Response(null, { status: 401 });
        }
        sendAttempted = true;
        return new Response(null, { status: 200 });
      }) as typeof fetch,
      () => sendPush(creds, { message: {} }),
    );
    assertEquals(result.ok, false);
    assert(!sendAttempted, "a failed OAuth exchange must never reach the FCM send call");
  },
);
