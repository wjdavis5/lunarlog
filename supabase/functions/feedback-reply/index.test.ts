// index.test.ts (Issue #567 Deno-half refactor)
//
// `feedback-reply` previously had no `deno test` coverage at all, was absent
// from `deno.json`'s `test.include`, and was never `deno check`ed in CI.
// `handleFeedbackReply` takes all real I/O as injected `FeedbackReplyDeps`,
// so every case here runs with fakes: no live Supabase project, no Resend
// key, no network. The shared-webhook-secret check itself lives in the
// `import.meta.main` block (see index.ts's header comment on why), so it is
// not exercised here - mirroring push-dispatch/index.test.ts's identical
// split.
//
// Run locally with `deno test supabase/functions/feedback-reply/`.

import { assertEquals } from "jsr:@std/assert@1";
import {
  buildDeps,
  handleFeedbackReply,
  type FeedbackReplyDeps,
  type FeedbackReplyEnv,
  type FeedbackReplyTicketRow,
  type SupabaseClientFactory,
} from "./index.ts";
import type { SendEmailResult } from "../_shared/email.ts";

function baseTicket(overrides: Partial<FeedbackReplyTicketRow> = {}): FeedbackReplyTicketRow {
  return {
    id: "t-123",
    category: "bug",
    reply_email: "user@example.test",
    device_info: { app_version: "1.2.3" },
    created_at: "2026-09-05T00:00:00.000Z",
    ...overrides,
  };
}

function webhookRequest(record: Record<string, unknown> | undefined): Request {
  return new Request("https://example.test/feedback-reply", {
    method: "POST",
    body: JSON.stringify(record === undefined ? {} : { record }),
  });
}

function fakeDeps(overrides: {
  ticket?: FeedbackReplyTicketRow | null;
  sendResult?: SendEmailResult;
} = {}): FeedbackReplyDeps & { sendEmailCalls: Array<{ ticketId: string; message: string }> } {
  const ticket = overrides.ticket === undefined ? baseTicket() : overrides.ticket;
  const sendEmailCalls: Array<{ ticketId: string; message: string }> = [];

  return {
    configured: true,
    getTicket: async (ticketId) => (ticket && ticket.id === ticketId ? { ...ticket } : null),
    sendEmail: async (summary, message) => {
      sendEmailCalls.push({ ticketId: summary.id, message });
      return overrides.sendResult ?? { ok: true };
    },
    get sendEmailCalls() {
      return sendEmailCalls;
    },
  };
}

Deno.test("a malformed JSON body is rejected with 400", async () => {
  const deps = fakeDeps();
  const request = new Request("https://example.test/feedback-reply", { method: "POST", body: "not json" });

  const response = await handleFeedbackReply(request, deps);

  assertEquals(response.status, 400);
});

Deno.test("a user-authored reply (author_type != admin) sends nothing and returns 204", async () => {
  const deps = fakeDeps();

  const response = await handleFeedbackReply(
    webhookRequest({ author_type: "user", ticket_id: "t-123", message: "thanks!" }),
    deps,
  );

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls.length, 0);
});

Deno.test("a missing record in the payload sends nothing and returns 204", async () => {
  const deps = fakeDeps();

  const response = await handleFeedbackReply(webhookRequest(undefined), deps);

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls.length, 0);
});

Deno.test("a record missing ticket_id or message sends nothing and returns 204", async () => {
  const deps = fakeDeps();

  const response = await handleFeedbackReply(
    webhookRequest({ author_type: "admin", ticket_id: "t-123" }),
    deps,
  );

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls.length, 0);
});

Deno.test("missing config degrades to 204 with no send attempted", async () => {
  const deps = fakeDeps();
  deps.configured = false;

  const response = await handleFeedbackReply(
    webhookRequest({ author_type: "admin", ticket_id: "t-123", message: "hello" }),
    deps,
  );

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls.length, 0);
});

Deno.test("a ticket that can't be found sends nothing and returns 204", async () => {
  const deps = fakeDeps({ ticket: null });

  const response = await handleFeedbackReply(
    webhookRequest({ author_type: "admin", ticket_id: "does-not-exist", message: "hello" }),
    deps,
  );

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls.length, 0);
});

Deno.test("an admin reply for a real ticket sends the reply email with the ticket's reply_email and message", async () => {
  const deps = fakeDeps({ ticket: baseTicket({ id: "t-123", reply_email: "someone@example.test" }) });

  const response = await handleFeedbackReply(
    webhookRequest({ author_type: "admin", ticket_id: "t-123", message: "we fixed it!" }),
    deps,
  );

  assertEquals(response.status, 204);
  assertEquals(deps.sendEmailCalls, [{ ticketId: "t-123", message: "we fixed it!" }]);
});

Deno.test(
  "#567: a failed sendEmail is logged and answered with a non-2xx status, not silently swallowed as 204",
  async () => {
    const deps = fakeDeps({ sendResult: { ok: false, reason: "resend_status_500" } });

    const originalError = console.error;
    const calls: unknown[][] = [];
    console.error = (...args: unknown[]) => {
      calls.push(args);
    };
    let response;
    try {
      response = await handleFeedbackReply(
        webhookRequest({ author_type: "admin", ticket_id: "t-123", message: "hello" }),
        deps,
      );
    } finally {
      console.error = originalError;
    }

    assertEquals(response.status, 502, "a send failure must not be reported as if it succeeded (old behavior: always 204)");
    assertEquals(calls.length, 1, "a send failure must be logged - previously this was completely silent");
    assertEquals(String(calls[0][0]).includes("sendEmail failed"), true);
  },
);

// ---------------------------------------------------------------------------
// buildDeps: the production wiring.
// ---------------------------------------------------------------------------

function fakeClientFactory(rows: FeedbackReplyTicketRow[]): SupabaseClientFactory {
  const client = {
    from(table: string) {
      if (table !== "feedback_tickets") {
        throw new Error(`fakeClientFactory: unexpected table ${table}`);
      }
      return {
        select(_columns: string) {
          return {
            eq(_column: string, value: unknown) {
              return {
                async single() {
                  const found = rows.find((row) => row.id === value);
                  return found ? { data: { ...found }, error: null } : { data: null, error: { message: "not found" } };
                },
              };
            },
          };
        },
      };
    },
  };
  return () => client;
}

const fullEnv: FeedbackReplyEnv = {
  supabaseUrl: "https://example.test",
  serviceRoleKey: "service-role-key",
};

Deno.test("buildDeps: configured is false when supabaseUrl or serviceRoleKey is missing", () => {
  const deps = buildDeps({ supabaseUrl: undefined, serviceRoleKey: "key" }, fakeClientFactory([]));
  assertEquals(deps.configured, false);
});

Deno.test("buildDeps: getTicket returns the matching row via the production query shape", async () => {
  const deps = buildDeps(fullEnv, fakeClientFactory([baseTicket({ id: "t-999" })]));

  const ticket = await deps.getTicket("t-999");

  assertEquals(ticket?.id, "t-999");
});

Deno.test("buildDeps: getTicket returns null when no row matches", async () => {
  const deps = buildDeps(fullEnv, fakeClientFactory([]));

  const ticket = await deps.getTicket("missing");

  assertEquals(ticket, null);
});
