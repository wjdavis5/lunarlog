// feedback-notify (Issue #6, U9)
//
// Invoked by the client, best-effort, right after a successful
// feedback_tickets insert (`client.functions.invoke('feedback-notify', ...)`
// in SupabaseFeedbackService). `verify_jwt = true` (supabase/config.toml)
// only proves the caller is *someone* signed in - it says nothing about
// which ticket they may notify on - so this handler adds two checks of its
// own before it will use the service-role key to send anything:
//
//   1. Ownership: the caller's own JWT (forwarded in Authorization, read
//      with the anon key rather than trusted as a raw claim) must name the
//      auth id that owns the ticket. Without this, any signed-in account
//      could pass an arbitrary or guessed ticket_id and get an admin email
//      sent on someone else's behalf.
//   2. Replay/rate: an atomic `UPDATE ... WHERE notified_at IS NULL` claims
//      the notification; a ticket can only ever be claimed once, so calling
//      this repeatedly for the same ticket (accidentally or to flood the
//      admin inbox / burn the Resend quota) sends at most one email.
//
// A missing/invalid caller identity, an unowned or already-notified ticket,
// and a not-found ticket all degrade to the same 204 - this endpoint never
// echoes ticket content or existence in its response (R21).
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
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const adminEmail = Deno.env.get("FEEDBACK_ADMIN_EMAIL");

  // Missing config degrades to "no alert sent" rather than a visible
  // failure — this call is best-effort from the client's perspective.
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !adminEmail) {
    return new Response(null, { status: 204 });
  }

  // Ownership check: identify the caller from their own forwarded JWT
  // (never from anything in the request body) before touching the
  // service-role client at all.
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(null, { status: 204 });
  }

  try {
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerData, error: callerError } = await callerClient.auth.getUser();
    const callerId = callerData?.user?.id;
    if (callerError || !callerId) {
      return new Response(null, { status: 204 });
    }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const { data: ticket, error } = await client
      .from("feedback_tickets")
      .select("id, user_id, category, device_info, created_at")
      .eq("id", ticketId)
      .single();

    // Ticket missing or owned by someone else: the same 204 either way, so
    // a guessed id can't be distinguished from someone else's real ticket.
    if (error || !ticket || ticket.user_id !== callerId) {
      return new Response(null, { status: 204 });
    }

    // Replay/rate guard: atomically claim the notification. This update
    // matches the row only the first time it runs for this ticket - every
    // later call (retried by the client, or invoked again on purpose)
    // matches zero rows and sends nothing.
    const { data: claimed, error: claimError } = await client
      .from("feedback_tickets")
      .update({ notified_at: new Date().toISOString() })
      .eq("id", ticketId)
      .is("notified_at", null)
      .select("id")
      .maybeSingle();

    if (claimError || !claimed) {
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
