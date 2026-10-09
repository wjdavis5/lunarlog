// webhook_secret.test.ts (issue #1740)
//
// The shared constant-time webhook-secret comparison both webhook
// functions now use. The tests pin the contract the comparison must keep:
// identical secrets match; anything else — a same-length difference, a
// prefix, a different length, a missing or empty expected secret, a
// missing header — never matches.

import { assertEquals } from "jsr:@std/assert@1";

import { webhookSecretsMatch } from "./webhook_secret.ts";

Deno.test("webhookSecretsMatch: an identical secret matches", async () => {
  assertEquals(await webhookSecretsMatch("s3cret-value", "s3cret-value"), true);
});

Deno.test("webhookSecretsMatch: a same-length different secret does not match", async () => {
  assertEquals(await webhookSecretsMatch("s3cret-value", "s3cret-walue"), false);
});

Deno.test("webhookSecretsMatch: a correct prefix does not match", async () => {
  assertEquals(await webhookSecretsMatch("s3cret-value", "s3cret"), false);
  assertEquals(await webhookSecretsMatch("s3cret", "s3cret-value"), false);
});

Deno.test("webhookSecretsMatch: a missing or empty expected secret never matches", async () => {
  assertEquals(await webhookSecretsMatch(undefined, "anything"), false);
  assertEquals(await webhookSecretsMatch("", "anything"), false);
  assertEquals(await webhookSecretsMatch("", ""), false);
});

Deno.test("webhookSecretsMatch: a missing header never matches", async () => {
  assertEquals(await webhookSecretsMatch("s3cret-value", null), false);
});
