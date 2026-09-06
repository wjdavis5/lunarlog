// feedback-notify (Issue #6, U9)
//
// Invoked by the client, best-effort, right after a successful
// feedback_tickets insert (`client.functions.invoke('feedback-notify', ...)`
// in SupabaseFeedbackService). Verified by the platform's own JWT check
// (`verify_jwt = true` in supabase/config.toml); this handler re-reads the
// ticket with the service-role client rather than trusting anything the
// caller sent beyond the ticket id, and never echoes ticket content in its
// response (R21).
//
// Thin by design (KTD6): all real logic lives in `_shared/format.ts`
// (tested) and `_shared/email.ts`.

import { createClient } from "@supabase/supabase-js";
import { buildAdminAlert, type FeedbackTicketSummary } from "../_shared/format.ts";
import { sendEmail } from "../_shared/email.ts";

function appVersionFrom(deviceInfo: unknown): string {
  if (deviceInfo && typeof deviceInfo === "object") {
    const value = (deviceInfo as Record<string, unknown>)["app_version"];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return "unknown";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(null, { status: 405 });
  }

  let body: { ticket_id?: unknown };
  try {
    body = await req.json();
  } catch {
    return new Response(null, { status: 400 });
  }

  const ticketId = typeof body.ticket_id === "string" ? body.ticket_id : null;
  if (!ticketId) {
    return new Response(null, { status: 400 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const adminEmail = Deno.env.get("FEEDBACK_ADMIN_EMAIL");

  // Missing config degrades to "no alert sent" rather than a visible
  // failure — this call is best-effort from the client's perspective.
  if (!supabaseUrl || !serviceRoleKey || !adminEmail) {
    return new Response(null, { status: 204 });
  }

  try {
    const client = createClient(supabaseUrl, serviceRoleKey);
    const { data: ticket, error } = await client
      .from("feedback_tickets")
      .select("id, category, device_info, created_at")
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
      replyEmail: "",
    };
    await sendEmail(buildAdminAlert(summary, adminEmail));
  } catch (_error) {
    // Never surface provider detail; this endpoint's contract is 204
    // either way (R21's best-effort promise extends to this handler).
  }

  return new Response(null, { status: 204 });
});
