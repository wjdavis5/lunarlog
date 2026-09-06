// _shared/email.ts (Issue #6, U9)
//
// Single fetch wrapper over the Resend send endpoint. Returns a
// discriminated result rather than throwing, so a caller's best-effort
// notify path never needs a try/catch around this call.
//
// PR #105 review round 5: `feedback-notify/index.ts` now claims
// `notified_at` *before* calling this function (see that file's header),
// which is what closes the round-4 double-send race - but it also means an
// unbounded `fetch` here could park the whole invocation indefinitely with
// the claim already committed. A platform-level isolate kill at that point
// (Supabase Edge Functions enforce their own wall-clock limit regardless of
// anything this code does) would never reach `index.ts`'s `catch` block, so
// `releaseClaim()` would never run and the ticket's alert would be lost
// silently and permanently - worse than the bounded duplicate-send window
// this fix replaced. `AbortSignal.timeout` bounds the fetch itself well
// under any platform timeout, so a hung Resend call fails *this* function
// first, in time for `index.ts` to release the claim in its normal
// send-failure path (see AGENTS.md and this repo's account for the residual
// risk that remains even so - a kill with no timeout ever firing, e.g. a
// host crash - which no in-process timeout can close).
//
// PR #105 review round 7: `apiKey`/`from` used to be read here directly
// with `Deno.env.get`, which is exactly the pattern `index.ts`'s own header
// comment calls out as the wrong one ("a plain object ... so tests can
// supply fixed values with no `--allow-env` permission") - and it left the
// timeout/failure-classification logic below with zero test coverage,
// since importing this module under `deno test` would otherwise need
// `--allow-env` just to reach a fake-fetch test at all. They are now params
// supplied by the caller (`index.ts`'s `buildDeps`, which already reads
// every other env var itself and passes plain values down), so
// `email.test.ts` can drive `sendEmail` with fakes and no Deno permissions
// beyond the suite's existing `deno test` default (no `--allow-*` flags).

import type { EmailEnvelope } from "./format.ts";

export type SendEmailResult =
  | { ok: true }
  | { ok: false; reason: string };

const RESEND_ENDPOINT = "https://api.resend.com/emails";

/** Comfortably inside any platform-level function timeout, so a hung Resend
 * call fails here - in time for the caller to release its `notified_at`
 * claim - rather than the isolate being killed out from under it first. */
const RESEND_TIMEOUT_MS = 12_000;

export async function sendEmail(
  envelope: EmailEnvelope,
  apiKey: string | undefined,
  from: string | undefined,
): Promise<SendEmailResult> {
  if (!apiKey || !from) {
    return { ok: false, reason: "missing_email_config" };
  }

  try {
    const response = await fetch(RESEND_ENDPOINT, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: envelope.to,
        subject: envelope.subject,
        html: envelope.html,
        text: envelope.text,
      }),
      signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
    });
    if (!response.ok) {
      return { ok: false, reason: `resend_status_${response.status}` };
    }
    return { ok: true };
  } catch (error) {
    // `AbortSignal.timeout` rejects the fetch with a `DOMException` named
    // "TimeoutError" - distinguished here so a hung Resend call is
    // diagnosable in logs, but it is caught and folded into the same
    // `{ ok: false }` shape as any other send failure, so `index.ts`'s
    // existing release-claim-on-failure path handles it with no special
    // case of its own.
    const reason = error instanceof DOMException && error.name === "TimeoutError"
      ? "timeout"
      : "network_error";
    return { ok: false, reason };
  }
}
