import { assertEquals, assertExists, assertNotEquals } from "jsr:@std/assert@^1.0.0";
import worker, { isAuthorized } from "./index.ts";
import { extractAuthLinks, extractOtpCode, normalizeEmail, parseInboundEmail } from "./parser.ts";
import { EmailStore, formatInvertedTimestamp, MemoryKV } from "./store.ts";
import type { Env, ExecutionContext, ForwardableEmailMessage, ParsedEmailData } from "./types.ts";

function createMockStream(content: string): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(content));
      controller.close();
    },
  });
}

function createMockEmailMessage(
  from: string,
  to: string,
  rawContent: string,
): { message: ForwardableEmailMessage; rejectedReason: () => string | null } {
  let rejected: string | null = null;
  const message: ForwardableEmailMessage = {
    from,
    to,
    headers: new Headers(),
    raw: createMockStream(rawContent),
    rawSize: rawContent.length,
    setReject(reason: string) {
      rejected = reason;
    },
    async forward() {},
    async reply() {},
  };
  return {
    message,
    rejectedReason: () => rejected,
  };
}

function createMockExecutionContext(): {
  ctx: ExecutionContext;
  waitUntilPromises: Promise<unknown>[];
} {
  const waitUntilPromises: Promise<unknown>[] = [];
  const ctx: ExecutionContext = {
    waitUntil(promise: Promise<unknown>) {
      waitUntilPromises.push(promise);
    },
    passThroughOnException() {},
  };
  return { ctx, waitUntilPromises };
}

// ---------------------------------------------------------------------------
// Parser Tests
// ---------------------------------------------------------------------------

Deno.test("parser: extractOtpCode extracts 8-digit and 6-digit codes", () => {
  assertEquals(
    extractOtpCode("Your confirmation code is 84920183. Never share this code."),
    "84920183",
  );
  assertEquals(
    extractOtpCode("Login with 123456 to verify"),
    "123456",
  );
  // Prioritizes 8-digit over 6-digit
  assertEquals(
    extractOtpCode("Old code 112233, new 8-digit code 99887766."),
    "99887766",
  );
  assertEquals(extractOtpCode("No code here at all."), undefined);
});

Deno.test("parser: extractAuthLinks extracts URLs and ignores XML namespaces", () => {
  const content = `
    Click https://app.lunarlog.app/auth/callback?code=abc123xyz to log in.
    Also custom link lunarlog://auth-callback?token_hash=token456!
    Ignored: http://www.w3.org/1999/xhtml
  `;
  const links = extractAuthLinks(content);
  assertEquals(links.length, 2);
  assertEquals(links.includes("https://app.lunarlog.app/auth/callback?code=abc123xyz"), true);
  assertEquals(links.includes("lunarlog://auth-callback?token_hash=token456"), true);
});

Deno.test("parser: normalizeEmail converts lowercase and trims", () => {
  assertEquals(normalizeEmail("  Test.User@LunarLog.APP  "), "test.user@lunarlog.app");
});

Deno.test("parser: parseInboundEmail parses RFC 5322 MIME stream", async () => {
  const mime = [
    "From: Lunarlog <noreply@lunarlog.app>",
    "To: Test Recipient <test-123@inbound.lunarlog.app>",
    "Subject: Confirm your signup",
    "Message-ID: <unique-msg-id-123@lunarlog.app>",
    "",
    "Welcome to Lunarlog! Your confirmation code is 58492018.",
    "Or click: https://dleexnnevuuddcgcpztq.supabase.co/auth/v1/verify?token=pkce999&type=signup",
  ].join("\r\n");

  const stream = createMockStream(mime);
  const parsed = await parseInboundEmail(stream);

  assertEquals(parsed.id, "unique-msg-id-123@lunarlog.app");
  assertEquals(parsed.from, "noreply@lunarlog.app");
  assertEquals(parsed.to, "test-123@inbound.lunarlog.app");
  assertEquals(parsed.subject, "Confirm your signup");
  assertEquals(parsed.otpCode, "58492018");
  assertExists(parsed.authLinks);
  assertEquals(parsed.authLinks.length, 1);
  assertEquals(
    parsed.authLinks[0],
    "https://dleexnnevuuddcgcpztq.supabase.co/auth/v1/verify?token=pkce999&type=signup",
  );
});

