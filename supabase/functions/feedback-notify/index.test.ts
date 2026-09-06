// index.test.ts (Issue #6, U9; PR #105 review round 3)
//
// Covers the ownership check and replay guard added in PR #105 review round
// 2 (previously zero automated coverage - `deno.json` only discovered
// `_shared/**` tests, and CI runs no `deno test` step at all for this
// function). `handleFeedbackNotify` takes all real I/O as injected
// `FeedbackNotifyDeps`, so every case here runs with fakes: no live
// Supabase project, no Resend key, no network.
//
// Run locally with `deno test supabase/functions/feedback-notify/`.

import { assertEquals } from "jsr:@std/assert@1";
import { handleFeedbackNotify, type FeedbackNotifyDeps, type FeedbackTicketRow } from "./index.ts";
import type { SendEmailResult } from "../_shared/email.ts";

function baseTicket(overrides: Partial<FeedbackTicketRow> = {}): FeedbackTicketRow {
  return {
    id: "t-123",
    user_id: "owner-1",
    category: "bug",
    device_info: { app_version: "1.2.3" },
    created_at: "2026-09-05T00:00:00.000Z",
    notified_at: null,
    ...overrides,
  };
}

function postRequest(ticketId: unknown, { withAuth = true }: { withAuth?: boolean } = {}): Request {
  return new Request("https://example.test/feedback-notify", {
    method: "POST",
    headers: withAuth ? { Authorization: "Bearer caller-jwt" } : {},
    body: JSON.stringify({ ticket_id: ticketId }),
  });
}

/** A deps fake with an in-memory single-ticket "table" so claimNotification
 * can emulate the real `UPDATE ... WHERE notified_at IS NULL` atomicity:
 * it only succeeds, and only mutates state, the first time it runs for a
 * still-unclaimed ticket. */
function fakeDeps(overrides: {
  callerId?: string | null;
  ticket?: FeedbackTicketRow | null;
  sendResult?: SendEmailResult | ((call: number) => SendEmailResult);
} = {}): FeedbackNotifyDeps & { sendEmailCalls: number; claimCalls: number } {
  const ticket = overrides.ticket === undefined ? baseTicket() : overrides.ticket;
  let sendEmailCalls = 0;
  let claimCalls = 0;

  const deps: FeedbackNotifyDeps & { sendEmailCalls: number; claimCalls: number } = {
    configured: true,
    resolveCallerId: async () => (overrides.callerId === undefined ? "owner-1" : overrides.callerId),
    getTicket: async (ticketId) => {
      if (!ticket || ticket.id !== ticketId) return null;
      return { ...ticket };
    },
    claimNotification: async (ticketId) => {
      claimCalls++;
      if (!ticket || ticket.id !== ticketId || ticket.notified_at) return false;
      ticket.notified_at = new Date().toISOString();
      return true;
    },
    sendEmail: async () => {
      const result = overrides.sendResult ?? { ok: true };
      const resolved = typeof result === "function" ? result(sendEmailCalls) : result;
      sendEmailCalls++;
      return resolved;
    },
    get sendEmailCalls() {
      return sendEmailCalls;
    },
    get claimCalls() {
      return claimCalls;
    },
  };
  return deps;
}

Deno.test("ownership check: a caller who does not own the ticket gets 204 and no email is sent", async () => {
  const deps = fakeDeps({
    callerId: "attacker-2",
    ticket: baseTicket({ user_id: "owner-1" }),
  });

  const response = await handleFeedbackNotify(postRequest("t-123"), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 0, "the non-owner's call must never trigger the admin alert");
  assertEquals(deps.claimCalls, 0);
});

Deno.test("ownership check: the ticket's own owner calling with their own ticket_id gets the alert sent", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: baseTicket({ user_id: "owner-1" }) });

  const response = await handleFeedbackNotify(postRequest("t-123"), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 1);
});

Deno.test("ownership check: a guessed ticket_id that doesn't exist gets the same 204 as an unowned one", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: null });

  const response = await handleFeedbackNotify(postRequest("does-not-exist"), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 0);
});

Deno.test("replay guard: calling twice for the same ticket sends the alert only once", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: baseTicket() });

  const first = await handleFeedbackNotify(postRequest("t-123"), deps);
  const second = await handleFeedbackNotify(postRequest("t-123"), deps);

  assertEquals(first.status, 204);
  assertEquals(second.status, 204);
  assertEquals(deps.sendEmailCalls, 1, "a second call for an already-notified ticket must not re-send");
});

Deno.test("replay guard: three calls in a row still send exactly one email", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: baseTicket() });

  for (let i = 0; i < 3; i++) {
    await handleFeedbackNotify(postRequest("t-123"), deps);
  }

  assertEquals(deps.sendEmailCalls, 1);
});

Deno.test("a failed send is not claimed as notified, so a later retry can still succeed", async () => {
  const deps = fakeDeps({
    callerId: "owner-1",
    ticket: baseTicket(),
    sendResult: (call) => (call === 0 ? { ok: false, reason: "resend_status_500" } : { ok: true }),
  });

  const first = await handleFeedbackNotify(postRequest("t-123"), deps);
  assertEquals(first.status, 502);
  assertEquals(deps.claimCalls, 0, "a failed send must never claim notified_at");

  const second = await handleFeedbackNotify(postRequest("t-123"), deps);
  assertEquals(second.status, 204);
  assertEquals(deps.sendEmailCalls, 2, "the retry after a failed send must actually attempt to send again");
});

Deno.test("missing config degrades to 204 with no send attempted", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: baseTicket() });
  deps.configured = false;

  const response = await handleFeedbackNotify(postRequest("t-123"), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 0);
});

Deno.test("a missing Authorization header gets 204 with no send attempted", async () => {
  const deps = fakeDeps({ callerId: "owner-1", ticket: baseTicket() });

  const response = await handleFeedbackNotify(postRequest("t-123", { withAuth: false }), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 0);
});

Deno.test("an invalid caller identity (resolveCallerId returns null) gets 204 with no send attempted", async () => {
  const deps = fakeDeps({ callerId: null, ticket: baseTicket() });

  const response = await handleFeedbackNotify(postRequest("t-123"), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, 0);
});

Deno.test("a non-POST method is rejected with 405 regardless of config", async () => {
  const deps = fakeDeps();
  const request = new Request("https://example.test/feedback-notify", { method: "GET" });

  const response = await handleFeedbackNotify(request, deps);

  assertEquals(response.status, 405);
});

Deno.test("a missing ticket_id in the body is rejected with 400", async () => {
  const deps = fakeDeps();
  const request = new Request("https://example.test/feedback-notify", {
    method: "POST",
    headers: { Authorization: "Bearer caller-jwt" },
    body: JSON.stringify({}),
  });

  const response = await handleFeedbackNotify(request, deps);

  assertEquals(response.status, 400);
});
