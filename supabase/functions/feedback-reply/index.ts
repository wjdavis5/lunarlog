// feedback-reply (Issue #6, U9)
//
// Database Webhook target (Database → Webhooks on `public.feedback_replies`
// INSERT), configured in the dashboard rather than a migration (KTD7) — see
// docs/ops/supabase-go-live.md's Feedback section. Validates the shared
// webhook secret header (the webhook config sets it as a custom header;
// this function never accepts a request without a matching value), ignores
// any payload whose `author_type` isn't `admin`, loads the parent ticket
// for `reply_email`, and sends the reply email. Its absence degrades to
// "no reply email sent" — the reply is still visible in Support history.

import { createClient } from "@supabase/supabase-js";
import { buildReplyEmail, type FeedbackTicketSummary } from "../_shared/format.ts";
import { sendEmail } from "../_shared/email.ts";

const WEBHOOK_SECRET_HEADER = "x-feedback-webhook-secret";

function appVersionFrom(deviceInfo: unknown): string {
  if (deviceInfo && typeof deviceInfo === "object") {
    const value = (deviceInfo as Record<string, unknown>)["app_version"];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return "unknown";
}

Deno.serve(async (req) => {
  const expectedSecret = Deno.env.get("FEEDBACK_WEBHOOK_SECRET");
  const providedSecret = req.headers.get(WEBHOOK_SECRET_HEADER);
  if (!expectedSecret || providedSecret !== expectedSecret) {
    return new Response(null, { status: 401 });
  }

  let payload: { record?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return new Response(null, { status: 400 });
  }

  const record = payload.record;
  if (!record || record["author_type"] !== "admin") {
    // A user-authored reply, or a malformed payload: nothing to send.
    return new Response(null, { status: 204 });
  }

  const ticketId = record["ticket_id"];
  const message = record["message"];
  if (typeof ticketId !== "string" || typeof message !== "string") {
    return new Response(null, { status: 204 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return new Response(null, { status: 204 });
  }

  try {
    const client = createClient(supabaseUrl, serviceRoleKey);
    const { data: ticket, error } = await client
      .from("feedback_tickets")
      .select("id, category, reply_email, device_info, created_at")
      .eq("id", ticketId)
      .single();

    if (error || !ticket) {
      return new Response(null, { status: 204 });
    }

    const summary: FeedbackTicketSummary = {
      id: ticket.id as string,
      category: ticket.category as string,
      appVersion: appVersionFrom(ticket.device_info),
      createdAt: ticket.created_at as string,
      replyEmail: ticket.reply_email as string,
    };
    await sendEmail(buildReplyEmail(summary, { message }));
  } catch (_error) {
    // Degrade silently; the reply is already visible in Support history.
  }

  return new Response(null, { status: 204 });
});
