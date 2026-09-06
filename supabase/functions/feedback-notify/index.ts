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
//      the notification BEFORE `sendEmail` is even attempted, so exactly one
//      concurrent/overlapping invocation for a given ticket ever wins the
//      claim - every other one (racing in, or a plain sequential retry)
//      matches zero rows, gets `claimed = false`, and returns 204 without
//      ever calling `sendEmail`. `await fetch` inside `sendEmail` is a
//      guaranteed yield point, so claiming *after* the send (as an earlier
//      version of this function did) is not atomic: two overlapping calls
//      can both observe "not yet notified" before either one's `fetch`
//      resolves, and both send. Claiming first and releasing the claim if
//      the send then fails (see below) gets both properties at once: no
//      duplicate sends under concurrency, and no failed send silently and
//      permanently swallowed.
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
//
// PR #105 review round 6: the *production* `FeedbackNotifyDeps` - including
// the atomic-claim query itself - used to be built entirely inside the
// `if (import.meta.main)` block below, which `deno test` never evaluates
// (it is Deno's own guard against binding a real network listener under
// `deno test`, which runs with no `--allow-net`). That meant deleting the
// `.is("notified_at", null)` guard clause from the real claim query left
// every test green: nothing in the suite ever ran that code path at all,
// only a hand-rolled `claimNotification` fake standing in for it. `buildDeps`
// below is that same construction pulled out as a plain function taking its
// environment and a Supabase client factory as parameters, so it runs
// (and can be asserted against) under `deno test` like anything else -
// see index.test.ts's "production claim predicate" test, which exercises
// this exact closure against a fake client that really enforces WHERE-clause
// filtering, and fails if that guard clause is ever removed again.

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
  /** Atomically claims notified_at (`UPDATE ... WHERE notified_at IS NULL`),
   * called BEFORE `sendEmail` is attempted. Resolves true only if this call
   * was the one that set it - every other concurrent/overlapping call for
   * the same ticket resolves false and must not send. */
  claimNotification(ticketId: string): Promise<boolean>;
  /** Releases a claim this same invocation just won, after its `sendEmail`
   * attempt failed (clears `notified_at` back to null) so a legitimate
   * retry - by the client, or a later manual invocation - can still claim
   * and send. Never called except by the claim's own winner. */
  releaseClaim(ticketId: string): Promise<void>;
  /** Sends the admin alert; resolves rather than throws on failure. */
  sendEmail(summary: FeedbackTicketSummary): Promise<SendEmailResult>;
}

/** The full request-handling logic (Issue #6, U9). See the header comment
 * for the ownership/replay-guard contract; every branch below preserves the
 * original check ordering (method -> body -> config -> caller identity ->
 * ownership -> claim -> send -> release-on-failure) so a config-check
 * short-circuit can never mask a malformed-request response or vice versa. */
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

    // Replay/rate guard: atomically claim the notification BEFORE
    // attempting to send anything. This update matches the row only the
    // first time it runs for this ticket - every other concurrent or
    // sequential call (racing in, retried by the client, or invoked again
    // on purpose) matches zero rows, gets `claimed = false`, and must not
    // send. Doing this before `sendEmail` (rather than after) is what makes
    // it atomic: `await fetch` inside `sendEmail` is a guaranteed yield
    // point, so a claim taken only after a successful send can't stop two
    // overlapping invocations from both passing a pre-send check and both
    // sending.
    const claimed = await deps.claimNotification(ticketId);
    if (!claimed) {
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
      // The alert was never actually sent, so release the claim this
      // invocation just won: leaving notified_at set would permanently and
      // silently suppress the ticket's alert (notified_at has no
      // authenticated grant, so nothing else could ever clear it and
      // retry). Logging + a non-2xx response also surfaces the failure in
      // this function's own logs, even though the client itself ignores
      // this invocation's result (R21's best-effort contract).
      console.error(
        `feedback-notify: sendEmail failed for ticket ${ticketId}: ${sendResult.reason}`,
      );
      await deps.releaseClaim(ticketId);
      return new Response(null, { status: 502 });
    }
  } catch (_error) {
    // Never surface provider detail; this endpoint's contract is 204
    // either way (R21's best-effort promise extends to this handler).
  }

  return new Response(null, { status: 204 });
}

/** The environment `buildDeps` needs. A plain object (rather than reading
 * `Deno.env` itself) so tests can supply fixed values with no `--allow-env`
 * permission and no dependency on the process's real environment. */
export interface FeedbackNotifyEnv {
  supabaseUrl: string | undefined;
  anonKey: string | undefined;
  serviceRoleKey: string | undefined;
  adminEmail: string | undefined;
}

/** Creates a Supabase client given a URL, key, and optional per-call
 * options (e.g. forwarding the caller's own `Authorization` header for
 * `resolveCallerId`). Matches `createClient`'s call shape narrowly enough
 * that a test's fake client - one that actually enforces WHERE-clause
 * filtering rather than standing in for `claimNotification` wholesale - can
 * satisfy it too. Loosely typed (`any` return) deliberately: this seam
 * exists precisely so `buildDeps` never needs the full `SupabaseClient`
 * generic surface, only the handful of calls it actually makes below. */
// deno-lint-ignore no-explicit-any
export type SupabaseClientFactory = (url: string, key: string, options?: Record<string, unknown>) => any;

/** Builds the production `FeedbackNotifyDeps` - including the atomic claim
 * query itself - as a plain function of its environment and a client
 * factory, independent of `import.meta.main`/`Deno.serve`. This is what
 * lets `deno test` actually evaluate the real claim predicate (see the
 * header comment above and index.test.ts's "production claim predicate"
 * test) instead of only ever running a test-only stand-in for it. */
export function buildDeps(env: FeedbackNotifyEnv, clientFactory: SupabaseClientFactory): FeedbackNotifyDeps {
  const { supabaseUrl, anonKey, serviceRoleKey, adminEmail } = env;
  const configured = !!(supabaseUrl && anonKey && serviceRoleKey && adminEmail);

  const client = configured ? clientFactory(supabaseUrl!, serviceRoleKey!) : null;

  return {
    configured,
    resolveCallerId: async (authHeader) => {
      const callerClient = clientFactory(supabaseUrl!, anonKey!, {
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
    releaseClaim: async (ticketId) => {
      const { error } = await client!
        .from("feedback_tickets")
        .update({ notified_at: null })
        .eq("id", ticketId);
      if (error) {
        console.error(`feedback-notify: failed to release notified_at claim for ticket ${ticketId}: ${error.message}`);
      }
    },
    sendEmail: (summary) => sendEmailReal(buildAdminAlert(summary, adminEmail!)),
  };
}

// Guarded so `index.test.ts` can import `handleFeedbackNotify`/`buildDeps`
// without this module trying to bind a real network listener (which
// `deno test` runs with no `--allow-net`, and would fail on) -
// `import.meta.main` is true only when Deno runs this file directly, which
// is how the Supabase Edge Runtime invokes it in production. `buildDeps`
// itself (above) carries none of that gating, which is the whole point of
// round 6's fix - see this file's header comment.
if (import.meta.main) {
  Deno.serve(async (req) => {
    const deps = buildDeps(
      {
        supabaseUrl: Deno.env.get("SUPABASE_URL"),
        anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
        serviceRoleKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
        adminEmail: Deno.env.get("FEEDBACK_ADMIN_EMAIL"),
      },
      createClient,
    );
    return handleFeedbackNotify(req, deps);
  });
}
