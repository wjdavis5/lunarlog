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
//      admin inbox / burn the Resend quota) sends at most one email. That
//      claim runs only AFTER `sendEmail` reports success - claiming first
//      and sending second would let a failed send get claimed as sent
//      anyway, permanently and silently suppressing that ticket's alert
//      (notified_at has no authenticated grant, so nothing could ever
//      un-claim it and retry).
//
// A missing/invalid caller identity, an unowned or already-notified ticket,
// and a not-found ticket all degrade to the same 204 - this endpoint never
// echoes ticket content or existence in its response (R21).
//
// Thin by design (KTD6): all real logic lives in `_shared/format.ts`
// (tested) and `_shared/email.ts`. `handleFeedbackNotify` below takes every
// real I/O call as an injected [FeedbackNotifyDeps] so the ownership check
// and replay guard can be covered by `deno test` with fakes - no live
// Supabase project or Resend key required (see index.test.ts).

import { createClient } from "@supabase/supabase-js";
import { buildAdminAlert, type FeedbackTicketSummary } from "../_shared/format.ts";
import { sendEmail as sendEmailReal, type SendEmailResult } from "../_shared/email.ts";

function appVersionFrom(deviceInfo: unknown): string {
  if (deviceInfo && typeof deviceInfo === "object") {
    const value = (deviceInfo as Record<string, unknown>)["app_version"];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return "unknown";
}

export interface FeedbackTicketRow {
  id: string;
  user_id: string;
  category: string;
  device_info: unknown;
  created_at: string;
  notified_at: string | null;
}

/** Every real I/O call `handleFeedbackNotify` needs, injected so tests can
 * supply fakes instead of a live Supabase project / Resend key. */
export interface FeedbackNotifyDeps {
  /** True only when every required env var (Supabase URL/keys, admin email)
   * is present. Missing config degrades to "no alert sent" (204) rather
   * than a visible failure - this call is best-effort from the client's
   * perspective. */
  configured: boolean;
  /** Resolves the caller's auth id from their own forwarded JWT (read with
   * the anon key, never trusted as a raw claim). Null on any invalid/failed
   * lookup. */
  resolveCallerId(authHeader: string): Promise<string | null>;
  /** Reads the ticket via the service-role client. Null if not found. */
  getTicket(ticketId: string): Promise<FeedbackTicketRow | null>;
  /** Atomically claims notified_at (`UPDATE ... WHERE notified_at IS NULL`).
   * Resolves true only if this call was the one that set it. */
  claimNotification(ticketId: string): Promise<boolean>;
  /** Sends the admin alert; resolves rather than throws on failure. */
  sendEmail(summary: FeedbackTicketSummary): Promise<SendEmailResult>;
}

/** The full request-handling logic (Issue #6, U9). See the header comment
 * for the ownership/replay-guard contract; every branch below preserves the
 * original check ordering (method -> body -> config -> caller identity ->
 * ownership -> replay -> send -> claim) so a config-check short-circuit
 * can never mask a malformed-request response or vice versa. */
export async function handleFeedbackNotify(req: Request, deps: FeedbackNotifyDeps): Promise<Response> {
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

  if (!deps.configured) {
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
    const callerId = await deps.resolveCallerId(authHeader);
    if (!callerId) {
      return new Response(null, { status: 204 });
    }

    const ticket = await deps.getTicket(ticketId);

    // Ticket missing or owned by someone else: the same 204 either way, so
    // a guessed id can't be distinguished from someone else's real ticket.
    if (!ticket || ticket.user_id !== callerId) {
      return new Response(null, { status: 204 });
    }

    // Cheap pre-send replay check: if a prior call already sent the alert,
    // don't send another. This alone isn't the atomic claim (that happens
    // below, after the send) - it just short-circuits the common sequential
    // retry case before spending a Resend call on it.
    if (ticket.notified_at) {
      return new Response(null, { status: 204 });
    }

    const summary: FeedbackTicketSummary = {
      id: ticket.id,
      category: ticket.category,
      appVersion: appVersionFrom(ticket.device_info),
      createdAt: ticket.created_at,
      replyEmail: "",
    };
    const sendResult = await deps.sendEmail(summary);

    if (!sendResult.ok) {
      // Do NOT claim notified_at: the alert was never actually sent, so
      // claiming here would permanently and silently suppress it (no log,
      // no retry path, ever - notified_at has no authenticated grant, so
      // nothing else can ever clear it). Logging + a non-2xx response at
      // least surfaces the failure in this function's own logs, even
      // though the client itself ignores this invocation's result (R21's
      // best-effort contract).
      console.error(
        `feedback-notify: sendEmail failed for ticket ${ticketId}: ${sendResult.reason}`,
      );
      return new Response(null, { status: 502 });
    }

    // Replay/rate guard: atomically claim the notification now that the
    // send actually succeeded. This update matches the row only the first
    // time it runs for this ticket - every later call (retried by the
    // client, or invoked again on purpose) matches zero rows and is a
    // no-op. Claiming only after a successful send means a failed send is
    // always retryable rather than permanently and silently swallowed.
    const claimed = await deps.claimNotification(ticketId);
    if (!claimed) {
      console.error(`feedback-notify: failed to claim notified_at for ticket ${ticketId}`);
    }
  } catch (_error) {
    // Never surface provider detail; this endpoint's contract is 204
    // either way (R21's best-effort promise extends to this handler).
  }

  return new Response(null, { status: 204 });
}

// Guarded so `index.test.ts` can import `handleFeedbackNotify` without this
// module trying to bind a real network listener (which `deno test` runs
// with no `--allow-net`, and would fail on) - `import.meta.main` is true
// only when Deno runs this file directly, which is how the Supabase Edge
// Runtime invokes it in production.
if (import.meta.main) {
  Deno.serve(async (req) => {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const adminEmail = Deno.env.get("FEEDBACK_ADMIN_EMAIL");
    const configured = !!(supabaseUrl && anonKey && serviceRoleKey && adminEmail);

    const client = configured ? createClient(supabaseUrl!, serviceRoleKey!) : null;

    return handleFeedbackNotify(req, {
      configured,
      resolveCallerId: async (authHeader) => {
        const callerClient = createClient(supabaseUrl!, anonKey!, {
          global: { headers: { Authorization: authHeader } },
        });
        const { data, error } = await callerClient.auth.getUser();
        const callerId = data?.user?.id;
        return error || !callerId ? null : callerId;
      },
      getTicket: async (ticketId) => {
        const { data, error } = await client!
          .from("feedback_tickets")
          .select("id, user_id, category, device_info, created_at, notified_at")
          .eq("id", ticketId)
          .single();
        return error || !data ? null : (data as FeedbackTicketRow);
      },
      claimNotification: async (ticketId) => {
        const { data, error } = await client!
          .from("feedback_tickets")
          .update({ notified_at: new Date().toISOString() })
          .eq("id", ticketId)
          .is("notified_at", null)
          .select("id")
          .maybeSingle();
        return !error && !!data;
      },
      sendEmail: (summary) => sendEmailReal(buildAdminAlert(summary, adminEmail!)),
    });
  });
}
