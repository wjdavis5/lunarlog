// _shared/email.ts (Issue #6, U9)
//
// Single fetch wrapper over the Resend send endpoint. Returns a
// discriminated result rather than throwing, so a caller's best-effort
// notify path never needs a try/catch around this call.

import type { EmailEnvelope } from "./format.ts";

export type SendEmailResult =
  | { ok: true }
  | { ok: false; reason: string };

const RESEND_ENDPOINT = "https://api.resend.com/emails";

export async function sendEmail(envelope: EmailEnvelope): Promise<SendEmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const from = Deno.env.get("FEEDBACK_FROM_ADDRESS");
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
    });
    if (!response.ok) {
      return { ok: false, reason: `resend_status_${response.status}` };
    }
    return { ok: true };
  } catch (_error) {
    return { ok: false, reason: "network_error" };
  }
}
