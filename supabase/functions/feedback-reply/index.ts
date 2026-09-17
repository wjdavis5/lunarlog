// feedback-reply (Issue #6, U9; Issue #567 Deno-half refactor)
//
// Database Webhook target (Database → Webhooks on `public.feedback_replies`
// INSERT), configured in the dashboard rather than a migration (KTD7) — see
// docs/ops/supabase-go-live.md's Feedback section. Validates the shared
// webhook secret header (the webhook config sets it as a custom header;
// this function never accepts a request without a matching value), ignores
// any payload whose `author_type` isn't `admin`, loads the parent ticket
// for `reply_email`, and sends the reply email.
//
// Issue #567 fix (2026-09-13): this function previously had no `deno test`
// coverage at all, was absent from `deno.json`'s `test.include`, and was
// never `deno check`ed in CI - a regression here would have shipped green
// with zero automated signal. Refactored to the same
// `handleFeedbackReply(req, deps)` / `buildDeps` dependency-injection shape
// `feedback-notify/index.ts` and `push-dispatch/index.ts` already use, so
// the ownership/config/send-result logic below can be exercised by
// `deno test` with fakes (see index.test.ts) - no live Supabase project, no
// Resend key, no network. Also fixed: `sendEmail`'s result used to be
// discarded and this function always returned 204 regardless - a rotated or
// exhausted `RESEND_API_KEY` silently stopped every admin reply email with
// no signal anywhere. A failed send is now logged and answered with a
// non-2xx status (502, mirroring feedback-notify's own send-failure
// status); this is still a Database Webhook target with nobody reading the
// response body, so the *reply itself* stays visible in the ticket's
// Support history either way (R20's degrade-gracefully contract for the
// email side only).

import { createClient } from "@supabase/supabase-js";
import { buildReplyEmail, type FeedbackTicketSummary } from "../_shared/format.ts";
import { sendEmail as sendEmailReal, type SendEmailResult } from "../_shared/email.ts";

const WEBHOOK_SECRET_HEADER = "x-feedback-webhook-secret";

function appVersionFrom(deviceInfo: unknown): string {
  if (deviceInfo && typeof deviceInfo === "object") {
    const value = (deviceInfo as Record<string, unknown>)["app_version"];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return "unknown";
}

export interface FeedbackReplyTicketRow {
  id: string;
  category: string;
  reply_email: string;
  device_info: unknown;
  created_at: string;
}

/** Every real I/O call `handleFeedbackReply` needs, injected so tests can
 * supply fakes instead of a live Supabase project / Resend key. */
export interface FeedbackReplyDeps {
  /** True only when every required env var (Supabase URL/service-role key)
   * is present. Missing config degrades to "no reply email sent" (204)
   * rather than a visible failure - the webhook caller (Database Webhooks)
   * never inspects this response body either way. */
  configured: boolean;
  /** Reads the reply's parent ticket via the service-role client. Null if
   * not found. */
  getTicket(ticketId: string): Promise<FeedbackReplyTicketRow | null>;
  /** Sends the reply email; resolves rather than throws on failure. */
  sendEmail(summary: FeedbackTicketSummary, message: string): Promise<SendEmailResult>;
}

/** The full request-handling logic (Issue #6, U9; Issue #567 refactor). The
 * shared-webhook-secret check stays in the `import.meta.main` block below,
 * not here - it is a property of *this specific invocation's transport*
 * (the Database Webhook config), not of the payload this function
 * interprets, matching `push-dispatch/index.ts`'s identical split. */
export async function handleFeedbackReply(req: Request, deps: FeedbackReplyDeps): Promise<Response> {
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

  if (!deps.configured) {
    return new Response(null, { status: 204 });
  }

  const ticket = await deps.getTicket(ticketId);
  if (!ticket) {
    return new Response(null, { status: 204 });
  }

  const summary: FeedbackTicketSummary = {
    id: ticket.id,
    category: ticket.category,
    appVersion: appVersionFrom(ticket.device_info),
    createdAt: ticket.created_at,
    replyEmail: ticket.reply_email,
  };

  const sendResult = await deps.sendEmail(summary, message);
  if (!sendResult.ok) {
    // Issue #567 fix: this used to be discarded, so a rotated/exhausted
    // RESEND_API_KEY (or any other send failure) silently stopped every
    // admin reply email with no signal anywhere. The reply itself is
    // already visible in the ticket's Support history regardless (R20's
    // degrade-gracefully contract still holds for the *webhook caller*,
    // which never inspects this response body) - but this function's own
    // logs and status code must show the failure.
    console.error(`feedback-reply: sendEmail failed for ticket ${ticketId}: ${sendResult.reason}`);
    return new Response(null, { status: 502 });
  }

  return new Response(null, { status: 204 });
}

/** The environment `buildDeps` needs. A plain object (rather than reading
 * `Deno.env` itself) so tests can supply fixed values with no `--allow-env`
 * permission, mirroring `feedback-notify/index.ts`'s `FeedbackNotifyEnv`. */
export interface FeedbackReplyEnv {
  supabaseUrl: string | undefined;
  serviceRoleKey: string | undefined;
  resendApiKey?: string;
  fromAddress?: string;
}

// deno-lint-ignore no-explicit-any
export type SupabaseClientFactory = (url: string, key: string) => any;

/** Builds the production `FeedbackReplyDeps` as a plain function of its
 * environment and a client factory, independent of `import.meta.main`/
 * `Deno.serve` - mirroring `feedback-notify/index.ts`'s `buildDeps`, so
 * `deno test` can exercise this production wiring directly. */
export function buildDeps(env: FeedbackReplyEnv, clientFactory: SupabaseClientFactory): FeedbackReplyDeps {
  const { supabaseUrl, serviceRoleKey } = env;
  const configured = !!(supabaseUrl && serviceRoleKey);
  const client = configured ? clientFactory(supabaseUrl!, serviceRoleKey!) : null;

  return {
    configured,
    getTicket: async (ticketId) => {
      const { data, error } = await client!
        .from("feedback_tickets")
        .select("id, category, reply_email, device_info, created_at")
        .eq("id", ticketId)
        .single();
      return error || !data ? null : (data as FeedbackReplyTicketRow);
    },
    sendEmail: (summary, message) =>
      sendEmailReal(buildReplyEmail(summary, { message }), env.resendApiKey, env.fromAddress),
  };
}

// Guarded so `index.test.ts` can import `handleFeedbackReply`/`buildDeps`
// without this module trying to bind a real network listener (which
// `deno test` runs with no `--allow-net`) - `import.meta.main` is true only
// when Deno runs this file directly, which is how the Supabase Edge Runtime
// invokes it in production, mirroring `feedback-notify/index.ts`'s same
// guard.
if (import.meta.main) {
  Deno.serve(async (req) => {
    const expectedSecret = Deno.env.get("FEEDBACK_WEBHOOK_SECRET");
    const providedSecret = req.headers.get(WEBHOOK_SECRET_HEADER);
    if (!expectedSecret || providedSecret !== expectedSecret) {
      return new Response(null, { status: 401 });
    }

    const deps = buildDeps(
      {
        supabaseUrl: Deno.env.get("SUPABASE_URL"),
        serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        resendApiKey: Deno.env.get("RESEND_API_KEY"),
        fromAddress: Deno.env.get("FEEDBACK_FROM_ADDRESS"),
      },
      createClient,
    );
    return handleFeedbackReply(req, deps);
  });
}
