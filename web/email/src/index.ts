/**
 * lunarlog-inbound-email: Cloudflare Worker for receiving and processing inbound emails.
 * Issue #1107.
 *
 * Implements:
 * - `email(message, env, ctx)`: Cloudflare Email Workers API handler. Parses inbound MIME,
 *   extracts OTPs & auth links, and persists to KV with a 24h retention TTL.
 * - `fetch(request, env, ctx)`: Authenticated REST API for test automation, CI, and services
 *   to query, retrieve, and delete processed emails.
 */

import { parseInboundEmail } from "./parser.ts";
import { EmailStore } from "./store.ts";
import type { Env, ExecutionContext, ForwardableEmailMessage, ParsedEmailData } from "./types.ts";

export const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-API-Key",
};

export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...CORS_HEADERS,
    },
  });
}

/**
 * Validates request authorization against env.EMAIL_API_KEY.
 * If EMAIL_API_KEY is unset (e.g. in test or unconfigured dev), requests are allowed.
 */
export function isAuthorized(request: Request, env: Env): boolean {
  if (!env.EMAIL_API_KEY) {
    return true;
  }

  const authHeader = request.headers.get("Authorization");
  if (authHeader && authHeader.startsWith("Bearer ")) {
    const token = authHeader.substring(7).trim();
    if (token === env.EMAIL_API_KEY) {
      return true;
    }
  }

  const apiKeyHeader = request.headers.get("X-API-Key");
  if (apiKeyHeader && apiKeyHeader.trim() === env.EMAIL_API_KEY) {
    return true;
  }

  return false;
}

/**
 * Optional background webhook dispatch when INBOUND_WEBHOOK_URL is configured.
 */
export async function dispatchWebhook(
  url: string,
  secret: string | undefined,
  data: ParsedEmailData,
): Promise<void> {
  try {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (secret) {
      headers["Authorization"] = `Bearer ${secret}`;
      headers["X-Webhook-Secret"] = secret;
    }
    await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(data),
    });
  } catch (err) {
    // In background workers, log errors without crashing worker
    console.error("Failed to dispatch inbound email webhook:", err);
  }
}

export default {
  /**
   * Cloudflare Email Routing handler.
   */
  async email(
    message: ForwardableEmailMessage,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<void> {
    try {
      const emailData = await parseInboundEmail(
        message.raw,
        message.from,
        message.to,
      );

      const store = new EmailStore(env.INBOUND_EMAILS);
      await store.saveEmail(emailData);

      if (env.INBOUND_WEBHOOK_URL) {
        ctx.waitUntil(
          dispatchWebhook(env.INBOUND_WEBHOOK_URL, env.INBOUND_WEBHOOK_SECRET, emailData),
        );
      }
    } catch (error) {
      console.error("Error processing inbound email:", error);
      // Rejecting notifies sender's MTA with an SMTP error
      message.setReject(`Failed to process email: ${error instanceof Error ? error.message : "internal error"}`);
    }
  },

  /**
   * HTTP REST API for test automation and email queries.
   */
  async fetch(
    request: Request,
    env: Env,
    _ctx: ExecutionContext,
  ): Promise<Response> {
    const url = new URL(request.url);
    const { pathname, searchParams } = url;

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // Health check endpoint (unauthenticated)
    if (pathname === "/health" || pathname === "/") {
      return jsonResponse({
        status: "ok",
        service: "lunarlog-inbound-email",
        timestamp: new Date().toISOString(),
      });
    }

    // Authenticate API routes
    if (!isAuthorized(request, env)) {
      return jsonResponse({ error: "unauthorized", message: "Invalid or missing API key" }, 401);
    }

    const store = new EmailStore(env.INBOUND_EMAILS);

    // GET /api/emails/latest?recipient=<email>
    if (pathname === "/api/emails/latest" && request.method === "GET") {
      const recipient = searchParams.get("recipient");
      if (!recipient) {
        return jsonResponse({ error: "bad_request", message: "recipient parameter is required" }, 400);
      }

      const email = await store.getLatestEmail(recipient);
      if (!email) {
        return jsonResponse({ error: "not_found", message: `No email found for recipient ${recipient}` }, 404);
      }
      return jsonResponse({ email });
    }

    // GET /api/emails?recipient=<email>&limit=<limit>
    if (pathname === "/api/emails" && request.method === "GET") {
      const recipient = searchParams.get("recipient");
      if (!recipient) {
        return jsonResponse({ error: "bad_request", message: "recipient parameter is required" }, 400);
      }
      const limit = parseInt(searchParams.get("limit") || "10", 10);
      const emails = await store.listEmailsByRecipient(recipient, isNaN(limit) ? 10 : limit);
      return jsonResponse({ emails });
    }

    // GET /api/emails/:id
    const singleMatch = pathname.match(/^\/api\/emails\/([^/]+)$/);
    if (singleMatch && request.method === "GET") {
      const id = decodeURIComponent(singleMatch[1]);
      const email = await store.getEmailById(id);
      if (!email) {
        return jsonResponse({ error: "not_found", message: `Email with ID ${id} not found` }, 404);
      }
      return jsonResponse({ email });
    }

    // DELETE /api/emails/:id
    if (singleMatch && request.method === "DELETE") {
      const id = decodeURIComponent(singleMatch[1]);
      const deleted = await store.deleteEmailById(id);
      if (!deleted) {
        return jsonResponse({ error: "not_found", message: `Email with ID ${id} not found` }, 404);
      }
      return jsonResponse({ success: true, message: `Email ${id} deleted` });
    }

    // POST /api/emails/simulate (simulation endpoint for CI and testing)
    if (pathname === "/api/emails/simulate" && request.method === "POST") {
      try {
        const contentType = request.headers.get("Content-Type") || "";
        let emailData: ParsedEmailData;

        if (contentType.includes("application/json")) {
          const body = await request.json() as Record<string, unknown>;
          const rawMime = typeof body.raw === "string" ? body.raw : undefined;
          if (rawMime) {
            emailData = await parseInboundEmail(rawMime);
          } else {
            const from = String(body.from || "simulator@example.com");
            const to = String(body.to || "test@inbound.lunarlog.app");
            const subject = String(body.subject || "Simulated Email");
            const text = body.text ? String(body.text) : undefined;
            const html = body.html ? String(body.html) : undefined;
            const rawMock = `From: ${from}\r\nTo: ${to}\r\nSubject: ${subject}\r\n\r\n${text || html || ""}`;
            emailData = await parseInboundEmail(rawMock, from, to);
          }
        } else {
          const rawText = await request.text();
          emailData = await parseInboundEmail(rawText);
        }

        await store.saveEmail(emailData);
        return jsonResponse({ success: true, email: emailData }, 201);
      } catch (err) {
        return jsonResponse({
          error: "simulation_failed",
          message: err instanceof Error ? err.message : String(err),
        }, 400);
      }
    }

    return jsonResponse({ error: "not_found", message: `Route ${pathname} not found` }, 404);
  },
};
