// _shared/format.ts (Issue #6, U9)
//
// Pure email-content builders shared by feedback-notify and feedback-reply.
// Neither function ever includes the ticket's message body in the admin
// alert (R21) — buildAdminAlert deliberately has no parameter for it.

export interface FeedbackTicketSummary {
  id: string;
  category: string;
  appVersion: string;
  createdAt: string;
  /** The address a reply email goes to; unused by buildAdminAlert. */
  replyEmail: string;
}

export interface FeedbackReplySummary {
  message: string;
}

export interface EmailEnvelope {
  to: string;
  subject: string;
  html: string;
  text: string;
}

const CATEGORY_LABELS: Record<string, string> = {
  bug: "Bug",
  feature_request: "Feature request",
  support: "Support",
  other: "Other",
};

function categoryLabel(category: string): string {
  return CATEGORY_LABELS[category] ?? category;
}

/** Minimal HTML escaping; these emails are plain and short. */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * The new-ticket alert to the admin address (R21). Carries only ticket id,
 * category, app version, and created-at — never the message body, the
 * reply email, or any attachment path.
 */
export function buildAdminAlert(
  ticket: FeedbackTicketSummary,
  adminEmail: string,
): EmailEnvelope {
  const label = categoryLabel(ticket.category);
  const subject = `New feedback ticket: ${label}`;
  const text = [
    `A new ${label} ticket was submitted.`,
    "",
    `Ticket: ${ticket.id}`,
    `App version: ${ticket.appVersion}`,
    `Created at: ${ticket.createdAt}`,
  ].join("\n");
  const html = `<p>A new <strong>${escapeHtml(label)}</strong> ticket was submitted.</p>` +
    "<ul>" +
    `<li>Ticket: ${escapeHtml(ticket.id)}</li>` +
    `<li>App version: ${escapeHtml(ticket.appVersion)}</li>` +
    `<li>Created at: ${escapeHtml(ticket.createdAt)}</li>` +
    "</ul>";
  return { to: adminEmail, subject, html, text };
}

/**
 * The admin-reply email to the ticket's own `reply_email` (R20). Includes
 * the reply text and the ticket's category.
 */
export function buildReplyEmail(
  ticket: FeedbackTicketSummary,
  reply: FeedbackReplySummary,
): EmailEnvelope {
  const label = categoryLabel(ticket.category);
  const subject = `Re: your ${label} feedback`;
  const escapedMessage = escapeHtml(reply.message).replace(/\n/g, "<br>");
  const text = [`Our team replied to your ${label} feedback:`, "", reply.message].join("\n");
  const html = `<p>Our team replied to your <strong>${escapeHtml(label)}</strong> feedback:</p>` +
    `<blockquote>${escapedMessage}</blockquote>`;
  return { to: ticket.replyEmail, subject, html, text };
}
