// _shared/apple_revoke.test.ts (Issue #560; Issue #1256's dual-client
// exchange)
//
// `revokeAppleToken` itself reads Apple credentials from `Deno.env` via its
// internal `readConfig()` - unlike every other credential-reading path in
// this repo's Edge Functions (see push.ts's own header comment on exactly
// this lesson), it was never refactored to take them as a parameter, so
// exercising it end to end needs `--allow-env`, which this suite's plain
// `deno test` invocation does not grant (confirmed: a bare `Deno.env.get`
// throws `NotCapable` here). `verifyIdentityBinding` is the pure decision
// Issue #560 added, factored out precisely so it can be tested without that
// permission at all - this file covers it directly.
//
// Issue #1256 added `revokeAppleTokenWith`, the same logic with the two
// environment seams (config + fetch) injected, so the dual-client-ID
// exchange contract - the request names the client id the code was minted
// for, and the client secret's `sub` claims that same id - is observable
// here against a throwaway in-test P-256 key and a stubbed Apple endpoint,
// with no env permissions and no network.

import { assertEquals } from "jsr:@std/assert@1";
import {
  APPLE_WEB_SERVICES_ID,
  resolveAppleClientId,
  revokeAppleTokenWith,
  verifyIdentityBinding,
  type AppleCodeClient,
  type AppleRevokeConfig,
} from "./apple_revoke.ts";

