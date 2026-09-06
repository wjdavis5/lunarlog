// _shared/format.test.ts (Issue #6, U9)
// Run locally with `deno test supabase/functions/_shared/`. Also runs in CI
// via the `edge-functions` job in `.github/workflows/ci.yml` (PR #105 review
// round 3).

import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildAdminAlert, buildReplyEmail, type FeedbackTicketSummary } from "./format.ts";

const baseTicket: FeedbackTicketSummary = {
  id: "t-123",
  category: "bug",
  appVersion: "1.2.3",
  createdAt: "2026-09-05T00:00:00.000Z",
  replyEmail: "user@example.com",
};

Deno.test("buildAdminAlert includes ticket id, category, app version, and created-at", () => {
  const envelope = buildAdminAlert(baseTicket, "admin@wjd.io");
  assertStringIncludes(envelope.text, "t-123");
  assertStringIncludes(envelope.text, "Bug");
  assertStringIncludes(envelope.text, "1.2.3");
  assertStringIncludes(envelope.text, "2026-09-05T00:00:00.000Z");
  assertStringIncludes(envelope.html, "t-123");
  assertStringIncludes(envelope.html, "1.2.3");
  assertEquals(envelope.to, "admin@wjd.io");
});

Deno.test("buildAdminAlert excludes the message body, reply email, and every attachment path", () => {
  const envelope = buildAdminAlert(baseTicket, "admin@wjd.io");
  assert(!envelope.text.includes("user@example.com"));
  assert(!envelope.html.includes("user@example.com"));
  // There is no message-body parameter on buildAdminAlert at all, so this
  // also proves the function has no way to leak one.
  assert(!envelope.text.toLowerCase().includes("message"));
});

Deno.test("buildReplyEmail includes the admin reply text, the ticket category, and addresses reply_email", () => {
  const envelope = buildReplyEmail(baseTicket, { message: "We shipped a fix for this." });
  assertStringIncludes(envelope.text, "We shipped a fix for this.");
  assertStringIncludes(envelope.html, "We shipped a fix for this.");
  assertStringIncludes(envelope.text, "Bug");
  assertEquals(envelope.to, "user@example.com");
});

Deno.test("buildReplyEmail escapes content that would break the email body structure", () => {
  const envelope = buildReplyEmail(baseTicket, {
    message: "<script>alert(1)</script> & \"quoted\"\nsecond line",
  });
  assert(!envelope.html.includes("<script>"));
  assertStringIncludes(envelope.html, "&lt;script&gt;");
  assertStringIncludes(envelope.html, "&amp;");
  assertStringIncludes(envelope.html, "&quot;quoted&quot;");
  assertStringIncludes(envelope.html, "<br>");
});

const categories = ["bug", "feature_request", "support", "other"];

Deno.test("both builders produce a non-empty subject for every FeedbackCategory value", () => {
  for (const category of categories) {
    const ticket: FeedbackTicketSummary = { ...baseTicket, category };
    const alert = buildAdminAlert(ticket, "admin@wjd.io");
    const reply = buildReplyEmail(ticket, { message: "hi" });
    assert(alert.subject.length > 0, `admin alert subject empty for ${category}`);
    assert(reply.subject.length > 0, `reply subject empty for ${category}`);
  }
});
