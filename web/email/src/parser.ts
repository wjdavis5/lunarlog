/**
 * Inbound email MIME parser and auth metadata extractor.
 */

import PostalMime from "npm:postal-mime@^2.2.0";
import type { ParsedEmailData } from "./types.ts";

/**
 * Extracts authentication OTP code from text/HTML content.
 * Prioritizes 8-digit OTPs (used by Lunarlog Auth per #2 and #970),
 * falling back to 6-digit OTPs if present.
 */
export function extractOtpCode(content: string): string | undefined {
  if (!content) return undefined;

  // Look for 8-digit OTPs first (word-boundary matched)
  const eightDigitMatch = content.match(/\b\d{8}\b/);
  if (eightDigitMatch) {
    return eightDigitMatch[0];
  }

  // Fallback to 6-digit OTPs
  const sixDigitMatch = content.match(/\b\d{6}\b/);
  if (sixDigitMatch) {
    return sixDigitMatch[0];
  }

  return undefined;
}

/**
 * Extracts links (HTTP/HTTPS and custom schemes like lunarlog://) from text/HTML.
 * Filters out common XML/HTML namespace URLs and deduplicates results.
 */
export function extractAuthLinks(content: string): string[] {
  if (!content) return [];

  const urlRegex = /(?:https?:\/\/|lunarlog:\/\/)[^\s"'<>)]+/gi;
  const matches = content.match(urlRegex) || [];

  const deduped = new Set<string>();
  for (const rawUrl of matches) {
    const cleaned = rawUrl.replace(/[.,;:!?]+$/, "");
    // Ignore XML/DTD schemas
    try {
      if (cleaned.startsWith("http://") || cleaned.startsWith("https://")) {
        const parsedUrl = new URL(cleaned);
        const host = parsedUrl.hostname.toLowerCase();
        if (
          host === "w3.org" ||
          host.endsWith(".w3.org") ||
          host === "schema.org" ||
          host.endsWith(".schema.org")
        ) {
          continue;
        }
      }
    } catch {
      // not a standard URL, continue
    }
    deduped.add(cleaned);
  }

  return Array.from(deduped);
}

/**
 * Normalizes email address (lowercase, trim).
 */
export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Parses raw email content (Stream, Uint8Array, or string) into ParsedEmailData.
 */
export async function parseInboundEmail(
  rawInput: ReadableStream<Uint8Array> | Uint8Array | string,
  fallbackFrom?: string,
  fallbackTo?: string,
): Promise<ParsedEmailData> {
  const parsed = await PostalMime.parse(rawInput);

  const from = parsed.from?.address || fallbackFrom || "unknown";
  const to = parsed.to?.[0]?.address || fallbackTo || "unknown";
  const subject = parsed.subject || "(no subject)";
  const text = parsed.text || undefined;
  const html = parsed.html || undefined;

  const combinedContent = `${subject}\n${text || ""}\n${html || ""}`;
  const otpCode = extractOtpCode(combinedContent);
  const authLinks = extractAuthLinks(combinedContent);

  // Generate or sanitize message ID
  const rawId = parsed.messageId ? parsed.messageId.replace(/[<>]/g, "").trim() : "";
  const id = rawId.length > 0 ? rawId : crypto.randomUUID();

  // Convert headers if present
  let headersRecord: Record<string, string> | undefined;
  if (parsed.headers && Array.isArray(parsed.headers)) {
    headersRecord = {};
    for (const h of parsed.headers) {
      if (h.key && h.value) {
        headersRecord[h.key.toLowerCase()] = String(h.value);
      }
    }
  }

  return {
    id,
    from: normalizeEmail(from),
    to: normalizeEmail(to),
    subject,
    receivedAt: new Date().toISOString(),
    text,
    html,
    otpCode,
    authLinks,
    headers: headersRecord,
  };
}
