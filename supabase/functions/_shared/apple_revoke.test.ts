// _shared/apple_revoke.test.ts (Issue #560)
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

import { assertEquals } from "jsr:@std/assert@1";
import { verifyIdentityBinding } from "./apple_revoke.ts";

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