function fakeIdToken(payload: Record<string, unknown>): string {
  const base64Url = (value: unknown) => {
    const json = JSON.stringify(value);
    const bytes = new TextEncoder().encode(json);
    let binary = "";
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  return `${base64Url({ alg: "RS256", typ: "JWT" })}.${base64Url(payload)}.fake-signature`;
}

Deno.test("verifyIdentityBinding: a matching sub claim is ok", () => {
  const idToken = fakeIdToken({ sub: "apple-user-b", aud: "com.wjdavis5.lunarlog" });

  assertEquals(verifyIdentityBinding(idToken, "apple-user-b"), "ok");
});

Deno.test(
  "verifyIdentityBinding: a mismatched sub claim is identity_mismatch - the attack #560 closes " +
    "(an attacker authenticated as themselves supplying victim B's authorization code)",
  () => {
    const victimsIdToken = fakeIdToken({ sub: "apple-user-victim-b" });

    assertEquals(verifyIdentityBinding(victimsIdToken, "apple-user-attacker"), "identity_mismatch");
  },
);

Deno.test("verifyIdentityBinding: a malformed id_token (not three dot-separated segments) fails closed", () => {
  assertEquals(verifyIdentityBinding("not-a-jwt", "apple-user-b"), "apple_rejected");
});

Deno.test("verifyIdentityBinding: a payload segment that isn't valid base64url fails closed", () => {
  assertEquals(verifyIdentityBinding("header.!!!not-base64!!!.sig", "apple-user-b"), "apple_rejected");
});

Deno.test("verifyIdentityBinding: a payload segment that decodes to non-JSON fails closed", () => {
  const notJson = btoa("not json at all").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  assertEquals(verifyIdentityBinding(`header.${notJson}.sig`, "apple-user-b"), "apple_rejected");
});

Deno.test("verifyIdentityBinding: a payload with no sub claim fails closed", () => {
  const idToken = fakeIdToken({ aud: "com.wjdavis5.lunarlog" });

  assertEquals(verifyIdentityBinding(idToken, "apple-user-b"), "apple_rejected");
});

Deno.test("verifyIdentityBinding: an empty-string sub claim fails closed", () => {
  const idToken = fakeIdToken({ sub: "" });

  assertEquals(verifyIdentityBinding(idToken, "apple-user-b"), "apple_rejected");
});

Deno.test("verifyIdentityBinding: unpadded base64url (no trailing '=') decodes correctly", () => {
  // JWT payloads are base64url-encoded with padding stripped per spec; a
  // decoder that assumes 4-byte-aligned input without restoring padding
  // would fail on the (common) case where the payload's length isn't a
  // multiple of 4.
  const idToken = fakeIdToken({ sub: "s" });

  assertEquals(verifyIdentityBinding(idToken, "s"), "ok");
});

// ---------------------------------------------------------------------------
// Issue #1256: the dual-client-ID exchange (revokeAppleTokenWith)
// ---------------------------------------------------------------------------

const BUNDLE_ID = "com.wjdavis5.lunarlog";

/** A throwaway P-256 keypair's PKCS8 PEM - the stand-in `.p8`. Generated per
 * suite run, never any real key material. */
async function generateTestPrivateKeyPem(): Promise<string> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
  const pkcs8 = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  let binary = "";
  for (const byte of new Uint8Array(pkcs8)) binary += String.fromCharCode(byte);
  const base64 = btoa(binary);
  return `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
}

function testConfig(privateKeyPem: string): AppleRevokeConfig {
  return { teamId: "TEAMID1234", keyId: "KEYID1234", privateKey: privateKeyPem, appClientId: BUNDLE_ID };
}

/** Decodes a JWT segment (header or payload) the way the module under test
 * decodes the id_token payload: base64url with padding restored. */
function decodeJwtSegment(jwt: string, segment: 0 | 1): Record<string, unknown> {
  const parts = jwt.split(".");
  assertEquals(parts.length, 3, "client secret must be a three-segment JWT");
  let base64 = parts[segment].replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) base64 += "=";
  return JSON.parse(atob(base64)) as Record<string, unknown>;
}

function decodeJwtPayload(jwt: string): Record<string, unknown> {
  return decodeJwtSegment(jwt, 1);
}

interface RecordedRequest {
  url: string;
  form: URLSearchParams;
}

/** A stubbed Apple endpoint: answers the token call with a fake grant bound
 * to [appleUserId], the revoke call with 200, and records every form body so
 * a test can assert which client id and secret each call carried. */
function fakeApple(
  appleUserId: string,
  options: { tokenStatus?: number; revokeStatus?: number; reject?: boolean } = {},
) {
  const requests: RecordedRequest[] = [];
  const appleFetch: typeof fetch = async (input, init) => {
    const url = String(input);
    if (options.reject === true) throw new TypeError("simulated network failure");
    // Both Apple calls here send URLSearchParams bodies; a Response built
    // from the same BodyInit serialises it back to the form string.
    const raw = await new Response(init?.body ?? null).text();
    requests.push({ url, form: new URLSearchParams(raw) });
    if (url.endsWith("/auth/token")) {
      const status = options.tokenStatus ?? 200;
      const payload: Record<string, unknown> =
        status === 200
          ? { refresh_token: "fake-refresh-token", id_token: fakeIdToken({ sub: appleUserId }) }
          : { error: "invalid_client" };
      return new Response(JSON.stringify(payload), { status });
    }
    if (url.endsWith("/auth/revoke")) {
      return new Response("{}", { status: options.revokeStatus ?? 200 });
    }
    return new Response("{}", { status: 404 });
  };
  return { requests, appleFetch };
}

async function runRevoke(
  codeClient: AppleCodeClient,
  config: ReturnType<typeof testConfig> | null,
  appleFetch: typeof fetch,
  expectedAppleUserId = "apple-user-1",
) {
  return revokeAppleTokenWith("one-time-code", expectedAppleUserId, codeClient, config, appleFetch);
}

Deno.test("resolveAppleClientId: the web flow is the constant Services ID, the app flow the bundle id", () => {
  const config = testConfig("unused");
  assertEquals(resolveAppleClientId(config, "web"), APPLE_WEB_SERVICES_ID);
  assertEquals(resolveAppleClientId(config, "app"), BUNDLE_ID);
});

Deno.test("resolveAppleClientId: an app code without APPLE_CLIENT_ID is unconfigured; a web code is not", () => {
  const noBundle: AppleRevokeConfig = { teamId: "T", keyId: "K", privateKey: "P", appClientId: null };
  assertEquals(resolveAppleClientId(noBundle, "app"), null);
  assertEquals(resolveAppleClientId(noBundle, "web"), APPLE_WEB_SERVICES_ID);
});

Deno.test(
  "the dual-client exchange: a web code is exchanged with the Services ID as client_id and client-secret sub, " +
    "then revoked under the same id",
  async () => {
    const pem = await generateTestPrivateKeyPem();
    const { requests, appleFetch } = fakeApple("apple-user-1");

    const result = await runRevoke("web", testConfig(pem), appleFetch);

    assertEquals(result, { kind: "ok" });
    assertEquals(requests.length, 2);
    assertEquals(requests[0].url.endsWith("/auth/token"), true);
    assertEquals(requests[0].form.get("client_id"), APPLE_WEB_SERVICES_ID);
    assertEquals(decodeJwtPayload(requests[0].form.get("client_secret")!).sub, APPLE_WEB_SERVICES_ID);
    assertEquals(requests[1].url.endsWith("/auth/revoke"), true);
    assertEquals(requests[1].form.get("client_id"), APPLE_WEB_SERVICES_ID);
    assertEquals(
      decodeJwtPayload(requests[1].form.get("client_secret")!).sub,
      APPLE_WEB_SERVICES_ID,
    );
  },
);

Deno.test(
  "the dual-client exchange: an app code is exchanged with the bundle id as client_id and client-secret sub",
  async () => {
    const pem = await generateTestPrivateKeyPem();
    const { requests, appleFetch } = fakeApple("apple-user-1");

    const result = await runRevoke("app", testConfig(pem), appleFetch);

    assertEquals(result, { kind: "ok" });
    assertEquals(requests[0].form.get("client_id"), BUNDLE_ID);
    assertEquals(decodeJwtPayload(requests[0].form.get("client_secret")!).sub, BUNDLE_ID);
    assertEquals(requests[1].form.get("client_id"), BUNDLE_ID);
  },
);

Deno.test(
  "the dual-client exchange: the client secret stays a fresh short-lived ES256 JWT bound to Apple's " +
    "token endpoint and the configured team/key",
  async () => {
    const pem = await generateTestPrivateKeyPem();
    const { requests, appleFetch } = fakeApple("apple-user-1");

    await runRevoke("web", testConfig(pem), appleFetch);

    const payload = decodeJwtPayload(requests[0].form.get("client_secret")!);
    assertEquals(payload.iss, "TEAMID1234");
    assertEquals(payload.aud, "https://appleid.apple.com");
    const header = decodeJwtSegment(requests[0].form.get("client_secret")!, 0);
    assertEquals(header.kid, "KEYID1234");
    assertEquals(header.alg, "ES256");
  },
);

Deno.test("a web code with no config at all is misconfigured, never a skipped revocation", async () => {
  const pem = await generateTestPrivateKeyPem();
  const { requests, appleFetch } = fakeApple("apple-user-1");

  const result = await runRevoke("web", null, appleFetch);

  assertEquals(result, { kind: "misconfigured" });
  assertEquals(requests.length, 0);
});

Deno.test("an app code without APPLE_CLIENT_ID is misconfigured even with the other secrets set", async () => {
  const pem = await generateTestPrivateKeyPem();
  const { requests, appleFetch } = fakeApple("apple-user-1");
  const noBundle: AppleRevokeConfig = { teamId: "T", keyId: "K", privateKey: pem, appClientId: null };

  const result = await runRevoke("app", noBundle, appleFetch);

  assertEquals(result, { kind: "misconfigured" });
  assertEquals(requests.length, 0);
});

Deno.test("an unparseable private key is misconfigured for either client", async () => {
  const { requests, appleFetch } = fakeApple("apple-user-1");

  assertEquals(await runRevoke("web", testConfig("not-a-pem"), appleFetch), { kind: "misconfigured" });
  assertEquals(await runRevoke("app", testConfig("not-a-pem"), appleFetch), { kind: "misconfigured" });
  assertEquals(requests.length, 0);
});

Deno.test("Apple rejecting the token exchange is apple_rejected for either client", async () => {
  const pem = await generateTestPrivateKeyPem();
  const rejected = fakeApple("apple-user-1", { tokenStatus: 400 });

  assertEquals(await runRevoke("web", testConfig(pem), rejected.appleFetch), {
    kind: "apple_rejected",
  });
  assertEquals(await runRevoke("app", testConfig(pem), rejected.appleFetch), {
    kind: "apple_rejected",
  });
});

Deno.test("the identity binding still gates a web-code exchange: another Apple user's code is never revoked", async () => {
  const pem = await generateTestPrivateKeyPem();
  // The token endpoint answered with victim B's id_token; the caller is A.
  const { requests, appleFetch } = fakeApple("apple-user-victim-b");

  const result = await runRevoke("web", testConfig(pem), appleFetch, "apple-user-attacker");

  assertEquals(result, { kind: "identity_mismatch" });
  // The exchange happened, the revoke did not.
  assertEquals(requests.length, 1);
  assertEquals(requests[0].url.endsWith("/auth/token"), true);
});

Deno.test("a failed revoke call is apple_rejected after a successful web exchange", async () => {
  const pem = await generateTestPrivateKeyPem();
  const { appleFetch } = fakeApple("apple-user-1", { revokeStatus: 500 });

  const result = await runRevoke("web", testConfig(pem), appleFetch);

  assertEquals(result, { kind: "apple_rejected" });
});

Deno.test("a network failure reaches Apple's endpoint resolves to network, not a thrown error", async () => {
  const pem = await generateTestPrivateKeyPem();
  const { appleFetch } = fakeApple("apple-user-1", { reject: true });

  const result = await runRevoke("web", testConfig(pem), appleFetch);

  assertEquals(result, { kind: "network" });
});
