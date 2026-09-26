/**
 * Cloudflare Workers KV storage engine for parsed inbound emails.
 */

import type { KVListResult, KVNamespace, ParsedEmailData } from "./types.ts";

/**
 * Default retention TTL for inbound test emails: 24 hours (86,400 seconds).
 */
export const DEFAULT_TTL_SECONDS = 86400;

/**
 * Formats inverted timestamp for lexicographical descending sort in Cloudflare KV.
 */
export function formatInvertedTimestamp(dateMs: number = Date.now()): string {
  const inverted = BigInt(Number.MAX_SAFE_INTEGER) - BigInt(dateMs);
  return inverted.toString().padStart(16, "0");
}

/**
 * In-memory KVNamespace implementation for testing and development.
 */
export class MemoryKV implements KVNamespace {
  private map = new Map<string, { value: string; expiration?: number }>();

  get(key: string, options?: { type?: "text" }): Promise<string | null>;
  get<T = unknown>(key: string, options: { type: "json" }): Promise<T | null>;
  get(key: string, options?: { type?: string }): Promise<unknown>;
  async get(key: string, options?: { type?: string }): Promise<unknown> {
    const entry = this.map.get(key);
    if (!entry) return null;
    if (entry.expiration && entry.expiration < Math.floor(Date.now() / 1000)) {
      this.map.delete(key);
      return null;
    }
    if (options?.type === "json") {
      try {
        return JSON.parse(entry.value);
      } catch {
        return null;
      }
    }
    return entry.value;
  }

  async put(
    key: string,
    value: string | ArrayBuffer | ArrayBufferView | ReadableStream,
    options?: { expiration?: number; expirationTtl?: number },
  ): Promise<void> {
    const str = typeof value === "string" ? value : String(value);
    let expiration = options?.expiration;
    if (options?.expirationTtl) {
      expiration = Math.floor(Date.now() / 1000) + options.expirationTtl;
    }
    this.map.set(key, { value: str, expiration });
  }

  async delete(key: string): Promise<void> {
    this.map.delete(key);
  }

  async list(options?: { prefix?: string; limit?: number; cursor?: string }): Promise<KVListResult> {
    const prefix = options?.prefix || "";
    const limit = options?.limit || 1000;
    const nowSec = Math.floor(Date.now() / 1000);

    const matchingKeys: string[] = [];
    for (const [key, entry] of this.map.entries()) {
      if (entry.expiration && entry.expiration < nowSec) {
        this.map.delete(key);
        continue;
      }
      if (key.startsWith(prefix)) {
        matchingKeys.push(key);
      }
    }

    matchingKeys.sort();
    const sliced = matchingKeys.slice(0, limit);

    return {
      keys: sliced.map((k) => ({ name: k })),
      list_complete: matchingKeys.length <= limit,
    };
  }
}

/**
 * Storage service managing email persistence and queries.
 */
export class EmailStore {
  private kv: KVNamespace;
  private ttlSeconds: number;

  constructor(kv?: KVNamespace, ttlSeconds: number = DEFAULT_TTL_SECONDS) {
    this.kv = kv || new MemoryKV();
    this.ttlSeconds = ttlSeconds;
  }

  /**
   * Persists an email into KV with multiple index keys:
   * 1. msg:<id> -> full email object
   * 2. recipient:<to>:<invertedTime>:<id> -> full email object
   * 3. latest:<to> -> full email object
   */
  async saveEmail(email: ParsedEmailData): Promise<void> {
    const serialized = JSON.stringify(email);
    const dateMs = Date.parse(email.receivedAt) || Date.now();
    const invertedTime = formatInvertedTimestamp(dateMs);

    const msgKey = `msg:${email.id}`;
    const recipientKey = `recipient:${email.to}:${invertedTime}:${email.id}`;
    const latestKey = `latest:${email.to}`;

    await Promise.all([
      this.kv.put(msgKey, serialized, { expirationTtl: this.ttlSeconds }),
      this.kv.put(recipientKey, serialized, { expirationTtl: this.ttlSeconds }),
      this.kv.put(latestKey, serialized, { expirationTtl: this.ttlSeconds }),
    ]);
  }

  /**
   * Retrieves an email by its message ID.
   */
  async getEmailById(id: string): Promise<ParsedEmailData | null> {
    const data = await this.kv.get(`msg:${id}`, { type: "json" });
    return (data as ParsedEmailData) || null;
  }

  /**
   * Retrieves the most recently received email for a recipient.
   */
  async getLatestEmail(recipient: string): Promise<ParsedEmailData | null> {
    const normalized = recipient.trim().toLowerCase();
    const latest = await this.kv.get(`latest:${normalized}`, { type: "json" });
    if (latest) {
      return latest as ParsedEmailData;
    }

    // Fallback: query recipient prefix
    const listResult = await this.kv.list({
      prefix: `recipient:${normalized}:`,
      limit: 1,
    });

    if (listResult.keys.length === 0) {
      return null;
    }

    const firstKey = listResult.keys[0].name;
    const data = await this.kv.get(firstKey, { type: "json" });
    return (data as ParsedEmailData) || null;
  }

  /**
   * Lists emails received for a specific recipient up to limit.
   */
  async listEmailsByRecipient(recipient: string, limit: number = 10): Promise<ParsedEmailData[]> {
    const normalized = recipient.trim().toLowerCase();
    const listResult = await this.kv.list({
      prefix: `recipient:${normalized}:`,
      limit: Math.min(Math.max(limit, 1), 50),
    });

    const emails: ParsedEmailData[] = [];
    for (const key of listResult.keys) {
      const email = await this.kv.get(key.name, { type: "json" });
      if (email) {
        emails.push(email as ParsedEmailData);
      }
    }

    return emails;
  }

  /**
   * Deletes an email by message ID and cleans up its latest entry if matching.
   */
  async deleteEmailById(id: string): Promise<boolean> {
    const existing = await this.getEmailById(id);
    if (!existing) {
      return false;
    }

    const dateMs = Date.parse(existing.receivedAt) || Date.now();
    const invertedTime = formatInvertedTimestamp(dateMs);
    const recipientKey = `recipient:${existing.to}:${invertedTime}:${existing.id}`;
    const latestKey = `latest:${existing.to}`;

    await Promise.all([
      this.kv.delete(`msg:${id}`),
      this.kv.delete(recipientKey),
    ]);

    // If this was the latest, check if latest key matches this ID
    const latestObj = await this.kv.get(latestKey, { type: "json" }) as ParsedEmailData | null;
    if (latestObj && latestObj.id === id) {
      await this.kv.delete(latestKey);
    }

    return true;
  }
}