// ---------------------------------------------------------------------------
// Store Tests
// ---------------------------------------------------------------------------

Deno.test("store: formatInvertedTimestamp sorts descending lexicographically", () => {
  const earlierMs = 1700000000000;
  const laterMs = 1700000001000;

  const earlierKey = formatInvertedTimestamp(earlierMs);
  const laterKey = formatInvertedTimestamp(laterMs);

  // In descending order, later timestamp must sort before earlier timestamp
  assertEquals(laterKey < earlierKey, true);
});

Deno.test("store: saveEmail, getEmailById, and getLatestEmail", async () => {
  const kv = new MemoryKV();
  const store = new EmailStore(kv);

  const email1: ParsedEmailData = {
    id: "msg-1",
    from: "noreply@lunarlog.app",
    to: "user@inbound.lunarlog.app",
    subject: "First email",
    receivedAt: new Date(1700000000000).toISOString(),
    text: "Code: 11111111",
    otpCode: "11111111",
    authLinks: [],
  };

  const email2: ParsedEmailData = {
    id: "msg-2",
    from: "noreply@lunarlog.app",
    to: "user@inbound.lunarlog.app",
    subject: "Second email",
    receivedAt: new Date(1700000010000).toISOString(),
    text: "Code: 22222222",
    otpCode: "22222222",
    authLinks: [],
  };

  await store.saveEmail(email1);
  await store.saveEmail(email2);

  const byId = await store.getEmailById("msg-1");
  assertEquals(byId?.subject, "First email");

  const latest = await store.getLatestEmail("user@inbound.lunarlog.app");
  assertEquals(latest?.id, "msg-2");
  assertEquals(latest?.otpCode, "22222222");

  const list = await store.listEmailsByRecipient("user@inbound.lunarlog.app");
  assertEquals(list.length, 2);
  // First item in list must be newest (msg-2)
  assertEquals(list[0].id, "msg-2");
  assertEquals(list[1].id, "msg-1");

  // Deletion
  const deleted = await store.deleteEmailById("msg-2");
  assertEquals(deleted, true);
  const afterDelete = await store.getEmailById("msg-2");
  assertEquals(afterDelete, null);
});

// ---------------------------------------------------------------------------
// Worker fetch API Tests
// ---------------------------------------------------------------------------

Deno.test("fetch: /health endpoint returns 200 without auth", async () => {
  const env: Env = {
    EMAIL_API_KEY: "secret-key",
  };
  const { ctx } = createMockExecutionContext();

  const req = new Request("https://email.lunarlog.app/health");
  const res = await worker.fetch(req, env, ctx);

  assertEquals(res.status, 200);
  const json = await res.json() as { status: string; service: string };
  assertEquals(json.status, "ok");
  assertEquals(json.service, "lunarlog-inbound-email");
});

Deno.test("fetch: isAuthorized validates Bearer and X-API-Key headers", () => {
  const env: Env = { EMAIL_API_KEY: "supersecret" };

  const validBearer = new Request("https://email.lunarlog.app/api/emails", {
    headers: { Authorization: "Bearer supersecret" },
  });
  assertEquals(isAuthorized(validBearer, env), true);

  const validApiKey = new Request("https://email.lunarlog.app/api/emails", {
    headers: { "X-API-Key": "supersecret" },
  });
  assertEquals(isAuthorized(validApiKey, env), true);

  const invalid = new Request("https://email.lunarlog.app/api/emails", {
    headers: { Authorization: "Bearer wrong" },
  });
  assertEquals(isAuthorized(invalid, env), false);

  const missing = new Request("https://email.lunarlog.app/api/emails");
  assertEquals(isAuthorized(missing, env), false);
});

Deno.test("fetch: API endpoints require auth when key is set", async () => {
  const env: Env = {
    INBOUND_EMAILS: new MemoryKV(),
    EMAIL_API_KEY: "prod-key",
  };
  const { ctx } = createMockExecutionContext();

  const unauthReq = new Request("https://email.lunarlog.app/api/emails/latest?recipient=test@inbound.lunarlog.app");
  const unauthRes = await worker.fetch(unauthReq, env, ctx);
  assertEquals(unauthRes.status, 401);

  const authReq = new Request("https://email.lunarlog.app/api/emails/latest?recipient=test@inbound.lunarlog.app", {
    headers: { Authorization: "Bearer prod-key" },
  });
  const authRes = await worker.fetch(authReq, env, ctx);
  // Not found (404) because no email exists yet, but authentication passed (not 401)
  assertEquals(authRes.status, 404);
});

Deno.test("fetch: simulate endpoint and query retrieval", async () => {
  const env: Env = {
    INBOUND_EMAILS: new MemoryKV(),
    EMAIL_API_KEY: "test-key",
  };
  const { ctx } = createMockExecutionContext();

  const simReq = new Request("https://email.lunarlog.app/api/emails/simulate", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer test-key",
    },
    body: JSON.stringify({
      from: "noreply@lunarlog.app",
      to: "sim-user@inbound.lunarlog.app",
      subject: "Your OTP is 73829104",
      text: "Use code 73829104 to log into Lunarlog.",
    }),
  });

  const simRes = await worker.fetch(simReq, env, ctx);
  assertEquals(simRes.status, 201);
  const simJson = await simRes.json() as { success: boolean; email: ParsedEmailData };
  assertEquals(simJson.success, true);
  assertEquals(simJson.email.otpCode, "73829104");

  // Query latest
  const latestReq = new Request(
    "https://email.lunarlog.app/api/emails/latest?recipient=sim-user@inbound.lunarlog.app",
    {
      headers: { Authorization: "Bearer test-key" },
    },
  );
  const latestRes = await worker.fetch(latestReq, env, ctx);
  assertEquals(latestRes.status, 200);
  const latestJson = await latestRes.json() as { email: ParsedEmailData };
  assertEquals(latestJson.email.otpCode, "73829104");

  // Query list
  const listReq = new Request(
    "https://email.lunarlog.app/api/emails?recipient=sim-user@inbound.lunarlog.app",
    {
      headers: { Authorization: "Bearer test-key" },
    },
  );
  const listRes = await worker.fetch(listReq, env, ctx);
  assertEquals(listRes.status, 200);
  const listJson = await listRes.json() as { emails: ParsedEmailData[] };
  assertEquals(listJson.emails.length, 1);
  assertEquals(listJson.emails[0].otpCode, "73829104");
});

// ---------------------------------------------------------------------------
// Worker email handler Tests
// ---------------------------------------------------------------------------

Deno.test("worker email handler processes inbound message into KV", async () => {
  const kv = new MemoryKV();
  const env: Env = {
    INBOUND_EMAILS: kv,
  };
  const { ctx } = createMockExecutionContext();

  const rawMime = [
    "From: Lunarlog Auth <noreply@lunarlog.app>",
    "To: Inbound Test <auth-test@inbound.lunarlog.app>",
    "Subject: Sign in to your account",
    "",
    "Your 8-digit verification code is 91827364.",
    "Or open this link on your device: https://app.lunarlog.app/auth/callback?code=mock_code",
  ].join("\r\n");

  const { message, rejectedReason } = createMockEmailMessage(
    "noreply@lunarlog.app",
    "auth-test@inbound.lunarlog.app",
    rawMime,
  );

  await worker.email(message, env, ctx);

  assertEquals(rejectedReason(), null);

  const store = new EmailStore(kv);
  const stored = await store.getLatestEmail("auth-test@inbound.lunarlog.app");
  assertExists(stored);
  assertEquals(stored.otpCode, "91827364");
  assertEquals(stored.authLinks.length, 1);
  assertEquals(stored.authLinks[0], "https://app.lunarlog.app/auth/callback?code=mock_code");
});

Deno.test("worker email handler triggers setReject on unparseable stream error", async () => {
  const env: Env = {
    INBOUND_EMAILS: new MemoryKV(),
  };
  const { ctx } = createMockExecutionContext();

  let rejectCalled = false;
  const errorStream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.error(new Error("Stream read failure"));
    },
  });

  const message: ForwardableEmailMessage = {
    from: "sender@example.com",
    to: "dest@inbound.lunarlog.app",
    headers: new Headers(),
    raw: errorStream,
    rawSize: 0,
    setReject(_reason: string) {
      rejectCalled = true;
    },
    async forward() {},
    async reply() {},
  };

  await worker.email(message, env, ctx);
  assertEquals(rejectCalled, true);
});

